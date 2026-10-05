# ClipPanel: Post-M7 Review and Enhancement Plan

Reviewed 2026-08-18, against commit `5f134ad` (M7). Written as the specification for the next
implementation round. The reviewer's job here was to find the places where the code and the promises
diverge, and it found some.

---

## Part 1: Review findings

### What holds up

The load-bearing decisions survive scrutiny: two-phase capture (secrets rejected from type
identifiers alone, payload never read), RAM-only unpinned history, GCM-authenticated encryption for
pins with a this-device-only keychain key, no dependencies, no networking, verification gates that
run as scripts rather than living as prose. The test suite genuinely tests behaviour (payload read
counting, no-file-on-disk assertions, tamper rejection) rather than implementation shape. The
"copy-only is a feature" framing made the app usable from M3 and keeps the Accessibility permission
honestly optional.

### Finding 1, bug: clear-on-lock destroys pinned entries while the UI promises the opposite

Severity: high. Data loss, and a broken promise in the settings UI.

`AppCoordinator`'s lock observer calls `store.removeEverything()`, which since M5 also wipes pinned
entries AND deletes the encrypted pin file. The Privacy tab text for the same toggle says "Pinned
entries are kept." M5 repurposed `removeEverything` into "forget everything including persistence"
and M6 wired the lock path to it without noticing the semantic change. Classic drift between two
milestones, and none of the 148 checks caught it because no test covers the lock path end to end.

Fix: the lock observer calls `clearUnpinned()`. Keep `removeEverything()` for a future explicit
"Forget Everything" action, where destroying pins is the point. Add a test: lock clearing with a
pinned entry present must leave the pin in the store and the file on disk.

### Finding 2, security gap: TOCTOU between the type check and the payload read

Severity: low likelihood, but it undermines the flagship guarantee, so it must go.

`poll()` reads type identifiers, decides, then calls `readSnapshot()`, which reads the live
pasteboard a second time. If a concealed copy (a password manager write) lands in the microseconds
between those two reads, the concealed check ran against the OLD types and the snapshot captures the
NEW secret payload. The "never even read" guarantee has a hole exactly one race wide.

Fix, two cheap layers: after `readSnapshot()`, (a) confirm `changeCount` is still the value the poll
started with, discard the snapshot if not, and (b) re-run the marker check against
`snapshot.allTypes`, which is derived from the bytes actually captured rather than from the earlier
peek. Add a `FakePasteboard` test that swaps contents between the type read and the payload read and
asserts the capture is discarded.

### Finding 3, behavioural gap: screenshots mostly cannot be captured

Severity: medium, silent feature failure.

`readSnapshot` reads and stores EVERY representation, and the size cap counts their sum. A clipboard
screenshot on a Retina display carries a multi-megabyte TIFF alongside the PNG, so the combined
payload routinely blows the 4 MB default and the copy is skipped as `tooLarge`. The user experiences
"screenshots never show up" with no explanation. Windows has the same cap but stores a single bitmap,
so parity reasoning does not rescue us here.

Fix: representation slimming before the size verdict. When a pasteboard item carries both PNG and
TIFF, drop the TIFF (PNG re-pastes fine everywhere that matters); apply the cap to what will actually
be stored. While in there: reading every exotic private type also forces promised-data resolution in
the source app, so restrict stored representations to a known-useful set (plain text, RTF, HTML, PNG,
TIFF-when-alone, file URLs) plus the markers, rather than hoovering all of them.

### Smaller observations, fold into whichever milestone touches the file

- `AppNameResolver` cache is unbounded. Irrelevant at 25 entries, sloppy at 100. Cap it.
- The monitor samples the frontmost app at poll time, up to 200 ms after the copy. A fast app switch
  can misattribute the source. Not fixable exactly (the pasteboard does not record the writer), worth
  a comment so nobody trusts `sourceBundleID` for security decisions beyond the exclusion heuristic
  it already serves.
