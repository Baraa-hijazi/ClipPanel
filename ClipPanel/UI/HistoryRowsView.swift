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
    var actions: PanelActions = .inert

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemCardView(
                    item: item,
                    isSelected: item.id == selectedID,
                    actions: actions
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
