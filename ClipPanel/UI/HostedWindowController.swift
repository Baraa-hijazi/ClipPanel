//
//  HostedWindowController.swift
//  ClipPanel
//
//  Ordinary utility windows (onboarding, settings), as opposed to the panel.
//
//  These deliberately DO take focus: the user asked for them, and they contain controls that need
//  the keyboard. That is the opposite of the panel's non-activating behaviour, so an accessory app
//  has to activate itself explicitly or the window opens behind everything and cannot be typed in.
//

import AppKit
import SwiftUI

@MainActor
final class HostedWindowController<Content: View> {
    private let title: String
    private let content: () -> Content
    private var window: NSWindow?

    init(title: String, content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 520, height: 420))
        return window
    }
}
