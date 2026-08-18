//
//  AppPreferences.swift
//  ClipPanel
//
//  Preferences only. Clipboard content never goes near UserDefaults, or any other file, unless it
//  is pinned and encrypted (DESIGN 4.2, guarantee 2).
//

import Foundation

nonisolated enum AppPreferences {
    private static let onboardingCompletedKey = "hasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompletedKey) }
    }
}
