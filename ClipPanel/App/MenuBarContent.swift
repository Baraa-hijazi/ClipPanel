//
//  MenuBarContent.swift
//  ClipPanel
//
//  Only items that actually work are listed. Pause Capture and Clear All arrive with the
//  capture pipeline in M2, Settings in M6.
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
