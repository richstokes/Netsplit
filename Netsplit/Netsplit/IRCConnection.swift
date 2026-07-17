//
//  IRCConnection.swift
//  Netsplit
//

import Foundation
import Network

enum IRCTransportEvent {
    case status(ConnectionStatus)
    case received(IRCWireMessage)
    case notice(String)
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

final class IRCConnection {
    private static let maximumOutboundLineBytes = 510
    private static let maximumBufferedLineBytes = 64 * 1024
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var nickname = "netsplit"
    private var advertisedCapabilities = Set<String>()
    private var capabilityNegotiationEnded = false
    private var serverPassword: String?
    private var saslCredentials: (username: String, password: String)?
    private var isWaitingForSASLResponse = false
    var eventHandler: (@MainActor (IRCTransportEvent) -> Void)?

    func connect(profile: ServerProfile, nickname: String, realName: String, serverPassword: String, saslUsername: String?, saslPassword: String) {
        disconnect()
        self.nickname = nickname
        advertisedCapabilities.removeAll()
        capabilityNegotiationEnded = false
        isWaitingForSASLResponse = false
        self.serverPassword = serverPassword.isEmpty ? nil : serverPassword
        if profile.useSASL == true, !saslPassword.isEmpty {
            self.saslCredentials = (saslUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? saslUsername!.trimmingCharacters(in: .whitespacesAndNewlines) : nickname, saslPassword)
        } else {
            self.saslCredentials = nil
        }
        let parameters: NWParameters
        if profile.useTLS {
            let tls = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }
        guard let port = NWEndpoint.Port(rawValue: profile.port) else {
            eventHandler?(.status(.failed("Invalid port")))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(profile.hostname), port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .setup, .preparing: self?.eventHandler?(.status(.connecting))
                case .ready:
                    self?.eventHandler?(.status(.online))
                    self?.register(nickname: nickname, realName: realName)
                    self?.receiveNext()
                case .failed(let error): self?.eventHandler?(.status(.failed(error.localizedDescription)))
                case .cancelled: self?.eventHandler?(.status(.offline))
                default: break
                }
            }
        }
        eventHandler?(.status(.connecting))
        connection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
    }

    /// Sends IRC QUIT and only closes the transport after Network.framework has
    /// accepted the line. This gives the server a chance to remove the client
    /// cleanly instead of treating a user-initiated disconnect as a dropped link.
    func quit(reason: String, completion: @MainActor @escaping () -> Void = {}) {
        guard let connection else {
            completion()
            return
        }

        let safeReason = reason
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let boundedCommand = Self.prefix("QUIT :\(safeReason)", fittingUTF8ByteCount: Self.maximumOutboundLineBytes)
        let line = "\(boundedCommand)\r\n"
        connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self, weak connection] _ in
            Task { @MainActor [weak self, weak connection] in
                connection?.cancel()
                self?.connection = nil
                self?.receiveBuffer.removeAll()
                completion()
            }
        })
    }

    func send(command: String, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let connection else {
            completion?(false)
            return
        }
        let singleLine = command
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let boundedCommand = Self.prefix(singleLine, fittingUTF8ByteCount: Self.maximumOutboundLineBytes)
        if boundedCommand != singleLine {
            eventHandler?(.notice("An outgoing IRC command exceeded the server line limit and was truncated."))
        }
        let line = boundedCommand + "\r\n"
        connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.eventHandler?(.notice("Send failed: \(error.localizedDescription)"))
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

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !self.process(data) { return }
                if let error {
                    self.eventHandler?(.status(.failed(error.localizedDescription)))
                } else if isComplete {
                    self.eventHandler?(.status(.offline))
                } else {
                    self.receiveNext()
                }
            }
        }
    }

    @discardableResult
    private func process(_ data: Data) -> Bool {
        receiveBuffer.append(data)
        while let range = receiveBuffer.range(of: Data([13, 10])) {
            guard range.lowerBound <= Self.maximumBufferedLineBytes else {
                failMalformedInput("The server sent an IRC line larger than 64 KB.")
                return false
            }
            let lineData = receiveBuffer.subdata(in: 0..<range.lowerBound)
            receiveBuffer.removeSubrange(0..<range.upperBound)
            // IRC commands are ASCII, but legacy networks can include text in a
            // different encoding. Preserve the command and replace only invalid
            // payload bytes instead of silently discarding the entire line.
            let line = String(decoding: lineData, as: UTF8.self)
            guard let message = IRCWireMessage(line: line) else { continue }
            if message.command == "PING" { send(command: "PONG :\(message.trailing ?? message.parameters.first ?? "")") }
            if message.command == "CAP" {
                handleCapabilityMessage(message)
            }
            if message.command == "AUTHENTICATE" {
                handleAuthenticationMessage(message)
            }
            handleSASLNumeric(message)
            eventHandler?(.received(message))
        }
        guard receiveBuffer.count <= Self.maximumBufferedLineBytes else {
            failMalformedInput("The server sent more than 64 KB without terminating an IRC line.")
            return false
        }
        return true
    }

    private func failMalformedInput(_ message: String) {
        eventHandler?(.notice(message))
        eventHandler?(.status(.failed(message)))
        disconnect()
    }

    private static func prefix(_ value: String, fittingUTF8ByteCount limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var result = ""
        var byteCount = 0
        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= limit else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }

    private func handleCapabilityMessage(_ message: IRCWireMessage) {
        // CAP replies are normally: CAP <nick|*> <LS|ACK|NAK> [*] :capabilities
        guard message.parameters.count >= 2 else { return }
        let subcommand = message.parameters[1].uppercased()
        switch subcommand {
        case "LS":
            let capabilities = (message.trailing ?? "").split(separator: " ").map { capabilityName(String($0)) }
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
            let acknowledged = (message.trailing ?? "").split(separator: " ").map { capabilityName(String($0)) }
            if acknowledged.contains("sasl"), saslCredentials != nil {
                send(command: "AUTHENTICATE PLAIN")
            } else {
                endCapabilityNegotiation()
            }
        case "NAK":
            if saslCredentials != nil, (message.trailing ?? "").split(separator: " ").map({ capabilityName(String($0)) }).contains("sasl") {
                eventHandler?(.notice("The server declined SASL authentication."))
            }
            endCapabilityNegotiation()
        default:
            break
        }
    }

    private func capabilityName(_ advertised: String) -> String {
        String(advertised.drop(while: { $0 == "-" }).split(separator: "=", maxSplits: 1).first ?? "")
    }

    private func endCapabilityNegotiation() {
        guard !capabilityNegotiationEnded else { return }
        capabilityNegotiationEnded = true
        send(command: "CAP END")
    }

    private func handleAuthenticationMessage(_ message: IRCWireMessage) {
        guard message.parameters.first == "+", let credentials = saslCredentials, !isWaitingForSASLResponse else { return }
        isWaitingForSASLResponse = true
        let payload = Data(([0] + Array(credentials.username.utf8) + [0] + Array(credentials.password.utf8))).base64EncodedString()
        let chunks = stride(from: 0, to: payload.count, by: 400).map { start in
            String(payload.dropFirst(start).prefix(400))
        }
        chunks.forEach { send(command: "AUTHENTICATE \($0)") }
        if payload.count.isMultiple(of: 400) { send(command: "AUTHENTICATE +") }
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