- `PinStore.load` runs synchronously at launch on the main actor. Fine at kilobytes of pins; add a
  size note so nobody grows it into a beachball.

---

## Part 2: What "actually secure" means for a clipboard manager

The user's framing is the right one: passwords get copied and pasted constantly, and most of them
arrive with no `ConcealedType` marker, because they come from browsers, terminals, chat messages, and
text files rather than from well-behaved password managers. Today ClipPanel treats an unmarked
password as ordinary text: captured, previewed in clear, retained until eviction or quit.

Windows Clipboard History has exactly the same behaviour, so "exact Win+V parity" and "secure" part
company here, and we choose secure.

First, the honest boundary, restated so the plan cannot oversell itself. A clipboard manager's
function is to retain what the OS treats as ephemeral. "100% secure" therefore cannot mean "secrets
never at risk"; it can only mean "at every stage of an entry's life, exposure is as small as the
function allows, and every claim is enforced by code that runs." Five stages, five layers:

1. **Capture**: keep secrets out of history when they can be recognised.
2. **Lifetime**: bound how long anything that got in stays in.
3. **Exposure**: bound who and what can see an entry while it is held.
4. **Rest**: protect whatever persists.
5. **Honesty**: state what remains unprotected, in the product, not just in a document.

Layers 1 (markers, exclusions), 3 partially (screen-capture exclusion), 4 (GCM plus keychain), and 5
(README) exist today. The unmarked-password problem lives in layers 1 through 3, and the plan below
attacks it there.

### The Secret Guard design (the heart of the plan)

**Detection.** A capture-time classifier, pure function, fully unit-testable, scoring on:

- Shape: single token, no internal whitespace, length 8 to 128.
- Composition: three or more character classes, or Shannon entropy above roughly 3.5 bits/char.
- Known secret shapes, matched by prefix or structure: `AKIA...`, `ghp_`/`gho_`/`github_pat_`,
  `sk-`, `xox[bp]-`, `eyJ` (JWT), `-----BEGIN ... PRIVATE KEY-----`, and kin.
- Context boost: copied from a browser or a terminal.
- Exculpatory evidence: parses as a URL or email, or is ordinary prose, scores it back down.

False positives are inevitable (git SHAs, long hex, magnet links), which is why detection must never
silently drop anything.

**Verdict handling: guarded, not discarded.** A detected entry stays in history and stays pasteable,
because blocking it would just teach the user to disable the feature. Instead it is:

- **Masked** in the panel: `••••••••  Probably sensitive · Safari`, with reveal on demand (optionally
  behind Touch ID). This also fixes shoulder-surfing, which screen-capture exclusion never covered.
- **Short-lived**: auto-expires from history after a few minutes (default 5, configurable). This is
  the single most valuable change in the whole plan: the password that got pasted four times this
  morning is not still sitting in the panel this afternoon.
- **Unpinnable without confirmation**, so a secret cannot be quietly promoted onto disk. Confirming
  stores it encrypted like any pin, which is the user's right.
- **Post-paste hygiene**: optionally, 60 seconds after pasting a guarded entry, ClipPanel clears the
  system clipboard, exactly as password managers do after their own copies, and only if the
  clipboard still holds what we wrote (changeCount check), so a newer copy is never clobbered.

**Strict mode** for users who want it: detected secrets are not recorded at all, same as concealed.
Default off, because the false-positive cost lands on usefulness.

### Layer 2 and 3 additions independent of detection

- **Global TTL, opt-in**: expire any unpinned entry older than N hours. The agent runs for weeks;
  "history until quit" quietly became "history forever."
- **Panic wipe**: one hotkey and menu item that clears everything unpinned instantly.
- **Touch ID gate, opt-in**: require `LocalAuthentication` to open the panel after the machine was
  locked or after N minutes idle.

### Layer 4 hardening, honest about its marginality

- **In-RAM sealing**: encrypt stored payloads with a per-launch ephemeral key, decrypting only at
  paste time. Previews stay plaintext (the UI needs them; guarded entries' previews are masked
  strings anyway). Shrinks what a memory dump or swapped page yields from "every payload" to
  "previews plus the ephemeral key." Real but modest; macOS already encrypts swap.
