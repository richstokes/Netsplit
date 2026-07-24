import Foundation
import Testing
@testable import Netsplit

@Suite("IRC outbound framing and commands")
struct IRCFramingAndCommandTests {
    @Test("Legacy on-connect command lists migrate to the pre-join phase")
    func migratesLegacyOnConnectCommands() throws {
        let legacy = Data(#"["/identify secret","MODE Alice +i"]"#.utf8)
        let phases = try JSONDecoder().decode(IRCOnConnectCommandPhases.self, from: legacy)

        #expect(phases.beforeFavoritesJoined == ["/identify secret", "MODE Alice +i"])
        #expect(phases.afterFavoritesJoined.isEmpty)
    }

    @Test("On-connect command phases round-trip and discard blank entries")
    func roundTripsOnConnectCommandPhases() throws {
        let phases = IRCOnConnectCommandPhases(
            beforeFavoritesJoined: ["  /identify secret  ", "   "],
            afterFavoritesJoined: ["/chanserv op #swift Alice", "\n"]
        ).removingBlankCommands

        #expect(phases.beforeFavoritesJoined == ["/identify secret"])
        #expect(phases.afterFavoritesJoined == ["/chanserv op #swift Alice"])

        let decoded = try JSONDecoder().decode(
            IRCOnConnectCommandPhases.self,
            from: JSONEncoder().encode(phases)
        )
        #expect(decoded == phases)
    }

    @Test("Post-join tracking uses the server's current case mapping")
    func tracksOnConnectJoinsAcrossCaseMappingUpdates() {
        var tracker = IRCOnConnectJoinTracker(channelNames: ["#^Ops", "#Swift"])

        tracker.complete("#^ops", caseMapping: .strictRFC1459)
        #expect(tracker.pendingChannelNames == ["#Swift"])

        tracker.complete("#SWIFT", caseMapping: .ascii)
        #expect(tracker.isComplete)
    }

    @Test("Parses one-off servers with inferred TLS and explicit overrides")
    func parsesOneOffServers() throws {
        let defaultEndpoint = try IRCOneOffServerCommand.endpoint(from: "irc.libera.chat").get()
        #expect(defaultEndpoint == IRCOneOffServerEndpoint(
            hostname: "irc.libera.chat",
            port: 6697,
            useTLS: true
        ))

        let inferredTLS = try IRCOneOffServerCommand.endpoint(from: "irc.libera.chat 6697").get()
        #expect(inferredTLS.useTLS)

        let inferredPlaintext = try IRCOneOffServerCommand.endpoint(from: "irc.example.com 6667").get()
        #expect(!inferredPlaintext.useTLS)

        let forcedTLS = try IRCOneOffServerCommand.endpoint(from: "--tls irc.example.com 7000").get()
        #expect(forcedTLS.port == 7000)
        #expect(forcedTLS.useTLS)

