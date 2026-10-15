import AppKit
import Testing
@testable import Netsplit

@Suite("Composer substitutions")
@MainActor
struct IRCComposerSubstitutionTests {
    typealias Setting = IRCComposerSubstitutionPreferences.Setting

    @Test("Opening a composer preserves AppKit defaults without saving them")
    func preservesSystemDefaults() throws {
        let suiteName = "Netsplit.SubstitutionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = IRCComposerSubstitutionPreferences(defaults: defaults)
        let view = IRCComposerNativeTextView()
        view.isRichText = false
        let originalValues = Setting.allCases.map { view[keyPath: $0.keyPath] }

        view.configureSubstitutions(using: preferences)

        #expect(Setting.allCases.map { view[keyPath: $0.keyPath] } == originalValues)
        #expect(preferences.overrides.isEmpty)
        #expect(defaults.persistentDomain(forName: suiteName)?.isEmpty != false)
    }

    @Test("Substitutions menu choices survive new composers and reloaded app state", arguments: Setting.allCases)
    func persistsMenuChoices(setting: Setting) throws {
        let suiteName = "Netsplit.SubstitutionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = IRCAppState(defaults: defaults, credentialStore: IRCInMemoryCredentialStore())
        let first = makeComposer(preferences: state.composerSubstitutions)
        let existing = makeComposer(preferences: state.composerSubstitutions)
        let initialValue = first[keyPath: setting.keyPath]

        // Exercise AppKit's real actions in both directions, including false.
        for expected in [!initialValue, initialValue] {
            first.perform(toggleAction(for: setting), with: nil)
            #expect(first[keyPath: setting.keyPath] == expected)
            #expect(existing[keyPath: setting.keyPath] == expected)
            #expect(defaults.object(forKey: setting.defaultsKey) as? Bool == expected)
            #expect(state.composerSubstitutions.overrides == [setting: expected])

            let newComposer = makeComposer(preferences: state.composerSubstitutions)
            #expect(newComposer[keyPath: setting.keyPath] == expected)

            let reloadedDefaults = try #require(UserDefaults(suiteName: suiteName))
            let reloaded = IRCAppState(defaults: reloadedDefaults, credentialStore: IRCInMemoryCredentialStore())
            let restored = IRCComposerNativeTextView()
            restored.isRichText = false
            restored[keyPath: setting.keyPath] = !expected
            restored.configureSubstitutions(using: reloaded.composerSubstitutions)
            #expect(restored[keyPath: setting.keyPath] == expected)
            #expect(reloaded.composerSubstitutions.overrides == [setting: expected])
        }
    }

    @Test("Property changes from the Substitutions panel persist without leaking to another preferences suite")
    func persistsPanelChoicesInIsolatedStore() throws {
        let suiteName = "Netsplit.SubstitutionTests.\(UUID().uuidString)"
        let otherSuiteName = "Netsplit.SubstitutionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let otherDefaults = try #require(UserDefaults(suiteName: otherSuiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            otherDefaults.removePersistentDomain(forName: otherSuiteName)
        }
        let preferences = IRCComposerSubstitutionPreferences(defaults: defaults)
        let view = makeComposer(preferences: preferences)
        let otherPreferences = IRCComposerSubstitutionPreferences(defaults: otherDefaults)
        let otherView = makeComposer(preferences: otherPreferences)
        let otherValues = Setting.allCases.map { otherView[keyPath: $0.keyPath] }

        for enabled in [false, true] {
            for setting in Setting.allCases {
                view[keyPath: setting.keyPath] = enabled
            }
            let restored = makeComposer(preferences: IRCComposerSubstitutionPreferences(defaults: defaults))
            #expect(Setting.allCases.allSatisfy { restored[keyPath: $0.keyPath] == enabled })
        }

        #expect(Setting.allCases.map { otherView[keyPath: $0.keyPath] } == otherValues)
        #expect(otherPreferences.overrides.isEmpty)
        #expect(otherDefaults.persistentDomain(forName: otherSuiteName)?.isEmpty != false)
    }

    private func makeComposer(preferences: IRCComposerSubstitutionPreferences) -> IRCComposerNativeTextView {
        let view = IRCComposerNativeTextView()
        view.isRichText = false
        view.configureSubstitutions(using: preferences)
        return view
    }

    private func toggleAction(for setting: Setting) -> Selector {
        switch setting {
        case .smartInsertDelete: return #selector(NSTextView.toggleSmartInsertDelete(_:))
        case .quotes: return #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))
        case .dashes: return #selector(NSTextView.toggleAutomaticDashSubstitution(_:))
        case .links: return #selector(NSTextView.toggleAutomaticLinkDetection(_:))
        case .dataDetection: return #selector(NSTextView.toggleAutomaticDataDetection(_:))
        case .textReplacement: return #selector(NSTextView.toggleAutomaticTextReplacement(_:))
        }
    }
}
