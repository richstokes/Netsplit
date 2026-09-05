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

struct IRCSASLCredentials: Equatable {
    var username: String
    var password: String
}

enum IRCSASLNegotiationState: Equatable {
    case pending(IRCSASLCredentials)
    case responseSent(IRCSASLCredentials)

    var credentials: IRCSASLCredentials {
        switch self {
        case .pending(let credentials), .responseSent(let credentials):
            credentials
        }
    }
}

struct IRCAdvertisedCapabilities: Equatable {
    var names = Set<String>()
    var values: [String: String] = [:]
    var saslMechanisms: Set<String>?

    mutating func apply(_ advertisedValues: [String]) {
        for advertisedValue in advertisedValues {
            let advertisement = IRCCapability.advertisement(from: advertisedValue)
            guard !advertisement.name.isEmpty else { continue }
            names.insert(advertisement.name)
            if let value = advertisement.value {
                values[advertisement.name] = value
            } else {
                values.removeValue(forKey: advertisement.name)
            }
            if advertisement.name == "sasl" {
                saslMechanisms = IRCCapability.saslMechanisms(from: advertisedValue)
            }
        }
    }

    mutating func remove(_ capabilityNames: Set<String>) {
        names.subtract(capabilityNames)
        capabilityNames.forEach { values.removeValue(forKey: $0) }
        if capabilityNames.contains("sasl") {
            saslMechanisms = nil
        }
    }
}

enum IRCCapabilityNegotiationState: Equatable {
    case active(
        IRCAdvertisedCapabilities,
        enabled: Set<String>,
        sasl: IRCSASLNegotiationState?
    )
    case ended(
        IRCAdvertisedCapabilities,
        enabled: Set<String>,
        sasl: IRCSASLNegotiationState?
    )

    var advertised: IRCAdvertisedCapabilities {
        switch self {
        case .active(let advertised, _, _), .ended(let advertised, _, _):
            advertised
        }
    }

    var enabled: Set<String> {
        switch self {
        case .active(_, let enabled, _), .ended(_, let enabled, _):
            enabled
        }
    }

    var sasl: IRCSASLNegotiationState? {
        switch self {
        case .active(_, _, let sasl), .ended(_, _, let sasl):
            sasl
        }
    }

    func replacingAdvertised(_ advertised: IRCAdvertisedCapabilities) -> Self {
        switch self {
        case .active(_, let enabled, let sasl):
            .active(advertised, enabled: enabled, sasl: sasl)
        case .ended(_, let enabled, let sasl):
            .ended(advertised, enabled: enabled, sasl: sasl)
        }
    }

    func replacingEnabled(_ enabled: Set<String>) -> Self {
        switch self {
        case .active(let advertised, _, let sasl):
            .active(advertised, enabled: enabled, sasl: sasl)
        case .ended(let advertised, _, let sasl):
            .ended(advertised, enabled: enabled, sasl: sasl)
        }
    }

    func acknowledging(_ capabilityTokens: [String]) -> Self {
        var nextEnabled = enabled
        var removed = Set<String>()
        for token in capabilityTokens {
            let name = IRCCapability.name(from: token)
            guard !name.isEmpty else { continue }
            if token.hasPrefix("-") {
                nextEnabled.remove(name)
                removed.insert(name)
            } else {
                nextEnabled.insert(name)
            }
        }
        nextEnabled = IRCCapability.enabledCapabilities(
            afterRemoving: removed,
            from: nextEnabled
        )
        return replacingEnabled(nextEnabled)
    }

    func removing(_ capabilityNames: Set<String>) -> Self {
        // cap-notify is implicit and cannot be disabled after CAP LS 302.
        let removableNames = capabilityNames.subtracting(["cap-notify"])
        var nextAdvertised = advertised
        nextAdvertised.remove(removableNames)
        var nextState = replacingAdvertised(nextAdvertised)
            .replacingEnabled(IRCCapability.enabledCapabilities(
                afterRemoving: removableNames,
                from: enabled
            ))
        if removableNames.contains("sasl"), let sasl {
            nextState = nextState.replacingSASL(.pending(sasl.credentials))
        }
        return nextState
    }

    func replacingSASL(_ nextSASL: IRCSASLNegotiationState?) -> Self {
        switch self {
        case .active(let advertised, let enabled, _):
            .active(advertised, enabled: enabled, sasl: nextSASL)
        case .ended(let advertised, let enabled, _):
            .ended(advertised, enabled: enabled, sasl: nextSASL)
        }
    }

