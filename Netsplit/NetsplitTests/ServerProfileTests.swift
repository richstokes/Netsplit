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
        #expect(profile.favoriteChannels == nil)
        #expect(profile.useSASL == nil)
        #expect(profile.useSSHTunnel == nil)
    }

    @Test("Round-trips security and connection settings")
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
            favoriteChannels: ["#swift"],
            mutedNicknames: ["bot"],
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
}
