//
//  IRCModels.swift
//  Netsplit
//

import Foundation
import SwiftUI

struct ServerProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var hostname: String
    var port: UInt16
    var useTLS: Bool
    var autoConnect: Bool = false
    var isBuiltIn: Bool = false
    var nicknameOverride: String?
    var isPresetModified: Bool?
    var favoriteChannels: [String]?
    var mutedNicknames: [String]?
    var useSASL: Bool?
    var saslUsername: String?
    /// Stable identity for bundled presets. The display name is user-editable
    /// and therefore cannot safely be used to match a profile back to a preset.
    var presetID: String?

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: UInt16,
        useTLS: Bool,
        autoConnect: Bool = false,
        isBuiltIn: Bool = false,
        nicknameOverride: String? = nil,
        isPresetModified: Bool? = nil,
        favoriteChannels: [String]? = nil,
        mutedNicknames: [String]? = nil,
        useSASL: Bool? = nil,
        saslUsername: String? = nil,
        presetID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.useTLS = useTLS
        self.autoConnect = autoConnect
        self.isBuiltIn = isBuiltIn
        self.nicknameOverride = nicknameOverride
        self.isPresetModified = isPresetModified
        self.favoriteChannels = favoriteChannels
        self.mutedNicknames = mutedNicknames
        self.useSASL = useSASL
        self.saslUsername = saslUsername
        self.presetID = presetID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, useTLS, autoConnect, isBuiltIn
        case nicknameOverride, isPresetModified, favoriteChannels, mutedNicknames, useSASL, saslUsername, presetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(UInt16.self, forKey: .port)
        useTLS = try container.decode(Bool.self, forKey: .useTLS)
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        nicknameOverride = try container.decodeIfPresent(String.self, forKey: .nicknameOverride)
        isPresetModified = try container.decodeIfPresent(Bool.self, forKey: .isPresetModified)
        favoriteChannels = try container.decodeIfPresent([String].self, forKey: .favoriteChannels)
        mutedNicknames = try container.decodeIfPresent([String].self, forKey: .mutedNicknames)
        useSASL = try container.decodeIfPresent(Bool.self, forKey: .useSASL)
        saslUsername = try container.decodeIfPresent(String.self, forKey: .saslUsername)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
    }

    static let recommended: [ServerProfile] = [
        .init(name: "Libera.Chat", hostname: "irc.libera.chat", port: 6697, useTLS: true, isBuiltIn: true, presetID: "libera-chat"),
        .init(name: "Snoonet", hostname: "irc.snoonet.org", port: 6697, useTLS: true, isBuiltIn: true, presetID: "snoonet"),
        .init(name: "OFTC", hostname: "irc.oftc.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "oftc"),
        .init(name: "EFnet", hostname: "irc.efnet.org", port: 6697, useTLS: true, isBuiltIn: true, presetID: "efnet"),
        .init(name: "Freenode", hostname: "irc.freenode.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "freenode"),
        .init(name: "Undernet", hostname: "irc.undernet.org", port: 6667, useTLS: false, isBuiltIn: true, presetID: "undernet"),
        .init(name: "QuakeNet", hostname: "irc.quakenet.org", port: 6667, useTLS: false, isBuiltIn: true, presetID: "quakenet"),
        .init(name: "IRCNet", hostname: "irc.ircnet.com", port: 6667, useTLS: false, isBuiltIn: true, presetID: "ircnet"),
        .init(name: "Rizon", hostname: "irc.rizon.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "rizon")
    ]
}

enum IRCCaseMapping: String {
    case ascii
    case rfc1459
    case strictRFC1459 = "strict-rfc1459"

    func normalize(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            let byte = scalar.value
            if byte >= 65, byte <= 90 {
                return Character(UnicodeScalar(byte + 32)!)
            }
            switch self {
            case .ascii:
                return Character(scalar)
            case .strictRFC1459:
                switch scalar {
                case "[", "{": return "{"
                case "]", "}": return "}"
                case "\\", "|": return "|"
                default: return Character(scalar)
                }
            case .rfc1459:
                switch scalar {
                case "[", "{": return "{"
                case "]", "}": return "}"
                case "\\", "|": return "|"
                case "^", "~": return "~"
                default: return Character(scalar)
                }
            }
        })
    }
}

struct IRCMessage: Identifiable, Hashable {
    let id = UUID()
    var sender: String
    var text: String
    var timestamp = Date()
    var isSystem = false
}

struct Conversation: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var serverID: UUID
    var hasUnread = false
}

struct ChannelListing: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var userCount: Int
    var topic: String
}

struct ChannelMember: Identifiable, Hashable {
    var nickname: String
    /// IRC servers can grant more than one membership mode (for example +v
    /// followed by +o). Keep every role so a later -o correctly falls back to
    /// the remaining privilege in the member list.
    var modes: Set<Character>

    init(nickname: String, prefix: Character? = nil, modes: Set<Character>? = nil) {
        self.nickname = nickname
        if let modes {
            self.modes = modes
        } else if let prefix, let mode = Self.modeByPrefix[prefix] {
            self.modes = [mode]
        } else {
            self.modes = []
        }
    }

    // Equality/deduplication is performed by IRCAppState with the server's
    // advertised CASEMAPPING. This exact value is only SwiftUI row identity.
    var id: String { nickname }

    var prefix: Character? {
        for mode in Self.rolePriority where modes.contains(mode) {
            return Self.prefixByMode[mode]
        }
        return nil
    }

    var role: String? {
        switch prefix {
        case "~": "Owner"
        case "&": "Admin"
        case "@": "Operator"
        case "%": "Half-op"
        case "+": "Voice"
        default: nil
        }
    }

    private static let modeByPrefix: [Character: Character] = [
        "~": "q", "&": "a", "@": "o", "%": "h", "+": "v"
    ]
    private static let prefixByMode: [Character: Character] = [
        "q": "~", "a": "&", "o": "@", "h": "%", "v": "+"
    ]
    private static let rolePriority: [Character] = ["q", "a", "o", "h", "v"]
}

enum SidebarItem: Hashable {
    case connectionCenter
    case server(UUID)
    case channel(UUID)
    case directMessage(UUID)

    var icon: String {
        switch self {
        case .connectionCenter: "bolt.horizontal.circle"
        case .server: "network"
        case .channel: "number"
        case .directMessage: "person.crop.circle"
        }
    }
}

enum ConnectionStatus: Equatable {
    case offline, connecting, online, failed(String)

    var label: String {
        switch self {
        case .offline: "Offline"
        case .connecting: "Connecting…"
        case .online: "Connected"
        case .failed: "Connection failed"
        }
    }

    var tint: Color {
        switch self {
        case .online: .green
        case .connecting: .orange
        case .failed: .red
        case .offline: .secondary
        }
    }
}
