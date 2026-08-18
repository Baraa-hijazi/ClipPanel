//
//  AuthGateAndPanicTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

/// Scripted authenticator, so the gate's logic is tested without biometric hardware.
final class FakeAuthenticator: Authenticating {
    var result = true
    var attempts = 0

    func authenticate(reason: String) async -> Bool {
        attempts += 1
        return result
    }
}

@Suite("Touch ID gate and panic wipe", .serialized)
@MainActor
struct AuthGateAndPanicTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeCoordinator(auth: FakeAuthenticator) -> AppCoordinator {
        AppCoordinator(
            pasteboard: FakePasteboard(),
            keystrokes: FakeKeystrokeSender(),
            authenticator: auth
        )
    }

    private func withAuthGate<T>(_ enabled: Bool, _ body: () async -> T) async -> T {
        let was = AppPreferences.requireAuthAfterLock
        AppPreferences.requireAuthAfterLock = enabled
        defer { AppPreferences.requireAuthAfterLock = was }
        return await body()
    }

    @Test("A lock arms the gate only when the setting is on")
    func lockArmsGate() async {
        await withAuthGate(true) {
            let coordinator = makeCoordinator(auth: FakeAuthenticator())
            #expect(coordinator.panelNeedsAuthentication == false)
            coordinator.handleScreenLock()
            #expect(coordinator.panelNeedsAuthentication)
        }
        await withAuthGate(false) {
            let coordinator = makeCoordinator(auth: FakeAuthenticator())
            coordinator.handleScreenLock()
            #expect(coordinator.panelNeedsAuthentication == false)
        }
    }

    @Test("A failed check keeps the gate armed, a passed one clears it")
    func gateFollowsAuthResult() async {
        await withAuthGate(true) {
            let auth = FakeAuthenticator()
            let coordinator = makeCoordinator(auth: auth)
            coordinator.handleScreenLock()

            auth.result = false
            coordinator.showPanel()
            // The auth task is async; give it a turn of the loop.
            try? await Task.sleep(for: .milliseconds(50))
            #expect(auth.attempts == 1)
            #expect(coordinator.panelNeedsAuthentication)
            #expect(coordinator.panelIsVisible == false)

            auth.result = true
            coordinator.showPanel()
            try? await Task.sleep(for: .milliseconds(50))
            #expect(auth.attempts == 2)
            #expect(coordinator.panelNeedsAuthentication == false)
        }
    }

    @Test("Turning the setting off disarms an armed gate")
    func disablingSettingDisarms() async {
        await withAuthGate(true) {
            let coordinator = makeCoordinator(auth: FakeAuthenticator())
            coordinator.handleScreenLock()
            #expect(coordinator.panelNeedsAuthentication)

            coordinator.requireAuthAfterLock = false
            #expect(coordinator.panelNeedsAuthentication == false)
            // Restore the persisted value for the surrounding helper.
            coordinator.requireAuthAfterLock = true
        }
    }

    @Test("Panic wipe clears unpinned entries and keeps pins")
    func panicWipeKeepsPins() {
        let coordinator = makeCoordinator(auth: FakeAuthenticator())
        coordinator.store.record(textItem("pinned", at: base, pinned: true))
        coordinator.store.record(textItem("gone", at: base.addingTimeInterval(1)))
        coordinator.store.record(textItem("also gone", at: base.addingTimeInterval(2)))

        coordinator.panicWipe()

        #expect(coordinator.store.items.count == 1)
        #expect(coordinator.store.items.first?.isPinned == true)
        #expect(coordinator.panelIsVisible == false)
    }
}
