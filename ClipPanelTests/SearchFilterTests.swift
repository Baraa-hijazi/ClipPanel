//
//  SearchFilterTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Search filter")
struct SearchFilterTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func items() -> [ClipItem] {
        [
            textItem("The quick brown fox", at: base),
            textItem("https://example.com/docs/setup", at: base.addingTimeInterval(1)),
            textItem("café résumé notes", at: base.addingTimeInterval(2)),
        ]
    }

    private func noAppName(_ bundleID: String?) -> String? { nil }

    @Test("An empty or whitespace query returns everything, guarded entries included")
    func emptyQueryReturnsAll() {
        var guarded = textItem("hunter2secret", at: base.addingTimeInterval(3))
        guarded.isGuarded = true
        let all = items() + [guarded]

        #expect(SearchFilter.filter(all, query: "", appName: noAppName).count == 4)
        #expect(SearchFilter.filter(all, query: "   ", appName: noAppName).count == 4)
    }

    @Test("Matching is a case-insensitive substring over the text")
    func caseInsensitiveSubstring() {
        let results = SearchFilter.filter(items(), query: "QUICK", appName: noAppName)
        #expect(results.count == 1)
        #expect(results.first?.preview == .text("The quick brown fox"))
    }

    @Test("Matching ignores diacritics in both directions")
    func diacriticInsensitive() {
        #expect(SearchFilter.filter(items(), query: "cafe", appName: noAppName).count == 1)
        #expect(SearchFilter.filter(items(), query: "résume", appName: noAppName).count == 1)
    }

    @Test("Multiple tokens all have to match (AND, not OR)")
    func multiTokenAnd() {
        #expect(SearchFilter.filter(items(), query: "example docs", appName: noAppName).count == 1)
        #expect(SearchFilter.filter(items(), query: "example fox", appName: noAppName).isEmpty)
    }

    @Test("File entries match on any part of their paths, including folders")
    func filePathsMatch() {
        let url = URL(fileURLWithPath: "/Users/test/Invoices/march-invoice.pdf")
        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.fileURL, data: url.dataRepresentation),
        ]])
        let file = ItemFactory.make(from: snapshot, sourceBundleID: nil)!

        #expect(SearchFilter.filter([file], query: "invoice", appName: noAppName).count == 1)
        #expect(SearchFilter.filter([file], query: "Invoices", appName: noAppName).count == 1)
        #expect(SearchFilter.filter([file], query: "receipt", appName: noAppName).isEmpty)
    }

    @Test("Entries match on the name of the app they came from")
    func appNameMatches() {
        let fromSafari = textItem("some copied line", at: base)
        let results = SearchFilter.filter([fromSafari], query: "safari") { _ in "Safari" }
        #expect(results.count == 1)
    }

    @Test("Image entries are findable by app name but not by imagined content")
    func imagesMatchAppNameOnly() {
        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 20, height: 20)),
        ]])
        let image = ItemFactory.make(from: snapshot, sourceBundleID: "com.apple.Preview")!

        #expect(SearchFilter.filter([image], query: "preview") { _ in "Preview" }.count == 1)
        #expect(SearchFilter.filter([image], query: "anything", appName: noAppName).isEmpty)
    }

    @Test("Guarded entries never match a query, even one equal to their content")
    func guardedEntriesAreExcluded() {
        var guarded = textItem("hunter2secret", at: base)
        guarded.isGuarded = true

        // The oracle this rule prevents: typing a suspected secret and watching whether the
        // masked row survives the filter would confirm the secret without ever revealing it.
        #expect(SearchFilter.filter([guarded], query: "hunter2secret", appName: noAppName).isEmpty)
        #expect(SearchFilter.filter([guarded], query: "hunter", appName: noAppName).isEmpty)
        #expect(SearchFilter.filter([guarded], query: "h", appName: noAppName).isEmpty)
    }

    @Test("Guarded entries are excluded even when the query matches their app, not their content")
    func guardedExcludedByAppNameToo() {
        var guarded = textItem("token-abc", at: base)
        guarded.isGuarded = true

        // Excluding by content but matching by app name would still shrink the visible list in a
        // way that confirms the guarded entry's origin. All or nothing, and it is nothing.
        #expect(SearchFilter.filter([guarded], query: "safari") { _ in "Safari" }.isEmpty)
    }

    @Test("Results keep their original order")
    func orderIsPreserved() {
        let list = [
            textItem("alpha one", at: base),
            textItem("beta", at: base.addingTimeInterval(1)),
            textItem("alpha two", at: base.addingTimeInterval(2)),
        ]
        let results = SearchFilter.filter(list, query: "alpha", appName: noAppName)
        #expect(results.map(\.preview) == [.text("alpha one"), .text("alpha two")])
    }
}
