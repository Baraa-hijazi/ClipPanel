# ClipPanel

Clipboard history for macOS, in the shape of Windows' Win+V. Press a shortcut, see the last things
you copied, pick one, and it goes back where you were typing.

A menu bar app: no Dock icon, no window until you ask for one. macOS 26 or later, Apple silicon or
Intel. No dependencies, and no network code of any kind.

## Using it

| Action | Key |
|---|---|
| Open the clipboard | `⌃⌘V` (configurable) |
| Move through entries | `↑` `↓` |
| Paste the selected entry | `Return` |
| Paste as plain text | `⌥Return` |
| Pin, so it survives Clear All and restarts | `⌘P` |
| Remove an entry | `Delete` |
| Close | `Escape` |

The shortcut is `⌃⌘V` rather than `⇧⌘V` because `⇧⌘V` is Paste and Match Style in most Mac apps, and
`⌥⌘V` is Move Item Here in Finder. Change it in Settings if you would rather have something else.

Everything is also reachable from the menu bar icon: open the panel, pause capture, Clear All, and
Settings.

## Permissions

Two, and the app tells you where it stands with both in Settings, Permissions.

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
   payload read count is zero on that path. This cannot be switched off.
5. **Excluded apps are never recorded**, also without reading their payloads. Password managers ship
   in the list by default; terminals do not, because people copy from them constantly, but you can
   add them.
6. **Your clipboard content never appears in logs.** `Scripts/audit-logging.sh` fails the build if a
   log statement references a payload, a preview, or item text. Logs carry counts, sizes, and
   outcomes only.
7. **The panel is excluded from screen recording and screenshots**, so your history does not turn up
   in a screen share.

**What it cannot do, stated plainly:**

- It cannot stop other apps from reading your clipboard. Any app you run can read the system
  clipboard; that is what a clipboard is. macOS 26's own clipboard prompts are your defence there,
  and ClipPanel adds nothing to that surface.
- It cannot recognise a secret that the app you copied it from never marked as one. The exclusion
  list and the pause switch are the tools for that.
- It cannot scrub its own memory. Swift strings and data cannot be reliably zeroed, so while an entry
  is in history it is in RAM. Lifetime is kept short (entries are dropped on delete, Clear All, and
  eviction), but no stronger claim is being made.
- It cannot protect an unlocked Mac from someone sitting at it. The optional clear-on-lock setting
  narrows that window.

Deliberately absent: cloud sync. That is a security decision, not a missing feature.

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

There is also a debug-only self test that drives the real app headlessly and checks 38 behaviours
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
