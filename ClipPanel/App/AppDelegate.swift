//
//  AppDelegate.swift
//  ClipPanel
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created here rather than in `applicationDidFinishLaunching` so the menu bar scene can
    /// reach it whenever SwiftUI decides to build its content.
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside INFOPLIST_KEY_LSUIElement: no Dock icon, no menu bar
        // takeover, no window on launch.
        NSApp.setActivationPolicy(.accessory)

        coordinator.start()

        #if DEBUG
        SelfTest.runIfRequested(coordinator: coordinator)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
