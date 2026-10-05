//
//  SelfTest.swift
//  ClipPanel
//
//  Debug-only smoke test for the M1 acceptance criteria, compiled out of Release builds.
//  Turns "does the panel behave" into something checkable from a terminal instead of
//  something a human has to eyeball:
//
//      CLIPPANEL_SELFTEST=1 ./ClipPanel.app/Contents/MacOS/ClipPanel
//
//  Exits 0 when every check passes, 1 otherwise.
//

#if DEBUG

import AppKit

enum SelfTest {
    static func runIfRequested(coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.environment["CLIPPANEL_SELFTEST"] == "1" else { return }

        Task { @MainActor in
            await run(coordinator: coordinator)
        }
    }

    private static func run(coordinator: AppCoordinator) async {
        var failures: [String] = []

        // The panel takes keyboard focus while it is open (as designed), and its search box is a real
        // text field, so anything the person at the Mac types during a run becomes a search query.
        // That filters the list and changes what Escape does, which made keyboard checks fail for
        // reasons unrelated to the code. Every failure now reports a stray query when there is one.
        var strayQueries: Set<String> = []

        func check(_ label: String, _ passed: Bool, detail: String = "") {
            if !passed, !coordinator.panelQuery.isEmpty {
                strayQueries.insert(coordinator.panelQuery)
            }
            let mark = passed ? "PASS" : "FAIL"
            let suffix = detail.isEmpty ? "" : "  (\(detail))"
            print("\(mark)  \(label)\(suffix)")
            if !passed { failures.append(label) }
        }

        print("ClipPanel self test, M1 through M6 plus Secret Guard")
        print("----------------------")

        // Let the app finish launching so activation policy and the menu bar item settle.
        try? await Task.sleep(for: .milliseconds(600))

        check("global hot key \(coordinator.panelShortcut.description) registered",
              !coordinator.hotKeyUnavailable)
        check("runs as an accessory app, no Dock icon",
              NSApp.activationPolicy() == .accessory,
              detail: "policy \(NSApp.activationPolicy().rawValue)")
        check("panel starts hidden", !coordinator.panelIsVisible)

        // Measured as a delta, not an absolute: launching a binary straight from a terminal
        // can leave the process active before the panel is ever involved, so the question
        // that matters is whether SHOWING the panel changes activation.
        let wasActiveBeforeShow = NSApp.isActive
        let frontmostBeforeShow = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        coordinator.showPanel()
        try? await Task.sleep(for: .milliseconds(300))

        // One retry, and only for losing the panel: it hides the moment it loses key status (the
        // click-outside-to-dismiss behaviour), so a person clicking another app during this window
        // legitimately closes it. Measured at about one run in six while the user was working in
        // another app, on untouched code as well. A real defect fails both attempts; a stray click
        // does not repeat on cue. The retry is announced, never silent.
        var shown = coordinator.panelDiagnostics
        if !shown.isVisible || !shown.isKeyWindow {
            print("INFO  panel lost visibility or key focus within 300 ms (likely live user input); retrying once")
            coordinator.showPanel()
            try? await Task.sleep(for: .milliseconds(300))
            shown = coordinator.panelDiagnostics
        }
        check("panel is on screen after show", shown.isVisible)
        check("panel can take key focus", shown.canBecomeKey)
        check("panel actually holds key focus", shown.isKeyWindow)
        // NSApp.isActive deliberately NOT asserted here: makeKey() on a non-activating panel
        // sets it while leaving the system frontmost app alone (measured, see PanelController).
        // The criterion that matters is which app the system still considers frontmost.
        print("INFO  NSApp.isActive \(wasActiveBeforeShow) before show, \(NSApp.isActive) after "
              + "(expected: taking key focus marks us active, frontmost app is unchanged)")
        check("another app is still frontmost, not ClipPanel",
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier,
              detail: "frontmost \(frontmostBeforeShow ?? "none") before, "
                      + "\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") after")
        check("panel excluded from screen capture", shown.excludedFromScreenCapture)
        check("panel content sits in Liquid Glass", shown.contentIsGlass)
        check("panel sits fully inside a screen", shown.fitsOnAScreen,
              detail: "frame \(NSStringFromRect(shown.frame))")
        check("recorded the app to paste back into",
              shown.restoreTargetBundleID != nil,
              detail: shown.restoreTargetBundleID ?? "none")

        coordinator.hidePanel()
        try? await Task.sleep(for: .milliseconds(200))
        let hidden = coordinator.panelDiagnostics
        check("panel hides again", !coordinator.panelIsVisible)
        check("panel releases key focus when hidden", !hidden.isKeyWindow)
        // Asserts what actually matters, rather than that the same app is still frontmost: a
        // notification or the person at the keyboard can switch apps mid-run, and an earlier version
        // of this check failed for exactly that reason. ClipPanel never becoming frontmost is the
        // real property, and it does not depend on the desktop holding still.
        let frontmostAtEnd = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        check("ClipPanel never became the frontmost app",
              frontmostAtEnd != Bundle.main.bundleIdentifier,
              detail: frontmostAtEnd ?? "none")
        if frontmostAtEnd != frontmostBeforeShow {
            print("INFO  the frontmost app changed during the run "
                  + "(\(frontmostBeforeShow ?? "none") to \(frontmostAtEnd ?? "none")), "
                  + "which the checks no longer depend on")
        }

        // MARK: M2, capture pipeline

        print("")
        print("M2 capture pipeline")
        check("clipboard monitor is polling", coordinator.monitorIsRunning)
        print("INFO  pasteboard access: \(coordinator.pasteboardAccess.rawValue)")
        check("history starts empty", coordinator.store.isEmpty)

        // Synthetic entries rather than the real clipboard: the self test must not disturb
        // whatever the user had copied, nor read it.
        let syntheticCount = 12
        for index in 0..<syntheticCount {
            let snapshot = PasteboardSnapshot(items: [[
                ClipItem.Representation(
                    type: PasteboardTypes.plainText,
                    data: Data("synthetic entry \(index)".utf8)
                ),
            ]])
            if let item = ItemFactory.make(from: snapshot, sourceBundleID: "com.apple.TextEdit") {
                coordinator.store.record(item)
            }
        }
        check("store recorded every synthetic entry",
              coordinator.store.items.count == syntheticCount,
              detail: "\(coordinator.store.items.count) of \(syntheticCount)")

        coordinator.showPanel()
        try? await Task.sleep(for: .milliseconds(300))
        let populated = coordinator.panelDiagnostics
        let emptyHeight = shown.frame.height

        // Deliberately a real threshold rather than "taller than empty": a ScrollView that
        // collapses to one row still grows by a point or two, and that bug shipped past a
        // greater-than check once already.
        let minimumExpectedHeight: CGFloat = 250
        check("panel grew to fit the list",
              populated.frame.height >= minimumExpectedHeight,
              detail: "\(Int(emptyHeight)) pt empty, \(Int(populated.frame.height)) pt with "
                      + "\(syntheticCount) entries, expected at least \(Int(minimumExpectedHeight))")
        check("panel height respects the cap",
              populated.frame.height <= PanelMetrics.maxHeight,
              detail: "cap \(Int(PanelMetrics.maxHeight)) pt")
        check("populated panel still fits on screen", populated.fitsOnAScreen)

        // MARK: M3, panel interaction

        print("")
        print("M3 panel interaction")

        check("selection starts on the newest entry",
              coordinator.panelSelectedID == coordinator.store.items.first?.id)

        let secondEntry = coordinator.store.items[1].id
        coordinator.sendPanelKeyCommand(.moveDown)
        check("down arrow moves to the next entry", coordinator.panelSelectedID == secondEntry)

        coordinator.sendPanelKeyCommand(.moveUp)
        coordinator.sendPanelKeyCommand(.moveUp)
        check("up arrow stops at the top rather than wrapping",
              coordinator.panelSelectedID == coordinator.store.items.first?.id)

        // Pin something further down the list, so "moved to the top" actually means something.
        for _ in 0..<3 { coordinator.sendPanelKeyCommand(.moveDown) }
        let toPin = coordinator.panelSelectedID
        coordinator.sendPanelKeyCommand(.togglePin)
        check("command-P pins the selected entry",
              coordinator.store.items.first?.isPinned == true)
        check("a pinned entry moves to the top of the list",
              coordinator.store.items.first?.id == toPin)
        check("selection follows the entry it was on",
              coordinator.panelSelectedID == toPin)

        coordinator.sendPanelKeyCommand(.moveDown)
        let toDelete = coordinator.panelSelectedID
        let countBeforeDelete = coordinator.store.items.count
        coordinator.sendPanelKeyCommand(.delete)
        check("Delete removes the selected entry",
              coordinator.store.items.count == countBeforeDelete - 1,
              detail: "\(countBeforeDelete) then \(coordinator.store.items.count)")
        check("selection lands on a neighbour after deleting",
              coordinator.panelSelectedID != nil && coordinator.panelSelectedID != toDelete)

        coordinator.clearHistory()
        check("Clear All keeps the pinned entry and drops the rest",
              coordinator.store.items.count == 1 && coordinator.store.items.first?.isPinned == true,
              detail: "\(coordinator.store.items.count) left")

        // Checked here rather than after a single delete: 12 entries overflow the list cap and so
        // do 11, so the panel is supposed to stay at the capped height until the content actually
        // fits inside it again.
        try? await Task.sleep(for: .milliseconds(150))
        let shrunk = coordinator.panelDiagnostics
        check("panel shrank once the content fitted again",
              shrunk.frame.height < populated.frame.height,
              detail: "\(Int(populated.frame.height)) pt with 12 entries, \(Int(shrunk.frame.height)) pt with 1")
        check("shrunken panel still sits on screen", shrunk.fitsOnAScreen)

        coordinator.sendPanelKeyCommand(.cancel)
        try? await Task.sleep(for: .milliseconds(150))
        check("Escape closes the panel", !coordinator.panelIsVisible)

        // MARK: M4, paste path and permissions

        print("")
        print("M4 paste path and permissions")
        print("INFO  Accessibility granted: \(AccessibilityPermission.isTrusted) "
              + "(false simply means copy-only mode)")
        check("permission state agrees with the system",
              coordinator.canPasteAutomatically == AccessibilityPermission.isTrusted)
        check("permissions model mirrors pasteboard access",
              coordinator.permissions.pasteboardAccess == coordinator.pasteboardAccess,
              detail: coordinator.pasteboardAccess.rawValue)
        // The paste path itself is covered by unit tests with fakes: exercising it here would write
        // to the real pasteboard and clobber whatever the user had copied.
        print("INFO  paste flow itself is covered by PasteInjectorTests, not here, to avoid "
              + "touching the real clipboard")

        // MARK: M5, encrypted pin persistence

        print("")
        print("M5 encrypted pin persistence")
        // Suppression matters: without it this headless run could stop on a keychain prompt, because
        // an ad-hoc signature changes identity on every rebuild.
        check("keychain and pin file are left alone during the self test",
              coordinator.pinsPersist == false)
        if let location = try? PinStore.defaultFileURL() {
            print("INFO  pins would live at \(location.path)")
        }
        print("INFO  crypto and pin store behaviour is covered by CryptoBoxTests and PinStoreTests")

        // MARK: M6, settings and polish

        print("")
        print("M6 settings and polish")
        check("app icon is compiled into the bundle",
              Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil)
        check("settings loaded from preferences are within the documented bounds",
              AppPreferences.historyLimitRange.contains(coordinator.captureSettings.historyLimit)
                  && coordinator.captureSettings.maxItemBytes >= 1024 * 1024,
              detail: "\(coordinator.captureSettings.historyLimit) entries, "
                      + "\(coordinator.captureSettings.maxItemBytes / (1024 * 1024)) MB cap")
        check("a shortcut is registered and rendered",
              !coordinator.panelShortcut.description.isEmpty,
              detail: coordinator.panelShortcut.description)
        print("INFO  launch at login: \(LoginItem.isEnabled ? "on" : "off")"
              + (LoginItem.needsApproval ? " (awaiting approval in System Settings)" : ""))
        print("INFO  clear on screen lock: \(AppPreferences.clearOnScreenLock ? "on" : "off")")
        check("excluded apps list is populated with the shipped defaults",
              !coordinator.captureSettings.excludedBundleIDs.isEmpty,
              detail: "\(coordinator.captureSettings.excludedBundleIDs.count) apps")

        // MARK: Secret Guard

        print("")
        print("Secret Guard")
        // The guard is off by default (PLAN.md Item 1). Turned on here by mutating the store
        // directly, never through captureSettings, which would persist to the user's real
        // preferences. Restored at the end of the Search section.
        let guardWasEnabled = coordinator.store.settings.secretGuardEnabled
        print("INFO  Secret Guard is \(guardWasEnabled ? "on" : "off") in this user's settings")
        coordinator.store.settings.secretGuardEnabled = true
        check("detector flags a generated password",
              SecretDetector.assess(text: "9k#mQ2$vLx8@pR5z", sourceBundleID: nil)
                  == .probablySecret(.passwordShape))
        check("detector flags a GitHub token",
              SecretDetector.assess(text: "ghp_" + "16C7e42F292c6912E7710c838347Ae178B4a", sourceBundleID: nil)
                  == .probablySecret(.knownTokenShape))
        check("detector passes ordinary prose",
              SecretDetector.assess(text: "meeting notes for tuesday", sourceBundleID: "com.apple.Terminal")
                  == .ordinary)

        let guardedEntry = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.plainText, data: Data("P@ssw0rd!2024".utf8)),
        ]])
        if var made = ItemFactory.make(from: guardedEntry, sourceBundleID: "com.apple.Safari") {
            made.isGuarded = true
            coordinator.store.record(made)
        }
        check("guarded entry lands in history",
              coordinator.store.items.contains { $0.isGuarded })

        // Expire it with a clock jump rather than a wait.
        let removed = coordinator.store.sweepExpired(
            now: Date().addingTimeInterval(coordinator.store.settings.guardedLifetime + 1)
        )
        check("guarded entry expires on schedule", removed >= 1,
              detail: "\(removed) removed")
        check("expiry left the pinned entry alone",
              coordinator.store.items.contains { $0.isPinned })
        _ = guardedEntry
        coordinator.store.removeEverything()

        // MARK: Search

        print("")
        print("Search")
        coordinator.store.removeEverything()
        for (index, text) in ["alpha one", "beta two", "alpha three"].enumerated() {
            let snapshot = PasteboardSnapshot(items: [[
                ClipItem.Representation(type: PasteboardTypes.plainText, data: Data(text.utf8)),
            ]])
            if let entry = ItemFactory.make(from: snapshot, sourceBundleID: "com.apple.TextEdit") {
                var entry = entry
                entry.createdAt = Date().addingTimeInterval(Double(index))
                coordinator.store.record(entry)
            }
        }
        var searchGuardedEntry = ItemFactory.make(
            from: PasteboardSnapshot(items: [[
                ClipItem.Representation(type: PasteboardTypes.plainText, data: Data("alpha-secret-9".utf8)),
            ]]),
            sourceBundleID: "com.apple.Safari"
        )!
        searchGuardedEntry.isGuarded = true
        coordinator.store.record(searchGuardedEntry)

        coordinator.showPanel()
        try? await Task.sleep(for: .milliseconds(200))
        check("panel opens with no query and everything visible",
              coordinator.panelQuery.isEmpty && coordinator.panelVisibleCount == 4,
              detail: "\(coordinator.panelVisibleCount) visible")

        for character in "alpha" {
            coordinator.sendPanelKeyCommand(.typeCharacter(character))
        }
        check("typing filters the list",
              coordinator.panelVisibleCount == 2,
              detail: "query '\(coordinator.panelQuery)', \(coordinator.panelVisibleCount) visible")
        check("the guarded entry stays hidden even though its content matches",
              coordinator.panelVisibleCount == 2)
        check("selection sits on the first match",
              coordinator.panelSelectedID != nil)

        coordinator.sendPanelKeyCommand(.deleteBackward)
        check("backspace edits the query rather than deleting a row",
              coordinator.panelQuery == "alph" && coordinator.store.items.count == 4,
              detail: "query '\(coordinator.panelQuery)'")

        coordinator.sendPanelKeyCommand(.cancel)
        check("escape clears the query first and keeps the panel open",
              coordinator.panelQuery.isEmpty && coordinator.panelIsVisible
                  && coordinator.panelVisibleCount == 4)

        coordinator.sendPanelKeyCommand(.cancel)
        try? await Task.sleep(for: .milliseconds(150))
        check("a second escape closes the panel", !coordinator.panelIsVisible)

        // With the guard off, the flagged entry is an ordinary entry and search finds it by content.
        coordinator.store.settings.secretGuardEnabled = false
        coordinator.showPanel()
        try? await Task.sleep(for: .milliseconds(150))
        for character in "alpha" {
            coordinator.sendPanelKeyCommand(.typeCharacter(character))
        }
        check("with the guard off, the flagged entry is found by its content",
              coordinator.panelVisibleCount == 3,
              detail: "\(coordinator.panelVisibleCount) visible")
        coordinator.sendPanelKeyCommand(.cancel)
        coordinator.sendPanelKeyCommand(.cancel)
        try? await Task.sleep(for: .milliseconds(150))

        coordinator.store.settings.secretGuardEnabled = guardWasEnabled

        // MARK: Menu bar menu (PLAN.md Item 7)

        print("")
        print("Menu bar menu")
        // Read-only on purpose: setting recentEntriesInMenu would persist to the user's preferences.
        let menuLimit = coordinator.recentEntriesInMenu
        let menuEntries = coordinator.recentEntriesForMenu
        check("menu lists the configured number of recent entries",
              menuEntries.count == min(menuLimit, coordinator.store.items.count),
              detail: "limit \(menuLimit), \(coordinator.store.items.count) in history, \(menuEntries.count) listed")
        check("menu lists them in history order",
              menuEntries.map(\.id) == Array(coordinator.store.items.prefix(menuEntries.count)).map(\.id))
        check("every menu label is a single bounded line",
              menuEntries.allSatisfy {
                  let title = coordinator.menuLabel(for: $0).title
                  return !title.contains("\n") && title.count <= MenuEntryFormatter.maxCharacters
              })

        coordinator.store.removeEverything()

        if !strayQueries.isEmpty {
            print("INFO  live typing reached the panel during this run (search query: "
                  + strayQueries.sorted().map { "'\($0)'" }.joined(separator: ", ")
                  + "). Failures above are likely that, not the code; rerun with hands off the keyboard.")
        }

        print("----------------------")
        if failures.isEmpty {
            print("all checks passed")
        } else {
            print("\(failures.count) check(s) failed:")
            for failure in failures { print("  - \(failure)") }
        }

        coordinator.stop()
        exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

#endif
