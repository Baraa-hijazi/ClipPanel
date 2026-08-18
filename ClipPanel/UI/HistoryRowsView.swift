//
//  HistoryRowsView.swift
//  ClipPanel
//
//  Split out from PanelRootView so the controller can measure the rows on their own and work
//  out how tall the panel should be. A plain VStack rather than a LazyVStack: laziness would
//  report only the rows it had bothered to build, which is useless for measuring, and the list
//  is capped at 100 entries so there is nothing to gain from it.
//

import SwiftUI

struct HistoryRowsView: View {
    let items: [ClipItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemRowView(item: item)
                if index < items.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .frame(width: PanelMetrics.width)
    }
}
