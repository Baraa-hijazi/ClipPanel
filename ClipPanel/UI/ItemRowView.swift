//
//  ItemRowView.swift
//  ClipPanel
//
//  M2 rows: enough to see that capture works. M3 replaces these with the full cards from
//  DESIGN 8, including hover actions, pin and delete affordances, and keyboard focus.
//

import SwiftUI

struct ItemRowView: View {
    let item: ClipItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                content
                caption
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch item.preview {
        case .text(let string):
            Text(string)
                .font(.callout)
                .lineLimit(3)
                .truncationMode(.tail)

        case .image(let thumbnailPNG, let pixelSize):
            HStack(spacing: 8) {
                if let image = NSImage(data: thumbnailPNG) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 60, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text("\(Int(pixelSize.width)) x \(Int(pixelSize.height))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .files(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(3), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text((path as NSString).lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if paths.count > 3 {
                    Text("and \(paths.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var captionText: String {
        let when = item.createdAt.formatted(.relative(presentation: .numeric))
        guard let app = AppNameResolver.shared.displayName(for: item.sourceBundleID) else {
            return when
        }
        return "\(app)  ·  \(when)"
    }
}
