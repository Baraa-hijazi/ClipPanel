//
//  AppCoordinator.swift
//  ClipPanel
//

import AppKit
import Observation
import OSLog

/// Wires the pieces together and owns them for the lifetime of the process.
/// M5 adds the encrypted pin store; M6 fills in the rest of Settings.
@Observable
final class AppCoordinator {
    let store = HistoryStore()
    let permissions: PermissionsModel

    private let hotKeys = HotKeyManager()
    private let pasteboard: any PasteboardSource & PasteboardWriting
    private let monitor: ClipboardMonitor
    private let paster: PasteInjector
    private let panel: PanelController
    private let selection = PanelSelection()

    @ObservationIgnored
    private var pinStore: PinStore?
    @ObservationIgnored
    private lazy var lockObserver = ScreenLockObserver { [weak self] in
        self?.store.removeEverything()
        self?.hidePanel()
    }
    /// False when the keychain or the file could not be reached. Pins still work for the session,
    /// they just will not survive a restart, and the user is told rather than being left to
    /// discover it after a reboot.
    private(set) var pinsPersist = false

    private(set) var panelShortcut = AppPreferences.loadShortcut()

    /// True when the shortcut could not be claimed, usually because another app owns it.
    /// The menu bar item stays the way in.
    private(set) var hotKeyUnavailable = false

    // @ObservationIgnored because the Observable macro cannot transform a lazy property, and these
    // are windows rather than state anything observes. Both are built on first show, which is
    // always after start(), so they see the final hot key registration result.
    @ObservationIgnored
    private lazy var onboardingWindow: HostedWindowController<OnboardingView> = {
        let permissions = self.permissions
        let shortcut = self.panelShortcut
        return HostedWindowController(title: "Welcome to ClipPanel") { [weak self] in
            OnboardingView(permissions: permissions, shortcut: shortcut) {
                self?.finishOnboarding()
            }
        }
    }()

    @ObservationIgnored
    private lazy var settingsWindow: HostedWindowController<SettingsView> = {
        // Takes the coordinator rather than a snapshot, so every tab reflects live state: a shortcut
        // the user just rebound, a permission they just granted, a setting they just changed.
        HostedWindowController(title: "ClipPanel Settings") { [weak self] in
            SettingsView(coordinator: self)
        }
    }()