    func ending() -> Self {
        switch self {
        case .active(let advertised, let enabled, let sasl):
            .ended(advertised, enabled: enabled, sasl: sasl)
        case .ended:
            self
        }
    }

    func markingSASLResponseSent() -> Self? {
        guard enabled.contains("sasl") else { return nil }
        return switch self {
        case .active(let advertised, let enabled, .pending(let credentials)):
            .active(advertised, enabled: enabled, sasl: .responseSent(credentials))
        case .ended(let advertised, let enabled, .pending(let credentials)):
            .ended(advertised, enabled: enabled, sasl: .responseSent(credentials))
        case .active(_, _, .responseSent), .active(_, _, nil),
             .ended(_, _, .responseSent), .ended(_, _, nil):
            nil
        }
    }
}

struct IRCRegistrationState: Equatable {
    var serverPassword: String?
    var capabilityNegotiation: IRCCapabilityNegotiationState

    init(serverPassword: String?, saslCredentials: IRCSASLCredentials?) {
        self.serverPassword = serverPassword
        capabilityNegotiation = .active(
            IRCAdvertisedCapabilities(),
            // CAP LS 302 implicitly enables cap-notify for the connection.
            enabled: ["cap-notify"],
            sasl: saslCredentials.map(IRCSASLNegotiationState.pending)
        )
    }
}

enum IRCTransport {
    case direct(NWConnection)
    case ssh(SSHTunnelConnection)

    var identifier: IRCTransportIdentifier {
        switch self {
        case .direct(let connection):
            .direct(ObjectIdentifier(connection))
        case .ssh(let tunnel):
            .ssh(ObjectIdentifier(tunnel))
        }
    }

    func close() {
        switch self {
        case .direct(let connection):
            connection.cancel()
        case .ssh(let tunnel):
            tunnel.close()
        }
    }
}

enum IRCTransportIdentifier: Equatable {
    case direct(ObjectIdentifier)
    case ssh(ObjectIdentifier)
}

enum IRCRegistrationProgress: Equatable {
    case connectingTransport
    case registering
    case ready
}

struct IRCConnectionSession {
    var transport: IRCTransport
    var registration: IRCRegistrationState
}

struct IRCQuitContext {
    var generation: UUID
    var timeoutGeneration: UUID?
    var completion: @MainActor () -> Void
}

enum IRCQuitPhase {
    case writing(IRCQuitContext)
    case waitingForPeer(IRCQuitContext)

    var context: IRCQuitContext {
        switch self {
        case .writing(let context), .waitingForPeer(let context):
            context
        }
    }

    func handling(_ event: IRCGracefulQuitEvent, timeoutGeneration: UUID?) -> Self {
        var context = context
        context.timeoutGeneration = timeoutGeneration
        switch event {
        case .localWriteSucceeded:
            return .waitingForPeer(context)
        case .started, .localWriteFailed, .peerClosed, .timedOut:
            return self.replacingContext(context)
        }
    }

    private func replacingContext(_ context: IRCQuitContext) -> Self {
        switch self {
        case .writing:
            .writing(context)
        case .waitingForPeer:
            .waitingForPeer(context)
        }
    }
}

struct IRCQuittingConnection {
    var progress: IRCRegistrationProgress
    var transport: IRCTransport?
    var registration: IRCRegistrationState
    var quit: IRCQuitPhase
    var failureMessage: String?
}

enum IRCConnectionFailure {
    case disconnected(String)
    case connected(String, previousProgress: IRCRegistrationProgress, IRCConnectionSession)

    var message: String {
        switch self {
        case .disconnected(let message), .connected(let message, _, _):
            message
        }
    }
}

enum IRCConnectionPhase {
    case idle
    case connectingTransport(IRCConnectionSession)
    case registering(IRCConnectionSession)
    case ready(IRCConnectionSession)
    case quitting(IRCQuittingConnection)
    case failed(IRCConnectionFailure)

    var transport: IRCTransport? {
        switch self {
        case .idle, .failed(.disconnected):
            nil
        case .connectingTransport(let session),
             .registering(let session),
             .ready(let session),
             .failed(.connected(_, _, let session)):
            session.transport
        case .quitting(let connection):
            connection.transport
        }
    }

    var transportIdentifier: IRCTransportIdentifier? {
        transport?.identifier
    }

