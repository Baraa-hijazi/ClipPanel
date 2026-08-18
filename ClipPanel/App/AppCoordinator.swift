//
//  AppCoordinator.swift
//  ClipPanel
//

import AppKit
import Observation
import OSLog

/// Wires the pieces together and owns them for the lifetime of the process.
/// M4 adds the paste injector here; M5 adds the encrypted pin store.
@Observable
final class AppCoordinator {
    let store = HistoryStore()

    private let hotKeys = HotKeyManager()
    private let pasteboard: any PasteboardSource
    private let monitor: ClipboardMonitor
    private let panel: PanelController

    let panelShortcut = GlobalShortcut.panelDefault

    /// True when the shortcut could not be claimed, usually because another app owns it.
    /// The menu bar item stays the way in, and M6 surfaces this in Settings.
    private(set) var hotKeyUnavailable = false

    /// Mirrors the macOS 26 pasteboard privacy state so the menu and panel can react.
    private(set) var pasteboardAccess: PasteboardAccess = .systemDefault

    init(pasteboard: any PasteboardSource = SystemPasteboard()) {
        self.pasteboard = pasteboard

        let store = self.store
        self.monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings }
        )
        self.panel = PanelController(
            store: store,
            currentAccess: { pasteboard.access }
        )
    }

    func start() {
        monitor.onCapture = { [weak self] item in
            guard let self else { return }
            store.record(item)
            panel.refreshSizeIfVisible()
            refreshPasteboardAccess()
        }
        monitor.onSkip = { [weak self] _ in
            self?.refreshPasteboardAccess()
        }
        monitor.start()
        refreshPasteboardAccess()

        let registered = hotKeys.register(shortcut: panelShortcut) { [weak self] in
            self?.togglePanel()
        }
        hotKeyUnavailable = !registered

        if registered {
            Log.app.info("ClipPanel ready")
        } else {
            Log.app.error("Hot key unavailable; panel reachable from the menu bar only")
        }
        if pasteboardAccess == .denied {
            Log.app.error("Pasteboard access denied; capture is inert until the user allows it")
        }
    }

    func stop() {
        monitor.stop()
        hotKeys.unregister()
    }

    // MARK: - Panel

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

    // MARK: - Capture controls

    var isPaused: Bool { store.settings.isPaused }

    func togglePause() {
        store.settings.isPaused.toggle()
        Log.app.info("Capture \(self.store.settings.isPaused ? "paused" : "resumed", privacy: .public)")
    }

    func clearHistory() {
        store.clearUnpinned()
        panel.refreshSizeIfVisible()
    }

    var monitorIsRunning: Bool { monitor.isRunning }

    private func refreshPasteboardAccess() {
        let current = pasteboard.access
        guard current != pasteboardAccess else { return }
        pasteboardAccess = current
        Log.app.info("Pasteboard access now \(current.rawValue, privacy: .public)")
    }
}
