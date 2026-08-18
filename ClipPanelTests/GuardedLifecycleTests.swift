//
//  GuardedLifecycleTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Guarded entry lifecycle")
@MainActor
struct GuardedLifecycleTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func guardedItem(_ text: String, at date: Date, pinned: Bool = false) -> ClipItem {
        var item = textItem(text, at: date, pinned: pinned)
        item.isGuarded = true
        return item
    }

    // MARK: - Capture

    @Test("A password-shaped copy is captured as guarded")
    func captureFlagsSecrets() {
        let pasteboard = FakePasteboard()
        let store = HistoryStore()
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings },
            frontmostBundleID: { "com.apple.Safari" }
        )
        monitor.onCapture = { store.record($0) }

        pasteboard.put(textSnapshot("P@ssw0rd!2024"))
        monitor.poll()

        #expect(store.items.count == 1)
        #expect(store.items[0].isGuarded)
    }

    @Test("Ordinary text is captured unguarded")
    func captureLeavesOrdinaryAlone() {
        let pasteboard = FakePasteboard()
        let store = HistoryStore()
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { store.settings },
            frontmostBundleID: { "com.apple.TextEdit" }
        )
        monitor.onCapture = { store.record($0) }

        pasteboard.put(textSnapshot("meeting notes for tuesday"))
        monitor.poll()

        #expect(store.items.count == 1)
        #expect(store.items[0].isGuarded == false)
    }

    @Test("Strict mode drops detected secrets entirely")
    func strictModeDrops() {
        let pasteboard = FakePasteboard()
        var settings = CaptureSettings()
        settings.strictSecretMode = true
        let captured = Box<[ClipItem]>([])
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { settings },
            frontmostBundleID: { "com.apple.Safari" }
        )
        monitor.onCapture = { captured.value.append($0) }

        pasteboard.put(textSnapshot("P@ssw0rd!2024"))
        #expect(monitor.poll() == .secretInStrictMode)
        #expect(captured.value.isEmpty)

        // Ordinary text still gets through.
        pasteboard.put(textSnapshot("ordinary sentence here"))
        #expect(monitor.poll() == nil)
        #expect(captured.value.count == 1)
    }

    // MARK: - Expiry

    @Test("Guarded entries expire after their lifetime, ordinary ones stay")
    func guardedExpire() {
        let store = HistoryStore()
        store.record(guardedItem("P@ssw0rd!", at: base))
        store.record(textItem("ordinary", at: base))

        let justBefore = base.addingTimeInterval(store.settings.guardedLifetime - 1)
        #expect(store.sweepExpired(now: justBefore) == 0)
        #expect(store.items.count == 2)

        let justAfter = base.addingTimeInterval(store.settings.guardedLifetime + 1)
        #expect(store.sweepExpired(now: justAfter) == 1)
        #expect(store.items.count == 1)
        #expect(store.items[0].isGuarded == false)
    }

    @Test("A pinned guarded entry never expires")
    func pinnedGuardedSurvives() {
        let store = HistoryStore()
        store.record(guardedItem("kept secret", at: base, pinned: true))

        let farFuture = base.addingTimeInterval(1_000_000)
        #expect(store.sweepExpired(now: farFuture) == 0)
        #expect(store.items.count == 1)
    }

    @Test("Re-copying a guarded entry restarts its clock")
    func recopyExtendsLife() {
        let store = HistoryStore()
        store.record(guardedItem("P@ssw0rd!", at: base))

        // Re-copied shortly before it would have expired.
        let nearExpiry = base.addingTimeInterval(store.settings.guardedLifetime - 10)
        store.record(guardedItem("P@ssw0rd!", at: nearExpiry))

        let pastOriginalExpiry = base.addingTimeInterval(store.settings.guardedLifetime + 10)
        #expect(store.sweepExpired(now: pastOriginalExpiry) == 0)
        #expect(store.items.count == 1)
    }

    @Test("The global lifetime expires ordinary entries when enabled")
    func globalLifetimeWorks() {
        let store = HistoryStore()
        store.settings.historyLifetime = 3600
        store.record(textItem("old news", at: base))
        store.record(textItem("pinned news", at: base, pinned: true))

        #expect(store.sweepExpired(now: base.addingTimeInterval(3601)) == 1)
        #expect(store.items.count == 1)
        #expect(store.items[0].isPinned)
    }

    @Test("The global lifetime off by default means no expiry")
    func globalLifetimeDefaultsOff() {
        let store = HistoryStore()
        store.record(textItem("stays forever", at: base))

        #expect(store.sweepExpired(now: base.addingTimeInterval(10_000_000)) == 0)
        #expect(store.items.count == 1)
    }

    // MARK: - Post-paste clipboard clearing

    @Test("The clipboard is cleared when it still holds the guarded paste")
    func clearsUnchangedClipboard() {
        let pasteboard = FakePasteboard()
        let coordinator = AppCoordinator(pasteboard: pasteboard, keystrokes: FakeKeystrokeSender())

        pasteboard.put(textSnapshot("the secret"))
        let countAtPaste = pasteboard.changeCount

        coordinator.clearClipboardIfUnchangedForTesting(since: countAtPaste)

        // The last write is the empty clear.
        #expect(pasteboard.writes.last?.isEmpty == true)
    }

    @Test("A newer copy cancels the clear")
    func newerCopyCancelsClear() {
        let pasteboard = FakePasteboard()
        let coordinator = AppCoordinator(pasteboard: pasteboard, keystrokes: FakeKeystrokeSender())

        pasteboard.put(textSnapshot("the secret"))
        let countAtPaste = pasteboard.changeCount
        // The user copies something new before the minute is up.
        pasteboard.put(textSnapshot("newer copy"))

        coordinator.clearClipboardIfUnchangedForTesting(since: countAtPaste)

        #expect(pasteboard.writes.isEmpty, "the newer copy must never be clobbered")
    }

    // MARK: - Persistence compatibility

    @Test("A pin file written before isGuarded existed still decodes")
    func oldPinFileDecodes() throws {
        // Encode with the key absent, the way an M5-era file would look.
        let item = textItem("old pin", at: base, pinned: true)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([item])
        ) as! [[String: Any]]
        json[0].removeValue(forKey: "isGuarded")
        let oldData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode([ClipItem].self, from: oldData)
        #expect(decoded.count == 1)
        #expect(decoded[0].isGuarded == false)
    }
}
