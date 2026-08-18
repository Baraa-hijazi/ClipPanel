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
