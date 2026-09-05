import Foundation

enum NetsplitLaunchEnvironment {
    static let testModeKey = "NETSPLIT_TEST_MODE"

    static var currentProcessIsInTestMode: Bool {
        isTestMode(environment: ProcessInfo.processInfo.environment)
    }

    static func isTestMode(environment: [String: String]) -> Bool {
        if let value = environment[testModeKey]?.lowercased(),
           value == "1" || value == "true" || value == "yes" {
            return true
        }
        // Also protect custom test plans that omit NETSPLIT_TEST_MODE.
        return ["XCTestConfigurationFilePath", "XCTestBundlePath"].contains {
            !(environment[$0] ?? "").isEmpty
        }
    }
}
