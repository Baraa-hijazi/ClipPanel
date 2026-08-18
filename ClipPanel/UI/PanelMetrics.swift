//
//  PanelMetrics.swift
//  ClipPanel
//

import Foundation

nonisolated enum PanelMetrics {
    /// Matches the Win+V flyout closely enough to feel familiar without looking foreign on macOS.
    static let width: CGFloat = 360
    static let maxHeight: CGFloat = 480
    static let cornerRadius: CGFloat = 12
    /// Gap between the panel and the screen edge when clamping.
    static let screenInset: CGFloat = 8
    /// Gap between the anchor point (caret or pointer) and the panel.
    static let anchorOffset: CGFloat = 10
}
