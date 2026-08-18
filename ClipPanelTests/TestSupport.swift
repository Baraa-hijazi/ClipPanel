//
//  TestSupport.swift
//  ClipPanelTests
//

import AppKit
import Foundation
import Testing

@testable import ClipPanel

// MARK: - Snapshot builders

func representation(_ type: String, _ string: String) -> ClipItem.Representation {
    ClipItem.Representation(type: type, data: Data(string.utf8))
}

func textSnapshot(_ string: String) -> PasteboardSnapshot {
    PasteboardSnapshot(items: [[representation(PasteboardTypes.plainText, string)]])
}

func snapshot(types: [String]) -> PasteboardSnapshot {
    PasteboardSnapshot(items: [types.map { representation($0, "payload for \($0)") }])
}

func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

func textItem(_ string: String, at date: Date, pinned: Bool = false) -> ClipItem {
    var item = ItemFactory.make(from: textSnapshot(string), sourceBundleID: "com.example.app", now: date)!
    item.isPinned = pinned
    return item
}

// MARK: - Fake pasteboard

/// Drives the capture pipeline without touching the real pasteboard, so tests never read or
/// disturb whatever the developer had copied.
final class FakePasteboard: PasteboardSource, PasteboardWriting {
    var changeCount = 0
    var access: PasteboardAccess = .allowed
    var stored = PasteboardSnapshot(items: [])
    /// Counts payload reads, to prove the rules reject a copy without ever looking at it.
    var payloadReadCount = 0
    /// Everything written back, newest last.
    var writes: [[[ClipItem.Representation]]] = []

    func write(_ items: [[ClipItem.Representation]]) {
        writes.append(items)
        stored = PasteboardSnapshot(items: items)
        changeCount += 1
    }

    /// Runs after the type peek and before the payload read, so a test can change the pasteboard
    /// in exactly the window the TOCTOU guards exist for.
    var afterTypesRead: (() -> Void)?

    func put(_ snapshot: PasteboardSnapshot) {
        stored = snapshot
        changeCount += 1
    }

    /// Replaces the contents WITHOUT advancing the change counter, which no real pasteboard write
    /// can do. Exists to prove the marker re-check holds even if the counter guard were bypassed.
    func sneakilyReplace(_ snapshot: PasteboardSnapshot) {
        stored = snapshot
    }

    func itemTypes() -> [[String]] {
        let types = stored.items.map { $0.map(\.type) }
        let hook = afterTypesRead
        afterTypesRead = nil
        hook?()
        return types
    }

    func readSnapshot(maxBytes: Int) -> PasteboardSnapshot {
        payloadReadCount += 1

        var runningTotal = 0
        for item in stored.items {
            for representation in item {
                runningTotal += representation.data.count
                if runningTotal > maxBytes {
                    return PasteboardSnapshot(items: [], exceededReadLimit: true)
                }
            }
        }
        return stored
    }
}

// MARK: - Fake keystroke sender

/// Stands in for Accessibility and the real keyboard, so the paste path can be tested without the
/// permission and without stealing focus from the test run.
final class FakeKeystrokeSender: KeystrokeSending {
    var canSendKeystrokes = true
    var activatedApps: [String] = []
    var pasteCount = 0
    /// Lets a test observe the state of the world at the moment the keystroke goes out.
    var onSendPaste: (() -> Void)?

    func activate(_ app: NSRunningApplication?) async {
        activatedApps.append(app?.bundleIdentifier ?? "none")
    }

    func sendPaste() {
        pasteCount += 1
        onSendPaste?()
    }
}
