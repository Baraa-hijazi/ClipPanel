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

        func check(_ label: String, _ passed: Bool, detail: String = "") {
            let mark = passed ? "PASS" : "FAIL"
            let suffix = detail.isEmpty ? "" : "  (\(detail))"
            print("\(mark)  \(label)\(suffix)")
            if !passed { failures.append(label) }
        }

        print("ClipPanel self test, M1 through M4")
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

        let shown = coordinator.panelDiagnostics
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
        check("frontmost app survived the whole cycle",
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == frontmostBeforeShow,
              detail: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")

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
