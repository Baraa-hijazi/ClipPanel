//
//  PasteboardSnapshot.swift
//  ClipPanel
//

import Foundation

/// A read of the pasteboard's payloads, decoupled from NSPasteboard so the capture pipeline
/// can be driven by a fake in tests.
nonisolated struct PasteboardSnapshot: Sendable, Equatable {
    /// One entry per pasteboard item.
    var items: [[ClipItem.Representation]]
    /// True when reading stopped early because the running total passed the size cap. The
    /// partial read is then discarded, which keeps a pathological 500 MB copy from being
    /// pulled into memory just to be measured and thrown away.
    var exceededReadLimit: Bool
    /// Every type the pasteboard DECLARED at read time, before representation slimming. The
    /// post-read marker check runs against this, because markers are deliberately never stored
    /// and would be invisible in `items`.
    var observedTypes: Set<String>

    init(
        items: [[ClipItem.Representation]],
        exceededReadLimit: Bool = false,
        observedTypes: Set<String>? = nil
    ) {
        self.items = items
        self.exceededReadLimit = exceededReadLimit
        self.observedTypes = observedTypes ?? Set(items.flatMap { $0.map(\.type) })
    }

    var byteSize: Int {
        items.reduce(0) { total, item in
            total + item.reduce(0) { $0 + $1.data.count }
        }
    }

    var allTypes: Set<String> {
        Set(items.flatMap { $0.map(\.type) })
    }

    var isEmpty: Bool {
        items.allSatisfy(\.isEmpty)
    }
}
