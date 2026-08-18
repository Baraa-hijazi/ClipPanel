//
//  PanelSelectionTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Panel selection")
@MainActor
struct PanelSelectionTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func items(_ count: Int) -> [ClipItem] {
        (0..<count).map { textItem("entry \($0)", at: base.addingTimeInterval(Double($0))) }
    }

    @Test("Opening selects the newest entry so Return pastes the last copy")
    func resetSelectsFirst() {
        let list = items(3)
        let selection = PanelSelection()
        selection.reset(to: list)

        #expect(selection.selectedID == list.first?.id)
    }

    @Test("Opening an empty history selects nothing")
    func resetOnEmpty() {
        let selection = PanelSelection()
        selection.reset(to: [])

        #expect(selection.selectedID == nil)
    }

    @Test("Arrow keys move one entry at a time")
    func movesByOne() {
        let list = items(3)
        let selection = PanelSelection()
        selection.reset(to: list)

        selection.move(by: 1, in: list)
        #expect(selection.selectedID == list[1].id)

        selection.move(by: 1, in: list)
        #expect(selection.selectedID == list[2].id)

        selection.move(by: -1, in: list)
        #expect(selection.selectedID == list[1].id)
    }

    @Test("Selection stops at the ends instead of wrapping")
    func clampsAtEnds() {
        let list = items(3)
        let selection = PanelSelection()
        selection.reset(to: list)

        selection.move(by: -1, in: list)
        #expect(selection.selectedID == list[0].id)

        selection.move(by: 99, in: list)
        #expect(selection.selectedID == list[2].id)

        selection.move(by: 1, in: list)
        #expect(selection.selectedID == list[2].id)
    }

    @Test("Moving with nothing selected picks the first entry")
    func moveWithoutSelection() {
        let list = items(2)
        let selection = PanelSelection()

        selection.move(by: 1, in: list)
        #expect(selection.selectedID == list[0].id)
    }

    @Test("Deleting a middle entry selects whatever slides into its place")
    func removalSelectsSuccessor() {
        let list = items(3)
        let selection = PanelSelection()
        selection.reset(to: list)
        selection.move(by: 1, in: list)

        let next = selection.selectionAfterRemoving(list[1].id, from: list)
        #expect(next == list[2].id)
    }

    @Test("Deleting the last entry selects the new last one")
    func removalAtEndSelectsPrevious() {
        let list = items(3)
        let selection = PanelSelection()
        selection.select(id: list[2].id)

        let next = selection.selectionAfterRemoving(list[2].id, from: list)
        #expect(next == list[1].id)
    }

    @Test("Deleting the only entry leaves nothing selected")
    func removalOfOnlyEntry() {
        let list = items(1)
        let selection = PanelSelection()
        selection.reset(to: list)

        #expect(selection.selectionAfterRemoving(list[0].id, from: list) == nil)
    }

    @Test("The selected entry can be looked up")
    func selectedItemLookup() {
        let list = items(3)
        let selection = PanelSelection()
        selection.select(id: list[1].id)

        #expect(selection.selectedItem(in: list)?.id == list[1].id)
        #expect(PanelSelection().selectedItem(in: list) == nil)
    }
}
