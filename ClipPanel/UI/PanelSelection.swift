//
//  PanelSelection.swift
//  ClipPanel
//
//  Which entry the keyboard is on. Separate from the store so the selection rules are testable
//  on their own, and so a capture arriving while the panel is open cannot silently move the
//  user's selection out from under them.
//

import Foundation
import Observation

@Observable
final class PanelSelection {
    private(set) var selectedID: ClipItem.ID?
    /// Guarded entries the user has unmasked this panel session. Cleared every time the panel
    /// opens, so a revealed password does not stay readable across openings.
    private(set) var revealedIDs: Set<ClipItem.ID> = []

    /// Called each time the panel opens. The first entry is selected so the Win+V habit of
    /// "shortcut, then Return" pastes the most recent copy.
    func reset(to items: [ClipItem]) {
        selectedID = items.first?.id
        revealedIDs.removeAll()
    }

    func toggleReveal(id: ClipItem.ID) {
        if revealedIDs.contains(id) {
            revealedIDs.remove(id)
        } else {
            revealedIDs.insert(id)
        }
    }

    func isRevealed(_ id: ClipItem.ID) -> Bool {
        revealedIDs.contains(id)
    }

    func selectedItem(in items: [ClipItem]) -> ClipItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    func select(id: ClipItem.ID?) {
        selectedID = id
    }

    /// Moves by `offset` entries, stopping at the ends rather than wrapping, which is what the
    /// Windows flyout does.
    func move(by offset: Int, in items: [ClipItem]) {
        guard !items.isEmpty else {
            selectedID = nil
            return
        }
        guard let selectedID, let current = items.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = items.first?.id
            return
        }

        let target = min(max(current + offset, 0), items.count - 1)
        self.selectedID = items[target].id
    }

    /// Where selection should land once `id` is removed: the entry that slides into its place,
    /// or the new last entry if it was at the end.
    func selectionAfterRemoving(_ id: ClipItem.ID, from items: [ClipItem]) -> ClipItem.ID? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return selectedID }

        var remaining = items
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }

        return remaining[min(index, remaining.count - 1)].id
    }
}
