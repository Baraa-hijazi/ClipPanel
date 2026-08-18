//
//  ClipPanelApp.swift
//  ClipPanel
//
//  A menu bar agent: no Dock icon, no main window. The panel is an AppKit NSPanel rather
//  than a SwiftUI window because SwiftUI cannot express a non-activating panel, which is
//  the one thing this app cannot do without.
//

import SwiftUI

@main
struct ClipPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ClipPanel", systemImage: "list.clipboard") {
            MenuBarContent(coordinator: appDelegate.coordinator)
        }
    }
}
