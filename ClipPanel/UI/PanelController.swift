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
    /// Performs the paste and reports what actually happened, so the panel can react when the app
    /// is in copy-only mode.
    private let paste: (ClipItem, Bool, NSRunningApplication?) async -> PasteOutcome

    private var window: PanelWindow?
    /// Held directly rather than found by casting `window.contentView`: the content view is the glass
    /// container now, with the hosting view inside it.
    private var hostingView: NSHostingView<PanelRootView>?
    private var isHiding = false
    /// True while a confirmation dialog is up, so losing key status to the dialog does not
    /// dismiss the panel underneath it.
    private var isPresentingDialog = false
    /// Kept so a size change while the panel is open stays anchored where it opened.
    private var lastAnchor: CGPoint = .zero

    /// Who owned the keyboard when the panel opened. M4 reactivates this app before synthesizing
    /// command-V, so the paste lands where the user was actually typing.
    private(set) var appToRestoreFocusTo: NSRunningApplication?

    init(
        store: HistoryStore,
        selection: PanelSelection,
        currentAccess: @escaping () -> PasteboardAccess,
        paste: @escaping (ClipItem, Bool, NSRunningApplication?) async -> PasteOutcome
    ) {
        self.store = store
        self.selection = selection
        self.currentAccess = currentAccess
        self.paste = paste
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// The entries the panel is actually showing: the history filtered by the live query.
    /// Every keyboard command and the view itself operate on this, never on `store.items`
    /// directly, so search cannot desynchronise what the arrows move over from what is drawn.
    var visibleItems: [ClipItem] {
        SearchFilter.filter(
            store.items,
            query: selection.query,
            excludingGuarded: store.settings.secretGuardEnabled
        ) {
            AppNameResolver.shared.displayName(for: $0)
        }
    }

    private lazy var actions = PanelActions(
        activate: { [weak self] item in self?.activate(item, plainTextOnly: false) },
        activateAsPlainText: { [weak self] item in self?.activate(item, plainTextOnly: true) },
        togglePin: { [weak self] id in self?.togglePin(id) },
        toggleReveal: { [weak self] id in self?.selection.toggleReveal(id: id) },
        delete: { [weak self] id in self?.delete(id) },
        clearAll: { [weak self] in self?.clearAll() },
        close: { [weak self] in self?.hide() },
        queryDidChange: { [weak self] in self?.queryDidChange() },
        handleKey: { [weak self] command in self?.handle(command) ?? false }
    )

    // MARK: - Showing and hiding

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = window ?? makeWindow()
        window = panel

        rememberFrontmostApp()
        // Opening always starts with no query and the newest entry selected, so the Win+V habit
        // of "shortcut, then Return" pastes the most recent copy.
        selection.query = ""
        lastHandledQuery = ""
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
        selection.searchFocusRequest += 1

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
        // An expiry sweep can remove the selected row out from under the keyboard, and a new
        // capture can change what the current query matches.
        if let id = selection.selectedID, !visibleItems.contains(where: { $0.id == id }) {
            selection.reset(to: visibleItems)
        }
        applySizeAndPosition(to: window)
    }

    // MARK: - Commands

    /// Returns true when the command was consumed. Internal rather than private so the debug self
    /// test can drive the keyboard model without a real key event.
    @discardableResult
    func handle(_ command: PanelKeyCommand) -> Bool {
        switch command {
        case .moveUp:
            selection.move(by: -1, in: visibleItems)
            return true

        case .moveDown:
            selection.move(by: 1, in: visibleItems)
            return true

        case .activate:
            guard let item = selection.selectedItem(in: visibleItems) else { return false }
            activate(item, plainTextOnly: false)
            return true

        case .activateAsPlainText:
            guard let item = selection.selectedItem(in: visibleItems), item.hasPlainText else {
                return false
            }
            activate(item, plainTextOnly: true)
            return true

        case .typeCharacter(let character):
            selection.query.append(character)
            queryDidChange()
            return true

        case .deleteBackward:
            if !selection.query.isEmpty {
                selection.query.removeLast()
                queryDidChange()
                return true
            }
            // With no query active, Backspace keeps its original meaning: remove the entry.
            guard let id = selection.selectedID else { return false }
            delete(id)
            return true

        case .togglePin:
            guard let id = selection.selectedID else { return false }
            togglePin(id)
            return true

        case .toggleReveal:
            guard let id = selection.selectedID,
                  let item = store.items.first(where: { $0.id == id }),
                  store.settings.isGuarded(item)
            else { return false }
            selection.toggleReveal(id: id)
            return true

        case .delete:
            guard let id = selection.selectedID else { return false }
            delete(id)
            return true

        case .cancel:
            // Escape backs out one layer at a time: an active search first, the panel second.
            if !selection.query.isEmpty {
                selection.query = ""
                queryDidChange()
                return true
            }
            hide()
            return true
        }
    }

    private func activate(_ item: ClipItem, plainTextOnly: Bool) {
        // Hidden before the paste, never after: the panel is the key window while it is open, so
        // the target app cannot take focus back until it is gone (DESIGN 6.7).
        hide()

        let target = appToRestoreFocusTo
        Task { [paste] in
            let outcome = await paste(item, plainTextOnly, target)
            switch outcome {
            case .pasted, .copiedOnly:
                break
            case .failed:
                // Most likely option-Return on an entry with no plain text.
                NSSound.beep()
            }
        }
    }

    private func togglePin(_ id: ClipItem.ID) {
        // Pinning a guarded entry promotes a probable secret onto disk (encrypted, but on disk),
        // so it does not happen silently (REVIEW.md part 2). Pinned entries also stop expiring.
        if let item = store.items.first(where: { $0.id == id }),
           store.settings.isGuarded(item), !item.isPinned,
           !confirmPinningGuardedEntry() {
            return
        }
        store.togglePin(id: id)
        // The entry keeps its identity, so selection follows it to its new position.
        refreshSizeIfVisible()
    }

    private func confirmPinningGuardedEntry() -> Bool {
        isPresentingDialog = true
        defer {
            isPresentingDialog = false
            // The dialog took key status; hand it back so the panel keeps taking arrow keys.
            window?.makeKey()
        }

        let alert = NSAlert()
        alert.messageText = "Pin an entry that looks sensitive?"
        alert.informativeText = "This entry looks like a password or access token. Pinning stores it encrypted on this Mac and stops it from expiring."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Pin It")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The last query this controller reacted to. Guards queryDidChange against double firing:
    /// a keyboard command mutates the query and reports the change directly, and the view's
    /// onChange then reports the same edit a runloop later.
    private var lastHandledQuery = ""

    /// Selection jumps to the first match on every keystroke, so Return always pastes the top
    /// hit, and the panel resizes to the filtered list.
    private func queryDidChange() {
        guard selection.query != lastHandledQuery else { return }
        lastHandledQuery = selection.query
        selection.reset(to: visibleItems)
        if let window, window.isVisible {
            applySizeAndPosition(to: window)
        }
    }

    private func delete(_ id: ClipItem.ID) {
        let next = selection.selectionAfterRemoving(id, from: visibleItems)
        store.delete(id: id)
        selection.select(id: next)
        refreshSizeIfVisible()
    }

    private func clearAll() {
        store.clearUnpinned()
        selection.reset(to: visibleItems)
        refreshSizeIfVisible()
    }

    // MARK: - NSWindowDelegate

    /// Clicking anywhere outside the panel takes key status away from it, which is our cue to
    /// dismiss. Cheaper and more reliable than a global mouse monitor, and unlike a global monitor
    /// it needs no permission.
    func windowDidResignKey(_ notification: Notification) {
        guard !isPresentingDialog else { return }
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
        hostingView = hosting

        // Liquid Glass (PLAN.md Item 3). NSGlassEffectView is AppKit's container for embedding a
        // window's content in glass, and the right tool for a borderless AppKit-owned panel, rather
        // than SwiftUI's glassEffect on a view inside it. It draws the rounded edge itself, so the
        // SwiftUI root no longer paints a material or a stroke. Reduce Transparency and Increase
        // Contrast fallbacks come with the system view. Screen-capture exclusion is a window
        // property and is unaffected.
        let glass = NSGlassEffectView()
        glass.cornerRadius = PanelMetrics.cornerRadius
        glass.style = .regular
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        panel.contentView = glass

        return panel
    }

    private func rootView(listHeight: CGFloat) -> PanelRootView {
        PanelRootView(
            store: store,
            selection: selection,
            visibleItems: visibleItems,
            pasteboardAccess: currentAccess(),
            actions: actions,
            listHeight: listHeight
        )
    }

    private func applySizeAndPosition(to panel: PanelWindow) {
        // Re-read access on every show so a permission change mid-session is reflected.
        hostingView?.rootView = rootView(listHeight: measuredListHeight())

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
    ///
    /// The probe renders rows unselected and unhovered, so it is only correct because a row's size
    /// does not depend on either (PLAN.md Item 2, enforced by RowLayoutStabilityTests). Before that
    /// fix, hovering a row could add a line of text the probe never measured.
    private func measuredListHeight() -> CGFloat {
        let visible = visibleItems
        guard !visible.isEmpty else { return 0 }

        let probe = NSHostingView(
            rootView: HistoryRowsView(
                items: visible,
                selectedID: nil,
                settings: store.settings
            )
        )
        probe.layoutSubtreeIfNeeded()
        let natural = probe.fittingSize.height

        return min(max(natural, 1), PanelMetrics.listMaxHeight)
    }

    private func fittingSize(for panel: PanelWindow) -> CGSize {
        // Measured on the hosting view: the glass container around it has no intrinsic size of its own.
        let fitting = hostingView?.fittingSize ?? .zero
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
        var contentIsGlass = false
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
            restoreTargetBundleID: appToRestoreFocusTo?.bundleIdentifier,
            contentIsGlass: window.contentView is NSGlassEffectView
        )
    }
}
