//
//  ImageCapacityTests.swift
//  ClipPanelTests
//
//  Screenshots of any size get captured; the limits that remain are deliberate ones: a per-image
//  cap for sanity, and a total in-memory budget that protects the machine.
//

import AppKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Image caps and the memory budget")
@MainActor
struct ImageCapacityTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Cap selection

    @Test("An image-bearing copy is judged against the image cap, not the text cap")
    func imageCapAppliesToImages() {
        var settings = CaptureSettings()
        settings.maxItemBytes = 1024
        settings.maxImageItemBytes = 1024 * 1024

        // Ten times the text cap, comfortably inside the image cap.
        let decision = CaptureRules.decideAfterReading(
            byteSize: 10 * 1024,
            exceededReadLimit: false,
            producedUsableItem: true,
            containsImage: true,
            settings: settings
        )
        #expect(decision == .record)

        // The same size as plain text is rejected.
        let textDecision = CaptureRules.decideAfterReading(
            byteSize: 10 * 1024,
            exceededReadLimit: false,
            producedUsableItem: true,
            containsImage: false,
            settings: settings
        )
        #expect(textDecision == .skip(.tooLarge))
    }

    @Test("An image over the image cap is still rejected")
    func imageCapIsACapNotAnExemption() {
        var settings = CaptureSettings()
        settings.maxImageItemBytes = 1024

        let decision = CaptureRules.decideAfterReading(
            byteSize: 2048,
            exceededReadLimit: false,
            producedUsableItem: true,
            containsImage: true,
            settings: settings
        )
        #expect(decision == .skip(.tooLarge))
    }

    @Test("The effective cap follows the declared types")
    func effectiveCapSelection() {
        let settings = CaptureSettings()
        #expect(settings.effectiveCap(forTypes: [PasteboardTypes.png]) == settings.maxImageItemBytes)
        #expect(settings.effectiveCap(forTypes: [PasteboardTypes.tiff, PasteboardTypes.plainText])
                == settings.maxImageItemBytes)
        #expect(settings.effectiveCap(forTypes: [PasteboardTypes.plainText]) == settings.maxItemBytes)
    }

    @Test("End to end: a screenshot larger than the text cap is captured")
    func oversizedScreenshotIsCaptured() {
        let png = pngData(width: 600, height: 400)
        var settings = CaptureSettings()
        // The text cap is set BELOW this real PNG's size, the image cap above it, so the test
        // proves the monitor reads against the right one.
        settings.maxItemBytes = png.count - 1
        settings.maxImageItemBytes = png.count + 100_000

        let pasteboard = FakePasteboard()
        let captured = Box<[ClipItem]>([])
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { settings },
            frontmostBundleID: { "com.apple.screencaptureui" }
        )
        monitor.onCapture = { captured.value.append($0) }

        pasteboard.put(PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: png),
        ]]))

        #expect(monitor.poll() == nil)
        #expect(captured.value.count == 1)
        guard case .image = captured.value.first?.preview else {
            Issue.record("expected an image preview")
            return
        }
    }

    // MARK: - Memory budget

    @Test("The byte budget evicts the oldest unpinned entries first")
    func budgetEvictsOldest() {
        let store = HistoryStore()
        store.settings.maxTotalBytes = 30

        // Each of these is roughly 9 bytes of payload.
        store.record(textItem("entry aa1", at: base))
        store.record(textItem("entry bb2", at: base.addingTimeInterval(1)))
        store.record(textItem("entry cc3", at: base.addingTimeInterval(2)))
        store.record(textItem("entry dd4", at: base.addingTimeInterval(3)))

        #expect(store.items.count < 4, "the budget must have evicted something")
        #expect(store.items.first?.preview == .text("entry dd4"))
        #expect(!store.items.contains { $0.preview == .text("entry aa1") })
    }

    @Test("Pinned entries neither count against the budget nor get evicted by it")
    func budgetSparesPins() {
        let store = HistoryStore()
        store.settings.maxTotalBytes = 30

        store.record(textItem("pinned big entry aaaaaaaa", at: base, pinned: true))
        store.record(textItem("entry bb2", at: base.addingTimeInterval(1)))
        store.record(textItem("entry cc3", at: base.addingTimeInterval(2)))

        #expect(store.items.contains { $0.isPinned })
        #expect(store.pinnedCount == 1)
    }

    @Test("The newest capture always survives, even when it alone exceeds the budget")
    func newestCaptureAlwaysSurvives() {
        let store = HistoryStore()
        store.settings.maxTotalBytes = 10

        store.record(textItem("older entry", at: base))
        store.record(textItem(String(repeating: "x", count: 500), at: base.addingTimeInterval(1)))

        // Everything older is evicted, but the capture that triggered the eviction stays:
        // otherwise large screenshots would silently vanish again, which is the bug this whole
        // area exists to fix.
        #expect(store.items.count == 1)
        #expect(store.unpinnedCount == 1)
    }

    @Test("Image and total limits round trip through preferences with clamping")
    func preferencesRoundTrip() {
        let keys = ["maxImageMegabytes", "maxTotalMegabytes"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }

        UserDefaults.standard.set(128, forKey: "maxImageMegabytes")
        UserDefaults.standard.set(512, forKey: "maxTotalMegabytes")
        var loaded = AppPreferences.loadCaptureSettings()
        #expect(loaded.maxImageItemBytes == 128 * 1024 * 1024)
        #expect(loaded.maxTotalBytes == 512 * 1024 * 1024)

        // Hand-edited nonsense is clamped, not obeyed.
        UserDefaults.standard.set(1, forKey: "maxImageMegabytes")
        UserDefaults.standard.set(1_000_000, forKey: "maxTotalMegabytes")
        loaded = AppPreferences.loadCaptureSettings()
        #expect(loaded.maxImageItemBytes == 8 * 1024 * 1024)
        #expect(loaded.maxTotalBytes == 4096 * 1024 * 1024)
    }
}
