# ClipPanel: Round 3 Execution Plan

Written 2026-10-05 against commit `2b392f0`, for implementation in a fresh session. Fable reviews the
result afterwards against the acceptance criteria below, so every item states what "done" means in
checkable terms. Work the items in order; each leaves the app shippable.

Conventions carried over from every earlier round: no em dashes anywhere, no AI attribution in
commits, one commit per item with the reasoning in the message, `make test` and `make selftest` and
`Scripts/verify-release.sh` green before each commit, and DESIGN.md section 13 gets a log entry per
item recording what changed and why. Tests never touch the real clipboard or keychain.

## Execution status (2026-10-06, for the review)

Executed in one session; released as **v0.2.0** (tag `v0.2.0`, GitHub release with the unsigned zip,
marked latest). Gates on the tagged commit: 206 unit cases, 56 self test checks (repeated clean
runs), logging audit, release verification, all green. Per-item detail and every deviation is in
DESIGN.md section 13.

| Item | Status | Commit |
|---|---|---|
| 1. Secret Guard opt-in | Done as specified | `ee5c710` |
| 7. Recent entries in menu | Done; rows use SF Symbols, not thumbnails (reason in DESIGN) | `ef88ef8` |
| 2. Hover layout stability | Done; test written first, failed on old code (17 pt jumps), passes now | `35bc6e6` |
| 3. Liquid Glass | Done via `NSGlassEffectView`; no glass pill (glass on glass), sliding highlight instead; Icon Composer icon deferred | `106d48c` |
| 4. README repositioning | Done; claims about Spotlight limited to what is certain | `6656ff0` |
| 5.1 Push helper | Done: `~/.local/bin/clippanel-push.sh` | `c866a95` |
| 5.2 Name cache cap | Already done in an earlier round | none |
| 5.3 "Never" expiry | Done with Item 1 | `ee5c710` |
| 5.4 Test preference isolation | Done, verified byte-identical real prefs after a full run | `61076e6` |
| 6. On-device model spike | Done, negative: 4/8 accuracy, 250 ms median; not integrated | `c866a95` |

Unplanned fixes found along the way: `SecretDetectorTests` no longer compiled under Xcode 27
(type-checker budget on split-string fixtures), and the self test's visibility check flaked about
one run in six whenever the user clicked another app (now one announced retry).

