//
//  PasteInjector.swift
//  ClipPanel
//
//  Puts a history entry back on the pasteboard.
//
//  M3 implements the copy half, which is also the degraded mode the design promises when
//  Accessibility is not granted (DESIGN 5, 6.2): the entry becomes the current clipboard and the
//  user presses command-V themselves. M4 adds the synthetic keystroke on top, which is the part
//  that needs the permission, and which must hand focus back to the recorded app first
//  (DESIGN 6.7).
//

import AppKit
import OSLog

final class PasteInjector {
    private let writer: any PasteboardWriting
    /// Called straight after a successful write so the monitor can recognise our own change and
    /// not capture it back as a new entry.
    private let didWrite: () -> Void

    init(writer: any PasteboardWriting, didWrite: @escaping () -> Void) {
        self.writer = writer
        self.didWrite = didWrite
    }

    /// Places `item` on the pasteboard with every representation intact.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem) -> Bool {
        guard !item.items.isEmpty else { return false }

        writer.write(item.items)
        didWrite()
        Log.paste.debug("Copied entry to pasteboard, \(item.items.count) pasteboard item(s)")
        return true
    }

    /// Places only the plain text of `item` on the pasteboard, for the paste-as-plain-text path.
    /// Uses the stored payload rather than the truncated preview.
    @discardableResult
    func copyPlainTextToPasteboard(_ item: ClipItem) -> Bool {
        guard let plainText = item.plainTextRepresentation else { return false }

        writer.write([[plainText]])
        didWrite()
        Log.paste.debug("Copied entry to pasteboard as plain text only")
        return true
    }
}
