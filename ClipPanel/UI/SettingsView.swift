//
//  SettingsView.swift
//  ClipPanel
//

import SwiftUI

struct SettingsView: View {
    /// Weak because the window outlives nothing but is owned by the coordinator; a strong reference
    /// here would be a cycle. A nil coordinator only happens during teardown.
    weak var coordinator: AppCoordinator?

    var body: some View {
        TabView {
            if let coordinator {
                GeneralSettingsTab(coordinator: coordinator)
                    .tabItem { Label("General", systemImage: "gearshape") }

                PrivacySettingsTab(coordinator: coordinator)
                    .tabItem { Label("Privacy", systemImage: "hand.raised") }

                PermissionsSettingsTab(coordinator: coordinator)
                    .tabItem { Label("Permissions", systemImage: "lock.shield") }
            }
        }
        .frame(width: 540, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorderView(
                        shortcut: coordinator.panelShortcut,
                        onRecord: { coordinator.updateShortcut($0) },
                        onReset: { coordinator.resetShortcut() }
                    )
                }
                if coordinator.hotKeyUnavailable {
                    Text("That combination is already taken by another app, so the previous one is still in use. Open ClipPanel from the menu bar in the meantime.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Picker("Keep", selection: historyLimit) {
                    ForEach([10, 25, 50, 100], id: \.self) { count in
                        Text("\(count) entries").tag(count)
                    }
                }
                Text("Pinned entries are kept as well, and do not count towards this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Skip copies larger than", selection: maxMegabytes) {
                    ForEach([1, 4, 8, 16, 32], id: \.self) { megabytes in
                        Text("\(megabytes) MB").tag(megabytes)
                    }
                }
                Picker("Skip images larger than", selection: maxImageMegabytes) {
                    ForEach([16, 32, 64, 128, 256], id: \.self) { megabytes in
                        Text("\(megabytes) MB").tag(megabytes)
                    }
                }
                Text("Images and screenshots get their own, larger limit. Oversized copies are not recorded; your clipboard still holds them, so pasting normally works as usual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Keep at most", selection: maxTotalMegabytes) {
                    ForEach([128, 256, 512, 1024], id: \.self) { megabytes in
                        Text("\(megabytes) MB of history").tag(megabytes)
                    }
                }
                Text("When history grows past this, the oldest unpinned entries are removed first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show which app a copy came from", isOn: showCaptions)
                Toggle("Open ClipPanel at login", isOn: launchAtLogin)
                if coordinator.launchAtLoginNeedsApproval {
                    Text("Waiting for approval in System Settings, Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var historyLimit: Binding<Int> {
        Binding(
            get: { coordinator.captureSettings.historyLimit },
            set: {
                var settings = coordinator.captureSettings
                settings.historyLimit = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var maxMegabytes: Binding<Int> {
        Binding(
            get: { coordinator.captureSettings.maxItemBytes / (1024 * 1024) },
            set: {
                var settings = coordinator.captureSettings
                settings.maxItemBytes = $0 * 1024 * 1024
                coordinator.captureSettings = settings
            }
        )
    }

    private var maxImageMegabytes: Binding<Int> {
        Binding(
            get: { coordinator.captureSettings.maxImageItemBytes / (1024 * 1024) },
            set: {
                var settings = coordinator.captureSettings
                settings.maxImageItemBytes = $0 * 1024 * 1024
                coordinator.captureSettings = settings
            }
        )
    }

    private var maxTotalMegabytes: Binding<Int> {
        Binding(
            get: { coordinator.captureSettings.maxTotalBytes / (1024 * 1024) },
            set: {
                var settings = coordinator.captureSettings
                settings.maxTotalBytes = $0 * 1024 * 1024
                coordinator.captureSettings = settings
            }
        )
    }

    private var showCaptions: Binding<Bool> {
        Binding(
            get: { coordinator.showSourceAppCaptions },
            set: { coordinator.showSourceAppCaptions = $0 }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { coordinator.launchAtLogin },
            set: { coordinator.launchAtLogin = $0 }
        )
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                Toggle("Pause saving copies", isOn: paused)
                Text("Nothing is recorded while paused, and a copy made during a pause is not collected afterwards either.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Skip copies apps mark as temporary", isOn: skipTransient)
                Text("Some apps flag a copy as transient or automatic. Off means those get saved too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Clear history when the screen locks", isOn: clearOnLock)
                Text("Pinned entries are kept. Off by default, because losing history at every lock is usually the worse trade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Require Touch ID or password after the screen locks", isOn: requireAuth)
                Text("The first time the panel opens after a lock, macOS asks you to prove it is you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Panic wipe shortcut (⌃⌥⌘⌫)", isOn: panicHotKey)
                Text("Clears every unpinned entry instantly, from anywhere. Also in the menu bar menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Entries that look like passwords") {
                Toggle("Guard entries that look like passwords", isOn: secretGuard)
                Text("When on, copies that look like passwords or access tokens are masked in the panel, hidden from search, and expire on their own. Pasting them works as usual. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Disabled rather than hidden while the guard is off, so the user can see what the
                // switch governs before deciding to turn it on.
                Group {
                    Picker("Expire them after", selection: guardedLifetime) {
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("15 minutes").tag(TimeInterval(900))
                        Text("1 hour").tag(TimeInterval(3600))
                        Text("Never").tag(TimeInterval(0))
                    }

                    Toggle("Clear the clipboard a minute after pasting one", isOn: clearAfterGuardedPaste)
                    Text("Only when the clipboard still holds that entry. Copying anything newer cancels it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Strict mode: do not save them at all", isOn: strictMode)
                    Text("A false alarm then means the copy is silently missing from history instead of masked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!coordinator.captureSettings.secretGuardEnabled)
            }

            Section("Whole history") {
                Picker("Remove unpinned entries after", selection: historyLifetime) {
                    Text("Never (until quit)").tag(TimeInterval(0))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("8 hours").tag(TimeInterval(8 * 3600))
                    Text("24 hours").tag(TimeInterval(24 * 3600))
                    Text("7 days").tag(TimeInterval(7 * 24 * 3600))
                }
                Text("The app runs for weeks at a time, so history until quit can mean history forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Never save copies from these apps") {
                ExcludedAppsView(
                    excluded: coordinator.captureSettings.excludedBundleIDs,
                    onAdd: { coordinator.exclude(bundleID: $0) },
                    onRemove: { coordinator.stopExcluding(bundleID: $0) }
                )
                Text("Copies marked secret by a password manager are never saved regardless of this list, and cannot be, which is why most password managers do not need to be here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var paused: Binding<Bool> {
        Binding(
            get: { coordinator.captureSettings.isPaused },
            set: {
                var settings = coordinator.captureSettings
                settings.isPaused = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var skipTransient: Binding<Bool> {
        Binding(
            get: { coordinator.captureSettings.skipTransientAndAutoGenerated },
            set: {
                var settings = coordinator.captureSettings
                settings.skipTransientAndAutoGenerated = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var guardedLifetime: Binding<TimeInterval> {
        Binding(
            get: { coordinator.captureSettings.guardedLifetime },
            set: {
                var settings = coordinator.captureSettings
                settings.guardedLifetime = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var clearAfterGuardedPaste: Binding<Bool> {
        Binding(
            get: { coordinator.captureSettings.clearClipboardAfterPastingGuarded },
            set: {
                var settings = coordinator.captureSettings
                settings.clearClipboardAfterPastingGuarded = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var secretGuard: Binding<Bool> {
        Binding(
            get: { coordinator.captureSettings.secretGuardEnabled },
            set: {
                var settings = coordinator.captureSettings
                settings.secretGuardEnabled = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var strictMode: Binding<Bool> {
        Binding(
            get: { coordinator.captureSettings.strictSecretMode },
            set: {
                var settings = coordinator.captureSettings
                settings.strictSecretMode = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var historyLifetime: Binding<TimeInterval> {
        Binding(
            get: { coordinator.captureSettings.historyLifetime },
            set: {
                var settings = coordinator.captureSettings
                settings.historyLifetime = $0
                coordinator.captureSettings = settings
            }
        )
    }

    private var clearOnLock: Binding<Bool> {
        Binding(
            get: { coordinator.clearOnScreenLock },
            set: { coordinator.clearOnScreenLock = $0 }
        )
    }

    private var requireAuth: Binding<Bool> {
        Binding(
            get: { coordinator.requireAuthAfterLock },
            set: { coordinator.requireAuthAfterLock = $0 }
        )
    }

    private var panicHotKey: Binding<Bool> {
        Binding(
            get: { coordinator.panicWipeHotKeyEnabled },
            set: { coordinator.panicWipeHotKeyEnabled = $0 }
        )
    }
}

// MARK: - Permissions

private struct PermissionsSettingsTab: View {
    let coordinator: AppCoordinator

    private var permissions: PermissionsModel { coordinator.permissions }

    var body: some View {
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
                Text("Pinned entries")
                    .font(.headline)
                Text(coordinator.pinsPersist
                     ? "Encrypted on this Mac, with the key in your login keychain. They do not sync to other devices, by design."
                     : "Not being saved this session, because the keychain could not be reached. Pins still work until you quit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await permissions.poll() }
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