    var registration: IRCRegistrationState? {
        switch self {
        case .idle, .failed(.disconnected):
            nil
        case .connectingTransport(let session),
             .registering(let session),
             .ready(let session),
             .failed(.connected(_, _, let session)):
            session.registration
        case .quitting(let connection):
            connection.registration
        }
    }

    var quitContext: IRCQuitContext? {
        guard case .quitting(let connection) = self else { return nil }
        return connection.quit.context
    }

    var canReportFailure: Bool {
        switch self {
        case .failed:
            false
        case .quitting(let connection):
            connection.failureMessage == nil
        case .idle, .connectingTransport, .registering, .ready:
            true
        }
    }

    var canMonitorViability: Bool {
        switch self {
        case .registering, .ready:
            true
        case .quitting(let connection):
            connection.progress != .connectingTransport && connection.failureMessage == nil
        case .idle, .connectingTransport, .failed:
            false
        }
    }

    var canRunConnectionTimeout: Bool {
        switch self {
        case .connectingTransport:
            true
        case .quitting(let connection):
            connection.progress == .connectingTransport
                && connection.transport != nil
                && connection.failureMessage == nil
        case .idle, .registering, .ready, .failed:
            false
        }
    }

    var canRunRegistrationTimeout: Bool {
        switch self {
        case .connectingTransport, .registering, .ready:
            true
        case .quitting(let connection):
            connection.transport != nil && connection.failureMessage == nil
        case .idle, .failed:
            false
        }
    }

    var canRunHeartbeat: Bool {
        switch self {
        case .connectingTransport, .registering, .ready:
            true
        case .quitting(let connection):
            connection.transport != nil && connection.failureMessage == nil
        case .idle, .failed:
            false
        }
    }

    func replacingRegistration(_ registration: IRCRegistrationState) -> Self {
        switch self {
        case .idle, .failed(.disconnected):
            return self
        case .connectingTransport(var session):
            session.registration = registration
            return .connectingTransport(session)
        case .registering(var session):
            session.registration = registration
            return .registering(session)
        case .ready(var session):
            session.registration = registration
            return .ready(session)
        case .quitting(var connection):
            connection.registration = registration
            return .quitting(connection)
        case .failed(.connected(let message, let progress, var session)):
            session.registration = registration
            return .failed(.connected(message, previousProgress: progress, session))
        }
    }

    func transportBecameReady(
        repeatingRegistration: Bool = false
    ) -> (phase: Self, shouldBeginRegistration: Bool) {
        switch self {
        case .connectingTransport(let session):
            return (.registering(session), true)
        case .registering, .ready:
            return (self, repeatingRegistration)
        case .idle, .failed(.disconnected):
            return (self, false)
        case .quitting(var connection):
            if connection.progress == .connectingTransport {
                connection.progress = .registering
                return (.quitting(connection), true)
            }
            return (self, repeatingRegistration)
        case .failed(.connected(let message, let progress, let session)):
            if progress == .connectingTransport {
                return (
                    .failed(.connected(message, previousProgress: .registering, session)),
                    true
                )
            }
            return (self, repeatingRegistration)
        }
    }

    func registrationCompleted() -> Self {
        switch self {
        case .registering(let session):
            return .ready(session)
        case .quitting(var connection):
            connection.progress = .ready
            return .quitting(connection)
        case .failed(.connected(let message, _, let session)):
            return .failed(.connected(message, previousProgress: .ready, session))
        case .idle, .connectingTransport, .ready, .failed(.disconnected):
            return self
        }
    }

    func beginningQuit(_ quit: IRCQuitPhase) -> Self? {
        switch self {
        case .connectingTransport(let session):
            .quitting(
                IRCQuittingConnection(
                    progress: .connectingTransport,
                    transport: session.transport,
                    registration: session.registration,
                    quit: quit,
                    failureMessage: nil
                )
            )
        case .registering(let session):
            .quitting(
                IRCQuittingConnection(
                    progress: .registering,
                    transport: session.transport,
                    registration: session.registration,
                    quit: quit,
                    failureMessage: nil
                )
            )
        case .ready(let session):
            .quitting(
                IRCQuittingConnection(
                    progress: .ready,
                    transport: session.transport,
                    registration: session.registration,
                    quit: quit,
                    failureMessage: nil
                )
            )
        case .failed(.connected(let message, let progress, let session)):
            .quitting(
                IRCQuittingConnection(
                    progress: progress,
                    transport: session.transport,
                    registration: session.registration,
                    quit: quit,
                    failureMessage: message
                )
            )
        case .idle, .quitting, .failed(.disconnected):
            nil
        }
    }

