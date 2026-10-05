//
//  PanelRootView.swift
//  ClipPanel
//

import SwiftUI

struct PanelRootView: View {
    let store: HistoryStore
    let selection: PanelSelection
    /// The search-filtered entries, computed by the controller. The view never filters for
    /// itself, so what is drawn and what the keyboard operates on cannot disagree.
    let visibleItems: [ClipItem]
    let pasteboardAccess: PasteboardAccess
    var actions: PanelActions = .inert
    /// Height the scrolling list is pinned to. The controller measures the rows first and passes
    /// the answer in, because a ScrollView's own ideal height is flexible and would otherwise
    /// collapse the panel to a single row.
    var listHeight: CGFloat = PanelMetrics.listMaxHeight

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: PanelMetrics.width)
        // The glass behind this view (NSGlassEffectView in PanelController) provides the material and
        // the edge. The clip stays so scrolling content cannot paint past the rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if pasteboardAccess == .denied {
            deniedState
        } else if store.isEmpty {
            emptyState
        } else {
            searchRow
            Divider()
            if visibleItems.isEmpty {
                noMatchesState
            } else {
                list
            }
        }
    }

    /// A real text field, not a display row: clickable, shows a cursor, supports text selection
    /// and input-method composition (CJK, dead keys), none of which the earlier fake row did.
    ///
    /// It holds focus while the panel is open, so the navigation keys are intercepted here via
    /// onKeyPress and routed back into the panel's normal command handling BEFORE the field
    /// editor can eat them: arrows move the list selection, Return pastes the top hit,
    /// option-Return pastes as plain text, Escape backs out (query first, panel second), and
    /// Backspace on an empty query keeps its original meaning of deleting the selected entry.
    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Type to search", text: queryBinding)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFieldFocused)
                .onKeyPress(phases: .down) { press in
                    routeFieldKey(press)
                }
            if !selection.query.isEmpty {
                Text("esc clears")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { searchFieldFocused = true }
        .onAppear { searchFieldFocused = true }
        .onChange(of: selection.searchFocusRequest) { _, _ in
            searchFieldFocused = true
        }
        .onChange(of: selection.query) { _, _ in
            actions.queryDidChange()
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { selection.query },
            set: { selection.query = $0 }
        )
    }

    private func routeFieldKey(_ press: KeyPress) -> KeyPress.Result {
        let command: PanelKeyCommand?
        switch press.key {
        case .upArrow:
            command = .moveUp
        case .downArrow:
            command = .moveDown
        case .return:
            command = press.modifiers.contains(.option) ? .activateAsPlainText : .activate
        case .escape:
            command = .cancel
        case .delete:
            // Backspace edits the query while one is active; the field handles that itself.
            command = selection.query.isEmpty ? .deleteBackward : nil
        case .deleteForward:
            command = .delete
        default:
            command = nil
        }
        guard let command else { return .ignored }
        return actions.handleKey(command) ? .handled : .ignored
    }

    private var noMatchesState: some View {
        VStack(spacing: 6) {
            Text("No matches.")
                .font(.callout)
            if store.items.contains(where: store.settings.isGuarded) {
                Text("Entries marked as sensitive stay hidden while searching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Clipboard")
                .font(.headline)
            if store.settings.isPaused {
                Text("Paused")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if store.unpinnedCount > 0 {
                Button("Clear All") {
                    actions.clearAll()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .font(.callout)
                .help("Remove every unpinned entry")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HistoryRowsView(
                    items: visibleItems,
                    selectedID: selection.selectedID,
                    revealedIDs: selection.revealedIDs,
                    actions: actions,
                    showsCaptions: store.showSourceAppCaptions,
                    settings: store.settings
                )
            }
            .frame(height: listHeight)
            .onChange(of: selection.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet.")
                .font(.callout)
            Text("Copy something to see it saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    /// macOS 26 lets the user refuse pasteboard reads outright (DESIGN 6.1). When that happens the
    /// honest thing is to say so rather than sit there looking empty and broken.
    private var deniedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Clipboard access is turned off.")
                .font(.callout)
            Text("ClipPanel cannot save copies until you allow pasteboard access in System Settings, Privacy and Security.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
    }
}

#Preview {
    PanelRootView(
        store: HistoryStore(),
        selection: PanelSelection(),
        visibleItems: [],
        pasteboardAccess: .allowed,
        listHeight: 200
    )
    .padding(40)
}
