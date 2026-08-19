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
    var toggleReveal: (ClipItem.ID) -> Void
    var delete: (ClipItem.ID) -> Void
    var clearAll: () -> Void
    var close: () -> Void
    /// Called when the search field edits the query, so the controller can move selection to the
    /// first match and resize the panel. Idempotent on the controller side, because keyboard
    /// commands report the same change through their own path.
    var queryDidChange: () -> Void
    /// Routes a keyboard command from the focused search field back into the panel's normal key
    /// handling. Returns true when consumed, so the field knows whether to keep the event.
    var handleKey: (PanelKeyCommand) -> Bool

    static let inert = PanelActions(
        activate: { _ in },
        activateAsPlainText: { _ in },
        togglePin: { _ in },
        toggleReveal: { _ in },
        delete: { _ in },
        clearAll: {},
        close: {},
        queryDidChange: {},
        handleKey: { _ in false }
    )
}
