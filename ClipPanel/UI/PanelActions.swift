//
//  PanelActions.swift
//  ClipPanel
//

import Foundation

/// What the panel can do, injected as closures so the views stay unaware of the store, the
/// pasteboard, and the window.
struct PanelActions {
    var activate: (ClipItem) -> Void
    var activateAsPlainText: (ClipItem) -> Void
    var togglePin: (ClipItem.ID) -> Void
    var delete: (ClipItem.ID) -> Void
    var clearAll: () -> Void
    var close: () -> Void

    static let inert = PanelActions(
        activate: { _ in },
        activateAsPlainText: { _ in },
        togglePin: { _ in },
        delete: { _ in },
        clearAll: {},
        close: {}
    )
}
