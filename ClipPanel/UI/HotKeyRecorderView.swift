//
//  HotKeyRecorderView.swift
//  ClipPanel
//
//  Click, press a combination, done. Written by hand rather than pulled in from a package, because
//  DESIGN 9 rules out dependencies and this is about a hundred lines.
//
//  Local monitoring only: the recorder listens while it has focus, using NSEvent's LOCAL monitor,
//  which sees events aimed at this app and needs no permission. A global monitor would need Input
//  Monitoring, which this app refuses to ask for.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorderView: View {
    let shortcut: GlobalShortcut
    let onRecord: (GlobalShortcut) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press a combination..." : shortcut.description)
                    .frame(minWidth: 120)
                    .monospaced()
            }
            .help("Click, then press the combination you want")

            if isRecording {
                Button("Cancel") { stopRecording() }
                    .buttonStyle(.link)
            } else if shortcut != .panelDefault {
                Button("Reset") { onReset() }
                    .buttonStyle(.link)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }

            // Escape abandons recording rather than becoming the shortcut.
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }

            let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
            // A bare key would fire while typing anywhere, so require at least one of
            // command, control, or option.
            guard carbonModifiers != 0 else {
                NSSound.beep()
                return nil
            }

            onRecord(
                GlobalShortcut(
                    keyCode: UInt32(event.keyCode),
                    carbonModifiers: carbonModifiers,
                    keyLabel: Self.label(for: event)
                )
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        // Shift alone is not enough to make a shortcut safe, so it only counts alongside another.
        if flags.contains(.shift), result != 0 { result |= UInt32(shiftKey) }
        return result
    }

    /// What to draw for the key itself. Function and navigation keys get a name; everything else uses
    /// the character the key produces without modifiers, upper-cased.
    private static func label(for event: NSEvent) -> String {
        if let named = namedKeys[Int(event.keyCode)] {
            return named
        }
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return "Key \(event.keyCode)"
        }
        return characters.uppercased()
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Delete: "Delete",
        kVK_ForwardDelete: "Forward Delete",
        kVK_Home: "Home",
        kVK_End: "End",
        kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
        kVK_LeftArrow: "Left",
        kVK_RightArrow: "Right",
        kVK_UpArrow: "Up",
        kVK_DownArrow: "Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
