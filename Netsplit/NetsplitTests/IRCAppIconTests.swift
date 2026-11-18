import AppKit
import Foundation
import Testing
@testable import Netsplit

@Suite("App icon preference")
struct IRCAppIconTests {
    @Test("The classic icon is the default, and a saved choice survives a relaunch")
    func persistsSelection() throws {
        let suiteName = "IRCAppIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = IRCAppState(defaults: defaults, credentialStore: IRCInMemoryCredentialStore())
        #expect(state.appIcon == .classic)

        state.appIcon = .bubble
        let reloaded = IRCAppState(defaults: defaults, credentialStore: IRCInMemoryCredentialStore())
        #expect(reloaded.appIcon == .bubble)
    }

    @Test("An icon removed in a later version falls back to the default")
    func unknownSelectionFallsBack() throws {
        let suiteName = "IRCAppIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("retired-icon", forKey: "appIcon")

        let state = IRCAppState(defaults: defaults, credentialStore: IRCInMemoryCredentialStore())
        #expect(state.appIcon == .default)
    }

    @Test("Every alternate icon has artwork in the asset catalog")
    func alternateIconsHaveArtwork() {
        #expect(IRCAppIcon.default.assetName == nil)
        for appIcon in IRCAppIcon.allCases {
            guard let assetName = appIcon.assetName else { continue }
            #expect(NSImage(named: assetName) != nil, "Missing asset \(assetName)")
        }
    }
}
