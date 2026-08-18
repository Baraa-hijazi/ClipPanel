//
//  AppNameResolver.swift
//  ClipPanel
//

import AppKit

/// Turns a bundle identifier into the name a person would recognise, cached because the panel
/// asks for the same handful of apps over and over.
final class AppNameResolver {
    static let shared = AppNameResolver()

    /// Far above anything a real history produces, low enough that the cache cannot grow without
    /// bound over an agent process that runs for weeks.
    private static let cacheLimit = 64

    private var cache: [String: String?] = [:]

    func displayName(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        if cache.count >= Self.cacheLimit { cache.removeAll() }

        let resolved = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) }

        cache[bundleID] = resolved
        return resolved
    }
}
