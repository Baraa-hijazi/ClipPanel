//
//  ScreenLockObserver.swift
//  ClipPanel
//
//  Optional: wipe the in-memory history when the screen locks (DESIGN 4.1). It narrows the window in
//  which someone with physical access to an unlocked-then-locked Mac could open the panel and read
//  what was copied. Off by default, because for most people losing history at every lock is a worse
//  trade than the risk it removes.
//

import AppKit
import OSLog

final class ScreenLockObserver {
    /// Distributed notification, not NSWorkspace: screen lock is posted on the distributed centre.
    private static let lockedNotification = Notification.Name("com.apple.screenIsLocked")

    private var token: NSObjectProtocol?
    private let onLock: () -> Void

    init(onLock: @escaping () -> Void) {
        self.onLock = onLock
    }

    var isObserving: Bool { token != nil }

    func start() {
        guard token == nil else { return }

        token = DistributedNotificationCenter.default().addObserver(
            forName: Self.lockedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so the main-actor hop is a formality rather than a race.
            MainActor.assumeIsolated {
                Log.app.info("Screen locked; clearing in-memory history")
                self?.onLock()
            }
        }
    }

    func stop() {
        guard let token else { return }
        DistributedNotificationCenter.default().removeObserver(token)
        self.token = nil
    }
}
