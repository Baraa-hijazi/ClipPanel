//
//  OnboardingView.swift
//  ClipPanel
//
//  Shown once, on first run. Three steps (DESIGN 8): what this is, then each permission explained
//  before its prompt appears. A permission dialog with no context is a permission dialog that gets
//  denied, and in this app a denied pasteboard prompt means nothing works at all.
//

import SwiftUI

struct OnboardingView: View {
    let permissions: PermissionsModel
    let shortcut: GlobalShortcut
    let onFinish: () -> Void

    @State private var step = 0

    private let lastStep = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 520)
        .task { await permissions.poll() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: pasteboardStep
        default: accessibilityStep
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Clipboard history, on macOS")
                .font(.title2.bold())

            Text("Press \(shortcut.description) to see the last things you copied, then pick one to paste it. Like Windows' clipboard history, with a Mac's manners.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Nothing leaves this Mac. ClipPanel has no networking code at all.")
                    bullet("Copies marked secret by password managers are never recorded, and never even read.")
                    bullet("History lives in memory only. Quit or restart and it is gone, except what you pin.")
                    bullet("Pinned entries are encrypted on disk, with the key in your login keychain.")
                    bullet("Optional, off by default: guard copies that look like passwords (masked, expire on their own). Turn it on in Settings, Privacy.")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("What it cannot do: stop other apps from reading your clipboard, or spot a secret that the app you copied it from never marked as one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pasteboardStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow clipboard access")
                .font(.title2.bold())

            Text("macOS asks before an app may read the clipboard. ClipPanel needs it to save your copies, so choose Always Allow when the prompt appears. Without it there is nothing to show you.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRowView(
                title: "Clipboard access",
                explanation: pasteboardExplanation,
                state: pasteboardState,
                actionTitle: "Open System Settings",
                action: permissions.openPasteboardSettings
            )

            Text("The prompt appears the first time you copy something after this. It is a system dialog, so it cannot be triggered from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional: paste for you")
                .font(.title2.bold())

            Text("With Accessibility granted, picking an entry pastes it straight into whatever you were typing in. Without it, picking an entry puts it on your clipboard and you press command-V yourself. Everything else works the same either way.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRowView(
                title: "Accessibility",
                explanation: permissions.accessibilityGranted
                    ? "Granted. Picking an entry pastes it for you."
                    : "Not granted. ClipPanel will copy the entry and leave the paste to you.",
                state: permissions.accessibilityGranted ? .granted : .optional,
                actionTitle: "Request Access",
                action: permissions.requestAccessibility
            )

            Text("macOS will ask you to unlock System Settings and tick ClipPanel in the list. You can do this later from Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Text("Step \(step + 1) of \(lastStep + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
            }
            if step < lastStep {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Using ClipPanel", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
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
        case .denied: "Turned off. ClipPanel cannot save anything until this is allowed."
        case .ask: "macOS will ask the next time you copy something."
        case .systemDefault: "Not decided yet. macOS will ask the next time you copy something."
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
