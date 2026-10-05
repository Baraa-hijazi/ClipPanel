//
//  ClipboardMonitor.swift
//  ClipPanel
//
//  There is no notification for pasteboard changes on macOS, so the change counter gets
//  polled. Every clipboard manager on the platform does this; the cost is one integer read
//  per tick.
//

import AppKit
import OSLog

final class ClipboardMonitor: NSObject {
    /// Fast enough that the panel never shows stale history, slow enough to be free.
    static let pollInterval: TimeInterval = 0.2

    private let source: any PasteboardSource
    private let currentSettings: () -> CaptureSettings
    /// Sampled at poll time, up to one poll interval after the copy, so a fast app switch can
    /// misattribute the source. The pasteboard does not record its writer, so this cannot be
    /// exact. Fine for the exclusion heuristic and the caption it feeds; never treat it as a
    /// security-grade fact.
    private let frontmostBundleID: () -> String?

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ownPasteChangeCount: Int?

    /// Called with each captured entry, and with the reason whenever a change is skipped.
    var onCapture: ((ClipItem) -> Void)?
    var onSkip: ((CaptureRules.SkipReason) -> Void)?

    var isRunning: Bool { timer != nil }
    var access: PasteboardAccess { source.access }

    init(
        source: any PasteboardSource,
        currentSettings: @escaping () -> CaptureSettings,
        frontmostBundleID: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.source = source
        self.currentSettings = currentSettings
        self.frontmostBundleID = frontmostBundleID
        // Start level with the current clipboard: whatever was copied before launch is not ours
        // to collect.
        self.lastChangeCount = source.changeCount
        super.init()
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        // .common rather than .default so polling continues while a menu is open or a window
        // is being dragged, both of which put the run loop into tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Log.capture.info("Monitor started, pasteboard access \(self.source.access.rawValue, privacy: .public)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Log.capture.info("Monitor stopped")
    }

    /// M4 calls this straight after writing an item to the pasteboard so our own paste does
    /// not come back around as a new capture.
    func markOwnPaste() {
        ownPasteChangeCount = source.changeCount
    }

    @objc private func timerFired() {
        poll()
    }

    /// Exposed rather than private so tests can step the pipeline without a run loop.
    @discardableResult
    func poll() -> CaptureRules.SkipReason? {
        let changeCount = source.changeCount
        guard changeCount != lastChangeCount else { return nil }

        // Advance immediately, even when the change is skipped. A copy made while capture was
        // paused or denied must not be swept up the moment capture resumes.
        lastChangeCount = changeCount

        let settings = currentSettings()
        let sourceBundleID = frontmostBundleID()
        let types = Set(source.itemTypes().flatMap { $0 })

        let preRead = CaptureRules.decideBeforeReading(
            types: types,
            sourceBundleID: sourceBundleID,
            changeCount: changeCount,
            ownPasteChangeCount: ownPasteChangeCount,
            settings: settings
        )

        switch preRead {
        case .skip(let reason):
            if reason == .ownPaste { ownPasteChangeCount = nil }
            return report(reason)
        case .readPayload:
            break
        }

        // Image-bearing copies read against the image cap; everything else against the text cap.
        let snapshot = source.readSnapshot(maxBytes: settings.effectiveCap(forTypes: types))

        // TOCTOU guards. The type peek and the payload read are two separate reads of a live
        // pasteboard, so the contents can change between them, and "concealed copies are never
        // read" must not have a hole exactly one race wide.
        //
        // First: if the change counter moved during the read, whatever was captured is a mixture
        // of two clipboards. Discard it; the next poll evaluates the new contents from scratch.
        guard source.changeCount == changeCount else {
            return report(.changedMidRead)
        }
        // Second: re-run the marker checks against the types that were ACTUALLY captured, not the
        // ones peeked at earlier. The snapshot's own types are derived from the bytes in hand, so
        // this check cannot race with anything.
        if snapshot.observedTypes.contains(PasteboardTypes.concealed) {
            return report(.concealed)
        }
        if settings.skipTransientAndAutoGenerated,
           !snapshot.observedTypes.isDisjoint(with: [PasteboardTypes.transient, PasteboardTypes.autoGenerated]) {
            return report(.transientOrAutoGenerated)
        }

        let item = ItemFactory.make(from: snapshot, sourceBundleID: sourceBundleID)

        let postRead = CaptureRules.decideAfterReading(
            byteSize: snapshot.byteSize,
            exceededReadLimit: snapshot.exceededReadLimit,
            producedUsableItem: item != nil,
            containsImage: !snapshot.observedTypes.isDisjoint(with: PasteboardTypes.imageTypes),
            settings: settings
        )

        switch postRead {
        case .skip(let reason):
            return report(reason)
        case .record:
            guard var item else { return report(.nothingUsable) }

            // Secret Guard: text entries get assessed once, at capture, and only while the guard is
            // on. Detection requires the payload, which has already been read exactly once by this
            // point. With the guard off the detector never runs, so strict mode is inert too.
            if settings.secretGuardEnabled,
               let plainText = item.plainTextRepresentation,
               let text = String(data: plainText.data, encoding: .utf8),
               case .probablySecret = SecretDetector.assess(text: text, sourceBundleID: sourceBundleID) {
                if settings.strictSecretMode {
                    return report(.secretInStrictMode)
                }
                item.isGuarded = true
            }

            // Note the absence of any payload or preview in this log line, per Log.swift.
            Log.capture.debug("Captured entry, \(item.byteSize) bytes, \(item.allTypes.count) types, guarded: \(item.isGuarded)")
            onCapture?(item)
            return nil
        }
    }

    private func report(_ reason: CaptureRules.SkipReason) -> CaptureRules.SkipReason {
        Log.capture.debug("Skipped change: \(reason.rawValue, privacy: .public)")
        onSkip?(reason)
        return reason
    }
}
