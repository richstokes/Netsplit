import Testing
@testable import Netsplit

@Suite("Keychain storage configuration")
struct KeychainStoreTests {
    @Test("Production service remains compatible with existing credentials")
    func preservesProductionService() {
        #expect(KeychainStore.serviceName(bundleIdentifier: "richstokes.irc", isTestMode: false) == "richstokes.irc")
    }

    @Test("Development and test hosts cannot use production credentials")
    func isolatesDevelopmentAndTests() {
        #expect(KeychainStore.serviceName(bundleIdentifier: "richstokes.irc.debug", isTestMode: false) == "richstokes.irc.debug")
        #expect(KeychainStore.serviceName(bundleIdentifier: "richstokes.irc", isTestMode: true) != "richstokes.irc")
        #expect(KeychainStore.serviceName(bundleIdentifier: nil, isTestMode: false) != "richstokes.irc")
        #expect(KeychainStore.service != "richstokes.irc")
    }

    @Test("New credentials have a human-readable Keychain label")
    func labelsNewCredentials() {
        let metadata = KeychainStore.itemMetadata(
            for: "server-password.ED696929-B866-420D-AD08-03F2C29EA516"
        )

        #expect(metadata.label == "Netsplit Server Password")
        #expect(metadata.description == "Secure connection information saved by Netsplit")
    }
}
