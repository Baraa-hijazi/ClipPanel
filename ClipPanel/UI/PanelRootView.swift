//
//  PanelRootView.swift
//  ClipPanel
//
//  M1 placeholder content. The real card list, previews, and keyboard navigation arrive
//  in M3 once the capture pipeline (M2) has something to show.
//

import SwiftUI

struct PanelRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            emptyState
        }
        .frame(width: PanelMetrics.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
}

#Preview {
    PanelRootView()
        .padding(40)
}
