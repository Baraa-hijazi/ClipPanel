//
//  AppCoordinator.swift
//  ClipPanel
//

import AppKit
import OSLog

/// Wires the pieces together and owns them for the lifetime of the process.
/// M2 adds the clipboard monitor and history store here; M4 adds the paste injector.
final class AppCoordinator {
    private let hotKeys = HotKeyManager()
    private let panel = PanelController()

    let panelShortcut = GlobalShortcut.panelDefault

    /// True when the shortcut could not be claimed, usually because another app owns it.
    /// The menu bar item stays the way in, and M6 surfaces this in Settings.
    private(set) var hotKeyUnavailable = false

    func start() {
        let registered = hotKeys.register(shortcut: panelShortcut) { [weak self] in
            self?.togglePanel()
        }
        hotKeyUnavailable = !registered
        if registered {
            Log.app.info("ClipPanel ready")
        } else {
            Log.app.error("Hot key unavailable; panel reachable from the menu bar only")
        }
    }

    func stop() {
        hotKeys.unregister()
    }

    func togglePanel() {
        panel.toggle()
    }

    func showPanel() {
        panel.show()
    }

    func hidePanel() {
        panel.hide()
    }

    var panelIsVisible: Bool { panel.isVisible }
    var panelDiagnostics: PanelController.Diagnostics { panel.diagnostics }
}
