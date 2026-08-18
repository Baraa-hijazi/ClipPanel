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

        let snapshot = source.readSnapshot(maxBytes: settings.maxItemBytes)
        let item = ItemFactory.make(from: snapshot, sourceBundleID: sourceBundleID)

        let postRead = CaptureRules.decideAfterReading(
            byteSize: snapshot.byteSize,
            exceededReadLimit: snapshot.exceededReadLimit,
            producedUsableItem: item != nil,
            settings: settings
        )

        switch postRead {
        case .skip(let reason):
            return report(reason)
        case .record:
            guard let item else { return report(.nothingUsable) }
            // Note the absence of any payload or preview in this log line, per Log.swift.
            Log.capture.debug("Captured entry, \(item.byteSize) bytes, \(item.allTypes.count) types")
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
