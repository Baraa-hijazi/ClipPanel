//
//  KeystrokeSender.swift
//  ClipPanel
//

import AppKit
import Carbon.HIToolbox
import OSLog

/// Sending a paste keystroke to another app, behind a protocol so the paste path can be tested
/// without Accessibility, without a real keyboard, and without stealing focus from whatever is
/// running the tests.
@MainActor
protocol KeystrokeSending: AnyObject {
    /// False when Accessibility has not been granted, which is what puts the app into copy-only
    /// mode rather than failing the paste.
    var canSendKeystrokes: Bool { get }
    /// Brings `app` back to the front and waits for it to get there.
    func activate(_ app: NSRunningApplication?) async
    func sendPaste()
}

final class SystemKeystrokeSender: KeystrokeSending {
    /// How long to wait for the target app to come back to the front before giving up and posting
    /// anyway. Generous enough for a slow app, short enough that a paste never feels laggy.
    private static let activationTimeout: Duration = .milliseconds(400)
    private static let activationPollInterval: Duration = .milliseconds(20)

    var canSendKeystrokes: Bool { AccessibilityPermission.isTrusted }

    func activate(_ app: NSRunningApplication?) async {
        guard let app else { return }

        app.activate()

        // The panel held key focus while it was open (DESIGN 6.7), so the keystroke must not go out
        // until the target app has actually taken focus back. Polling rather than a flat sleep
        // keeps the common case fast.
        let deadline = ContinuousClock.now.advanced(by: Self.activationTimeout)
        while ContinuousClock.now < deadline {
            if app.isActive { return }
            try? await Task.sleep(for: Self.activationPollInterval)
        }
        Log.paste.debug("Target app did not report active within the timeout; pasting anyway")
    }

    func sendPaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.paste.error("Could not create an event source for the paste keystroke")
            return
        }

        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)

        // Flags are set explicitly rather than inherited, so a modifier the user happens to still
        // be holding (the option of option-Return, for instance) does not turn this into a
        // different shortcut.
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
