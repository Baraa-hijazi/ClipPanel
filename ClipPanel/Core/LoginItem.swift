//
//  LoginItem.swift
//  ClipPanel
//
//  Launch at login through SMAppService, which is the supported route on modern macOS. The user
//  approves it once in System Settings, Login Items, and can revoke it there.
//

import OSLog
import ServiceManagement

nonisolated enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS wants the user to approve it in System Settings before it takes effect.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Re-registers the current binary under the existing login item record.
    ///
    /// Exists because of a failure observed in the field, not hypothesised: with ad-hoc signing,
    /// the identity BTM records is effectively the hash of one specific binary, so every update
    /// invalidates the record and the app silently stops launching at boot, while the toggle
    /// still reads as on. Registering again from the running binary rewrites the record
    /// (dumpbtm shows its generation bump), so one manual launch after an update heals it.
    /// A Developer ID signature, whose identity is stable across updates, removes the need.
    static func reassert() {
        guard SMAppService.mainApp.status != .requiresApproval else {
            Log.app.info("Login item awaiting approval in System Settings; not reasserting")
            return
        }
        do {
            try SMAppService.mainApp.register()
            Log.app.info("Login item reasserted for the current binary")
        } catch {
            Log.app.error("Could not reassert the login item: \(String(describing: error), privacy: .public)")
        }
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("Login item \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            Log.app.error("Could not change the login item: \(String(describing: error), privacy: .public)")
        }
    }
}
