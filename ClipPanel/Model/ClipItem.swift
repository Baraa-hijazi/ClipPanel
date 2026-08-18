//
//  ClipItem.swift
//  ClipPanel
//

import CoreGraphics
import Foundation

/// One entry in the clipboard history.
///
/// Deviates from DESIGN 7 in one way, deliberately and before M5 makes the shape permanent:
/// representations are stored per pasteboard item (`[[Representation]]`) rather than as one
/// flat list. A multi-file copy from Finder puts several items on the pasteboard, and a flat
/// list cannot reproduce that on re-paste. Fixing the model now avoids an encrypted-store
/// migration later.
nonisolated struct ClipItem: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    /// Bumped when the same content is copied again, which is what moves an entry back to the
    /// top of the list the way Windows does.
    var createdAt: Date
    let sourceBundleID: String?
    var isPinned: Bool
    /// True when the secret detector flagged this entry (REVIEW.md, part 2). Guarded entries are
    /// masked in the panel, auto-expire unless pinned, and require confirmation to pin. Never
    /// blocks pasting; that would only teach people to turn the protection off.
    var isGuarded: Bool
    /// Outer array: pasteboard items. Inner array: that item's type/payload pairs, kept in
    /// full so a paste reproduces the original fidelity rather than a flattened version.
    let items: [[Representation]]
    let preview: Preview
    let byteSize: Int
    /// SHA-256 over every type and payload. Used for dedup, so a re-copy moves the existing
    /// entry instead of adding a twin.
    let contentHash: Data

    struct Representation: Sendable, Codable, Equatable {
        let type: String
        let data: Data
    }

    enum Preview: Sendable, Codable, Equatable {
        case text(String)
        case image(thumbnailPNG: Data, pixelSize: CGSize)
        case files([String])
    }

    /// Hand-written solely so `isGuarded` decodes as false from pin files written before the
    /// field existed, instead of failing and quarantining the user's pins.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isGuarded = try container.decodeIfPresent(Bool.self, forKey: .isGuarded) ?? false
        items = try container.decode([[Representation]].self, forKey: .items)
        preview = try container.decode(Preview.self, forKey: .preview)
        byteSize = try container.decode(Int.self, forKey: .byteSize)
        contentHash = try container.decode(Data.self, forKey: .contentHash)
    }

    init(
        id: UUID,
        createdAt: Date,
        sourceBundleID: String?,
        isPinned: Bool,
        isGuarded: Bool = false,
        items: [[Representation]],
        preview: Preview,
        byteSize: Int,
        contentHash: Data
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
        self.isGuarded = isGuarded
        self.items = items
        self.preview = preview
        self.byteSize = byteSize
        self.contentHash = contentHash
    }

    /// Every type present anywhere in the item.
    var allTypes: Set<String> {
        Set(items.flatMap { $0.map(\.type) })
    }
}

extension ClipItem {
    /// The stored plain text payload.
    ///
    /// Deliberately not derived from `preview`, which is truncated for display. Pasting from a
    /// preview would silently hand the user a shortened version of what they copied.
    var plainTextRepresentation: Representation? {
        items.flatMap { $0 }.first { $0.type == PasteboardTypes.plainText }
    }

    /// Whether "paste as plain text" can do anything for this entry.
    var hasPlainText: Bool { plainTextRepresentation != nil }
}
