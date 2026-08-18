//
//  ExcludedAppsView.swift
//  ClipPanel
//
//  Apps whose copies are never recorded. Adding one is a file picker over /Applications, because
//  asking a person to type a bundle identifier is asking them not to use the feature.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExcludedAppsView: View {
    let excluded: Set<String>
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: $selection) {
                ForEach(sortedExcluded, id: \.self) { bundleID in
                    HStack(spacing: 6) {
                        Text(AppNameResolver.shared.displayName(for: bundleID) ?? bundleID)
                        if AppNameResolver.shared.displayName(for: bundleID) != nil {
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tag(bundleID)
                }
            }
            .frame(height: 120)
            .border(.separator)

            HStack(spacing: 8) {
                Button("Add App...") { pickApp() }
                Button("Remove") {
                    if let selection {
                        onRemove(selection)
                        self.selection = nil
                    }
                }
                .disabled(selection == nil)
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var sortedExcluded: [String] {
        excluded.sorted {
            let left = AppNameResolver.shared.displayName(for: $0) ?? $0
            let right = AppNameResolver.shared.displayName(for: $1) ?? $1
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }

        onAdd(bundleID)
    }
}
