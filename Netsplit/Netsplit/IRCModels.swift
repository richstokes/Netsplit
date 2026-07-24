//
//  IRCModels.swift
//  Netsplit
//

import AppKit
import Foundation
import OSLog
import SwiftUI

enum IRCApplicationAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case catppuccinLatte
    case catppuccinMocha
    case githubLight
    case githubDark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .catppuccinLatte: return "Catppuccin Latte"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .githubLight: return "GitHub Light"
        case .githubDark: return "GitHub Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .catppuccinLatte, .githubLight: return .light
        case .dark, .catppuccinMocha, .githubDark: return .dark
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

enum IRCChatFont: String, CaseIterable, Identifiable {
    case system
    case rounded
    case monospaced

    static let `default`: IRCChatFont = .monospaced

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System (SF Pro)"
        case .rounded: return "SF Rounded"
        case .monospaced: return "SF Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let systemDesign: NSFontDescriptor.SystemDesign?
        switch self {
        case .system: systemDesign = nil
        case .rounded: systemDesign = .rounded
        case .monospaced: systemDesign = .monospaced
        }
        guard let systemDesign,
              let descriptor = base.fontDescriptor.withDesign(systemDesign) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
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

enum IRCNoticeRoutingPolicy {
    enum Destination: Equatable {
        case server
        case directMessage
    }

    static func fallbackDestination(
        sender: String,
        prefix: String?,
        caseMapping: IRCCaseMapping
    ) -> Destination {
        guard prefix?.contains("!") == true else { return .server }
        return caseMapping.normalize(sender) == caseMapping.normalize("Global")
            ? .server
            : .directMessage
    }
}

struct IRCIncomingInvite: Equatable {
    let inviter: String
    let channel: String

    init?(
        wire: IRCWireMessage,
        localNickname: String,
        caseMapping: IRCCaseMapping,
        channelTypes: Set<Character> = Set("#&+!")
    ) {
        guard wire.command == "INVITE",
              let target = wire.parameters.first,
              caseMapping.normalize(target) == caseMapping.normalize(localNickname),
              let prefix = wire.prefix else { return nil }

        let inviter = prefix.split(separator: "!", maxSplits: 1).first.map(String.init) ?? ""
        guard !inviter.isEmpty,
              caseMapping.normalize(inviter) != caseMapping.normalize(localNickname) else { return nil }

        let rawChannel = wire.trailing ?? wire.parameters.dropFirst().first
        let channel = rawChannel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard channel.first.map(channelTypes.contains) == true else { return nil }

        self.inviter = inviter
        self.channel = channel
    }
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
    /// When nil, the server follows the global mention-notification setting.
    var mentionNotificationsOverride: Bool?
    var isPresetModified: Bool?
    var favoriteChannels: [String]?
    var ignoredNicknames: [String]?
    var mutedConversationNames: [String]?
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
        mentionNotificationsOverride: Bool? = nil,
        isPresetModified: Bool? = nil,
        favoriteChannels: [String]? = nil,
        ignoredNicknames: [String]? = nil,
        mutedConversationNames: [String]? = nil,
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
        self.mentionNotificationsOverride = mentionNotificationsOverride
        self.isPresetModified = isPresetModified
        self.favoriteChannels = favoriteChannels
        self.ignoredNicknames = ignoredNicknames
        self.mutedConversationNames = mutedConversationNames
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
        case nicknameOverride, mentionNotificationsOverride, isPresetModified, favoriteChannels
        case ignoredNicknames, mutedConversationNames
        case useSASL, saslUsername
        case useSSHTunnel, sshHostname, sshPort, sshUsername, sshKeyFilename, sshTrustedHostKey, presetID
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case mutedNicknames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(UInt16.self, forKey: .port)
        useTLS = try container.decode(Bool.self, forKey: .useTLS)
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        nicknameOverride = try container.decodeIfPresent(String.self, forKey: .nicknameOverride)
        mentionNotificationsOverride = try container.decodeIfPresent(Bool.self, forKey: .mentionNotificationsOverride)
        isPresetModified = try container.decodeIfPresent(Bool.self, forKey: .isPresetModified)
        favoriteChannels = try container.decodeIfPresent([String].self, forKey: .favoriteChannels)
        ignoredNicknames = try container.decodeIfPresent([String].self, forKey: .ignoredNicknames)
            ?? legacyContainer.decodeIfPresent([String].self, forKey: .mutedNicknames)
        mutedConversationNames = try container.decodeIfPresent([String].self, forKey: .mutedConversationNames)
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

enum ServerProfileStore {
    static let profilesKey = "profiles"
    static let decodeFailureBackupKey = "profiles.decodeFailureBackup"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Netsplit",
        category: "ServerProfileStore"
    )

