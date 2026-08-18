//
//  MenuBarContent.swift
//  ClipPanel
//
//  Only items that actually work are listed. Settings arrives in M6.
//

import Carbon.HIToolbox
import SwiftUI

struct MenuBarContent: View {
    let coordinator: AppCoordinator

    var body: some View {
        Button("Open Clipboard") {
            coordinator.showPanel()
        }
        .keyboardShortcut(
            coordinator.panelShortcut.menuKeyEquivalent,
            modifiers: coordinator.panelShortcut.menuModifiers
        )

        if coordinator.hotKeyUnavailable {
            Text("Shortcut \(coordinator.panelShortcut.description) is in use by another app")
        }
        if coordinator.pasteboardAccess == .denied {
            Text("Clipboard access is turned off in System Settings")
        }
        if !coordinator.canPasteAutomatically {
            Text("Copy-only mode: picking an entry copies it, then press command-V")
        }
        if !coordinator.pinsPersist {
            Text("Pinned entries will not survive a restart this session")
        }

        Divider()

        Button(coordinator.isPaused ? "Resume Capture" : "Pause Capture") {
            coordinator.togglePause()
        }
        Button("Clear All") {
            coordinator.clearHistory()
        }
        .disabled(coordinator.store.unpinnedCount == 0)

        Divider()

        Button("Settings...") {
            coordinator.showSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit ClipPanel") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

extension GlobalShortcut {
    /// SwiftUI rendering of the same shortcut, so the menu and the registered hot key stay
    /// in step. Multi-character labels (function keys) get handled with the recorder in M6.
    var menuKeyEquivalent: KeyEquivalent {
        KeyEquivalent(keyLabel.lowercased().first ?? "v")
    }

    var menuModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        return modifiers
    }
}
