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
    /// Whether this entry will actually be removed early (guarded, not pinned, lifetime not Never).
    var expires = false
    let actions: PanelActions
    var showsCaption = true
    /// Shared across the list's rows so the selection highlight slides between them rather than
    /// switching one row off and the next on. Optional so a card can stand alone (tests, previews).
    var selectionNamespace: Namespace.ID? = nil

    @State private var isHovering = false

    private var showsActions: Bool { isHovering || isSelected }
    private var isMasked: Bool { isGuarded && !isRevealed }

    /// Width every row action occupies, whatever its symbol. `pin` and `pin.slash` (and `eye` and
    /// `eye.slash`) are different widths, so without a fixed frame toggling one would nudge the
    /// text column too.
    private static let actionWidth: CGFloat = 16
    private static let pinColumnWidth: CGFloat = 12

    /// Layout is identical whether or not the row is hovered, selected, or pinned (PLAN.md Item 2).
    /// The actions and the pin glyph are always in the HStack and only their opacity changes, so the
    /// text column has one width, the preview wraps once, and hovering can never re-wrap a row or
    /// resize the panel under the pointer. RowLayoutStabilityTests holds this, and
    /// PanelController's measurement probe (which renders rows unselected) depends on it.
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
            rowActions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
                .accessibilityHidden(!showsActions)
        }
        .animation(.easeOut(duration: 0.1), value: showsActions)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(background)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { actions.activate(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Always occupies its column, visible only when pinned, so pinning never shifts the text.
    private var pinIndicator: some View {
        Image(systemName: "pin.fill")
            .font(.caption)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .padding(.top, 2)
            .frame(width: Self.pinColumnWidth)
            .opacity(item.isPinned ? 1 : 0)
            .accessibilityHidden(!item.isPinned)
    }

    /// A solid highlight rather than a glass pill: the panel itself is glass now, and Apple's guidance
    /// is not to layer glass on glass. The sliding motion is what the plan was after.
    @ViewBuilder
    private var background: some View {
        if isSelected {
            let highlight = RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.selection)
                .padding(.horizontal, 4)
            if let selectionNamespace {
                highlight.matchedGeometryEffect(id: "selection", in: selectionNamespace)
            } else {
                highlight
            }
        }
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
                    .fixedSize(horizontal: false, vertical: true)
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
        return expires ? "\(base)  ·  expires soon" : base
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            if isGuarded {
                Button {
                    actions.toggleReveal(item.id)
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: Self.actionWidth)
                }
                .help(isRevealed ? "Mask again" : "Reveal (command-R)")
            }

            Button {
                actions.togglePin(item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .frame(width: Self.actionWidth)
            }
            .help(item.isPinned ? "Unpin" : "Pin, so this survives Clear All")

            Button {
                actions.delete(item.id)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: Self.actionWidth)
            }
            .help("Remove from history")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }
}
