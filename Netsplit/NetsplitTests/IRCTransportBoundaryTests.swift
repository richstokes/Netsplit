import Foundation
import Testing
@testable import Netsplit

@Suite("IRC transport boundaries")
struct IRCTransportBoundaryTests {
    @Test("Reassembles a line when both content and CRLF cross packet boundaries")
    func reassemblesFragmentedLine() {
        var buffer = IRCLineBuffer(maximumLineBytes: 510)

        #expect(buffer.append(Data("PING :to".utf8)).lines.isEmpty)
        #expect(buffer.append(Data("ken\r".utf8)).lines.isEmpty)
        let output = buffer.append(Data("\n".utf8))

        #expect(output.lines == ["PING :token"])
        #expect(!output.exceededMaximumLineLength)
    }

    @Test("Emits multiple complete lines while retaining a partial tail")
    func handlesCoalescedLinesAndPartialTail() {
        var buffer = IRCLineBuffer(maximumLineBytes: 510)
        let first = buffer.append(Data("001 nick :welcome\r\nPING :one\r\nNOTICE".utf8))
        let second = buffer.append(Data(" nick :later\r\n".utf8))

        #expect(first.lines == ["001 nick :welcome", "PING :one"])
        #expect(second.lines == ["NOTICE nick :later"])
    }

    @Test("Preserves empty protocol lines and replaces invalid UTF-8 bytes")
    func handlesEmptyAndLegacyEncodedLines() {
        var buffer = IRCLineBuffer(maximumLineBytes: 510)
        var bytes = Data("\r\nPRIVMSG #swift :".utf8)
        bytes.append(0xFF)
        bytes.append(contentsOf: [13, 10])

        let output = buffer.append(bytes)
        #expect(output.lines.count == 2)
        #expect(output.lines[0].isEmpty)
        #expect(output.lines[1] == "PRIVMSG #swift :�")
    }

    @Test("Accepts the exact line limit and rejects the next byte")
    func enforcesUnterminatedLineLimit() {
        var buffer = IRCLineBuffer(maximumLineBytes: 5)
        #expect(!buffer.append(Data("12345".utf8)).exceededMaximumLineLength)
        #expect(buffer.append(Data("6".utf8)).exceededMaximumLineLength)
    }

    @Test("Rejects an oversized terminated line without exposing it to the parser")
    func rejectsOversizedTerminatedLine() {
        var buffer = IRCLineBuffer(maximumLineBytes: 5)
        let output = buffer.append(Data("123456\r\n".utf8))

        #expect(output.lines.isEmpty)
        #expect(output.exceededMaximumLineLength)
    }

    @Test("Delivers valid lines that arrived before an oversized line")
    func preservesValidLinesBeforeFailure() {
        var buffer = IRCLineBuffer(maximumLineBytes: 5)
        let output = buffer.append(Data("OK\r\n123456\r\n".utf8))

        #expect(output.lines == ["OK"])
        #expect(output.exceededMaximumLineLength)
    }

    @Test("Graceful QUIT waits after a successful local write")
    func gracefulQuitWaitsForPeerClose() {
        #expect(IRCGracefulQuitPolicy.timeout(after: .started) == 2)
        #expect(IRCGracefulQuitPolicy.timeout(after: .localWriteSucceeded) == 0.5)
        #expect(IRCGracefulQuitPolicy.timeout(after: .localWriteFailed) == nil)
        #expect(!IRCGracefulQuitPolicy.shouldFinish(after: .started))
        #expect(!IRCGracefulQuitPolicy.shouldFinish(after: .localWriteSucceeded))
        #expect(IRCGracefulQuitPolicy.shouldFinish(after: .localWriteFailed))
        #expect(IRCGracefulQuitPolicy.shouldFinish(after: .peerClosed))
        #expect(IRCGracefulQuitPolicy.shouldFinish(after: .timedOut))
    }

    @Test("SSH host-key pinning rejects a malformed saved identity")
    func rejectsMalformedPinnedSSHHostKey() {
        #expect(throws: SSHTunnelError.self) {
            _ = try PinnedSSHHostKeyValidator(
                trustedKey: "not-an-openssh-public-key",
                onFirstSeen: { _ in }
            )
        }
    }
}
