//
//  CryptoBox.swift
//  ClipPanel
//
//  AES-256-GCM sealing for the pinned-entry file (DESIGN 4.2, guarantee 3).
//
//  GCM rather than CBC or raw encryption on purpose: it authenticates as well as encrypts, so a
//  file that has been tampered with fails to open rather than decrypting into plausible rubbish.
//  Nonces come from CryptoKit per seal and are stored with the ciphertext, which is what
//  AES.GCM.SealedBox.combined gives us.
//

import CryptoKit
import Foundation

nonisolated enum CryptoBox {
    /// File magic, so a truncated or unrelated file is rejected before we try to decrypt it.
    static let magic = Data("CLIPPIN1".utf8)
    /// Bumped if the payload layout ever changes, so an old file can be recognised and migrated
    /// rather than misread.
    static let formatVersion: UInt8 = 1

    enum Failure: Error, Equatable {
        case notOurFile
        case unsupportedVersion(UInt8)
        case couldNotDecrypt
        case couldNotDecode
    }

    /// magic + version byte + AES-GCM sealed box.
    static func seal<Value: Encodable>(_ value: Value, using key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: key)

        var output = magic
        output.append(formatVersion)
        output.append(sealed.combined ?? Data())
        return output
    }

    static func open<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        using key: SymmetricKey
    ) throws -> Value {
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw Failure.notOurFile
        }

        let version = data[data.startIndex + magic.count]
        guard version == formatVersion else {
            throw Failure.unsupportedVersion(version)
        }

        let ciphertext = data.dropFirst(magic.count + 1)
        let plaintext: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            plaintext = try AES.GCM.open(sealed, using: key)
        } catch {
            // Wrong key, or the bytes were altered. GCM cannot tell us which, and it does not
            // matter: either way we must not trust the contents.
            throw Failure.couldNotDecrypt
        }

        do {
            return try JSONDecoder().decode(type, from: plaintext)
        } catch {
            throw Failure.couldNotDecode
        }
    }
}
