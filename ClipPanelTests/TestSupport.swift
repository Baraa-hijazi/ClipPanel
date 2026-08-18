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

    func put(_ snapshot: PasteboardSnapshot) {
        stored = snapshot
        changeCount += 1
    }

    func itemTypes() -> [[String]] {
        stored.items.map { $0.map(\.type) }
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
