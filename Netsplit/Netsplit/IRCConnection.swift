//
//  IRCConnection.swift
//  Netsplit
//

import Foundation
import Network
import OSLog

enum IRCTransportEvent {
    case status(ConnectionStatus)
    case recoverableFailure(String, IRCReconnectReason)
    case terminalFailure(String)
    case received(IRCWireMessage)
    case notice(String)
    case sshHostKeyLearned(String)
}

enum IRCGracefulQuitEvent {
    case started
    case localWriteSucceeded
    case localWriteFailed
    case peerClosed
    case timedOut
}

enum IRCGracefulQuitPolicy {
    static let maximumWriteDuration: TimeInterval = 2
    static let peerCloseGraceDuration: TimeInterval = 0.5

    static func timeout(after event: IRCGracefulQuitEvent) -> TimeInterval? {
        switch event {
        case .started:
            maximumWriteDuration
        case .localWriteSucceeded:
            peerCloseGraceDuration
        case .localWriteFailed, .peerClosed, .timedOut:
            nil
        }
    }

    static func shouldFinish(after event: IRCGracefulQuitEvent) -> Bool {
        switch event {
        case .started, .localWriteSucceeded:
            false
        case .localWriteFailed, .peerClosed, .timedOut:
            true
        }
    }
}

struct IRCWireMessage {
    var tags: [String: String?]
    var prefix: String?
    var command: String
    var parameters: [String]
    var trailing: String?

    var isSASLContinuation: Bool {
        guard command == "AUTHENTICATE" else { return false }
        return (parameters == ["+"] && trailing == nil)
            || (parameters.isEmpty && trailing == "+")
    }

    init?(line: String) {
        var remainder = line
        tags = [:]

        // IRCv3 message tags precede the prefix/command, for example:
        // @time=2026-07-16T20:00:00.000Z :server 311 me nick user host * :Real Name
        // Parse them before looking for the traditional prefix so tagged numeric
        // replies (/WHOIS, /LIST, etc.) reach the higher-level dispatcher.
        if remainder.hasPrefix("@") {
            guard let space = remainder.firstIndex(of: " ") else { return nil }
            let rawTags = remainder[remainder.index(after: remainder.startIndex)..<space]
            for rawTag in rawTags.split(separator: ";") {
                let pair = rawTag.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(pair[0])
                let value = pair.count == 2 ? Self.unescapeTagValue(String(pair[1])) : nil
                tags[key] = value
            }
            remainder = String(remainder[remainder.index(after: space)...])
        }
        if remainder.hasPrefix(":") {
            guard let space = remainder.firstIndex(of: " ") else { return nil }
            prefix = String(remainder.dropFirst().prefix(upTo: space))
            remainder = String(remainder[remainder.index(after: space)...])
        }
        let split = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawCommand = split.first else { return nil }
        command = rawCommand.uppercased()
        remainder = split.count == 2 ? String(split[1]) : ""
        if let trailingRange = remainder.range(of: " :") {
            parameters = remainder[..<trailingRange.lowerBound].split(separator: " ").map(String.init)
            trailing = String(remainder[trailingRange.upperBound...])
        } else if remainder.hasPrefix(":") {
            parameters = []
            trailing = String(remainder.dropFirst())
        } else {
            parameters = remainder.split(separator: " ").map(String.init)
            trailing = nil
        }
    }

