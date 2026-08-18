//
//  PanelWindow.swift
//  ClipPanel
//

import AppKit
import Carbon.HIToolbox

/// The panel window itself.
///
/// `.nonactivatingPanel` is the load-bearing detail: it lets the panel take keyboard focus
/// for arrow keys and Return WITHOUT activating ClipPanel, so the app the user was typing
/// in stays frontmost and keeps its caret. A borderless NSWindow refuses key status by
/// default, hence the `canBecomeKey` override.
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        // Handled here as well as in cancelOperation because the SwiftUI hosting view sits
        // in front of us in the responder chain and does not always forward Escape.
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}