    func reportingFailure(
        _ message: String,
        cancellingTransport: Bool
    ) -> Self {
        switch self {
        case .idle:
            return .failed(.disconnected(message))
        case .connectingTransport(let session):
            return Self.failure(
                message,
                progress: .connectingTransport,
                session: session,
                cancellingTransport: cancellingTransport
            )
        case .registering(let session):
            return Self.failure(
                message,
                progress: .registering,
                session: session,
                cancellingTransport: cancellingTransport
            )
        case .ready(let session):
            return Self.failure(
                message,
                progress: .ready,
                session: session,
                cancellingTransport: cancellingTransport
            )
        case .quitting(var connection):
            guard connection.failureMessage == nil else { return self }
            connection.failureMessage = message
            if cancellingTransport,
               case .ssh = connection.transport {
                connection.transport = nil
            }
            return .quitting(connection)
        case .failed:
            return self
        }
    }

    func removingTransport() -> Self {
        switch self {
        case .failed(.connected(let message, _, _)):
            return .failed(.disconnected(message))
        case .quitting(var connection):
            connection.transport = nil
            return .quitting(connection)
        case .idle, .failed(.disconnected):
            return self
        case .connectingTransport, .registering, .ready:
            return .idle
        }
    }

    func resetting() -> Self {
        .idle
    }

    func wakeRecoveryAction(isViable: Bool?) -> IRCWakeRecoveryAction {
        switch self {
        case .idle, .failed:
            return .none
        case .connectingTransport:
            return .resumeConnectionTimeout
        case .registering:
            return .resumeRegistrationTimeout
        case .ready:
            return isViable == false ? .waitForViability : .probeEstablishedConnection
        case .quitting(let connection):
            guard connection.transport != nil, connection.failureMessage == nil else {
                return .none
            }
            switch connection.progress {
            case .connectingTransport:
                return .resumeConnectionTimeout
            case .registering:
                return .resumeRegistrationTimeout
            case .ready:
                return isViable == false ? .waitForViability : .probeEstablishedConnection
            }
        }
    }

    private static func failure(
        _ message: String,
        progress: IRCRegistrationProgress,
        session: IRCConnectionSession,
        cancellingTransport: Bool
    ) -> Self {
        if cancellingTransport, case .ssh = session.transport {
            return .failed(.disconnected(message))
        }
        return .failed(.connected(message, previousProgress: progress, session))
    }
}

struct IRCWireMessage {
    var tags: [String: String?]
    var prefix: String?
    var command: String
    var parameters: [String]
    var trailing: String?