    private static func unescapeTagValue(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case ":": result.append(";")
                case "s": result.append(" ")
                case "r": result.append("\r")
                case "n": result.append("\n")
                case "\\": result.append("\\")
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}

@MainActor
final class IRCConnection {
    private static let maximumBufferedLineBytes = 64 * 1024
    private static let heartbeatInterval: TimeInterval = 30
    private static let heartbeatTimeout: TimeInterval = 15
    private static let viabilityGraceDuration: TimeInterval = 5
    // Network.framework or the SSH transport can remain in setup without
    // delivering a terminal state (for example, when TLS trust evaluation
    // stalls). Cover the entire DNS/TCP/SSH/TLS setup phase with a bound.
    private static let connectionTimeout: TimeInterval = 30
    // Some IRC networks perform reverse-DNS and Ident checks before replying
    // to CAP or completing registration. IRCnet commonly takes about 30
    // seconds, so leave enough headroom for capability negotiation afterward.
    private static let registrationTimeout: TimeInterval = 60
    private var connection: NWConnection?
    private var sshTunnel: SSHTunnelConnection?
    private var receiveBuffer = IRCLineBuffer(maximumLineBytes: maximumBufferedLineBytes)
    private var heartbeatGeneration: UUID?
    private var pendingHeartbeatToken: String?
    private var connectionTimeoutGeneration: UUID?
    private var lastConnectionAttemptError: String?
    private var registrationTimeoutGeneration: UUID?
    private var viabilityFailureGeneration: UUID?
    private var wakeRecoveryGeneration: UUID?
    private var hasReportedFailure = false
    private var hasReachedReadyState = false
    private var hasCompletedRegistration = false
    private var isSystemSleeping = false
    private var isAwaitingWakeRecovery = false
    private var isConnectionViable: Bool?
    private var heartbeatIsWakeProbe = false
    private var diagnosticEndpoint = "unknown"
    private var nickname = "netsplit"
    private var advertisedCapabilities = Set<String>()
    private var advertisedSASLMechanisms: Set<String>?
    private var capabilityNegotiationEnded = false
    private var maximumOutboundLineBytes = IRCTextFraming.maximumLineBytes
    private var serverPassword: String?
    private var saslCredentials: (username: String, password: String)?
    private var isWaitingForSASLResponse = false
    private var quitGeneration: UUID?
    private var quitTimeoutGeneration: UUID?
    private var quitCompletion: (@MainActor () -> Void)?
    var eventHandler: (@MainActor (IRCTransportEvent) -> Void)?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Netsplit",
        category: "IRCConnection"
    )

