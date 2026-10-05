//
//  SecretDetectorTests.swift
//  ClipPanelTests
//
//  The detector is a heuristic, so these tests ARE the specification: the corpus below defines
//  what gets flagged and what does not. Change the rules, update the corpus, knowingly.
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Secret detector")
struct SecretDetectorTests {
    private func isSecret(_ text: String, from source: String? = "com.apple.finder") -> Bool {
        if case .probablySecret = SecretDetector.assess(text: text, sourceBundleID: source) {
            return true
        }
        return false
    }

    // MARK: - True positives

    // Every fixture is assembled at runtime from a split prefix, on purpose: these are fake, but
    // they are realistic enough that GitHub's push protection (and any other secret scanner
    // reading this repository) matches them as live credentials when they appear contiguously in
    // source. The VALUES the detector sees are unchanged. Do not "simplify" them back into single
    // literals; the first push of this repository was blocked for exactly that.
    //
    // Held in an explicitly typed static rather than inline in the macro: Xcode 27's type checker
    // times out on seven string concatenations inside an untyped array literal in @Test arguments.
    nonisolated static let knownTokenFixtures: [String] = [
        "AKIA" + "IOSFODNN7EXAMPLE",                            // AWS access key id
        "ghp_" + "16C7e42F292c6912E7710c838347Ae178B4a",        // GitHub personal access token
        "sk-proj-" + "AbCdEfGhIjKlMnOpQrStUvWx",                // OpenAI style
        "xoxb-" + "1234567890-abcdefghijklmnop",                // Slack bot token
        "AIzaSy" + "D4iE2xVSpqzLE7KqBnE3f8W3mhrpV1BXY",         // Google API key
        "glpat-" + "XyZ123AbC456DeF789Gh",                      // GitLab
        "eyJhbGciOiJIUzI1NiJ9" + ".eyJzdWIiOiIxIn0.dQw4w9WgXcQ", // JWT
    ]

    @Test("Known token shapes are flagged", arguments: knownTokenFixtures)
    func knownTokensFlagged(token: String) {
        #expect(SecretDetector.assess(text: token, sourceBundleID: nil)
                == .probablySecret(.knownTokenShape))
    }

    @Test("A PEM private key block is flagged despite being multi-line")
    func pemBlockFlagged() {
        let pem = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        -----END OPENSSH PRIVATE KEY-----
        """
        #expect(SecretDetector.assess(text: pem, sourceBundleID: nil)
                == .probablySecret(.privateKeyBlock))
    }

    @Test("Password-shaped tokens are flagged", arguments: [
        "P@ssw0rd!",                     // 4 character classes
        "Tr0ub4dor&3",                   // the classic
        "correct-Horse-Battery-99!",     // long, 4 classes
        "9k#mQ2$vLx8@pR5z",              // generated password
    ])
    func passwordShapesFlagged(password: String) {
        #expect(isSecret(password))
    }

    @Test("A borderline shape tips over when copied from a browser")
    func browserContextBreaksTies() {
        // Three classes, short, low entropy: 2 points, ordinary on its own.
        #expect(isSecret("Hello123", from: "com.apple.finder") == false)
        // The same token from Safari gets the context point and crosses the threshold.
        #expect(isSecret("Hello123", from: "com.apple.Safari"))
    }

    // MARK: - True negatives

    @Test("Ordinary content is not flagged", arguments: [
        "hello world this is a sentence",
        "meeting notes for tuesday",
        "https://example.com/some/long/path?query=value&more=1",
        "user@example.com",
        "d670460b4b4aece5915caf5c68d12f560a9fe3e4",   // git SHA
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", // sha256 digest
        "backup_v2.tar.gz",                            // filename
        "example.com",                                 // bare domain
        "short1!",                                     // under the length floor
        "aaaaaaaaaaaaaaaaaaaaaaaa",                    // long but one class, no entropy
        "1234567890123456",                            // digits only
    ])
    func ordinaryContentPasses(text: String) {
        #expect(isSecret(text) == false)
    }

    @Test("Terminal context alone cannot condemn ordinary text")
    func contextAloneIsNotEnough() {
        #expect(isSecret("meeting notes for tuesday", from: "com.apple.Terminal") == false)
        #expect(isSecret("filename_v2.txt", from: "com.apple.Terminal") == false)
    }

    @Test("sk-learn style prose is not mistaken for a token prefix")
    func shortPrefixLookalikesPass() {
        #expect(isSecret("sk-learn12") == false)
    }

    @Test("Entropy is computed sanely")
    func entropyBasics() {
        #expect(SecretDetector.shannonEntropyPerCharacter(of: "aaaa") == 0)
        #expect(SecretDetector.shannonEntropyPerCharacter(of: "") == 0)
        let high = SecretDetector.shannonEntropyPerCharacter(of: "9k#mQ2$vLx8@pR5zWn3&")
        #expect(high > 3.5)
    }
}
