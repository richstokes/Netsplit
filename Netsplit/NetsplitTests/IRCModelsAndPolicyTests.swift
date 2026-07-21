import AppKit
import Foundation
import Testing
@testable import Netsplit

@Suite("IRC models and state policies")
struct IRCModelsAndPolicyTests {
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

    @Test("WHOIS channel lists preserve channels and remove membership prefixes")
    func parsesWhoisChannels() {
        let channels = IRCWhoisChannelParser.channels(
            from: "@#operators +#voiced #general &local +modeless not-a-channel #general"
        )
        #expect(channels == ["#operators", "#voiced", "#general", "&local", "+modeless"])
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

        member.modes.remove("o")
        #expect(member.prefix == "+")
        #expect(member.role == "Voice")

        member.modes.formUnion(["a", "q"])
        #expect(member.prefix == "~")
        #expect(member.role == "Owner")
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

    @Test("Normalizes capability modifiers and advertised values")
    func parsesCapabilityNames() {
        #expect(IRCCapability.name(from: "sasl=PLAIN,EXTERNAL") == "sasl")
        #expect(IRCCapability.name(from: "-echo-message") == "echo-message")
        #expect(IRCCapability.name(from: "server-time") == "server-time")
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
        let notice = IRCMessage(sender: "Alice (notice)", text: "Hello", nicknameColorKey: "Alice")

        #expect(ordinary.resolvedNicknameColorKey == "Alice")
        #expect(action.resolvedNicknameColorKey == ordinary.resolvedNicknameColorKey)
        #expect(notice.resolvedNicknameColorKey == ordinary.resolvedNicknameColorKey)
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

    @Test("Member list shortcut only applies to channels")
    @MainActor
    func ignoresMemberListToggleOutsideChannels() {
        let state = IRCAppState()
        let initialValue = state.showsMemberList

        #expect(!state.canToggleMemberList)
        state.toggleMemberList()
        #expect(state.showsMemberList == initialValue)
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
