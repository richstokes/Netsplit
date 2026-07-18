import Foundation
import Testing
@testable import Netsplit

@Suite("IRC models and state policies")
struct IRCModelsAndPolicyTests {
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

    @Test("Member list shortcut only applies to channels")
    @MainActor
    func ignoresMemberListToggleOutsideChannels() {
        let state = IRCAppState()
        let initialValue = state.showsMemberList

        #expect(!state.canToggleMemberList)
        state.toggleMemberList()
        #expect(state.showsMemberList == initialValue)
    }
}
