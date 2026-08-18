//
//  PasteInjectorTests.swift
//  ClipPanelTests
//

import AppKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Paste injector")
@MainActor
struct PasteInjectorTests {
    private func makeInjector(
        _ pasteboard: FakePasteboard,
        keystrokes: FakeKeystrokeSender = FakeKeystrokeSender()
    ) -> (PasteInjector, Box<Int>) {
        let writeCount = Box(0)
        let injector = PasteInjector(
            writer: pasteboard,
            keystrokes: keystrokes,
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
        let injector = PasteInjector(
            writer: pasteboard,
            keystrokes: FakeKeystrokeSender(),
            didWrite: { monitor.markOwnPaste() }
        )

        pasteboard.put(textSnapshot("original"))
        monitor.poll()
        #expect(store.items.count == 1)

        // Paste it back, which changes the pasteboard exactly as a fresh copy would.
        injector.copyToPasteboard(store.items[0])

        #expect(monitor.poll() == .ownPaste)
        #expect(store.items.count == 1)
    }

    // MARK: - Paste flow

    @Test("With Accessibility granted, the entry is pasted into the target app")
    func pastesWhenTrusted() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)
        let item = ItemFactory.make(from: textSnapshot("paste me"), sourceBundleID: nil)!

        let outcome = await injector.paste(item, plainTextOnly: false, into: .current)

        #expect(outcome == .pasted)
        #expect(pasteboard.writes.count == 1)
        #expect(sender.pasteCount == 1)
        #expect(sender.activatedApps == [NSRunningApplication.current.bundleIdentifier ?? "none"])
    }

    @Test("The pasteboard is written before the keystroke goes out")
    func writesBeforeKeystroke() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)
        let item = ItemFactory.make(from: textSnapshot("order matters"), sourceBundleID: nil)!

        let writesAtPasteTime = Box(-1)
        sender.onSendPaste = { writesAtPasteTime.value = pasteboard.writes.count }

        _ = await injector.paste(item, plainTextOnly: false, into: .current)

        // Otherwise command-V would paste whatever was on the clipboard beforehand.
        #expect(writesAtPasteTime.value == 1)
    }

    @Test("Without Accessibility, the entry is still copied and no keystroke is sent")
    func fallsBackToCopyOnly() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        sender.canSendKeystrokes = false
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)
        let item = ItemFactory.make(from: textSnapshot("copy me"), sourceBundleID: nil)!

        let outcome = await injector.paste(item, plainTextOnly: false, into: .current)

        #expect(outcome == .copiedOnly(.accessibilityNotGranted))
        // The point of the fallback: the user can still paste manually.
        #expect(pasteboard.writes.count == 1)
        #expect(sender.pasteCount == 0)
        #expect(sender.activatedApps.isEmpty)
    }

    @Test("With no recorded target app, the entry is copied rather than pasted into nothing")
    func fallsBackWithoutTarget() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)
        let item = ItemFactory.make(from: textSnapshot("no target"), sourceBundleID: nil)!

        let outcome = await injector.paste(item, plainTextOnly: false, into: nil)

        #expect(outcome == .copiedOnly(.noTargetApp))
        #expect(pasteboard.writes.count == 1)
        #expect(sender.pasteCount == 0)
    }

    @Test("Plain text paste on an entry with no text writes nothing and reports why")
    func plainTextFailureIsReported() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)

        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 8, height: 8)),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        let outcome = await injector.paste(item, plainTextOnly: true, into: .current)

        #expect(outcome == .failed(.entryHasNoPlainText))
        #expect(pasteboard.writes.isEmpty)
        #expect(sender.pasteCount == 0)
    }

    @Test("Plain text paste sends the keystroke once the text is on the pasteboard")
    func plainTextPasteReachesKeystroke() async {
        let pasteboard = FakePasteboard()
        let sender = FakeKeystrokeSender()
        let (injector, _) = makeInjector(pasteboard, keystrokes: sender)

        let snapshot = PasteboardSnapshot(items: [[
            representation(PasteboardTypes.plainText, "plain"),
            representation(PasteboardTypes.rtf, "styled"),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        let outcome = await injector.paste(item, plainTextOnly: true, into: .current)

        #expect(outcome == .pasted)
        #expect(pasteboard.writes[0].flatMap { $0 }.map(\.type) == [PasteboardTypes.plainText])
        #expect(sender.pasteCount == 1)
    }
}
