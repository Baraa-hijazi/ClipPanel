//
//  Permissions.swift
//  ClipPanel
//
//  The two system gates this app lives with (DESIGN 6.1, 6.2), in one place:
//
//  1. Pasteboard access, macOS 26. Without it nothing can be captured. Read through
//     PasteboardSource.access.
//  2. Accessibility. Without it the app cannot synthesize command-V, so activating an entry
//     copies it and the user pastes manually. Everything else still works.
//
//  Neither is requested at launch. Onboarding explains each one before triggering the prompt,
//  because a permission dialog with no context is a permission dialog that gets denied.
//

import AppKit
import ApplicationServices

nonisolated enum AccessibilityPermission {
    /// Whether the app may post synthetic keystrokes to other apps.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show its Accessibility prompt. Returns the state as of right now, which
    /// is almost always false: the user grants it in System Settings afterwards, and macOS does
    /// not call back, so the UI has to re-check.
    @discardableResult
    static func request() -> Bool {
        // Spelled literally because `kAXTrustedCheckOptionPrompt` is imported as a mutable global,
        // which Swift 6 will not let us touch. The value is stable API.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

nonisolated enum SystemSettingsLink {
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    /// If this anchor is not recognised, macOS opens the Privacy and Security pane itself, which
    /// is still where the user needs to be.
    static let pasteboard = "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard"

    @MainActor
    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
