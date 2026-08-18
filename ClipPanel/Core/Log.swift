//
//  Log.swift
//  ClipPanel
//
//  Logging rule for this whole project (DESIGN 4.2, guarantee 6): clipboard payloads,
//  previews, and item text must NEVER be interpolated into a log message, at any level.
//  Log counts, types, sizes, and outcomes instead. If a message needs user data to be
//  useful, it does not get logged.
//

import Foundation
import OSLog

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.baraahijazi.ClipPanel"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
