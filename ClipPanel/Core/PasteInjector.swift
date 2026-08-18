//
//  PasteInjector.swift
//  ClipPanel
//
//  Puts a history entry back where the user wants it.
//
//  Two modes, and the fallback is a feature rather than a failure. With Accessibility granted the
//  entry is written to the pasteboard and command-V is synthesized into the app the user was
//  typing in. Without it, the entry becomes the current clipboard and the user presses command-V
//  themselves (DESIGN 5, 6.2). Everything else about the app is identical either way.
//

import AppKit
import OSLog

/// What actually happened, so the UI can tell the user the truth.
enum PasteOutcome: Equatable {
    /// Written to the pasteboard and pasted into the target app.
    case pasted
    /// Written to the pasteboard only. The user finishes with command-V.
    case copiedOnly(CopyOnlyReason)
    /// Nothing was written.
    case failed(FailureReason)

    enum CopyOnlyReason: Equatable {
        case accessibilityNotGranted
        case noTargetApp
    }

    enum FailureReason: Equatable {
        case entryHasNothingToWrite
        case entryHasNoPlainText
    }
}

final class PasteInjector {
    private let writer: any PasteboardWriting
    private let keystrokes: any KeystrokeSending
    /// Called straight after a successful write so the monitor can recognise our own change and not
    /// capture it back as a new entry.
    private let didWrite: () -> Void

    init(
        writer: any PasteboardWriting,
        keystrokes: any KeystrokeSending,
        didWrite: @escaping () -> Void
    ) {
        self.writer = writer
        self.keystrokes = keystrokes
        self.didWrite = didWrite
    }

    /// Writes `item` and, when possible, pastes it into `targetApp`.
    ///
    /// The order is not negotiable and comes from the measurement in DESIGN 6.7: the panel holds
    /// key focus while it is open, so the caller must hide it first, then this reactivates the
    /// target app, and only then does the keystroke go out. Posting command-V while the panel still
    /// has focus would paste into nothing.
    func paste(
        _ item: ClipItem,
        plainTextOnly: Bool,
        into targetApp: NSRunningApplication?
    ) async -> PasteOutcome {
        let written = plainTextOnly
            ? copyPlainTextToPasteboard(item)
            : copyToPasteboard(item)

        guard written else {
            let reason: PasteOutcome.FailureReason = plainTextOnly
                ? .entryHasNoPlainText
                : .entryHasNothingToWrite
            Log.paste.error("Nothing written for this entry: \(String(describing: reason), privacy: .public)")
            return .failed(reason)
        }

        guard keystrokes.canSendKeystrokes else {
            Log.paste.debug("Copy-only mode: Accessibility not granted")
            return .copiedOnly(.accessibilityNotGranted)
        }
        guard let targetApp else {
            Log.paste.debug("Copy-only mode: no app recorded to paste into")
            return .copiedOnly(.noTargetApp)
        }

        await keystrokes.activate(targetApp)
        keystrokes.sendPaste()
        Log.paste.debug("Pasted into the target app")
        return .pasted
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
