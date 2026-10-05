//
//  MenuBarContent.swift
//  ClipPanel
//
//  Only items that actually work are listed. Recent entries sit at the top (PLAN.md Item 7), so
//  the icon is a second way into history; SwiftUI rebuilds this content on every open.
//

import Carbon.HIToolbox
import SwiftUI

struct MenuBarContent: View {
    let coordinator: AppCoordinator

    var body: some View {
        if coordinator.recentEntriesInMenu > 0 {
            recentEntries
            Divider()
        }

        // Titled "Show All" when the recent list is above it; with the list off it is the only way
        // in, so it keeps its original name.
        Button(coordinator.recentEntriesInMenu > 0 ? "Show All..." : "Open Clipboard") {
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

        Button("Panic Wipe") {
            coordinator.panicWipe()
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

    @ViewBuilder
    private var recentEntries: some View {
        let entries = coordinator.recentEntriesForMenu
        if entries.isEmpty {
            Text("No copies yet")
        } else {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                let label = coordinator.menuLabel(for: item)
                let button = Button {
                    coordinator.pasteFromMenu(item)
                } label: {
                    Label(label.title, systemImage: label.symbol)
                }
                // Command-1 through command-9 for the first nine. Menu-only: they work while the
                // menu is open and register nothing global.
                if index < 9 {
                    button.keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))),
                        modifiers: .command
                    )
                } else {
                    button
                }
            }
        }
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
