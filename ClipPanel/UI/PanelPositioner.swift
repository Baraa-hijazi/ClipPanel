//
//  PanelPositioner.swift
//  ClipPanel
//

import AppKit

/// The bits of NSScreen the geometry needs, as plain values so the maths is testable without a
/// display attached.
nonisolated struct ScreenGeometry: Sendable, Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

/// Works out where the panel should sit.
///
/// M1/M2 anchor to the mouse pointer. M3/M4 will prefer the text caret via the accessibility
/// API and fall back to this.
nonisolated enum PanelPositioner {
    /// Screen-coordinate origin (bottom-left, AppKit convention) for a panel of `size` hanging
    /// below and slightly right of `anchor`, clamped to stay fully on screen.
    static func origin(for size: CGSize, near anchor: CGPoint, screens: [ScreenGeometry]) -> CGPoint {
        let screen = screens.first { $0.frame.contains(anchor) } ?? screens.first

        guard let visible = screen?.visibleFrame else {
            return CGPoint(x: anchor.x, y: anchor.y - size.height)
        }

        let inset = PanelMetrics.screenInset
        let offset = PanelMetrics.anchorOffset

        // Hang below the anchor, the way the Windows flyout drops from the caret.
        var x = anchor.x + offset
        var y = anchor.y - offset - size.height

        x = clamp(x, lower: visible.minX + inset, upper: visible.maxX - size.width - inset)
        y = clamp(y, lower: visible.minY + inset, upper: visible.maxY - size.height - inset)

        return CGPoint(x: x, y: y)
    }

    @MainActor
    static func currentScreens() -> [ScreenGeometry] {
        NSScreen.screens.map {
            ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
    }

    /// Degrades predictably when the panel is larger than the space available: pin to the
    /// lower bound rather than producing an inverted range.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return lower }
        return min(max(value, lower), upper)
    }
}
