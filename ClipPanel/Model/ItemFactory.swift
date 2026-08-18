//
//  ItemFactory.swift
//  ClipPanel
//

import AppKit
import CryptoKit
import Foundation

/// Turns a raw pasteboard read into a `ClipItem`: content hash for dedup, and a small preview
/// so the panel never has to hold or re-decode full payloads while drawing.
nonisolated enum ItemFactory {
    /// Longest side of a generated image thumbnail, in pixels.
    static let thumbnailLongestSide: CGFloat = 128
    /// Upper bound on stored preview text. Long enough for a useful card, short enough that
    /// the panel stays cheap to draw.
    static let previewCharacterLimit = 500

    static func make(
        from snapshot: PasteboardSnapshot,
        sourceBundleID: String?,
        now: Date = Date()
    ) -> ClipItem? {
        guard !snapshot.isEmpty, let preview = preview(for: snapshot) else { return nil }

        return ClipItem(
            id: UUID(),
            createdAt: now,
            sourceBundleID: sourceBundleID,
            isPinned: false,
            items: snapshot.items,
            preview: preview,
            byteSize: snapshot.byteSize,
            contentHash: contentHash(for: snapshot)
        )
    }

    /// SHA-256 over every type identifier and payload, in pasteboard order.
    static func contentHash(for snapshot: PasteboardSnapshot) -> Data {
        var hasher = SHA256()
        for item in snapshot.items {
            for representation in item {
                hasher.update(data: Data(representation.type.utf8))
                hasher.update(data: representation.data)
            }
        }
        return Data(hasher.finalize())
    }

    // MARK: - Preview derivation

    /// Files beat images beat text, matching what the source app is most likely to have meant.
    static func preview(for snapshot: PasteboardSnapshot) -> ClipItem.Preview? {
        if let paths = filePaths(in: snapshot), !paths.isEmpty {
            return .files(paths)
        }
        if let image = imagePreview(in: snapshot) {
            return image
        }
        if let text = text(in: snapshot), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    private static func filePaths(in snapshot: PasteboardSnapshot) -> [String]? {
        let urlData = snapshot.items.compactMap { item in
            item.first { $0.type == PasteboardTypes.fileURL }?.data
        }
        guard !urlData.isEmpty else { return nil }

        return urlData.compactMap { data in
            URL(dataRepresentation: data, relativeTo: nil)?.path
        }
    }

    private static func imagePreview(in snapshot: PasteboardSnapshot) -> ClipItem.Preview? {
        let candidates = snapshot.items.flatMap { $0 }
            .filter { PasteboardTypes.imageTypes.contains($0.type) }

        for candidate in candidates {
            guard let (thumbnail, pixelSize) = thumbnail(from: candidate.data) else { continue }
            return .image(thumbnailPNG: thumbnail, pixelSize: pixelSize)
        }
        return nil
    }

    private static func thumbnail(from data: Data) -> (Data, CGSize)? {
        guard let image = NSImage(data: data) else { return nil }

        let original = image.size
        guard original.width > 0, original.height > 0 else { return nil }

        let scale = min(1, thumbnailLongestSide / max(original.width, original.height))
        let target = NSSize(
            width: max(1, (original.width * scale).rounded()),
            height: max(1, (original.height * scale).rounded())
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = target

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, original)
    }

    /// Plain text first, then RTF, then a crude tag strip for the rare HTML-only copy. The
    /// stored representations keep the original markup regardless; this is only what the card
    /// shows.
    static func text(in snapshot: PasteboardSnapshot) -> String? {
        let all = snapshot.items.flatMap { $0 }

        if let plain = all.first(where: { $0.type == PasteboardTypes.plainText })?.data,
           let string = String(data: plain, encoding: .utf8) {
            return condense(string)
        }
        if let rtf = all.first(where: { $0.type == PasteboardTypes.rtf })?.data,
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return condense(attributed.string)
        }
        if let html = all.first(where: { $0.type == PasteboardTypes.html })?.data,
           let markup = String(data: html, encoding: .utf8) {
            return condense(stripTags(from: markup))
        }
        return nil
    }

    /// Collapses runs of spaces and tabs, and runs of three or more newlines, but keeps single
    /// newlines so a multi-line card still looks multi-line.
    static func condense(_ string: String) -> String {
        var result = string.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.count > previewCharacterLimit else { return result }
        return String(result.prefix(previewCharacterLimit))
    }

    private static func stripTags(from markup: String) -> String {
        markup.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }
}