    /// Parameters have the same meaning whether the final value uses a colon or not.
    /// Keep the original wire fields available for framing and expose semantic access here.
    func parameter(at index: Int) -> String? {
        guard index >= 0 else { return nil }
        if index < parameters.count { return parameters[index] }
        return index == parameters.count ? trailing : nil
    }

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
                let unescapedValue = pair.count == 2
                    ? Self.unescapeTagValue(String(pair[1]))
                    : nil
                // IRCv3 requires `key=` to have the same meaning as `key`.
                // Preserve the key while normalizing both forms to a nil value;
                // this also ensures a final empty duplicate replaces an earlier
                // non-empty value rather than removing the dictionary entry.
                let value = unescapedValue?.isEmpty == true ? nil : unescapedValue
                tags[key] = .some(value)
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
    private var phase = IRCConnectionPhase.idle
    private var receiveBuffer = IRCLineBuffer(maximumLineBytes: maximumBufferedLineBytes)
    private var heartbeatGeneration: UUID?
    private var pendingHeartbeatToken: String?
    private var connectionTimeoutGeneration: UUID?
    private var lastConnectionAttemptError: String?
    private var registrationTimeoutGeneration: UUID?
    private var viabilityFailureGeneration: UUID?
    private var wakeRecoveryGeneration: UUID?
    private var isSystemSleeping = false
    private var isAwaitingWakeRecovery = false
    private var isConnectionViable: Bool?
    private var heartbeatIsWakeProbe = false
    private var diagnosticEndpoint = "unknown"
    private var nickname = "netsplit"
    private var maximumOutboundLineBytes = IRCTextFraming.maximumLineBytes
    var eventHandler: (@MainActor (IRCTransportEvent) -> Void)?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Netsplit",
        category: "IRCConnection"
    )

    func isCapabilityEnabled(_ name: String) -> Bool {
        phase.registration?.capabilityNegotiation.enabled.contains(name) == true
    }

    func connect(profile: ServerProfile, nickname: String, realName: String, serverPassword: String, saslUsername: String?, saslPassword: String, sshPassword: String, sshPrivateKey: String) {
        disconnect()
        diagnosticEndpoint = "\(profile.hostname):\(profile.port)"
        self.nickname = nickname
        maximumOutboundLineBytes = IRCTextFraming.maximumLineBytes
        isSystemSleeping = false
        isAwaitingWakeRecovery = false
        isConnectionViable = nil
        heartbeatIsWakeProbe = false
        guard IRCIdentityValidation.isValidNickname(nickname) else {
            let message = IRCIdentityValidation.nicknameError(nickname) ?? "The configured nickname is invalid."
            phase = .failed(.disconnected(message))
            eventHandler?(.terminalFailure(message))
            return
        }
        guard profile.useSASL != true || !saslPassword.isEmpty else {
            let message = "SASL is enabled for this profile, but no SASL password is configured."
            phase = .failed(.disconnected(message))
            eventHandler?(.terminalFailure(message))
            return
        }
        let credentials: IRCSASLCredentials?
        if profile.useSASL == true, !saslPassword.isEmpty {
            let username: String
            if let saslUsername = saslUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
               !saslUsername.isEmpty {
                username = saslUsername
            } else {
                username = nickname
            }
            credentials = IRCSASLCredentials(username: username, password: saslPassword)
        } else {
            credentials = nil
        }
        let registration = IRCRegistrationState(
            serverPassword: serverPassword.isEmpty ? nil : serverPassword,
            saslCredentials: credentials
        )

        if profile.useSSHTunnel == true {
            guard let sshHostname = profile.sshHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshHostname.isEmpty,
                  let sshUsername = profile.sshUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshUsername.isEmpty else {
                let message = "The SSH hostname and username are required."
                phase = .failed(.disconnected(message))
                eventHandler?(.terminalFailure(message))
                return
            }
            let tunnel = SSHTunnelConnection()
            phase = .connectingTransport(
                IRCConnectionSession(transport: .ssh(tunnel), registration: registration)
            )
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
                    guard let self,
                          let tunnel,
                          self.phase.transportIdentifier == .ssh(ObjectIdentifier(tunnel)) else {
                        return
                    }
                    let transition = self.phase.transportBecameReady(
                        repeatingRegistration: true
                    )
                    self.phase = transition.phase
                    self.stopConnectionTimeout()
                    self.eventHandler?(.status(.online))
                    if transition.shouldBeginRegistration {
                        self.register(nickname: nickname, realName: realName)
                        self.startRegistrationTimeout()
                    }
                },
                onData: { [weak self, weak tunnel] data in
                    guard let self,
                          let tunnel,
                          self.phase.transportIdentifier == .ssh(ObjectIdentifier(tunnel)) else {
                        return
                    }
                    _ = self.process(data)
                },
                onClose: { [weak self, weak tunnel] error in
                    guard let self,
                          let tunnel,
                          self.phase.transportIdentifier == .ssh(ObjectIdentifier(tunnel)) else {
                        return
                    }
                    // The tunnel wrapper begins closing both the forwarded
                    // channel and its parent SSH session before this callback.
                    self.phase = self.phase.removingTransport()
                    self.stopHeartbeat()
                    if self.handleQuitEvent(.peerClosed) { return }
                    if let error {
                        Self.logger.error(
                            "SSH tunnel underlying failure endpoint=\(self.diagnosticEndpoint, privacy: .public) error=\(String(reflecting: error), privacy: .public)"
                        )
                        let preventsReconnect = (error as? SSHTunnelError)?.preventsAutomaticReconnect == true
                        self.reportFailure(
                            "SSH tunnel failed: \(error.localizedDescription)",
                            reason: .sshTransport,
                            cancelling: false,
                            automaticallyReconnect: !preventsReconnect
                        )
                    } else if self.phase.canReportFailure {
                        self.reportFailure(
                            "SSH tunnel closed.",
                            reason: .remoteClose,
                            cancelling: false
                        )
                    }
                },
                onHostKeyLearned: { [weak self, weak tunnel] key in
                    guard let self,
                          let tunnel,
                          self.phase.transportIdentifier == .ssh(ObjectIdentifier(tunnel)) else {
                        return
                    }
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
            let message = "Invalid port"
            phase = .failed(.disconnected(message))
            eventHandler?(.terminalFailure(message))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(profile.hostname), port: port, using: parameters)
        phase = .connectingTransport(
            IRCConnectionSession(transport: .direct(connection), registration: registration)
        )
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      let connection,
                      self.phase.transportIdentifier == .direct(ObjectIdentifier(connection)) else {
                    return
                }
                switch state {
                case .setup, .preparing: self.eventHandler?(.status(.connecting))
                case .waiting(let error):
                    // A waiting connection may recover on its own. Keep it
                    // alive until the setup watchdog expires, while retaining
                    // the most useful error for the eventual UI message.
                    self.lastConnectionAttemptError = error.localizedDescription
                    self.eventHandler?(.status(.connecting))
                case .ready:
                    let transition = self.phase.transportBecameReady()
                    self.phase = transition.phase
                    self.stopConnectionTimeout()
                    self.eventHandler?(.status(.online))
                    if transition.shouldBeginRegistration {
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
                        self.phase = self.phase.removingTransport()
                        if self.phase.canReportFailure {
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
                      self.phase.transportIdentifier == .direct(ObjectIdentifier(connection)) else {
                    return
                }
                self.handleViabilityChange(isViable)
            }
        }
        eventHandler?(.status(.connecting))
        startConnectionTimeout()
        connection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        if case .quitting = phase {
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
        let action = phase.wakeRecoveryAction(isViable: isConnectionViable)
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

        guard phase.canMonitorViability,
              !isSystemSleeping else { return }
        scheduleViabilityFailure()
    }

    private func scheduleViabilityFailure() {
        guard isConnectionViable == false,
              phase.canMonitorViability,
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
        let transport = phase.transport
        phase = phase.resetting()
        transport?.close()
        receiveBuffer.removeAll()
    }

    /// Sends IRC QUIT and keeps the transport open until the server closes its
    /// side of the IRC session. A bounded timeout still guarantees completion if
    /// the peer does not respond to QUIT with an orderly close.
    func quit(reason: String, completion: @MainActor @escaping () -> Void = {}) {
        if case .quitting = phase {
            completion()
            return
        }
        guard let transport = phase.transport else {
            completion()
            return
        }

        stopHeartbeat()
        stopRegistrationTimeout()
        let generation = UUID()
        let quit = IRCQuitPhase.writing(
            IRCQuitContext(
                generation: generation,
                timeoutGeneration: nil,
                completion: completion
            )
        )
        guard let quittingPhase = phase.beginningQuit(quit) else {
            completion()
            return
        }
        phase = quittingPhase
        _ = handleQuitEvent(.started, generation: generation)

        switch transport {
        case .ssh(let sshTunnel):
            let safeReason = reason
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let boundedCommand = IRCTextFraming.prefix(
                "QUIT :\(safeReason)",
                fittingUTF8ByteCount: maximumOutboundLineBytes
            )
            sshTunnel.send(Data("\(boundedCommand)\r\n".utf8)) { [weak self, weak sshTunnel] sent, error in
                guard let self,
                      let sshTunnel,
                      self.phase.quitContext?.generation == generation,
                      self.phase.transportIdentifier == .ssh(ObjectIdentifier(sshTunnel)) else {
                    return
                }
                let event: IRCGracefulQuitEvent = sent && error == nil ? .localWriteSucceeded : .localWriteFailed
                _ = self.handleQuitEvent(event, generation: generation)
            }
        case .direct(let connection):
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
                          let connection,
                          self.phase.quitContext?.generation == generation,
                          self.phase.transportIdentifier == .direct(ObjectIdentifier(connection)) else {
                        return
                    }
                    let event: IRCGracefulQuitEvent = error == nil ? .localWriteSucceeded : .localWriteFailed
                    _ = self.handleQuitEvent(event, generation: generation)
                }
            })
        }
    }

    @discardableResult
    private func handleQuitEvent(_ event: IRCGracefulQuitEvent, generation: UUID? = nil) -> Bool {
        guard case .quitting(var connection) = phase else { return false }
        let context = connection.quit.context
        let activeGeneration = context.generation
        guard generation == nil || generation == activeGeneration else { return false }
        if let timeout = IRCGracefulQuitPolicy.timeout(after: event) {
            let timeoutGeneration = UUID()
            connection.quit = connection.quit.handling(
                event,
                timeoutGeneration: timeoutGeneration
            )
            phase = .quitting(connection)
            // This closure deliberately retains the transport until its deadline.
            // The initial watchdog bounds a stalled write; after a successful
            // write, a fresh grace period gives the peer time to close cleanly.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in
                guard phase.quitContext?.timeoutGeneration == timeoutGeneration else { return }
                _ = handleQuitEvent(.timedOut, generation: activeGeneration)
            }
        }
        if IRCGracefulQuitPolicy.shouldFinish(after: event) {
            finishQuit(generation: activeGeneration)
        }
        return true
    }

    private func finishQuit(generation: UUID? = nil) {
        guard let context = phase.quitContext,
              generation == nil || generation == context.generation else { return }
        let completion = context.completion
        closeTransport()
        completion()
    }

    func send(command: String, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let transport = phase.transport else {
            completion?(false)
            return
        }
        let boundedCommand: String
        switch IRCOutboundCommandFraming.frame(
            command,
            maximumMessageBytes: maximumOutboundLineBytes
        ) {
        case .tagsTooLong:
            eventHandler?(.notice("Outgoing IRC message tags exceeded the IRCv3 byte limit."))
            completion?(false)
            return
        case .framed(let command, let wasTruncated):
            boundedCommand = command
            if wasTruncated {
                eventHandler?(.notice("An outgoing IRC command exceeded the server line limit and was truncated."))
            }
        }
        let line = boundedCommand + "\r\n"
        switch transport {
        case .ssh(let sshTunnel):
            sshTunnel.send(Data(line.utf8)) { [weak self, weak sshTunnel] sent, error in
                guard let self,
                      let sshTunnel,
                      self.phase.transportIdentifier == .ssh(ObjectIdentifier(sshTunnel)) else {
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
        case .direct(let connection):
            connection.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self, weak connection] error in
                Task { @MainActor [weak self, weak connection] in
                    guard let self,
                          let connection,
                          self.phase.transportIdentifier == .direct(ObjectIdentifier(connection)) else {
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
        if let serverPassword = phase.registration?.serverPassword {
            send(command: "PASS :\(serverPassword.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))")
        }
        send(command: "CAP LS 302")
        send(command: "NICK \(nickname)")
        send(command: "USER \(nickname) 0 * :\(safeRealName)")
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            Task { @MainActor [weak self, weak connection] in
                guard let self,
                      let connection,
                      self.phase.transportIdentifier == .direct(ObjectIdentifier(connection)) else {
                    return
                }
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
                        self.phase = self.phase.removingTransport()
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
                phase = phase.registrationCompleted()
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
                  self.phase.canRunHeartbeat else { return }
            self.sendHeartbeatProbe(generation: generation)
        }
    }

    private func sendHeartbeatProbe(generation: UUID) {
        guard heartbeatGeneration == generation,
              phase.canRunHeartbeat,
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
                  self.phase.canRunConnectionTimeout else { return }
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
                  self.phase.canRunRegistrationTimeout else { return }
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
        guard phase.canReportFailure else { return }
        let transport = phase.transport
        phase = phase.reportingFailure(message, cancellingTransport: cancelling)
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
            transport?.close()
        }
    }

    private func handleCapabilityMessage(_ message: IRCWireMessage) {
        // CAP replies are normally: CAP <nick|*> <LS|ACK|NAK> [*] :capabilities
        guard message.parameters.count >= 2,
              var registration = phase.registration else { return }
        let subcommand = message.parameters[1].uppercased()
        switch subcommand {
        case "LS":
            let advertisedValues = (message.trailing ?? "").split(separator: " ").map(String.init)
            var advertised = registration.capabilityNegotiation.advertised
            advertised.apply(advertisedValues)
            registration.capabilityNegotiation =
                registration.capabilityNegotiation.replacingAdvertised(advertised)
            phase = phase.replacingRegistration(registration)
            // An asterisk after LS signals a multi-line capability list.
            let hasMore = message.parameters.dropFirst(2).contains("*")
            guard !hasMore else { return }
            var supported = IRCCapability.requestablePreferred(
                advertised: advertised.names,
                enabled: registration.capabilityNegotiation.enabled
            )
            if registration.capabilityNegotiation.sasl != nil {
                if advertised.names.contains("sasl"),
                   IRCSASL.canUsePlain(advertisedMechanisms: advertised.saslMechanisms) {
                    supported.append("sasl")
                } else if advertised.names.contains("sasl") {
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
            let acknowledgedTokens = (message.trailing ?? "").split(separator: " ").map(String.init)
            registration.capabilityNegotiation =
                registration.capabilityNegotiation.acknowledging(acknowledgedTokens)
            phase = phase.replacingRegistration(registration)
            let acknowledgedSASL = acknowledgedTokens.contains {
                !$0.hasPrefix("-") && IRCCapability.name(from: $0) == "sasl"
            }
            if acknowledgedSASL,
               registration.capabilityNegotiation.sasl != nil {
                send(command: "AUTHENTICATE PLAIN")
            } else {
                endCapabilityNegotiation()
            }
        case "NAK":
            if registration.capabilityNegotiation.sasl != nil,
               (message.trailing ?? "").split(separator: " ").map({
                   IRCCapability.name(from: String($0))
               }).contains("sasl") {
                eventHandler?(.notice("The server declined SASL authentication."))
            }
            endCapabilityNegotiation()
        case "NEW":
            let advertisedValues = (message.trailing ?? "").split(separator: " ").map(String.init)
            let newNames = Set(advertisedValues.map { IRCCapability.name(from: $0) })
            var advertised = registration.capabilityNegotiation.advertised
            advertised.apply(advertisedValues)
            registration.capabilityNegotiation =
                registration.capabilityNegotiation.replacingAdvertised(advertised)
            phase = phase.replacingRegistration(registration)

            var requested = IRCCapability.requestablePreferred(
                advertised: advertised.names,
                enabled: registration.capabilityNegotiation.enabled
            )
            if newNames.contains("sasl"),
               registration.capabilityNegotiation.sasl != nil,
               !registration.capabilityNegotiation.enabled.contains("sasl"),
               IRCSASL.canUsePlain(advertisedMechanisms: advertised.saslMechanisms) {
                requested.append("sasl")
            }
            if !requested.isEmpty {
                send(command: "CAP REQ :\(requested.joined(separator: " "))")
            }
        case "DEL":
            let removed = Set(
                (message.trailing ?? "").split(separator: " ").map {
                    IRCCapability.name(from: String($0))
                }
            )
            registration.capabilityNegotiation =
                registration.capabilityNegotiation.removing(removed)
            phase = phase.replacingRegistration(registration)
        default:
            break
        }
    }

    private func endCapabilityNegotiation() {
        guard var registration = phase.registration else { return }
        guard case .active = registration.capabilityNegotiation else { return }
        registration.capabilityNegotiation = registration.capabilityNegotiation.ending()
        phase = phase.replacingRegistration(registration)
        send(command: "CAP END")
    }

    private func handleAuthenticationMessage(_ message: IRCWireMessage) {
        guard message.isSASLContinuation,
              var registration = phase.registration,
              let nextNegotiation = registration.capabilityNegotiation.markingSASLResponseSent() else {
            return
        }
        let credentials = nextNegotiation.sasl?.credentials
        registration.capabilityNegotiation = nextNegotiation
        phase = phase.replacingRegistration(registration)
        guard let credentials else { return }
        IRCSASL.plainAuthenticationChunks(username: credentials.username, password: credentials.password)
            .forEach { send(command: "AUTHENTICATE \($0)") }
    }

    private func handleSASLNumeric(_ message: IRCWireMessage) {
        guard let negotiation = phase.registration?.capabilityNegotiation,
              negotiation.enabled.contains("sasl"),
              negotiation.sasl != nil else { return }
        switch message.command {
        case "903":
            eventHandler?(.notice("SASL authentication succeeded."))
            endCapabilityNegotiation()
        case "902", "904", "905", "906":
            eventHandler?(.notice(message.trailing ?? "SASL authentication failed."))
            endCapabilityNegotiation()
        case "907":
            eventHandler?(.notice(message.trailing ?? "SASL authentication was already complete."))
            endCapabilityNegotiation()
        case "908":
            eventHandler?(.notice(message.trailing ?? "The server does not support the requested SASL mechanism."))
        default:
            break
        }
    }
}
