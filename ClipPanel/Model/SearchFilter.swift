//
//  SearchFilter.swift
//  ClipPanel
//
//  Type-to-filter over the history. Pure functions, so the matching rules are unit-testable
//  without a panel on screen.
//
//  One rule here is a security decision, not a UX one: guarded entries never participate in a
//  search. Their previews are masked, so matching on their CONTENT would turn the search box into
//  a confirmation oracle: type a password you suspect, watch whether the masked row survives the
//  filter, repeat. Excluding them entirely leaks nothing. The cost is that a guarded entry cannot
//  be found by searching, which is the point.
//

import Foundation

nonisolated enum SearchFilter {
    /// Splits a query into whitespace-separated tokens. Every token must match somewhere in an
    /// entry (AND semantics), so "safari http" finds the link copied from Safari.
    static func tokens(from query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Entries matching `query`, in their original order. An empty or whitespace-only query
    /// returns everything, guarded entries included: they are only hidden while a search is
    /// actually narrowing things down.
    ///
    /// `excludingGuarded` is the Secret Guard switch. The exclusion exists only because guarded
    /// previews are masked; with the guard off nothing is masked, a filter surviving a row reveals
    /// nothing the row itself does not already show, and so there is no oracle to prevent.
    static func filter(
        _ items: [ClipItem],
        query: String,
        excludingGuarded: Bool = true,
        appName: (String?) -> String?
    ) -> [ClipItem] {
        let tokens = tokens(from: query)
        guard !tokens.isEmpty else { return items }

        return items.filter { item in
            guard !(excludingGuarded && item.isGuarded) else { return false }
            return matches(item, tokens: tokens, appName: appName(item.sourceBundleID))
        }
    }

    /// Case- and diacritic-insensitive substring match against everything a user could reasonably
    /// mean: the text preview, file paths (the whole path, so folder names count), and the name of
    /// the app the entry came from. Image entries are findable by app name only.
    static func matches(_ item: ClipItem, tokens: [String], appName: String?) -> Bool {
        var haystacks: [String] = []
        switch item.preview {
        case .text(let string):
            haystacks.append(string)
        case .files(let paths):
            haystacks.append(contentsOf: paths)
        case .image:
            break
        }
        if let appName {
            haystacks.append(appName)
        }

        return tokens.allSatisfy { token in
            haystacks.contains {
                $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