    func connect(profile: ServerProfile, nickname: String, realName: String, serverPassword: String, saslUsername: String?, saslPassword: String, sshPassword: String, sshPrivateKey: String) {
        disconnect()
        diagnosticEndpoint = "\(profile.hostname):\(profile.port)"
        self.nickname = nickname
        advertisedCapabilities.removeAll()
        advertisedSASLMechanisms = nil
        capabilityNegotiationEnded = false
        maximumOutboundLineBytes = IRCTextFraming.maximumLineBytes
        isWaitingForSASLResponse = false
        hasReportedFailure = false
        hasReachedReadyState = false
        hasCompletedRegistration = false
        isSystemSleeping = false
        isAwaitingWakeRecovery = false
        isConnectionViable = nil
        heartbeatIsWakeProbe = false
        guard IRCIdentityValidation.isValidNickname(nickname) else {
            eventHandler?(.terminalFailure(IRCIdentityValidation.nicknameError(nickname) ?? "The configured nickname is invalid."))
            return
        }
        guard profile.useSASL != true || !saslPassword.isEmpty else {
            eventHandler?(.terminalFailure("SASL is enabled for this profile, but no SASL password is configured."))
            return
        }
        self.serverPassword = serverPassword.isEmpty ? nil : serverPassword
        if profile.useSASL == true, !saslPassword.isEmpty {
            let username: String
            if let saslUsername = saslUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
               !saslUsername.isEmpty {
                username = saslUsername
            } else {
                username = nickname
            }
            self.saslCredentials = (username, saslPassword)
        } else {
            self.saslCredentials = nil
        }

        if profile.useSSHTunnel == true {
            guard let sshHostname = profile.sshHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshHostname.isEmpty,
                  let sshUsername = profile.sshUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshUsername.isEmpty else {
                eventHandler?(.terminalFailure("The SSH hostname and username are required."))
                return
            }
            let tunnel = SSHTunnelConnection()
            sshTunnel = tunnel
            eventHandler?(.status(.connecting))
            startConnectionTimeout()
            tunnel.connect(
                configuration: SSHTunnelConfiguration(
                    sshHostname: sshHostname,
                    sshPort: Int(profile.sshPort ?? 22),
                    sshUsername: sshUsername,
                    sshPassword: sshPassword,
                    sshPrivateKey: sshPrivateKey,
                    trustedHostKey: profile.sshTrustedHostKey,
                    targetHostname: profile.hostname,
                    targetPort: Int(profile.port),
                    useTLS: profile.useTLS
                ),
                onReady: { [weak self, weak tunnel] in
                    guard let self, let tunnel, self.sshTunnel === tunnel else { return }
                    self.hasReachedReadyState = true
                    self.stopConnectionTimeout()
                    self.eventHandler?(.status(.online))
                    self.register(nickname: nickname, realName: realName)
                    self.startRegistrationTimeout()
                },
                onData: { [weak self, weak tunnel] data in
                    guard let self, let tunnel, self.sshTunnel === tunnel else { return }
                    _ = self.process(data)
                },
                onClose: { [weak self, weak tunnel] error in
                    guard let self, let tunnel, self.sshTunnel === tunnel else { return }
                    // The tunnel wrapper begins closing both the forwarded
                    // channel and its parent SSH session before this callback.
                    self.sshTunnel = nil
                    self.stopHeartbeat()
                    if self.handleQuitEvent(.peerClosed) { return }
                    if let error {
                        let preventsReconnect = (error as? SSHTunnelError)?.preventsAutomaticReconnect == true
                        self.reportFailure(
                            "SSH tunnel failed: \(error.localizedDescription)",
                            reason: .sshTransport,
                            cancelling: false,
                            automaticallyReconnect: !preventsReconnect
                        )
                    } else if !self.hasReportedFailure {
                        self.reportFailure(
                            "SSH tunnel closed.",
                            reason: .remoteClose,
                            cancelling: false
                        )
                    }
                },
                onHostKeyLearned: { [weak self, weak tunnel] key in
                    guard let self, let tunnel, self.sshTunnel === tunnel else { return }
                    self.eventHandler?(.sshHostKeyLearned(key))
                }
            )
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3

        let parameters: NWParameters
        if profile.useTLS {
            let tls = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tls, tcp: tcp)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        guard let port = NWEndpoint.Port(rawValue: profile.port) else {
            eventHandler?(.terminalFailure("Invalid port"))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(profile.hostname), port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .setup, .preparing: self.eventHandler?(.status(.connecting))
                case .waiting(let error):
                    // A waiting connection may recover on its own. Keep it
                    // alive until the setup watchdog expires, while retaining
                    // the most useful error for the eventual UI message.
                    self.lastConnectionAttemptError = error.localizedDescription
                    self.eventHandler?(.status(.connecting))
                case .ready:
                    let isInitialReadyState = !self.hasReachedReadyState
                    self.hasReachedReadyState = true
                    self.stopConnectionTimeout()
                    self.eventHandler?(.status(.online))
                    if isInitialReadyState {
                        self.register(nickname: nickname, realName: realName)
                        self.startRegistrationTimeout()
                        self.receiveNext(on: connection)
                    }
                case .failed(let error):
                    if !self.handleQuitEvent(.peerClosed) {
                        self.reportFailure(
                            error.localizedDescription,
                            reason: .connectionState,
                            cancelling: false
                        )
                    }
                case .cancelled:
                    self.stopHeartbeat()
                    if !self.handleQuitEvent(.peerClosed) {
                        self.connection = nil
                        if !self.hasReportedFailure {
                            self.reportFailure(
                                "The network connection was cancelled.",
                                reason: .connectionState,
                                cancelling: false
                            )
                        }
                    }
                default: break
                }
            }
        }
        connection.viabilityUpdateHandler = { [weak self, weak connection] isViable in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      let connection,
                      self.connection === connection else { return }
                self.handleViabilityChange(isViable)
            }
        }
        eventHandler?(.status(.connecting))
        startConnectionTimeout()
        connection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        if quitGeneration != nil {
            finishQuit()
            return
        }
        closeTransport()
    }

    func systemWillSleep() {
        guard !isSystemSleeping else { return }
        isSystemSleeping = true
        isAwaitingWakeRecovery = false
        wakeRecoveryGeneration = nil
        viabilityFailureGeneration = nil
        stopHeartbeat()
        stopConnectionTimeout()
        stopRegistrationTimeout()
        Self.logger.info(
            "Paused connection watchdogs before sleep endpoint=\(self.diagnosticEndpoint, privacy: .public)"
        )
    }

    func systemDidWake(after delay: TimeInterval = 0) {
        guard isSystemSleeping else { return }
        isSystemSleeping = false
        isAwaitingWakeRecovery = true
        let generation = UUID()
        wakeRecoveryGeneration = generation

        let recover: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self,
                  self.wakeRecoveryGeneration == generation,
                  !self.isSystemSleeping else { return }
            self.wakeRecoveryGeneration = nil
            self.resumeAfterWake()
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: recover)
        } else {
            recover()
        }
    }

    private func resumeAfterWake() {
        let action = IRCConnectionRecoveryPolicy.wakeAction(
            hasTransport: connection != nil || sshTunnel != nil,
            hasReportedFailure: hasReportedFailure,
            hasCompletedRegistration: hasCompletedRegistration,
            hasReachedReadyState: hasReachedReadyState,
            isViable: isConnectionViable
        )
        Self.logger.info(
            "Resuming after wake endpoint=\(self.diagnosticEndpoint, privacy: .public) action=\(String(describing: action), privacy: .public)"
        )

        switch action {
        case .none:
            isAwaitingWakeRecovery = false
        case .waitForViability:
            scheduleViabilityFailure()
        case .probeEstablishedConnection:
            isAwaitingWakeRecovery = false
            startHeartbeat(probeImmediately: true, isWakeProbe: true)
        case .resumeRegistrationTimeout:
            isAwaitingWakeRecovery = false
            startRegistrationTimeout()
        case .resumeConnectionTimeout:
            isAwaitingWakeRecovery = false
            startConnectionTimeout()
        }
    }

    private func handleViabilityChange(_ isViable: Bool) {
        isConnectionViable = isViable
        Self.logger.debug(
            "Viability changed endpoint=\(self.diagnosticEndpoint, privacy: .public) viable=\(isViable, privacy: .public)"
        )
        if isViable {
            viabilityFailureGeneration = nil
            if isAwaitingWakeRecovery, !isSystemSleeping {
                resumeAfterWake()
            }
            return
        }

        guard hasReachedReadyState,
              !hasReportedFailure,
              !isSystemSleeping else { return }
        scheduleViabilityFailure()
    }

    private func scheduleViabilityFailure() {
        guard isConnectionViable == false,
              hasReachedReadyState,
              !hasReportedFailure,
              !isSystemSleeping else { return }
        let generation = UUID()
        viabilityFailureGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.viabilityGraceDuration) { [weak self] in
            guard let self,
                  self.viabilityFailureGeneration == generation,
                  self.isConnectionViable == false,
                  !self.isSystemSleeping else { return }
            self.viabilityFailureGeneration = nil
            self.reportFailure(
                "The network path remained unavailable for \(Int(Self.viabilityGraceDuration)) seconds.",
                reason: .networkViability
            )
        }
    }

    private func closeTransport() {
        isSystemSleeping = false
        isAwaitingWakeRecovery = false
        wakeRecoveryGeneration = nil
        viabilityFailureGeneration = nil
        isConnectionViable = nil
        stopHeartbeat()
        stopConnectionTimeout()
        stopRegistrationTimeout()
        connection?.cancel()
        connection = nil
        sshTunnel?.close()
        sshTunnel = nil
        receiveBuffer.removeAll()
    }

    /// Sends IRC QUIT and keeps the transport open until the server closes its
    /// side of the IRC session. A bounded timeout still guarantees completion if
    /// the peer does not respond to QUIT with an orderly close.
    func quit(reason: String, completion: @MainActor @escaping () -> Void = {}) {
        guard quitGeneration == nil else {
            completion()
            return
        }
        guard connection != nil || sshTunnel != nil else {
            completion()
            return
        }

        stopHeartbeat()
        stopRegistrationTimeout()
        let generation = UUID()
        quitGeneration = generation
        quitCompletion = completion
        _ = handleQuitEvent(.started, generation: generation)

        if let sshTunnel {
            let safeReason = reason
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let boundedCommand = IRCTextFraming.prefix(
                "QUIT :\(safeReason)",
                fittingUTF8ByteCount: maximumOutboundLineBytes
            )
            sshTunnel.send(Data("\(boundedCommand)\r\n".utf8)) { [weak self, weak sshTunnel] sent, error in
                guard let self,
                      self.quitGeneration == generation,
                      self.sshTunnel === sshTunnel else { return }
                let event: IRCGracefulQuitEvent = sent && error == nil ? .localWriteSucceeded : .localWriteFailed
                _ = self.handleQuitEvent(event, generation: generation)
            }
            return
        }
        guard let connection else { return }

        let safeReason = reason
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let boundedCommand = IRCTextFraming.prefix(
            "QUIT :\(safeReason)",
            fittingUTF8ByteCount: maximumOutboundLineBytes
        )
        let line = "\(boundedCommand)\r\n"
        connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self, weak connection] error in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      self.quitGeneration == generation,
                      self.connection === connection else { return }
                let event: IRCGracefulQuitEvent = error == nil ? .localWriteSucceeded : .localWriteFailed
                _ = self.handleQuitEvent(event, generation: generation)
            }
        })
    }

    @discardableResult
    private func handleQuitEvent(_ event: IRCGracefulQuitEvent, generation: UUID? = nil) -> Bool {
        guard let activeGeneration = quitGeneration,
              generation == nil || generation == activeGeneration else { return false }
        if let timeout = IRCGracefulQuitPolicy.timeout(after: event) {
            let timeoutGeneration = UUID()
            quitTimeoutGeneration = timeoutGeneration
            // This closure deliberately retains the transport until its deadline.
            // The initial watchdog bounds a stalled write; after a successful
            // write, a fresh grace period gives the peer time to close cleanly.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in
                guard quitTimeoutGeneration == timeoutGeneration else { return }
                _ = handleQuitEvent(.timedOut, generation: activeGeneration)
            }
        }
        if IRCGracefulQuitPolicy.shouldFinish(after: event) {
            finishQuit(generation: activeGeneration)
        }
        return true
    }

    private func finishQuit(generation: UUID? = nil) {
        guard let activeGeneration = quitGeneration,
              generation == nil || generation == activeGeneration else { return }
        let completion = quitCompletion
        quitGeneration = nil
        quitTimeoutGeneration = nil
        quitCompletion = nil
        closeTransport()
        completion?()
    }

    func send(command: String, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard connection != nil || sshTunnel != nil else {
            completion?(false)
            return
        }
        let singleLine = IRCTextFraming.sanitizedSingleLine(command)
        let boundedCommand = IRCTextFraming.prefix(
            singleLine,
            fittingUTF8ByteCount: maximumOutboundLineBytes
        )
        if boundedCommand != singleLine {
            eventHandler?(.notice("An outgoing IRC command exceeded the server line limit and was truncated."))
        }
        let line = boundedCommand + "\r\n"
        if let sshTunnel {
            sshTunnel.send(Data(line.utf8)) { [weak self, weak sshTunnel] sent, error in
                guard let self, self.sshTunnel === sshTunnel else {
                    completion?(false)
                    return
                }
                if let error {
                    self.reportFailure(
                        "Send failed: \(error.localizedDescription)",
                        reason: .sendError
                    )
                    completion?(false)
                } else {
                    completion?(sent)
                }
            }
            return
        }
        guard let connection else {
            completion?(false)
            return
        }
        connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self, weak connection] error in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connection === connection else {
                    completion?(false)
                    return
                }
                if let error {
                    self.reportFailure(
                        "Send failed: \(error.localizedDescription)",
                        reason: .sendError
                    )
                    completion?(false)
                } else {
                    completion?(true)
                }
            }
        })
    }

    func setMaximumLineLength(_ maximumLineLength: Int) {
        maximumOutboundLineBytes = max(
            0,
            maximumLineLength - IRCTextFraming.lineTerminatorBytes
        )
    }

    private func register(nickname: String, realName: String) {
        // CAP is an optional IRCv3 extension. Registration is deliberately sent
        // independently so an older IRC server that does not implement CAP still
        // behaves as a normal RFC-style IRC connection.
        let registrationName = realName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeRealName = registrationName.isEmpty ? "Netsplit User" : registrationName
        if let serverPassword { send(command: "PASS :\(serverPassword.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))") }
        send(command: "CAP LS 302")
        send(command: "NICK \(nickname)")
        send(command: "USER \(nickname) 0 * :\(safeRealName)")
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connection === connection else { return }
                if let data, !self.process(data) { return }
                if let error {
                    if !self.handleQuitEvent(.peerClosed) {
                        self.reportFailure(
                            error.localizedDescription,
                            reason: .receiveError
                        )
                    }
                } else if isComplete {
                    self.stopHeartbeat()
                    if !self.handleQuitEvent(.peerClosed) {
                        self.connection = nil
                        self.reportFailure(
                            "Connection closed by the IRC server.",
                            reason: .remoteClose,
                            cancelling: false
                        )
                    }
                } else {
                    self.receiveNext(on: connection)
                }
            }
        }
    }

    @discardableResult
    private func process(_ data: Data) -> Bool {
        let output = receiveBuffer.append(data)
        for line in output.lines {
            guard let message = IRCWireMessage(line: line) else { continue }
            if message.command == "001" {
                hasCompletedRegistration = true
                stopRegistrationTimeout()
                if !isSystemSleeping {
                    startHeartbeat()
                }
            }
            if message.command == "PING" { send(command: "PONG :\(message.trailing ?? message.parameters.first ?? "")") }
            if message.command == "PONG" { handleHeartbeatReply(message) }
            if message.command == "CAP" {
                handleCapabilityMessage(message)
            }
            if message.command == "AUTHENTICATE" {
                handleAuthenticationMessage(message)
            }
            handleSASLNumeric(message)
            eventHandler?(.received(message))
        }
        guard !output.exceededMaximumLineLength else {
            failMalformedInput("The server sent an IRC line larger than 64 KB.")
            return false
        }
        return true
    }

    private func failMalformedInput(_ message: String) {
        eventHandler?(.notice(message))
        reportFailure(message, reason: .malformedInput)
    }

    /// TCP can remain locally established through a network outage when no data
    /// is in flight. Probe the IRC peer so a silent half-open connection has a
    /// deterministic upper bound instead of waiting for the kernel's TCP timeout.
    private func startHeartbeat(
        probeImmediately: Bool = false,
        isWakeProbe: Bool = false
    ) {
        guard !isSystemSleeping else { return }
        let generation = UUID()
        heartbeatGeneration = generation
        pendingHeartbeatToken = nil
        heartbeatIsWakeProbe = isWakeProbe
        if probeImmediately {
            sendHeartbeatProbe(generation: generation)
        } else {
            scheduleHeartbeat(generation: generation)
        }
    }

    private func scheduleHeartbeat(generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatInterval) { [weak self] in
            guard let self,
                  self.heartbeatGeneration == generation,
                  self.connection != nil || self.sshTunnel != nil,
                  !self.hasReportedFailure else { return }
            self.sendHeartbeatProbe(generation: generation)
        }
    }

    private func sendHeartbeatProbe(generation: UUID) {
        guard heartbeatGeneration == generation,
              connection != nil || sshTunnel != nil,
              !hasReportedFailure,
              !isSystemSleeping else { return }
        let token = "netsplit-\(UUID().uuidString)"
        pendingHeartbeatToken = token
        scheduleHeartbeatTimeout(token: token, generation: generation)
        send(command: "PING :\(token)")
    }

    private func scheduleHeartbeatTimeout(token: String, generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatTimeout) { [weak self] in
            guard let self,
                  self.heartbeatGeneration == generation,
                  self.pendingHeartbeatToken == token else { return }
            let isWakeProbe = self.heartbeatIsWakeProbe
            self.reportFailure(
                isWakeProbe
                    ? "The connection did not respond after system wake."
                    : "Connection heartbeat timed out after \(Int(Self.heartbeatTimeout)) seconds.",
                reason: isWakeProbe ? .wakeProbeTimeout : .heartbeatTimeout
            )
        }
    }

    private func handleHeartbeatReply(_ message: IRCWireMessage) {
        guard let token = pendingHeartbeatToken else { return }
        let isMatchingReply = message.trailing == token || message.parameters.contains(token)
        guard isMatchingReply, let generation = heartbeatGeneration else { return }
        pendingHeartbeatToken = nil
        heartbeatIsWakeProbe = false
        scheduleHeartbeat(generation: generation)
    }

    private func stopHeartbeat() {
        heartbeatGeneration = nil
        pendingHeartbeatToken = nil
        heartbeatIsWakeProbe = false
    }

    private func startConnectionTimeout() {
        let generation = UUID()
        connectionTimeoutGeneration = generation
        lastConnectionAttemptError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout) { [weak self] in
            guard let self,
                  self.connectionTimeoutGeneration == generation,
                  !self.hasReachedReadyState,
                  self.connection != nil || self.sshTunnel != nil,
                  !self.hasReportedFailure else { return }
            let detail = self.lastConnectionAttemptError.map { " Last network error: \($0)" } ?? ""
            self.reportFailure(
                "The connection could not be established within \(Int(Self.connectionTimeout)) seconds.\(detail)",
                reason: .connectionTimeout
            )
        }
    }

    private func stopConnectionTimeout() {
        connectionTimeoutGeneration = nil
        lastConnectionAttemptError = nil
    }

    private func startRegistrationTimeout() {
        let generation = UUID()
        registrationTimeoutGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationTimeout) { [weak self] in
            guard let self,
                  self.registrationTimeoutGeneration == generation,
                  self.connection != nil || self.sshTunnel != nil,
                  !self.hasReportedFailure else { return }
            self.reportFailure(
                "The IRC server did not complete registration within \(Int(Self.registrationTimeout)) seconds.",
                reason: .registrationTimeout
            )
        }
    }

    private func stopRegistrationTimeout() {
        registrationTimeoutGeneration = nil
    }

    private func reportFailure(
        _ message: String,
        reason: IRCReconnectReason,
        cancelling: Bool = true,
        automaticallyReconnect: Bool = true
    ) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        stopHeartbeat()
        stopConnectionTimeout()
        stopRegistrationTimeout()
        viabilityFailureGeneration = nil
        wakeRecoveryGeneration = nil
        isAwaitingWakeRecovery = false
        Self.logger.error(
            "Connection failure endpoint=\(self.diagnosticEndpoint, privacy: .public) reason=\(reason.rawValue, privacy: .public) message=\(message, privacy: .public)"
        )
        if automaticallyReconnect {
            eventHandler?(.recoverableFailure(message, reason))
        } else {
            eventHandler?(.terminalFailure(message))
        }
        if cancelling {
            connection?.cancel()
            sshTunnel?.close()
            sshTunnel = nil
        }
    }

    private func handleCapabilityMessage(_ message: IRCWireMessage) {
        // CAP replies are normally: CAP <nick|*> <LS|ACK|NAK> [*] :capabilities
        guard message.parameters.count >= 2 else { return }
        let subcommand = message.parameters[1].uppercased()
        switch subcommand {
        case "LS":
            let advertisedValues = (message.trailing ?? "").split(separator: " ").map(String.init)
            advertisedCapabilities.formUnion(
                advertisedValues.map { IRCCapability.name(from: $0) }
            )
            for advertisedValue in advertisedValues {
                guard let mechanisms = IRCCapability.saslMechanisms(from: advertisedValue) else {
                    continue
                }
                advertisedSASLMechanisms = (advertisedSASLMechanisms ?? []).union(mechanisms)
            }
            // An asterisk after LS signals a multi-line capability list.
            let hasMore = message.parameters.dropFirst(2).contains("*")
            guard !hasMore else { return }
            var supported = IRCCapability.preferred.filter { advertisedCapabilities.contains($0) }
            if saslCredentials != nil {
                if advertisedCapabilities.contains("sasl"),
                   IRCSASL.canUsePlain(advertisedMechanisms: advertisedSASLMechanisms) {
                    supported.append("sasl")
                } else if advertisedCapabilities.contains("sasl") {
                    eventHandler?(.notice("The server advertises SASL, but not the PLAIN mechanism required by this profile."))
                } else {
                    eventHandler?(.notice("SASL is enabled for this profile, but the server does not advertise SASL."))
                }
            }
            if supported.isEmpty {
                endCapabilityNegotiation()
            } else {
                send(command: "CAP REQ :\(supported.joined(separator: " "))")
            }
        case "ACK":
            let acknowledged = (message.trailing ?? "").split(separator: " ").map { IRCCapability.name(from: String($0)) }
            if acknowledged.contains("sasl"), saslCredentials != nil {
                send(command: "AUTHENTICATE PLAIN")
            } else {
                endCapabilityNegotiation()
            }
        case "NAK":
            if saslCredentials != nil, (message.trailing ?? "").split(separator: " ").map({ IRCCapability.name(from: String($0)) }).contains("sasl") {
                eventHandler?(.notice("The server declined SASL authentication."))
            }
            endCapabilityNegotiation()
        default:
            break
        }
    }

    private func endCapabilityNegotiation() {
        guard !capabilityNegotiationEnded else { return }
        capabilityNegotiationEnded = true
        send(command: "CAP END")
    }

    private func handleAuthenticationMessage(_ message: IRCWireMessage) {
        guard message.isSASLContinuation, let credentials = saslCredentials, !isWaitingForSASLResponse else { return }
        isWaitingForSASLResponse = true
        IRCSASL.plainAuthenticationChunks(username: credentials.username, password: credentials.password)
            .forEach { send(command: "AUTHENTICATE \($0)") }
    }

    private func handleSASLNumeric(_ message: IRCWireMessage) {
        switch message.command {
        case "903":
            eventHandler?(.notice("SASL authentication succeeded."))
            endCapabilityNegotiation()
        case "904", "905", "906", "907":
            eventHandler?(.notice(message.trailing ?? "SASL authentication failed."))
            endCapabilityNegotiation()
        default:
            break
        }
    }
}
