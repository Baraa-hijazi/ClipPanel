//
//  KeychainKey.swift
//  ClipPanel
//
//  The AES key for the pinned-entry file, kept in the login keychain rather than in a file beside
//  the data it protects.
//
//  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is the important attribute: ThisDeviceOnly keeps
//  the key out of iCloud Keychain and out of any backup that would carry it to another machine, and
//  WhenUnlocked means a locked Mac cannot be made to hand it over. Consequence, by design: pinned
//  entries do not migrate between machines. That is the correct trade for a clipboard history.
//

import CryptoKit
import Foundation
import OSLog
import Security

nonisolated enum KeychainKey {
    private static let service = "com.baraahijazi.ClipPanel"
    private static let account = "pinned-entries-key"
    private static let keyByteCount = 32

    enum Failure: Error, Equatable {
        case keychainError(OSStatus)
        case unexpectedKeySize(Int)
    }

    /// Returns the existing key, creating and storing one on first use.
    static func loadOrCreate() throws -> SymmetricKey {
        if let existing = try load() {
            return existing
        }
        return try create()
    }

    static func load() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw Failure.keychainError(status) }
            guard data.count == keyByteCount else { throw Failure.unexpectedKeySize(data.count) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychainError(status)
        }
    }

    @discardableResult
    static func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychainError(status) }

        Log.pins.info("Created a new pinned-entries key")
        return key
    }

    /// Used when the user asks to forget everything. Removing the key makes any surviving ciphertext
    /// permanently unreadable, which is the point.
    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychainError(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
