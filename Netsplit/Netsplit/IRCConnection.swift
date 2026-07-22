//
//  IRCConnection.swift
//  Netsplit
//

import Foundation
import Network

enum IRCTransportEvent {
    case status(ConnectionStatus)
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
        if escaped { result.append("\\") }
        return result
    }
}

@MainActor
final class IRCConnection {
    private static let maximumBufferedLineBytes = 64 * 1024
    private static let heartbeatInterval: TimeInterval = 30
    private static let heartbeatTimeout: TimeInterval = 15
    // Some IRC networks perform reverse-DNS and Ident checks before replying
    // to CAP or completing registration. IRCnet commonly takes about 30
    // seconds, so leave enough headroom for capability negotiation afterward.
    private static let registrationTimeout: TimeInterval = 60
    private var connection: NWConnection?
    private var sshTunnel: SSHTunnelConnection?
    private var receiveBuffer = IRCLineBuffer(maximumLineBytes: maximumBufferedLineBytes)
    private var heartbeatGeneration: UUID?
    private var pendingHeartbeatToken: String?
    private var registrationTimeoutGeneration: UUID?
    private var hasReportedFailure = false
    private var hasReachedReadyState = false
    private var nickname = "netsplit"
    private var advertisedCapabilities = Set<String>()
    private var capabilityNegotiationEnded = false
    private var serverPassword: String?
    private var saslCredentials: (username: String, password: String)?
    private var isWaitingForSASLResponse = false
    private var quitGeneration: UUID?
    private var quitTimeoutGeneration: UUID?
    private var quitCompletion: (@MainActor () -> Void)?
    var eventHandler: (@MainActor (IRCTransportEvent) -> Void)?

