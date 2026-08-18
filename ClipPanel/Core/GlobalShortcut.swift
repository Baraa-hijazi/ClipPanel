//
//  GlobalShortcut.swift
//  ClipPanel
//

import Carbon.HIToolbox

/// A system-wide key combination, stored in the Carbon representation that
/// `RegisterEventHotKey` needs, plus a label for display in menus and settings.
nonisolated struct GlobalShortcut: Equatable, Sendable {
    /// Virtual key code, e.g. `kVK_ANSI_V`.
    let keyCode: UInt32
    /// Carbon modifier mask, e.g. `controlKey | cmdKey`.
    let carbonModifiers: UInt32
    /// How the key itself is drawn, e.g. "V". Modifier glyphs are derived.
    let keyLabel: String

    /// Default panel shortcut, the macOS answer to Win+V.
    ///
    /// Not shift-command-V: that is "Paste and Match Style" in most Mac apps.
    /// Not option-command-V: that is "Move Item Here" in Finder.
    static let panelDefault = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyLabel: "V"
    )
}

extension GlobalShortcut: CustomStringConvertible {
    /// Menu-style rendering, e.g. "⌃⌘V". Glyph order matches Apple's convention.
    var description: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }
}
