//
//  PermissionsModel.swift
//  ClipPanel
//

import AppKit
import Observation

/// Live view of the two system gates.
///
/// Polled rather than observed, because macOS does not tell an app when the user grants or revokes
/// Accessibility or pasteboard access. Any window showing this state runs `poll()` while it is
/// open, so the status rows stop lying the moment the user comes back from System Settings.
@Observable
final class PermissionsModel {
    private(set) var accessibilityGranted: Bool
    private(set) var pasteboardAccess: PasteboardAccess

    private let readPasteboardAccess: () -> PasteboardAccess

    init(readPasteboardAccess: @escaping () -> PasteboardAccess) {
        self.readPasteboardAccess = readPasteboardAccess
        self.accessibilityGranted = AccessibilityPermission.isTrusted
        self.pasteboardAccess = readPasteboardAccess()
    }

    func refresh() {
        let trusted = AccessibilityPermission.isTrusted
        if trusted != accessibilityGranted { accessibilityGranted = trusted }

        let access = readPasteboardAccess()
        if access != pasteboardAccess { pasteboardAccess = access }
    }

    /// Refreshes every second until cancelled. Driven by `.task` from whichever window is showing.
    func poll() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    func openAccessibilitySettings() {
        SystemSettingsLink.open(SystemSettingsLink.accessibility)
    }

    func openPasteboardSettings() {
        SystemSettingsLink.open(SystemSettingsLink.pasteboard)
    }
}
