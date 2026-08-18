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
