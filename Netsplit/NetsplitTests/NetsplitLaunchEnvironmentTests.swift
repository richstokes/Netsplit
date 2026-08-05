import Foundation
import Testing
@testable import Netsplit

@Suite("App launch environment")
struct NetsplitLaunchEnvironmentTests {
    @Test("Normal launches allow automatic server connections")
    func normalLaunch() {
        #expect(!NetsplitLaunchEnvironment.isTestMode(environment: [:]))
    }

    @Test("The explicit test flag disables automatic server connections")
    func explicitTestFlag() {
        for value in ["1", "true", "TRUE", "yes"] {
            #expect(NetsplitLaunchEnvironment.isTestMode(
                environment: [NetsplitLaunchEnvironment.testModeKey: value]
            ))
        }
    }

    @Test("The shared test plan launches the app in test mode")
    func sharedTestPlanFlag() {
        #expect(NetsplitLaunchEnvironment.currentProcessIsInTestMode)
    }
}
