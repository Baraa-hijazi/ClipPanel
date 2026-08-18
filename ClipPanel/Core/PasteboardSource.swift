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

/// Writing half, kept separate from reading so the paste path can be tested without touching
/// the real pasteboard.
@MainActor
protocol PasteboardWriting: AnyObject {
    /// Replaces the pasteboard contents with `items`, one NSPasteboardItem per entry.
    func write(_ items: [[ClipItem.Representation]])
}

/// The real thing, wrapping `NSPasteboard.general`.
final class SystemPasteboard: PasteboardSource, PasteboardWriting {
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

    func write(_ items: [[ClipItem.Representation]]) {
        pasteboard.clearContents()

        let objects = items.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.type)
                )
            }
            return item
        }
        guard !objects.isEmpty else { return }
        pasteboard.writeObjects(objects)
    }

    func readSnapshot(maxBytes: Int) -> PasteboardSnapshot {
        var items: [[ClipItem.Representation]] = []
        var observed: Set<String> = []
        var runningTotal = 0

        for item in pasteboard.pasteboardItems ?? [] {
            let declared = item.types.map(\.rawValue)
            observed.formUnion(declared)

            var representations: [ClipItem.Representation] = []
            // Only the types worth keeping are read at all. Reading a type forces the source app
            // to resolve promised data, and the size cap should judge what will be stored, not a
            // redundant TIFF that was never going to be kept.
            for type in RepresentationPolicy.typesToStore(from: declared) {
                guard let data = item.data(forType: NSPasteboard.PasteboardType(type)) else { continue }

                runningTotal += data.count
                if runningTotal > maxBytes {
                    // Discard the partial read rather than hand back something half measured.
                    return PasteboardSnapshot(items: [], exceededReadLimit: true, observedTypes: observed)
                }
                representations.append(
                    ClipItem.Representation(type: type, data: data)
                )
            }
            items.append(representations)
        }

        return PasteboardSnapshot(items: items, observedTypes: observed)
    }
}
