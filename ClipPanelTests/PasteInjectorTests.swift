//
//  PasteInjectorTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Paste injector")
@MainActor
struct PasteInjectorTests {
    private func makeInjector(_ pasteboard: FakePasteboard) -> (PasteInjector, Box<Int>) {
        let writeCount = Box(0)
        let injector = PasteInjector(
            writer: pasteboard,
            didWrite: { writeCount.value += 1 }
        )
        return (injector, writeCount)
    }

    @Test("Copying puts every representation back on the pasteboard")
    func writesAllRepresentations() {
        let pasteboard = FakePasteboard()
        let (injector, _) = makeInjector(pasteboard)

        let snapshot = PasteboardSnapshot(items: [[
            representation(PasteboardTypes.plainText, "hello"),
            representation(PasteboardTypes.html, "<b>hello</b>"),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        #expect(injector.copyToPasteboard(item))
        #expect(pasteboard.writes.count == 1)
        #expect(pasteboard.writes[0].flatMap { $0 }.map(\.type).sorted()
                == [PasteboardTypes.html, PasteboardTypes.plainText].sorted())
    }

    @Test("A multi item copy is written back as multiple pasteboard items")
    func preservesMultipleItems() {
        let pasteboard = FakePasteboard()
        let (injector, _) = makeInjector(pasteboard)

        let first = URL(fileURLWithPath: "/tmp/one.txt")
        let second = URL(fileURLWithPath: "/tmp/two.txt")
        let snapshot = PasteboardSnapshot(items: [
            [ClipItem.Representation(type: PasteboardTypes.fileURL, data: first.dataRepresentation)],
            [ClipItem.Representation(type: PasteboardTypes.fileURL, data: second.dataRepresentation)],
        ])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        #expect(injector.copyToPasteboard(item))
        #expect(pasteboard.writes[0].count == 2)
    }

    @Test("The monitor is told about our own write so it is not captured back")
    func notifiesAfterWriting() {
        let pasteboard = FakePasteboard()
        let (injector, writeCount) = makeInjector(pasteboard)
        let item = ItemFactory.make(from: textSnapshot("x"), sourceBundleID: nil)!

        injector.copyToPasteboard(item)
        #expect(writeCount.value == 1)
    }

    @Test("Plain text paste writes the full payload, not the truncated preview")
    func plainTextIsNotTruncated() {
        let pasteboard = FakePasteboard()
        let (injector, _) = makeInjector(pasteboard)

        // Longer than the preview cap, so a naive implementation that pasted the preview would
        // silently hand back a shortened version of what the user copied.
        let original = String(repeating: "a", count: ItemFactory.previewCharacterLimit + 400)
        let item = ItemFactory.make(from: textSnapshot(original), sourceBundleID: nil)!

        // The preview is capped, as designed.
        guard case .text(let preview) = item.preview else {
            Issue.record("expected a text preview")
            return
        }
        #expect(preview.count == ItemFactory.previewCharacterLimit)

        #expect(injector.copyPlainTextToPasteboard(item))
        let written = pasteboard.writes[0].flatMap { $0 }
        #expect(written.count == 1)
        #expect(written[0].type == PasteboardTypes.plainText)
        #expect(String(data: written[0].data, encoding: .utf8) == original)
    }

    @Test("Plain text paste keeps only the plain text representation")
    func plainTextDropsOtherTypes() {
        let pasteboard = FakePasteboard()
        let (injector, _) = makeInjector(pasteboard)

        let snapshot = PasteboardSnapshot(items: [[
            representation(PasteboardTypes.plainText, "plain"),
            representation(PasteboardTypes.rtf, "styled"),
            representation(PasteboardTypes.html, "<b>styled</b>"),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        #expect(injector.copyPlainTextToPasteboard(item))
        #expect(pasteboard.writes[0].flatMap { $0 }.map(\.type) == [PasteboardTypes.plainText])
    }

    @Test("Plain text paste declines when the entry has no text, and writes nothing")
    func plainTextUnavailable() {
        let pasteboard = FakePasteboard()
        let (injector, writeCount) = makeInjector(pasteboard)

        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 10, height: 10)),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!
        #expect(item.hasPlainText == false)

        #expect(injector.copyPlainTextToPasteboard(item) == false)
        #expect(pasteboard.writes.isEmpty)
        #expect(writeCount.value == 0)
    }

    @Test("Pasting from history does not come back around as a new capture")
    func roundTripIsNotRecaptured() {
        let pasteboard = FakePasteboard()
        let store = HistoryStore()
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings },
            frontmostBundleID: { "com.apple.TextEdit" }
        )
        monitor.onCapture = { store.record($0) }
        let injector = PasteInjector(writer: pasteboard, didWrite: { monitor.markOwnPaste() })

        pasteboard.put(textSnapshot("original"))
        monitor.poll()
        #expect(store.items.count == 1)

        // Paste it back, which changes the pasteboard exactly as a fresh copy would.
        injector.copyToPasteboard(store.items[0])

        #expect(monitor.poll() == .ownPaste)
        #expect(store.items.count == 1)
    }
}
