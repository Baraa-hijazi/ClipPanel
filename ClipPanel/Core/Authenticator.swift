//
//  Authenticator.swift
//  ClipPanel
//
//  Touch ID (or the account password) in front of the panel, opt-in, checked after the screen has
//  been locked (REVIEW.md part 2, exposure layer). Behind a protocol so the gate's logic is
//  testable without biometric hardware.
//

import LocalAuthentication
import OSLog

@MainActor
protocol Authenticating: AnyObject {
    /// True when the user proved themselves, or when the machine has no way to ask (no password
    /// set): an authenticator that cannot ask must not brick the panel.
    func authenticate(reason: String) async -> Bool
}

final class SystemAuthenticator: Authenticating {
    func authenticate(reason: String) async -> Bool {
        // A fresh context per attempt: contexts cache success, and the whole point of the gate is
        // asking again after each lock.
        let context = LAContext()

        var error: NSError?
        // deviceOwnerAuthentication accepts Touch ID, Apple Watch, or the account password, so a
        // Mac without biometrics still gets the protection.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Log.app.error("Cannot evaluate authentication policy; letting the panel open")
            return true
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // Cancelled or failed. The panel stays closed; the hot key asks again.
            return false
        }
    }
}
