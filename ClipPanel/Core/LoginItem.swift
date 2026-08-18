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
