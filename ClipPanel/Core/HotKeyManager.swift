//
//  HotKeyManager.swift
//  ClipPanel
//
//  Global hot key registration via Carbon's RegisterEventHotKey.
//
//  Why Carbon and not NSEvent.addGlobalMonitorForEvents: the NSEvent route requires the
//  Input Monitoring permission, and a clipboard manager has no business asking for the
//  ability to watch every keystroke on the machine. RegisterEventHotKey needs no
//  permission at all, because the OS matches the combination and only tells us when it
//  fires. There is no modern Swift replacement for this API.
//
//  Each HotKeyManager instance owns ONE hot key (the app has two: the panel and the panic
//  wipe). The Carbon event handler is installed once per process, because a handler per
//  instance would deliver every hot key event to every handler and run each action twice.
//

import AppKit
import Carbon.HIToolbox
import OSLog

/// Hot key actions keyed by Carbon hot key id.
///
/// The Carbon callback is a C function pointer that cannot capture context. The usual trick
/// is to smuggle `self` through the handler's `userData` pointer, but Swift 6 rightly
/// refuses to send a non-Sendable object across that boundary, so the actions live in this
/// main-actor-isolated table instead and the callback looks them up by id.
@MainActor private var hotKeyActions: [UInt32: () -> Void] = [:]
@MainActor private var carbonHandlerInstalled = false
@MainActor private var nextHotKeyID: UInt32 = 1

final class HotKeyManager {
    /// Four-char code identifying our hot keys, 'CLP1'.
    private static let signature: OSType = 0x434C_5031

    /// This instance's slot in the action table, unique per instance for the process lifetime.
    private let hotKeyID: UInt32
    private var hotKeyRef: EventHotKeyRef?

    init() {
        hotKeyID = nextHotKeyID
        nextHotKeyID += 1
    }

    /// Registers `shortcut` system-wide. Returns false if the combination is unavailable,
    /// which usually means another running app already owns it.
    func register(shortcut: GlobalShortcut, action: @escaping () -> Void) -> Bool {
        unregister()

        guard Self.installCarbonHandlerIfNeeded() else { return false }
        hotKeyActions[hotKeyID] = action

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: hotKeyID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr, let ref else {
            Log.hotKey.error("RegisterEventHotKey failed with status \(registerStatus)")
            unregister()
            return false
        }

        hotKeyRef = ref
        Log.hotKey.info("Registered hot key \(shortcut.description, privacy: .public)")
        return true
    }

    /// Releases the hot key. Safe to call when nothing is registered. The process-wide Carbon
    /// handler stays installed; with no actions in the table it does nothing.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        hotKeyActions[hotKeyID] = nil
    }

    private static func installCarbonHandlerIfNeeded() -> Bool {
        guard !carbonHandlerInstalled else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            clipPanelHotKeyCallback,
            1,
            &eventType,
            nil,
            nil
        )
        guard status == noErr else {
            Log.hotKey.error("InstallEventHandler failed with status \(status)")
            return false
        }
        carbonHandlerInstalled = true
        return true
    }
}

/// Carbon C callback for kEventHotKeyPressed, installed once per process.
private nonisolated func clipPanelHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let eventRef else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        .init(MemoryLayout<EventHotKeyID>.size),
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let firedID = hotKeyID.id
    // Carbon delivers hot key events on the main run loop, so main-actor state is safe to
    // touch here without hopping, which keeps the panel appearing on the same event cycle.
    MainActor.assumeIsolated {
        hotKeyActions[firedID]?()
    }
    return noErr
}
