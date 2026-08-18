//
//  SecretDetector.swift
//  ClipPanel
//
//  Heuristic recognition of secrets that arrive WITHOUT the ConcealedType marker, which is most
//  of them: passwords copied from browsers, terminals, chat, and text files (REVIEW.md, part 2).
//
//  A verdict of probablySecret never blocks anything. Detected entries are guarded: masked in the
//  panel, auto-expired, unpinnable without confirmation. False positives therefore cost a masked
//  preview and a shorter life, not data loss, which is what makes shipping a heuristic tolerable.
//
//  Pure and deterministic, so every rule is unit tested against a corpus.
//

import Foundation

nonisolated enum SecretVerdict: Equatable, Sendable {
    case ordinary
    case probablySecret(SecretSignal)
}

/// Why something was flagged, in words the UI could one day show.
nonisolated enum SecretSignal: String, Equatable, Sendable {
    case privateKeyBlock
    case knownTokenShape
    case passwordShape
}

nonisolated enum SecretDetector {
    /// Tokens shorter than this are never flagged. Also the floor most password policies enforce.
    static let minimumLength = 8
    /// Tokens longer than this are prose or data, not credentials.
    static let maximumLength = 128
    /// Score at or above this is a secret. Signals below are worth 1 to 3 points each.
    static let threshold = 3

    static func assess(text: String, sourceBundleID: String?) -> SecretVerdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ordinary }

        // PEM private keys are multi-line and would fail the single-token test, so they go first.
        if trimmed.contains("-----BEGIN"), trimmed.contains("PRIVATE KEY") {
            return .probablySecret(.privateKeyBlock)
        }

        // Everything below reasons about a single token.
        guard !trimmed.contains(where: \.isWhitespace) else { return .ordinary }
        guard (minimumLength...maximumLength).contains(trimmed.count) else { return .ordinary }

        // Exculpatory shapes, checked before the incriminating ones.
        if looksLikeURL(trimmed) || looksLikeEmail(trimmed) { return .ordinary }
        // Git SHAs and content digests: public identifiers, not credentials. Hex-shaped API keys
        // exist but almost always carry a recognisable prefix, which is matched below before this
        // rule can hide them.
        if isKnownTokenShape(trimmed) { return .probablySecret(.knownTokenShape) }
        if looksLikeLowercaseHexDigest(trimmed) { return .ordinary }
        if looksLikeFilenameOrDomain(trimmed) { return .ordinary }

        // Scored password shape.
        var score = 0
        let classes = characterClassCount(in: trimmed)
        if classes >= 3 { score += 2 }
        if classes == 4 { score += 1 }
        if trimmed.count >= 16, shannonEntropyPerCharacter(of: trimmed) > 3.5 { score += 2 }
        if trimmed.count >= 20 { score += 1 }
        // Where passwords actually come from. Only ever worth one point, so context alone can
        // never condemn ordinary text; it breaks ties for borderline shapes.
        if let sourceBundleID, secretProneSources.contains(sourceBundleID) { score += 1 }

        return score >= threshold ? .probablySecret(.passwordShape) : .ordinary
    }

    // MARK: - Known token shapes

    /// Prefixes issuers stamp onto machine credentials. Deliberately conservative: a match also
    /// requires the token to be at least 16 characters, so prose like "sk-learn" cannot trip it.
    private static let knownPrefixes = [
        "AKIA", "ASIA",                                   // AWS access keys
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",
        "sk-", "sk_live_", "sk_test_", "rk_live_",        // OpenAI, Stripe
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "xapp-",      // Slack
        "AIza", "ya29.",                                  // Google
        "glpat-", "npm_", "dop_v1_", "shpat_", "shpss_",
        "figd_", "hf_", "pypi-",
    ]

    private static func isKnownTokenShape(_ token: String) -> Bool {
        if token.count >= 16, knownPrefixes.contains(where: { token.hasPrefix($0) }) {
            return true
        }
        // JWT: three dot-separated base64url segments, header starting with eyJ ("{" encoded).
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        if segments.count == 3, token.hasPrefix("eyJ"), segments.allSatisfy({ !$0.isEmpty }) {
            return true
        }
        return false
    }

    // MARK: - Exculpatory shapes

    private static func looksLikeURL(_ token: String) -> Bool {
        guard let components = URLComponents(string: token) else { return false }
        return components.scheme != nil && components.host != nil
    }

    private static func looksLikeEmail(_ token: String) -> Bool {
        token.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,
                    options: .regularExpression) != nil
    }

    private static func looksLikeLowercaseHexDigest(_ token: String) -> Bool {
        (7...64).contains(token.count)
            && token.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }

    /// "backup_v2.tar.gz", "example.com": word characters and separators ending in a short
    /// alphanumeric extension, with no symbols beyond dot, dash, and underscore.
    private static func looksLikeFilenameOrDomain(_ token: String) -> Bool {
        token.range(of: #"^[A-Za-z0-9._-]+\.[A-Za-z0-9]{1,6}$"#,
                    options: .regularExpression) != nil
    }

    // MARK: - Scoring inputs

    private static func characterClassCount(in token: String) -> Int {
        var lower = false, upper = false, digit = false, symbol = false
        for character in token {
            if character.isLowercase { lower = true }
            else if character.isUppercase { upper = true }
            else if character.isNumber { digit = true }
            else { symbol = true }
        }
        return [lower, upper, digit, symbol].count(where: { $0 })
    }

    static func shannonEntropyPerCharacter(of token: String) -> Double {
        guard !token.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for character in token { counts[character, default: 0] += 1 }

        let length = Double(token.count)
        return counts.values.reduce(0) { entropy, count in
            let probability = Double(count) / length
            return entropy - probability * log2(probability)
        }
    }

    /// Apps whose copies skew toward credentials: browsers (password fields, token dashboards)
    /// and terminals (env vars, key files). Worth one tie-breaking point, never a verdict.
    static let secretProneSources: Set<String> = [
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
    ]
}
