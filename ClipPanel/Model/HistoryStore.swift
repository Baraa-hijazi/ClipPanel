//
//  HistoryStore.swift
//  ClipPanel
//
//  Deviates from DESIGN 5, which specified a Swift actor, in favour of an @Observable
//  main-actor class. Reasons: the store is 25 small entries mutated only from the monitor and
//  the panel (both main-actor already), so an actor would add async hops and a manual
//  observation bridge for zero contention benefit. The expensive part of capture (hashing and
//  thumbnailing) lives in ItemFactory, which is nonisolated and can be moved off the main
//  actor independently if profiling ever asks for it.
//
//  Guarantee 2 (DESIGN 4.2) lives here: unpinned entries exist ONLY in this array. Nothing in
//  this file writes to disk, and nothing may be added that does. Pinned entries reach disk
//  through PinStore in M5, encrypted.
//

import Foundation
import Observation
import OSLog

@Observable
final class HistoryStore {
    /// Pinned entries first, then unpinned, each group newest first.
    private(set) var items: [ClipItem] = []

    var settings = CaptureSettings()

    /// Display preference rather than a capture rule, which is why it lives here and not in
    /// CaptureSettings (that struct feeds the pure capture logic).
    var showSourceAppCaptions = true

    /// Called whenever the pinned set changes, so persistence stays somebody else's problem.
    /// Nil means nothing is persisted, which is how the tests and previews run.
    @ObservationIgnored
    var onPinnedItemsChanged: (([ClipItem]) -> Void)?

    var isEmpty: Bool { items.isEmpty }
    var pinnedCount: Int { items.count { $0.isPinned } }
    var unpinnedCount: Int { items.count { !$0.isPinned } }

    /// Seeds the pinned entries restored from disk at launch, ahead of any capture.
    func restore(pinned items: [ClipItem]) {
        for item in items where item.isPinned {
            insert(item)
        }
        Log.app.debug("Restored \(items.count) pinned entries")
    }

    /// Records a capture. A re-copy of existing content moves that entry back to the top of
    /// its group and keeps its pin state and identity, which is what Windows does.
    @discardableResult
    func record(_ item: ClipItem) -> ClipItem {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.createdAt = item.createdAt
            insert(existing)
            return existing
        }

        insert(item)
        evictIfNeeded()
        return item
    }

    func togglePin(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.isPinned.toggle()
        insert(item)
        // Unpinning can push the list back over the limit.
        evictIfNeeded()
        pinnedItemsChanged()
    }

    func delete(id: ClipItem.ID) {
        let wasPinned = items.first { $0.id == id }?.isPinned ?? false
        items.removeAll { $0.id == id }
        if wasPinned { pinnedItemsChanged() }
    }

    /// Clear All, matching Windows: pinned entries survive.
    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
    }

    /// Used by the lock-screen path in M6, and by tests. Clears the persisted pins too, because
    /// "forget everything" that leaves a file behind is not forgetting.
    func removeEverything() {
        let hadPinned = pinnedCount > 0
        items.removeAll()
        if hadPinned { pinnedItemsChanged() }
    }

    /// Applies the current limit right now, for when the user lowers it in Settings.
    func enforceLimit() {
        evictIfNeeded()
    }

    /// Removes entries whose time is up: guarded entries past the guarded lifetime, and, when the
    /// global lifetime is on, any unpinned entry past that. Pins never expire; pinning is the
    /// user's explicit "keep this". Returns how many were removed so callers know whether the
    /// panel needs resizing.
    @discardableResult
    func sweepExpired(now: Date = Date()) -> Int {
        let before = items.count
        items.removeAll { item in
            guard !item.isPinned else { return false }
            let age = now.timeIntervalSince(item.createdAt)
            if settings.isGuarded(item), settings.guardedLifetime > 0, age > settings.guardedLifetime {
                return true
            }
            if settings.historyLifetime > 0, age > settings.historyLifetime {
                return true
            }
            return false
        }
        let removed = before - items.count
        if removed > 0 {
            Log.app.debug("Expired \(removed) entries")
        }
        return removed
    }

    private func pinnedItemsChanged() {
        onPinnedItemsChanged?(items.filter(\.isPinned))
    }

    // MARK: - Private

    private func insert(_ item: ClipItem) {
        let insertionPoint = items.firstIndex { candidate in
            if item.isPinned {
                // Ahead of older pinned entries, and ahead of every unpinned one.
                return !candidate.isPinned || candidate.createdAt <= item.createdAt
            }
            // Behind every pinned entry, ahead of older unpinned ones.
            return !candidate.isPinned && candidate.createdAt <= item.createdAt
        }

        items.insert(item, at: insertionPoint ?? items.count)
    }

    /// Both limits apply to unpinned entries only. Pinning is the user saying "keep this", so
    /// pins are never evicted to make room. The byte budget always spares the newest unpinned
    /// entry: evicting the thing that was just captured to satisfy the budget would make large
    /// screenshots silently uncapturable again, which is the bug the image cap exists to fix.
    private func evictIfNeeded() {
        while unpinnedCount > settings.historyLimit {
            guard let oldest = items.lastIndex(where: { !$0.isPinned }) else { return }
            items.remove(at: oldest)
        }
        while unpinnedCount > 1, unpinnedBytes > settings.maxTotalBytes {
            guard let oldest = items.lastIndex(where: { !$0.isPinned }) else { return }
            items.remove(at: oldest)
        }
    }

    private var unpinnedBytes: Int {
        items.reduce(0) { $0 + ($1.isPinned ? 0 : $1.byteSize) }
    }
}
