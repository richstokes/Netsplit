import AppKit
import Foundation
import Testing
@testable import Netsplit

@Suite("IRC models and state policies")
struct IRCModelsAndPolicyTests {
    @Test("Application themes expose the expected light and dark variants")
    func exposesApplicationThemes() {
        #expect(IRCApplicationAppearance.allCases.count == 7)
        #expect(IRCApplicationAppearance.catppuccinLatte.colorScheme == .light)
        #expect(IRCApplicationAppearance.catppuccinMocha.colorScheme == .dark)
        #expect(IRCApplicationAppearance.githubLight.colorScheme == .light)
        #expect(IRCApplicationAppearance.githubDark.colorScheme == .dark)
        #expect(IRCApplicationAppearance.catppuccinLatte.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.catppuccinMocha.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.githubLight.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.githubDark.palette?.nicknameColors.count == 8)
        #expect(IRCApplicationAppearance.system.palette == nil)
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

    @Test("System wake restores only active or already-reconnecting sessions")
    func selectsConnectionsToRestoreAfterSleep() {
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .online, reconnectWasScheduled: false))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .connecting, reconnectWasScheduled: false))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .failed("offline"), reconnectWasScheduled: true))
        #expect(IRCSystemSleepPolicy.shouldRestoreConnection(status: .offline, reconnectWasScheduled: true))
        #expect(!IRCSystemSleepPolicy.shouldRestoreConnection(status: .failed("bad credentials"), reconnectWasScheduled: false))
        #expect(!IRCSystemSleepPolicy.shouldRestoreConnection(status: .offline, reconnectWasScheduled: false))
    }

    @Test("Nickname validation accepts IRC-safe names and rejects malformed identities")
    func validatesNicknames() {
        for nickname in ["Netsplit_User", "[Netsplit]", "rich-stokes", "Ålice42"] {
            #expect(IRCIdentityValidation.nicknameError(nickname) == nil, "Nickname: \(nickname)")
        }
        for nickname in ["", " nick", "nick ", "nick name", "1nickname", "nick!user", "nick\nOPER"] {
            #expect(IRCIdentityValidation.nicknameError(nickname) != nil, "Nickname: \(nickname)")
        }
    }

    @Test("Case mappings implement the network-advertised RFC variants")
    func normalizesIdentifiers() {
        #expect(IRCCaseMapping.ascii.normalize("[Nick]\\^") == "[nick]\\^")
        #expect(IRCCaseMapping.strictRFC1459.normalize("[Nick]\\^") == "{nick}|^")
        #expect(IRCCaseMapping.rfc1459.normalize("[Nick]\\^") == "{nick}|~")
        #expect(IRCCaseMapping.rfc1459.normalize("ÅLICE 👋") == "Ålice 👋")
        #expect(IRCCaseMapping.rfc1459.normalize("").isEmpty)
    }

    @Test("Mute snapshots normalize once and honor the server case mapping")
    func matchesMutedNicknames() {
        let rfcSnapshot = IRCMuteSnapshot(nicknames: ["[Nick]", "Alice"], caseMapping: .rfc1459)
        #expect(rfcSnapshot.contains("{nick}"))
        #expect(rfcSnapshot.contains("ALICE"))
        #expect(!rfcSnapshot.contains("Bob"))

        let asciiSnapshot = IRCMuteSnapshot(nicknames: ["[Nick]"], caseMapping: .ascii)
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

    @Test("WHOIS channel lists preserve channels and remove membership prefixes")
    func parsesWhoisChannels() {
        let channels = IRCWhoisChannelParser.channels(
            from: "@#operators +#voiced #general &local +modeless not-a-channel #general"
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
            "MODES=6"
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

        features.apply(parameters: [
            "-CASEMAPPING", "-PREFIX", "-CHANMODES", "-CHANTYPES",
            "-STATUSMSG", "-NETWORK", "-NICKLEN", "-CHANNELLEN", "-MODES"
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
    }

    @Test("Normalizes capability modifiers and advertised values")
    func parsesCapabilityNames() {
        #expect(IRCCapability.name(from: "sasl=PLAIN,EXTERNAL") == "sasl")
        #expect(IRCCapability.name(from: "-echo-message") == "echo-message")
        #expect(IRCCapability.name(from: "server-time") == "server-time")
        #expect(IRCCapability.preferred == [
            "message-tags",
            "server-time",
            "multi-prefix",
            "userhost-in-names",
            "chghost",
            "echo-message"
        ])
        #expect(!IRCCapability.preferred.contains("batch"))
        #expect(!IRCCapability.preferred.contains("labeled-response"))
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
            .link(URL(string: "https://swift.org")!)
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

    @Test("Chat typography keeps the system face as the first default choice")
    func exposesChatFonts() {
        #expect(IRCChatFont.allCases == [.system, .rounded, .monospaced])
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
            text: "Alice is on: @#operators +#voiced",
            isSystem: true,
            channelLinks: ["#operators", "#voiced"]
        )
        let rendered = IRCMessageTextRenderer.linkifiedText(for: message)

        #expect(try link(for: "#operators", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#operators")
        #expect(try link(for: "#voiced", occurrence: 0, in: rendered).flatMap(IRCInternalLink.channelName(from:)) == "#voiced")
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

        try await Task.sleep(for: .milliseconds(100))
        #expect(signal.revision == 2)

        signal.advance()
        #expect(signal.revision == 2)

        try await Task.sleep(for: .milliseconds(100))
        #expect(signal.revision == 3)

        try await Task.sleep(for: .milliseconds(80))
        signal.advance()
        #expect(signal.revision == 4)
    }

    @Test("Transcript presentation expands retained history in bounded pages")
    func expandsTranscriptPresentationInPages() {
        let initial = IRCTranscriptPresentationPolicy.initialVisibleMessageLimit
        let pageSize = IRCTranscriptPresentationPolicy.earlierMessagePageSize

        #expect(initial < IRCConversationHistory.retentionLimit)
        #expect(pageSize > 0)
        #expect(IRCTranscriptPresentationPolicy.expandedVisibleMessageLimit(
            current: initial,
            total: IRCConversationHistory.retentionLimit
        ) == initial + pageSize)
        #expect(IRCTranscriptPresentationPolicy.expandedVisibleMessageLimit(
            current: IRCConversationHistory.retentionLimit - 100,
            total: IRCConversationHistory.retentionLimit
        ) == IRCConversationHistory.retentionLimit)
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

    @Test("Sidebar channel selection requests composer focus, including reselection")
    @MainActor
    func focusesComposerForSidebarChannelSelection() throws {
        let state = IRCAppState()
        let firstChannel = SidebarItem.channel(UUID())
        let secondChannel = SidebarItem.channel(UUID())

        state.selectFromSidebar(firstChannel)
        let firstRequest = try #require(state.workspaceFocusRequest)
        #expect(state.selection == firstChannel)
        #expect(firstRequest.target == .composer(firstChannel))

        state.selectFromSidebar(secondChannel)
        let secondRequest = try #require(state.workspaceFocusRequest)
        #expect(state.selection == secondChannel)
        #expect(secondRequest.target == .composer(secondChannel))
        #expect(secondRequest.id != firstRequest.id)

        state.selectFromSidebar(secondChannel)
        let reselectionRequest = try #require(state.workspaceFocusRequest)
        #expect(reselectionRequest.target == .composer(secondChannel))
        #expect(reselectionRequest.id != secondRequest.id)
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
        state.selectServerRestoringLastConversation(secondProfile)
        #expect(state.selection == bob)
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
