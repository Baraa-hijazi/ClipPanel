//
//  CryptoBoxTests.swift
//  ClipPanelTests
//

import CryptoKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Crypto box")
struct CryptoBoxTests {
    private let key = SymmetricKey(size: .bits256)

    @Test("Sealed data round trips")
    func roundTrip() throws {
        let original = ["one", "two", "three"]
        let sealed = try CryptoBox.seal(original, using: key)

        #expect(try CryptoBox.open([String].self, from: sealed, using: key) == original)
    }

    @Test("The plaintext is genuinely not present in the sealed bytes")
    func plaintextIsNotRecoverable() throws {
        let secret = "correct-horse-battery-staple"
        let sealed = try CryptoBox.seal([secret], using: key)

        // The cheapest possible check that this is encryption and not encoding.
        #expect(sealed.range(of: Data(secret.utf8)) == nil)
    }

    @Test("A different key cannot open it")
    func wrongKeyIsRejected() throws {
        let sealed = try CryptoBox.seal(["secret"], using: key)
        let other = SymmetricKey(size: .bits256)

        #expect(throws: CryptoBox.Failure.couldNotDecrypt) {
            try CryptoBox.open([String].self, from: sealed, using: other)
        }
    }

    @Test("Tampered ciphertext is rejected rather than decrypted into rubbish")
    func tamperingIsDetected() throws {
        var sealed = try CryptoBox.seal(["secret"], using: key)

        // Flip one bit somewhere in the ciphertext. GCM authenticates, so this must fail loudly.
        let target = sealed.index(sealed.endIndex, offsetBy: -4)
        sealed[target] ^= 0x01

        #expect(throws: CryptoBox.Failure.couldNotDecrypt) {
            try CryptoBox.open([String].self, from: sealed, using: key)
        }
    }

    @Test("A file that is not ours is rejected before any decryption is attempted")
    func foreignFileIsRejected() {
        let junk = Data("this is not a ClipPanel file, it is a text file".utf8)

        #expect(throws: CryptoBox.Failure.notOurFile) {
            try CryptoBox.open([String].self, from: junk, using: key)
        }
    }

    @Test("An empty file is rejected")
    func emptyFileIsRejected() {
        #expect(throws: CryptoBox.Failure.notOurFile) {
            try CryptoBox.open([String].self, from: Data(), using: key)
        }
    }

    @Test("An unknown format version is reported rather than misread")
    func futureVersionIsReported() throws {
        var sealed = try CryptoBox.seal(["secret"], using: key)
        sealed[sealed.startIndex + CryptoBox.magic.count] = 99

        #expect(throws: CryptoBox.Failure.unsupportedVersion(99)) {
            try CryptoBox.open([String].self, from: sealed, using: key)
        }
    }

    @Test("Each seal uses a fresh nonce, so identical input gives different bytes")
    func noncesAreUnique() throws {
        let first = try CryptoBox.seal(["same"], using: key)
        let second = try CryptoBox.seal(["same"], using: key)

        #expect(first != second)
        #expect(try CryptoBox.open([String].self, from: first, using: key) == ["same"])
        #expect(try CryptoBox.open([String].self, from: second, using: key) == ["same"])
    }

    @Test("A full clip item survives the round trip with its payloads intact")
    func clipItemRoundTrip() throws {
        let item = textItem("pinned content", at: Date(timeIntervalSince1970: 12345), pinned: true)
        let sealed = try CryptoBox.seal([item], using: key)

        let restored = try CryptoBox.open([ClipItem].self, from: sealed, using: key)
        #expect(restored.count == 1)
        #expect(restored[0].id == item.id)
        #expect(restored[0].preview == item.preview)
        #expect(restored[0].items == item.items)
        #expect(restored[0].contentHash == item.contentHash)
    }
}