    static func load(
        from defaults: UserDefaults,
        recommended: [ServerProfile] = ServerProfile.recommended
    ) -> [ServerProfile] {
        guard let data = defaults.data(forKey: profilesKey) else {
            return recommended
        }

        do {
            let decoded = try decodeProfiles(from: data)
            if decoded.droppedCount > 0 {
                preserveDecodeFailureBackup(data, in: defaults)
                logger.error(
                    "Recovered \(decoded.profiles.count, privacy: .public) server profiles and skipped \(decoded.droppedCount, privacy: .public) invalid entries."
                )
            }

            let refreshed = refreshedProfiles(from: decoded.profiles, recommended: recommended)
            if decoded.droppedCount > 0 || refreshed != decoded.profiles {
                save(refreshed, to: defaults)
            }
            return refreshed
        } catch {
            preserveDecodeFailureBackup(data, in: defaults)
            logger.error("Could not decode saved server profiles: \(error.localizedDescription, privacy: .public)")
            return recommended
        }
    }

    @discardableResult
    static func save(_ profiles: [ServerProfile], to defaults: UserDefaults) -> Bool {
        do {
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: profilesKey)
            return true
        } catch {
            logger.error("Could not encode server profiles: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func refreshedProfiles(
        from saved: [ServerProfile],
        recommended: [ServerProfile] = ServerProfile.recommended
    ) -> [ServerProfile] {
        let refreshed = saved.map { profile -> ServerProfile in
            guard profile.isBuiltIn,
                  let matchedPreset = preset(matching: profile, in: recommended) else {
                return profile
            }
            if profile.isPresetModified == true {
                var migrated = profile
                migrated.presetID = matchedPreset.presetID
                return migrated
            }
            var current = matchedPreset
            current.id = profile.id
            current.autoConnect = profile.autoConnect
            current.mentionNotificationsOverride = profile.mentionNotificationsOverride
            current.favoriteChannels = profile.favoriteChannels
            current.ignoredNicknames = profile.ignoredNicknames
            current.mutedConversationNames = profile.mutedConversationNames
            current.useSASL = profile.useSASL
            current.saslUsername = profile.saslUsername
            current.useSSHTunnel = profile.useSSHTunnel
            current.sshHostname = profile.sshHostname
            current.sshPort = profile.sshPort
            current.sshUsername = profile.sshUsername
            current.sshKeyFilename = profile.sshKeyFilename
            current.sshTrustedHostKey = profile.sshTrustedHostKey
            return current
        }
        let missing = recommended.filter { recommendedProfile in
            !refreshed.contains { profile in
                profile.isBuiltIn && profile.presetID == recommendedProfile.presetID
            }
        }
        return refreshed + missing
    }

    private static func decodeProfiles(from data: Data) throws -> DecodedServerProfiles {
        let entries = try JSONDecoder().decode([FailableServerProfile].self, from: data)
        let profiles = entries.compactMap(\.profile)
        return DecodedServerProfiles(
            profiles: profiles,
            droppedCount: entries.count - profiles.count
        )
    }

    private static func preserveDecodeFailureBackup(_ data: Data, in defaults: UserDefaults) {
        guard defaults.data(forKey: decodeFailureBackupKey) == nil else { return }
        defaults.set(data, forKey: decodeFailureBackupKey)
    }

    static func preset(
        matching profile: ServerProfile,
        in recommended: [ServerProfile] = ServerProfile.recommended
    ) -> ServerProfile? {
        if let presetID = profile.presetID,
           let preset = recommended.first(where: { $0.presetID == presetID }) {
            return preset
        }
        // Migrate profiles saved before stable preset IDs existed. Hostname is
        // also checked so a renamed built-in can still recover its identity.
        return recommended.first {
            $0.name.caseInsensitiveCompare(profile.name) == .orderedSame
                || $0.hostname.caseInsensitiveCompare(profile.hostname) == .orderedSame
        }
    }
}

private struct FailableServerProfile: Decodable {
    let profile: ServerProfile?

