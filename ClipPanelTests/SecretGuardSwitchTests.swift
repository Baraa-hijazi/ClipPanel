//
//  SecretGuardSwitchTests.swift
//  ClipPanelTests
//
//  The Secret Guard master switch (PLAN.md Item 1). Off by default; with it off, nothing is
//  detected, masked, expired early, cleared after pasting, or hidden from search. Turning it back
//  on restores guarded behaviour for entries captured while it was on.
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Secret Guard switch", .serialized)
@MainActor
struct SecretGuardSwitchTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func guardedItem(_ text: String, at date: Date) -> ClipItem {
        var item = textItem(text, at: date)
        item.isGuarded = true
        return item
    }

    private func captureOnce(_ text: String, settings: CaptureSettings) -> [ClipItem] {
        let pasteboard = FakePasteboard()
        let captured = Box<[ClipItem]>([])
        let monitor = ClipboardMonitor(
            source: pasteboard,
            currentSettings: { settings },
            frontmostBundleID: { "com.apple.Safari" }
        )
        monitor.onCapture = { captured.value.append($0) }
        pasteboard.put(textSnapshot(text))
        monitor.poll()
        return captured.value
    }

    // MARK: - Default

    @Test("A fresh install has the guard off")
    func offByDefault() {
        #expect(CaptureSettings().secretGuardEnabled == false)
    }

    // MARK: - The single rule every consumer uses

    @Test("The effective rule is the switch AND the detector's verdict")
    func effectiveRuleMatrix() {
        var on = CaptureSettings()
        on.secretGuardEnabled = true
        let off = CaptureSettings()

        let flagged = guardedItem("P@ssw0rd!2024", at: base)
        let plain = textItem("hello", at: base)

        #expect(on.isGuarded(flagged) == true)
        #expect(on.isGuarded(plain) == false)
        #expect(off.isGuarded(flagged) == false)
        #expect(off.isGuarded(plain) == false)
    }

    // MARK: - Capture

    @Test("With the guard off, a password-shaped copy is captured as an ordinary entry")
    func captureUnguardedWhenOff() {
        let captured = captureOnce("P@ssw0rd!2024", settings: CaptureSettings())

        #expect(captured.count == 1)
        #expect(captured.first?.isGuarded == false)
    }

    @Test("With the guard off, strict mode is inert and the copy is still recorded")
    func strictModeInertWhenOff() {
        var settings = CaptureSettings()
        settings.strictSecretMode = true

        let captured = captureOnce("P@ssw0rd!2024", settings: settings)

        #expect(captured.count == 1)
    }

    @Test("With the guard on, the same copy is flagged, proving the off case is the switch")
    func captureGuardedWhenOn() {
        var settings = CaptureSettings()
        settings.secretGuardEnabled = true

        let captured = captureOnce("P@ssw0rd!2024", settings: settings)

        #expect(captured.first?.isGuarded == true)
    }

    // MARK: - Expiry

    @Test("With the guard off, an entry guarded earlier does not expire early, and does once it is on")
    func expiryFollowsTheSwitch() {
        let store = HistoryStore()
        store.record(guardedItem("P@ssw0rd!2024", at: base))
        let pastLifetime = base.addingTimeInterval(store.settings.guardedLifetime + 60)

        store.sweepExpired(now: pastLifetime)
        #expect(store.items.count == 1, "guard off: the flagged entry is an ordinary entry")

        store.settings.secretGuardEnabled = true
        store.sweepExpired(now: pastLifetime)
        #expect(store.items.isEmpty, "guard back on: the stored flag is acted on again")
    }

    @Test("The whole-history lifetime still applies with the guard off")
    func historyLifetimeUnaffected() {
        let store = HistoryStore()
        store.settings.historyLifetime = 3600
        store.record(textItem("ordinary", at: base))

        store.sweepExpired(now: base.addingTimeInterval(7200))

        #expect(store.items.isEmpty)
    }

    @Test("Never (zero) disables guarded expiry even with the guard on")
    func neverDisablesGuardedExpiry() {
        let store = HistoryStore()
        store.settings.secretGuardEnabled = true
        store.settings.guardedLifetime = 0
        store.record(guardedItem("P@ssw0rd!2024", at: base))

        store.sweepExpired(now: base.addingTimeInterval(86_400))

        #expect(store.items.count == 1)
    }

    // MARK: - Search

    @Test("With the guard off, a flagged entry is found by its content")
    func searchIncludesFlaggedWhenOff() {
        let flagged = guardedItem("hunter2secret", at: base)

        let results = SearchFilter.filter(
            [flagged],
            query: "hunter",
            excludingGuarded: false,
            appName: { _ in nil }
        )
        #expect(results.count == 1)
    }

    // MARK: - Preferences

    @Test("The switch round trips through preferences and defaults to off when unset")
    func preferencesRoundTrip() {
        let key = "secretGuardEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppPreferences.loadCaptureSettings().secretGuardEnabled == false)

        var settings = AppPreferences.loadCaptureSettings()
        settings.secretGuardEnabled = true
        AppPreferences.save(settings)
        #expect(AppPreferences.loadCaptureSettings().secretGuardEnabled == true)
    }
}
