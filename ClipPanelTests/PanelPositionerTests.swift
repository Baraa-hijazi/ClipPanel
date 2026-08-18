//
//  PanelPositionerTests.swift
//  ClipPanelTests
//

import Foundation
import Testing

@testable import ClipPanel

@Suite("Panel positioning")
struct PanelPositionerTests {
    /// A 1920x1080 display with a 25pt menu bar, in AppKit's bottom-left origin coordinates.
    private let main = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055)
    )
    private let size = CGSize(width: 360, height: 200)

    @Test("Panel hangs below and right of the anchor")
    func hangsBelowAnchor() {
        let origin = PanelPositioner.origin(
            for: size,
            near: CGPoint(x: 500, y: 800),
            screens: [main]
        )

        #expect(origin.x == 500 + PanelMetrics.anchorOffset)
        #expect(origin.y == 800 - PanelMetrics.anchorOffset - size.height)
    }

    @Test("Panel is pulled back from the right edge")
    func clampsToRightEdge() {
        let origin = PanelPositioner.origin(
            for: size,
            near: CGPoint(x: 1900, y: 800),
            screens: [main]
        )

        #expect(origin.x == main.visibleFrame.maxX - size.width - PanelMetrics.screenInset)
        #expect(origin.x + size.width <= main.visibleFrame.maxX)
    }

    @Test("Panel is pushed up off the bottom edge")
    func clampsToBottomEdge() {
        let origin = PanelPositioner.origin(
            for: size,
            near: CGPoint(x: 500, y: 20),
            screens: [main]
        )

        #expect(origin.y == main.visibleFrame.minY + PanelMetrics.screenInset)
    }

    @Test("Panel avoids the menu bar at the top")
    func respectsVisibleFrameTop() {
        let tall = CGSize(width: 360, height: 1040)
        let origin = PanelPositioner.origin(
            for: tall,
            near: CGPoint(x: 500, y: 1075),
            screens: [main]
        )

        #expect(origin.y + tall.height <= main.visibleFrame.maxY)
    }

    @Test("Panel opens on the display holding the anchor")
    func picksScreenContainingAnchor() {
        let secondary = ScreenGeometry(
            frame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1440, height: 875)
        )

        let origin = PanelPositioner.origin(
            for: size,
            near: CGPoint(x: 2500, y: 500),
            screens: [main, secondary]
        )

        #expect(origin.x >= secondary.visibleFrame.minX)
        #expect(origin.x + size.width <= secondary.visibleFrame.maxX)
    }

    @Test("A panel taller than the screen pins to the bottom rather than inverting")
    func degradesWhenTooLarge() {
        let huge = CGSize(width: 360, height: 5000)
        let origin = PanelPositioner.origin(
            for: huge,
            near: CGPoint(x: 500, y: 500),
            screens: [main]
        )

        #expect(origin.y == main.visibleFrame.minY + PanelMetrics.screenInset)
    }

    @Test("With no screens reported, positioning still returns something usable")
    func survivesNoScreens() {
        let origin = PanelPositioner.origin(for: size, near: CGPoint(x: 10, y: 900), screens: [])
        #expect(origin.y == 900 - size.height)
    }
}