    init(from decoder: Decoder) throws {
        profile = try? ServerProfile(from: decoder)
    }
}

private struct DecodedServerProfiles {
    let profiles: [ServerProfile]
    let droppedCount: Int
}

enum IRCServerOrdering {
    static func alphabetically(_ profiles: [ServerProfile]) -> [ServerProfile] {
        profiles.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            let hostnameOrder = lhs.hostname.localizedStandardCompare(rhs.hostname)
            if hostnameOrder != .orderedSame {
                return hostnameOrder == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

enum IRCCaseMapping: String {
    case ascii
    case rfc1459
    case strictRFC1459 = "strict-rfc1459"

    func normalize(_ value: String) -> String {
        var result = String()
        result.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            let byte = scalar.value
            if byte >= 65, byte <= 90 {
                result.unicodeScalars.append(UnicodeScalar(byte + 32)!)
                continue
            }
            switch self {
            case .ascii:
                result.unicodeScalars.append(scalar)
            case .strictRFC1459:
                switch scalar {
                case "[", "{": result.append("{")
                case "]", "}": result.append("}")
                case "\\", "|": result.append("|")
                default: result.unicodeScalars.append(scalar)
                }
            case .rfc1459:
                switch scalar {
                case "[", "{": result.append("{")
                case "]", "}": result.append("}")
                case "\\", "|": result.append("|")
                case "^", "~": result.append("~")
                default: result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

struct IRCIgnoreSnapshot {
    private let normalizedNicknames: Set<String>
    private let caseMapping: IRCCaseMapping

    init(nicknames: [String], caseMapping: IRCCaseMapping) {
        self.caseMapping = caseMapping
        normalizedNicknames = Set(nicknames.map(caseMapping.normalize))
    }

    func contains(_ nickname: String) -> Bool {
        normalizedNicknames.contains(caseMapping.normalize(nickname))
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
    var isNotice = false
    var channelLinks: [String] = []
    /// The channel-name prefixes advertised by the originating server. Nil
    /// keeps the broad legacy defaults for messages created outside a session.
    var channelTypes: Set<Character>?
    var channelEventKind: IRCChannelEventKind?
    var channelMemberCount: Int?
    var nicknameColorKey: String?

    var resolvedNicknameColorKey: String {
        nicknameColorKey ?? sender
    }

    var interactiveNickname: String? {
        guard !isSystem, !isNotice else { return nil }
        return nicknameColorKey ?? sender
    }
}

enum IRCMessageTextRenderer {
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func displayText(for message: IRCMessage) -> String {
        guard message.isSystem, message.sender != "System", message.sender != "•" else {
            return message.text
        }
        return "\(message.sender) \(message.text)"
    }

    static func plainText(_ text: String) -> String {
        IRCFormattingParser.parse(text).plainText
    }

    static func plainDisplayText(for message: IRCMessage) -> String {
        plainText(displayText(for: message))
    }

    static func webURLs(for message: IRCMessage) -> [URL] {
        let text = plainDisplayText(for: message)
        guard let linkDetector else { return [] }

        var seen = Set<URL>()
        let fullRange = NSRange(text.startIndex..., in: text)
        return linkDetector.matches(in: text, range: fullRange).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  seen.insert(url).inserted else { return nil }
            return url
        }
    }

    static func linkifiedText(
        for message: IRCMessage,
        rendersIRCFormatting: Bool = false
    ) -> AttributedString {
        let parsed = IRCFormattingParser.parse(displayText(for: message))
        let text = parsed.plainText
        var attributedText = rendersIRCFormatting
            ? parsed.attributedText
            : AttributedString(text)
        if let linkDetector {
            let fullRange = NSRange(text.startIndex..., in: text)
            for match in linkDetector.matches(in: text, range: fullRange) {
                guard let url = match.url,
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      let stringRange = Range(match.range, in: text),
                      let attributedRange = Range(stringRange, in: attributedText) else { continue }
                attributedText[attributedRange].link = url
            }
        }

        for channel in message.channelLinks {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let stringRange = text.range(of: channel, range: searchStart..<text.endIndex) {
                applyChannelLink(channel, range: stringRange, to: &attributedText)
                searchStart = stringRange.upperBound
            }
        }

        for reference in IRCChannelReferenceParser.references(
            in: text,
            channelTypes: message.channelTypes ?? Set("#&+!")
        ) {
            applyChannelLink(reference.name, range: reference.range, to: &attributedText)
        }
        return attributedText
    }

    private static func applyChannelLink(
        _ channel: String,
        range stringRange: Range<String.Index>,
        to attributedText: inout AttributedString
    ) {
        guard let url = IRCInternalLink.channelURL(for: channel),
              let attributedRange = Range(stringRange, in: attributedText),
              !attributedText[attributedRange].runs.contains(where: { $0.link != nil }) else { return }
        attributedText[attributedRange].link = url
    }
}

private enum IRCFormattingParser {
    struct Result {
        let plainText: String
        let attributedText: AttributedString
    }

    private struct Style: Equatable {
        var isBold = false
        var isItalic = false
        var isUnderlined = false
        var isStruckThrough = false
        var isMonospaced = false
        var isReversed = false
        var foregroundRGB: UInt32?
        var backgroundRGB: UInt32?
    }

    private struct Segment {
        var text: String
        let style: Style
    }

    private static let bold: Unicode.Scalar = "\u{02}"
    private static let color: Unicode.Scalar = "\u{03}"
    private static let hexadecimalColor: Unicode.Scalar = "\u{04}"
    private static let monospace: Unicode.Scalar = "\u{11}"
    private static let reset: Unicode.Scalar = "\u{0F}"
    private static let reverse: Unicode.Scalar = "\u{16}"
    private static let italic: Unicode.Scalar = "\u{1D}"
    private static let strikethrough: Unicode.Scalar = "\u{1E}"
    private static let underline: Unicode.Scalar = "\u{1F}"

    static func parse(_ rawText: String) -> Result {
        let scalars = Array(rawText.unicodeScalars)
        var style = Style()
        var segments: [Segment] = []
        var index = 0

        func append(_ scalar: Unicode.Scalar) {
            let value = String(scalar)
            if segments.last?.style == style {
                segments[segments.count - 1].text.append(value)
            } else {
                segments.append(Segment(text: value, style: style))
            }
        }

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case bold:
                style.isBold.toggle()
                index += 1
            case color:
                index += 1
                let foreground = parseDecimalColor(in: scalars, index: &index)
                if let foreground {
                    style.foregroundRGB = paletteRGB(for: foreground)
                    if index < scalars.count, scalars[index] == "," {
                        var backgroundIndex = index + 1
                        if let background = parseDecimalColor(in: scalars, index: &backgroundIndex) {
                            index = backgroundIndex
                            style.backgroundRGB = paletteRGB(for: background)
                        }
                    }
                } else {
                    style.foregroundRGB = nil
                    style.backgroundRGB = nil
                }
            case hexadecimalColor:
                index += 1
                let foreground = parseHexColor(in: scalars, index: &index)
                if let foreground {
                    style.foregroundRGB = foreground
                    if index < scalars.count, scalars[index] == "," {
                        var backgroundIndex = index + 1
                        if let background = parseHexColor(in: scalars, index: &backgroundIndex) {
                            index = backgroundIndex
                            style.backgroundRGB = background
                        }
                    }
                } else {
                    style.foregroundRGB = nil
                    style.backgroundRGB = nil
                }
            case monospace:
                style.isMonospaced.toggle()
                index += 1
            case reset:
                style = Style()
                index += 1
            case reverse:
                style.isReversed.toggle()
                index += 1
            case italic:
                style.isItalic.toggle()
                index += 1
            case strikethrough:
                style.isStruckThrough.toggle()
                index += 1
            case underline:
                style.isUnderlined.toggle()
                index += 1
            default:
                // IRC cannot carry embedded newlines. Strip the remaining C0
                // controls (including CTCP delimiters and bell) rather than
                // exposing their placeholder glyphs in the transcript.
                if scalar.value < 0x20, scalar != "\t" {
                    index += 1
                } else {
                    append(scalar)
                    index += 1
                }
            }
        }

        let plainText = segments.map(\.text).joined()
        var attributedText = AttributedString()
        for segment in segments {
            var attributedSegment = AttributedString(segment.text)
            apply(segment.style, to: &attributedSegment)
            attributedText.append(attributedSegment)
        }
        return Result(plainText: plainText, attributedText: attributedText)
    }

    private static func parseDecimalColor(
        in scalars: [Unicode.Scalar],
        index: inout Int
    ) -> Int? {
        let start = index
        var digits = ""
        while index < scalars.count, index - start < 2, (48...57).contains(scalars[index].value) {
            digits.append(String(scalars[index]))
            index += 1
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func parseHexColor(
        in scalars: [Unicode.Scalar],
        index: inout Int
    ) -> UInt32? {
        guard index + 6 <= scalars.count else { return nil }
        let digits = scalars[index..<(index + 6)].map(String.init).joined()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        index += 6
        return value
    }

    private static func apply(_ style: Style, to text: inout AttributedString) {
        var intents: InlinePresentationIntent = []
        if style.isBold { intents.insert(.stronglyEmphasized) }
        if style.isItalic { intents.insert(.emphasized) }
        if style.isMonospaced { intents.insert(.code) }
        if !intents.isEmpty { text.inlinePresentationIntent = intents }
        if style.isUnderlined { text.underlineStyle = .single }
        if style.isStruckThrough { text.strikethroughStyle = .single }

        var foreground = style.foregroundRGB.map(color(for:))
        var background = style.backgroundRGB.map(color(for:))
        if style.isReversed {
            if foreground == nil, background == nil {
                foreground = Color(nsColor: .textBackgroundColor)
                background = .primary
            } else {
                swap(&foreground, &background)
            }
        }
        if let foreground { text.foregroundColor = foreground }
        if let background { text.backgroundColor = background }
    }

    nonisolated private static func color(for rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    private static func paletteRGB(for code: Int) -> UInt32? {
        guard palette.indices.contains(code) else { return nil }
        return palette[code]
    }

    // mIRC's 0–98 palette. Values remain data rather than fixed SwiftUI
    // Colors so reverse-video formatting can swap foreground/background.
    private static let palette: [UInt32] = [
        0xFFFFFF, 0x000000, 0x00007F, 0x009300, 0xFF0000, 0x7F0000, 0x9C009C, 0xFC7F00,
        0xFFFF00, 0x00FC00, 0x009393, 0x00FFFF, 0x0000FC, 0xFF00FF, 0x7F7F7F, 0xD2D2D2,
        0x470000, 0x472100, 0x474700, 0x324700, 0x004700, 0x00472C, 0x004747, 0x002747,
        0x000047, 0x2E0047, 0x470047, 0x47002A, 0x740000, 0x743A00, 0x747400, 0x517400,
        0x007400, 0x007449, 0x007474, 0x004074, 0x000074, 0x4B0074, 0x740074, 0x740045,
        0xB50000, 0xB56300, 0xB5B500, 0x7DB500, 0x00B500, 0x00B571, 0x00B5B5, 0x0063B5,
        0x0000B5, 0x7500B5, 0xB500B5, 0xB5006B, 0xFF0000, 0xFF8C00, 0xFFFF00, 0xB2FF00,
        0x00FF00, 0x00FFA0, 0x00FFFF, 0x008CFF, 0x0000FF, 0xA500FF, 0xFF00FF, 0xFF0098,
        0xFF5959, 0xFFB459, 0xFFFF71, 0xCFFF60, 0x6FFF6F, 0x65FFC9, 0x6DFFFF, 0x59B4FF,
        0x5959FF, 0xC459FF, 0xFF66FF, 0xFF59BC, 0xFF9C9C, 0xFFD39C, 0xFFFF9C, 0xE2FF9C,
        0x9CFF9C, 0x9CFFDB, 0x9CFFFF, 0x9CD3FF, 0x9C9CFF, 0xDC9CFF, 0xFF9CFF, 0xFF94D3,
        0x000000, 0x131313, 0x282828, 0x363636, 0x4D4D4D, 0x656565, 0x818181, 0x9F9F9F,
        0xBCBCBC, 0xE2E2E2, 0xFFFFFF
    ]
}

final class IRCMessageTextCache {
    private struct Signature: Equatable {
        let sender: String
        let text: String
        let isSystem: Bool
        let channelLinks: [String]
        let channelTypes: Set<Character>?
        let rendersIRCFormatting: Bool

        init(message: IRCMessage, rendersIRCFormatting: Bool) {
            sender = message.sender
            text = message.text
            isSystem = message.isSystem
            channelLinks = message.channelLinks
            channelTypes = message.channelTypes
            self.rendersIRCFormatting = rendersIRCFormatting
        }
    }

    private final class Entry {
        let signature: Signature
        let value: AttributedString

        init(signature: Signature, value: AttributedString) {
            self.signature = signature
            self.value = value
        }
    }

    private let cache = NSCache<NSUUID, Entry>()

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func attributedText(
        for message: IRCMessage,
        rendersIRCFormatting: Bool = false
    ) -> AttributedString {
        let key = message.id as NSUUID
        let signature = Signature(message: message, rendersIRCFormatting: rendersIRCFormatting)
        if let cached = cache.object(forKey: key), cached.signature == signature {
            return cached.value
        }
        let value = IRCMessageTextRenderer.linkifiedText(
            for: message,
            rendersIRCFormatting: rendersIRCFormatting
        )
        cache.setObject(Entry(signature: signature, value: value), forKey: key)
        return value
    }
}

enum IRCTranscriptUpdatePolicy {
    /// Keep ordinary messages immediate, while bounding transcript layout work
    /// and array snapshot churn during sustained bursts. A full retained
    /// transcript can take tens of milliseconds to lay out, so cap an ongoing
    /// flood at four visual updates per second.
    static let burstPublicationInterval: Duration = .milliseconds(250)
}

enum IRCTranscriptPresentationPolicy {
    static let initialVisibleMessageLimit = 1_000
    static let earlierMessagePageSize = 1_000

    static func expandedVisibleMessageLimit(current: Int, total: Int) -> Int {
        min(total, current + earlierMessagePageSize)
    }
}

enum IRCTranscriptScrollPolicy {
    static let coalescingDelay: Duration = .milliseconds(60)
    static let minimumAnimatedScrollInterval: TimeInterval = 0.35
    static let animationDuration: TimeInterval = 0.12
    static let tailTolerance: CGFloat = 24

    static func shouldAnimate(lastAnimatedScroll: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastAnimatedScroll) >= minimumAnimatedScrollInterval
    }

    static func isAtBottom(
        visibleBounds: CGRect,
        contentBounds: CGRect,
        contentIsFlipped: Bool,
        tolerance: CGFloat = tailTolerance
    ) -> Bool {
        let distanceFromBottom = contentIsFlipped
            ? contentBounds.maxY - visibleBounds.maxY
            : visibleBounds.minY - contentBounds.minY
        return distanceFromBottom <= tolerance
    }

    /// Returns a value only when a live user scroll crosses the tail boundary.
    /// Avoiding redundant state writes keeps high-frequency scroll notifications
    /// from needlessly invalidating the transcript view.
    static func followingTailChange(
        from currentValue: Bool,
        visibleBounds: CGRect,
        contentBounds: CGRect,
        contentIsFlipped: Bool,
        tolerance: CGFloat = tailTolerance
    ) -> Bool? {
        let newValue = isAtBottom(
            visibleBounds: visibleBounds,
            contentBounds: contentBounds,
            contentIsFlipped: contentIsFlipped,
            tolerance: tolerance
        )
        return newValue == currentValue ? nil : newValue
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

enum IRCConversationActivityPolicy {
    static func mergedUnreadState(
        existingHasUnread: Bool,
        incomingHasUnread: Bool,
        conversationIsMuted: Bool
    ) -> Bool {
        guard !conversationIsMuted else { return false }
        return existingHasUnread || incomingHasUnread
    }
}

struct IRCServerActivity: Equatable {
    enum Indicator: Equatable {
        case unread
        case mention
    }

    let unreadConversationCount: Int
    let mentionConversationCount: Int

    init<S: Sequence>(serverID: UUID, conversations: S) where S.Element == Conversation {
        var unreadConversationCount = 0
        var mentionConversationCount = 0
        for conversation in conversations where conversation.serverID == serverID {
            if conversation.hasUnread { unreadConversationCount += 1 }
            if conversation.hasMention { mentionConversationCount += 1 }
        }
        self.unreadConversationCount = unreadConversationCount
        self.mentionConversationCount = mentionConversationCount
    }

    var hasUnread: Bool { unreadConversationCount > 0 }
    var hasMention: Bool { mentionConversationCount > 0 }

    var indicator: Indicator? {
        if hasMention { return .mention }
        if hasUnread { return .unread }
        return nil
    }

    var accessibilityDescription: String? {
        var values: [String] = []
        if mentionConversationCount > 0 {
            values.append("\(mentionConversationCount) \(mentionConversationCount == 1 ? "mention" : "mentions")")
        }
        if unreadConversationCount > 0 {
            values.append("\(unreadConversationCount) unread \(unreadConversationCount == 1 ? "conversation" : "conversations")")
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }
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

enum IRCMentionNotificationPolicy {
    static func isEnabled(globalSetting: Bool, serverOverride: Bool?) -> Bool {
        serverOverride ?? globalSetting
    }

    static func shouldNotify(
        isEnabled: Bool,
        applicationIsActive: Bool,
        conversationIsSelected: Bool
    ) -> Bool {
        isEnabled && !(applicationIsActive && conversationIsSelected)
    }

    static func channelID(
        for destination: IRCMentionNotificationDestination,
        in channels: [Conversation],
        caseMapping: IRCCaseMapping
    ) -> UUID? {
        let normalizedName = caseMapping.normalize(destination.channelName)
        return channels.first {
            $0.serverID == destination.serverID
                && caseMapping.normalize($0.name) == normalizedName
        }?.id
    }
}

struct IRCMentionNotificationDestination: Equatable {
    let serverID: UUID
    let channelName: String
}

enum IRCDirectMessageNotificationPolicy {
    static func shouldNotify(
        isEnabled: Bool,
        applicationIsActive: Bool,
        conversationIsSelected: Bool
    ) -> Bool {
        isEnabled && !(applicationIsActive && conversationIsSelected)
    }
}

struct IRCDirectMessageNotificationDestination: Equatable {
    let serverID: UUID
    let nickname: String
}

enum IRCWhoisChannelParser {
    static func channels(
        from value: String,
        membership: IRCMembershipConfiguration = .common,
        channelTypes: Set<Character> = Set("#&+!")
    ) -> [String] {
        var seen = Set<String>()
        return value.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
            guard let channel = channelName(
                from: String(token),
                membership: membership,
                channelTypes: channelTypes
            ), seen.insert(channel).inserted else { return nil }
            return channel
        }
    }

    private static func channelName(
        from token: String,
        membership: IRCMembershipConfiguration,
        channelTypes: Set<Character>
    ) -> String? {
        var channel = token
        while channel.count > 1, let first = channel.first {
            let remainder = channel.dropFirst()
            guard membership.prefixes.contains(first),
                  remainder.first.map(channelTypes.contains) == true else { break }
            channel.removeFirst()
        }
        guard let first = channel.first, channelTypes.contains(first) else { return nil }
        return channel
    }
}

struct IRCChannelReference {
    let name: String
    let range: Range<String.Index>
}

enum IRCChannelReferenceParser {
    private static let trailingPunctuation = ".;:!?)]}>\"'”’"
    private static let disallowedLeadingNeighbors = "-_[]\\`^{|}/@#&+!"

    static func references(
        in text: String,
        channelTypes: Set<Character> = Set("#&+!")
    ) -> [IRCChannelReference] {
        var references: [IRCChannelReference] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard channelTypes.contains(text[index]),
                  hasLeadingBoundary(at: index, in: text, channelTypes: channelTypes) else {
                index = text.index(after: index)
                continue
            }

            let contentStart = text.index(after: index)
            var rawEnd = contentStart
            while rawEnd < text.endIndex, isChannelCharacter(text[rawEnd]) {
                rawEnd = text.index(after: rawEnd)
            }

            var channelEnd = rawEnd
            while channelEnd > contentStart {
                let previous = text.index(before: channelEnd)
                guard trailingPunctuation.contains(text[previous]) else { break }
                channelEnd = previous
            }

            if channelEnd > contentStart {
                let range = index..<channelEnd
                references.append(IRCChannelReference(name: String(text[range]), range: range))
            }
            index = rawEnd > index ? rawEnd : text.index(after: index)
        }
        return references
    }

    private static func hasLeadingBoundary(
        at index: String.Index,
        in text: String,
        channelTypes: Set<Character>
    ) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter
            && !previous.isNumber
            && !disallowedLeadingNeighbors.contains(previous)
            && !channelTypes.contains(previous)
    }

    private static func isChannelCharacter(_ character: Character) -> Bool {
        !character.isWhitespace
            && character != ","
            && !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
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
              !channel.isEmpty,
              !channel.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
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
    var membership: IRCMembershipConfiguration
    var username: String?
    var hostname: String?

    init(
        nickname: String,
        prefix: Character? = nil,
        modes: Set<Character>? = nil,
        membership: IRCMembershipConfiguration = .common,
        username: String? = nil,
        hostname: String? = nil
    ) {
        self.nickname = nickname
        self.membership = membership
        self.username = username
        self.hostname = hostname
        if let modes {
            self.modes = modes
        } else if let prefix, let mode = membership.mode(for: prefix) {
            self.modes = [mode]
        } else {
            self.modes = []
        }
    }

    // Equality/deduplication is performed by IRCAppState with the server's
    // advertised CASEMAPPING. This exact value is only SwiftUI row identity.
    var id: String { nickname }

    var prefix: Character? {
        membership.highestEntry(in: modes)?.prefix
    }

    var role: String? {
        membership.highestEntry(in: modes).map { membership.roleName(for: $0.mode) }
    }

    var hasOperatorPrivileges: Bool {
        membership.hasOperatorPrivileges(modes)
    }

    var hasOperatorMode: Bool {
        membership.operatorMode.map(modes.contains) ?? false
    }

    var hasVoice: Bool {
        membership.voiceMode.map(modes.contains) ?? false
    }

    var privilegeRank: Int? {
        membership.rank(of: modes)
    }
}

struct IRCMemberModerationState: Equatable {
    var supportsOperator: Bool
    var supportsVoice: Bool
    var hasOperator: Bool
    var hasVoice: Bool

    init(member: ChannelMember) {
        supportsOperator = member.membership.operatorMode != nil
        supportsVoice = member.membership.voiceMode != nil
        hasOperator = member.hasOperatorMode
        hasVoice = member.hasVoice
    }
}

enum IRCChannelModerationPolicy {
    static func canModerate(
        localNickname: String,
        targetNickname: String,
        members: [ChannelMember],
        caseMapping: IRCCaseMapping
    ) -> Bool {
        let local = caseMapping.normalize(localNickname)
        let target = caseMapping.normalize(targetNickname)
        guard local != target,
              members.contains(where: { caseMapping.normalize($0.nickname) == target }),
              let localMember = members.first(where: {
                  caseMapping.normalize($0.nickname) == local
              }) else { return false }
        return localMember.hasOperatorPrivileges
    }

    static func banMask(for nickname: String) -> String {
        "\(nickname)!*@*"
    }

    static func banMask(for member: ChannelMember) -> String {
        if let username = member.username, !username.isEmpty,
           let hostname = member.hostname, !hostname.isEmpty {
            return "*!\(username)@\(hostname)"
        }
        return banMask(for: member.nickname)
    }
}

struct IRCBanEntry: Identifiable, Hashable {
    var channel: String
    var mask: String
    var setBy: String?
    var setAt: Date?

    var id: String { mask }
}

enum IRCBanListParser {
    static func entry(from wire: IRCWireMessage) -> IRCBanEntry? {
        guard wire.command == "367", wire.parameters.count >= 3 else { return nil }
        let timestamp = wire.parameters.count > 4
            ? Double(wire.parameters[4]).map { Date(timeIntervalSince1970: $0) }
            : nil
        return IRCBanEntry(
            channel: wire.parameters[1],
            mask: wire.parameters[2],
            setBy: wire.parameters.count > 3 ? wire.parameters[3] : nil,
            setAt: timestamp
        )
    }

    static func endChannel(from wire: IRCWireMessage) -> String? {
        guard wire.command == "368", wire.parameters.count >= 2 else { return nil }
        return wire.parameters[1]
    }
}

enum IRCBanListRequestErrorPolicy {
    /// Errors that can result from asking for `MODE #channel +b` without a
    /// mask. Numeric 478 is deliberately excluded: it means a list mutation
    /// failed because the list is full, so it belongs to the pending +b change.
    static func isListRequestFailure(_ command: String) -> Bool {
        ["403", "442", "482"].contains(command)
    }
}

enum IRCBanListMutation {
    static func applying(
        _ changes: [IRCParsedChannelModeChange],
        to existingBans: [IRCBanEntry],
        channelName: String
    ) -> [IRCBanEntry] {
        var bans = existingBans
        var didChange = false
        for change in changes where change.mode == "b" {
            guard let mask = change.argument else { continue }
            if change.adding {
                guard !bans.contains(where: {
                    $0.mask.caseInsensitiveCompare(mask) == .orderedSame
                }) else { continue }
                bans.append(IRCBanEntry(channel: channelName, mask: mask))
                didChange = true
            } else if let index = bans.firstIndex(where: {
                $0.mask.caseInsensitiveCompare(mask) == .orderedSame
            }) {
                bans.remove(at: index)
                didChange = true
            }
        }
        guard didChange else { return existingBans }
        return bans.sorted {
            $0.mask.localizedCaseInsensitiveCompare($1.mask) == .orderedAscending
        }
    }
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

enum IRCJumpDestinationKind: String, Hashable {
    case server = "Server"
    case channel = "Channel"
    case directMessage = "Direct message"

    var icon: String {
        switch self {
        case .server: "network"
        case .channel: "number"
        case .directMessage: "person.crop.circle"
        }
    }
}

struct IRCJumpDestination: Identifiable, Hashable {
    let selection: SidebarItem
    let title: String
    let serverName: String
    let kind: IRCJumpDestinationKind

    var id: SidebarItem { selection }
}

/// Small, deterministic matcher shared by the jump palette and its tests.
/// Results favor exact and prefix title matches, then substring and fuzzy
/// matches across the conversation and server names.
enum IRCJumpSearch {
    static func results(
        in destinations: [IRCJumpDestination],
        matching query: String
    ) -> [IRCJumpDestination] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalized(String($0)) }

        guard !terms.isEmpty else { return destinations }

        return destinations.enumerated().compactMap { index, destination -> (Int, Int, IRCJumpDestination)? in
            let title = normalized(destination.title)
            let server = normalized(destination.serverName)
            let combined = "\(title) \(server)"
            var score = 0

            for term in terms {
                guard let termScore = matchScore(term, title: title, server: server, combined: combined) else {
                    return nil
                }
                score += termScore
            }
            return (score, index, destination)
        }
        .sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1 < $1.1
        }
        .map(\.2)
    }

    private static func matchScore(_ term: String, title: String, server: String, combined: String) -> Int? {
        if title == term { return 0 }
        if title.hasPrefix(term) { return 10 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(term) }) { return 20 }
        if title.contains(term) { return 30 }
        if server == term { return 35 }
        if server.hasPrefix(term) { return 40 }
        if combined.contains(term) { return 50 }
        if isSubsequence(term, of: title) { return 70 }
        if isSubsequence(term, of: combined) { return 80 }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIndex = needle.startIndex
        for character in haystack where needleIndex < needle.endIndex {
            if character == needle[needleIndex] {
                needle.formIndex(after: &needleIndex)
            }
        }
        return needleIndex == needle.endIndex
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum IRCWorkspaceFocus: Hashable {
    case sidebar
    case composer(SidebarItem)
}

struct IRCWorkspaceFocusRequest: Equatable {
    let id = UUID()
    let target: IRCWorkspaceFocus
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