- **Best-effort zeroization**: `resetBytes` on uniquely-held payload `Data` before removal. Swift
  copy-on-write means this is best-effort only, and the README must keep saying so.
- **Key custody upgrade**: wrap the pin key with a Secure Enclave key
  (`kSecAttrTokenIDSecureEnclave`), so the at-rest key is never extractable in plaintext even from a
  keychain dump. Requires stable code identity, so it lands together with Developer ID signing.

### What stays impossible, so nobody claims otherwise

Any process the user runs can read the system pasteboard the moment something is copied (macOS 26
prompts mitigate, ClipPanel adds nothing to that surface). An AX-trusted process can read the
panel's UI like any other window's. Swift memory cannot be deterministically scrubbed. A clipboard
manager cannot detect every secret, only the recognisable ones. These stay in the README, and the
onboarding keeps saying them.

---

## Part 3: The plan

Ordered so that every step leaves the app shippable, same as M1 through M7.

**P0, correctness and the review fixes (small, do first)**
1. Lock-clear preserves pins (`clearUnpinned`), plus the missing end-to-end test.
2. TOCTOU closure: changeCount re-verify plus post-read marker check, plus the race test.
3. Representation slimming: drop TIFF when PNG exists, restrict stored types to the known-useful
   set, apply the cap post-slimming. Screenshots become capturable. Tests for each rule.
4. Cap the `AppNameResolver` cache; comment the source-attribution caveat.

**P1, Secret Guard (the substance of this round)**
5. `SecretDetector`: pure scoring function plus verdict enum, exhaustively unit-tested against a
   corpus of true positives (passwords, tokens, keys) and true negatives (URLs, SHAs, prose, code).
6. Guarded lifecycle: masked card UI, reveal affordance, auto-expiry timer, pin confirmation,
   guarded badge. Expiry must survive the panel being open (entries vanish live).
7. Post-paste clipboard clearing for guarded entries, changeCount-checked, opt-in, default on for
   guarded items only.
8. Strict mode toggle in Privacy settings.

**P2, lifetime and exposure options**
9. Global TTL for unpinned entries, opt-in.
10. Panic wipe hotkey and menu item.
11. Touch ID gate for panel access after lock or idle, opt-in.

**P3, hardening and release**
12. In-RAM payload sealing with a per-launch key.
13. Best-effort zeroization on removal and eviction.
14. Secure Enclave key wrapping, landing alongside the user-run Developer ID signing step.
15. Re-run every gate, extend `verify-release.sh` for the new invariants, update README's guarantee
    and non-guarantee lists to match reality exactly.

**Explicitly rejected, with reasons**
- Auto-update (Sparkle or hand-rolled): requires networking, and "no networking code at all" is worth
  more than update convenience. Updates stay manual.
- Cloud sync: same verdict as the original design.
- Silent discard of detected secrets as the default: turns false positives into invisible data loss
  and teaches users to turn the protection off. Guarded-not-discarded is the default; strict mode is
  the opt-in.

**Deferred, unchanged from M7**: the credential-gated signing and notarization run, the manual paste
matrix, and the Win11 pinned-ordering comparison. All need the user.

---

## Part 4: Round 3 review and plan (2026-10-05), macOS 26 polish

Written against commit `c9e612e`. Two inputs: a screen recording of a hover glitch (the file did not
survive screencaptureui's staging folder, so the diagnosis below comes from the layout code, which is
unambiguous about it), and the question of what Liquid Glass and the rest of macOS 26 should change.

### Finding: text reflows on hover, and the panel height can jump with it

Severity: medium. It is the kind of jitter that makes a tool feel cheap, and it fires on every row
the pointer crosses.

