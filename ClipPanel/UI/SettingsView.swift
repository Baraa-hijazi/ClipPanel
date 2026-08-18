//
//  SettingsView.swift
//  ClipPanel
//
//  M4 ships the Permissions tab, which is the one that can leave the app not working. General and
//  Privacy arrive with M6, along with the hot key recorder and the exclusion list editor.
//

import SwiftUI

struct SettingsView: View {
    let permissions: PermissionsModel
    let shortcut: GlobalShortcut
    let hotKeyUnavailable: Bool

    var body: some View {
        TabView {
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 380)
        .task { await permissions.poll() }
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionRowView(
                title: "Clipboard access",
                explanation: pasteboardExplanation,
                state: pasteboardState,
                actionTitle: "Open System Settings",
                action: permissions.openPasteboardSettings
            )

            Divider()

            PermissionRowView(
                title: "Accessibility",
                explanation: permissions.accessibilityGranted
                    ? "Granted. Picking an entry pastes it into the app you were using."
                    : "Not granted. Picking an entry copies it and you press command-V yourself.",
                state: permissions.accessibilityGranted ? .granted : .optional,
                actionTitle: "Request Access",
                action: permissions.requestAccessibility
            )

            if !permissions.accessibilityGranted {
                Button("Open Accessibility Settings", action: permissions.openAccessibilitySettings)
                    .buttonStyle(.link)
                    .font(.callout)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcut")
                    .font(.headline)
                Text(hotKeyUnavailable
                     ? "\(shortcut.description) could not be registered, because another app is already using it. Open ClipPanel from the menu bar instead. A shortcut picker arrives in a later version."
                     : "\(shortcut.description) opens the clipboard. A shortcut picker arrives in a later version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pasteboardState: PermissionRowView.State {
        switch permissions.pasteboardAccess {
        case .allowed: .granted
        case .denied: .needed
        case .ask, .systemDefault: .optional
        }
    }

    private var pasteboardExplanation: String {
        switch permissions.pasteboardAccess {
        case .allowed: "Allowed. Copies are being saved."
        case .denied: "Turned off. Nothing can be saved until this is allowed in System Settings."
        case .ask: "macOS will ask the next time you copy something."
        case .systemDefault: "Not decided yet. macOS will ask the next time you copy something."
        }
    }
}
