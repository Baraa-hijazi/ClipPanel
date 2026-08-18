//
//  PasteboardSource.swift
//  ClipPanel
//

import AppKit

/// Where the macOS 26 pasteboard privacy setting currently stands for this app (DESIGN 6.1).
nonisolated enum PasteboardAccess: String, Sendable, Equatable {
    /// The user chose Always Allow. Capture works.
    case allowed
    /// The system will ask, so the first payload read raises the alert.
    case ask
    /// The user chose Always Deny. Capture cannot work and the UI has to say so.
    case denied
    /// System default, not yet pinned either way by the user.
    case systemDefault
}

/// The slice of NSPasteboard the capture pipeline needs, so tests can drive it with a fake.
///
/// Deliberately split into a types-only peek and a payload read. Reading type identifiers is
/// how any app decides whether it could paste, and is not believed to raise the macOS 26
/// privacy alert; reading payloads is what does. Keeping them separate means a concealed or
/// excluded copy is rejected without a payload read, and a captured copy costs exactly one.
@MainActor
protocol PasteboardSource: AnyObject {
    var changeCount: Int { get }
    var access: PasteboardAccess { get }
    /// Type identifiers per pasteboard item. Reads no payloads.
    func itemTypes() -> [[String]]
    /// Reads payloads, abandoning the read as soon as the running total passes `maxBytes`.
    func readSnapshot(maxBytes: Int) -> PasteboardSnapshot
}

/// The real thing, wrapping `NSPasteboard.general`.
final class SystemPasteboard: PasteboardSource {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var access: PasteboardAccess {
        switch pasteboard.accessBehavior {
        case .alwaysAllow: .allowed
        case .ask: .ask
        case .alwaysDeny: .denied
        case .default: .systemDefault
        @unknown default: .systemDefault
        }
    }

    func itemTypes() -> [[String]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.map(\.rawValue)
        }
    }

    func readSnapshot(maxBytes: Int) -> PasteboardSnapshot {
        var items: [[ClipItem.Representation]] = []
        var runningTotal = 0

        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [ClipItem.Representation] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }

                runningTotal += data.count
                if runningTotal > maxBytes {
                    // Discard the partial read rather than hand back something half measured.
                    return PasteboardSnapshot(items: [], exceededReadLimit: true)
                }
                representations.append(
                    ClipItem.Representation(type: type.rawValue, data: data)
                )
            }
            items.append(representations)
        }

        return PasteboardSnapshot(items: items)
    }
}
