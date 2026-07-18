import XCTest
@testable import Netsplit

final class IRCParsingTests: XCTestCase {
    func testNicknameValidationRejectsUnsafeValues() {
        XCTAssertNotNil(IRCIdentityValidation.nicknameError(""))
        XCTAssertNotNil(IRCIdentityValidation.nicknameError(" nick"))
        XCTAssertNotNil(IRCIdentityValidation.nicknameError("nick name"))
        XCTAssertNotNil(IRCIdentityValidation.nicknameError("1nickname"))
        XCTAssertNotNil(IRCIdentityValidation.nicknameError("nick!user"))
    }

    func testNicknameValidationAcceptsCommonIRCNicknameSymbols() {
        XCTAssertNil(IRCIdentityValidation.nicknameError("Netsplit_User"))
        XCTAssertNil(IRCIdentityValidation.nicknameError("[Netsplit]"))
        XCTAssertNil(IRCIdentityValidation.nicknameError("rich-stokes"))
    }

    func testWireParserHandlesTagsPrefixAndTrailingText() throws {
        let message = try XCTUnwrap(
            IRCWireMessage(line: "@time=2026-07-17T20:00:00.000Z;example=hello\\sworld :nick!user@example PRIVMSG #swift :hello there")
        )

        XCTAssertEqual(message.tags["time"]!, "2026-07-17T20:00:00.000Z")
        XCTAssertEqual(message.tags["example"]!, "hello world")
        XCTAssertEqual(message.prefix, "nick!user@example")
        XCTAssertEqual(message.command, "PRIVMSG")
        XCTAssertEqual(message.parameters, ["#swift"])
        XCTAssertEqual(message.trailing, "hello there")
    }

    func testCaseMappingUsesRFC1459Equivalences() {
        XCTAssertEqual(IRCCaseMapping.rfc1459.normalize("[Nick]\\^"), "{nick}|~")
        XCTAssertNotEqual(IRCCaseMapping.ascii.normalize("[Nick]"), IRCCaseMapping.ascii.normalize("{Nick}"))
    }
}
