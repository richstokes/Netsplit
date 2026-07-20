//
//  IRCModels.swift
//  Netsplit
//

import Foundation
import SwiftUI

enum IRCApplicationAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum IRCMessageSpacing: String, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: Self { self }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        }
    }
}

enum IRCChannelEventVisibility: String, CaseIterable, Identifiable {
    case alwaysShow
    case hideInBusyChannels
    case alwaysHide

    static let busyChannelMemberThreshold = 100

    var id: Self { self }

    var label: String {
        switch self {
        case .alwaysShow: return "Always Show"
        case .hideInBusyChannels: return "Hide in Busy Channels"
        case .alwaysHide: return "Always Hide"
        }
    }

    func shouldShow(memberCount: Int) -> Bool {
        switch self {
        case .alwaysShow:
            return true
        case .hideInBusyChannels:
            return memberCount < Self.busyChannelMemberThreshold
        case .alwaysHide:
            return false
        }
    }
}

enum IRCChannelEventKind: Hashable {
    case join
    case part
    case quit
    case nickname
    case topic
    case mode
}

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
    var useSSHTunnel: Bool?
    var sshHostname: String?
    var sshPort: UInt16?
    var sshUsername: String?
    var sshKeyFilename: String?
    /// OpenSSH-formatted public host key learned on the first successful SSH
    /// handshake. This is not secret and is persisted with the profile so a
    /// changed SSH host identity is rejected on later connections.
    var sshTrustedHostKey: String?
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
        useSSHTunnel: Bool? = nil,
        sshHostname: String? = nil,
        sshPort: UInt16? = nil,
        sshUsername: String? = nil,
        sshKeyFilename: String? = nil,
        sshTrustedHostKey: String? = nil,
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
        self.useSSHTunnel = useSSHTunnel
        self.sshHostname = sshHostname
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshKeyFilename = sshKeyFilename
        self.sshTrustedHostKey = sshTrustedHostKey
        self.presetID = presetID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, useTLS, autoConnect, isBuiltIn
        case nicknameOverride, isPresetModified, favoriteChannels, mutedNicknames, useSASL, saslUsername
        case useSSHTunnel, sshHostname, sshPort, sshUsername, sshKeyFilename, sshTrustedHostKey, presetID
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
        useSSHTunnel = try container.decodeIfPresent(Bool.self, forKey: .useSSHTunnel)
        sshHostname = try container.decodeIfPresent(String.self, forKey: .sshHostname)
        sshPort = try container.decodeIfPresent(UInt16.self, forKey: .sshPort)
        sshUsername = try container.decodeIfPresent(String.self, forKey: .sshUsername)
        sshKeyFilename = try container.decodeIfPresent(String.self, forKey: .sshKeyFilename)
        sshTrustedHostKey = try container.decodeIfPresent(String.self, forKey: .sshTrustedHostKey)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
    }

    static let recommended: [ServerProfile] = [
        .init(name: "Libera.Chat", hostname: "irc.libera.chat", port: 6697, useTLS: true, isBuiltIn: true, presetID: "libera-chat"),
        .init(name: "Snoonet", hostname: "irc.snoonet.org", port: 6697, useTLS: true, isBuiltIn: true, presetID: "snoonet"),
        .init(name: "OFTC", hostname: "irc.oftc.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "oftc"),
        .init(name: "EFnet", hostname: "irc.efnet.org", port: 6667, useTLS: false, isBuiltIn: true, presetID: "efnet"),
        .init(name: "Freenode", hostname: "irc.freenode.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "freenode"),
        .init(name: "DALnet", hostname: "irc.dal.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "dalnet"),
        .init(name: "Undernet", hostname: "irc.undernet.org", port: 6667, useTLS: false, isBuiltIn: true, presetID: "undernet"),
        .init(name: "QuakeNet", hostname: "irc.quakenet.org", port: 6667, useTLS: false, isBuiltIn: true, presetID: "quakenet"),
        .init(name: "IRCNet", hostname: "irc.ircnet.com", port: 6697, useTLS: true, isBuiltIn: true, presetID: "ircnet"),
        .init(name: "Rizon", hostname: "irc.rizon.net", port: 6697, useTLS: true, isBuiltIn: true, presetID: "rizon"),
        .init(name: "HybridIRC", hostname: "irc.hybridirc.com", port: 6697, useTLS: true, isBuiltIn: true, presetID: "hybridirc"),
        .init(name: "MansionNET", hostname: "irc.inthemansion.com", port: 6697, useTLS: true, isBuiltIn: true, presetID: "mansionnet")
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

enum IRCIdentityValidation {
    static func nicknameError(_ value: String) -> String? {
        let nickname = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { return "Enter a nickname." }
        guard nickname == value else { return "Nicknames cannot begin or end with whitespace." }
        guard !nickname.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            return "Nicknames cannot contain whitespace or control characters."
        }
        let leadingSymbols = "[]\\`_^{|}"
        guard let first = nickname.first,
              first.isLetter || leadingSymbols.contains(first) else {
            return "Nicknames must begin with a letter or nickname symbol."
        }
        let remainingSymbols = "-[]\\`_^{|}"
        guard nickname.allSatisfy({ $0.isLetter || $0.isNumber || remainingSymbols.contains($0) }) else {
            return "The nickname contains a character reserved by IRC."
        }
        return nil
    }

    static func isValidNickname(_ value: String) -> Bool {
        nicknameError(value) == nil
    }
}

struct IRCMessage: Identifiable, Hashable {
    let id = UUID()
    var sender: String
    var text: String
    var timestamp = Date()
    var isSystem = false
    var channelLinks: [String] = []
    var channelEventKind: IRCChannelEventKind?
    var channelMemberCount: Int?
    var nicknameColorKey: String?

    var resolvedNicknameColorKey: String {
        nicknameColorKey ?? sender
    }
}

struct Conversation: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var serverID: UUID
    var hasUnread = false
    var hasMention = false
    var mentionRevision = 0
}

enum IRCMentionPolicy {
    static func containsMention(
        of nickname: String,
        in message: String,
        caseMapping: IRCCaseMapping
    ) -> Bool {
        let normalizedNickname = caseMapping.normalize(nickname)
        let normalizedMessage = caseMapping.normalize(message)
        guard !normalizedNickname.isEmpty, !normalizedMessage.isEmpty else { return false }

        var searchStart = normalizedMessage.startIndex
        while searchStart < normalizedMessage.endIndex,
              let match = normalizedMessage.range(
                of: normalizedNickname,
                range: searchStart..<normalizedMessage.endIndex
              ) {
            let hasLeadingBoundary = match.lowerBound == normalizedMessage.startIndex
                || !isNicknameCharacter(normalizedMessage[normalizedMessage.index(before: match.lowerBound)])
            let hasTrailingBoundary = match.upperBound == normalizedMessage.endIndex
                || !isNicknameCharacter(normalizedMessage[match.upperBound])
            if hasLeadingBoundary && hasTrailingBoundary { return true }
            searchStart = match.upperBound
        }
        return false
    }

    private static func isNicknameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "-[]\\`_^{|}".contains(character)
    }
}

enum IRCWhoisChannelParser {
    static func channels(from value: String) -> [String] {
        var seen = Set<String>()
        return value.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
            guard let channel = channelName(from: String(token)), seen.insert(channel).inserted else { return nil }
            return channel
        }
    }

    private static func channelName(from token: String) -> String? {
        var channel = token
        while channel.count > 1 {
            let first = channel.first!
            let second = channel[channel.index(after: channel.startIndex)]
            let isUnambiguousMembershipPrefix = "~@%".contains(first)
                || ((first == "+" || first == "&") && "#&+!".contains(second))
            guard isUnambiguousMembershipPrefix else { break }
            channel.removeFirst()
        }
        guard let first = channel.first, "#&+!".contains(first) else { return nil }
        return channel
    }
}

enum IRCInternalLink {
    private static let scheme = "netsplit"
    private static let joinChannelHost = "join-channel"

    static func channelURL(for channel: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = joinChannelHost
        components.queryItems = [URLQueryItem(name: "name", value: channel)]
        return components.url
    }

    static func channelName(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == joinChannelHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let channel = components.queryItems?.first(where: { $0.name == "name" })?.value,
              let first = channel.first,
              "#&+!".contains(first) else { return nil }
        return channel
    }
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
