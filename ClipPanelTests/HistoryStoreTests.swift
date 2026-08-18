//
//  HistoryStoreTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("History store")
@MainActor
struct HistoryStoreTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    @Test("Newest capture goes to the top")
    func newestFirst() {
        let store = HistoryStore()
        store.record(textItem("first", at: base))
        store.record(textItem("second", at: base.addingTimeInterval(1)))

        #expect(store.items.count == 2)
        #expect(store.items.first?.preview == .text("second"))
    }

    @Test("Re-copying existing content moves it up instead of duplicating")
    func dedupMovesToTop() {
        let store = HistoryStore()
        let original = textItem("repeated", at: base)
        store.record(original)
        store.record(textItem("other", at: base.addingTimeInterval(1)))
        store.record(textItem("repeated", at: base.addingTimeInterval(2)))

        #expect(store.items.count == 2)
        #expect(store.items.first?.preview == .text("repeated"))
        // Identity survives, so a pinned entry stays the same entry.
        #expect(store.items.first?.id == original.id)
    }

    @Test("Re-copying a pinned entry keeps it pinned")
    func dedupPreservesPin() {
        let store = HistoryStore()
        store.record(textItem("keep me", at: base, pinned: true))
        store.record(textItem("keep me", at: base.addingTimeInterval(5)))

        #expect(store.items.count == 1)
        #expect(store.items.first?.isPinned == true)
    }

    @Test("Oldest unpinned entry is evicted past the limit")
    func evictsOldest() {
        let store = HistoryStore()
        store.settings.historyLimit = 3

        for index in 0..<4 {
            store.record(textItem("item \(index)", at: base.addingTimeInterval(Double(index))))
        }

        #expect(store.items.count == 3)
        #expect(store.items.map(\.preview).contains(.text("item 0")) == false)
        #expect(store.items.first?.preview == .text("item 3"))
    }

    @Test("Pinned entries are never evicted and do not use up the limit")
    func pinnedSurviveEviction() {
        let store = HistoryStore()
        store.settings.historyLimit = 2

        store.record(textItem("pinned", at: base, pinned: true))
        for index in 0..<5 {
            store.record(textItem("item \(index)", at: base.addingTimeInterval(Double(index + 1))))
        }

        #expect(store.pinnedCount == 1)
        #expect(store.unpinnedCount == 2)
        #expect(store.items.first?.preview == .text("pinned"))
    }

    @Test("Pinned entries sort above unpinned ones")
    func pinnedSortFirst() {
        let store = HistoryStore()
        store.record(textItem("old pinned", at: base, pinned: true))
        store.record(textItem("new unpinned", at: base.addingTimeInterval(100)))

        #expect(store.items.first?.preview == .text("old pinned"))
    }

    @Test("Clear All keeps pinned entries, matching Windows")
    func clearKeepsPinned() {
        let store = HistoryStore()
        store.record(textItem("pinned", at: base, pinned: true))
        store.record(textItem("transient", at: base.addingTimeInterval(1)))

        store.clearUnpinned()

        #expect(store.items.count == 1)
        #expect(store.items.first?.isPinned == true)
    }

    @Test("Toggling a pin moves the entry into the pinned group")
    func togglePinReorders() {
        let store = HistoryStore()
        store.record(textItem("a", at: base))
        let second = textItem("b", at: base.addingTimeInterval(1))
        store.record(second)
        #expect(store.items.first?.preview == .text("b"))

        store.togglePin(id: store.items.last!.id)

        #expect(store.items.first?.preview == .text("a"))
        #expect(store.items.first?.isPinned == true)
    }

    @Test("Deleting removes exactly one entry")
    func deleteRemovesOne() {
        let store = HistoryStore()
        store.record(textItem("a", at: base))
        let target = textItem("b", at: base.addingTimeInterval(1))
        store.record(target)

        store.delete(id: target.id)

        #expect(store.items.count == 1)
        #expect(store.items.first?.preview == .text("a"))
    }

    @Test("Unpinning an entry can trigger eviction")
    func unpinCanEvict() {
        let store = HistoryStore()
        store.settings.historyLimit = 1
        store.record(textItem("pinned", at: base, pinned: true))
        store.record(textItem("newer", at: base.addingTimeInterval(10)))
        #expect(store.items.count == 2)

        store.togglePin(id: store.items.first!.id)

        #expect(store.items.count == 1)
        #expect(store.items.first?.preview == .text("newer"))
    }
}
