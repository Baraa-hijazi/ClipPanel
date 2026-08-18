//
//  PinStore.swift
//  ClipPanel
//
//  The only part of this app that writes clipboard content to disk, and it writes ciphertext.
//
//  Guarantee 2 (DESIGN 4.2) depends on this file staying narrow: it persists PINNED entries only.
//  Unpinned history lives in memory and dies with the process, which is both stronger than Windows
//  and the reason "clear on restart" needs no code.
//

import CryptoKit
import Foundation
import OSLog

final class PinStore {
    private let fileURL: URL
    private let key: SymmetricKey
    private let fileManager: FileManager

    init(fileURL: URL, key: SymmetricKey, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.key = key
        self.fileManager = fileManager
    }

    /// Default location, `~/Library/Application Support/ClipPanel/pins.enc`.
    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("ClipPanel", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pins.enc", isDirectory: false)
    }

    /// Reads the pinned entries. A missing file is normal (nothing pinned yet). A corrupt or
    /// undecryptable file is moved aside and treated as empty, because refusing to launch over a
    /// damaged cache would be worse than losing pins the user can re-pin.
    func load() -> [ClipItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let items = try CryptoBox.open([ClipItem].self, from: data, using: key)
            Log.pins.info("Loaded \(items.count) pinned entries")
            // Anything in this file is pinned by definition; do not trust a stale flag.
            return items.map { item in
                var item = item
                item.isPinned = true
                return item
            }
        } catch {
            Log.pins.error("Could not read pinned entries: \(String(describing: error), privacy: .public)")
            quarantineDamagedFile()
            return []
        }
    }

    /// Rewrites the whole file. Called on every pin change: the data is at most a handful of entries,
    /// so there is no reason to be cleverer than this.
    func save(_ items: [ClipItem]) {
        let pinned = items.filter(\.isPinned)

        do {
            guard !pinned.isEmpty else {
                try removeFile()
                Log.pins.info("No pinned entries left; removed the file")
                return
            }

            let sealed = try CryptoBox.seal(pinned, using: key)
            // .atomic so a crash mid-write cannot leave a half-written file where the pins were.
            try sealed.write(to: fileURL, options: [.atomic])
            try restrictPermissions()
            Log.pins.info("Saved \(pinned.count) pinned entries, \(sealed.count) bytes of ciphertext")
        } catch {
            Log.pins.error("Could not save pinned entries: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeFile() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    /// Owner read and write only. Belt to the encryption's braces.
    private func restrictPermissions() throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func quarantineDamagedFile() {
        let damaged = fileURL.appendingPathExtension("damaged")
        try? fileManager.removeItem(at: damaged)
        do {
            try fileManager.moveItem(at: fileURL, to: damaged)
            Log.pins.error("Moved the unreadable file aside; starting with no pinned entries")
        } catch {
            // If it cannot even be moved, remove it: leaving it in place would fail the same way on
            // every launch.
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
