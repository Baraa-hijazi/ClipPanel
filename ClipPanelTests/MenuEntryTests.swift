//
//  MenuEntryTests.swift
//  ClipPanelTests
//
//  Recent entries in the menu bar menu (PLAN.md Item 7).
//

import AppKit
import Foundation
import Testing

@testable import ClipPanel

@Suite("Menu entries")
@MainActor
struct MenuEntryTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - One-line formatting

    @Test("Short single-line text is shown as is")
    func shortText() {
        #expect(MenuEntryFormatter.oneLine("hello world") == "hello world")
    }

    @Test("Long text is truncated to the cap with an ellipsis")
    func longTextTruncated() {
        let long = String(repeating: "a", count: 200)
        let line = MenuEntryFormatter.oneLine(long)
        #expect(line.count == MenuEntryFormatter.maxCharacters)
        #expect(line.hasSuffix("…"))
    }

    @Test("Only the first non-empty line is used, and continuation is marked")
    func firstLineOnly() {
        let line = MenuEntryFormatter.oneLine("\n\n  first line  \nsecond line")
        #expect(line == "first line …")
    }

    @Test("Whitespace runs collapse to single spaces")
    func whitespaceCondensed() {
        #expect(MenuEntryFormatter.oneLine("a  \t  b") == "a b")
    }

    @Test("Blank text gets a placeholder rather than an empty menu item")
    func blankText() {
        #expect(MenuEntryFormatter.oneLine(" \n \t ") == "(blank)")
    }

    // MARK: - Labels

    @Test("Text entries get a text symbol and their first line")
    func textLabel() {
        let label = MenuEntryFormatter.label(for: textItem("copied words", at: base), guarded: false)
        #expect(label == MenuEntryLabel(title: "copied words", symbol: "doc.plaintext"))
    }

    @Test("Image entries say so, with dimensions")
    func imageLabel() {
        let snapshot = PasteboardSnapshot(items: [[
            ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 30, height: 20)),
        ]])
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!
        let label = MenuEntryFormatter.label(for: item, guarded: false)
        #expect(label == MenuEntryLabel(title: "Image, 30 x 20", symbol: "photo"))
    }

    @Test("File entries show the first name and how many more")
    func filesLabel() {
        let urls = ["/tmp/one.txt", "/tmp/two.txt", "/tmp/three.txt"].map { URL(fileURLWithPath: $0) }
        let snapshot = PasteboardSnapshot(items: urls.map {
            [ClipItem.Representation(type: PasteboardTypes.fileURL, data: $0.dataRepresentation)]
        })
        let item = ItemFactory.make(from: snapshot, sourceBundleID: nil)!
        let label = MenuEntryFormatter.label(for: item, guarded: false)
        #expect(label == MenuEntryLabel(title: "one.txt and 2 more", symbol: "doc"))
    }

    @Test("A pinned entry shows the pin in the icon slot")
    func pinnedLabel() {
        let label = MenuEntryFormatter.label(for: textItem("kept", at: base, pinned: true), guarded: false)
        #expect(label.symbol == "pin.fill")
        #expect(label.title == "kept")
    }

    @Test("A guarded entry is masked, and its content never reaches the label")
    func guardedLabelMasked() {
        var item = textItem("P@ssw0rd!2024", at: base)
        item.isGuarded = true
        let label = MenuEntryFormatter.label(for: item, guarded: true)

        #expect(label == MenuEntryLabel(title: MenuEntryFormatter.maskedTitle, symbol: "shield.fill"))
        #expect(!label.title.contains("P@ss"))
    }

    @Test("With the guard off, a flagged entry is labelled like any other")
    func flaggedButGuardOff() {
        var item = textItem("P@ssw0rd!2024", at: base)
        item.isGuarded = true
        let label = MenuEntryFormatter.label(for: item, guarded: false)
        #expect(label.title == "P@ssw0rd!2024")
    }

    // MARK: - Selection of entries

    @Test("The menu lists the history's own order, capped at the limit")
    func recentEntriesCapped() {
        let items = (0..<12).map { textItem("entry \($0)", at: base.addingTimeInterval(Double($0))) }

        #expect(MenuEntryFormatter.recentEntries(from: items, limit: 8).map(\.id) == items.prefix(8).map(\.id))
        #expect(MenuEntryFormatter.recentEntries(from: items, limit: 0).isEmpty)
        #expect(MenuEntryFormatter.recentEntries(from: Array(items.prefix(3)), limit: 8).count == 3)
        #expect(MenuEntryFormatter.recentEntries(from: items, limit: -5).isEmpty)
    }

    // MARK: - Preference

    @Test("The count defaults to 8, round trips, and is clamped to 0 through 12")
    func preferenceRoundTrip() {
        let key = "recentEntriesInMenu"
        let saved = AppPreferences.defaults.object(forKey: key)
        defer {
            if let saved { AppPreferences.defaults.set(saved, forKey: key) }
            else { AppPreferences.defaults.removeObject(forKey: key) }
        }

        AppPreferences.defaults.removeObject(forKey: key)
        #expect(AppPreferences.recentEntriesInMenu == 8)

        AppPreferences.recentEntriesInMenu = 5
        #expect(AppPreferences.recentEntriesInMenu == 5)

        AppPreferences.defaults.set(99, forKey: key)
        #expect(AppPreferences.recentEntriesInMenu == 12)
    }

    // MARK: - Paste path

    @Test("Picking an entry from the menu writes it through the shared paste path")
    func menuPickReachesInjector() async throws {
        let pasteboard = FakePasteboard()
        let coordinator = AppCoordinator(
            pasteboard: pasteboard,
            keystrokes: FakeKeystrokeSender(),
            authenticator: FakeAuthenticator()
        )
        let item = textItem("from the menu", at: base)
        coordinator.store.record(item)

        coordinator.pasteFromMenu(item)

        // pasteFromMenu hands off to a task; wait briefly for it rather than sleeping a fixed time.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while pasteboard.writes.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(pasteboard.writes.count == 1)
        let written = pasteboard.writes.first?.flatMap { $0 }.first { $0.type == PasteboardTypes.plainText }
        #expect(written.flatMap { String(data: $0.data, encoding: .utf8) } == "from the menu")
    }
}