**Still needs a human, because no headless run can see it:**
1. The glass panel over a busy desktop, light and dark, and with Reduce Transparency on.
2. The menu bar menu as rendered: labels, symbols, the ⌘1 to ⌘9 hints, "Show All...".
3. The hover fix by eye, with the pointer sweeping across long entries.
4. The Icon Composer icon (deferred; needs Apple's GUI tool).
5. Standing: Developer ID signing.

---

## Item 1: Secret Guard becomes opt-in (user request, do first)

### What the user asked for

The password protections are getting in the way in daily use: entries that look like passwords are
masked in the panel, expire after five minutes, and the clipboard is cleared a minute after pasting
one. The user wants those behaviours gone from their experience.

### Decision: a master switch, default off, rather than deleting the code

Reasoning, so the reviewer can check it rather than relitigate it:

- Deleting Secret Guard removes the product's main differentiator (REVIEW.md parts 2 and 4) and a
  large tested subsystem (`SecretDetector`, `GuardedLifecycleTests`, the search exclusion, the
  masked card, reveal, Touch ID gate, post-paste clearing) for a benefit a single Bool delivers.
- A default-off switch gives the user exactly the experience they asked for on this machine while
  leaving the protection one click away for anyone who wants it. Default off also means a fresh
  install behaves like a plain clipboard manager, which is the least surprising default.
- If the user, after living with it, still wants the code gone, the deletion scope is listed at the
  end of this item. It is a strictly larger change and should be a separate decision.

### Behaviour specification

One new setting, `secretGuardEnabled: Bool`, default `false`.

When OFF (the new default):

| Behaviour today | Behaviour when off |
|---|---|
| Text captures are assessed by `SecretDetector`; matches set `isGuarded` | Detector is not run at capture; `isGuarded` is never set on new entries |
| Guarded entries are masked (`••••••••`, shield) until revealed with ⌘R, optionally behind Touch ID | Nothing is masked; ⌘R and the reveal action are no-ops and the hint is hidden |
| Guarded entries expire after `guardedLifetime` unless pinned | No guarded expiry (the whole-history lifetime setting is unaffected) |
| Pasting a guarded entry schedules a clipboard clear after 60 s | No clipboard clearing |
| Pinning a guarded entry asks for confirmation | No confirmation |
| Guarded entries are excluded from search results | Nothing is excluded from search |
| Strict mode drops detected secrets at capture | Strict mode is inert |
| Card shows a guarded badge and "Probably sensitive" caption | No badge |

Entries that were guarded BEFORE the switch was turned off (in RAM, or pinned on disk with
`isGuarded: true`) are treated as ordinary entries while the switch is off, and resume guarded
behaviour if it is turned back on. Rule: every consumer reads an effective value,
`item.isGuarded && settings.secretGuardEnabled`, never the raw flag. The stored flag is kept so
turning the switch back on restores protection for existing entries.

When ON: identical to today, no behavioural change.

### Implementation steps

1. `Model/CaptureSettings.swift`: add `var secretGuardEnabled: Bool = false` next to the other guard
   settings, with a doc comment pointing at this plan item.
2. `Model/AppPreferences.swift`: key `secretGuardEnabled`, read in `loadCaptureSettings()` with the
   `object(forKey:) as? Bool ?? false` pattern, written in `save(_:)`.
3. `Core/ClipboardMonitor.swift` (around line 155): wrap the `SecretDetector.assess` block in
   `if settings.secretGuardEnabled`. Strict mode lives inside that block already, so it becomes inert
   for free.
4. Effective-guard helper: add to `HistoryStore` a method `isEffectivelyGuarded(_ item: ClipItem)
   -> Bool { item.isGuarded && settings.secretGuardEnabled }`, and route every consumer through it:
   - `Model/HistoryStore.swift` `sweepExpired(now:)` line 109: use the helper.
   - `UI/PanelController.swift`: the `toggleReveal` guard (line 175) and `togglePin` confirmation
     (`confirmPinningGuardedEntry`) use the helper.
   - `App/AppCoordinator.swift` line 114: the post-paste clear condition uses the helper.
   - `UI/ItemCardView.swift`: receives `isGuarded` as an effective value (compute in
     `HistoryRowsView` from the store, or pass the flag down from `PanelRootView`), so `isMasked`
     and the badge follow the switch.
   - `Model/SearchFilter.swift`: `filter(_:query:appName:)` gains a parameter
     `excludingGuarded: Bool` (or receives the effective flag per item); `PanelController.visibleItems`
     passes `store.settings.secretGuardEnabled`. The oracle-prevention comment stays, amended to say
     the exclusion applies only while the guard is on, because without masking there is no oracle.
5. `UI/SettingsView.swift`, Privacy tab, section "Entries that look like passwords": add
   `Toggle("Guard entries that look like passwords", isOn: secretGuard)` as the FIRST row, with a
   one-line caption explaining what it does. The existing picker and two toggles stay in the section
   but are `.disabled(!secretGuardEnabled)` so the hierarchy is visible rather than hidden.
6. `UI/OnboardingView.swift` line 63 and the README (lines 28, 83, 103 region): the bullet and
   prose change from "are masked and expire" to "can be masked and expired, off by default, in
   Settings, Privacy". Truthfulness over marketing: a protection that is off must not be described
   as active.
7. `REVIEW.md` part 2 and part 4 get a one-paragraph note that Secret Guard is now opt-in, with the
   date and the reason, so the security narrative in the repo stays honest.

### Tests

- `GuardedLifecycleTests`: fixtures turn the switch ON explicitly, so the 22 existing assertions keep
  testing the protection. Any test that constructs `CaptureSettings()` and expects guarding must set
  `secretGuardEnabled = true`.
- `SearchFilterTests`: the two guarded-exclusion tests set the switch on; add one test asserting that
  with the switch OFF a guarded entry IS matched by content.
- New `SecretGuardSwitchTests`:
  - monitor with switch off captures a password-shaped string with `isGuarded == false` and the
    detector path not taken (assert via the capture's flag; the detector is pure so no spy is needed);
  - monitor with switch off and `strictSecretMode = true` still records the entry (strict is inert);
  - `sweepExpired` with switch off does not expire a pre-existing guarded entry even past its
    lifetime, and DOES expire it once the switch is on;
  - the post-paste clear is not scheduled with the switch off (drive through the coordinator's
    existing `clearClipboardIfUnchangedForTesting` seam or assert the pasteboard was not rewritten);
  - preferences round trip, default false when unset.
- `Debug/SelfTest.swift`: the Secret Guard section (around line 267) and the search section (line
  305) set the switch on before exercising guarded behaviour, and one new check asserts that with the
  switch off a guarded-flagged entry is visible in a search by content.

### Acceptance

- Fresh install: no masking, no expiry of password-shaped entries, no clipboard clearing, search finds
  everything. Settings, Privacy shows the master toggle off with its three sub-settings disabled.
- Turning the toggle on restores today's behaviour exactly, including for entries captured earlier.
- All gates green; test count rises.

### If deletion is chosen later instead

Remove `SecretDetector.swift`, `GuardedLifecycleTests.swift`, `Authenticator.swift` and the Touch ID
gate, the guarded fields in `CaptureSettings` and `AppPreferences` (keep decoding `isGuarded` for old
pin files so they still open), the masked card branch, reveal command and ⌘R, the search exclusion,
the post-paste clear, the pin confirmation, the privacy section, the onboarding bullet, and the
README and REVIEW claims. Roughly 1,500 lines. Not recommended; recorded so the scope is known.

---

## Item 2: Hover must not change layout (REVIEW.md part 4 finding)

### Steps

1. `UI/ItemCardView.swift`: render `rowActions` unconditionally in the `HStack`; apply
   `.opacity(showsActions ? 1 : 0)` and `.allowsHitTesting(showsActions)`. Remove the `if`.
2. Same treatment for `pinIndicator`: always render the pin glyph's frame, opacity 0 when not pinned,
   so pinning and unpinning do not shift the text column either. Keep the `.frame(width:)` fixed.
3. Preview `Text` (line 102 region): add `.fixedSize(horizontal: false, vertical: true)` so the wrap
   is decided once from the constant column width.
4. The hover state change must not animate layout: set `isHovering` inside
   `withTransaction(Transaction(animation: nil))` or wrap the opacity change in an explicit
   `.animation(.easeOut(duration: 0.1), value: showsActions)` and nothing else.
5. `UI/PanelController.measuredListHeight()`: no change needed once rows are layout-stable, but add
   a comment that the probe's correctness depends on rows not changing size with selection or hover,
   and point at the test below.

### Tests

New `RowLayoutStabilityTests` (main actor, uses `NSHostingView.fittingSize`): for a text entry, an
image entry, and a files entry, the fitting height of `ItemCardView` is identical for
`isSelected` false and true, and identical for `isPinned` false and true. A 4-line text entry is
included so wrap sensitivity is covered.

### Acceptance

Hovering any row changes nothing but the action buttons' visibility; the panel never resizes on
hover. The invariance test passes for all three preview kinds.

---

## Item 3: Liquid Glass adoption (spike first)

### Spike (one hour, decides everything)

In a scratch branch: apply `.glassEffect(.regular, in: RoundedRectangle(cornerRadius:
PanelMetrics.cornerRadius, style: .continuous))` to `PanelRootView`'s root in place of
`.background(.regularMaterial)` and the stroke overlay. Launch, open the panel over a busy desktop
and over a window. Question: does the glass refract what is BEHIND the panel window? The panel is a
borderless `NSPanel` with a clear background, and glass must sample the backdrop through the window
for this to look right.

- If yes: proceed with adoption below.
- If no (glass only refracts within the view hierarchy): keep `.regularMaterial` for the container
  and apply glass to controls only (steps 3 and 4 below). Record the finding in DESIGN.md.

### Adoption steps (in order, each its own commit)

1. Container: wrap `PanelRootView` content in `GlassEffectContainer`, apply the container glass, drop
   the hand-drawn stroke border. `sharingType = .none` is untouched (verify with the existing self test
   check). Check Reduce Transparency in System Settings produces a sensible fallback (it does with
   system glass; confirm, do not assume).
2. Selection pill: replace the per-row `.selection` fill in `ItemCardView.background` with a single
   glass highlight that morphs between rows via `.glassEffectID(item.id, in: namespace)` inside the
   container, so arrowing slides one highlight instead of lighting rows up and down. Keyboard
   navigation and `scrollTo` must still work; test by eye and by the existing self test selection
   checks.
3. Controls: `.buttonStyle(.glass)` for Clear All and the row actions; `.glassProminent` for the
   primary onboarding button. Remove the `.borderless` style where replaced.
4. Entrance: choose either the panel's `.utilityWindow` animation or `glassEffectTransition`, not
   both. Prefer the glass transition if the container glass shipped.
5. Icon: build a layered Icon Composer asset (`.icon`) from the existing squircle and clipboard glyph
   and add it to the asset catalog so Tahoe renders it as a native glass icon rather than wrapping the
   PNGs. Keep the PNG set as the fallback for the Finder and older contexts.

### Acceptance

Panel visibly matches Tahoe system palettes; self test still reports screen-capture exclusion and
all selection checks pass; Reduce Transparency fallback confirmed; DESIGN.md records the spike
result. If the spike failed, acceptance is steps 3 and 4 only plus the recorded finding.

---

## Item 4: README repositioning for Tahoe's built-in clipboard history

macOS 26 Spotlight includes clipboard history (roughly eight hours, plain text and images, no pins,
no persistence across restart, no secret handling). Add a short section "Versus Spotlight's clipboard
history" near the top of the README that states this plainly and lists what ClipPanel adds: pins that
survive a restart (encrypted), optional secret guarding (now off by default, see Item 1), images and
files with fidelity re-paste, search, zero networking, a panel at the pointer, configurable shortcut.
No marketing adjectives; a comparison table is fine. Update the release notes template in
`Scripts/package-release.sh`'s header comment only if it mentions competitors (it does not today).

### Acceptance

README states the Spotlight baseline accurately and the differentiators without overclaiming.
Secret Guard is described as optional.

---

## Item 5: Housekeeping

1. DONE: `~/.local/bin/clippanel-push.sh`. The personal-account push helper (`askpass-personal.sh`) lived in the session scratchpad and was
   lost on every reboot. Move it to `~/.local/bin/clippanel-push.sh` (outside the repo; it encodes
   a username, not a secret, but it is machine-specific) and document the path and the reason in
   DESIGN.md section 13 next to the existing gh two-account note.
2. DONE in an earlier round. `AppNameResolver` cache cap (REVIEW.md part 1 small observation), 64 entries; it clears when full rather than evicting oldest-first, which is bounded and is what matters.
3. DONE in Item 1 (same control). The `Picker("Expire them after")` in Settings gains a "Never" option (`TimeInterval(0)`) so users
   who keep Secret Guard on can still opt out of expiry alone; `sweepExpired` already treats 0 as
   disabled.

4. DONE. **Tests must not touch the user's real preferences.** Found during Item 1: unit tests run
   inside the app as test host, so `UserDefaults.standard` IS the user's `com.baraahijazi.ClipPanel`
   domain, and every `AppPreferences.save` call in a test writes all keys into it (after Item 1 the
   user's domain contained a `secretGuardEnabled` key the user never set). Existing tests save and
   restore the keys they touch, so no setting was corrupted, but that discipline is one forgotten
   key away from overwriting a real preference. Fix: give `AppPreferences` an injectable
   `UserDefaults` (default `.standard`), and have tests use
   `UserDefaults(suiteName: "ClipPanelTests-\(UUID())")` removed in teardown. Acceptance: run the
   suite, then `defaults read com.baraahijazi.ClipPanel` shows no key the user did not set.

---

## Item 6: Foundation Models detector spike (optional, do not ship by default)

Only if time remains. Behind a compile-time flag, ask the on-device model whether a text is likely a
credential, and if it says yes AND the heuristics said no, set guarded. Additive only: the model may
never un-guard. Measure latency on this Mac; anything over 50 ms per capture disqualifies it from the
capture path and moves it to a background pass. Record findings in DESIGN.md. No tests depend on the
model's output.

---

## Item 7: Recent entries in the menu bar menu (user request)

### What the user asked for

Clicking the menu bar icon currently shows only commands (Open Clipboard, Pause, Clear All, Panic
Wipe, Settings, Quit). The user wants the latest copied entries listed there too, so the icon is a
second way to reach history without the shortcut.

### Design decisions

**Keep the menu; add entries to it.** The alternative (left-click opens the panel under the icon,
right-click shows the menu) needs an AppKit `NSStatusItem` to tell the clicks apart, which means
leaving `MenuBarExtra`. Not worth it: the user said "as well", the menu pattern is what Maccy and
Flycut established, and `MenuBarExtra`'s `.menu` style already rebuilds its content on every open
from the `@Observable` store. One surface gains entries; nothing else moves.

**Selecting an entry pastes it, same path as the panel.** A status item menu does not activate the
owning app, so the frontmost app at click time is still the one the user was working in. Record it
when the menu content appears, then route through the existing `PasteInjector.paste(_:plainTextOnly:
into:)`. Copy-only mode and the Accessibility fallback behave exactly as in the panel.

**Guarded entries obey the Secret Guard switch (Item 1).** With the guard on, a guarded entry
appears masked (`•••••••• (sensitive)`) and selecting it still pastes; with the guard off it is an
ordinary row. One honest limitation to record in DESIGN.md: an `NSMenu` cannot be excluded from
screen capture the way the panel is (`sharingType` is a window property), so entry previews in the
menu can appear in a screenshot taken while the menu is open. Menus are transient and user-opened,
so this is an accepted trade, but it is the reason the menu shows one truncated line per entry and
never a full payload, and the reason the feature has an off switch.

### Specification

- Entries appear at the TOP of the menu, above "Open Clipboard", newest first, pinned entries first
  within the group exactly as the panel orders them. Count comes from a new setting
  `recentEntriesInMenu: Int`, default 8, choices 0 (off), 5, 8, 12 in Settings, General.
- Each entry is a `Button` whose label is `Label { Text(oneLine) } icon: { ... }`:
  - text: first line of the preview, whitespace-condensed, truncated to 48 characters with an
    ellipsis;
  - image: the stored thumbnail as the icon, text "Image, W x H";
  - files: `doc` symbol icon, the first file name, plus "and N more" when several;
  - pinned: `pin.fill` as the icon (text entries) or appended to the text (images, files);
  - guarded while the guard is on: `shield.fill` icon and the masked text.
- The first nine entries get `.keyboardShortcut` ⌘1 through ⌘9. These are menu-only shortcuts, so
  they work while the menu is open and never register anything global.
- Below the entries: a `Divider`, then "Show All..." which calls `showPanel()`, then the existing
  menu. "Open Clipboard" is renamed to nothing: "Show All..." replaces it and keeps the ⌃⌘V
  shortcut display, since two items that open the same panel would be clutter.
- Empty history: a single disabled `Text("No copies yet")` in place of the entries.
- Capture paused, access denied, hot key unavailable, copy-only mode: the existing informational
  rows stay where they are.

### Implementation steps

1. `Model/CaptureSettings.swift` and `Model/AppPreferences.swift`: `recentEntriesInMenu` with the
   usual clamped load (0...12) and save.
2. `App/AppCoordinator.swift`: `func pasteFromMenu(_ item: ClipItem)` that records
   `NSWorkspace.shared.frontmostApplication` (skipping ourselves) and awaits
   `paster.paste(item, plainTextOnly: false, into: target)`; beep only on `.failed`. Expose
   `recentEntriesForMenu: [ClipItem]` as `store.items.prefix(settings.recentEntriesInMenu)`.
3. `App/MenuBarContent.swift`: a new `recentEntries` section built per the specification, a
   `MenuEntryLabel` helper that produces the one-line label and icon (pure formatting, put the
   string logic in `Model/MenuEntryFormatter.swift` so it is unit-testable without SwiftUI).
4. `UI/SettingsView.swift`, General tab: `Picker("Show in the menu bar menu", ...)` with the four
   choices, placed after the history size picker.
5. DESIGN.md section 13: the screen-capture limitation and the design decisions above.

### Tests

- `MenuEntryFormatterTests`: text truncation at 48 with ellipsis, first line only, whitespace
  condensing, image and file labels, pinned marker, masked label when guarded and the guard is on,
  plain label when the guard is off.
- Preferences round trip and clamping for `recentEntriesInMenu`.
- Self test: with the switch at 8 and 12 entries recorded, `recentEntriesForMenu.count == 8`; with
  the switch at 0, it is empty.
- Paste path: the existing `PasteInjectorTests` already cover the injector; add one coordinator-level
  test that `pasteFromMenu` records a target and reaches the injector (use the fake keystroke sender).

### Acceptance

Clicking the icon shows the latest entries at the top with ⌘1 through ⌘9, picking one pastes into
the app that was frontmost (or copies, in copy-only mode), "Show All..." opens the panel, the count
is adjustable and 0 hides the section, and a guarded entry is masked only while Secret Guard is on.

---

## Standing item: Developer ID signing (user)

`Scripts/package-release.sh` with `DEVELOPER_ID` and `NOTARY_PROFILE` set. Resolves the login-item
breakage after updates, the keychain re-prompts, and the Gatekeeper friction on downloads, all of
which trace to the ad-hoc signature's unstable identity.

---

## Commit plan and order

1. Item 1 (Secret Guard opt-in) with tests and doc updates.
2. Item 7 (recent entries in the menu bar menu) with the formatter tests.
3. Item 2 (hover layout stability) with the invariance test.
4. Item 5.2 and 5.3 (small, ride along).
5. Item 3 spike result recorded; then adoption commits 1 through 5 as they land.
6. Item 4 README.
7. Item 5.1 helper relocation (not a code commit; DESIGN.md note).
8. Item 6 if attempted.

Tag `v0.2.0` after Items 1, 7, 2, 3, and 4; rebuild the release zip and attach it with notes that lead
with "Secret Guard is now opt-in" so existing users are not surprised.

## Review checklist for Fable afterwards

- Every acceptance line above, checked against the running app, not the diff.
- Grep for raw `item.isGuarded` reads outside the effective-guard helper; there should be none in
  consumers, the menu formatter included.
- Menu shows recent entries, ⌘1 through ⌘9 work while it is open, and the count setting is honoured
  including 0.
- README, onboarding, and REVIEW describe Secret Guard as optional and off by default.
- `make test`, `make selftest`, `Scripts/verify-release.sh` green on the tagged commit.
- No em dashes, no attribution lines, in any file or commit.
