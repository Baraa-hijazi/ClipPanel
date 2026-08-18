//
//  PermissionRowView.swift
//  ClipPanel
//

import SwiftUI

/// One permission, its current state, and the button that does something about it.
struct PermissionRowView: View {
    let title: String
    let explanation: String
    let state: State
    let actionTitle: String?
    let action: (() -> Void)?

    enum State: Equatable {
        case granted
        case needed
        /// Works without it, just less conveniently.
        case optional

        var symbol: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .needed: "exclamationmark.triangle.fill"
            case .optional: "circle.dashed"
            }
        }

        var tint: Color {
            switch self {
            case .granted: .green
            case .needed: .orange
            case .optional: .secondary
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.tint)
                .font(.title3)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action, state != .granted {
                Button(actionTitle, action: action)
            }
        }
        .padding(.vertical, 6)
    }
}