Mechanism, in `ItemCardView`: the pin and delete buttons are inserted into the row's `HStack`
conditionally (`if showsActions { rowActions }`). On hover they appear, the text column loses their
width, and the preview re-wraps. With `lineLimit(4)` a re-wrap can add or drop a line, which changes
the row's height, which changes the list's height, which `PanelController` has already measured
WITHOUT the actions (the probe renders rows with no selection and no hover). So the rendered panel
can disagree with its own measurement by a line of text, and the user sees the list shift.

Fix, for the Opus round (P0 below): reserve the actions' space permanently. Render `rowActions`
always, with `.opacity(showsActions ? 1 : 0)` and `.allowsHitTesting(showsActions)`, so the text
column width is a constant and hover changes pixels but never layout. Add `.fixedSize(horizontal:
false, vertical: true)` on the preview text so wrapping is decided once. Disable implicit animation
on the hover toggle so the fade is deliberate, not a layout animation. Side effect worth having: the
measurement probe and the rendered row now agree by construction. Test it as an invariant, in a
main-actor unit test using `NSHostingView.fittingSize`: a row's height must be identical with and
without selection, and with and without the pin indicator reserved. The pin indicator has the same
conditional-insertion shape and should get the same treatment.

### What macOS 26 changes for this app

Three things, in descending order of how much they should move the plan.

**1. Spotlight now has clipboard history built in.** Tahoe's Spotlight keeps roughly the last eight
hours of copies, plain, no pins, no persistence, no secret handling. This is the new baseline every
Mac has for free, and the README's comparison section must say so plainly. It also sharpens what
ClipPanel is for: everything Spotlight's history is not. Pins that survive a restart (encrypted),
secrets detected and masked and expired, images and files with fidelity re-paste, search that
excludes guarded entries, zero networking, a panel at the caret. The pitch narrows and gets better.

**2. Liquid Glass.** The panel currently wears `.regularMaterial`, which on Tahoe reads as the
previous design language. The glass APIs are in the macOS 26 SDK, and a floating palette that sits
above content is exactly what Apple says glass is for. Adoption plan, with one spike first:

- Spike: the panel is a borderless NSPanel with a clear background. Verify that `glassEffect` on the
  SwiftUI root refracts the desktop and windows behind the panel, not just content within the same
  view hierarchy. If it does not, the fallback is to keep the material for the container and apply
  glass to controls only. This is a one-hour question and it decides the rest.
- Container: `.glassEffect(.regular, in: RoundedRectangle(...))` on the panel root inside a
  `GlassEffectContainer`, replacing the material and the hand-drawn stroke border. Keep
  `sharingType = .none`; glass changes nothing about screen-capture exclusion.
- Controls: `.buttonStyle(.glass)` for Clear All and the row actions, `.glassProminent` for the
  primary onboarding button.
- Selection: the current solid `.selection` fill becomes a glass pill that morphs between rows using
  `glassEffectID` in a shared namespace, so arrowing through the list slides one highlight rather
  than lighting rows up and down. This is the single most Tahoe-feeling change available.
- Icon: the generated PNG set now renders inside Tahoe's legacy-icon wrapper. Produce a layered
  Icon Composer asset so the icon participates in glass like the system's own.
- Accessibility: Reduce Transparency and Increase Contrast fall back automatically with glass, which
  is a reason to prefer the system API over any custom blur.

**3. On-device models, as an experiment only.** The Foundation Models framework runs entirely
on-device, which is the only kind of model this app could ever use without breaking guarantee 1.
It could help `SecretDetector` with the cases heuristics handle worst: a password that is also a
word, a token with no known prefix. Treat strictly as a research spike: non-deterministic output is
hostile to the detector's test corpus, availability depends on hardware and user settings, and the
fallback must remain the heuristics. If it ever ships, it ships as an opt-in boost that can only
ADD a guarded verdict, never remove one, so the worst case is a false positive rather than a leak.

### Smaller Tahoe items

- Menu bar is translucent by default on Tahoe; confirm the status item icon is a template image
  (SF Symbols are) so it adapts to light and dark wallpaper.
