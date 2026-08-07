import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Netsplit

// These tests share UserDefaults.standard and include AppKit/SwiftUI integration
// checks whose run-loop work must not overlap another test in this suite.
@Suite("IRC models and state policies", .serialized)
struct IRCModelsAndPolicyTests {
    @Test("Application themes expose the expected light and dark variants")
    func exposesApplicationThemes() {
        #expect(IRCApplicationAppearance.allCases.count == 15)
        #expect(IRCApplicationAppearance.catppuccinLatte.colorScheme == .light)
        #expect(IRCApplicationAppearance.catppuccinMocha.colorScheme == .dark)
        #expect(IRCApplicationAppearance.githubLight.colorScheme == .light)
        #expect(IRCApplicationAppearance.githubDark.colorScheme == .dark)
        #expect(IRCApplicationAppearance.gruvboxDark.colorScheme == .dark)
        #expect(IRCApplicationAppearance.nord.colorScheme == .dark)
        #expect(IRCApplicationAppearance.rosePineDawn.colorScheme == .light)
        #expect(IRCApplicationAppearance.solarizedSepia.colorScheme == .light)
        #expect(IRCApplicationAppearance.solarizedSepia.rawValue == "pastelDaybreak")
        #expect(IRCApplicationAppearance.rosePine.colorScheme == .dark)
        #expect(IRCApplicationAppearance.cyberpunk.colorScheme == .dark)
        #expect(IRCApplicationAppearance.c64.colorScheme == .dark)
        #expect(IRCApplicationAppearance.greyscale.colorScheme == .dark)
        #expect(IRCApplicationAppearance.catppuccinLatte.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.catppuccinMocha.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.githubLight.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.githubDark.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.gruvboxDark.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.nord.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.rosePineDawn.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.solarizedSepia.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.rosePine.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.cyberpunk.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.c64.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.greyscale.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.system.palette == nil)
    }

