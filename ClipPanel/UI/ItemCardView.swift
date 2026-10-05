//
//  ItemCardView.swift
//  ClipPanel
//
//  One history entry: preview, source and time caption, pin and delete affordances on hover or
//  keyboard focus. Guarded entries (the secret detector flagged them) are masked until revealed,
//  which also covers the shoulder-surfing case that screen-capture exclusion never could.
//

import SwiftUI

struct ItemCardView: View {
    let item: ClipItem
    let isSelected: Bool
    let isRevealed: Bool
    /// Effective guarded state (Secret Guard switch AND the detector's verdict), decided by the
    /// caller. Never read `isGuarded` in this view.
    let isGuarded: Bool
    let actions: PanelActions
    var showsCaption = true

    @State private var isHovering = false

    private var showsActions: Bool { isHovering || isSelected }
    private var isMasked: Bool { isGuarded && !isRevealed }

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
        if isMasked {
            maskedContent
        } else {
            plainContent
        }
    }

    /// The preview string is deliberately not rendered at all while masked, not even blurred:
    /// blurs can be reversed and screen readers still speak hidden views' text.
    private var maskedContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.fill")
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
            Text("••••••••")
                .font(.callout.monospaced())
            Text("Probably sensitive")
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
        .accessibilityLabel("Probably sensitive entry, masked")
    }

    @ViewBuilder
    private var plainContent: some View {
        switch item.preview {
        case .text(let string):
            HStack(alignment: .top, spacing: 6) {
                if isGuarded {
                    Image(systemName: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.orange))
                        .padding(.top, 2)
                }
                Text(string)
                    .font(.callout)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .textSelection(.disabled)
            }

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
        let source = AppNameResolver.shared.displayName(for: item.sourceBundleID)
        let base = source.map { "\($0)  ·  \(when)" } ?? when
        return isGuarded ? "\(base)  ·  expires soon" : base
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            if isGuarded {
                Button {
                    actions.toggleReveal(item.id)
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .help(isRevealed ? "Mask again" : "Reveal (command-R)")
            }

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
