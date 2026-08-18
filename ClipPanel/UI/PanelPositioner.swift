//
//  PanelPositioner.swift
//  ClipPanel
//

import AppKit

/// Works out where the panel should sit. Pure functions so the geometry is unit testable
/// without a window on screen.
///
/// M1 anchors to the mouse pointer. M3/M4 will prefer the text caret via the accessibility
/// API and fall back to this.
nonisolated enum PanelPositioner {
    /// Screen-coordinate origin (bottom-left, AppKit convention) for a panel of `size`
    /// hanging below and slightly right of `anchor`, clamped to stay fully on screen.
    static func origin(for size: CGSize, near anchor: CGPoint, screens: [NSScreen]) -> CGPoint {
        let screen = screens.first { NSPointInRect(anchor, $0.frame) } ?? screens.first

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

    /// Degrades gracefully when the panel is larger than the space available.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return lower }
        return min(max(value, lower), upper)
    }
}
