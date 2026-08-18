//
//  ItemFactoryTests.swift
//  ClipPanelTests
//

import AppKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Item factory")
struct ItemFactoryTests {
    @Test("Identical content hashes identically, different content does not")
    func contentHashing() {
        let a = ItemFactory.contentHash(for: textSnapshot("same"))
        let b = ItemFactory.contentHash(for: textSnapshot("same"))
        let c = ItemFactory.contentHash(for: textSnapshot("different"))

        #expect(a == b)
        #expect(a != c)
        #expect(a.count == 32)
    }

    @Test("Type identifiers are part of the hash")
    func hashCoversTypes() {
        let asText = PasteboardSnapshot(items: [[representation(PasteboardTypes.plainText, "x")]])
        let asHTML = PasteboardSnapshot(items: [[representation(PasteboardTypes.html, "x")]])

        #expect(ItemFactory.contentHash(for: asText) != ItemFactory.contentHash(for: asHTML))
    }

    @Test("An empty snapshot produces no item")
    func emptySnapshotIsRejected() {
        #expect(ItemFactory.make(from: PasteboardSnapshot(items: []), sourceBundleID: nil) == nil)
    }

    @Test("Plain text becomes a text preview")
    func textPreview() {
        let item = ItemFactory.make(from: textSnapshot("hello"), sourceBundleID: nil)
        #expect(item?.preview == .text("hello"))
        #expect(item?.isPinned == false)
    }

    @Test("Spaces and tabs collapse, single newlines survive")
    func condenseKeepsLineStructure() {
        let condensed = ItemFactory.condense("a  \t b\nsecond    line")
        #expect(condensed == "a b\nsecond line")
    }

    @Test("Runs of blank lines collapse to one blank line")
    func condenseCollapsesBlankRuns() {
        #expect(ItemFactory.condense("a\n\n\n\n\nb") == "a\n\nb")
    }

    @Test("Preview text is capped")
    func previewIsTruncated() {
        let long = String(repeating: "x", count: ItemFactory.previewCharacterLimit + 250)
        let condensed = ItemFactory.condense(long)
        #expect(condensed.count == ItemFactory.previewCharacterLimit)
    }

    @Test("RTF falls back to its plain string")
    func rtfPreview() throws {
        let attributed = NSAttributedString(string: "styled text")
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let snapshot = PasteboardSnapshot(items: [[ClipItem.Representation(type: PasteboardTypes.rtf, data: rtf)]])

        #expect(ItemFactory.make(from: snapshot, sourceBundleID: nil)?.preview == .text("styled text"))
    }

    @Test("An image becomes a thumbnail no larger than the cap")
    func imagePreviewIsThumbnailed() throws {
        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 900, height: 300)),
        ]])

        let item = try #require(ItemFactory.make(from: snapshot, sourceBundleID: nil))
        guard case .image(let thumbnailPNG, let pixelSize) = item.preview else {
            Issue.record("expected an image preview")
            return
        }

        // Original dimensions are reported, the stored thumbnail is small.
        #expect(pixelSize == CGSize(width: 900, height: 300))
        let thumbnail = try #require(NSImage(data: thumbnailPNG))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= ItemFactory.thumbnailLongestSide)
        #expect(thumbnailPNG.count < pngData(width: 900, height: 300).count)
    }

    @Test("File URLs become a list of paths")
    func filePreview() throws {
        let url = URL(fileURLWithPath: "/tmp/example.txt")
        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.fileURL, data: url.dataRepresentation),
        ]])

        let item = try #require(ItemFactory.make(from: snapshot, sourceBundleID: nil))
        #expect(item.preview == .files(["/tmp/example.txt"]))
    }

    @Test("A multi item copy keeps every pasteboard item")
    func multipleItemsPreserved() throws {
        let first = URL(fileURLWithPath: "/tmp/one.txt")
        let second = URL(fileURLWithPath: "/tmp/two.txt")
        let snapshot = PasteboardSnapshot(items: [
            [ClipItem.Representation(type: PasteboardTypes.fileURL, data: first.dataRepresentation)],
            [ClipItem.Representation(type: PasteboardTypes.fileURL, data: second.dataRepresentation)],
        ])

        let item = try #require(ItemFactory.make(from: snapshot, sourceBundleID: nil))
        #expect(item.items.count == 2)
        #expect(item.preview == .files(["/tmp/one.txt", "/tmp/two.txt"]))
    }

    @Test("Byte size counts every representation")
    func byteSizeSums() {
        let snapshot = PasteboardSnapshot(items: [[
            representation(PasteboardTypes.plainText, "12345"),
            representation(PasteboardTypes.html, "1234567890"),
        ]])
        #expect(snapshot.byteSize == 15)
    }
}
