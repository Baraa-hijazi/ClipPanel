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

        // Status rows are short buttons that open the Settings tab explaining and fixing what they
        // report, rather than sentences: a menu is as wide as its widest row, and full-sentence rows
        // made this one roughly twice the width it needs (user screenshot, REVIEW.md part 5).
        if coordinator.hotKeyUnavailable {
            Button("Shortcut \(coordinator.panelShortcut.description) Unavailable...") {
                coordinator.showSettings(tab: .general)
            }
        }
        if coordinator.pasteboardAccess == .denied {
            Button("Clipboard Access Is Off...") {
                coordinator.showSettings(tab: .permissions)
            }
        }
        if !coordinator.canPasteAutomatically {
            Button("Turn On Automatic Paste...") {
                coordinator.showSettings(tab: .permissions)
            }
        }
        if !coordinator.pinsPersist {
            Button("Pins Not Being Saved...") {
                coordinator.showSettings(tab: .permissions)
            }
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
