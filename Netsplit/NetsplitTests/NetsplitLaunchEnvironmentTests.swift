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

    @Test("Xcode test hosts are isolated even without the shared test-plan flag")
    func detectsOtherTestPlans() {
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath"] {
            #expect(NetsplitLaunchEnvironment.isTestMode(environment: [key: "/test/fixture"]))
            #expect(!NetsplitLaunchEnvironment.isTestMode(environment: [key: ""]))
        }
        #expect(NetsplitLaunchEnvironment.isTestMode(environment: [
            NetsplitLaunchEnvironment.testModeKey: "0",
            "XCTestBundlePath": "/test/fixture"
        ]))
    }

    @Test("Test profile and identity edits cannot overwrite app settings or another test")
    @MainActor
    func isolatesStatePersistence() throws {
        let appDefaults = UserDefaults.standard
        let savedProfiles = appDefaults.data(forKey: ServerProfileStore.profilesKey)
        let savedNickname = appDefaults.string(forKey: "nickname")
        let savedDeletedPresets = appDefaults.stringArray(forKey: ServerProfileStore.deletedPresetIDsKey)
        let first = IRCAppState()
        let second = IRCAppState()
        let secondProfiles = second.profiles
        let secondNickname = second.nickname

        first.nickname = "IsolatedTestUser"
        first.delete(try #require(first.profiles.first))

        #expect(second.nickname == secondNickname)
        #expect(second.profiles == secondProfiles)
        #expect(appDefaults.data(forKey: ServerProfileStore.profilesKey) == savedProfiles)
        #expect(appDefaults.string(forKey: "nickname") == savedNickname)
        #expect(appDefaults.stringArray(forKey: ServerProfileStore.deletedPresetIDsKey) == savedDeletedPresets)
    }

    @Test("Default test credentials stay with their state and never reach the Keychain")
    @MainActor
    func isolatesStateCredentials() throws {
        let first = IRCAppState()
        let second = IRCAppState()
        let id = UUID()
        let result = first.addProfile(
            id: id, name: "Isolated Profile", hostname: "irc.test.invalid", port: 6697,
            useTLS: true, autoConnect: false, nicknameOverride: "", realNameOverride: "",
            mentionNotificationsOverride: nil,
            credentials: IRCProfileCredentialChanges(serverPassword: "test-only-value"),
            useSASL: false, saslUsername: "", useSSHTunnel: false,
            sshHostname: "", sshPort: 22, sshUsername: "", sshKeyFilename: nil
        )
        #expect(result.succeeded)
        let profile = try #require(first.profiles.first { $0.id == id })
        #expect(first.credentialSnapshot(for: profile).serverPassword == "test-only-value")
        #expect(second.credentialSnapshot(for: profile).serverPassword == "")
        #expect(!second.profiles.contains { $0.id == id })
    }

    @Test("The shared test plan launches the app in test mode")
    func sharedTestPlanFlag() {
        #expect(NetsplitLaunchEnvironment.currentProcessIsInTestMode)
    }
}