    @Test("Settings list keeps built-in modes first and sorts named themes")
    func sortsApplicationThemesForSettings() {
        #expect(IRCApplicationAppearance.settingsCases.map(\.label) == [
            "System", "Light", "Dark",
            "C64", "Catppuccin Latte", "Catppuccin Mocha", "Cyberpunk",
            "GitHub Dark", "GitHub Light", "Greyscale", "Gruvbox Dark", "Nord",
            "Rose Pine", "Rose Pine Dawn", "Solarized Sepia",
        ])
    }

    @Test("Every theme provides restrained connection presentation text")
    func exposesThemeConnectionPresentations() {
        for appearance in IRCApplicationAppearance.allCases {
            let presentation = appearance.connectionPresentation
            #expect(!presentation.title.isEmpty)
            #expect(!presentation.description.isEmpty)
            #expect(!presentation.connectingLabel.isEmpty)
        }

        #expect(IRCApplicationAppearance.system.connectionPresentation.title == "Connections")
        #expect(IRCApplicationAppearance.c64.connectionPresentation.title == "READY.")
        #expect(IRCApplicationAppearance.c64.connectionPresentation.connectingLabel == "CONNECTING...")
        #expect(IRCApplicationAppearance.cyberpunk.connectionPresentation.connectingLabel == "ESTABLISHING LINK…")
    }

    @Test("Theme menu swatches preserve their original colors")
    func preservesThemeMenuSwatchColors() {
        for appearance in IRCApplicationAppearance.allCases {
            let image = appearance.previewImage
            #expect(image.size == NSSize(width: 12, height: 12))
            #expect(!image.isTemplate)
        }
    }

    @Test("Catppuccin Latte text colors meet normal-text contrast")
    func validatesCatppuccinLatteTextContrast() {
        for color in IRCThemePalette.catppuccinLatteNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.catppuccinLatteBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.catppuccinLatteSecondaryTextHex,
            background: IRCThemePalette.catppuccinLatteBarHex
        ) >= 4.5)
    }

    @Test("Solarized Sepia text colors meet normal-text contrast")
    func validatesSolarizedSepiaTextContrast() {
        for color in IRCThemePalette.solarizedSepiaNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.solarizedSepiaBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.solarizedSepiaSecondaryTextHex,
            background: IRCThemePalette.solarizedSepiaBarHex
        ) >= 4.5)
    }

    @Test("Rose Pine Dawn text colors meet normal-text contrast")
    func validatesRosePineDawnTextContrast() {
        for color in IRCThemePalette.rosePineDawnNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.rosePineDawnBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.rosePineDawnSecondaryTextHex,
            background: IRCThemePalette.rosePineDawnBarHex
        ) >= 4.5)
    }

    @Test("Rose Pine text colors meet normal-text contrast")
    func validatesRosePineTextContrast() {
        for color in IRCThemePalette.rosePineNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.rosePineBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.rosePineSecondaryTextHex,
            background: IRCThemePalette.rosePineBarHex
        ) >= 4.5)
    }

    @Test("Cyberpunk text colors meet normal-text contrast")
    func validatesCyberpunkTextContrast() {
        for color in IRCThemePalette.cyberpunkNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.cyberpunkBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.cyberpunkSecondaryTextHex,
            background: IRCThemePalette.cyberpunkBarHex
        ) >= 4.5)
    }

    @Test("Greyscale text colors meet normal-text contrast")
    func validatesGreyscaleTextContrast() {
        for color in IRCThemePalette.greyscaleNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.greyscaleBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.greyscaleSecondaryTextHex,
            background: IRCThemePalette.greyscaleBarHex
        ) >= 4.5)
    }

    @Test("Gruvbox Dark text colors meet normal-text contrast")
    func validatesGruvboxDarkTextContrast() {
        for color in IRCThemePalette.gruvboxDarkNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.gruvboxDarkBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.gruvboxDarkSecondaryTextHex,
            background: IRCThemePalette.gruvboxDarkBarHex
        ) >= 4.5)
    }

    @Test("Nord text colors meet normal-text contrast")
    func validatesNordTextContrast() {
        for color in IRCThemePalette.nordNicknameHexValues {
            #expect(Self.contrastRatio(
                foreground: color,
                background: IRCThemePalette.nordBackgroundHex
            ) >= 4.5)
        }
        #expect(Self.contrastRatio(
            foreground: IRCThemePalette.nordSecondaryTextHex,
            background: IRCThemePalette.nordBarHex
        ) >= 4.5)
    }

    private static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let foregroundLuminance = relativeLuminance(of: foreground)
        let backgroundLuminance = relativeLuminance(of: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of hex: UInt32) -> Double {
        let components = [
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        ].map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
    }

    @Test("Nickname hover details appear only when the sender column truncates")
    func detectsTruncatedNicknames() {
        #expect(!IRCNicknameTruncationPolicy.isTruncated(
            "windoxDCC",
            availableWidth: 116,
            fontSize: 15
        ))
        #expect(IRCNicknameTruncationPolicy.isTruncated(
            "[EWG]-B-MONTY",
            availableWidth: 116,
            fontSize: 15
        ))
        #expect(!IRCNicknameTruncationPolicy.isTruncated(
            "[EWG]-B-MONTY",
            availableWidth: 160,
            fontSize: 15
        ))
    }

    @Test("Global service notices route to the server transcript")
    func routesGlobalNotices() {
        let mapping = IRCCaseMapping.rfc1459

        #expect(IRCNoticeRoutingPolicy.fallbackDestination(
            sender: "Global",
            prefix: "Global!service@irc.example.org",
            caseMapping: mapping
        ) == .server)
        #expect(IRCNoticeRoutingPolicy.fallbackDestination(
            sender: "global",
            prefix: "global!service@irc.example.org",
            caseMapping: mapping
        ) == .server)
        #expect(IRCNoticeRoutingPolicy.fallbackDestination(
            sender: "Alice",
            prefix: "Alice!user@example.org",
            caseMapping: mapping
        ) == .directMessage)
        #expect(IRCNoticeRoutingPolicy.fallbackDestination(
            sender: "irc.example.org",
            prefix: "irc.example.org",
            caseMapping: mapping
        ) == .server)
    }

    @Test("Incoming channel invitations identify the inviter and channel")
    func parsesIncomingInvites() throws {
        let standard = try #require(IRCWireMessage(
            line: ":Alice!user@example.org INVITE NetsplitUser :#swift"
        ))
        let parameterOnly = try #require(IRCWireMessage(
            line: ":Bob!user@example.org INVITE NetsplitUser #macos"
        ))

        let standardInvite = try #require(IRCIncomingInvite(
            wire: standard,
            localNickname: "netsplituser",
            caseMapping: .rfc1459
        ))
        let parameterOnlyInvite = try #require(IRCIncomingInvite(
            wire: parameterOnly,
            localNickname: "NetsplitUser",
            caseMapping: .rfc1459
        ))

        #expect(standardInvite.inviter == "Alice")
        #expect(standardInvite.channel == "#swift")
        #expect(parameterOnlyInvite.inviter == "Bob")
        #expect(parameterOnlyInvite.channel == "#macos")
    }

    @Test("Incoming channel invitations reject other targets and self-invites")
    func rejectsIrrelevantInvites() throws {
        let otherTarget = try #require(IRCWireMessage(
            line: ":Alice!user@example.org INVITE SomeoneElse :#swift"
        ))
        let selfInvite = try #require(IRCWireMessage(
            line: ":NetsplitUser!user@example.org INVITE NetsplitUser :#swift"
        ))

        #expect(IRCIncomingInvite(
            wire: otherTarget,
            localNickname: "NetsplitUser",
            caseMapping: .rfc1459
        ) == nil)
        #expect(IRCIncomingInvite(
            wire: selfInvite,
            localNickname: "NetsplitUser",
            caseMapping: .rfc1459
        ) == nil)
    }

    @Test("Command-click joins channels without closing the channel browser")
    func choosesChannelBrowserJoinBehavior() {
        let ordinaryClick = IRCChannelBrowserJoinBehavior(modifierFlags: [])
        #expect(ordinaryClick == .joinAndClose)
        #expect(!ordinaryClick.keepsBrowserOpen)
        #expect(ordinaryClick.selectsConversation)

        let commandClick = IRCChannelBrowserJoinBehavior(modifierFlags: [.command, .shift])
        #expect(commandClick == .joinAndKeepBrowsing)
        #expect(commandClick.keepsBrowserOpen)
        #expect(!commandClick.selectsConversation)

        #expect(IRCChannelBrowserJoinBehavior(modifierFlags: [.option]) == .joinAndClose)
    }

    @Test("Launch auto-connect staggers only profiles sharing an SSH host")
    func staggersLaunchConnectionsBySSHHost() {
        let profiles = [
            ServerProfile(
                name: "Direct",
                hostname: "irc.direct.example",
                port: 6697,
                useTLS: true
            ),
            ServerProfile(
                name: "First shared tunnel",
                hostname: "irc.one.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: true,
                sshHostname: " bastion.example.com "
            ),
            ServerProfile(
                name: "Different tunnel",
                hostname: "irc.two.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: true,
                sshHostname: "other.example.com"
            ),
            ServerProfile(
                name: "Second shared tunnel",
                hostname: "irc.three.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: true,
                sshHostname: "BASTION.EXAMPLE.COM"
            ),
            ServerProfile(
                name: "Third shared tunnel",
                hostname: "irc.four.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: true,
                sshHostname: "bastion.example.com"
            ),
            ServerProfile(
                name: "Disabled tunnel",
                hostname: "irc.disabled.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: false,
                sshHostname: "bastion.example.com"
            ),
            ServerProfile(
                name: "Blank tunnel host",
                hostname: "irc.blank.example",
                port: 6697,
                useTLS: true,
                useSSHTunnel: true,
                sshHostname: "  "
            )
        ]

        #expect(IRCAutoConnectPolicy.launchDelays(for: profiles, stagger: 0.5) == [
            0, 0, 0, 0.5, 1, 0, 0
        ])
    }

    @Test("System wake restores only active or already-reconnecting sessions")
    func selectsConnectionsToRestoreAfterSleep() {
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .online, reconnectWasScheduled: false))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .connecting, reconnectWasScheduled: false))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .failed("offline"), reconnectWasScheduled: true))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .offline, reconnectWasScheduled: true))
        #expect(!IRCSystemSleepPolicy.shouldRestoreConnection(status: .failed("bad credentials"), reconnectWasScheduled: false))
        #expect(!IRCSystemSleepPolicy.shouldRestoreConnection(status: .offline, reconnectWasScheduled: false))
    }

    @Test("System sleep state coalesces duplicate notifications and honors manual removal")
    func coalescesSystemSleepTransitions() throws {
        let firstServerID = UUID()
        let secondServerID = UUID()
        var state = IRCSystemSleepStateMachine()

        let firstSleepResult = state.beginSleep(
            restoring: [firstServerID, secondServerID]
        )
        let firstSleep = try #require(firstSleepResult)
        #expect(firstSleep == [firstServerID, secondServerID])
        #expect(state.isSleeping)
        let duplicateSleep = state.beginSleep(restoring: [firstServerID])
        #expect(duplicateSleep == nil)

        state.remove(firstServerID)
        let firstWakeResult = state.beginWake()
        let firstWake = try #require(firstWakeResult)
        #expect(firstWake == [secondServerID])
        #expect(!state.isSleeping)
        let duplicateWake = state.beginWake()
        #expect(duplicateWake == nil)

        let secondSleep = state.beginSleep(restoring: [firstServerID])
        #expect(secondSleep == [firstServerID])
        let secondWake = state.beginWake()
        #expect(secondWake == [firstServerID])
    }

    @Test("Wake recovery probes registered transports and waits out temporary path loss")
    func choosesWakeRecoveryActions() {
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: true,
            hasReportedFailure: false,
            hasCompletedRegistration: true,
            hasReachedReadyState: true,
            isViable: true
        ) == .probeEstablishedConnection)
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: true,
            hasReportedFailure: false,
            hasCompletedRegistration: true,
            hasReachedReadyState: true,
            isViable: false
        ) == .waitForViability)
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: true,
            hasReportedFailure: false,
            hasCompletedRegistration: false,
            hasReachedReadyState: true,
            isViable: nil
        ) == .resumeRegistrationTimeout)
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: true,
            hasReportedFailure: false,
            hasCompletedRegistration: false,
            hasReachedReadyState: false,
            isViable: nil
        ) == .resumeConnectionTimeout)
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: true,
            hasReportedFailure: true,
            hasCompletedRegistration: true,
            hasReachedReadyState: true,
            isViable: true
        ) == .none)
        #expect(IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: false,
            hasReportedFailure: false,
            hasCompletedRegistration: true,
            hasReachedReadyState: true,
            isViable: true
        ) == .none)
    }

    @Test("Nickname validation accepts IRC-safe names and rejects malformed identities")
    func validatesNicknames() {
        let maximumLengthNickname = String(
            repeating: "n",
            count: IRCIdentityValidation.maximumNicknameLength
        )
        for nickname in ["Netsplit_User", "[Netsplit]", "rich-stokes", "Ålice42", maximumLengthNickname] {
            #expect(IRCIdentityValidation.nicknameError(nickname) == nil, "Nickname: \(nickname)")
        }
        for nickname in ["", " nick", "nick ", "nick name", "1nickname", "nick!user", "nick\nOPER"] {
            #expect(IRCIdentityValidation.nicknameError(nickname) != nil, "Nickname: \(nickname)")
        }
        let overlongNickname = maximumLengthNickname + "n"
        #expect(
            IRCIdentityValidation.nicknameError(overlongNickname)
                == "Nicknames can be at most \(IRCIdentityValidation.maximumNicknameLength) characters."
        )
        #expect(
            IRCIdentityValidation.nicknameLimitedToMaximumLength(overlongNickname)
                == maximumLengthNickname
        )
    }

    @Test("Case mappings implement the network-advertised RFC variants")
    func normalizesIdentifiers() {
        #expect(IRCCaseMapping.ascii.normalize("[Nick]\\^") == "[nick]\\^")
        #expect(IRCCaseMapping.strictRFC1459.normalize("[Nick]\\^") == "{nick}|^")
        #expect(IRCCaseMapping.rfc1459.normalize("[Nick]\\^") == "{nick}|~")
        #expect(IRCCaseMapping.rfc1459.normalize("ÅLICE 👋") == "Ålice 👋")
        #expect(IRCCaseMapping.rfc1459.normalize("").isEmpty)
    }

    @Test("Ignore snapshots normalize once and honor the server case mapping")
    func matchesIgnoredNicknames() {
        let rfcSnapshot = IRCIgnoreSnapshot(nicknames: ["[Nick]", "Alice"], caseMapping: .rfc1459)
        #expect(rfcSnapshot.contains("{nick}"))
        #expect(rfcSnapshot.contains("ALICE"))
        #expect(!rfcSnapshot.contains("Bob"))

        let asciiSnapshot = IRCIgnoreSnapshot(nicknames: ["[Nick]"], caseMapping: .ascii)
        #expect(!asciiSnapshot.contains("{nick}"))
    }

    @Test("Nickname mentions require IRC nickname boundaries")
    func detectsNicknameMentions() {
        let mapping = IRCCaseMapping.rfc1459

        for message in ["hello dbr", "DBR: are you there?", "ping @dbr", "(dbr)"] {
            #expect(IRCMentionPolicy.containsMention(of: "dbr", in: message, caseMapping: mapping), "Message: \(message)")
        }
        for message in ["adbr", "dbr2", "dbr_name", "not related"] {
            #expect(!IRCMentionPolicy.containsMention(of: "dbr", in: message, caseMapping: mapping), "Message: \(message)")
        }

        #expect(IRCMentionPolicy.containsMention(of: "[Nick]", in: "hello {nick}", caseMapping: mapping))
    }

    @Test("Mention notification settings allow per-server overrides")
    func resolvesMentionNotificationSettings() {
        #expect(!IRCMentionNotificationPolicy.isEnabled(globalSetting: false, serverOverride: nil))
        #expect(IRCMentionNotificationPolicy.isEnabled(globalSetting: true, serverOverride: nil))
        #expect(IRCMentionNotificationPolicy.isEnabled(globalSetting: false, serverOverride: true))
        #expect(!IRCMentionNotificationPolicy.isEnabled(globalSetting: true, serverOverride: false))

        #expect(IRCMentionNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: false,
            conversationIsSelected: true
        ))
        #expect(IRCMentionNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: true,
            conversationIsSelected: false
        ))
        #expect(!IRCMentionNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: true,
            conversationIsSelected: true
        ))
        #expect(!IRCMentionNotificationPolicy.shouldNotify(
            isEnabled: false,
            applicationIsActive: false,
            conversationIsSelected: false
        ))

        let serverID = UUID()
        let freshChannel = Conversation(name: "#Swift", serverID: serverID)
        let destination = IRCMentionNotificationDestination(serverID: serverID, channelName: "#swift")
        #expect(IRCMentionNotificationPolicy.channelID(
            for: destination,
            in: [freshChannel, Conversation(name: "#swift", serverID: UUID())],
            caseMapping: .rfc1459
        ) == freshChannel.id)
    }

    @Test("Direct message notifications follow the global setting and active conversation")
    func resolvesDirectMessageNotificationSettings() {
        #expect(IRCDirectMessageNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: false,
            conversationIsSelected: true
        ))
        #expect(IRCDirectMessageNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: true,
            conversationIsSelected: false
        ))
        #expect(!IRCDirectMessageNotificationPolicy.shouldNotify(
            isEnabled: true,
            applicationIsActive: true,
            conversationIsSelected: true
        ))
        #expect(!IRCDirectMessageNotificationPolicy.shouldNotify(
            isEnabled: false,
            applicationIsActive: false,
            conversationIsSelected: false
        ))
    }

    @Test("WHOIS channel lists preserve channels and remove membership prefixes")
    func parsesWhoisChannels() {
        let channels = IRCWhoisChannelParser.channels(
            from: "@+#operators @#voiced #general &local +modeless @+modeless not-a-channel #general"
        )
        #expect(channels == ["#operators", "#voiced", "#general", "&local", "+modeless"])
    }

    @Test("WHOIS channel lists honor advertised channel and membership prefixes")
    func parsesAdvertisedWhoisChannels() throws {
        let membership = try #require(IRCMembershipConfiguration(advertisedValue: "(Yov)!@+"))
        let channels = IRCWhoisChannelParser.channels(
            from: "!$founders @$operators $general #standard &unsupported",
            membership: membership,
            channelTypes: ["$", "#"]
        )
        #expect(channels == ["$founders", "$operators", "$general", "#standard"])
    }

    @Test("Internal channel links round-trip reserved channel characters")
    func roundTripsChannelLinks() {
        let channel = "#swift+macOS"
        let url = IRCInternalLink.channelURL(for: channel)
        #expect(url != nil)
        #expect(url.flatMap(IRCInternalLink.channelName(from:)) == channel)
        #expect(IRCInternalLink.channelName(from: URL(string: "https://example.com/#swift")!) == nil)
    }

    @Test("Member roles retain fallback privileges in server priority order")
    func prioritizesMemberRoles() {
        var member = ChannelMember(nickname: "Alice", modes: ["v", "o"])
        #expect(member.prefix == "@")
        #expect(member.role == "Operator")
        #expect(member.hasOperatorPrivileges)
        #expect(member.hasOperatorMode)
        #expect(member.hasVoice)

        member.modes.remove("o")
        #expect(member.prefix == "+")
        #expect(member.role == "Voice")
        #expect(!member.hasOperatorPrivileges)
        #expect(!member.hasOperatorMode)
        #expect(member.hasVoice)

        member.modes.formUnion(["a", "q"])
        #expect(member.prefix == "~")
        #expect(member.role == "Owner")
        #expect(member.hasOperatorPrivileges)
        #expect(!member.hasOperatorMode)
        #expect(member.hasVoice)

        member.modes.remove("v")
        #expect(!member.hasVoice)
    }

    @Test("Moderation actions follow current operator and voice modes")
    func tracksMemberModerationModes() {
        var member = ChannelMember(nickname: "Alice")
        var state = IRCMemberModerationState(member: member)
        #expect(state.supportsOperator)
        #expect(state.supportsVoice)
        #expect(!state.hasOperator)
        #expect(!state.hasVoice)

        member.modes.formUnion(["o", "v"])
        state = IRCMemberModerationState(member: member)
        #expect(state.hasOperator)
        #expect(state.hasVoice)

        member.modes.remove("o")
        state = IRCMemberModerationState(member: member)
        #expect(!state.hasOperator)
        #expect(state.hasVoice)

        member.modes.remove("v")
        state = IRCMemberModerationState(member: member)
        #expect(!state.hasVoice)
    }

    @Test("Only channel operators can moderate other current members")
    func gatesChannelModeration() {
        let members = [
            ChannelMember(nickname: "[Local]", modes: ["o"]),
            ChannelMember(nickname: "Alice"),
            ChannelMember(nickname: "Voiced", modes: ["v"])
        ]

        #expect(IRCChannelModerationPolicy.canModerate(
            localNickname: "{local}",
            targetNickname: "Alice",
            members: members,
            caseMapping: .rfc1459
        ))
        #expect(!IRCChannelModerationPolicy.canModerate(
            localNickname: "[Local]",
            targetNickname: "{local}",
            members: members,
            caseMapping: .rfc1459
        ))
        #expect(!IRCChannelModerationPolicy.canModerate(
            localNickname: "Voiced",
            targetNickname: "Alice",
            members: members,
            caseMapping: .rfc1459
        ))
        #expect(!IRCChannelModerationPolicy.canModerate(
            localNickname: "[Local]",
            targetNickname: "Departed",
            members: members,
            caseMapping: .rfc1459
        ))
        #expect(IRCChannelModerationPolicy.banMask(for: "Alice") == "Alice!*@*")

        let identified = ChannelMember(
            nickname: "Alice",
            username: "~alice",
            hostname: "cloak.example"
        )
        #expect(IRCChannelModerationPolicy.banMask(for: identified) == "*!~alice@cloak.example")
    }

    @Test("Custom ban commands use an explicit channel or fall back to the current channel")
    func parsesCustomBanCommands() {
        #expect(IRCBanCommand.parse(
            "*!*@*.example.com",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCBanCommand(mask: "*!*@*.example.com", channel: "#swift", reason: nil))
        #expect(IRCBanCommand.parse(
            "*@*.att.com &help repeated abuse",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCBanCommand(mask: "*@*.att.com", channel: "&help", reason: "repeated abuse"))
        #expect(IRCBanCommand.parse(
            "BadNick!*@* repeated abuse",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCBanCommand(mask: "BadNick!*@*", channel: "#swift", reason: "repeated abuse"))
        #expect(IRCBanCommand.parse(
            "*!*@*.example.com",
            defaultChannel: nil,
            channelTypes: ["#", "&"]
        ) == nil)
        #expect(IRCBanCommand.parse(
            "*!*@*.example.com #swift",
            defaultChannel: nil,
            channelTypes: ["#", "&"]
        ) == IRCBanCommand(mask: "*!*@*.example.com", channel: "#swift", reason: nil))
    }

    @Test("Kick commands use an explicit channel or fall back to the current channel")
    func parsesKickCommands() {
        #expect(IRCKickCommand.parse(
            "Alice",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCKickCommand(channel: "#swift", nickname: "Alice", reason: nil))
        #expect(IRCKickCommand.parse(
            "Alice repeated abuse",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCKickCommand(channel: "#swift", nickname: "Alice", reason: "repeated abuse"))
        #expect(IRCKickCommand.parse(
            "&help Alice repeated abuse",
            defaultChannel: "#swift",
            channelTypes: ["#", "&"]
        ) == IRCKickCommand(channel: "&help", nickname: "Alice", reason: "repeated abuse"))
        #expect(IRCKickCommand.parse(
            "Alice",
            defaultChannel: nil,
            channelTypes: ["#", "&"]
        ) == nil)
        #expect(IRCKickCommand.parse(
            "#swift",
            defaultChannel: "#help",
            channelTypes: ["#", "&"]
        ) == nil)
    }

    @Test("Custom ban masks match complete member identities with IRC wildcards")
    func matchesCustomBanMasks() {
        let alice = ChannelMember(
            nickname: "[Alice]",
            username: "~alice",
            hostname: "user-1.att.com"
        )
        let bob = ChannelMember(
            nickname: "Bob",
            username: "bob",
            hostname: "example.net"
        )
        let unidentified = ChannelMember(nickname: "Guest")

        #expect(IRCChannelModerationPolicy.mask("*@*.att.com", matches: alice, caseMapping: .rfc1459))
        #expect(IRCChannelModerationPolicy.mask(
            "{alice}!?alice@user-?.att.com",
            matches: alice,
            caseMapping: .rfc1459
        ))
        #expect(!IRCChannelModerationPolicy.mask("*@*.att.com", matches: bob, caseMapping: .rfc1459))
        #expect(IRCChannelModerationPolicy.mask("Guest!*@*", matches: unidentified, caseMapping: .rfc1459))
    }

    @Test("Ban confirmations tolerate a normalized echo only when one request is in flight")
    func correlatesConfirmedBanMasks() {
        #expect(IRCBanConfirmationPolicy.pendingMaskIndex(
            in: ["*!*@*.example.com", "*!*@elsewhere.example"],
            confirmedMask: "*!*@*.EXAMPLE.COM",
            caseMapping: .rfc1459
        ) == 0)
        #expect(IRCBanConfirmationPolicy.pendingMaskIndex(
            in: ["*@*.att.com"],
            confirmedMask: "*!*@*.att.com",
            caseMapping: .rfc1459
        ) == 0)
        #expect(IRCBanConfirmationPolicy.pendingMaskIndex(
            in: ["*@*.att.com", "*@*.example.net"],
            confirmedMask: "*!*@*.att.com",
            caseMapping: .rfc1459
        ) == nil)
    }

    @Test("Parses single and multi-prefix NAMES entries without corrupting nicknames")
    func parsesNamesMembers() {
        let plain = IRCMemberParser.member(from: "Alice")
        let operatorMember = IRCMemberParser.member(from: "@Bob")
        let multiPrefix = IRCMemberParser.member(from: "@+Carol")

        #expect(plain.nickname == "Alice")
        #expect(plain.modes.isEmpty)
        #expect(operatorMember.nickname == "Bob")
        #expect(operatorMember.modes == ["o"])
        #expect(multiPrefix.nickname == "Carol")
        #expect(multiPrefix.modes == ["o", "v"])
        #expect(multiPrefix.prefix == "@")
    }

    @Test("NAMES parsing honors PREFIX and userhost-in-names")
    func parsesAdvertisedNamesMembers() throws {
        let membership = try #require(IRCMembershipConfiguration(advertisedValue: "(Yov)!@+"))
        let member = IRCMemberParser.member(
            from: "!@Alice!~alice@cloak.example",
            membership: membership
        )

        #expect(member.nickname == "Alice")
        #expect(member.modes == ["Y", "o"])
        #expect(member.prefix == "!")
        #expect(member.role == "Mode +Y")
        #expect(member.hasOperatorPrivileges)
        #expect(member.username == "~alice")
        #expect(member.hostname == "cloak.example")
    }

    @Test("Mixed channel modes consume arguments without shifting nicknames")
    func parsesMembershipModes() {
        let mixed = IRCChannelModeParser.membershipChanges(
            modeString: "+klo-v",
            arguments: ["secret", "50", "Alice", "Bob"]
        )
        #expect(mixed == [
            IRCMembershipModeChange(nickname: "Alice", mode: "o", adding: true),
            IRCMembershipModeChange(nickname: "Bob", mode: "v", adding: false)
        ])

        let multiple = IRCChannelModeParser.membershipChanges(
            modeString: "+ov-h",
            arguments: ["Alice", "Bob", "Carol"]
        )
        #expect(multiple.map(\.nickname) == ["Alice", "Bob", "Carol"])
        #expect(multiple.map(\.adding) == [true, true, false])

        let removalWithoutArgument = IRCChannelModeParser.membershipChanges(
            modeString: "-l+o",
            arguments: ["Dana"]
        )
        #expect(removalWithoutArgument == [
            IRCMembershipModeChange(nickname: "Dana", mode: "o", adding: true)
        ])

        let legacyFallback = IRCChannelModeParser.membershipChanges(
            modeString: "+eIofjL-v",
            arguments: [
                "*!*@excepted", "*!*@invited", "Alice",
                "#forward", "3:10", "#redirect", "Bob"
            ]
        )
        #expect(legacyFallback == [
            IRCMembershipModeChange(nickname: "Alice", mode: "o", adding: true),
            IRCMembershipModeChange(nickname: "Bob", mode: "v", adding: false)
        ])
    }

    @Test("Channel mode parsing uses advertised PREFIX and CHANMODES argument rules")
    func parsesAdvertisedChannelModes() throws {
        let membership = try #require(IRCMembershipConfiguration(advertisedValue: "(Yov)!@+"))
        let channelModes = try #require(IRCChannelModeCapabilities(
            advertisedValue: "beI,kf,l,imnst"
        ))
        let changes = IRCChannelModeParser.changes(
            modeString: "+fYo-l",
            arguments: ["forward-target", "Founder", "Operator"],
            membership: membership,
            channelModes: channelModes
        )

        #expect(changes == [
            IRCParsedChannelModeChange(mode: "f", adding: true, argument: "forward-target"),
            IRCParsedChannelModeChange(mode: "Y", adding: true, argument: "Founder"),
            IRCParsedChannelModeChange(mode: "o", adding: true, argument: "Operator"),
            IRCParsedChannelModeChange(mode: "l", adding: false, argument: nil)
        ])
        #expect(IRCChannelModeParser.membershipChanges(
            modeString: "+fYo-l",
            arguments: ["forward-target", "Founder", "Operator"],
            membership: membership,
            channelModes: channelModes
        ) == [
            IRCMembershipModeChange(nickname: "Founder", mode: "Y", adding: true),
            IRCMembershipModeChange(nickname: "Operator", mode: "o", adding: true)
        ])
    }

    @Test("ISUPPORT updates and resets server-advertised protocol features")
    func parsesServerFeatures() throws {
        var features = IRCServerFeatures.defaults
        features.apply(parameters: [
            "CASEMAPPING=ascii",
            "PREFIX=(Yov)!@+",
            "CHANMODES=beI,kf,l,imnst",
            "CHANTYPES=#$",
            "STATUSMSG=!@",
            "NETWORK=ExampleNet",
            "NICKLEN=24",
            "CHANNELLEN=50",
            "MODES=6",
            "LINELEN=2048"
        ][...])

        #expect(features.caseMapping == .ascii)
        #expect(features.membership.entries.map(\.mode) == ["Y", "o", "v"])
        #expect(features.membership.entries.map(\.prefix) == ["!", "@", "+"])
        #expect(features.channelModes.listModes == Set("beI"))
        #expect(features.channelTypes == ["#", "$"])
        #expect(features.statusMessagePrefixes == ["!", "@"])
        #expect(features.channelName(fromMessageTarget: "!$staff") == "$staff")
        #expect(features.channelName(fromMessageTarget: "@#general") == "#general")
        #expect(features.channelName(fromMessageTarget: "&local") == nil)
        #expect(features.networkName == "ExampleNet")
        #expect(features.maximumNicknameLength == 24)
        #expect(features.maximumChannelLength == 50)
        #expect(features.maximumModesPerCommand == 6)
        #expect(features.maximumLineLength == 2048)

        features.apply(parameters: [
            "-CASEMAPPING", "-PREFIX", "-CHANMODES", "-CHANTYPES",
            "-STATUSMSG", "-NETWORK", "-NICKLEN", "-CHANNELLEN", "-MODES", "-LINELEN"
        ][...])
        #expect(features == .defaults)
    }

    @Test("Ban-list numerics preserve the exact mask and optional metadata")
    func parsesBanListNumerics() throws {
        let reply = try #require(IRCWireMessage(
            line: ":irc.example 367 NetsplitUser #swift *!~alice@cloak.example Oper 1720000000"
        ))
        let end = try #require(IRCWireMessage(
            line: ":irc.example 368 NetsplitUser #swift :End of channel ban list"
        ))
        let entry = try #require(IRCBanListParser.entry(from: reply))

        #expect(entry.channel == "#swift")
        #expect(entry.mask == "*!~alice@cloak.example")
        #expect(entry.setBy == "Oper")
        #expect(entry.setAt == Date(timeIntervalSince1970: 1_720_000_000))
        #expect(IRCBanListParser.endChannel(from: end) == "#swift")
        #expect(IRCBanListRequestErrorPolicy.isListRequestFailure("482"))
        #expect(!IRCBanListRequestErrorPolicy.isListRequestFailure("478"))

        let added = IRCBanListMutation.applying(
            [IRCParsedChannelModeChange(
                mode: "b",
                adding: true,
                argument: "*!*@new.example"
            )],
            to: [entry],
            channelName: "#swift"
        )
        #expect(added.map(\.mask) == ["*!*@new.example", "*!~alice@cloak.example"])

        let removed = IRCBanListMutation.applying(
            [IRCParsedChannelModeChange(
                mode: "b",
                adding: false,
                argument: "*!*@NEW.EXAMPLE"
            )],
            to: added,
            channelName: "#swift"
        )
        #expect(removed == [entry])
    }

    @Test("Normalizes capability modifiers and advertised values")
    func parsesCapabilityNames() {
        #expect(IRCCapability.advertisement(from: "sts=port=6697,duration=3600") == .init(
            name: "sts",
            value: "port=6697,duration=3600"
        ))
        #expect(IRCCapability.name(from: "sasl=PLAIN,EXTERNAL") == "sasl")
        #expect(IRCCapability.saslMechanisms(from: "sasl=PLAIN,EXTERNAL") == ["PLAIN", "EXTERNAL"])
        #expect(IRCCapability.saslMechanisms(from: "sasl") == nil)
        #expect(IRCSASL.canUsePlain(advertisedMechanisms: ["PLAIN", "EXTERNAL"]))
        #expect(!IRCSASL.canUsePlain(advertisedMechanisms: ["EXTERNAL"]))
        #expect(IRCSASL.canUsePlain(advertisedMechanisms: nil))
        #expect(IRCCapability.name(from: "-echo-message") == "echo-message")
        #expect(IRCCapability.name(from: "server-time") == "server-time")
        #expect(IRCCapability.preferred == [
            "message-tags",
            "server-time",
            "multi-prefix",
            "userhost-in-names",
            "chghost",
            "echo-message",
            "batch",
            "labeled-response",
            "standard-replies"
        ])
        #expect(!IRCCapability.requestablePreferred(
            advertised: ["labeled-response"],
            enabled: []
        ).contains("labeled-response"))
        #expect(IRCCapability.requestablePreferred(
            advertised: ["server-time"],
            enabled: []
        ).contains("server-time"))
        #expect(IRCCapability.requestablePreferred(
            advertised: ["batch", "labeled-response"],
            enabled: []
        ).contains("labeled-response"))
        #expect(IRCCapability.enabledCapabilities(
            afterRemoving: ["message-tags"],
            from: ["message-tags", "server-time", "batch", "labeled-response"]
        ) == ["server-time", "batch", "labeled-response"])
        #expect(IRCCapability.enabledCapabilities(
            afterRemoving: ["batch"],
            from: ["message-tags", "server-time", "batch", "labeled-response"]
        ) == ["message-tags", "server-time"])
    }

    @Test("Parses and presents IRCv3 standard replies")
    func parsesStandardReplies() throws {
        let failureWire = try #require(IRCWireMessage(
            line: ":irc.example.org FAIL PRIVMSG CANNOTSENDTOCHAN #swift :Cannot send to channel"
        ))
        let warningWire = try #require(IRCWireMessage(
            line: ":irc.example.org WARN MODE DEPRECATED #swift :Use the new mode syntax"
        ))
        let oneWordWire = try #require(IRCWireMessage(
            line: ":irc.example.org NOTE * MAINTENANCE Soon"
        ))
        let failure = try #require(IRCStandardReply(wire: failureWire))
        let warning = try #require(IRCStandardReply(wire: warningWire))
        let oneWord = try #require(IRCStandardReply(wire: oneWordWire))

        #expect(failure.kind == .failure)
        #expect(failure.command == "PRIVMSG")
        #expect(failure.code == "CANNOTSENDTOCHAN")
        #expect(failure.context == ["#swift"])
        #expect(failure.displayText == "PRIVMSG CANNOTSENDTOCHAN: Cannot send to channel")
        #expect(warning.displayText == "Warning — MODE DEPRECATED: Use the new mode syntax")
        #expect(oneWord.description == "Soon")
        #expect(oneWord.context.isEmpty)
        #expect(IRCNumericReply.isError("401"))
        #expect(IRCNumericReply.isError("599"))
        #expect(!IRCNumericReply.isError("399"))
        #expect(!IRCNumericReply.isError("FAIL"))
    }

    @Test("Authoritative echoes preserve row identity and attach server metadata")
    func reconcilesAuthoritativeEchoes() throws {
        var optimistic = IRCMessage(sender: "tester", text: "hello \u{02}there\u{0F}")
        optimistic.timestamp = Date(timeIntervalSince1970: 100)
        let serverTimestamp = Date(timeIntervalSince1970: 200)

        let reconciled = IRCMessageEchoReconciliationPolicy.authoritativeMessage(
            from: optimistic,
            echoedWireText: "hello there",
            tags: [
                "time": "1970-01-01T00:03:20.000Z",
                "msgid": "server-message-1",
                "account": "tester-account",
                "+reply": "parent-message"
            ],
            timestamp: serverTimestamp,
            presentation: .message
        )

        #expect(reconciled.id == optimistic.id)
        #expect(reconciled.text == "hello there")
        #expect(reconciled.timestamp == serverTimestamp)
        #expect(reconciled.serverMessageID == "server-message-1")
        #expect(reconciled.accountName == "tester-account")
        #expect(reconciled.replyToMessageID == "parent-message")
        #expect(reconciled.ircv3Tags.map(\.name) == ["+reply", "account", "msgid", "time"])

        let action = IRCMessageEchoReconciliationPolicy.authoritativeMessage(
            from: IRCMessage(sender: "* tester", text: "waves", nicknameColorKey: "tester"),
            echoedWireText: "\u{01}ACTION waves enthusiastically\u{01}",
            tags: ["msgid": "action-1"],
            timestamp: nil,
            presentation: .action
        )
        #expect(action.text == "waves enthusiastically")
        #expect(action.serverMessageID == "action-1")

        let notice = IRCMessageEchoReconciliationPolicy.authoritativeMessage(
            from: IRCMessage(
                sender: "System",
                text: "Notice sent to Alice: original",
                isSystem: true,
                isNotice: true
            ),
            echoedWireText: "filtered",
            tags: ["msgid": "notice-1"],
            timestamp: nil,
            presentation: .notice(target: "Alice")
        )
        #expect(notice.text == "Notice sent to Alice: filtered")
        #expect(notice.serverMessageID == "notice-1")
    }

    @Test("Outgoing echo state handles either callback ordering and echo-confirmed writes")
    func transitionsOutgoingEchoState() throws {
        let optimistic = IRCMessage(sender: "tester", text: "original")

        var writeFirst = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        let localAppend = writeFirst.completeWrite(succeeded: true)
        #expect(localAppend.transcriptMutation == .append(optimistic))
        #expect(!localAppend.isComplete)
        let replacementResult = writeFirst.receiveEcho(
            wireText: "filtered",
            tags: ["msgid": "message-1"],
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let replacement = try #require(replacementResult)
        guard case .replace(let replacedMessage) = replacement.transcriptMutation else {
            Issue.record("Expected the authoritative echo to replace the optimistic row")
            return
        }
        #expect(replacement.isComplete)
        #expect(replacedMessage.id == optimistic.id)
        #expect(replacedMessage.text == "filtered")
        #expect(replacedMessage.serverMessageID == "message-1")

        var echoFirst = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        let heldEchoResult = echoFirst.receiveEcho(
            wireText: "filtered",
            tags: ["msgid": "message-2"],
            timestamp: nil
        )
        let heldEcho = try #require(heldEchoResult)
        #expect(heldEcho.transcriptMutation == .none)
        #expect(!heldEcho.isComplete)
        let echoConfirmedFailure = echoFirst.completeWrite(succeeded: false)
        guard case .append(let confirmedMessage) = echoConfirmedFailure.transcriptMutation else {
            Issue.record("A server echo must win over a later local write failure")
            return
        }
        #expect(echoConfirmedFailure.isComplete)
        #expect(confirmedMessage.text == "filtered")
        #expect(confirmedMessage.serverMessageID == "message-2")

        var acknowledgedFirst = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        let acknowledgementResult = acknowledgedFirst.receiveAcknowledgement()
        let acknowledgement = try #require(acknowledgementResult)
        #expect(acknowledgement.transcriptMutation == .none)
        #expect(!acknowledgement.isComplete)
        let acknowledgementConfirmedFailure = acknowledgedFirst.completeWrite(succeeded: false)
        #expect(acknowledgementConfirmedFailure.transcriptMutation == .append(optimistic))
        #expect(acknowledgementConfirmedFailure.isComplete)

        var rejectedAfterWrite = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        _ = rejectedAfterWrite.completeWrite(succeeded: true)
        let optionalRemoveResult = rejectedAfterWrite.receiveRejection()
        let removeResult = try #require(optionalRemoveResult)
        #expect(removeResult.transcriptMutation == .remove(optimistic.id))
        #expect(removeResult.isComplete)

        var rejectedBeforeWrite = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        let optionalHeldRejection = rejectedBeforeWrite.receiveRejection()
        let heldRejection = try #require(optionalHeldRejection)
        #expect(heldRejection.transcriptMutation == .none)
        #expect(!heldRejection.isComplete)
        let rejectedWrite = rejectedBeforeWrite.completeWrite(succeeded: true)
        #expect(rejectedWrite.transcriptMutation == .none)
        #expect(rejectedWrite.isComplete)
    }

    @Test("Outgoing echo retention never races an outstanding write callback")
    func retainsOutgoingEchoesAwaitingWriteCompletion() {
        let sentAt = Date(timeIntervalSince1970: 100)
        let expiredAt = sentAt.addingTimeInterval(
            IRCOutgoingEchoRetentionPolicy.maximumAge + 1
        )
        let optimistic = IRCMessage(sender: "tester", text: "hello")

        var locallyDisplayed = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        _ = locallyDisplayed.completeWrite(succeeded: true)
        #expect(IRCOutgoingEchoRetentionPolicy.shouldExpire(
            locallyDisplayed,
            sentAt: sentAt,
            now: expiredAt
        ))

        var echoBeforeWrite = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        _ = echoBeforeWrite.receiveEcho(
            wireText: "filtered",
            tags: ["msgid": "server-message"],
            timestamp: nil
        )
        #expect(!IRCOutgoingEchoRetentionPolicy.shouldExpire(
            echoBeforeWrite,
            sentAt: sentAt,
            now: expiredAt
        ))

        var acknowledgementBeforeWrite = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        _ = acknowledgementBeforeWrite.receiveAcknowledgement()
        #expect(!IRCOutgoingEchoRetentionPolicy.shouldExpire(
            acknowledgementBeforeWrite,
            sentAt: sentAt,
            now: expiredAt
        ))

        var rejectionBeforeWrite = IRCOutgoingEchoState(
            message: optimistic,
            presentation: .message
        )
        _ = rejectionBeforeWrite.receiveRejection()
        #expect(!IRCOutgoingEchoRetentionPolicy.shouldExpire(
            rejectionBeforeWrite,
            sentAt: sentAt,
            now: expiredAt
        ))
    }

    @Test("Outgoing echo correlation uses labels and skips entries already echoed")
    func correlatesLabeledAndIdenticalEchoes() {
        let candidates = [
            IRCOutgoingEchoCandidate(
                target: "#Swift",
                wireText: "same",
                label: nil,
                hasReceivedServerConfirmation: true
            ),
            IRCOutgoingEchoCandidate(
                target: "#swift",
                wireText: "same",
                label: nil,
                hasReceivedServerConfirmation: false
            ),
            IRCOutgoingEchoCandidate(
                target: "#swift",
                wireText: "original",
                label: "request-3",
                hasReceivedServerConfirmation: false
            )
        ]

        #expect(IRCOutgoingEchoCorrelationPolicy.matchingIndex(
            in: candidates,
            target: "#SWIFT",
            wireText: "same",
            label: nil,
            maximumEchoBytes: nil,
            caseMapping: .rfc1459
        ) == 1)
        #expect(IRCOutgoingEchoCorrelationPolicy.matchingIndex(
            in: candidates,
            target: "#swift",
            wireText: "server-modified",
            label: "request-3",
            maximumEchoBytes: nil,
            caseMapping: .rfc1459
        ) == 2)
        #expect(IRCOutgoingEchoCorrelationPolicy.matchingIndex(
            in: candidates,
            target: "#swift",
            wireText: "original",
            label: nil,
            maximumEchoBytes: nil,
            caseMapping: .rfc1459
        ) == nil)
    }

    @Test("Self-targeted duplicate correlation is exact, case-aware, and expires")
    func correlatesSelfTargetedDuplicatesWithoutMessageIDs() {
        let now = Date(timeIntervalSince1970: 100)
        let recent = [
            IRCRecentSelfTargetedConfirmation(
                target: "Tester",
                wireText: "same",
                recordedAt: Date(timeIntervalSince1970: 90)
            ),
            IRCRecentSelfTargetedConfirmation(
                target: "tester",
                wireText: "expired",
                recordedAt: Date(timeIntervalSince1970: 50)
            )
        ]

        #expect(IRCSelfTargetedEchoDuplicatePolicy.matchingIndex(
            in: recent,
            target: "TESTER",
            wireText: "same",
            now: now,
            maximumAge: 30,
            caseMapping: .rfc1459
        ) == 0)
        #expect(IRCSelfTargetedEchoDuplicatePolicy.matchingIndex(
            in: recent,
            target: "tester",
            wireText: "different",
            now: now,
            maximumAge: 30,
            caseMapping: .rfc1459
        ) == nil)

        let pending = [
            IRCOutgoingEchoCandidate(
                target: "Tester",
                wireText: "original",
                label: "request-1",
                hasReceivedServerConfirmation: false,
                presentation: .message
            ),
            IRCOutgoingEchoCandidate(
                target: "Tester",
                wireText: "same",
                label: "request-2",
                hasReceivedServerConfirmation: true,
                presentation: .message
            ),
            IRCOutgoingEchoCandidate(
                target: "Tester",
                wireText: "\u{01}ACTION waves\u{01}",
                label: "request-3",
                hasReceivedServerConfirmation: false,
                presentation: .action
            )
        ]
        #expect(IRCSelfTargetedEchoDuplicatePolicy.matchingPendingIndex(
            in: pending,
            target: "tester",
            wireText: "filtered",
            presentation: .message,
            caseMapping: .rfc1459
        ) == 0)
        #expect(IRCSelfTargetedEchoDuplicatePolicy.matchingPendingIndex(
            in: pending,
            target: "tester",
            wireText: "waves",
            presentation: .action,
            caseMapping: .rfc1459
        ) == 2)
        #expect(IRCSelfTargetedEchoDuplicatePolicy.matchingIndex(
            in: recent,
            target: "tester",
            wireText: "expired",
            now: now,
            maximumAge: 30,
            caseMapping: .rfc1459
        ) == nil)
    }

    @Test("Incoming messages retain IRCv3 IDs, account names, and reply references")
    @MainActor
    func retainsIncomingMessageMetadata() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.handle(
            try #require(IRCWireMessage(
                line: "@time=2026-07-17T20:00:00.125Z;msgid=message-2;account=alice;+reply=message-1 :Alice!user@example.org PRIVMSG tester :hello"
            )),
            profile: profile
        )

        let conversation = try #require(state.directMessages.first {
            $0.serverID == profile.id && $0.name == "Alice"
        })
        let message = try #require(state.messages(
            for: .directMessage(conversation.id),
            channelEventVisibility: .alwaysShow
        ).last)
        #expect(message.serverMessageID == "message-2")
        #expect(message.accountName == "alice")
        #expect(message.replyToMessageID == "message-1")
        #expect(message.timestamp == IRCServerTimeParser.date(from: "2026-07-17T20:00:00.125Z"))
    }

    @Test("Self-sent bouncer notices remain visible with server metadata")
    @MainActor
    func retainsUnmatchedSelfNotices() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.handle(
            try #require(IRCWireMessage(
                line: "@msgid=notice-2 :\(state.nickname)!user@example.org NOTICE Alice :hello"
            )),
            profile: profile
        )

        let conversation = try #require(state.directMessages.first {
            $0.serverID == profile.id && $0.name == "Alice"
        })
        let message = try #require(state.messages(
            for: .directMessage(conversation.id),
            channelEventVisibility: .alwaysShow
        ).last)
        #expect(message.isNotice)
        #expect(message.text == "hello")
        #expect(message.serverMessageID == "notice-2")
    }

    @Test("Self-targeted labeled notices suppress the duplicate unlabeled delivery")
    @MainActor
    func deduplicatesSelfTargetedLabeledNotices() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        let nickname = state.nickname

        state.handle(
            try #require(IRCWireMessage(
                line: "@label=request-1;msgid=notice-self-1 :\(nickname)!user@example.org NOTICE \(nickname) :hello"
            )),
            profile: profile
        )

        let conversation = try #require(state.directMessages.first {
            $0.serverID == profile.id && $0.name == nickname
        })
        let destination = SidebarItem.directMessage(conversation.id)
        let countAfterLabeledDelivery = state.messages(
            for: destination,
            channelEventVisibility: .alwaysShow
        ).count

        state.handle(
            try #require(IRCWireMessage(
                line: "@msgid=notice-self-1 :\(nickname)!user@example.org NOTICE \(nickname) :hello"
            )),
            profile: profile
        )

        let messages = state.messages(
            for: destination,
            channelEventVisibility: .alwaysShow
        )
        #expect(messages.count == countAfterLabeledDelivery)
        #expect(messages.filter { $0.serverMessageID == "notice-self-1" }.count == 1)

        let reverseOrderState = IRCAppState()
        let reverseOrderProfile = try #require(reverseOrderState.profiles.first)
        let reverseOrderNickname = reverseOrderState.nickname
        reverseOrderState.handle(
            try #require(IRCWireMessage(
                line: "@msgid=notice-self-2 :\(reverseOrderNickname)!user@example.org NOTICE \(reverseOrderNickname) :hello"
            )),
            profile: reverseOrderProfile
        )
        reverseOrderState.handle(
            try #require(IRCWireMessage(
                line: "@label=request-2;msgid=notice-self-2 :\(reverseOrderNickname)!user@example.org NOTICE \(reverseOrderNickname) :hello"
            )),
            profile: reverseOrderProfile
        )
        let reverseOrderConversation = try #require(reverseOrderState.directMessages.first {
            $0.serverID == reverseOrderProfile.id && $0.name == reverseOrderNickname
        })
        let reverseOrderMessages = reverseOrderState.messages(
            for: .directMessage(reverseOrderConversation.id),
            channelEventVisibility: .alwaysShow
        )
        #expect(reverseOrderMessages.filter { $0.serverMessageID == "notice-self-2" }.count == 1)
    }

    @Test("Standard replies remain visible in the server transcript")
    @MainActor
    func displaysStandardReplies() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.handle(
            try #require(IRCWireMessage(
                line: "@label=request-1 :irc.example.org FAIL PRIVMSG CANNOTSENDTOCHAN #missing :Cannot send to channel"
            )),
            profile: profile
        )

        let reply = try #require(state.messages(
            for: .server(profile.id),
            channelEventVisibility: .alwaysShow
        ).last)
        #expect(reply.isSystem)
        #expect(reply.text == "PRIVMSG CANNOTSENDTOCHAN: Cannot send to channel")
        #expect(reply.tagValue(named: "label") == "request-1")
    }

    @Test("Labeled-response batches propagate their label to contained replies")
    @MainActor
    func inheritsLabelsFromBatches() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.handle(
            try #require(IRCWireMessage(
                line: "@label=request-2 :irc.example.org BATCH +batch-1 labeled-response"
            )),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(
                line: "@batch=batch-1 :irc.example.org NOTE * MAINTENANCE :Brief maintenance soon"
            )),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(
                line: ":irc.example.org BATCH -batch-1"
            )),
            profile: profile
        )

        let reply = try #require(state.messages(
            for: .server(profile.id),
            channelEventVisibility: .alwaysShow
        ).last)
        #expect(reply.tagValue(named: "label") == "request-2")
        #expect(reply.tagValue(named: "batch") == "batch-1")
    }

    @Test("Nested batches preserve explicit labels and reject invalid boundaries")
    @MainActor
    func validatesNestedBatchBoundaries() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        let lines = [
            "@label=outer-request :irc.example.org BATCH +outer labeled-response",
            "@batch=outer;label=inner-request :irc.example.org BATCH +inner labeled-response",
            // A duplicate start must not overwrite the original inner label.
            "@batch=outer;label=wrong-request :irc.example.org BATCH +inner labeled-response",
            // The inner batch can only end through the parent it started in.
            "@batch=unknown :irc.example.org BATCH -inner",
            // A parent cannot end while one of its nested batches is open.
            ":irc.example.org BATCH -outer",
            "@batch=inner :irc.example.org NOTE * MAINTENANCE :Nested response",
            "@batch=outer :irc.example.org BATCH -inner",
            "@batch=outer :irc.example.org NOTE * MAINTENANCE :Outer response",
            ":irc.example.org BATCH -outer"
        ]
        for line in lines {
            state.handle(
                try #require(IRCWireMessage(line: line)),
                profile: profile
            )
        }

        let replies = state.messages(
            for: .server(profile.id),
            channelEventVisibility: .alwaysShow
        ).suffix(2)
        let innerReply = try #require(replies.first)
        let outerReply = try #require(replies.last)
        #expect(innerReply.tagValue(named: "label") == "inner-request")
        #expect(innerReply.tagValue(named: "batch") == "inner")
        #expect(outerReply.tagValue(named: "label") == "outer-request")
        #expect(outerReply.tagValue(named: "batch") == "outer")
    }

    @Test("Parses IRCv3 server-time tags with or without fractional seconds")
    func parsesServerTimeTags() {
        let fractional = IRCServerTimeParser.date(from: "2026-07-17T20:00:00.125Z")
        let wholeSeconds = IRCServerTimeParser.date(from: "2026-07-17T20:00:00Z")

        #expect(fractional != nil)
        #expect(wholeSeconds != nil)
        #expect(fractional?.timeIntervalSince(wholeSeconds!) == 0.125)
        #expect(IRCServerTimeParser.date(from: "not-a-date") == nil)
    }

    @Test("Reconnect backoff is exponential and capped")
    func computesReconnectDelay() {
        let delays = (0...8).map {
            IRCReconnectPolicy.delay(attempt: $0, initialDelay: 2, maximumDelay: 60)
        }
        #expect(delays == [0, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    @Test("Reconnect jitter staggers retries without exceeding the backoff")
    func jittersReconnectDelay() {
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 60, randomUnit: 0) == 45)
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 60, randomUnit: 0.5) == 52.5)
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 60, randomUnit: 1) == 60)
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 60, randomUnit: -1) == 45)
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 60, randomUnit: 2) == 60)
        #expect(IRCReconnectPolicy.jitteredDelay(baseDelay: 0, randomUnit: 0.5) == 0)
    }

    @Test("Sleep resumes the pending reconnect attempt without resetting backoff")
    func preservesReconnectAttemptAcrossSleep() {
        #expect(IRCReconnectPolicy.attempt(after: 0, reusingCurrent: false) == 1)
        #expect(IRCReconnectPolicy.attempt(after: 4, reusingCurrent: false) == 5)
        #expect(IRCReconnectPolicy.attempt(after: 4, reusingCurrent: true) == 4)
        #expect(IRCReconnectPolicy.attempt(after: 0, reusingCurrent: true) == 1)
    }

    @Test("Channel event visibility treats 100 members as busy")
    func filtersBusyChannelEvents() {
        #expect(IRCChannelEventVisibility.alwaysShow.shouldShow(memberCount: 1_000))
        #expect(!IRCChannelEventVisibility.alwaysHide.shouldShow(memberCount: 1))
        #expect(IRCChannelEventVisibility.hideInBusyChannels.shouldShow(memberCount: 99))
        #expect(!IRCChannelEventVisibility.hideInBusyChannels.shouldShow(memberCount: 100))
        #expect(!IRCChannelEventVisibility.hideInBusyChannels.shouldShow(memberCount: 1_000))
    }

    @Test("Decorated messages retain the nickname used for color selection")
    func preservesNicknameColorIdentity() {
        let ordinary = IRCMessage(sender: "Alice", text: "Hello")
        let action = IRCMessage(sender: "* Alice", text: "waves", nicknameColorKey: "Alice")
        let notice = IRCMessage(sender: "Alice (notice)", text: "Hello", isNotice: true, nicknameColorKey: "Alice")

        #expect(ordinary.resolvedNicknameColorKey == "Alice")
        #expect(action.resolvedNicknameColorKey == ordinary.resolvedNicknameColorKey)
        #expect(notice.resolvedNicknameColorKey == ordinary.resolvedNicknameColorKey)
        #expect(ordinary.interactiveNickname == "Alice")
        #expect(action.interactiveNickname == "Alice")
        #expect(notice.interactiveNickname == nil)
    }

    @Test("Message rendering links web URLs and every channel occurrence")
    func rendersMessageLinks() throws {
        let message = IRCMessage(
            sender: "Alice",
            text: "See https://example.com, #swift, and #swift; skip ftp://example.com"
        )
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message)

        #expect(String(rendered.characters) == message.text)
        #expect(try link(for: "https://example.com", occurrence: 0, in: rendered) == URL(string: "https://example.com"))
        #expect(try link(for: "#swift", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#swift")
        #expect(try link(for: "#swift", occurrence: 1, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#swift")
        #expect(try link(for: "ftp://example.com", occurrence: 0, in: rendered) == nil)
    }

    @Test("Message previews classify image links, deduplicate URLs, and cap each message")
    func classifiesMessagePreviews() {
        let destination = SidebarItem.channel(UUID())
        let message = IRCMessage(
            sender: "Alice",
            text: "https://example.com/photo.JPG?large=1 https://swift.org https://swift.org https://example.net https://ignored.example"
        )

        #expect(IRCMessageTextRenderer.webURLs(for: message).count == 4)
        #expect(IRCMessagePreviewPolicy.previews(
            for: message,
            in: destination,
            showsLinkPreviews: false,
            showsImagePreviews: false
        ).isEmpty)
        #expect(IRCMessagePreviewPolicy.previews(
            for: message,
            in: destination,
            showsLinkPreviews: true,
            showsImagePreviews: true
        ) == [
            .image(URL(string: "https://example.com/photo.JPG?large=1")!),
            .link(URL(string: "https://swift.org")!),
            .link(URL(string: "https://example.net")!)
        ])
        #expect(IRCMessagePreviewPolicy.previews(
            for: message,
            in: destination,
            showsLinkPreviews: false,
            showsImagePreviews: true
        ) == [
            .image(URL(string: "https://example.com/photo.JPG?large=1")!)
        ])
    }

    @Test("Message previews skip direct non-image binary resources")
    func skipsBinaryMessagePreviews() {
        let message = IRCMessage(
            sender: "Alice",
            text: "https://example.com/movie.mp4 https://example.com/song.mp3 https://example.com/document.pdf https://example.com/article.html https://example.com/release.v2 https://example.com/photo.png https://example.com/archive.zip"
        )

        #expect(IRCMessagePreviewPolicy.previews(
            for: message,
            in: .channel(UUID()),
            showsLinkPreviews: true,
            showsImagePreviews: true
        ) == [
            .link(URL(string: "https://example.com/article.html")!),
            .link(URL(string: "https://example.com/release.v2")!),
            .image(URL(string: "https://example.com/photo.png")!)
        ])

        #expect(IRCMessagePreviewPolicy.previews(
            for: IRCMessage(sender: "Alice", text: "https://example.com/photo.png"),
            in: .channel(UUID()),
            showsLinkPreviews: true,
            showsImagePreviews: false
        ).isEmpty)
    }

    @Test("Preview disclosure state survives row reuse and channel changes")
    func preservesCollapsedPreviewStateByMessageAndChannel() {
        let firstMessageID = UUID()
        let secondMessageID = UUID()
        let firstChannel = SidebarItem.channel(UUID())
        let secondChannel = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()

        #expect(expansion.isExpanded(for: firstMessageID, in: firstChannel))
        #expect(expansion.isExpanded(for: secondMessageID, in: secondChannel))

        expansion.toggle(for: firstMessageID, in: firstChannel)

        #expect(!expansion.isExpanded(for: firstMessageID, in: firstChannel))
        #expect(expansion.isExpanded(for: secondMessageID, in: secondChannel))

        expansion.setExpanded(false, for: secondMessageID, in: secondChannel)

        #expect(!expansion.isExpanded(for: firstMessageID, in: firstChannel))
        #expect(!expansion.isExpanded(for: secondMessageID, in: secondChannel))

        // Visiting and cleaning up another channel must not discard the first
        // channel's disclosure choice.
        expansion.retainMessages(withIDs: [secondMessageID], in: secondChannel)

        #expect(!expansion.isExpanded(for: firstMessageID, in: firstChannel))

        expansion.setExpanded(true, for: firstMessageID, in: firstChannel)
        expansion.retainMessages(withIDs: [firstMessageID], in: firstChannel)

        #expect(expansion.isExpanded(for: firstMessageID, in: firstChannel))
        #expect(!expansion.isExpanded(for: secondMessageID, in: secondChannel))
    }

    @Test("A loaded preview explicitly invalidates its transcript row")
    func invalidatesRowAfterPreviewLoad() throws {
        let messageID = UUID()
        let selection = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()

        expansion.invalidateLayout(for: messageID, in: selection)
        let firstChange = try #require(expansion.latestLayoutChange)

        #expect(firstChange.selection == selection)
        #expect(firstChange.messageID == messageID)
        #expect(expansion.isExpanded(for: messageID, in: selection))

        expansion.invalidateLayout(for: messageID, in: selection)
        let secondChange = try #require(expansion.latestLayoutChange)

        #expect(secondChange.revision > firstChange.revision)
    }

    @Test("Preview layout changes remain available for each conversation")
    func retainsPreviewLayoutChangesPerConversation() throws {
        let firstMessageID = UUID()
        let secondMessageID = UUID()
        let firstSelection = SidebarItem.channel(UUID())
        let secondSelection = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()

        expansion.invalidateLayout(for: firstMessageID, in: firstSelection)
        let firstChange = try #require(
            expansion.latestLayoutChange(for: firstSelection)
        )
        expansion.invalidateLayout(for: secondMessageID, in: secondSelection)

        #expect(expansion.latestLayoutChange(for: firstSelection) == firstChange)
        #expect(expansion.latestLayoutChange(for: secondSelection)?.messageID == secondMessageID)
        #expect(expansion.latestLayoutChange?.selection == secondSelection)
    }

    @Test("A burst of loaded image previews produces one transcript layout refresh")
    @MainActor
    func coalescesImagePreviewLoadLayoutInvalidations() async throws {
        let selection = SidebarItem.channel(UUID())
        let messageIDs = (0..<20).map { _ in UUID() }
        let expansion = IRCMessagePreviewExpansionStore()

        for messageID in messageIDs {
            expansion.schedulePreviewLayoutInvalidation(
                for: messageID,
                in: selection
            )
        }

        #expect(expansion.latestLayoutChange == nil)
        try await Self.waitUntil(timeout: .seconds(1)) {
            expansion.latestLayoutChange != nil
        }
        let change = try #require(expansion.latestLayoutChange)
        #expect(change.selection == selection)
        #expect(change.messageID == messageIDs.last)
        #expect(change.revision == 1)
    }

    @Test("Preview cache keeps the newest visible resources under its cost limit")
    @MainActor
    func deterministicallyEvictsLeastRecentlyUsedPreview() {
        var cache = IRCPreviewMemoryCache<String, Int>(
            countLimit: 3,
            totalCostLimit: 64
        )
        cache.insert(1, for: "older", cost: 46)
        cache.insert(2, for: "first-visible", cost: 18)
        cache.insert(3, for: "second-visible", cost: 18)

        #expect(cache.value(for: "older") == nil)
        #expect(cache.value(for: "first-visible") == 2)
        #expect(cache.value(for: "second-visible") == 3)

        // Reads refresh recency, so a later insertion evicts the entry that is
        // no longer being used rather than either currently visible preview.
        cache.insert(4, for: "later", cost: 32)

        #expect(cache.value(for: "first-visible") == nil)
        #expect(cache.value(for: "second-visible") == 3)
        #expect(cache.value(for: "later") == 4)
    }

    @Test("Preview disclosure updates an existing hosted row")
    @MainActor
    func updatesHostedRowWhenPreviewExpansionChanges() async throws {
        let messageID = UUID()
        let selection = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()
        var renderedExpansion: Bool?
        let hostingController = NSHostingController(
            rootView: PreviewExpansionObservationTestRow(
                messageID: messageID,
                selection: selection,
                expansion: expansion,
                onRender: { renderedExpansion = $0 }
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil {
            renderedExpansion == true
        }
        #expect(renderedExpansion == true)

        // This is the same store operation used by the disclosure button.
        // The hosting root is intentionally not replaced between toggles.
        expansion.toggle(for: messageID, in: selection)

        try await Self.waitUntil {
            renderedExpansion == false
        }
        #expect(renderedExpansion == false)
    }

    @Test("A completed preview replaces its placeholder row at full height")
    @MainActor
    func rebuildsRowAfterPreviewLoad() async throws {
        let message = IRCMessage(sender: "tester", text: "Image preview")
        let selection = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()
        var isLoaded = false
        var didPositionInitially = false

        func rootView() -> AnyView {
            let rowLayoutInvalidation = expansion.latestLayoutChange.map {
                IRCTranscriptRowLayoutInvalidation(
                    messageID: $0.messageID,
                    revision: $0.revision
                )
            }
            let preview: AnyView = if isLoaded {
                AnyView(
                    IRCBoundedImageLayout(aspectRatio: 4.0 / 3.0) {
                        Color.orange
                    }
                )
            } else {
                AnyView(Color.clear.frame(width: 373, height: 96))
            }
            return AnyView(
                IRCTranscriptTable(
                    contentIdentity: selection,
                    messages: [message],
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "async-preview-height-test",
                    rowLayoutInvalidation: rowLayoutInvalidation,
                    makeRow: { _ in
                        AnyView(
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preview")
                                preview
                            }
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 600, height: 500)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            didPositionInitially
                && Self.view(
                    withIdentifier: "IRCTranscriptTable",
                    in: hostingController.view
                ) != nil
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let placeholderHeight = tableView.rect(ofRow: 1).height

        isLoaded = true
        expansion.invalidateLayout(for: message.id, in: selection)
        hostingController.rootView = rootView()

        try await Self.waitUntil(timeout: .seconds(3)) {
            tableView.rect(ofRow: 1).height > placeholderHeight + 150
        }
        #expect(tableView.rect(ofRow: 1).height > placeholderHeight + 150)

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Re-expanding a retained preview updates its native transcript row height")
    @MainActor
    func remeasuresRetainedPreviewAfterExpansion() async throws {
        let messages = (0..<5).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        let targetMessage = try #require(messages.last)
        let selection = SidebarItem.channel(UUID())
        let expansion = IRCMessagePreviewExpansionStore()
        var didPositionInitially = false

        // Simulate revisiting a channel whose preview was collapsed before
        // this transcript and its reusable hosting cells were constructed.
        expansion.setExpanded(
            false,
            for: targetMessage.id,
            in: selection
        )

        let hostingController = NSHostingController(
            rootView: AnyView(
                PreviewExpansionHeightTestTranscript(
                    messages: messages,
                    targetMessageID: targetMessage.id,
                    selection: selection,
                    expansion: expansion,
                    onInitialPositioned: { didPositionInitially = true }
                )
                .frame(width: 320, height: 240)
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            didPositionInitially
                && Self.view(
                    withIdentifier: "IRCTranscriptTable",
                    in: hostingController.view
                ) != nil
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let targetRow = messages.count
        let collapsedHeight = tableView.rect(ofRow: targetRow).height

        expansion.setExpanded(
            true,
            for: targetMessage.id,
            in: selection
        )

        try await Self.waitUntil(timeout: .seconds(3)) {
            tableView.rect(ofRow: targetRow).height > collapsedHeight + 50
        }
        #expect(tableView.rect(ofRow: targetRow).height > collapsedHeight + 50)

        // Drain any coalesced AppKit invalidation before the next serialized
        // integration test starts.
        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Automatic previews only appear for regular channel and direct messages")
    func limitsAutomaticPreviewsToRegularConversationMessages() {
        let notice = IRCMessage(
            sender: "Alice (notice)",
            text: "https://example.com/photo.jpg https://example.com/article",
            isNotice: true,
            nicknameColorKey: "Alice"
        )
        let systemMessage = IRCMessage(
            sender: "System",
            text: "https://example.com/photo.jpg",
            isSystem: true
        )
        let regularMessage = IRCMessage(
            sender: "Alice",
            text: "https://example.com/photo.jpg"
        )
        let conversationDestinations: [SidebarItem] = [
            .channel(UUID()),
            .directMessage(UUID())
        ]

        for destination in conversationDestinations {
            #expect(IRCMessagePreviewPolicy.previews(
                for: notice,
                in: destination,
                showsLinkPreviews: true,
                showsImagePreviews: true
            ).isEmpty)
            #expect(IRCMessagePreviewPolicy.previews(
                for: systemMessage,
                in: destination,
                showsLinkPreviews: true,
                showsImagePreviews: true
            ).isEmpty)
            #expect(!IRCMessagePreviewPolicy.previews(
                for: regularMessage,
                in: destination,
                showsLinkPreviews: true,
                showsImagePreviews: true
            ).isEmpty)
        }

        #expect(IRCMessagePreviewPolicy.previews(
            for: regularMessage,
            in: .server(UUID()),
            showsLinkPreviews: true,
            showsImagePreviews: true
        ).isEmpty)
    }

    @Test("Automatic previews reject local and private network targets")
    func protectsLocalAddressesFromAutomaticPreviews() {
        for address in [
            "https://localhost/image.png",
            "https://router.local/image.png",
            "https://0.0.0.0/image.png",
            "https://127.0.0.1/image.png",
            "https://0177.0.0.1/image.png",
            "https://10.0.0.1/image.png",
            "https://100.64.0.1/image.png",
            "https://169.254.169.254/latest/meta-data",
            "https://172.16.10.2/image.png",
            "https://192.168.1.1/image.png",
            "https://198.18.0.1/image.png",
            "https://224.0.0.1/image.png",
            "https://[::1]/image.png",
            "https://[::ffff:192.168.1.1]/image.png",
            "https://[fc00::1]/image.png",
            "https://[fe80::1]/image.png",
            "https://[ff02::1]/image.png",
            "https://[2001:db8::1]/image.png",
            "https://[2002:0a00:0001::1]/image.png",
            "https://[2001:2::1]/image.png",
            "https://[2620:4f:8000::1]/image.png",
            "https://[3fff::1]/image.png",
            "https://example.com:8443/image.png",
            "https://user:password@example.com/image.png"
        ] {
            #expect(!IRCRemotePreviewPolicy.isPermitted(URL(string: address)!))
        }
        #expect(IRCRemotePreviewPolicy.isPermitted(URL(string: "https://example.com/image.png")!))
        #expect(IRCRemotePreviewPolicy.isPermitted(URL(string: "https://1.1.1.1/image.png")!))
        #expect(IRCRemotePreviewPolicy.isPermitted(URL(string: "https://[2606:4700:4700::1111]/image.png")!))
        #expect(!IRCRemotePreviewPolicy.isPermitted(URL(string: "http://example.com/image.png")!))
    }

    @Test("Preview redirects remain on-host and never downgrade HTTPS")
    func validatesPreviewRedirects() {
        #expect(!IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "http://example.com/article")!,
            to: URL(string: "https://example.com/article")!
        ))
        #expect(IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "https://example.com/old")!,
            to: URL(string: "https://example.com/new")!
        ))
        #expect(!IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "https://example.com/article")!,
            to: URL(string: "http://example.com/article")!
        ))
        #expect(!IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "https://example.com/article")!,
            to: URL(string: "https://cdn.example.com/article")!
        ))
        #expect(!IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "https://example.com/article")!,
            to: URL(string: "http://127.0.0.1/admin")!
        ))
        #expect(!IRCRemotePreviewPolicy.permitsRedirect(
            from: URL(string: "https://youtu.be/dQw4w9WgXcQ")!,
            to: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        ))
    }

    @Test("YouTube short links normalize without allowing generic cross-host redirects")
    func normalizesYouTubeShortLinks() {
        #expect(IRCRemotePreviewPolicy.normalizedNetworkURL(
            URL(string: "https://youtu.be/dQw4w9WgXcQ?si=tracking#fragment")!
        ) == URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)
        #expect(IRCRemotePreviewPolicy.normalizedNetworkURL(
            URL(string: "https://youtu.be/not-a-video-id")!
        ) == nil)
        #expect(IRCRemotePreviewPolicy.normalizedNetworkURL(
            URL(string: "https://youtu.be/dQw4w9WgXcQ/extra")!
        ) == nil)
    }

    @Test("HTML head detection is streaming and case insensitive")
    func detectsEndOfHTMLHead() {
        var terminator = IRCHTMLHeadTerminator()
        let html = Data("<html><HeAd><title>Example</title></hEaD><body>Ignored".utf8)
        let detectionIndexes = html.indices.filter { terminator.consume(html[$0]) }
        #expect(detectionIndexes == [40])

        var nonTerminator = IRCHTMLHeadTerminator()
        #expect(!Data("</header>".utf8).contains { nonTerminator.consume($0) })

        var collector = IRCBoundedHTMLHeadCollector(maximumBytes: 128)
        let firstChunkCompletedHead = collector.consume(Data("<html><he".utf8))
        let secondChunkCompletedHead = collector.consume(
            Data("ad><title>Example</title></HEAD><body>Ignored".utf8)
        )
        #expect(!firstChunkCompletedHead)
        #expect(secondChunkCompletedHead)
        #expect(String(decoding: collector.data, as: UTF8.self) ==
            "<html><head><title>Example</title></HEAD>")

        var boundedCollector = IRCBoundedHTMLHeadCollector(maximumBytes: 8)
        let reachedByteLimit = boundedCollector.consume(Data(repeating: 65, count: 32))
        #expect(reachedByteLimit)
        #expect(boundedCollector.data == Data(repeating: 65, count: 8))
    }

    @Test("Preview resources deduplicate URL fragments")
    func deduplicatesPreviewFragments() {
        let message = IRCMessage(
            sender: "Alice",
            text: "https://example.com/article#first https://example.com/article#second"
        )
        #expect(IRCMessagePreviewPolicy.previews(
            for: message,
            in: .channel(UUID()),
            showsLinkPreviews: true,
            showsImagePreviews: false
        ).count == 1)
    }

    @Test("HTML metadata is converted to bounded inert plain text")
    func sanitizesLinkPreviewMetadata() {
        let html = """
        <html><head>
        <title>Ignored fallback</title>
        <meta content="Description &amp; details" name="description">
        <meta content="&#x202E;&lt;script&gt;alert(1)&lt;/script&gt; Safe &amp; Sound" property="og:title">
        </head></html>
        """
        let metadata = IRCLinkPreviewMetadataParser.parse(
            data: Data(html.utf8),
            responseURL: URL(string: "https://example.com/article")!
        )

        #expect(metadata.title == "alert(1) Safe & Sound")
        #expect(metadata.summary == "Description & details")
        #expect(metadata.title?.contains("<script>") == false)
        #expect(metadata.title?.unicodeScalars.contains(where: { $0.value == 0x202E }) == false)
    }

    @Test("HTML metadata falls back to the title element and limits output length")
    func boundsLinkPreviewMetadata() {
        let oversizedTitle = String(repeating: "A", count: 500)
        let html = "<title>\(oversizedTitle)</title>"
        let metadata = IRCLinkPreviewMetadataParser.parse(
            data: Data(html.utf8),
            responseURL: URL(string: "https://example.com")!
        )

        #expect(metadata.title?.count == 200)
        #expect(metadata.summary == nil)

        let combiningTitle = "A" + String(repeating: "\u{0301}", count: 500)
        let combiningMetadata = IRCLinkPreviewMetadataParser.parse(
            data: Data("<title>\(combiningTitle)</title>".utf8),
            responseURL: URL(string: "https://example.com")!
        )
        #expect(combiningMetadata.title?.unicodeScalars.count == 200)
    }

    @Test("Reddit post previews use the public oEmbed endpoint")
    func createsRedditOEmbedURLs() throws {
        let permalink = try #require(URL(
            string: "https://www.reddit.com/r/AbsoluteUnits/comments/1mewyt5/of_a_mustache/?utm_source=share#comments"
        ))
        let oEmbedURL = try #require(IRCLinkPreviewMetadataParser.redditOEmbedURL(for: permalink))
        let components = try #require(URLComponents(
            url: oEmbedURL,
            resolvingAgainstBaseURL: false
        ))

        #expect(components.scheme == "https")
        #expect(components.host == "www.reddit.com")
        #expect(components.path == "/oembed")
        #expect(components.queryItems == [
            URLQueryItem(
                name: "url",
                value: "https://www.reddit.com/r/AbsoluteUnits/comments/1mewyt5/of_a_mustache/"
            )
        ])
        #expect(IRCLinkPreviewMetadataParser.redditOEmbedURL(
            for: URL(string: "https://www.reddit.com/r/AbsoluteUnits/")!
        ) == nil)
        #expect(IRCLinkPreviewMetadataParser.redditOEmbedURL(
            for: URL(string: "https://reddit.example/r/AbsoluteUnits/comments/1mewyt5/title/")!
        ) == nil)
    }

    @Test("Reddit oEmbed metadata is rendered as inert preview text")
    func parsesRedditOEmbedMetadata() throws {
        let originalURL = URL(
            string: "https://www.reddit.com/r/AbsoluteUnits/comments/1mewyt5/of_a_mustache/"
        )!
        let response = """
        {
          "author_name": "amrindersr16",
          "provider_name": "reddit",
          "title": "of a mustache",
          "type": "rich"
        }
        """
        let metadata = try IRCLinkPreviewMetadataParser.parseRedditOEmbed(
            data: Data(response.utf8),
            originalURL: originalURL
        )

        #expect(metadata.title == "of a mustache")
        #expect(metadata.summary == "Posted by u/amrindersr16")
        #expect(metadata.resolvedURL == originalURL)
    }

    @Test("Image previews accept bounded raster data and reject malformed data")
    func validatesImagePreviewData() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))

        #expect(IRCBoundedImageLoader.thumbnail(from: pngData) != nil)
        #expect(IRCBoundedImageLoader.thumbnail(from: Data("<script>alert(1)</script>".utf8)) == nil)
    }

    @Test("Preview failures provide useful user-facing reasons")
    func describesPreviewFailures() {
        #expect(IRCPreviewFailureReason(error: URLError(.timedOut)) == .timedOut)
        #expect(IRCPreviewFailureReason(error: IRCPreviewError.tooLarge) == .tooLarge)
        #expect(IRCPreviewFailureReason(error: IRCPreviewError.disallowedRedirect) == .blocked)
        #expect(IRCPreviewFailureReason(error: IRCPreviewError.invalidImage) == .unavailable)
        #expect(IRCPreviewFailureReason.timedOut.message == "The preview took too long to load.")
    }

    @Test("Preview downloads enforce their byte limit for known and unknown lengths")
    func boundsPreviewDownloads() {
        #expect(!IRCPreviewTransferPolicy.exceedsLimit(
            totalBytesWritten: 12,
            totalBytesExpectedToWrite: 12,
            maximumBytes: 12
        ))
        #expect(IRCPreviewTransferPolicy.exceedsLimit(
            totalBytesWritten: 13,
            totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown,
            maximumBytes: 12
        ))
        #expect(IRCPreviewTransferPolicy.exceedsLimit(
            totalBytesWritten: 1,
            totalBytesExpectedToWrite: 13,
            maximumBytes: 12
        ))
    }

    @Test("Saved image names preserve useful names and add missing extensions")
    func suggestsSavedImageFilenames() {
        #expect(IRCImageSavePolicy.suggestedFilename(
            for: URL(string: "https://example.com/photos/sunset.jpg?size=large")!,
            mimeType: "image/jpeg"
        ) == "sunset.jpg")
        #expect(IRCImageSavePolicy.suggestedFilename(
            for: URL(string: "https://example.com/download")!,
            mimeType: "image/png"
        ) == "download.png")
        #expect(IRCImageSavePolicy.suggestedFilename(
            for: URL(string: "https://example.com/")!,
            mimeType: "image/webp"
        ) == "image.webp")
        #expect(IRCImageSavePolicy.contentType(for: "text/html") == nil)
    }

    @Test("Image viewer expands only when source resolution warrants it")
    func sizesImageViewerForSourceResolution() {
        let screenSize = CGSize(width: 2_000, height: 1_200)

        #expect(IRCImageViewerSizingPolicy.preferredModalSize(
            imagePixelSize: CGSize(width: 1_600, height: 900),
            screenVisibleSize: screenSize
        ) == CGSize(width: 1_500, height: 900))
        #expect(IRCImageViewerSizingPolicy.preferredModalSize(
            imagePixelSize: CGSize(width: 1_200, height: 675),
            screenVisibleSize: screenSize
        ) == CGSize(width: 1_500, height: 900))
        #expect(IRCImageViewerSizingPolicy.preferredModalSize(
            imagePixelSize: CGSize(width: 640, height: 360),
            screenVisibleSize: screenSize
        ) == CGSize(width: 900, height: 700))
    }

    @Test("Enlarged image viewer animates only multi-frame GIFs")
    func selectsAnimatedImageRendering() {
        #expect(IRCEnlargedImagePolicy.shouldAnimate(mimeType: "image/gif", frameCount: 2))
        #expect(IRCEnlargedImagePolicy.shouldAnimate(mimeType: "IMAGE/GIF", frameCount: 20))
        #expect(!IRCEnlargedImagePolicy.shouldAnimate(mimeType: "image/gif", frameCount: 1))
        #expect(!IRCEnlargedImagePolicy.shouldAnimate(mimeType: "image/png", frameCount: 20))
    }

    @Test("Image previews report their aspect-fitted size without blank framing")
    func sizesImagePreviews() {
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 1,
            within: CGSize(width: 520, height: 280)
        ) == CGSize(width: 280, height: 280))
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 2,
            within: CGSize(width: 520, height: 280)
        ) == CGSize(width: 520, height: 260))
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 0.5,
            within: CGSize(width: 520, height: 280)
        ) == CGSize(width: 140, height: 280))
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 2,
            within: CGSize(width: 300, height: 280)
        ) == CGSize(width: 300, height: 150))
    }

    @Test("Image preview sizing ignores stale automatic-row height proposals")
    func ignoresStaleImagePreviewRowHeight() {
        // Async image loading starts in a 96-point placeholder row. Its stale
        // height proposal must not become the loaded preview's intrinsic cap.
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 2,
            proposal: ProposedViewSize(width: 520, height: 96)
        ) == CGSize(width: 520, height: 260))
        #expect(IRCBoundedImageLayout.fittedSize(
            aspectRatio: 2,
            proposal: ProposedViewSize(width: 300, height: 96)
        ) == CGSize(width: 300, height: 150))
    }

    @Test("Chat typography defaults to SF Mono")
    func exposesChatFonts() {
        #expect(IRCChatFont.allCases == [.system, .rounded, .monospaced])
        #expect(IRCChatFont.default == .monospaced)
        #expect(IRCChatFont.system.label == "System (SF Pro)")
        #expect(IRCChatFont.monospaced.label == "SF Mono")
    }

    @Test("Message rendering recognizes IRC channel types and trims surrounding punctuation")
    func detectsChannelReferencesInMessages() throws {
        let message = IRCMessage(
            sender: "Alice",
            text: "Try (#swift), &local; +modeless or !safe. Not C++, word#tag, or https://example.com/#fragment"
        )
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message)

        for channel in ["#swift", "&local", "+modeless", "!safe"] {
            #expect(try link(for: channel, occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == channel)
        }
        #expect(try link(for: "word#tag", occurrence: 0, in: rendered) == nil)
        #expect(try link(for: "C++", occurrence: 0, in: rendered) == nil)
        #expect(try link(for: "https://example.com/#fragment", occurrence: 0, in: rendered) == URL(string: "https://example.com/#fragment"))
    }

    @Test("Message rendering honors server-advertised custom channel types")
    func linkifiesAdvertisedChannelTypes() {
        let message = IRCMessage(
            sender: "Alice",
            text: "Try $staff and #ordinary.",
            channelTypes: ["$"]
        )
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message)
        let links = rendered.runs.compactMap(\.link)

        #expect(links.contains(IRCInternalLink.channelURL(for: "$staff")!))
        #expect(!links.contains(IRCInternalLink.channelURL(for: "#ordinary")!))
        #expect(IRCInternalLink.channelName(
            from: IRCInternalLink.channelURL(for: "$staff")!
        ) == "$staff")
    }

    @Test("Advertised channel links still handle membership-prefixed WHOIS output")
    func rendersAdvertisedChannelLinks() throws {
        let message = IRCMessage(
            sender: "System",
            text: "Alice is on: @+#operators @#voiced @+#local",
            isSystem: true,
            channelLinks: IRCWhoisChannelParser.channels(
                from: "@+#operators @#voiced @+#local"
            )
        )
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message)

        #expect(try link(for: "#operators", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#operators")
        #expect(try link(for: "#voiced", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#voiced")
        #expect(try link(for: "#local", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#local")
    }

    @Test("System message rendering preserves generic senders and prefixes event senders")
    func rendersSystemMessages() {
        let generic = IRCMessage(sender: "System", text: "Connected", isSystem: true)
        let event = IRCMessage(sender: "→ Alice", text: "joined #swift", isSystem: true)

        #expect(IRCMessageTextRenderer.displayText(for: generic) == "Connected")
        #expect(IRCMessageTextRenderer.displayText(for: event) == "→ Alice joined #swift")
    }

    @Test("IRC formatting codes are stripped by default and rendered only when enabled")
    func handlesIRCFormattingCodes() throws {
        let message = IRCMessage(
            sender: "Alice",
            text: "\u{03}04red\u{03} plain \u{02}bold\u{02} \u{1D}italic\u{1D} \u{1F}underlined\u{1F}"
        )
        let stripped = IRCMessageTextRenderer.linkifiedText(for: message)
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message, rendersIRCFormatting: true)
        let expected = "red plain bold italic underlined"

        #expect(String(stripped.characters) == expected)
        #expect(String(rendered.characters) == expected)
        #expect(try attributes(for: "red", in: stripped).foregroundColor == nil)
        #expect(try attributes(for: "red", in: rendered).foregroundColor != nil)
        #expect(try attributes(for: "bold", in: rendered).inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(try attributes(for: "italic", in: rendered).inlinePresentationIntent?.contains(.emphasized) == true)
        #expect(try attributes(for: "underlined", in: rendered).underlineStyle != nil)
    }

    @Test("IRC rendering removes non-formatting control characters")
    func stripsIRCControlCharacters() {
        #expect(IRCMessageTextRenderer.plainText("hello\u{07}\u{01}world\u{0F}") == "helloworld")
    }

    @Test("IRC color formatting preserves commas that do not introduce a background color")
    func preservesLiteralCommasAfterIRCColors() {
        #expect(IRCMessageTextRenderer.plainText("\u{03}04, decimal") == ", decimal")
        #expect(IRCMessageTextRenderer.plainText("\u{04}FF0000, hexadecimal") == ", hexadecimal")
        #expect(IRCMessageTextRenderer.plainText("\u{03}04,12decimal") == "decimal")
        #expect(IRCMessageTextRenderer.plainText("\u{04}FF0000,00FF00hexadecimal") == "hexadecimal")
    }

    @Test("Server activity aggregates unread conversations and mentions")
    func aggregatesServerActivity() {
        let serverID = UUID()
        let activity = IRCServerActivity(serverID: serverID, conversations: [
            Conversation(name: "#quiet", serverID: serverID),
            Conversation(name: "#unread", serverID: serverID, hasUnread: true),
            Conversation(name: "#mention", serverID: serverID, hasUnread: true, hasMention: true),
            Conversation(name: "#other-server", serverID: UUID(), hasUnread: true, hasMention: true)
        ])

        #expect(activity.unreadConversationCount == 2)
        #expect(activity.mentionConversationCount == 1)
        #expect(activity.hasUnread)
        #expect(activity.hasMention)
        #expect(activity.indicator == .mention)
        #expect(activity.accessibilityDescription == "1 mention, 2 unread conversations")
    }

    @Test("Server activity uses an unread indicator when there are no mentions")
    func prioritizesServerActivityIndicators() {
        let serverID = UUID()
        let activity = IRCServerActivity(serverID: serverID, conversations: [
            Conversation(name: "#unread", serverID: serverID, hasUnread: true)
        ])

        #expect(activity.indicator == .unread)
        #expect(activity.accessibilityDescription == "1 unread conversation")
    }

    @Test("Server activity has no summary when every conversation is read")
    func omitsEmptyServerActivity() {
        let serverID = UUID()
        let activity = IRCServerActivity(serverID: serverID, conversations: [
            Conversation(name: "#quiet", serverID: serverID)
        ])

        #expect(!activity.hasUnread)
        #expect(!activity.hasMention)
        #expect(activity.indicator == nil)
        #expect(activity.accessibilityDescription == nil)
    }

    @Test("Channel activity starts five seconds after joining")
    func delaysChannelActivityAfterJoining() {
        let joinedAt = ContinuousClock().now

        #expect(!IRCConversationActivityPolicy.shouldAccumulateChannelActivity(
            joinedAt: nil,
            now: joinedAt.advanced(by: .seconds(10))
        ))
        #expect(!IRCConversationActivityPolicy.shouldAccumulateChannelActivity(
            joinedAt: joinedAt,
            now: joinedAt.advanced(by: .milliseconds(4_999))
        ))
        #expect(IRCConversationActivityPolicy.shouldAccumulateChannelActivity(
            joinedAt: joinedAt,
            now: joinedAt.advanced(by: .seconds(5))
        ))
    }

    @Test("Messages received immediately after joining do not mark a channel unread")
    @MainActor
    func suppressesChannelActivityImmediatelyAfterJoining() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        let nickname = state.nickname

        state.handle(
            try #require(IRCWireMessage(line: ":\(nickname)!user@example.org JOIN #welcome")),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(line: ":Greeter!bot@example.org PRIVMSG #welcome :Welcome!")),
            profile: profile
        )

        let channel = try #require(state.channels.first {
            $0.serverID == profile.id && $0.name == "#welcome"
        })
        #expect(!channel.hasUnread)
        #expect(state.messages(
            for: .channel(channel.id),
            channelEventVisibility: .alwaysShow
        ).contains { $0.text == "Welcome!" })
    }

    @Test("Marking a server read clears only that server's conversation activity")
    func clearsConversationActivityForOneServer() {
        let serverID = UUID()
        let otherServerID = UUID()
        var conversations = [
            Conversation(
                name: "#swift",
                serverID: serverID,
                hasUnread: true,
                hasMention: true
            ),
            Conversation(
                name: "Alice",
                serverID: serverID,
                hasUnread: true
            ),
            Conversation(
                name: "#other",
                serverID: otherServerID,
                hasUnread: true,
                hasMention: true
            )
        ]

        IRCConversationActivityPolicy.clearActivity(
            for: serverID,
            in: &conversations
        )

        #expect(!conversations[0].hasUnread)
        #expect(!conversations[0].hasMention)
        #expect(!conversations[1].hasUnread)
        #expect(!conversations[1].hasMention)
        #expect(conversations[2].hasUnread)
        #expect(conversations[2].hasMention)
    }

    @Test("Muted conversation merges discard unread activity")
    func discardsUnreadActivityWhenMergingMutedConversations() {
        #expect(!IRCConversationActivityPolicy.mergedUnreadState(
            existingHasUnread: false,
            incomingHasUnread: true,
            conversationIsMuted: true
        ))
        #expect(!IRCConversationActivityPolicy.mergedUnreadState(
            existingHasUnread: true,
            incomingHasUnread: false,
            conversationIsMuted: true
        ))
        #expect(IRCConversationActivityPolicy.mergedUnreadState(
            existingHasUnread: false,
            incomingHasUnread: true,
            conversationIsMuted: false
        ))
    }

    @Test("Message text cache invalidates when mutable render content changes")
    func invalidatesCachedMessageText() throws {
        let cache = IRCMessageTextCache(countLimit: 10)
        var message = IRCMessage(sender: "Alice", text: "Before", channelLinks: ["#one"])
        let original = cache.attributedText(for: message)

        message.text = "After #two"
        message.channelLinks = ["#two"]
        let updated = cache.attributedText(for: message)

        #expect(String(original.characters) == "Before")
        #expect(String(updated.characters) == "After #two")
        #expect(try link(for: "#two", occurrence: 0, in: updated).flatMap(IRCInternalLink.channelName(from:)) == "#two")
    }

    @Test("Message web URL cache invalidates when mutable detection content changes")
    func invalidatesCachedMessageWebURLs() {
        let cache = IRCMessageWebURLCache(countLimit: 10)
        var message = IRCMessage(sender: "Alice", text: "https://before.example")

        #expect(cache.webURLs(for: message) == [URL(string: "https://before.example")!])

        message.text = "https://after.example"

        #expect(cache.webURLs(for: message) == [URL(string: "https://after.example")!])
    }

    @Test("Transcript scrolling animates at most once per throttle interval")
    func throttlesTranscriptAnimations() {
        let previous = Date(timeIntervalSince1970: 1_000)

        #expect(!IRCTranscriptScrollPolicy.shouldAnimate(
            lastAnimatedScroll: previous,
            now: previous.addingTimeInterval(IRCTranscriptScrollPolicy.minimumAnimatedScrollInterval - 0.01)
        ))
        #expect(IRCTranscriptScrollPolicy.shouldAnimate(
            lastAnimatedScroll: previous,
            now: previous.addingTimeInterval(IRCTranscriptScrollPolicy.minimumAnimatedScrollInterval + 0.01)
        ))
    }

    @Test("Conversation replacement discards inherited momentum until a direct scroll")
    func discardsInheritedTranscriptMomentum() {
        var policy = IRCTranscriptScrollMomentumPolicy()

        let forwardsInitialMomentum = policy.shouldForwardScroll(hasMomentum: true)
        #expect(forwardsInitialMomentum)

        policy.discardMomentumUntilNextDirectScroll()

        let forwardsFirstInheritedMomentum = policy.shouldForwardScroll(hasMomentum: true)
        let forwardsLaterInheritedMomentum = policy.shouldForwardScroll(hasMomentum: true)
        let forwardsDirectScroll = policy.shouldForwardScroll(hasMomentum: false)
        let forwardsNewMomentum = policy.shouldForwardScroll(hasMomentum: true)

        #expect(!forwardsFirstInheritedMomentum)
        #expect(!forwardsLaterInheritedMomentum)
        #expect(forwardsDirectScroll)
        #expect(forwardsNewMomentum)
    }

    @Test("Transcript tail following tolerates the bottom inset and detects scrolling into history")
    func detectsTranscriptTailPosition() {
        let content = CGRect(x: 0, y: 0, width: 600, height: 1_000)

        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: CGRect(x: 0, y: 600, width: 600, height: 400),
            contentBounds: content,
            contentIsFlipped: true
        ))
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: CGRect(x: 0, y: 580, width: 600, height: 400),
            contentBounds: content,
            contentIsFlipped: true
        ))
        #expect(!IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: CGRect(x: 0, y: 500, width: 600, height: 400),
            contentBounds: content,
            contentIsFlipped: true
        ))

        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: CGRect(x: 0, y: 0, width: 600, height: 400),
            contentBounds: content,
            contentIsFlipped: false
        ))
        #expect(!IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: CGRect(x: 0, y: 100, width: 600, height: 400),
            contentBounds: content,
            contentIsFlipped: false
        ))
    }

    @Test("Transcript scroll notifications publish only tail-boundary transitions at retention-scale heights")
    func deduplicatesTranscriptTailChanges() {
        let rowHeight: CGFloat = 24
        let content = CGRect(
            x: 0,
            y: 0,
            width: 600,
            height: CGFloat(IRCConversationHistory.retentionLimit) * rowHeight
        )
        let viewportHeight: CGFloat = 600
        let bottom = CGRect(
            x: 0,
            y: content.maxY - viewportHeight,
            width: content.width,
            height: viewportHeight
        )
        let history = bottom.offsetBy(dx: 0, dy: -rowHeight * 10)
        var isFollowingTail = true
        var publishedChanges = 0

        for _ in 0..<IRCConversationHistory.retentionLimit {
            if let newValue = IRCTranscriptScrollPolicy.followingTailChange(
                from: isFollowingTail,
                visibleBounds: history,
                contentBounds: content,
                contentIsFlipped: true
            ) {
                isFollowingTail = newValue
                publishedChanges += 1
            }
        }
        #expect(!isFollowingTail)
        #expect(publishedChanges == 1)

        for _ in 0..<IRCConversationHistory.retentionLimit {
            if let newValue = IRCTranscriptScrollPolicy.followingTailChange(
                from: isFollowingTail,
                visibleBounds: bottom,
                contentBounds: content,
                contentIsFlipped: true
            ) {
                isFollowingTail = newValue
                publishedChanges += 1
            }
        }
        #expect(isFollowingTail)
        #expect(publishedChanges == 2)
    }

    @Test("Transcript history trims in a batch beyond the five-thousand-message limit and preserves the newest tail")
    func trimsTranscriptHistoryAtRetentionBoundary() {
        var messages: [IRCMessage] = []
        let totalBeforeTrim = IRCConversationHistory.retentionLimit + IRCConversationHistory.trimBatchSize

        for index in 0..<(IRCConversationHistory.retentionLimit - 1) {
            IRCConversationHistory.append(
                IRCMessage(sender: "Alice", text: "message \(index)"),
                to: &messages
            )
        }
        #expect(messages.count == IRCConversationHistory.retentionLimit - 1)

        let messageAtLimit = IRCMessage(
            sender: "Alice",
            text: "message \(IRCConversationHistory.retentionLimit - 1)"
        )
        IRCConversationHistory.append(messageAtLimit, to: &messages)
        #expect(messages.count == IRCConversationHistory.retentionLimit)
        #expect(messages.last?.id == messageAtLimit.id)

        for index in IRCConversationHistory.retentionLimit..<totalBeforeTrim {
            IRCConversationHistory.append(
                IRCMessage(sender: "Alice", text: "message \(index)"),
                to: &messages
            )
        }

        #expect(messages.count == totalBeforeTrim)
        #expect(messages.first?.text == "message 0")
        #expect(messages.last?.text == "message \(totalBeforeTrim - 1)")

        let messageAfterThreshold = IRCMessage(sender: "Alice", text: "message \(totalBeforeTrim)")
        IRCConversationHistory.append(messageAfterThreshold, to: &messages)

        #expect(messages.count == IRCConversationHistory.retentionLimit)
        #expect(messages.first?.text == "message \(IRCConversationHistory.trimBatchSize + 1)")
        #expect(messages.last?.id == messageAfterThreshold.id)
    }

    @Test("Merging renamed conversations preserves time order and retention limits")
    func mergesConversationHistory() {
        let base = Date(timeIntervalSince1970: 1_000)
        let first = [
            IRCMessage(sender: "Alice", text: "one", timestamp: base.addingTimeInterval(1)),
            IRCMessage(sender: "Alice", text: "three", timestamp: base.addingTimeInterval(3))
        ]
        let second = [
            IRCMessage(sender: "Alice", text: "zero", timestamp: base),
            IRCMessage(sender: "Alice", text: "two", timestamp: base.addingTimeInterval(2))
        ]

        let merged = IRCConversationHistory.merging(first, second, limit: 3)
        #expect(merged.map(\.text) == ["one", "two", "three"])
        #expect(IRCConversationHistory.merging(first, second, limit: 0).isEmpty)
    }

    @Test("Closing a direct message returns to its server")
    @MainActor
    func closesActiveDirectMessage() {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))

        #expect(state.canCloseActiveSelection)
        #expect(state.directMessages.count == 1)

        state.closeActiveSelection()

        #expect(state.directMessages.isEmpty)
        #expect(state.selection == .server(profile.id))
    }

    @Test("Conversation mute state toggles with IRC case mapping")
    @MainActor
    func togglesConversationMuteStateUsingIRCCaseMapping() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.startDirectMessage(with: "Alice[Work]", from: .server(profile.id))
        let directMessage = try #require(state.directMessages.first {
            $0.serverID == profile.id && $0.name == "Alice[Work]"
        })
        let equivalentName = Conversation(name: "alice{work}", serverID: profile.id)
        let existingMutedNames = profile.mutedConversationNames ?? []

        state.mute(directMessage)

        #expect(state.isMuted(directMessage))
        #expect(state.isMuted(equivalentName))
        #expect(
            state.profiles.first(where: { $0.id == profile.id })?.mutedConversationNames
                == existingMutedNames + ["Alice[Work]"]
        )

        state.unmute(equivalentName)

        #expect(!state.isMuted(directMessage))
        #expect(
            state.profiles.first(where: { $0.id == profile.id })?.mutedConversationNames
                == (existingMutedNames.isEmpty ? nil : existingMutedNames)
        )
    }

    @Test("Opening a direct message notification selects its conversation")
    @MainActor
    func opensDirectMessageNotification() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)

        state.openDirectMessageNotification(
            IRCDirectMessageNotificationDestination(serverID: profile.id, nickname: "Alice")
        )

        let directMessage = try #require(state.directMessages.first {
            $0.serverID == profile.id && $0.name == "Alice"
        })
        #expect(state.selection == .directMessage(directMessage.id))
    }

    @Test("Conversation update signals stay scoped to their conversation")
    @MainActor
    func scopesConversationUpdates() throws {
        let state = IRCAppState()
        let profile = state.profiles[0]

        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.directMessages.first { $0.name == "Alice" })
        let aliceUpdates = state.messageUpdates(for: .directMessage(alice.id))
        #expect(aliceUpdates === state.messageUpdates(for: .directMessage(alice.id)))

        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        let bob = try #require(state.directMessages.first { $0.name == "Bob" })
        let bobUpdates = state.messageUpdates(for: .directMessage(bob.id))

        state.close(bob)

        #expect(aliceUpdates.revision == 0)
        #expect(bobUpdates.revision == 1)
        let replacementBobUpdates = state.messageUpdates(for: .directMessage(bob.id))
        #expect(replacementBobUpdates !== bobUpdates)
        #expect(replacementBobUpdates.revision == 0)
    }

    @Test("Clear removes only the selected transcript and works while disconnected")
    @MainActor
    func clearsSelectedTranscript() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.selection)
        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        let bob = try #require(state.selection)
        let aliceMessages = state.messages(for: alice, channelEventVisibility: .alwaysShow)
        let aliceUpdates = state.messageUpdates(for: alice)

        #expect(!aliceMessages.isEmpty)
        #expect(!state.messages(for: bob, channelEventVisibility: .alwaysShow).isEmpty)
        #expect(state.send("/clear", to: alice))

        #expect(state.messages(for: alice, channelEventVisibility: .alwaysShow).isEmpty)
        #expect(!state.messages(for: bob, channelEventVisibility: .alwaysShow).isEmpty)
        #expect(aliceUpdates.revision == 1)
    }

    @Test("Automatic MOTD replies route to their server transcript")
    @MainActor
    func routesAutomaticMOTDToMatchingServer() throws {
        let state = IRCAppState()
        let profile = try #require(state.profiles.first)
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let selectedConversation = try #require(state.selection)
        let selectedMessages = state.messages(
            for: selectedConversation,
            channelEventVisibility: .alwaysShow
        )

        state.handle(
            try #require(IRCWireMessage(line: ":irc.example.org 001 tester :Connected")),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(line: ":irc.example.org 375 tester :- Message of the Day -")),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(line: ":irc.example.org 372 tester :- Welcome")),
            profile: profile
        )
        state.handle(
            try #require(IRCWireMessage(line: ":irc.example.org 376 tester :End of /MOTD")),
            profile: profile
        )

        #expect(state.selection == selectedConversation)
        #expect(
            state.messages(for: selectedConversation, channelEventVisibility: .alwaysShow)
                == selectedMessages
        )
        #expect(
            state.messages(for: .server(profile.id), channelEventVisibility: .alwaysShow)
                .map(\.text)
                .suffix(3)
                == ["Connected", "- Message of the Day -", "- Welcome"]
        )
    }

    @Test("Transcript update signals throttle bursts without starving trailing updates")
    @MainActor
    func throttlesTranscriptUpdateBursts() async throws {
        let signal = IRCRevisionSignal(minimumPublicationInterval: .milliseconds(60))

        signal.advance()
        #expect(signal.revision == 1)

        for _ in 0..<5 {
            signal.advance()
        }
        #expect(signal.revision == 1)

        var deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while signal.revision != 2, ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(signal.revision == 2)

        signal.advance()
        #expect(signal.revision == 2)

        deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while signal.revision != 3, ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(signal.revision == 3)

        try await Task.sleep(for: .milliseconds(80))
        signal.advance()
        #expect(signal.revision == 4)
    }

    @Test("Member list shortcut only applies to channels")
    @MainActor
    func ignoresMemberListToggleOutsideChannels() {
        let state = IRCAppState()
        let initialValue = state.showsMemberList

        #expect(!state.canToggleMemberList)
        state.toggleMemberList()
        #expect(state.showsMemberList == initialValue)
    }

    @Test("Join navigation waits for server confirmation and does not override later navigation")
    func selectsChannelOnlyAfterSuccessfulJoin() {
        let server = SidebarItem.server(UUID())
        let otherConversation = SidebarItem.channel(UUID())
        let joinedChannelID = UUID()

        #expect(IRCJoinSelectionPolicy.selectionAfterSuccessfulJoin(
            currentSelection: server,
            requestDestination: server,
            joinedChannelID: joinedChannelID,
            selectsConversation: true
        ) == .channel(joinedChannelID))

        #expect(IRCJoinSelectionPolicy.selectionAfterSuccessfulJoin(
            currentSelection: otherConversation,
            requestDestination: server,
            joinedChannelID: joinedChannelID,
            selectsConversation: true
        ) == otherConversation)

        #expect(IRCJoinSelectionPolicy.selectionAfterSuccessfulJoin(
            currentSelection: server,
            requestDestination: server,
            joinedChannelID: joinedChannelID,
            selectsConversation: false
        ) == server)
    }

    @Test("Sidebar conversation selection requests composer focus, including reselection")
    @MainActor
    func focusesComposerForSidebarChannelSelection() throws {
        let state = IRCAppState()
        let firstChannel = SidebarItem.channel(UUID())
        let directMessage = SidebarItem.directMessage(UUID())

        state.selectFromSidebar(firstChannel)
        let firstRequest = try #require(state.workspaceFocusRequest)
        #expect(state.selection == firstChannel)
        #expect(firstRequest.target == .composer(firstChannel))

        state.selectFromSidebar(directMessage)
        let secondRequest = try #require(state.workspaceFocusRequest)
        #expect(state.selection == directMessage)
        #expect(secondRequest.target == .composer(directMessage))
        #expect(secondRequest.id != firstRequest.id)

        state.selectFromSidebar(directMessage)
        let reselectionRequest = try #require(state.workspaceFocusRequest)
        #expect(reselectionRequest.target == .composer(directMessage))
        #expect(reselectionRequest.id != secondRequest.id)
    }

    @Test("Native composer is reused and becomes first responder when focus is requested")
    @MainActor
    func focusesNativeComposer() async throws {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.selection)
        state.setDraft("Alice draft", for: alice)
        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        let bob = try #require(state.selection)
        state.setDraft("Bob draft", for: bob)
        state.selectFromSidebar(alice)

        let hostingController = NSHostingController(
            rootView: ContentView(state: state)
                .frame(width: 1_000, height: 700)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            Self.composer(in: hostingController.view) != nil
        }
        let initialComposer = try #require(Self.composer(in: hostingController.view))
        try await Self.waitUntil {
            window.firstResponder === initialComposer
        }
        #expect(window.firstResponder === initialComposer)
        #expect(initialComposer.string == "Alice draft")

        #expect(window.makeFirstResponder(nil))
        state.requestComposerFocus()
        try await Self.waitUntil {
            window.firstResponder === initialComposer
        }
        #expect(window.firstResponder === initialComposer)

        #expect(window.makeFirstResponder(nil))
        state.selectFromSidebar(bob)
        try await Self.waitUntil {
            window.firstResponder === initialComposer
                && initialComposer.string == "Bob draft"
        }
        let switchedComposer = try #require(Self.composer(in: hostingController.view))
        #expect(switchedComposer === initialComposer)
        #expect(window.firstResponder === switchedComposer)
        #expect(switchedComposer.string == "Bob draft")
        #expect(!(switchedComposer.undoManager?.canUndo ?? false))

        state.selectFromSidebar(alice)
        try await Self.waitUntil {
            initialComposer.string == "Alice draft"
        }
        #expect(Self.composer(in: hostingController.view) === initialComposer)
        #expect(initialComposer.string == "Alice draft")
    }

    @Test("Native composer recalls, edits, and resends history")
    @MainActor
    func navigatesHistoryInNativeComposer() async throws {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.selection)
        state.recordComposerInput("hello Alice", for: alice)
        state.recordComposerInput("/msg Alice original", for: alice)
        state.setDraft("unfinished draft", for: alice)

        let hostingController = NSHostingController(
            rootView: ContentView(state: state)
                .frame(width: 1_000, height: 700)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            Self.composer(in: hostingController.view)?.string == "unfinished draft"
        }
        let composer = try #require(Self.composer(in: hostingController.view))

        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 126)))
        #expect(composer.string == "/msg Alice original")
        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 126)))
        #expect(composer.string == "hello Alice")
        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 125)))
        #expect(composer.string == "/msg Alice original")
        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 125)))
        #expect(composer.string == "unfinished draft")

        composer.string = "/msg Alice edited"
        composer.didChangeText()
        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 36, characters: "\r")))
        try await Self.waitUntil { composer.string.isEmpty }
        composer.keyDown(with: try #require(Self.keyEvent(keyCode: 126)))
        #expect(composer.string == "/msg Alice edited")
    }

    @Test("Native transcript virtualizes retained rows and initially positions at the tail")
    @MainActor
    func virtualizesNativeTranscript() async throws {
        let messages = (0..<1_000).map { index in
            IRCMessage(
                sender: "tester",
                text: index == 999
                    ? String(repeating: "This message must wrap at the table width. ", count: 20)
                    : "Message \(index)"
            )
        }
        var initialGeometry: IRCTranscriptTableGeometry?
        let hostingController = NSHostingController(
            rootView: IRCTranscriptTable(
                messages: messages,
                estimatedRowHeight: 24,
                rowSpacing: 0,
                renderConfiguration: "test",
                makeRow: { message in
                    AnyView(
                        Text(message.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
                },
                onInitialPositioned: { initialGeometry = $0 },
                onFollowingTailChange: { _, _ in },
                onTailPositioned: { _, _ in },
                onGeometryChange: { _, _ in }
            )
            .frame(width: 320, height: 700)
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
        hostingController.view.layoutSubtreeIfNeeded()
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        #expect(scrollView.alphaValue == 0)

        try await Task.sleep(for: .milliseconds(200))
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let geometry = try #require(initialGeometry)
        let hostedRowCount = Self.views(
            withIdentifier: "IRCTranscriptHostedRow",
            in: hostingController.view
        ).count
        let revealedDocumentHeight = geometry.documentFrame.height

        // Initial positioning must not expose the table while its first
        // viewport-width and automatic-row-height refresh is still pending.
        try await Task.sleep(for: .milliseconds(100))
        hostingController.view.layoutSubtreeIfNeeded()

        #expect(tableView.numberOfRows == messages.count + 2)
        #expect(hostedRowCount > 0)
        #expect(hostedRowCount < 100)
        #expect(tableView.rect(ofRow: messages.count).height > 24)
        #expect(abs(tableView.frame.height - revealedDocumentHeight) < 0.5)
        #expect(scrollView.alphaValue == 1)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: geometry.visibleBounds,
            contentBounds: geometry.contentBounds,
            contentIsFlipped: geometry.contentIsFlipped,
            tolerance: 1
        ))
    }

    @Test("Native transcript waits for a real viewport before initial positioning")
    @MainActor
    func defersInitialPositionUntilViewportIsLaidOut() async throws {
        let messages = (0..<200).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var transcriptHeight: CGFloat = 0
        var initialGeometry: IRCTranscriptTableGeometry?

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "deferred-initial-position-test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { initialGeometry = $0 },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: transcriptHeight)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 0)
        hostingController.view.layoutSubtreeIfNeeded()
        let initialScrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )

        try await Task.sleep(for: .milliseconds(100))
        #expect(initialGeometry == nil)
        #expect(initialScrollView.alphaValue == 0)

        transcriptHeight = 240
        hostingController.rootView = rootView()
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil {
            (initialGeometry?.visibleBounds.width ?? 0) > 1
                && (initialGeometry?.visibleBounds.height ?? 0) > 1
        }
        let geometry = try #require(initialGeometry)
        let positionedScrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        #expect(positionedScrollView.alphaValue == 1)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: geometry.visibleBounds,
            contentBounds: geometry.contentBounds,
            contentIsFlipped: geometry.contentIsFlipped,
            tolerance: 1
        ))

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Native transcript retains its scroll view when conversation content changes")
    @MainActor
    func retainsNativeTranscriptAcrossConversationChanges() async throws {
        var contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<120).map {
            IRCMessage(sender: "first", text: "First conversation message \($0)")
        }
        var initialGeometries: [IRCTranscriptTableGeometry] = []

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "conversation-replacement-test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { initialGeometries.append($0) },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 500)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil { initialGeometries.count == 1 }
        let initialScrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        let initialTableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )

        contentIdentity = .channel(UUID())
        messages = (0..<75).map {
            IRCMessage(
                sender: "second",
                text: String(repeating: "Second conversation message \($0). ", count: 3)
            )
        }
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()

        let hiddenScrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        #expect(hiddenScrollView === initialScrollView)
        #expect(hiddenScrollView.alphaValue == 0)

        try await Self.waitUntil { initialGeometries.count == 2 }
        let finalScrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        let finalTableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let finalGeometry = try #require(initialGeometries.last)

        #expect(finalScrollView === initialScrollView)
        #expect(finalTableView === initialTableView)
        #expect(finalTableView.numberOfRows == messages.count + 2)
        #expect(finalScrollView.alphaValue == 1)
        let finalBottomDistance = finalGeometry.contentBounds.maxY
            - finalGeometry.visibleBounds.maxY
        #expect(abs(finalBottomDistance) <= 1)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: finalGeometry.visibleBounds,
            contentBounds: finalGeometry.contentBounds,
            contentIsFlipped: finalGeometry.contentIsFlipped,
            tolerance: 1
        ))

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Native transcript reuses measured row heights when revisiting a conversation")
    @MainActor
    func reusesMeasuredTranscriptRowHeightsAcrossConversationChanges() async throws {
        let firstIdentity = SidebarItem.channel(UUID())
        let secondIdentity = SidebarItem.channel(UUID())
        let firstMessages = (0..<80).map {
            IRCMessage(sender: "first", text: "First conversation message \($0)")
        }
        let secondMessages = (0..<80).map {
            IRCMessage(sender: "second", text: "Second conversation message \($0)")
        }
        let firstLayoutMessageID = try #require(firstMessages.last?.id)
        var contentIdentity = firstIdentity
        var messages = firstMessages
        var firstRowHeight: CGFloat = 84
        let secondRowHeight: CGFloat = 36
        var firstLayoutRevision: UInt64?
        var initialPositionCount = 0

        func rootView() -> AnyView {
            let rowLayoutInvalidation: IRCTranscriptRowLayoutInvalidation? =
                if contentIdentity == firstIdentity, let firstLayoutRevision {
                IRCTranscriptRowLayoutInvalidation(
                    messageID: firstLayoutMessageID,
                    revision: firstLayoutRevision
                )
            } else {
                nil
            }
            return AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "conversation-height-cache-test",
                    rowLayoutInvalidation: rowLayoutInvalidation,
                    makeRow: { message in
                        let fixedRowHeight = message.sender == "first"
                            ? firstRowHeight
                            : secondRowHeight
                        return AnyView(
                            Text(message.text)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: fixedRowHeight,
                                    maxHeight: fixedRowHeight,
                                    alignment: .leading
                                )
                        )
                    },
                    onInitialPositioned: { _ in initialPositionCount += 1 },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 500)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 1 }

        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let delegate = try #require(tableView.delegate)
        let firstHeight = delegate.tableView?(
            tableView,
            heightOfRow: firstMessages.count
        )
        #expect((firstHeight ?? 0) > 80)

        contentIdentity = secondIdentity
        messages = secondMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 2 }

        let secondHeight = delegate.tableView?(
            tableView,
            heightOfRow: secondMessages.count
        )
        #expect((secondHeight ?? 0) > 32)
        #expect((secondHeight ?? 0) < 40)

        contentIdentity = firstIdentity
        messages = firstMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()

        // Before the revisited rows are realized again, the delegate should
        // already offer AppKit the exact height measured on the first visit.
        let revisitedHeight = delegate.tableView?(
            tableView,
            heightOfRow: firstMessages.count
        )
        #expect(abs((revisitedHeight ?? 0) - (firstHeight ?? 0)) <= 0.5)

        try await Self.waitUntil { initialPositionCount == 3 }

        // Simulate an asynchronous preview completing after its conversation
        // has gone inactive, followed by another visit. The pending per-
        // conversation signal must discard the old estimate before reveal.
        contentIdentity = secondIdentity
        messages = secondMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 4 }

        firstRowHeight = 124
        firstLayoutRevision = 1
        contentIdentity = firstIdentity
        messages = firstMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil(timeout: .seconds(3)) {
            initialPositionCount == 5
                && tableView.rect(ofRow: firstMessages.count).height > 120
        }
        let refreshedHeight = delegate.tableView?(
            tableView,
            heightOfRow: firstMessages.count
        )
        #expect((refreshedHeight ?? 0) > 120)

        // The applied revision should not keep evicting the now-correct cache.
        contentIdentity = secondIdentity
        messages = secondMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 6 }
        contentIdentity = firstIdentity
        messages = firstMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        let recachedHeight = delegate.tableView?(
            tableView,
            heightOfRow: firstMessages.count
        )
        #expect(abs((recachedHeight ?? 0) - (refreshedHeight ?? 0)) <= 0.5)
        try await Self.waitUntil { initialPositionCount == 7 }

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Retained conversation stays bottom-aligned when its viewport height settles")
    @MainActor
    func bottomAlignsRetainedConversationAfterViewportHeightChange() async throws {
        var contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<80).map {
            IRCMessage(sender: "first", text: "First conversation message \($0)")
        }
        var transcriptHeight: CGFloat = 500
        var initialPositionCount = 0

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "viewport-height-reconciliation-test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(height: 24, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in initialPositionCount += 1 },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: transcriptHeight)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 1 }

        contentIdentity = .channel(UUID())
        messages = (0..<10).map {
            IRCMessage(sender: "second", text: "Short conversation message \($0)")
        }
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 2 }

        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )

        transcriptHeight = 700
        hostingController.rootView = rootView()
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil {
            let newestMessageBottom = tableView.rect(ofRow: messages.count).maxY
            let expectedMessageBottom = scrollView.contentView.bounds.height - 18
            return abs(newestMessageBottom - expectedMessageBottom) <= 1
        }

        let newestMessageBottom = tableView.rect(ofRow: messages.count).maxY
        let expectedMessageBottom = scrollView.contentView.bounds.height - 18

        #expect(abs(newestMessageBottom - expectedMessageBottom) <= 1)

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Native transcript reuses hosted cells without leaking row state or callbacks")
    @MainActor
    func reusesNativeTranscriptCells() async throws {
        let messages = (0..<200).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        var renderedStateOwners: [UUID: UUID] = [:]

        let hostingController = NSHostingController(
            rootView: AnyView(
                IRCTranscriptTable(
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "reuse-test",
                    makeRow: { message in
                        AnyView(
                            TranscriptTestStatefulRow(messageID: message.id) {
                                renderedMessageID, stateOwnerMessageID in
                                renderedStateOwners[renderedMessageID] = stateOwnerMessageID
                            }
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 240)
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            didPositionInitially
                && !Self.views(
                    withIdentifier: "IRCTranscriptHostedRow",
                    in: hostingController.view
                ).isEmpty
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let initialHostingViewIDs = Set(
            Self.views(
                withIdentifier: "IRCTranscriptHostedRow",
                in: hostingController.view
            ).map(ObjectIdentifier.init)
        )

        tableView.scrollRowToVisible(1)
        tableView.layoutSubtreeIfNeeded()
        try await Self.waitUntil {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            let currentHostingViewIDs = Set(
                Self.views(
                    withIdentifier: "IRCTranscriptHostedRow",
                    in: hostingController.view
                ).map(ObjectIdentifier.init)
            )
            return visibleRows.location != NSNotFound
                && NSLocationInRange(1, visibleRows)
                && !initialHostingViewIDs.isDisjoint(with: currentHostingViewIDs)
        }

        let reusedHostingView = try #require(
            Self.views(
                withIdentifier: "IRCTranscriptHostedRow",
                in: hostingController.view
            ).compactMap { $0 as? IntrinsicInvalidatingHostingView }
                .first { initialHostingViewIDs.contains(ObjectIdentifier($0)) }
        )
        let reusedCell = try #require(reusedHostingView.superview as? NSTableCellView)
        let reusedRow = tableView.row(for: reusedCell)
        let reusedMessage = try #require(
            messages.indices.contains(reusedRow - 1) ? messages[reusedRow - 1] : nil
        )

        try await Self.waitUntil {
            renderedStateOwners[reusedMessage.id] != nil
        }
        #expect(reusedHostingView.representedMessageID == reusedMessage.id)
        #expect(renderedStateOwners[reusedMessage.id] == reusedMessage.id)

        var invalidatedMessageID: UUID?
        let originalInvalidation = reusedHostingView.onIntrinsicSizeInvalidated
        reusedHostingView.onIntrinsicSizeInvalidated = { messageID in
            invalidatedMessageID = messageID
        }
        reusedHostingView.invalidateIntrinsicContentSize()
        reusedHostingView.onIntrinsicSizeInvalidated = originalInvalidation
        #expect(invalidatedMessageID == reusedMessage.id)

        // Explicitly dismantle the representable and drain its queued AppKit
        // invalidation before the next serialized integration test begins.
        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Native transcript does not reuse hosted cells across conversations")
    @MainActor
    func isolatesNativeTranscriptCellsByConversation() async throws {
        let firstIdentity = SidebarItem.channel(UUID())
        let secondIdentity = SidebarItem.channel(UUID())
        let firstMessages = (0..<100).map {
            IRCMessage(sender: "first", text: "First conversation message \($0)")
        }
        let secondMessages = (0..<100).map {
            IRCMessage(sender: "second", text: "Second conversation message \($0)")
        }
        var contentIdentity = firstIdentity
        var messages = firstMessages
        var initialPositionCount = 0

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "conversation-cell-isolation-test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: message.sender == "first" ? 72 : 24,
                                    maxHeight: message.sender == "first" ? 72 : 24,
                                    alignment: .leading
                                )
                        )
                    },
                    onInitialPositioned: { _ in initialPositionCount += 1 },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 240)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil { initialPositionCount == 1 }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )

        func visibleHostingViewIDs() -> Set<ObjectIdentifier> {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return [] }
            return Set(
                (visibleRows.location..<NSMaxRange(visibleRows)).compactMap { row in
                    guard let cell = tableView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ),
                    let hostingView = Self.view(
                        withIdentifier: "IRCTranscriptHostedRow",
                        in: cell
                    ) else { return nil }
                    return ObjectIdentifier(hostingView)
                }
            )
        }

        let firstHostingViewIDs = visibleHostingViewIDs()
        #expect(!firstHostingViewIDs.isEmpty)

        contentIdentity = secondIdentity
        messages = secondMessages
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil {
            initialPositionCount == 2 && !visibleHostingViewIDs().isEmpty
        }

        let secondHostingViewIDs = visibleHostingViewIDs()
        #expect(firstHostingViewIDs.isDisjoint(with: secondHostingViewIDs))

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Reattached native transcript rows cancel deferred hosted-content release")
    @MainActor
    func cancelsDeferredReleaseForReattachedNativeTranscriptContent() async throws {
        let messages = (0..<100).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        let hostingController = NSHostingController(
            rootView: AnyView(
                IRCTranscriptTable(
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "release-hosted-content-test",
                    makeRow: { message in
                        AnyView(Text(message.text))
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 240)
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil { didPositionInitially }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let row = try #require(
            visibleRows.location == NSNotFound
                ? nil
                : visibleRows.location
        )
        let rowView = try #require(
            tableView.rowView(atRow: row, makeIfNecessary: false)
        )
        let hostedRow = try #require(
            Self.views(
                withIdentifier: "IRCTranscriptHostedRow",
                in: rowView
            ).compactMap { $0 as? IntrinsicInvalidatingHostingView }.first
        )
        let coordinator = try #require(
            tableView.delegate as? IRCTranscriptTable.Coordinator
        )

        #expect(hostedRow.hasHostedContent)
        #expect(hostedRow.representedMessageID != nil)

        coordinator.tableView(tableView, didRemove: rowView, forRow: row)

        #expect(hostedRow.hasHostedContent)
        #expect(hostedRow.representedMessageID != nil)
        #expect(hostedRow.hasPendingHostedContentRelease)

        coordinator.tableView(tableView, didAdd: rowView, forRow: row)

        #expect(hostedRow.hasHostedContent)
        #expect(hostedRow.representedMessageID != nil)
        #expect(!hostedRow.hasPendingHostedContentRelease)

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Detached hosted content releases to a neutral reusable placeholder")
    @MainActor
    func releasesDetachedHostedContentWithoutRetainingStaleHeight() async throws {
        let hostingView = IntrinsicInvalidatingHostingView(
            rootView: AnyView(EmptyView())
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.setHostedContent(
            AnyView(Color.clear.frame(width: 320, height: 96)),
            for: UUID()
        )
        hostingView.layoutSubtreeIfNeeded()
        let hostedHeight = hostingView.fittingSize.height

        hostingView.scheduleHostedContentRelease(
            after: 0.05,
            shouldRelease: { true }
        )
        #expect(hostingView.cancelPendingHostedContentRelease())
        try await Task.sleep(for: .milliseconds(100))
        #expect(hostingView.hasHostedContent)

        hostingView.scheduleHostedContentRelease(
            after: 0.05,
            shouldRelease: { true }
        )

        try await Self.waitUntil {
            !hostingView.hasHostedContent
        }
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostedHeight > 0)
        #expect(!hostingView.hasHostedContent)
        #expect(hostingView.representedMessageID == nil)
        #expect(!hostingView.hasPendingHostedContentRelease)

        let releasedHeight = hostingView.fittingSize.height
        #expect(releasedHeight < hostedHeight - 1)

        hostingView.setHostedContent(
            AnyView(Color.clear.frame(width: 320, height: 28)),
            for: UUID()
        )
        hostingView.layoutSubtreeIfNeeded()
        #expect(abs(hostingView.fittingSize.height - 28) < 0.5)
    }

    @Test("Transient native row removal does not restart an asynchronous preview")
    @MainActor
    func keepsPreviewStableThroughTransientNativeRowRemoval() async throws {
        let message = IRCMessage(sender: "tester", text: "Preview")
        let probe = TranscriptPreviewLifecycleProbe()
        var didPositionInitially = false
        let hostingController = NSHostingController(
            rootView: AnyView(
                IRCTranscriptTable(
                    messages: [message],
                    estimatedRowHeight: 72,
                    rowSpacing: 0,
                    renderConfiguration: "preview-lifecycle-test",
                    makeRow: { _ in
                        AnyView(TranscriptPreviewLifecycleTestRow(probe: probe))
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 240)
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil {
            didPositionInitially && probe.completions == 1
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let row = 1
        let rowView = try #require(
            tableView.rowView(atRow: row, makeIfNecessary: false)
        )
        let hostedRow = try #require(
            Self.views(
                withIdentifier: "IRCTranscriptHostedRow",
                in: rowView
            ).compactMap { $0 as? IntrinsicInvalidatingHostingView }.first
        )
        let coordinator = try #require(
            tableView.delegate as? IRCTranscriptTable.Coordinator
        )
        let settledHeight = tableView.rect(ofRow: row).height
        let settledTaskStarts = probe.taskStarts
        let settledCompletions = probe.completions

        for _ in 0..<4 {
            coordinator.tableView(tableView, didRemove: rowView, forRow: row)
            #expect(hostedRow.hasHostedContent)
            #expect(hostedRow.hasPendingHostedContentRelease)
            try await Task.sleep(for: .milliseconds(20))
            coordinator.tableView(tableView, didAdd: rowView, forRow: row)
            #expect(hostedRow.hasHostedContent)
            #expect(!hostedRow.hasPendingHostedContentRelease)
        }

        try await Task.sleep(for: .milliseconds(150))
        tableView.layoutSubtreeIfNeeded()

        #expect(settledTaskStarts > 0)
        #expect(settledCompletions > 0)
        #expect(probe.taskStarts == settledTaskStarts)
        #expect(probe.completions == settledCompletions)
        #expect(abs(tableView.rect(ofRow: row).height - settledHeight) < 0.5)

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Short native transcripts grow upward from the bottom")
    @MainActor
    func bottomAlignsShortNativeTranscript() async throws {
        var messages = [
            IRCMessage(sender: "tester", text: "Only message")
        ]
        var didPositionInitially = false
        var tailUpdateCount = 0

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in tailUpdateCount += 1 },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
        hostingController.view.layoutSubtreeIfNeeded()

        try await Self.waitUntil { didPositionInitially }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        let messageBottom = tableView.rect(ofRow: 1).maxY
        let expectedMessageBottom = scrollView.contentView.bounds.height - 18

        #expect(abs(messageBottom - expectedMessageBottom) <= 1)

        messages.append(IRCMessage(sender: "tester", text: "Newest message"))
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { tailUpdateCount == 1 }

        let newestMessageBottom = tableView.rect(ofRow: 2).maxY
        #expect(abs(newestMessageBottom - expectedMessageBottom) <= 1)
        #expect(tableView.rect(ofRow: 1).maxY < messageBottom)
    }

    @Test("An empty native transcript positions its first message once at the bottom")
    @MainActor
    func positionsFirstNativeTranscriptMessage() async throws {
        var messages: [IRCMessage] = []
        var initialPositionCount = 0
        var tailUpdateCount = 0

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in initialPositionCount += 1 },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in tailUpdateCount += 1 },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
        hostingController.view.layoutSubtreeIfNeeded()
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        #expect(scrollView.alphaValue == 0)

        messages.append(IRCMessage(sender: "tester", text: "First message"))
        hostingController.rootView = rootView()
        hostingController.view.layoutSubtreeIfNeeded()
        try await Self.waitUntil { initialPositionCount == 1 }
        try await Task.sleep(for: .milliseconds(100))

        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let expectedMessageBottom = scrollView.contentView.bounds.height - 18

        #expect(tableView.numberOfRows == 3)
        #expect(abs(tableView.rect(ofRow: 1).maxY - expectedMessageBottom) <= 1)
        #expect(scrollView.alphaValue == 1)
        #expect(initialPositionCount == 1)
        #expect(tailUpdateCount == 0)
    }

    @Test("Native transcript appends with one settled animated tail update")
    @MainActor
    func appendsNativeTranscriptAtTail() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<100).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        var tailUpdates: [(animated: Bool, geometry: IRCTranscriptTableGeometry)] = []
        var rowHeightChangeCount = 0

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { animated, geometry in
                        tailUpdates.append((animated, geometry))
                    },
                    onGeometryChange: { event, _ in
                        if event == "row-height-changed" {
                            rowHeightChangeCount += 1
                        }
                    }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil { didPositionInitially }
        let initialTableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let initialContentHeight = initialTableView.frame.height
        tailUpdates.removeAll()
        rowHeightChangeCount = 0

        messages.append(IRCMessage(sender: "tester", text: "Appended message"))
        hostingController.rootView = rootView()

        try await Self.waitUntil { !tailUpdates.isEmpty }
        let updatedTableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let tailUpdate = try #require(tailUpdates.last)

        #expect(updatedTableView === initialTableView)
        #expect(updatedTableView.numberOfRows == messages.count + 2)
        #expect(tailUpdates.count == 1)
        #expect(tailUpdate.geometry.contentBounds.height > initialContentHeight)
        #expect(tailUpdate.animated)
        #expect(rowHeightChangeCount == 0)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: tailUpdate.geometry.visibleBounds,
            contentBounds: tailUpdate.geometry.contentBounds,
            contentIsFlipped: tailUpdate.geometry.contentIsFlipped,
            tolerance: 1
        ))
    }

    @Test("Authoritative echo updates its native row without a second tail movement")
    @MainActor
    func updatesAuthoritativeEchoInPlace() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<80).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        var tailUpdateCount = 0
        var geometryEvents: [String] = []

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "authoritative-echo-in-place-test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in tailUpdateCount += 1 },
                    onGeometryChange: { event, _ in geometryEvents.append(event) }
                )
                .frame(width: 320, height: 500)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil { didPositionInitially }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        let lastRow = messages.count
        let initialDocumentHeight = tableView.frame.height
        let initialVisibleOrigin = scrollView.contentView.bounds.origin
        tailUpdateCount = 0
        geometryEvents.removeAll()

        messages[messages.index(before: messages.endIndex)].timestamp =
            messages[lastRow - 1].timestamp.addingTimeInterval(60)
        messages[messages.index(before: messages.endIndex)].ircv3Tags = [
            IRCMessageTag(name: "msgid", value: "authoritative-message")
        ]
        hostingController.rootView = rootView()

        try await Self.waitUntil(timeout: .seconds(2)) {
            geometryEvents.contains {
                $0.hasPrefix("messages-reconfigured-in-place count=1")
            }
        }
        try await Task.sleep(for: .milliseconds(250))

        #expect(tailUpdateCount == 0)
        #expect(!geometryEvents.contains {
            $0.hasPrefix("hosted-content-release-scheduled")
        })
        #expect(!geometryEvents.contains { $0 == "row-height-changed" })
        #expect(abs(tableView.frame.height - initialDocumentHeight) <= 1)
        #expect(abs(
            scrollView.contentView.bounds.origin.y - initialVisibleOrigin.y
        ) <= 1)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: scrollView.contentView.bounds,
            contentBounds: tableView.bounds,
            contentIsFlipped: tableView.isFlipped,
            tolerance: 1
        ))

        hostingController.rootView = AnyView(EmptyView())
        hostingController.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Appended native transcript rows expand to show every wrapped line")
    @MainActor
    func expandsAppendedWrappingTranscriptRow() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<40).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var transcriptWidth: CGFloat = 720
        var didPositionInitially = false
        var geometryEvents: [String] = []

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "wrapping-append-test",
                    makeRow: { message in
                        AnyView(
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("2:57 PM")
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 64, alignment: .trailing)
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(message.sender)
                                        .lineLimit(1)
                                        .frame(width: 116, alignment: .leading)
                                    Text(AttributedString(message.text))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .font(.system(size: 15, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { event, _ in geometryEvents.append(event) }
                )
                .frame(width: transcriptWidth, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: transcriptWidth, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil { didPositionInitially }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )

        messages.append(IRCMessage(
            sender: "tester",
            text: String(repeating: "Every wrapped line must remain visible. ", count: 20)
        ))
        hostingController.rootView = rootView()
        let appendedRow = messages.count

        try await Self.waitUntil(timeout: .seconds(2)) {
            tableView.numberOfRows == messages.count + 2
                && tableView.rect(ofRow: appendedRow).height > 40
        }
        let wideRowHeight = tableView.rect(ofRow: appendedRow).height

        geometryEvents.removeAll()
        for width: CGFloat in [640, 560, 480, 400, 320] {
            transcriptWidth = width
            hostingController.rootView = rootView()
            window.setContentSize(NSSize(width: transcriptWidth, height: 700))
            hostingController.view.frame = NSRect(
                x: 0,
                y: 0,
                width: transcriptWidth,
                height: 700
            )
            hostingController.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }

        try await Self.waitUntil(timeout: .seconds(2)) {
            scrollView.contentView.bounds.width < 400
                && tableView.rect(ofRow: appendedRow).height > wideRowHeight + 40
        }

        #expect(wideRowHeight > 40)
        #expect(scrollView.contentView.bounds.width < 400)
        #expect(tableView.rect(ofRow: appendedRow).height > wideRowHeight + 40)
        #expect(geometryEvents.filter { $0 == "width-reloaded" }.count == 1)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: scrollView.contentView.bounds,
            contentBounds: tableView.bounds,
            contentIsFlipped: tableView.isFlipped,
            tolerance: 1
        ))
    }

    @Test("Latest asynchronous preview growth finishes at the transcript tail")
    @MainActor
    func revealsLatestPreviewAfterAppendAnimation() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<40).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        let previewMessage = IRCMessage(sender: "tester", text: "Preview")
        var previewIsLoaded = false
        var previewLayoutRevision: UInt64 = 0
        var didPositionInitially = false
        var tailUpdates: [(animated: Bool, geometry: IRCTranscriptTableGeometry)] = []

        func rootView() -> AnyView {
            let invalidation = previewLayoutRevision == 0 ? nil :
                IRCTranscriptRowLayoutInvalidation(
                    messageID: previewMessage.id,
                    revision: previewLayoutRevision
                )
            return AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 30,
                    rowSpacing: 0,
                    renderConfiguration: "latest-preview-tail-test",
                    rowLayoutInvalidation: invalidation,
                    makeRow: { message in
                        AnyView(
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 30)
                                if message.id == previewMessage.id {
                                    Color.clear.frame(
                                        height: previewIsLoaded ? 180 : 30
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { _, _ in },
                    onTailPositioned: { animated, geometry in
                        tailUpdates.append((animated, geometry))
                    },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil { didPositionInitially }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )
        tailUpdates.removeAll()

        messages.append(previewMessage)
        hostingController.rootView = rootView()

        // Load after the coalesced append has begun its 120 ms animation,
        // matching a fast cached preview completing during that movement.
        try await Task.sleep(for: .milliseconds(100))
        previewIsLoaded = true
        previewLayoutRevision = 1
        hostingController.rootView = rootView()

        try await Self.waitUntil(timeout: .seconds(3)) {
            !tailUpdates.isEmpty
                && tableView.rect(ofRow: messages.count).height > 180
        }
        try await Task.sleep(for: .milliseconds(50))
        let tailUpdate = try #require(tailUpdates.last)
        let currentBottomDistance = tableView.bounds.maxY
            - scrollView.contentView.bounds.maxY

        #expect(tailUpdate.animated)
        #expect(IRCTranscriptScrollPolicy.isAtBottom(
            visibleBounds: tailUpdate.geometry.visibleBounds,
            contentBounds: tailUpdate.geometry.contentBounds,
            contentIsFlipped: tailUpdate.geometry.contentIsFlipped,
            tolerance: 1
        ))
        #expect(abs(currentBottomDistance) <= 1)
    }

    @Test("Retention trimming preserves the visible native transcript message and offset")
    @MainActor
    func preservesNativeTranscriptPositionAcrossRetentionTrim() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        var messages = (0..<5_250).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        var isFollowingTail = true

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: "test",
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { followingTail, _ in
                        isFollowingTail = followingTail
                    },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            didPositionInitially
                && Self.view(
                    withIdentifier: "IRCTranscriptTable",
                    in: hostingController.view
                ) != nil
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )

        let readingRow = 1_001
        tableView.scrollRowToVisible(readingRow)
        tableView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let readingBounds = NSRect(
            x: clipView.bounds.minX,
            y: tableView.rect(ofRow: readingRow).minY + 7,
            width: clipView.bounds.width,
            height: clipView.bounds.height
        )
        clipView.setBoundsOrigin(clipView.constrainBoundsRect(readingBounds).origin)
        scrollView.reflectScrolledClipView(clipView)
        try await Self.waitUntil {
            let rows = tableView.rows(in: tableView.visibleRect)
            return !isFollowingTail
                && rows.location != NSNotFound
                && NSLocationInRange(readingRow, rows)
        }
        #expect(!isFollowingTail)

        let visibleRows = tableView.rows(in: tableView.visibleRect)
        #expect(NSLocationInRange(readingRow, visibleRows))
        let anchorRow = try #require(
            visibleRows.location == NSNotFound
                ? nil
                : max(visibleRows.location, 1)
        )
        let anchorMessage = try #require(messages.indices.contains(anchorRow - 1)
            ? messages[anchorRow - 1]
            : nil)
        let originalOffset = tableView.rect(ofRow: anchorRow).minY
            - clipView.bounds.minY

        let newestMessage = IRCMessage(sender: "tester", text: "Message 5250")
        messages = Array(messages.dropFirst(251))
        messages.append(newestMessage)
        hostingController.rootView = rootView()

        try await Self.waitUntil {
            tableView.numberOfRows == messages.count + 2
                && messages.firstIndex(where: { $0.id == anchorMessage.id }) != nil
        }
        try await Task.sleep(for: .milliseconds(200))
        let restoredIndex = try #require(
            messages.firstIndex(where: { $0.id == anchorMessage.id })
        )
        let restoredOffset = tableView.rect(ofRow: restoredIndex + 1).minY
            - clipView.bounds.minY

        #expect(tableView.numberOfRows == IRCConversationHistory.retentionLimit + 2)
        #expect(abs(restoredOffset - originalOffset) <= 1)
        #expect(!isFollowingTail)
    }

    @Test("Height remeasurement preserves the visible native transcript message and offset")
    @MainActor
    func preservesNativeTranscriptPositionAcrossHeightRemeasurement() async throws {
        let contentIdentity = SidebarItem.channel(UUID())
        let messages = (0..<400).map {
            IRCMessage(sender: "tester", text: "Message \($0)")
        }
        var didPositionInitially = false
        var isFollowingTail = true
        var measuredRowHeight: CGFloat = 30
        var renderConfiguration = "height-30"

        func rootView() -> AnyView {
            AnyView(
                IRCTranscriptTable(
                    contentIdentity: contentIdentity,
                    messages: messages,
                    estimatedRowHeight: 24,
                    rowSpacing: 0,
                    renderConfiguration: renderConfiguration,
                    makeRow: { message in
                        AnyView(
                            Text(message.text)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: measuredRowHeight,
                                    maxHeight: measuredRowHeight,
                                    alignment: .leading
                                )
                        )
                    },
                    onInitialPositioned: { _ in didPositionInitially = true },
                    onFollowingTailChange: { followingTail, _ in
                        isFollowingTail = followingTail
                    },
                    onTailPositioned: { _, _ in },
                    onGeometryChange: { _, _ in }
                )
                .frame(width: 320, height: 700)
            )
        }

        let hostingController = NSHostingController(rootView: rootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        try await Self.waitUntil {
            didPositionInitially
                && Self.view(
                    withIdentifier: "IRCTranscriptTable",
                    in: hostingController.view
                ) != nil
        }
        let tableView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptTable",
                in: hostingController.view
            ) as? NSTableView
        )
        let scrollView = try #require(
            Self.view(
                withIdentifier: "IRCTranscriptScrollView",
                in: hostingController.view
            ) as? NSScrollView
        )

        let readingRow = 201
        tableView.scrollRowToVisible(readingRow)
        tableView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let readingBounds = NSRect(
            x: clipView.bounds.minX,
            y: tableView.rect(ofRow: readingRow).minY + 7,
            width: clipView.bounds.width,
            height: clipView.bounds.height
        )
        clipView.setBoundsOrigin(clipView.constrainBoundsRect(readingBounds).origin)
        scrollView.reflectScrolledClipView(clipView)
        try await Self.waitUntil {
            let rows = tableView.rows(in: tableView.visibleRect)
            return !isFollowingTail
                && rows.location != NSNotFound
                && NSLocationInRange(readingRow, rows)
        }
        #expect(!isFollowingTail)

        let visibleRows = tableView.rows(in: tableView.visibleRect)
        #expect(NSLocationInRange(readingRow, visibleRows))
        let anchorRow = try #require(
            visibleRows.location == NSNotFound
                ? nil
                : max(visibleRows.location, 1)
        )
        let anchorMessage = try #require(messages.indices.contains(anchorRow - 1)
            ? messages[anchorRow - 1]
            : nil)
        let originalOffset = tableView.rect(ofRow: anchorRow).minY
            - clipView.bounds.minY
        let originalHeight = tableView.rect(ofRow: anchorRow).height

        measuredRowHeight = 54
        renderConfiguration = "height-54"
        hostingController.rootView = rootView()
        try await Self.waitUntil(timeout: .seconds(3)) {
            abs(tableView.rect(ofRow: anchorRow).height - originalHeight) > 0.5
        }
        try await Task.sleep(for: .milliseconds(200))

        let restoredIndex = try #require(
            messages.firstIndex(where: { $0.id == anchorMessage.id })
        )
        let restoredOffset = tableView.rect(ofRow: restoredIndex + 1).minY
            - clipView.bounds.minY
        #expect(abs(tableView.rect(ofRow: restoredIndex + 1).height - originalHeight) > 0.5)
        #expect(abs(restoredOffset - originalOffset) <= 1)
        #expect(!isFollowingTail)
    }

    @Test("Conversation drafts remain separate and clear when emptied")
    @MainActor
    func preservesConversationDrafts() {
        let state = IRCAppState()
        let first = SidebarItem.server(state.profiles[0].id)
        let second = SidebarItem.directMessage(UUID())

        state.setDraft("first draft", for: first)
        state.setDraft("second draft", for: second)
        #expect(state.draft(for: first) == "first draft")
        #expect(state.draft(for: second) == "second draft")

        state.setDraft("", for: first)
        #expect(state.draft(for: first).isEmpty)
        #expect(state.draft(for: second) == "second draft")
    }

    @Test("Composer history walks sent input and restores the unfinished draft")
    func navigatesComposerHistory() {
        var history = IRCComposerHistory()
        history.record("hello everyone")
        history.record("/join #swift")

        #expect(history.navigate(.previous, from: "unfinished draft") == "/join #swift")
        #expect(history.navigate(.previous, from: "ignored while navigating") == "hello everyone")
        #expect(history.navigate(.previous, from: "ignored while navigating") == "hello everyone")
        #expect(history.navigate(.next, from: "ignored while navigating") == "/join #swift")
        #expect(history.navigate(.next, from: "ignored while navigating") == "unfinished draft")
        #expect(history.navigate(.next, from: "unfinished draft") == nil)

        history.record("/msg Alice edited version")
        #expect(history.navigate(.previous, from: "") == "/msg Alice edited version")
    }

    @Test("Composer histories stay scoped to their channel or direct message")
    @MainActor
    func scopesComposerHistoryToConversation() throws {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let aliceConversation = try #require(state.directMessages.first { $0.name == "Alice" })
        let alice = SidebarItem.directMessage(aliceConversation.id)
        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        let bobConversation = try #require(state.directMessages.first { $0.name == "Bob" })
        let bob = SidebarItem.directMessage(bobConversation.id)

        state.recordComposerInput("hello Alice", for: alice)
        #expect(state.send("/join #alice", to: alice))
        state.recordComposerInput("hello Bob", for: bob)

        #expect(state.navigateComposerHistory(.previous, from: "Alice draft", for: alice) == "/join #alice")
        #expect(state.navigateComposerHistory(.previous, from: "", for: alice) == "hello Alice")
        #expect(state.navigateComposerHistory(.previous, from: "Bob draft", for: bob) == "hello Bob")
        #expect(state.navigateComposerHistory(.next, from: "", for: bob) == "Bob draft")

        state.close(aliceConversation)
        #expect(state.navigateComposerHistory(.previous, from: "", for: alice) == nil)
    }

    @Test("Composer history arrows activate only at multiline boundaries")
    func appliesComposerHistoryCaretPolicy() {
        let multiline = "first line\nsecond line"
        let string = multiline as NSString
        let newline = string.range(of: "\n")

        #expect(IRCComposerHistoryCaretPolicy.canNavigate(
            .previous,
            in: multiline,
            selectedRange: NSRange(location: newline.location, length: 0)
        ))
        #expect(!IRCComposerHistoryCaretPolicy.canNavigate(
            .previous,
            in: multiline,
            selectedRange: NSRange(location: NSMaxRange(newline), length: 0)
        ))
        #expect(!IRCComposerHistoryCaretPolicy.canNavigate(
            .next,
            in: multiline,
            selectedRange: NSRange(location: newline.location, length: 0)
        ))
        #expect(IRCComposerHistoryCaretPolicy.canNavigate(
            .next,
            in: multiline,
            selectedRange: NSRange(location: NSMaxRange(newline), length: 0)
        ))
        #expect(!IRCComposerHistoryCaretPolicy.canNavigate(
            .previous,
            in: "single line",
            selectedRange: NSRange(location: 0, length: 1)
        ))
        #expect(IRCComposerHistoryCaretPolicy.canNavigate(
            .previous,
            in: "single line",
            selectedRange: NSRange(location: 6, length: 0)
        ))
        #expect(IRCComposerHistoryCaretPolicy.canNavigate(
            .next,
            in: "single line",
            selectedRange: NSRange(location: 6, length: 0)
        ))
    }

    @Test("Conversation composer stops at the target's UTF-8 message budget")
    @MainActor
    func boundsConversationComposerDrafts() throws {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let conversation = try #require(state.selection)
        let maximumBytes = try #require(state.maximumMessageBytes(for: conversation))
        #expect(maximumBytes > 400)
        let fittingDraft = String(repeating: "a", count: maximumBytes)

        #expect(state.boundedComposerDraft(fittingDraft, for: conversation) == fittingDraft)
        #expect(state.boundedComposerDraft(fittingDraft + "b", for: conversation) == fittingDraft)
        #expect(state.boundedComposerDraft("/" + fittingDraft + "b", for: conversation)
            == "/" + fittingDraft + "b")
        #expect(!state.send(fittingDraft + "b", to: conversation))
    }

    @Test("Selection history navigates backward, forward, and clears forward branches")
    @MainActor
    func navigatesSelectionHistory() {
        let state = IRCAppState()
        let profile = state.profiles[0]

        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = state.selection
        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        let bob = state.selection

        #expect(state.canNavigateBack)
        #expect(!state.canNavigateForward)

        state.navigateBack()
        #expect(state.selection == alice)
        #expect(state.workspaceFocusRequest?.target == alice.map(IRCWorkspaceFocus.composer))
        #expect(state.canNavigateForward)

        state.navigateBack()
        #expect(state.selection == .connectionCenter)

        state.navigateForward()
        #expect(state.selection == alice)
        state.navigateForward()
        #expect(state.selection == bob)

        state.navigateBack()
        state.selection = .connectionCenter
        #expect(!state.canNavigateForward)
    }

    @Test("Jump palette selection requests composer focus")
    @MainActor
    func focusesComposerAfterJumping() throws {
        let state = IRCAppState()
        let profile = state.profiles[0]
        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.selection)
        state.presentJumpPalette()

        state.jump(to: IRCJumpDestination(
            selection: alice,
            title: "Alice",
            serverName: profile.name,
            kind: .directMessage
        ))

        #expect(state.selection == alice)
        #expect(!state.isJumpPalettePresented)
        #expect(state.workspaceFocusRequest == nil)

        state.jumpPaletteDidDismiss()
        #expect(state.workspaceFocusRequest?.target == .composer(alice))
    }

    @Test("History shortcuts recognize Logitech command-arrow and auxiliary mouse events")
    func recognizesHistoryNavigationInput() {
        #expect(IRCHistoryNavigationShortcut.direction(
            keyCode: 123,
            charactersIgnoringModifiers: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        ) == .back)
        #expect(IRCHistoryNavigationShortcut.direction(
            keyCode: 124,
            charactersIgnoringModifiers: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        ) == .forward)
        #expect(IRCHistoryNavigationShortcut.direction(
            keyCode: 33,
            charactersIgnoringModifiers: "["
        ) == .back)
        #expect(IRCHistoryNavigationShortcut.direction(
            keyCode: 30,
            charactersIgnoringModifiers: "]"
        ) == .forward)
        #expect(IRCHistoryNavigationShortcut.direction(mouseButtonNumber: 3) == .back)
        #expect(IRCHistoryNavigationShortcut.direction(mouseButtonNumber: 4) == .forward)
        #expect(IRCHistoryNavigationShortcut.direction(mouseButtonNumber: 2) == nil)
    }

    @Test("Composer nickname completion targets the final word of a chat message")
    func completesNicknameInChatMessages() throws {
        let singleWordInput = "ali"
        let singleWord = try #require(IRCComposerCompletion.recipientContext(in: singleWordInput))
        #expect(singleWord.command == nil)
        #expect(singleWord.prefix == "ali")
        #expect(String(singleWordInput[singleWord.range]) == "ali")

        let sentenceInput = "hello there bo"
        let sentence = try #require(IRCComposerCompletion.recipientContext(in: sentenceInput))
        #expect(sentence.command == nil)
        #expect(sentence.prefix == "bo")
        #expect(String(sentenceInput[sentence.range]) == "bo")

        let afterSpace = try #require(IRCComposerCompletion.recipientContext(in: "hello "))
        #expect(afterSpace.prefix.isEmpty)
        #expect(afterSpace.range.isEmpty)

        #expect(IRCComposerCompletion.recipientContext(in: "") == nil)
    }

    @Test("Composer nickname completion preserves command recipient contexts")
    func completesNicknameInCommandRecipients() throws {
        let messageInput = "/msg ali"
        let message = try #require(IRCComposerCompletion.recipientContext(in: messageInput))
        #expect(message.command == "MSG")
        #expect(message.prefix == "ali")
        #expect(String(messageInput[message.range]) == "ali")

        #expect(IRCComposerCompletion.recipientContext(in: "/join #swift") == nil)
    }

    @Test("Selection history skips conversations after they close")
    @MainActor
    func skipsClosedHistoryItems() {
        let state = IRCAppState()
        let profile = state.profiles[0]

        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = state.selection
        state.startDirectMessage(with: "Bob", from: .server(profile.id))
        guard let bob = state.directMessages.first(where: { $0.name == "Bob" }) else {
            Issue.record("Expected Bob direct message")
            return
        }

        state.close(bob)
        state.navigateBack()

        #expect(state.selection == alice)
    }

    @Test("Server selection restores the last open conversation on each server")
    @MainActor
    func restoresLastConversationForServerShortcuts() throws {
        let state = IRCAppState()
        let firstProfile = state.profiles[0]
        let secondProfile = state.profiles[1]

        state.startDirectMessage(with: "Alice", from: .server(firstProfile.id))
        let alice = try #require(state.selection)
        state.startDirectMessage(with: "Bob", from: .server(secondProfile.id))
        let bob = try #require(state.selection)

        state.selectServerRestoringLastConversation(firstProfile)
        #expect(state.selection == alice)
        #expect(state.workspaceFocusRequest?.target == .composer(alice))
        state.selectServerRestoringLastConversation(secondProfile)
        #expect(state.selection == bob)
        #expect(state.workspaceFocusRequest?.target == .composer(bob))
    }

    @Test("Connections selection preserves each server's remembered conversation")
    @MainActor
    func opensConnectionsWithoutForgettingConversation() throws {
        let state = IRCAppState()
        let profile = state.profiles[0]

        state.startDirectMessage(with: "Alice", from: .server(profile.id))
        let alice = try #require(state.selection)

        state.showConnections()
        #expect(state.selection == .connectionCenter)

        state.selectServerRestoringLastConversation(profile)
        #expect(state.selection == alice)
    }

    @Test("Jump search supports partial, fuzzy, and cross-field matches")
    func matchesJumpDestinations() {
        let libera = UUID()
        let snoonet = UUID()
        let destinations = [
            IRCJumpDestination(
                selection: .server(libera),
                title: "Libera.Chat",
                serverName: "Libera.Chat",
                kind: .server
            ),
            IRCJumpDestination(
                selection: .channel(UUID()),
                title: "#general",
                serverName: "Libera.Chat",
                kind: .channel
            ),
            IRCJumpDestination(
                selection: .channel(UUID()),
                title: "#development",
                serverName: "Snoonet",
                kind: .channel
            ),
            IRCJumpDestination(
                selection: .directMessage(snoonet),
                title: "Élodie",
                serverName: "Snoonet",
                kind: .directMessage
            )
        ]

        #expect(IRCJumpSearch.results(in: destinations, matching: "lib gen").map(\.title) == ["#general"])
        #expect(IRCJumpSearch.results(in: destinations, matching: "dvlp").map(\.title) == ["#development"])
        #expect(IRCJumpSearch.results(in: destinations, matching: "elodie").map(\.title) == ["Élodie"])
        #expect(IRCJumpSearch.results(in: destinations, matching: "libera").first?.title == "Libera.Chat")
    }

    private func link(
        for substring: String,
        occurrence: Int,
        in attributedText: AttributedString
    ) throws -> URL? {
        let text = String(attributedText.characters)
        var searchStart = text.startIndex
        var match: Range<String.Index>?
        for _ in 0...occurrence {
            match = text.range(of: substring, range: searchStart..<text.endIndex)
            let found = try #require(match)
            searchStart = found.upperBound
        }
        let stringRange = try #require(match)
        let attributedRange = try #require(Range(stringRange, in: attributedText))
        return attributedText[attributedRange].link
    }

    @MainActor
    private static func composer(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView,
           textView.identifier?.rawValue == "IRCComposerTextView" {
            return textView
        }
        for subview in view.subviews {
            if let composer = composer(in: subview) {
                return composer
            }
        }
        return nil
    }

    private static func keyEvent(
        keyCode: UInt16,
        characters: String? = nil
    ) -> NSEvent? {
        let characters = characters ?? String(
            Character(UnicodeScalar(keyCode == 126 ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)
        )
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private static func view(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = Self.view(withIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private static func views(withIdentifier identifier: String, in view: NSView) -> [NSView] {
        var matches = view.identifier?.rawValue == identifier ? [view] : []
        for subview in view.subviews {
            matches.append(contentsOf: Self.views(withIdentifier: identifier, in: subview))
        }
        return matches
    }

    private func attributes(
        for substring: String,
        in attributedText: AttributedString
    ) throws -> AttributeContainer {
        let text = String(attributedText.characters)
        let stringRange = try #require(text.range(of: substring))
        let attributedRange = try #require(Range(stringRange, in: attributedText))
        return attributedText[attributedRange].runs.first?.attributes ?? AttributeContainer()
    }
}

private struct TranscriptTestStatefulRow: View {
    let messageID: UUID
    let onRender: (UUID, UUID) -> Void
    @State private var stateOwnerMessageID: UUID

    init(
        messageID: UUID,
        onRender: @escaping (UUID, UUID) -> Void
    ) {
        self.messageID = messageID
        self.onRender = onRender
        _stateOwnerMessageID = State(initialValue: messageID)
    }

    var body: some View {
        TranscriptTestStateReporter(
            messageID: messageID,
            stateOwnerMessageID: stateOwnerMessageID,
            onRender: onRender
        )
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
    }
}

@MainActor
private final class TranscriptPreviewLifecycleProbe {
    var taskStarts = 0
    var completions = 0
}

private struct TranscriptPreviewLifecycleTestRow: View {
    let probe: TranscriptPreviewLifecycleProbe
    @State private var isLoaded = false

    var body: some View {
        Color.clear
            .frame(
                maxWidth: .infinity,
                minHeight: isLoaded ? 96 : 72,
                maxHeight: isLoaded ? 96 : 72
            )
            .task {
                probe.taskStarts += 1
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                isLoaded = true
                probe.completions += 1
            }
    }
}

private struct PreviewExpansionObservationTestRow: View {
    let messageID: UUID
    let selection: SidebarItem
    @ObservedObject var expansion: IRCMessagePreviewExpansionStore
    let onRender: (Bool) -> Void

    var body: some View {
        PreviewExpansionTestReporter(
            isExpanded: expansion.isExpanded(for: messageID, in: selection),
            onRender: onRender
        )
    }
}

private struct PreviewExpansionTestReporter: NSViewRepresentable {
    let isExpanded: Bool
    let onRender: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        onRender(isExpanded)
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onRender(isExpanded)
    }
}

private struct PreviewExpansionHeightTestTranscript: View {
    let messages: [IRCMessage]
    let targetMessageID: UUID
    let selection: SidebarItem
    @ObservedObject var expansion: IRCMessagePreviewExpansionStore
    let onInitialPositioned: () -> Void

    var body: some View {
        let rowLayoutInvalidation: IRCTranscriptRowLayoutInvalidation? =
            expansion.latestLayoutChange.flatMap { change in
            guard change.selection == selection else { return nil }
            return IRCTranscriptRowLayoutInvalidation(
                messageID: change.messageID,
                revision: change.revision
            )
        }
        IRCTranscriptTable(
            contentIdentity: selection,
            messages: messages,
            estimatedRowHeight: 24,
            rowSpacing: 0,
            renderConfiguration: "preview-height-test",
            rowLayoutInvalidation: rowLayoutInvalidation,
            makeRow: { message in
                AnyView(
                    PreviewExpansionHeightTestRow(
                        messageID: message.id,
                        targetMessageID: targetMessageID,
                        selection: selection,
                        expansion: expansion
                    )
                )
            },
            onInitialPositioned: { _ in onInitialPositioned() },
            onFollowingTailChange: { _, _ in },
            onTailPositioned: { _, _ in },
            onGeometryChange: { _, _ in }
        )
    }
}

private struct PreviewExpansionHeightTestRow: View {
    let messageID: UUID
    let targetMessageID: UUID
    let selection: SidebarItem
    @ObservedObject var expansion: IRCMessagePreviewExpansionStore

    var body: some View {
        let isExpanded = expansion.isExpanded(
            for: messageID,
            in: selection
        )
        Color.clear
            .frame(
                maxWidth: .infinity,
                minHeight: messageID == targetMessageID && isExpanded ? 120 : 30,
                maxHeight: messageID == targetMessageID && isExpanded ? 120 : 30
            )
    }
}

private struct TranscriptTestStateReporter: NSViewRepresentable {
    let messageID: UUID
    let stateOwnerMessageID: UUID
    let onRender: (UUID, UUID) -> Void

    func makeNSView(context: Context) -> NSView {
        onRender(messageID, stateOwnerMessageID)
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onRender(messageID, stateOwnerMessageID)
    }
}
