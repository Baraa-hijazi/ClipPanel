//
//  MenuEntryFormatter.swift
//  ClipPanel
//
//  How a history entry is drawn as one line in the menu bar menu (PLAN.md Item 7). Pure, so the
//  rules are unit-testable without SwiftUI or a menu on screen.
//
//  One line and a symbol, never more, on purpose: the panel is excluded from screen capture, but a
//  system menu cannot be (that exclusion is a window property, and NSMenu is not ours to configure),
//  so anything shown here can appear in a screenshot taken while the menu is open. A truncated first
//  line keeps that exposure small, and guarded entries stay masked while Secret Guard is on.
//

import Foundation

nonisolated struct MenuEntryLabel: Equatable, Sendable {
    let title: String
    /// SF Symbol name. A symbol rather than the image thumbnail: thumbnail sizing in SwiftUI-bridged
    /// NSMenu items is not reliably controllable, and uniform rows read better in a menu.
    let symbol: String
}

nonisolated enum MenuEntryFormatter {
    /// Sized for menu width: a menu is as wide as its widest row, so this cap sets the menu's width
    /// once entries are listed. 36 plus an icon and a shortcut hint keeps it near a normal menu's
    /// width; 48 made it roughly a third wider.
    static let maxCharacters = 36
    static let maskedTitle = "•••••••• (sensitive)"

    /// The entries the menu lists: the history's own order (pinned first, then newest), capped.
    static func recentEntries(from items: [ClipItem], limit: Int) -> [ClipItem] {
        Array(items.prefix(max(0, limit)))
    }

    /// `guarded` is the effective value (Secret Guard switch AND the detector's verdict), decided by
    /// the caller, never read from the item here.
    static func label(for item: ClipItem, guarded: Bool) -> MenuEntryLabel {
        if guarded {
            return MenuEntryLabel(title: maskedTitle, symbol: "shield.fill")
        }

        let title: String
        let symbol: String
        switch item.preview {
        case .text(let string):
            title = oneLine(string)
            symbol = "doc.plaintext"
        case .image(_, let pixelSize):
            title = "Image, \(Int(pixelSize.width)) x \(Int(pixelSize.height))"
            symbol = "photo"
        case .files(let paths):
            let first = (paths.first.map { ($0 as NSString).lastPathComponent }) ?? "File"
            title = truncated(paths.count > 1 ? "\(first) and \(paths.count - 1) more" : first)
            symbol = "doc"
        }
        // The pin wins the icon slot; the title already says what kind of entry it is.
        return MenuEntryLabel(title: title, symbol: item.isPinned ? "pin.fill" : symbol)
    }

    /// First non-empty line, whitespace runs collapsed, truncated. An ellipsis also marks text that
    /// continued past its first line, so a one-line preview never pretends to be the whole entry.
    static func oneLine(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }

        guard let first = lines.first else { return "(blank)" }
        let continues = lines.count > 1
        if first.count > maxCharacters || !continues {
            return truncated(first)
        }
        return truncated(first + " …")
    }

    static func truncated(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters - 1)) + "…"
    }
}