- Panel entrance uses `.utilityWindow` animation; glass has its own `glassEffectTransition`, use
  one or the other, not both.
- Settings already uses `.formStyle(.grouped)`, which is right for Tahoe; no change.

### Plan for the Opus round

- **P0** Hover reflow fix, with the height-invariance test. Also apply the reserved-space treatment
  to the pin indicator. Small, do first.
- **P1** Liquid Glass spike, then adoption in the order above if the spike passes: container,
  controls, morphing selection pill, Icon Composer icon.
- **P2** README comparison section updated for Spotlight's built-in history, repositioning the
  pitch as "everything Spotlight's clipboard is not."
- **P3** Foundation Models detector spike, behind a flag, additive-only, no shipping commitment.
- Standing, unchanged: Developer ID signing (`Scripts/package-release.sh`), which also resolves the
  login item, keychain, and Gatekeeper issues at the root.

---

## Note, 2026-10-06: Secret Guard is now opt-in

Parts 2 and 4 describe Secret Guard as always on. As of PLAN.md Item 1 it ships OFF by default, at
the user's request after living with it: the masking, five-minute expiry, and post-paste clipboard
clearing got in the way more than they helped. Nothing was deleted. One master switch,
`CaptureSettings.secretGuardEnabled`, gates detection at capture, and a single rule,
`CaptureSettings.isGuarded(_:)`, gates every downstream behaviour, so an entry flagged while the
guard was on is treated as ordinary while it is off and regains its protection when it is turned
back on. The concealed-marker rule (password managers' own flag) is unaffected and still cannot be
switched off. The security narrative above remains accurate for users who turn the guard on, and
the README's non-guarantees now say plainly what is held in the clear when it is off.

---

## Part 5: Review of the round 3 execution (2026-10-06, v0.2.0)

Reviewed against PLAN.md's acceptance criteria and its review checklist, with every gate re-run
independently rather than read from the execution log: 179 distinct test functions (206 cases
with parameter expansion) passing, 56 self test checks passing, logging audit and release
verification green on the tagged build, deployment target still 26.0. Checklist items: no raw
`isGuarded` read outside the rule (the one grep hit is the rule's own doc comment), no em dashes
in any tracked file, no attribution in any commit, guard described as optional in README,
onboarding, and this document.

**Verdict: approve.** The round did what the plan said, deviated only where it said why, and found
two real problems the plan had not anticipated (tests writing into the user's real preferences;
Xcode 27 breaking a test file). Three small corrections and one verification remain, below.

### What held up well

- Item 1 is exactly the design: one switch, one pure rule, every consumer routed through it, the
  stored flag preserved so re-enabling restores protection. The test proving the rule's full truth
  table and the one proving expiry follows the switch in both directions are the right tests.
- Item 2 was done test-first and the test failed on the old code with a measured 17 pt jump before
  passing on the new. That is how a visual bug should be fixed when the reviewer cannot see it.
- Item 5.4's acceptance (user preferences byte-identical after a full run) was actually executed,
  not asserted.
- The glass container decision (AppKit's `NSGlassEffectView` for an AppKit-owned panel, rather
  than SwiftUI glass inside it) is the right call, and the controller correctly stopped casting
  `contentView` to the hosting view, which would otherwise have silently frozen the panel.
  Verified by probe for this review: the glass view sizes a zero-framed content view to its
  bounds, so the panel content is laid out, not blank.
- The on-device model spike was run honestly and reported negative instead of being wedged in.

### Finding 1, small bug now reachable: "expires soon" is shown for entries that never expire

`ItemCardView.captionText` appends "expires soon" to every effectively guarded entry. Two cases
make that false. Pinned guarded entries never expire (`sweepExpired` skips pinned first), which
was already untrue before this round. And the new "Never" lifetime, added in this round, means no
guarded entry expires, yet the caption still promises it. Fix for the next round: the card receives
an `expires: Bool` alongside `isGuarded`, computed where the effective flag is computed as
`isGuarded && !item.isPinned && settings.guardedLifetime > 0`, and the caption keys off that. One
line in `HistoryRowsView`, one in the card, one test.

### Finding 2, nit: the menu count picker has no slot for off-list values

`recentEntriesInMenu` is clamped to 0...12 on load, but the picker offers only 0, 5, 8, 12. A
value such as 7 (hand-edited defaults, or a future default change) loads fine and the menu honours
it, while the picker renders empty. Either clamp to the offered set on load or add the remaining
values to the picker. Cosmetic; the behaviour is correct.

### Finding 3, documentation nit

The README's key table lists "Reveal or mask a guarded entry, ⌘R" without qualification. It only
applies while the guard is on. A parenthetical would do.

### Finding 4, the one that matters most: v0.2.0 shipped a look nobody has seen

The release notes say "the panel now sits in native macOS glass." Every mechanical check passes
and the probe confirms the content is laid out, but how glass reads over a real desktop, in light
and dark, with Reduce Transparency on, with the selection highlight sliding over it, has not been
seen by a human. Shipping it was defensible (the previous look was correct and this is a
container swap with the fallbacks owned by the system), and the plan's own "needs a human" list
said so, but a release claim is now ahead of its verification. Action for the user, today: open
the panel over something busy and over something dark. If the text contrast or the edge looks
wrong, that is a 0.2.1, and the fallback is a one-line switch of `glass.style` or a return to the
material. The same look is needed at the menu bar menu (labels, symbols, the ⌘1 to ⌘9 hints) and
at the hover fix with the pointer sweeping long entries.

### Finding 5, from the user's screenshot: the menu is too wide

A menu is exactly as wide as its widest row, and two of the rows are sentences: "Copy-only mode:
picking an entry copies it, then press command-V" and "Pinned entries will not survive a restart
this session." They predate this round, but the new entry list makes the menu something people look
at. Once entries appear, the 48-character labels will hold it wide as well (48 characters of menu
text plus icon and shortcut is roughly 400 pt; a comfortable menu is nearer 280).

Fix for the next round, two parts:

1. **Status rows become short, actionable items** instead of explanatory sentences. The explanation
   belongs in Settings, which is where each one should lead:
   - copy-only mode: `Button("Turn On Automatic Paste...")` opening Settings, Permissions;
   - pins not persisting: `Button("Pinned Entries Not Being Saved...")` opening Settings,
     Permissions;
   - hot key taken: `Button("Shortcut \(shortcut) Unavailable...")` opening Settings, General;
   - clipboard access denied: `Button("Clipboard Access Is Off...")` opening Settings, Permissions.
   `showSettings` needs a tab parameter for this. Every row stays under about 34 characters.
2. **`MenuEntryFormatter.maxCharacters` drops from 48 to 36.** The formatter tests that pin the cap
   need their numbers updated, not their logic.

Acceptance: with eight long text entries and copy-only mode on, the menu is no wider than the
Settings status rows need, and every informational row leads somewhere.

### Also visible in that screenshot: pins are not being saved this session

"Pinned entries will not survive a restart this session" means the installed app could not read
its keychain key at launch, almost certainly because the keychain prompt from the last relaunch was
denied or dismissed. Nothing is lost, and nothing is wrong with the code: quit ClipPanel, open it
again, and choose Always Allow when asked. The row disappears once the key is readable. Developer ID
signing is what stops this prompt recurring after every update.

### Verification left by design

The paste-from-menu target assumes a status item menu does not activate ClipPanel, which is how
`NSStatusItem` menus behave and how `MenuBarExtra` is built, but it has not been observed live.
Pick a menu entry with a document focused and confirm it lands there (in copy-only mode, that it
is on the clipboard). Developer ID signing stays the standing item; it resolves the keychain
prompt that every reinstall in this round produced.

### For the next Opus round

1. Finding 1 (caption truth), with its test.
2. Finding 2 and 3, if the files are open anyway.
3. Nothing else until the human verification in Finding 4 has happened; a 0.2.1 depends on it.
