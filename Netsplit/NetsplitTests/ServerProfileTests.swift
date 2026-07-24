import Foundation
import Testing
@testable import Netsplit

@Suite("Server profile persistence")
struct ServerProfileTests {
    @Test("Servers are ordered alphabetically for the sidebar")
    func ordersServersForSidebar() {
        let names = ["Rizon", "ircNet", "Freenode", "Libera.Chat", "Server 10", "server 2", "alpha"]
        let profiles = names.map {
            ServerProfile(name: $0, hostname: "irc.\($0).example", port: 6697, useTLS: true)
        }

        #expect(IRCServerOrdering.alphabetically(profiles).map(\.name) == [
            "alpha", "Freenode", "ircNet", "Libera.Chat", "Rizon", "server 2", "Server 10"
        ])
    }

    @Test("Decodes legacy profiles with safe defaults for newer fields")
    func decodesLegacyProfile() throws {
        let json = Data(#"{"name":"Legacy","hostname":"irc.example.com","port":6697,"useTLS":true}"#.utf8)
        let profile = try JSONDecoder().decode(ServerProfile.self, from: json)

        #expect(profile.name == "Legacy")
        #expect(profile.hostname == "irc.example.com")
        #expect(profile.port == 6697)
        #expect(profile.useTLS)
        #expect(!profile.autoConnect)
        #expect(!profile.isBuiltIn)
        #expect(profile.mentionNotificationsOverride == nil)
        #expect(profile.favoriteChannels == nil)
        #expect(profile.ignoredNicknames == nil)
        #expect(profile.mutedConversationNames == nil)
        #expect(profile.useSASL == nil)
        #expect(profile.useSSHTunnel == nil)
    }

    @Test("Decodes legacy muted nicknames as ignored users")
    func migratesLegacyMutedNicknames() throws {
        let json = Data(#"{"name":"Legacy","hostname":"irc.example.com","port":6697,"useTLS":true,"mutedNicknames":["bot"]}"#.utf8)
        let profile = try JSONDecoder().decode(ServerProfile.self, from: json)

        #expect(profile.ignoredNicknames == ["bot"])
    }

    @Test("Round-trips security, connection, and conversation settings")
    func roundTripsProfile() throws {
        let id = UUID(uuidString: "ED696929-B866-420D-AD08-03F2C29EA516")!
        let original = ServerProfile(
            id: id,
            name: "Secure IRC",
            hostname: "irc.example.com",
            port: 6697,
            useTLS: true,
            autoConnect: true,
            nicknameOverride: "Alice",
            mentionNotificationsOverride: true,
            favoriteChannels: ["#swift"],
            ignoredNicknames: ["bot"],
            mutedConversationNames: ["#quiet", "Bob"],
            useSASL: true,
            saslUsername: "alice",
            useSSHTunnel: true,
            sshHostname: "bastion.example.com",
            sshPort: 22,
            sshUsername: "alice",
            sshKeyFilename: "id_ed25519",
            sshTrustedHostKey: "ssh-ed25519 AAAA",
            presetID: "secure-irc"
        )

        let decoded = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("Bundled presets keep stable, unique identities and usable endpoints")
    func validatesRecommendedProfiles() {
        let profiles = ServerProfile.recommended
        let presetIDs = profiles.compactMap(\.presetID)
        let ircnet = profiles.first { $0.presetID == "ircnet" }

        #expect(!profiles.isEmpty)
        #expect(presetIDs.count == profiles.count)
        #expect(Set(presetIDs).count == profiles.count)
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        #expect(profiles.allSatisfy { $0.isBuiltIn })
        #expect(profiles.allSatisfy { !$0.name.isEmpty && !$0.hostname.isEmpty && $0.port > 0 })
        #expect(ircnet?.hostname == "irc.ircnet.com")
        #expect(ircnet?.port == 6697)
        #expect(ircnet?.useTLS == true)
    }

    @Test("One invalid saved profile does not discard valid profiles")
    func recoversValidProfilesAroundInvalidEntry() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let originalData = Data(
            """
            [
              {
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "First",
                "hostname": "irc.first.example",
                "port": 6697,
                "useTLS": true
              },
              {
                "id": "22222222-2222-2222-2222-222222222222",
                "name": "Broken",
                "hostname": "irc.broken.example",
                "useTLS": true
              },
              {
                "id": "33333333-3333-3333-3333-333333333333",
                "name": "Third",
                "hostname": "irc.third.example",
                "port": 6667,
                "useTLS": false
              }
            ]
            """.utf8
        )
        defaults.set(originalData, forKey: ServerProfileStore.profilesKey)

        let loaded = ServerProfileStore.load(from: defaults, recommended: [])
        let persistedData = try #require(defaults.data(forKey: ServerProfileStore.profilesKey))
        let persisted = try JSONDecoder().decode([ServerProfile].self, from: persistedData)

        #expect(loaded.map(\.name) == ["First", "Third"])
        #expect(persisted.map(\.name) == ["First", "Third"])
        #expect(defaults.data(forKey: ServerProfileStore.decodeFailureBackupKey) == originalData)
    }

    @Test("Malformed profile storage is preserved instead of overwritten as first launch")
    func preservesMalformedTopLevelData() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let malformedData = Data(#"{"not":"an array"}"#.utf8)
        defaults.set(malformedData, forKey: ServerProfileStore.profilesKey)

        let loaded = ServerProfileStore.load(from: defaults)

        #expect(loaded == ServerProfile.recommended)
        #expect(defaults.data(forKey: ServerProfileStore.profilesKey) == malformedData)
        #expect(defaults.data(forKey: ServerProfileStore.decodeFailureBackupKey) == malformedData)
    }

    @Test("New bundled presets are persisted with the UUID assigned on first load")
    func persistsNewPresetIdentity() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let existingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let firstNewID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let nextLaunchNewID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let existing = ServerProfile(
            id: existingID,
            name: "Existing",
            hostname: "irc.existing.example",
            port: 6697,
            useTLS: true,
            isBuiltIn: true,
            presetID: "existing"
        )
        defaults.set(try JSONEncoder().encode([existing]), forKey: ServerProfileStore.profilesKey)

        let firstLaunchRecommendations = [
            existing,
            ServerProfile(
                id: firstNewID,
                name: "New Network",
                hostname: "irc.new.example",
                port: 6697,
                useTLS: true,
                isBuiltIn: true,
                presetID: "new-network"
            )
        ]
        let firstLoad = ServerProfileStore.load(
            from: defaults,
            recommended: firstLaunchRecommendations
        )
        #expect(firstLoad.first { $0.presetID == "new-network" }?.id == firstNewID)

        let nextLaunchRecommendations = [
            existing,
            ServerProfile(
                id: nextLaunchNewID,
                name: "New Network",
                hostname: "irc.new.example",
                port: 6697,
                useTLS: true,
                isBuiltIn: true,
                presetID: "new-network"
            )
        ]
        let secondLoad = ServerProfileStore.load(
            from: defaults,
            recommended: nextLaunchRecommendations
        )

        #expect(secondLoad.first { $0.presetID == "new-network" }?.id == firstNewID)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ServerProfileTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
