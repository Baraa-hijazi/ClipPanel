# ClipPanel

Clipboard history for macOS, in the shape of Windows' Win+V. Press a shortcut, see the last things
you copied, pick one, and it goes back where you were typing.

A menu bar app: no Dock icon, no window until you ask for one. macOS 26 or later, Apple silicon or
Intel. No dependencies, and no network code of any kind.

## Using it

| Action | Key |
|---|---|
| Open the clipboard | `⌃⌘V` (configurable) |
| Search | just start typing; `⌫` edits, `esc` clears |
| Move through entries | `↑` `↓` |
| Paste the selected entry | `Return` |
| Paste as plain text | `⌥Return` |
| Pin, so it survives Clear All and restarts | `⌘P` |
| Reveal or mask a guarded entry | `⌘R` |
| Remove an entry | `Delete` |
| Close | `Escape` |

The shortcut is `⌃⌘V` rather than `⇧⌘V` because `⇧⌘V` is Paste and Match Style in most Mac apps, and
`⌥⌘V` is Move Item Here in Finder. Change it in Settings if you would rather have something else.

Everything is also reachable from the menu bar icon: open the panel, pause capture, Clear All,
Panic Wipe, and Settings. Panic Wipe (also `⌃⌥⌘⌫`, disableable) clears every unpinned entry
instantly. Optional protections in Settings, Privacy: expire the whole history on a schedule,
clear it when the screen locks, and require Touch ID or your password the first time the panel
opens after a lock.

## Permissions

Two, and the app tells you where it stands with both in Settings, Permissions.

### Images and screenshots

Images and screenshots are captured like anything else, with their own larger size limit (64 MB by
default) because a Retina screenshot dwarfs any sensible text limit. Redundant representations are
discarded first: a screenshot arrives as both PNG and TIFF, and only the PNG is kept, which is
typically a fiftieth of the size and re-pastes everywhere the TIFF would.

Two limits remain, both adjustable in Settings, General:

- **Per image**, 64 MB by default. Bigger than that and the copy is not recorded; your clipboard
  still holds it, so pasting normally works.
- **Total history**, 256 MB by default. Past that, the oldest unpinned entries are dropped first.
  The entry you just copied is never the one evicted, so a large screenshot cannot vanish the
  instant it arrives.

**Clipboard access (required).** macOS 26 asks before an app may read the clipboard. Choose Always
Allow, or there is nothing for ClipPanel to show you. If you refuse, the panel says so rather than
sitting there looking broken.

**Accessibility (optional).** With it, picking an entry pastes it into whatever you were typing in.
Without it, picking an entry puts it on your clipboard and you press `⌘V` yourself. Nothing else
changes. The menu bar menu says which mode you are in.

## What it does with your data

The honest version, because a clipboard manager is by nature a pile of sensitive data.

**What it guarantees, and how each one is checked:**

1. **Nothing leaves your Mac.** There is no networking code. `Scripts/verify-release.sh` checks that
   no networking framework is linked and no networking symbol is imported; the release process also
   observes a running build with `nettop` to confirm zero connections.
2. **Unpinned history never touches disk.** It lives in memory and dies with the process, which is
   why quitting or restarting clears it. A test saves a set of unpinned entries and asserts that no
   file exists afterwards.
3. **Pinned entries are encrypted.** AES-256-GCM, with the key in your login keychain marked
   this-device-only, so it is never synced to iCloud or carried to another machine in a backup. The
   file lives at `~/Library/Application Support/ClipPanel/pins.enc`, owner-readable only. A test
   asserts the written bytes do not contain the plaintext, and that a tampered file refuses to open
   rather than decrypting into rubbish.
4. **Copies your password manager marks as secret are never recorded, and never even read.** The
   decision is made from type identifiers alone, before any payload is fetched. Tests assert the
   payload read count is zero on that path. This cannot be switched off. Two independent guards
   also cover the race where the clipboard changes mid-read.
