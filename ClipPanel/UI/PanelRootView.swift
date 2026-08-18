//
//  PanelRootView.swift
//  ClipPanel
//

import SwiftUI

struct PanelRootView: View {
    let store: HistoryStore
    let selection: PanelSelection
    let pasteboardAccess: PasteboardAccess
    var actions: PanelActions = .inert
    /// Height the scrolling list is pinned to. The controller measures the rows first and passes
    /// the answer in, because a ScrollView's own ideal height is flexible and would otherwise
    /// collapse the panel to a single row.
    var listHeight: CGFloat = PanelMetrics.listMaxHeight

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: PanelMetrics.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if pasteboardAccess == .denied {
            deniedState
        } else if store.isEmpty {
            emptyState
        } else {
            list
        }
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
                .buttonStyle(.link)
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
                    items: store.items,
                    selectedID: selection.selectedID,
                    actions: actions
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
        pasteboardAccess: .allowed,
        listHeight: 200
    )
    .padding(40)
}
