//
//  RowLayoutStabilityTests.swift
//  ClipPanelTests
//
//  PLAN.md Item 2: hovering a row must change pixels, never layout. The bug was the pin and delete
//  buttons being inserted into the row on hover, which narrowed the text column, re-wrapped the
//  preview, and could change the row's height (and the panel's) under the pointer.
//
//  Hover is view-private state, but selection drives the identical code path (actions show for
//  hovered OR selected rows), so selected-versus-unselected height is the testable proxy.
//

import AppKit
import SwiftUI
import Testing

@testable import ClipPanel

@Suite("Row layout stability")
@MainActor
struct RowLayoutStabilityTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func height(of item: ClipItem, selected: Bool) -> CGFloat {
        let view = ItemCardView(
            item: item,
            isSelected: selected,
            isRevealed: false,
            isGuarded: false,
            actions: .inert
        )
        .frame(width: PanelMetrics.width)

        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// Only lengths near a wrap boundary expose the reflow, so sweep many of them rather than
    /// trusting one hand-picked string.
    private var textLengths: [Int] { Array(stride(from: 20, through: 320, by: 3)) }

    private func sampleText(length: Int) -> String {
        let words = ["clipboard", "history", "panel", "entry", "copy", "paste", "macOS", "text"]
        var result = ""
        var index = 0
        while result.count < length {
            result += (result.isEmpty ? "" : " ") + words[index % words.count]
            index += 1
        }
        return String(result.prefix(length))
    }

    @Test("Selecting a text row (the hover path) never changes its height, at any text length")
    func selectionDoesNotReflowText() {
        var mismatches: [String] = []
        for length in textLengths {
            let item = textItem(sampleText(length: length), at: base)
            let idle = height(of: item, selected: false)
            let active = height(of: item, selected: true)
            if idle != active {
                mismatches.append("length \(length): \(idle) pt idle, \(active) pt selected")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) lengths reflowed, e.g. \(mismatches.prefix(3))")
    }

    @Test("Pinning a text row never changes its height, at any text length")
    func pinningDoesNotReflowText() {
        var mismatches: [String] = []
        for length in textLengths {
            let text = sampleText(length: length)
            let unpinned = height(of: textItem(text, at: base), selected: false)
            let pinned = height(of: textItem(text, at: base, pinned: true), selected: false)
            if unpinned != pinned {
                mismatches.append("length \(length): \(unpinned) pt unpinned, \(pinned) pt pinned")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) lengths reflowed, e.g. \(mismatches.prefix(3))")
    }

    @Test("Image and file rows keep their height when selected")
    func nonTextRowsStable() {
        let image = ItemFactory.make(
            from: PasteboardSnapshot(items: [[
                ClipItem.Representation(type: PasteboardTypes.png, data: pngData(width: 300, height: 200)),
            ]]),
            sourceBundleID: nil
        )!
        let longName = "/tmp/" + String(repeating: "very-long-file-name-", count: 6) + "end.txt"
        let files = ItemFactory.make(
            from: PasteboardSnapshot(items: [[
                ClipItem.Representation(
                    type: PasteboardTypes.fileURL,
                    data: URL(fileURLWithPath: longName).dataRepresentation
                ),
            ]]),
            sourceBundleID: nil
        )!

        #expect(height(of: image, selected: false) == height(of: image, selected: true))
        #expect(height(of: files, selected: false) == height(of: files, selected: true))
    }
}
