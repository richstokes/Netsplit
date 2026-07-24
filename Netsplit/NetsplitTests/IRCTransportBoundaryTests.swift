import Foundation
import Network
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

    @Test("Accepts bare LF delimiters and strips CR from standard delimiters")
    func handlesBareAndStandardLineEndings() {
        var buffer = IRCLineBuffer(maximumLineBytes: 510)
        let output = buffer.append(Data("PING :bare\nNOTICE nick :standard\r\n".utf8))

        #expect(output.lines == ["PING :bare", "NOTICE nick :standard"])
        #expect(!output.exceededMaximumLineLength)
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

    @Test("Does not count a fragmented CRLF delimiter against the line limit")
    func acceptsExactLimitBeforeFragmentedDelimiter() {
        var buffer = IRCLineBuffer(maximumLineBytes: 5)
        #expect(!buffer.append(Data("12345\r".utf8)).exceededMaximumLineLength)
        let output = buffer.append(Data("\n".utf8))

        #expect(output.lines == ["12345"])
        #expect(!output.exceededMaximumLineLength)
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

    @Test("Connection lifecycle phases are mutually exclusive and reset atomically")
    @MainActor
    func connectionLifecyclePhasesAreMutuallyExclusive() {
        let transport = IRCTransport.direct(
            NWConnection(
                host: "localhost",
                port: NWEndpoint.Port(rawValue: 6667)!,
                using: .tcp
            )
        )
        let credentials = IRCSASLCredentials(username: "nick", password: "secret")
        let registration = IRCRegistrationState(
            serverPassword: "server-secret",
            saslCredentials: credentials
        )
        var phase = IRCConnectionPhase.connectingTransport(
            IRCConnectionSession(transport: transport, registration: registration)
        )

        #expect(phase.wakeRecoveryAction(isViable: nil) == .resumeConnectionTimeout)
        let transportReady = phase.transportBecameReady()
        phase = transportReady.phase
        #expect(transportReady.shouldBeginRegistration)
        guard case .registering = phase else {
            Issue.record("Transport readiness must transition to registration")
            return
        }

        phase = phase.registrationCompleted()
        guard case .ready = phase else {
            Issue.record("Registration completion must transition to ready")
            return
        }
        #expect(phase.wakeRecoveryAction(isViable: true) == .probeEstablishedConnection)

        phase = phase.reportingFailure("first failure", cancellingTransport: false)
        guard case .failed(.connected(let message, let previousProgress, _)) = phase else {
            Issue.record("Failure must replace the ready phase atomically")
            return
        }
        #expect(message == "first failure")
        #expect(previousProgress == .ready)
        #expect(!phase.canReportFailure)
        #expect(phase.wakeRecoveryAction(isViable: true) == .none)

        phase = phase.reportingFailure("duplicate failure", cancellingTransport: false)
        #expect(phase.registrationCompleted().wakeRecoveryAction(isViable: true) == .none)
        guard case .failed(let failure) = phase else {
            Issue.record("A duplicate failure must not restore an active phase")
            return
        }
        #expect(failure.message == "first failure")

        phase = phase.resetting().resetting()
        guard case .idle = phase else {
            Issue.record("Repeated cleanup must remain idle")
            return
        }
        #expect(phase.transport == nil)
        #expect(phase.registration == nil)
    }

    @Test("Registration substate resets capabilities, SASL, and secrets together")
    @MainActor
    func registrationSubstateResetsTogether() {
        let directConnection = NWConnection(
            host: "localhost",
            port: NWEndpoint.Port(rawValue: 6667)!,
            using: .tcp
        )
        let directTransport = IRCTransport.direct(directConnection)
        let oldCredentials = IRCSASLCredentials(username: "old", password: "old-secret")
        var oldRegistration = IRCRegistrationState(
            serverPassword: "old-server-secret",
            saslCredentials: oldCredentials
        )
        oldRegistration.capabilityNegotiation = .ended(
            IRCAdvertisedCapabilities(
                names: ["message-tags", "sasl"],
                saslMechanisms: ["PLAIN"]
            ),
            sasl: .responseSent(oldCredentials)
        )
        var phase = IRCConnectionPhase.ready(
            IRCConnectionSession(
                transport: directTransport,
                registration: oldRegistration
            )
        )

        phase = phase.resetting()
        let newCredentials = IRCSASLCredentials(username: "new", password: "new-secret")
        let newRegistration = IRCRegistrationState(
            serverPassword: nil,
            saslCredentials: newCredentials
        )
        phase = .connectingTransport(
            IRCConnectionSession(
                transport: .ssh(SSHTunnelConnection()),
                registration: newRegistration
            )
        )

        guard case .connectingTransport(let session) = phase else {
            Issue.record("A reconnect must have exactly one connecting transport")
            return
        }
        guard case .ssh = session.transport else {
            Issue.record("The transport enum must contain exactly the selected SSH transport")
            return
        }
        #expect(session.registration.serverPassword == nil)
        #expect(session.registration.capabilityNegotiation.advertised.names.isEmpty)
        #expect(session.registration.capabilityNegotiation.advertised.saslMechanisms == nil)
        #expect(session.registration.capabilityNegotiation.sasl == .pending(newCredentials))
    }

    @Test("Failure during graceful quit stays in one explicit quitting phase")
    @MainActor
    func failureDuringGracefulQuitRetainsQuitState() {
        let transport = IRCTransport.direct(
            NWConnection(
                host: "localhost",
                port: NWEndpoint.Port(rawValue: 6667)!,
                using: .tcp
            )
        )
        let session = IRCConnectionSession(
            transport: transport,
            registration: IRCRegistrationState(
                serverPassword: nil,
                saslCredentials: nil
            )
        )
        let generation = UUID()
        let quit = IRCQuitPhase.writing(
            IRCQuitContext(
                generation: generation,
                timeoutGeneration: UUID(),
                completion: {}
            )
        )
        var phase = IRCConnectionPhase.ready(session).beginningQuit(quit)!

        phase = phase.reportingFailure("write raced with close", cancellingTransport: true)

        guard case .quitting(let connection) = phase else {
            Issue.record("An in-flight quit must remain the exclusive top-level phase")
            return
        }
        #expect(connection.progress == .ready)
        #expect(connection.failureMessage == "write raced with close")
        #expect(connection.transport != nil)
        #expect(connection.quit.context.generation == generation)
        #expect(!phase.canReportFailure)

        phase = phase.removingTransport()
        guard case .quitting(let transportClosed) = phase else {
            Issue.record("Peer close must retain quit completion state until cleanup")
            return
        }
        #expect(transportClosed.transport == nil)
        #expect(transportClosed.quit.context.generation == generation)
        guard case .idle = phase.resetting() else {
            Issue.record("Quit cleanup must atomically discard all associated state")
            return
        }
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
