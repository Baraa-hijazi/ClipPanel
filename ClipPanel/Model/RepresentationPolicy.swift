//
//  RepresentationPolicy.swift
//  ClipPanel
//
//  Which of a pasteboard item's representations get read and stored. Pure, so it is unit
//  testable without a pasteboard.
//
//  Two reasons this exists (REVIEW.md, finding 3). Reading every exotic type forces promised-data
//  resolution in the source app and hoovers private formats we cannot re-render anyway. And a
//  clipboard screenshot carries a multi-megabyte TIFF next to its PNG, which blew the size cap
//  and made screenshots silently uncapturable; storing the PNG alone re-pastes fine everywhere
//  that matters.
//

import Foundation

nonisolated enum RepresentationPolicy {
    /// The types worth reading and keeping, out of everything a pasteboard item declares.
    /// Order is preserved from the item's own declaration order.
    static func typesToStore(from declaredTypes: [String]) -> [String] {
        var kept = declaredTypes.filter { PasteboardTypes.supported.contains($0) }

        // PNG wins over TIFF when both are present. TIFF survives only when it is the sole
        // image representation, because some apps put nothing else on the pasteboard.
        if kept.contains(PasteboardTypes.png) {
            kept.removeAll { $0 == PasteboardTypes.tiff }
        }
        return kept
    }
}
