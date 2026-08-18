//
//  PanelWindow.swift
//  ClipPanel
//

import AppKit
import Carbon.HIToolbox

/// Keyboard commands the panel understands, per DESIGN 8.
enum PanelKeyCommand: Equatable {
    case moveUp
    case moveDown
    case activate
    case activateAsPlainText
    case togglePin
    case delete
    case cancel
}

/// The panel window itself.
///
/// `.nonactivatingPanel` is the load-bearing detail: it lets the panel take keyboard focus for
/// arrow keys and Return WITHOUT activating ClipPanel, so the app the user was typing in stays
/// frontmost and keeps its caret. A borderless NSWindow refuses key status by default, hence the
/// `canBecomeKey` override.
///
/// Keys are handled here rather than with SwiftUI's `onKeyPress` because the panel is the key
/// window and AppKit's responder chain is the reliable place to catch Escape, Return, and the
/// arrows before the hosting view has an opinion about them.
final class PanelWindow: NSPanel {
    /// Returns true when the command was consumed.
    var onKeyCommand: ((PanelKeyCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        _ = onKeyCommand?(.cancel)
    }

    override func keyDown(with event: NSEvent) {
        guard let command = command(for: event), onKeyCommand?(command) == true else {
            super.keyDown(with: event)
            return
        }
    }

    /// Command-modified keys arrive here rather than in `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "p",
              onKeyCommand?(.togglePin) == true
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func command(for event: NSEvent) -> PanelKeyCommand? {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            return .moveUp
        case kVK_DownArrow:
            return .moveDown
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return event.modifierFlags.contains(.option) ? .activateAsPlainText : .activate
        case kVK_Delete, kVK_ForwardDelete:
            return .delete
        case kVK_Escape:
            return .cancel
        default:
            return nil
        }
    }
}