5. **Copies that merely LOOK like passwords are guarded.** Most real passwords arrive unmarked,
   from browsers, terminals, and chat. A detector recognises password shapes, access tokens (AWS,
   GitHub, Slack, and kin), JWTs, and private key blocks. Flagged entries still paste normally,
   but they are masked in the panel until revealed (`⌘R`), expire after five minutes unless
   pinned, need confirmation to pin, and a minute after you paste one the clipboard is cleared if
   it still holds it, the way password managers clean up after themselves. Strict mode (off by
   default) refuses to record them at all.
6. **Excluded apps are never recorded**, also without reading their payloads. Password managers ship
   in the list by default; terminals do not, because people copy from them constantly, but you can
   add them.
7. **Your clipboard content never appears in logs.** `Scripts/audit-logging.sh` fails the build if a
   log statement references a payload, a preview, or item text. Logs carry counts, sizes, and
   outcomes only.
8. **The panel is excluded from screen recording and screenshots**, so your history does not turn up
   in a screen share. Masked entries also cover the case screen exclusion cannot: a person looking
   at your screen.

**What it cannot do, stated plainly:**

- It cannot stop other apps from reading your clipboard. Any app you run can read the system
  clipboard; that is what a clipboard is. macOS 26's own clipboard prompts are your defence there,
  and ClipPanel adds nothing to that surface.
- The secret detector is a heuristic. It catches recognisable shapes, not every secret, and it
  sometimes guards something harmless, which costs a masked preview and a shorter life, never data
  loss. The exclusion list, strict mode, and the pause switch are the stronger tools.
- It cannot scrub its own memory. Swift strings and data cannot be reliably zeroed, so while an entry
  is in history it is in RAM. Lifetime is kept short (entries are dropped on delete, Clear All, and
  eviction), but no stronger claim is being made.
- It cannot protect an unlocked Mac from someone sitting at it. The optional clear-on-lock setting
  narrows that window.

Deliberately absent: cloud sync. That is a security decision, not a missing feature.

## Installing

Two ways, pick one.

**Build it yourself (recommended until releases are notarized).** Requires Xcode 26 or later.
Because the app is built on your own machine it carries no quarantine flag, so it launches without
any Gatekeeper ceremony, and you can read every line of what you just built.

```bash
git clone https://github.com/Baraa-hijazi/ClipPanel.git
cd ClipPanel
make install
```

**Download a release.** Grab the zip from the Releases page, unzip, and move `ClipPanel.app` to
Applications. Until releases are signed with a Developer ID, macOS will refuse the first launch
with "Apple could not verify". That is Gatekeeper doing its job on an unsigned download. If you
decide to trust it (the source is right here to check), the path is: attempt to open the app once,
then System Settings, Privacy and Security, scroll to the ClipPanel notice, Open Anyway, and
confirm. You only do this once. Notarized releases, which skip all of that, are planned.

First launch shows a short onboarding that walks through the two permissions (clipboard access,
and optionally Accessibility for automatic pasting).

## Building

Requires Xcode 26 or later.

```bash
xcodebuild -project ClipPanel.xcodeproj -scheme ClipPanel -configuration Debug build
```

Tests (110 cases, Swift Testing):

```bash
xcodebuild -project ClipPanel.xcodeproj -scheme ClipPanel -destination 'platform=macOS' test
```

The tests never touch the real clipboard or the real keychain: they drive fakes and injected keys, so
running them cannot disturb what you had copied or raise a permission prompt.

There is also a debug-only self test that drives the real app headlessly and checks 43 behaviours
(panel focus, sizing, keyboard model, permission consistency). It is compiled out of Release builds:

```bash
CLIPPANEL_SELFTEST=1 ./ClipPanel.app/Contents/MacOS/ClipPanel
```

Verification scripts:

```bash
Scripts/audit-logging.sh
Scripts/verify-release.sh /path/to/ClipPanel.app
```

## Releasing

`Scripts/package-release.sh` builds, signs, notarizes, staples, and zips. It needs an Apple Developer
ID certificate in your keychain and a `notarytool` keychain profile, both of which are yours to set
up; the script never handles credentials itself. Run it with no arguments for the exact instructions.

## Design

`DESIGN.md` is the full design document: threat model, architecture, the macOS-specific constraints
that shaped it, and an implementation log recording what changed during the build and why.
