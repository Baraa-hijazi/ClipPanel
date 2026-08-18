//
//  PanelController.swift
//  ClipPanel
//

import AppKit
import OSLog
import SwiftUI

/// Owns the panel window: builds it once, shows it at the right place, hides it again.
final class PanelController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let currentAccess: () -> PasteboardAccess

    private var window: PanelWindow?
    private var isHiding = false
    /// Kept so a size change while the panel is open stays anchored where it opened.
    private var lastAnchor: CGPoint = .zero

    init(store: HistoryStore, currentAccess: @escaping () -> PasteboardAccess) {
        self.store = store
        self.currentAccess = currentAccess
        super.init()
    }

    /// Who owned the keyboard when the panel opened. M4 reactivates this app before
    /// synthesizing command-V, so the paste lands where the user was actually typing.
    private(set) var appToRestoreFocusTo: NSRunningApplication?

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = window ?? makeWindow()
        window = panel

        rememberFrontmostApp()

        lastAnchor = NSEvent.mouseLocation
        applySizeAndPosition(to: panel)

        // orderFrontRegardless plus makeKey, never NSApp.activate: that combination is what
        // shows the panel and gives it keystrokes while leaving the other app frontmost.
        //
        // Measured behaviour, do not "fix" this: makeKey() flips NSApp.isActive to true while
        // NSWorkspace.frontmostApplication stays on the other app. That is the deal a
        // non-activating panel offers, and it is what we want, because the panel needs key
        // status for arrow keys and Return while the user's app keeps its caret. NSApp.isActive
        // is therefore a bad signal for "did we steal focus"; frontmostApplication is the real
        // one. Consequence for M4: the panel DOES hold key focus while open, so the paste path
        // must hand focus back (appToRestoreFocusTo) before synthesizing command-V.
        panel.orderFrontRegardless()
        panel.makeKey()

        Log.panel.debug("Panel shown, key: \(panel.isKeyWindow)")
    }

    func hide() {
        guard let window, window.isVisible, !isHiding else { return }
        isHiding = true
        window.orderOut(nil)
        isHiding = false
        Log.panel.debug("Panel hidden")
    }

    /// Called after the history changes so the panel grows or shrinks to match instead of
    /// clipping new rows.
    func refreshSizeIfVisible() {
        guard let window, window.isVisible else { return }
        applySizeAndPosition(to: window)
    }

    // MARK: - NSWindowDelegate

    /// Clicking anywhere outside the panel takes key status away from it, which is our cue
    /// to dismiss. Cheaper and more reliable than a global mouse monitor, and unlike a
    /// global monitor it needs no permission.
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

        // Security, DESIGN 4.2 guarantee 7: clipboard history must not turn up in a screen
        // share, screen recording, or screenshot.
        panel.sharingType = .none

        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }

        let hosting = NSHostingView(
            rootView: PanelRootView(
                store: store,
                pasteboardAccess: currentAccess(),
                listHeight: measuredListHeight()
            )
        )
        hosting.sizingOptions = .intrinsicContentSize
        panel.contentView = hosting

        return panel
    }

    private func applySizeAndPosition(to panel: PanelWindow) {
        // Re-read access on every show so a permission change mid-session is reflected.
        (panel.contentView as? NSHostingView<PanelRootView>)?.rootView = PanelRootView(
            store: store,
            pasteboardAccess: currentAccess(),
            listHeight: measuredListHeight()
        )

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

    /// Measures the rows on their own, in a throwaway hosting view, and returns how much
    /// height the list should get: its natural height, or the cap if it overflows.
    ///
    /// Measuring separately is what makes the panel size correctly. Asking a ScrollView for its
    /// fitting size returns something near its minimum, because scroll views are happy at any
    /// height, which previously sized the whole panel as though it held a single row.
    private func measuredListHeight() -> CGFloat {
        guard !store.items.isEmpty else { return 0 }

        let probe = NSHostingView(rootView: HistoryRowsView(items: store.items))
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
    /// Observable facts about the panel, used by the debug self test and by future
    /// troubleshooting UI. Deliberately contains no clipboard data.
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
