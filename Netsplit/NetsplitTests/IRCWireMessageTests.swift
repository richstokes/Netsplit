import Testing
@testable import Netsplit

@Suite("IRC wire message parsing")
struct IRCWireMessageTests {
    @Test("Parses tags, prefix, parameters, and trailing text")
    func parsesCompleteMessage() throws {
        let message = try #require(IRCWireMessage(
            line: "@time=2026-07-17T20:00:00.000Z;example=hello\\sworld :nick!user@example PRIVMSG #swift :hello there"
        ))

        #expect(message.tags["time"] ?? nil == "2026-07-17T20:00:00.000Z")
        #expect(message.tags["example"] ?? nil == "hello world")
        #expect(message.prefix == "nick!user@example")
        #expect(message.command == "PRIVMSG")
        #expect(message.parameters == ["#swift"])
        #expect(message.trailing == "hello there")
    }

    @Test("Unescapes every IRCv3 tag escape without altering trailing text")
    func unescapesTagValues() throws {
        let message = try #require(IRCWireMessage(
            line: "@escaped=semi\\:space\\sbackslash\\\\return\\rnewline\\n;flag PING :token:with:colons"
        ))

        #expect(message.tags["escaped"] ?? nil == "semi;space backslash\\return\rnewline\n")
        #expect(message.tags.keys.contains("flag"))
        #expect(message.tags["flag"] == .some(nil))
        #expect(message.trailing == "token:with:colons")
    }

    @Test("Drops a dangling tag escape and preserves unknown escaped characters")
    func handlesEdgeCaseTagEscapes() throws {
        let message = try #require(IRCWireMessage(
            line: "@dangling=value\\;unknown=keep\\q PING :token"
        ))

        #expect(message.tags["dangling"] ?? nil == "value")
        #expect(message.tags["unknown"] ?? nil == "keepq")
    }

    @Test("Recognizes both wire forms of a SASL continuation")
    func recognizesSASLContinuations() throws {
        let middle = try #require(IRCWireMessage(line: "AUTHENTICATE +"))
        let trailing = try #require(IRCWireMessage(line: "AUTHENTICATE :+"))
        let unrelated = try #require(IRCWireMessage(line: "PRIVMSG #swift :+"))

        #expect(middle.isSASLContinuation)
        #expect(trailing.isSASLContinuation)
        #expect(!unrelated.isSASLContinuation)
    }

    @Test("Normalizes commands and preserves ordinary parameters")
    func parsesCommandWithoutPrefix() throws {
        let message = try #require(IRCWireMessage(line: "mode #swift +ov Alice Bob"))

        #expect(message.command == "MODE")
        #expect(message.parameters == ["#swift", "+ov", "Alice", "Bob"])
        #expect(message.trailing == nil)
    }

    @Test("Rejects incomplete wire lines")
    func rejectsIncompleteLines() {
        #expect(IRCWireMessage(line: "") == nil)
        #expect(IRCWireMessage(line: "   ") == nil)
        #expect(IRCWireMessage(line: ":server-only") == nil)
        #expect(IRCWireMessage(line: "@tag-only") == nil)
    }
}
