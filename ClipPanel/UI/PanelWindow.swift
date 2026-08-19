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
    case toggleReveal
    /// Forward Delete: always removes the selected entry.
    case delete
    /// Backspace: edits the search query when one is active, removes the entry otherwise.
    case deleteBackward
    case typeCharacter(Character)
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

    /// The search field holds focus while the panel is open, which normally means the field
    /// editor consumes every keystroke. The keys that belong to the LIST rather than the text
    /// (arrows, Return, forward delete, Escape) are intercepted here, before dispatch, so the
    /// keyboard model works identically whether or not the field has focus.
    ///
    /// The one exception is input-method composition: while marked text exists (typing Japanese
    /// or Chinese, dead keys), Return confirms the composition and arrows navigate candidates, so
    /// everything passes through untouched until composition ends.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           !isComposingText,
           let command = listCommand(for: event),
           onKeyCommand?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    /// Keys that always mean the list, never the text field. Backspace is deliberately absent:
    /// it edits the query while one is active, so its routing is decided by the field, which
    /// knows the query state.
    private func listCommand(for event: NSEvent) -> PanelKeyCommand? {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            return .moveUp
        case kVK_DownArrow:
            return .moveDown
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return event.modifierFlags.contains(.option) ? .activateAsPlainText : .activate
        case kVK_ForwardDelete:
            return .delete
        case kVK_Escape:
            return .cancel
        default:
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let command = command(for: event), onKeyCommand?(command) == true else {
            super.keyDown(with: event)
            return
        }
    }

    /// Command-modified keys arrive here rather than in `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let command: PanelKeyCommand? = switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": .togglePin
        case "r": .toggleReveal
        default: nil
        }
        guard let command, onKeyCommand?(command) == true else {
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
        case kVK_Delete:
            return .deleteBackward
        case kVK_ForwardDelete:
            return .delete
        case kVK_Escape:
            return .cancel
        case kVK_Tab:
            return nil
        default:
            return typedCharacter(from: event)
        }
    }

    /// Printable keystrokes become search input. Command- and control-modified keys are left for
    /// the responder chain, and the private function-key plane (arrows, F-keys) is filtered out.
    ///
    /// Known limitation, recorded in DESIGN.md: without a real text view there is no input-method
    /// composition, so dead keys and CJK input do not compose here. A follow-up can trade this
    /// simplicity for an NSTextField if that audience needs serving.
    private func typedCharacter(from event: NSEvent) -> PanelKeyCommand? {
        guard !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              let characters = event.charactersIgnoringModifiers,
              let character = characters.first,
              let scalar = character.unicodeScalars.first,
              !(0xF700...0xF8FF).contains(scalar.value),
              scalar.value >= 0x20
        else { return nil }

        if character.isWhitespace, character != " " {
            return nil
        }
        return .typeCharacter(character)
    }
}