    func connect(profile: ServerProfile, nickname: String, realName: String, serverPassword: String, saslUsername: String?, saslPassword: String, sshPassword: String, sshPrivateKey: String) {
        disconnect()
        self.nickname = nickname
        advertisedCapabilities.removeAll()
        capabilityNegotiationEnded = false
        isWaitingForSASLResponse = false
        hasReportedFailure = false
        hasReachedReadyState = false
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
            self.saslCredentials = (saslUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? saslUsername!.trimmingCharacters(in: .whitespacesAndNewlines) : nickname, saslPassword)
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
                            cancelling: false,
                            automaticallyReconnect: !preventsReconnect
                        )
                    } else if !self.hasReportedFailure {
                        self.eventHandler?(.status(.offline))
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
            eventHandler?(.status(.failed("Invalid port")))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(profile.hostname), port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .setup, .preparing: self.eventHandler?(.status(.connecting))
                case .ready:
                    self.hasReachedReadyState = true
                    self.eventHandler?(.status(.online))
                    self.register(nickname: nickname, realName: realName)
                    self.startRegistrationTimeout()
                    self.receiveNext(on: connection)
                case .failed(let error):
                    if !self.handleQuitEvent(.peerClosed) {
                        self.reportFailure(error.localizedDescription, cancelling: false)
                    }
                case .cancelled:
                    self.stopHeartbeat()
                    if !self.handleQuitEvent(.peerClosed) {
                        self.connection = nil
                        if !self.hasReportedFailure { self.eventHandler?(.status(.offline)) }
                    }
                default: break
                }
            }
        }
        connection.viabilityUpdateHandler = { [weak self, weak connection] isViable in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      let connection,
                      self.connection === connection,
                      self.hasReachedReadyState,
                      !isViable else { return }
                self.reportFailure("The network path became unavailable.")
            }
        }
        eventHandler?(.status(.connecting))
        connection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        if quitGeneration != nil {
            finishQuit()
            return
        }
        closeTransport()
    }

    private func closeTransport() {
        stopHeartbeat()
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
            let boundedCommand = IRCTextFraming.prefix("QUIT :\(safeReason)")
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
        let boundedCommand = IRCTextFraming.prefix("QUIT :\(safeReason)")
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
        let boundedCommand = IRCTextFraming.prefix(singleLine)
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
                    self.reportFailure("Send failed: \(error.localizedDescription)")
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
                    self.reportFailure("Send failed: \(error.localizedDescription)")
                    completion?(false)
                } else {
                    completion?(true)
                }
            }
        })
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
                        self.reportFailure(error.localizedDescription)
                    }
                } else if isComplete {
                    self.stopHeartbeat()
                    if !self.handleQuitEvent(.peerClosed) {
                        self.connection = nil
                        self.eventHandler?(.status(.offline))
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
                stopRegistrationTimeout()
                startHeartbeat()
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
        reportFailure(message)
    }

    /// TCP can remain locally established through a network outage when no data
    /// is in flight. Probe the IRC peer so a silent half-open connection has a
    /// deterministic upper bound instead of waiting for the kernel's TCP timeout.
    private func startHeartbeat() {
        let generation = UUID()
        heartbeatGeneration = generation
        pendingHeartbeatToken = nil
        scheduleHeartbeat(generation: generation)
    }

    private func scheduleHeartbeat(generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatInterval) { [weak self] in
            guard let self,
                  self.heartbeatGeneration == generation,
                  self.connection != nil || self.sshTunnel != nil,
                  !self.hasReportedFailure else { return }

            let token = "netsplit-\(UUID().uuidString)"
            self.pendingHeartbeatToken = token
            self.scheduleHeartbeatTimeout(token: token, generation: generation)
            self.send(command: "PING :\(token)")
        }
    }

    private func scheduleHeartbeatTimeout(token: String, generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatTimeout) { [weak self] in
            guard let self,
                  self.heartbeatGeneration == generation,
                  self.pendingHeartbeatToken == token else { return }
            self.reportFailure("Connection heartbeat timed out after \(Int(Self.heartbeatTimeout)) seconds.")
        }
    }

    private func handleHeartbeatReply(_ message: IRCWireMessage) {
        guard let token = pendingHeartbeatToken else { return }
        let isMatchingReply = message.trailing == token || message.parameters.contains(token)
        guard isMatchingReply, let generation = heartbeatGeneration else { return }
        pendingHeartbeatToken = nil
        scheduleHeartbeat(generation: generation)
    }

    private func stopHeartbeat() {
        heartbeatGeneration = nil
        pendingHeartbeatToken = nil
    }

    private func startRegistrationTimeout() {
        let generation = UUID()
        registrationTimeoutGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationTimeout) { [weak self] in
            guard let self,
                  self.registrationTimeoutGeneration == generation,
                  self.connection != nil || self.sshTunnel != nil,
                  !self.hasReportedFailure else { return }
            self.reportFailure("The IRC server did not complete registration within \(Int(Self.registrationTimeout)) seconds.")
        }
    }

    private func stopRegistrationTimeout() {
        registrationTimeoutGeneration = nil
    }

    private func reportFailure(
        _ message: String,
        cancelling: Bool = true,
        automaticallyReconnect: Bool = true
    ) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        stopHeartbeat()
        stopRegistrationTimeout()
        if automaticallyReconnect {
            eventHandler?(.status(.failed(message)))
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
            let capabilities = (message.trailing ?? "").split(separator: " ").map { IRCCapability.name(from: String($0)) }
            advertisedCapabilities.formUnion(capabilities)
            // An asterisk after LS signals a multi-line capability list.
            let hasMore = message.parameters.dropFirst(2).contains("*")
            guard !hasMore else { return }
            let preferred = ["message-tags", "server-time", "batch", "labeled-response", "echo-message"]
            var supported = preferred.filter { advertisedCapabilities.contains($0) }
            if saslCredentials != nil {
                if advertisedCapabilities.contains("sasl") {
                    supported.append("sasl")
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
        guard message.parameters.first == "+", let credentials = saslCredentials, !isWaitingForSASLResponse else { return }
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