    init(
        pasteboard: any PasteboardSource & PasteboardWriting = SystemPasteboard(),
        keystrokes: any KeystrokeSending = SystemKeystrokeSender()
    ) {
        self.pasteboard = pasteboard

        // Built through locals rather than self, so each piece can capture the one before it while
        // self is still being initialised.
        let store = self.store
        let selection = self.selection

        let permissions = PermissionsModel(readPasteboardAccess: { pasteboard.access })
        self.permissions = permissions

        store.settings = AppPreferences.loadCaptureSettings()
        store.showSourceAppCaptions = AppPreferences.showSourceAppCaptions

        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings }
        )
        self.monitor = monitor

        let paster = PasteInjector(
            writer: pasteboard,
            keystrokes: keystrokes,
            didWrite: { monitor.markOwnPaste() }
        )
        self.paster = paster

        self.panel = PanelController(
            store: store,
            selection: selection,
            currentAccess: { pasteboard.access },
            paste: { item, plainTextOnly, targetApp in
                await paster.paste(item, plainTextOnly: plainTextOnly, into: targetApp)
            }
        )
    }

    func start(presentOnboarding: Bool = true, persistPins: Bool = true) {
        if persistPins { setUpPinPersistence() }

        monitor.onCapture = { [weak self] item in
            guard let self else { return }
            store.record(item)
            panel.refreshSizeIfVisible()
            permissions.refresh()
        }
        monitor.onSkip = { [weak self] _ in
            self?.permissions.refresh()
        }
        monitor.start()
        permissions.refresh()

        let registered = registerHotKey(panelShortcut)

        if registered {
            Log.app.info("ClipPanel ready")
        } else {
            Log.app.error("Hot key unavailable; panel reachable from the menu bar only")
        }
        if permissions.pasteboardAccess == .denied {
            Log.app.error("Pasteboard access denied; capture is inert until the user allows it")
        }

        if AppPreferences.clearOnScreenLock {
            lockObserver.start()
        }

        if presentOnboarding, !AppPreferences.hasCompletedOnboarding {
            onboardingWindow.show()
        }
    }

    func stop() {
        monitor.stop()
        hotKeys.unregister()
        lockObserver.stop()
    }

    // MARK: - Settings

    var captureSettings: CaptureSettings {
        get { store.settings }
        set {
            store.settings = newValue
            AppPreferences.save(newValue)
            // A smaller history has to take effect immediately rather than at the next capture.
            store.enforceLimit()
            panel.refreshSizeIfVisible()
        }
    }

    var showSourceAppCaptions: Bool {
        get { store.showSourceAppCaptions }
        set {
            store.showSourceAppCaptions = newValue
            AppPreferences.showSourceAppCaptions = newValue
            panel.refreshSizeIfVisible()
        }
    }

    var clearOnScreenLock: Bool {
        get { AppPreferences.clearOnScreenLock }
        set {
            AppPreferences.clearOnScreenLock = newValue
            newValue ? lockObserver.start() : lockObserver.stop()
        }
    }

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set { LoginItem.setEnabled(newValue) }
    }

    var launchAtLoginNeedsApproval: Bool { LoginItem.needsApproval }

    func exclude(bundleID: String) {
        var settings = captureSettings
        settings.excludedBundleIDs.insert(bundleID)
        captureSettings = settings
    }

    func stopExcluding(bundleID: String) {
        var settings = captureSettings
        settings.excludedBundleIDs.remove(bundleID)
        captureSettings = settings
    }

    /// Rebinds the panel shortcut, keeping the old one if the new combination is already taken.
    @discardableResult
    func updateShortcut(_ shortcut: GlobalShortcut) -> Bool {
        let previous = panelShortcut
        guard registerHotKey(shortcut) else {
            Log.app.error("Could not claim the new shortcut; keeping the previous one")
            registerHotKey(previous)
            return false
        }
        panelShortcut = shortcut
        AppPreferences.save(shortcut)
        return true
    }

    func resetShortcut() {
        AppPreferences.resetShortcut()
        updateShortcut(.panelDefault)
    }

    @discardableResult
    private func registerHotKey(_ shortcut: GlobalShortcut) -> Bool {
        let registered = hotKeys.register(shortcut: shortcut) { [weak self] in
            self?.togglePanel()
        }
        hotKeyUnavailable = !registered
        return registered
    }

    /// Restores pinned entries and keeps them saved from here on.
    ///
    /// Deliberately skipped by the self test: reading a key written by a previous build makes macOS
    /// prompt for keychain access, because an ad-hoc signature changes on every rebuild, and a
    /// prompt would hang a headless run. A Developer ID signed build has a stable identity and does
    /// not have this problem.
    private func setUpPinPersistence() {
        do {
            let key = try KeychainKey.loadOrCreate()
            let fileURL = try PinStore.defaultFileURL()
            let pinStore = PinStore(fileURL: fileURL, key: key)

            store.restore(pinned: pinStore.load())
            store.onPinnedItemsChanged = { [weak pinStore] pinned in
                pinStore?.save(pinned)
            }

            self.pinStore = pinStore
            pinsPersist = true
        } catch {
            pinsPersist = false
            Log.pins.error(
                "Pinned entries will not survive a restart this session: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Panel

    func togglePanel() {
        // Cheap, and the only reliable way to notice a permission change: macOS never calls back.
        permissions.refresh()
        panel.toggle()
    }

    func showPanel() {
        permissions.refresh()
        panel.show()
    }

    func hidePanel() {
        panel.hide()
    }

    var panelIsVisible: Bool { panel.isVisible }
    var panelDiagnostics: PanelController.Diagnostics { panel.diagnostics }
    var panelSelectedID: ClipItem.ID? { selection.selectedID }

    /// Drives the panel's keyboard model without a real key event, for the debug self test.
    @discardableResult
    func sendPanelKeyCommand(_ command: PanelKeyCommand) -> Bool {
        panel.handle(command)
    }

    // MARK: - Windows

    func showSettings() {
        permissions.refresh()
        settingsWindow.show()
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    private func finishOnboarding() {
        AppPreferences.hasCompletedOnboarding = true
        onboardingWindow.close()
    }

    // MARK: - Capture controls

    var isPaused: Bool { store.settings.isPaused }
    var pasteboardAccess: PasteboardAccess { permissions.pasteboardAccess }
    /// False means copy-only mode, which works, just with one extra keystroke from the user.
    var canPasteAutomatically: Bool { permissions.accessibilityGranted }
    var monitorIsRunning: Bool { monitor.isRunning }

    func togglePause() {
        store.settings.isPaused.toggle()
        Log.app.info("Capture \(self.store.settings.isPaused ? "paused" : "resumed", privacy: .public)")
    }

    func clearHistory() {
        store.clearUnpinned()
        panel.refreshSizeIfVisible()
    }
}
