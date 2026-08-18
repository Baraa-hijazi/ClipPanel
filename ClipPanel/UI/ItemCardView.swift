//
//  ItemCardView.swift
//  ClipPanel
//
//  One history entry, per DESIGN 8: preview, source app and time caption, and pin/delete
//  affordances that appear on hover or when the keyboard is on the row.
//

import SwiftUI

struct ItemCardView: View {
    let item: ClipItem
    let isSelected: Bool
    let actions: PanelActions
    var showsCaption = true

    @State private var isHovering = false

    private var showsActions: Bool { isHovering || isSelected }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            pinIndicator
            VStack(alignment: .leading, spacing: 4) {
                content
                if showsCaption {
                    caption
                }
            }
            Spacer(minLength: 0)
            if showsActions {
                rowActions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(background)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { actions.activate(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var pinIndicator: some View {
        if item.isPinned {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .padding(.top, 2)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch item.preview {
        case .text(let string):
            Text(string)
                .font(.callout)
                .lineLimit(4)
                .truncationMode(.tail)
                .textSelection(.disabled)

        case .image(let thumbnailPNG, let pixelSize):
            HStack(spacing: 8) {
                if let image = NSImage(data: thumbnailPNG) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 64, maxHeight: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text("Image, \(Int(pixelSize.width)) x \(Int(pixelSize.height))")
                    .font(.callout)
            }

        case .files(let paths):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(3), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.caption)
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
            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
    }

    private var captionText: String {
        let when = item.createdAt.formatted(.relative(presentation: .numeric))
        guard let app = AppNameResolver.shared.displayName(for: item.sourceBundleID) else {
            return when
        }
        return "\(app)  ·  \(when)"
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            Button {
                actions.togglePin(item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .help(item.isPinned ? "Unpin" : "Pin, so this survives Clear All")

            Button {
                actions.delete(item.id)
            } label: {
                Image(systemName: "xmark")
            }
            .help("Remove from history")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }
}
