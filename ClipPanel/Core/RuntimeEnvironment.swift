//
//  RuntimeEnvironment.swift
//  ClipPanel
//

import Foundation

nonisolated enum RuntimeEnvironment {
    /// True when this process is the host for the unit test bundle. Decided once per process:
    /// several components (launch, preferences) must agree on it, and it cannot change mid-run.
    static let isHostingTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }()
}
