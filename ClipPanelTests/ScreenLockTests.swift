//
//  ScreenLockTests.swift
//  ClipPanelTests
//
//  The test that was missing when the lock path shipped wrong (REVIEW.md, finding 1).
//

import CryptoKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Screen lock behaviour")
@MainActor
struct ScreenLockTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeCoordinatorWithPinFile() -> (AppCoordinator, PinStore, URL) {
        let coordinator = AppCoordinator(
            pasteboard: FakePasteboard(),
            keystrokes: FakeKeystrokeSender()
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipPanelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("pins.enc")
        let pinStore = PinStore(fileURL: fileURL, key: SymmetricKey(size: .bits256))
        coordinator.store.onPinnedItemsChanged = { pinStore.save($0) }
        return (coordinator, pinStore, fileURL)
    }

    @Test("Lock clearing keeps pinned entries and their file, as the Settings toggle promises")
    func lockKeepsPins() {
        let (coordinator, pinStore, fileURL) = makeCoordinatorWithPinFile()
        let wasEnabled = AppPreferences.clearOnScreenLock
        defer { AppPreferences.clearOnScreenLock = wasEnabled }
        AppPreferences.clearOnScreenLock = true

        coordinator.store.record(textItem("pinned secret note", at: base, pinned: true))
        coordinator.store.record(textItem("transient copy", at: base.addingTimeInterval(1)))
        // Persist the pin the way the running app would.
        coordinator.store.togglePin(id: coordinator.store.items.first!.id)
        coordinator.store.togglePin(id: coordinator.store.items.first!.id)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        coordinator.handleScreenLock()

        #expect(coordinator.store.items.count == 1)
        #expect(coordinator.store.items.first?.isPinned == true)
        #expect(FileManager.default.fileExists(atPath: fileURL.path),
                "the encrypted pin file must survive a screen lock")
        #expect(pinStore.load().count == 1)
    }

    @Test("Lock clearing does nothing to history when the toggle is off")
    func lockRespectsDisabledToggle() {
        let (coordinator, _, _) = makeCoordinatorWithPinFile()
        let wasEnabled = AppPreferences.clearOnScreenLock
        defer { AppPreferences.clearOnScreenLock = wasEnabled }
        AppPreferences.clearOnScreenLock = false

        coordinator.store.record(textItem("survives", at: base))
        coordinator.handleScreenLock()

        #expect(coordinator.store.items.count == 1)
    }
}
