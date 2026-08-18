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

        print("ClipPanel M1 self test")
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
