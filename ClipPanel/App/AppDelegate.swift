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
        guard !RuntimeEnvironment.isHostingTests else {
            Log.app.info("Test host launch: capture and hot key left unstarted")
            return
        }

        // The self test drives the app headlessly, so it wants no onboarding window and no keychain
        // access. Both the check and the affordance live inside DEBUG: a Release build must not
        // respond to an environment variable at all, and until this was wrapped the variable's name
        // was still sitting in the shipping binary.
        #if DEBUG
        let isSelfTest = ProcessInfo.processInfo.environment["CLIPPANEL_SELFTEST"] == "1"
        coordinator.start(presentOnboarding: !isSelfTest, persistPins: !isSelfTest)
        SelfTest.runIfRequested(coordinator: coordinator)
        #else
        coordinator.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

}
