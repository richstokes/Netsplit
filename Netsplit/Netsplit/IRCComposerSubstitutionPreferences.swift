import AppKit
import Combine

@MainActor
final class IRCComposerSubstitutionPreferences {
    enum Setting: String, CaseIterable {
        case smartInsertDelete
        case quotes
        case dashes
        case links
        case dataDetection
        case textReplacement

        var defaultsKey: String { "composerSubstitutions.\(rawValue)" }

        var keyPath: ReferenceWritableKeyPath<NSTextView, Bool> {
            switch self {
            case .smartInsertDelete: return \.smartInsertDeleteEnabled
            case .quotes: return \.isAutomaticQuoteSubstitutionEnabled
            case .dashes: return \.isAutomaticDashSubstitutionEnabled
            case .links: return \.isAutomaticLinkDetectionEnabled
            case .dataDetection: return \.isAutomaticDataDetectionEnabled
            case .textReplacement: return \.isAutomaticTextReplacementEnabled
            }
        }
    }

    // Only explicit choices are stored. An absent key leaves AppKit's system
    // default intact, while a stored false must override an enabled default.
    @Published private(set) var overrides: [Setting: Bool]
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        overrides = Dictionary(uniqueKeysWithValues: Setting.allCases.compactMap { setting in
            guard let enabled = defaults.object(forKey: setting.defaultsKey) as? Bool else {
                return nil
            }
            return (setting, enabled)
        })
    }

    func set(_ enabled: Bool, for setting: Setting) {
        guard overrides[setting] != enabled else { return }
        defaults.set(enabled, forKey: setting.defaultsKey)
        overrides[setting] = enabled
    }
}
