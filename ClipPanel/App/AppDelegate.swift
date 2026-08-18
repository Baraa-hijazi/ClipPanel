//
//  AppDelegate.swift
//  ClipPanel
//

import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created here rather than in `applicationDidFinishLaunching` so the menu bar scene can
    /// reach it whenever SwiftUI decides to build its content.
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside INFOPLIST_KEY_LSUIElement: no Dock icon, no menu bar
        // takeover, no window on launch.
        NSApp.setActivationPolicy(.accessory)

        // Unit tests are hosted in this app, and a live monitor would poll the real clipboard
        // (raising the macOS 26 privacy alert and hanging the run) and claim the global hot key
        // out from under a copy of the app the user may already be running.
        guard !isHostingTests else {
            Log.app.info("Test host launch: capture and hot key left unstarted")
            return
        }

        // Onboarding is suppressed during the self test, which drives the app headlessly.
        coordinator.start(
            presentOnboarding: !isRunningSelfTest,
            persistPins: !isRunningSelfTest
        )

        #if DEBUG
        SelfTest.runIfRequested(coordinator: coordinator)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private var isRunningSelfTest: Bool {
        ProcessInfo.processInfo.environment["CLIPPANEL_SELFTEST"] == "1"
    }

    private var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}
