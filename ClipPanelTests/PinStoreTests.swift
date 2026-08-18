//
//  PinStoreTests.swift
//  ClipPanelTests
//

import CryptoKit
import Foundation
import Testing

@testable import ClipPanel

/// Every test gets its own directory and its own injected key. The real keychain is never touched:
/// an ad-hoc signed test host changes identity on each rebuild, which would make macOS prompt for
/// keychain access and hang the run. KeychainKey itself is verified by hand.
@Suite("Pin store")
@MainActor
struct PinStoreTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() -> (PinStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipPanelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("pins.enc")
        return (PinStore(fileURL: fileURL, key: SymmetricKey(size: .bits256)), fileURL)
    }

    @Test("Pinned entries survive a save and load")
    func roundTrip() {
        let (store, _) = makeStore()
        let pinned = textItem("keep me", at: base, pinned: true)

        store.save([pinned, textItem("do not keep", at: base)])
        let loaded = store.load()

        #expect(loaded.count == 1)
        #expect(loaded[0].id == pinned.id)
        #expect(loaded[0].preview == .text("keep me"))
        #expect(loaded[0].isPinned)
    }

    @Test("Unpinned entries never reach the disk")
    func unpinnedAreNeverWritten() {
        let (store, fileURL) = makeStore()

        store.save([
            textItem("transient one", at: base),
            textItem("transient two", at: base.addingTimeInterval(1)),
        ])

        // Guarantee 2 in DESIGN 4.2, checked rather than asserted in prose: no file at all.
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        #expect(store.load().isEmpty)
    }

    @Test("Unpinning the last entry removes the file rather than leaving ciphertext behind")
    func emptyingRemovesFile() {
        let (store, fileURL) = makeStore()
        store.save([textItem("pinned", at: base, pinned: true)])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.save([])

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test("A missing file simply means nothing is pinned")
    func missingFileLoadsEmpty() {
        let (store, _) = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test("The file is owner-readable only")
    func filePermissionsAreRestricted() throws {
        let (store, fileURL) = makeStore()
        store.save([textItem("pinned", at: base, pinned: true)])

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.int16Value == 0o600)
    }

    @Test("The written file is ciphertext, not readable content")
    func fileIsEncrypted() throws {
        let (store, fileURL) = makeStore()
        store.save([textItem("very secret pinned text", at: base, pinned: true)])

        let raw = try Data(contentsOf: fileURL)
        #expect(raw.range(of: Data("very secret pinned text".utf8)) == nil)
        #expect(raw.prefix(CryptoBox.magic.count) == CryptoBox.magic)
    }

    @Test("A corrupt file is moved aside and the app starts empty")
    func corruptFileIsQuarantined() throws {
        let (store, fileURL) = makeStore()
        store.save([textItem("pinned", at: base, pinned: true)])

        // Simulate damage: keep the magic so it gets as far as decryption, then break the payload.
        var damaged = try Data(contentsOf: fileURL)
        for index in stride(from: damaged.count - 8, to: damaged.count, by: 1) {
            damaged[index] ^= 0xFF
        }
        try damaged.write(to: fileURL)

        #expect(store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("damaged").path))
    }

    @Test("A file written with a different key is treated as unreadable, not fatal")
    func wrongKeyIsSurvivable() throws {
        let (store, fileURL) = makeStore()
        store.save([textItem("pinned", at: base, pinned: true)])

        let other = PinStore(fileURL: fileURL, key: SymmetricKey(size: .bits256))
        #expect(other.load().isEmpty)
    }

    @Test("Restoring feeds pinned entries back into the history store")
    func restoreIntoHistoryStore() {
        let (store, _) = makeStore()
        store.save([
            textItem("first pin", at: base, pinned: true),
            textItem("second pin", at: base.addingTimeInterval(10), pinned: true),
        ])

        let history = HistoryStore()
        history.restore(pinned: store.load())

        #expect(history.items.count == 2)
        #expect(history.pinnedCount == 2)
        #expect(history.items.first?.preview == .text("second pin"))
    }

    @Test("A pin change is handed to persistence exactly when it happens")
    func historyStoreNotifiesOnPinChanges() {
        let history = HistoryStore()
        let saved = Box<[[ClipItem]]>([])
        history.onPinnedItemsChanged = { saved.value.append($0) }

        history.record(textItem("entry", at: base))
        // A plain capture is not a pin change, so nothing should have been written.
        #expect(saved.value.isEmpty)

        history.togglePin(id: history.items[0].id)
        #expect(saved.value.count == 1)
        #expect(saved.value[0].count == 1)

        history.togglePin(id: history.items[0].id)
        #expect(saved.value.count == 2)
        #expect(saved.value[1].isEmpty)
    }

    @Test("Deleting a pinned entry updates persistence, deleting an unpinned one does not")
    func deleteOnlyNotifiesForPinned() {
        let history = HistoryStore()
        let saved = Box<[[ClipItem]]>([])
        history.record(textItem("unpinned", at: base))
        history.record(textItem("pinned", at: base.addingTimeInterval(1), pinned: true))
        history.onPinnedItemsChanged = { saved.value.append($0) }

        history.delete(id: history.items.first { !$0.isPinned }!.id)
        #expect(saved.value.isEmpty)

        history.delete(id: history.items.first { $0.isPinned }!.id)
        #expect(saved.value.count == 1)
        #expect(saved.value[0].isEmpty)
    }
}
