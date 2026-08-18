//
//  PanelController.swift
//  ClipPanel
//

import AppKit
import OSLog
import SwiftUI

/// Owns the panel window: builds it once, shows it at the right place, routes keys and row
/// actions, hides it again.
final class PanelController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let selection: PanelSelection
    private let currentAccess: () -> PasteboardAccess
    /// Returns false when the request could not be honoured, e.g. plain text was asked for and
    /// the entry has none.
    private let copyToPasteboard: (ClipItem, Bool) -> Bool

    private var window: PanelWindow?
    private var isHiding = false
    /// Kept so a size change while the panel is open stays anchored where it opened.
    private var lastAnchor: CGPoint = .zero

    /// Who owned the keyboard when the panel opened. M4 reactivates this app before synthesizing
    /// command-V, so the paste lands where the user was actually typing.
    private(set) var appToRestoreFocusTo: NSRunningApplication?

    init(
        store: HistoryStore,
        selection: PanelSelection,
        currentAccess: @escaping () -> PasteboardAccess,
        copyToPasteboard: @escaping (ClipItem, Bool) -> Bool
    ) {
        self.store = store
        self.selection = selection
        self.currentAccess = currentAccess
        self.copyToPasteboard = copyToPasteboard
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    private lazy var actions = PanelActions(
        activate: { [weak self] item in self?.activate(item, plainTextOnly: false) },
        activateAsPlainText: { [weak self] item in self?.activate(item, plainTextOnly: true) },
        togglePin: { [weak self] id in self?.togglePin(id) },
        delete: { [weak self] id in self?.delete(id) },
        clearAll: { [weak self] in self?.clearAll() },
        close: { [weak self] in self?.hide() }
    )

    // MARK: - Showing and hiding

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = window ?? makeWindow()
        window = panel

        rememberFrontmostApp()
        // Opening always starts at the newest entry, so the Win+V habit of "shortcut, then
        // Return" pastes the most recent copy.
        selection.reset(to: store.items)

        lastAnchor = NSEvent.mouseLocation
        applySizeAndPosition(to: panel)

        // orderFrontRegardless plus makeKey, never NSApp.activate: that combination is what shows
        // the panel and gives it keystrokes while leaving the other app frontmost.
        //
        // Measured behaviour, do not "fix" this: makeKey() flips NSApp.isActive to true while
        // NSWorkspace.frontmostApplication stays on the other app. That is the deal a
        // non-activating panel offers, and it is what we want, because the panel needs key status
        // for arrow keys and Return while the user's app keeps its caret. NSApp.isActive is
        // therefore a bad signal for "did we steal focus"; frontmostApplication is the real one.
        // Consequence for M4: the panel DOES hold key focus while open, so the paste path must
        // hand focus back (appToRestoreFocusTo) before synthesizing command-V.
        panel.orderFrontRegardless()
        panel.makeKey()

        Log.panel.debug("Panel shown, key: \(panel.isKeyWindow), entries: \(self.store.items.count)")
    }

    func hide() {
        guard let window, window.isVisible, !isHiding else { return }
        isHiding = true
        window.orderOut(nil)
        isHiding = false
        Log.panel.debug("Panel hidden")
    }

    /// Called after the history changes so the panel grows or shrinks to match instead of clipping
    /// new rows.
    func refreshSizeIfVisible() {
        guard let window, window.isVisible else { return }
        applySizeAndPosition(to: window)
    }

    // MARK: - Commands

    /// Returns true when the command was consumed. Internal rather than private so the debug self
    /// test can drive the keyboard model without a real key event.
    @discardableResult
    func handle(_ command: PanelKeyCommand) -> Bool {
        switch command {
        case .moveUp:
            selection.move(by: -1, in: store.items)
            return true

        case .moveDown:
            selection.move(by: 1, in: store.items)
            return true

        case .activate:
            guard let item = selection.selectedItem(in: store.items) else { return false }
            activate(item, plainTextOnly: false)
            return true

        case .activateAsPlainText:
            guard let item = selection.selectedItem(in: store.items), item.hasPlainText else {
                return false
            }
            activate(item, plainTextOnly: true)
            return true

        case .togglePin:
            guard let id = selection.selectedID else { return false }
            togglePin(id)
            return true

        case .delete:
            guard let id = selection.selectedID else { return false }
            delete(id)
            return true

        case .cancel:
            hide()
            return true
        }
    }

    private func activate(_ item: ClipItem, plainTextOnly: Bool) {
        guard copyToPasteboard(item, plainTextOnly) else {
            NSSound.beep()
            return
        }
        hide()
    }

    private func togglePin(_ id: ClipItem.ID) {
        store.togglePin(id: id)
        // The entry keeps its identity, so selection follows it to its new position.
        refreshSizeIfVisible()
    }

    private func delete(_ id: ClipItem.ID) {
        let next = selection.selectionAfterRemoving(id, from: store.items)
        store.delete(id: id)
        selection.select(id: next)
        refreshSizeIfVisible()
    }

    private func clearAll() {
        store.clearUnpinned()
        selection.reset(to: store.items)
        refreshSizeIfVisible()
    }

    // MARK: - NSWindowDelegate

    /// Clicking anywhere outside the panel takes key status away from it, which is our cue to
    /// dismiss. Cheaper and more reliable than a global mouse monitor, and unlike a global monitor
    /// it needs no permission.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Private

    private func makeWindow() -> PanelWindow {
        let panel = PanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Security, DESIGN 4.2 guarantee 7: clipboard history must not turn up in a screen share,
        // screen recording, or screenshot.
        panel.sharingType = .none

        panel.delegate = self
        panel.onKeyCommand = { [weak self] command in
            self?.handle(command) ?? false
        }

        let hosting = NSHostingView(rootView: rootView(listHeight: measuredListHeight()))
        hosting.sizingOptions = .intrinsicContentSize
        panel.contentView = hosting

        return panel
    }

    private func rootView(listHeight: CGFloat) -> PanelRootView {
        PanelRootView(
            store: store,
            selection: selection,
            pasteboardAccess: currentAccess(),
            actions: actions,
            listHeight: listHeight
        )
    }

    private func applySizeAndPosition(to panel: PanelWindow) {
        // Re-read access on every show so a permission change mid-session is reflected.
        (panel.contentView as? NSHostingView<PanelRootView>)?.rootView =
            rootView(listHeight: measuredListHeight())

        let size = fittingSize(for: panel)
        panel.setContentSize(size)
        panel.setFrameOrigin(
            PanelPositioner.origin(
                for: size,
                near: lastAnchor,
                screens: PanelPositioner.currentScreens()
            )
        )
    }

    /// Measures the rows on their own, in a throwaway hosting view, and returns how much height the
    /// list should get: its natural height, or the cap if it overflows.
    ///
    /// Measuring separately is what makes the panel size correctly. Asking a ScrollView for its
    /// fitting size returns something near its minimum, because scroll views are happy at any
    /// height, which previously sized the whole panel as though it held a single row.
    private func measuredListHeight() -> CGFloat {
        guard !store.items.isEmpty else { return 0 }

        let probe = NSHostingView(
            rootView: HistoryRowsView(items: store.items, selectedID: nil)
        )
        probe.layoutSubtreeIfNeeded()
        let natural = probe.fittingSize.height

        return min(max(natural, 1), PanelMetrics.listMaxHeight)
    }

    private func fittingSize(for panel: PanelWindow) -> CGSize {
        let fitting = panel.contentView?.fittingSize ?? .zero
        let height = min(max(fitting.height, 1), PanelMetrics.maxHeight)
        return CGSize(width: PanelMetrics.width, height: height)
    }

    private func rememberFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        appToRestoreFocusTo = front
    }
}

// MARK: - Diagnostics

extension PanelController {
    /// Observable facts about the panel, used by the debug self test and by future troubleshooting
    /// UI. Deliberately contains no clipboard data.
    struct Diagnostics: Sendable {
        var exists = false
        var isVisible = false
        var isKeyWindow = false
        var canBecomeKey = false
        var excludedFromScreenCapture = false
        var frame: NSRect = .zero
        var fitsOnAScreen = false
        var restoreTargetBundleID: String?
    }

    var diagnostics: Diagnostics {
        guard let window else { return Diagnostics() }
        let frame = window.frame
        return Diagnostics(
            exists: true,
            isVisible: window.isVisible,
            isKeyWindow: window.isKeyWindow,
            canBecomeKey: window.canBecomeKey,
            excludedFromScreenCapture: window.sharingType == .none,
            frame: frame,
            fitsOnAScreen: NSScreen.screens.contains { $0.visibleFrame.contains(frame) },
            restoreTargetBundleID: appToRestoreFocusTo?.bundleIdentifier
        )
    }
}
