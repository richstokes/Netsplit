import Foundation
import Testing
@testable import Netsplit

@Suite("IRC models and state policies")
struct IRCModelsAndPolicyTests {
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
}
