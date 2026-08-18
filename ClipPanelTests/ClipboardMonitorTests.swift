//
//  ClipboardMonitorTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Clipboard monitor")
@MainActor
struct ClipboardMonitorTests {
    private func makeMonitor(
        pasteboard: FakePasteboard,
        settings: CaptureSettings = CaptureSettings(),
        frontmost: String? = "com.apple.TextEdit"
    ) -> (ClipboardMonitor, Box<[ClipItem]>) {
        let captured = Box<[ClipItem]>([])
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { settings },
            frontmostBundleID: { frontmost }
        )
        monitor.onCapture = { captured.value.append($0) }
        return (monitor, captured)
    }

    @Test("Nothing happens when the clipboard has not changed")
    func noChangeNoCapture() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        #expect(monitor.poll() == nil)
        #expect(captured.value.isEmpty)
    }

    @Test("A text copy is captured")
    func capturesText() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(textSnapshot("copied text"))
        #expect(monitor.poll() == nil)

        #expect(captured.value.count == 1)
        #expect(captured.value.first?.preview == .text("copied text"))
        #expect(captured.value.first?.sourceBundleID == "com.apple.TextEdit")
    }

    @Test("The same change is not captured twice")
    func pollIsIdempotent() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(textSnapshot("once"))
        monitor.poll()
        monitor.poll()
        monitor.poll()

        #expect(captured.value.count == 1)
    }

    @Test("A concealed copy is rejected without its payload ever being read")
    func concealedIsNeverRead() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(PasteboardSnapshot(items: [[
            representation(PasteboardTypes.plainText, "hunter2"),
            representation(PasteboardTypes.concealed, ""),
        ]]))

        #expect(monitor.poll() == .concealed)
        #expect(captured.value.isEmpty)
        // The point of the two phase design: we did not merely discard the secret, we never
        // looked at it.
        #expect(pasteboard.payloadReadCount == 0)
    }

    @Test("A copy from an excluded app is rejected without a payload read")
    func excludedAppIsNeverRead() {
        let pasteboard = FakePasteboard()
        let excluded = ExclusionList.suggestedDefaults.first!
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard, frontmost: excluded)

        pasteboard.put(textSnapshot("secret"))

        #expect(monitor.poll() == .excludedApp)
        #expect(captured.value.isEmpty)
        #expect(pasteboard.payloadReadCount == 0)
    }

    @Test("Our own paste is not captured back")
    func ownPasteIgnored() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(textSnapshot("pasted by us"))
        monitor.markOwnPaste()

        #expect(monitor.poll() == .ownPaste)
        #expect(captured.value.isEmpty)
    }

    @Test("An oversized copy is skipped")
    func oversizedSkipped() {
        var settings = CaptureSettings()
        settings.maxItemBytes = 64

        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard, settings: settings)

        pasteboard.put(textSnapshot(String(repeating: "x", count: 500)))

        #expect(monitor.poll() == .tooLarge)
        #expect(captured.value.isEmpty)
    }

    @Test("Copies made while paused stay uncaptured after resuming")
    func pausedCopiesAreNotSweptUpLater() {
        var settings = CaptureSettings()
        settings.isPaused = true

        let pasteboard = FakePasteboard()
        let captured = Box<[ClipItem]>([])
        // A settings closure the test can flip, the way the menu item does at runtime.
        let box = Box(settings)
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { box.value },
            frontmostBundleID: { "com.apple.TextEdit" }
        )
        monitor.onCapture = { captured.value.append($0) }

        pasteboard.put(textSnapshot("copied while paused"))
        #expect(monitor.poll() == .paused)

        box.value.isPaused = false
        // Nothing new has been copied, so resuming must not retroactively collect the secret.
        #expect(monitor.poll() == nil)
        #expect(captured.value.isEmpty)

        pasteboard.put(textSnapshot("copied after resuming"))
        #expect(monitor.poll() == nil)
        #expect(captured.value.count == 1)
        #expect(captured.value.first?.preview == .text("copied after resuming"))
    }

    @Test("Content the app does not understand is skipped")
    func unsupportedSkipped() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(snapshot(types: ["com.example.proprietary"]))

        #expect(monitor.poll() == .nothingUsable)
        #expect(captured.value.isEmpty)
        #expect(pasteboard.payloadReadCount == 0)
    }

    @Test("Whatever was on the clipboard before launch is left alone")
    func preexistingClipboardIsNotCollected() {
        let pasteboard = FakePasteboard()
        pasteboard.put(textSnapshot("copied before ClipPanel started"))

        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        #expect(monitor.poll() == nil)
        #expect(captured.value.isEmpty)
    }

    @Test("Capture feeds the history store end to end")
    func endToEndIntoStore() {
        let pasteboard = FakePasteboard()
        let store = HistoryStore()
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings },
            frontmostBundleID: { "com.apple.TextEdit" }
        )
        monitor.onCapture = { store.record($0) }

        pasteboard.put(textSnapshot("one"))
        monitor.poll()
        pasteboard.put(textSnapshot("two"))
        monitor.poll()
        pasteboard.put(textSnapshot("one"))
        monitor.poll()

        // Third copy is a repeat of the first, so it moves rather than duplicating.
        #expect(store.items.count == 2)
        #expect(store.items.first?.preview == .text("one"))
    }
}

/// Mutable reference holder, so a test can observe callbacks and flip settings mid-run.
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@Suite("Clipboard monitor, race windows")
@MainActor
struct ClipboardMonitorRaceTests {
    private func makeMonitor(
        pasteboard: FakePasteboard
    ) -> (ClipboardMonitor, Box<[ClipItem]>) {
        let captured = Box<[ClipItem]>([])
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { CaptureSettings() },
            frontmostBundleID: { "com.apple.TextEdit" }
        )
        monitor.onCapture = { captured.value.append($0) }
        return (monitor, captured)
    }

    @Test("A pasteboard change during the read discards the mixed capture")
    func changeDuringReadIsDiscarded() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(textSnapshot("harmless"))
        // Between the type peek and the payload read, a password manager writes a secret.
        pasteboard.afterTypesRead = {
            pasteboard.put(PasteboardSnapshot(items: [[
                representation(PasteboardTypes.plainText, "hunter2"),
                representation(PasteboardTypes.concealed, ""),
            ]]))
        }

        #expect(monitor.poll() == .changedMidRead)
        #expect(captured.value.isEmpty)

        // The next poll evaluates the new contents from scratch and rejects them for the real
        // reason, without a payload read.
        let readsBefore = pasteboard.payloadReadCount
        #expect(monitor.poll() == .concealed)
        #expect(pasteboard.payloadReadCount == readsBefore)
        #expect(captured.value.isEmpty)
    }

    @Test("The marker re-check holds even when the change counter cannot catch the swap")
    func markerRecheckIsIndependentOfTheCounter() {
        let pasteboard = FakePasteboard()
        let (monitor, captured) = makeMonitor(pasteboard: pasteboard)

        pasteboard.put(textSnapshot("harmless"))
        // Impossible on a real pasteboard, which always advances the counter. This bypasses the
        // counter guard on purpose to prove the second, independent layer.
        pasteboard.afterTypesRead = {
            pasteboard.sneakilyReplace(PasteboardSnapshot(items: [[
                representation(PasteboardTypes.plainText, "hunter2"),
                representation(PasteboardTypes.concealed, ""),
            ]]))
        }

        #expect(monitor.poll() == .concealed)
        #expect(captured.value.isEmpty)
    }
}