        let forcedPlaintext = try IRCOneOffServerCommand.endpoint(from: "irc.example.com --no-tls").get()
        #expect(forcedPlaintext.port == 6667)
        #expect(!forcedPlaintext.useTLS)
    }

    @Test("Rejects malformed one-off server commands")
    func rejectsMalformedOneOffServers() {
        let invalidArguments = [
            "",
            "irc.example.com 0",
            "irc.example.com 65536",
            "irc.example.com not-a-port",
            "irc.example.com 6697 extra",
            "irc.example.com --tls --no-tls",
            "irc.example.com --unknown"
        ]

        for argument in invalidArguments {
            if case .success = IRCOneOffServerCommand.endpoint(from: argument) {
                Issue.record("Expected invalid /server arguments: \(argument)")
            }
        }
    }

    @Test("Builds CTCP VERSION replies from the app marketing version")
    func buildsClientVersionReply() throws {
        #expect(IRCClientVersion.ctcpReply(infoDictionary: [
            "CFBundleShortVersionString": "9.8.7"
        ]) == "Netsplit 9.8.7 for macOS - https://github.com/richstokes/Netsplit")

        let bundledVersion = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        #expect(
            IRCClientVersion.ctcpReply
                == "Netsplit \(bundledVersion) for macOS - https://github.com/richstokes/Netsplit"
        )
    }

    @Test("Builds CTCP PING payloads and measures round-trip time")
    func buildsUserPing() {
        #expect(IRCCTCPPing.payload(token: "ping-token") == "\u{01}PING ping-token\u{01}")
        #expect(IRCCTCPPing.roundTripMilliseconds(
            sentAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 100.1234)
        ) == 123)
        #expect(IRCCTCPPing.roundTripMilliseconds(
            sentAt: Date(timeIntervalSince1970: 101),
            receivedAt: Date(timeIntervalSince1970: 100)
        ) == 0)
    }

    @Test("Suppresses echoed CTCP requests from the local nickname")
    func suppressesSelfCTCPEchoes() {
        #expect(IRCCTCPEchoPolicy.isSelfEcho(
            sender: "DBR",
            localNickname: "dbr",
            caseMapping: .rfc1459,
            canReplyToRequest: true
        ))
        #expect(!IRCCTCPEchoPolicy.isSelfEcho(
            sender: "Alice",
            localNickname: "dbr",
            caseMapping: .rfc1459,
            canReplyToRequest: true
        ))
        #expect(!IRCCTCPEchoPolicy.isSelfEcho(
            sender: "dbr",
            localNickname: "dbr",
            caseMapping: .rfc1459,
            canReplyToRequest: false
        ))
    }

    @Test("Removes CR/LF command injection and enforces the IRC byte limit")
    func sanitizesAndBoundsCommands() {
        let sanitized = IRCTextFraming.sanitizedSingleLine("PRIVMSG #swift :hello\r\nOPER attacker")
        #expect(sanitized == "PRIVMSG #swift :hello  OPER attacker")
        #expect(!sanitized.contains("\r"))
        #expect(!sanitized.contains("\n"))

        let bounded = IRCTextFraming.prefix(String(repeating: "é", count: 300))
        #expect(bounded.utf8.count == 510)
        #expect(bounded.count == 255)
    }

    @Test("Splits long Unicode messages into complete, reconstructable wire-safe chunks")
    func chunksUnicodeMessages() {
        let prefix = "PRIVMSG #swift :"
        let text = String(repeating: "Swift 🦉 ", count: 100)
        let chunks = IRCTextFraming.messageChunks(text, commandPrefix: prefix)

        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { (prefix + $0).utf8.count <= IRCTextFraming.maximumLineBytes })
    }

    @Test("Honors logical lines and CTCP suffix overhead")
    func chunksActionsAndLogicalLines() {
        let prefix = "PRIVMSG #swift :\u{01}ACTION "
        let suffix = "\u{01}"
        let chunks = IRCTextFraming.messageChunks("first\r\nsecond\rthird", commandPrefix: prefix, suffix: suffix)

        #expect(chunks == ["first", "second", "third"])
        #expect(chunks.allSatisfy { (prefix + $0 + suffix).utf8.count <= IRCTextFraming.maximumLineBytes })
        #expect(IRCTextFraming.messageChunks("message", commandPrefix: String(repeating: "x", count: 510)).isEmpty)
    }

    @Test("Translates user-friendly on-connect commands to IRC wire commands")
    func translatesOnConnectCommands() {
        let cases: [(String, String?)] = [
            ("  PRIVMSG NickServ :STATUS  ", "PRIVMSG NickServ :STATUS"),
            ("/msg Alice hello there", "PRIVMSG Alice :hello there"),
            ("/query Alice hello there", "PRIVMSG Alice :hello there"),
            ("/notice #swift deployment soon", "NOTICE #swift :deployment soon"),
            ("/ns identify secret", "PRIVMSG NickServ :identify secret"),
            ("/chanserv op #swift Alice", "PRIVMSG ChanServ :op #swift Alice"),
            ("/identify secret", "PRIVMSG NickServ :IDENTIFY secret"),
            ("/raw MODE #swift +i", "MODE #swift +i"),
            ("/join swift", "JOIN #swift"),
            ("/join &staff key", "JOIN &staff key"),
            ("/away lunch", "AWAY lunch"),
            ("/away", "AWAY"),
            ("", nil),
            ("/msg Alice", nil),
            ("/join", nil),
            ("/raw", nil)
        ]

        for (input, expected) in cases {
            #expect(IRCCommandTranslator.onConnectWireCommand(from: input) == expected, "Input: \(input)")
        }

        #expect(IRCCommandTranslator.onConnectWireCommand(
            from: "/join staff",
            channelTypes: ["$"],
            preferredChannelPrefix: "$"
        ) == "JOIN $staff")
        #expect(IRCCommandTranslator.onConnectWireCommand(
            from: "/join $staff",
            channelTypes: ["$"],
            preferredChannelPrefix: "$"
        ) == "JOIN $staff")
    }

    @Test("Builds SASL PLAIN payloads and emits the required terminal chunk")
    func buildsSASLPlainChunks() throws {
        let chunks = IRCSASL.plainAuthenticationChunks(username: "alice", password: "pässword")
        let encoded = chunks.filter { $0 != "+" }.joined()
        let decoded = try #require(Data(base64Encoded: encoded))
        let expected = Data([0] + Array("alice".utf8) + [0] + Array("pässword".utf8))

        #expect(decoded == expected)
        #expect(chunks.allSatisfy { $0 == "+" || $0.count <= 400 })

        let exactBoundary = IRCSASL.plainAuthenticationChunks(
            username: "u",
            password: String(repeating: "p", count: 295)
        )
        #expect(exactBoundary.count == 2)
        #expect(exactBoundary[0].count == 400)
        #expect(exactBoundary[1] == "+")
    }
}
