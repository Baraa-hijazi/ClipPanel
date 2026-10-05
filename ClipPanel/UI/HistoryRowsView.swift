//
//  HistoryRowsView.swift
//  ClipPanel
//
//  The rows on their own, so PanelController can measure them and work out how tall the panel
//  should be. A plain VStack rather than a LazyVStack: laziness would report only the rows it had
//  bothered to build, which is useless for measuring, and the list is capped at 100 entries so
//  there is nothing to gain from it.
//

import SwiftUI

struct HistoryRowsView: View {
    let items: [ClipItem]
    var selectedID: ClipItem.ID?
    var revealedIDs: Set<ClipItem.ID> = []
    var actions: PanelActions = .inert
    var showsCaptions = true
    /// The Secret Guard switch. Rows receive an effective per-item flag computed from it, so a
    /// card never decides for itself whether to mask.
    var guardEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemCardView(
                    item: item,
                    isSelected: item.id == selectedID,
                    isRevealed: revealedIDs.contains(item.id),
                    isGuarded: guardEnabled && item.isGuarded,
                    actions: actions,
                    showsCaption: showsCaptions
                )
                .id(item.id)

                if index < items.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .frame(width: PanelMetrics.width)
    }
}
