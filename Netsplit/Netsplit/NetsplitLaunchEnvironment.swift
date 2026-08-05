import Foundation

enum NetsplitLaunchEnvironment {
    static let testModeKey = "NETSPLIT_TEST_MODE"

    static var currentProcessIsInTestMode: Bool {
        isTestMode(environment: ProcessInfo.processInfo.environment)
    }

    static func isTestMode(environment: [String: String]) -> Bool {
        guard let value = environment[testModeKey]?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }
}
