//
//  SSHTunnelConnection.swift
//  Netsplit
//

@preconcurrency import Citadel
@preconcurrency import Crypto
import Foundation
@preconcurrency import NIO
@preconcurrency import NIOSSH
@preconcurrency import NIOSSL
@preconcurrency import NIOTLS

struct SSHTunnelConfiguration: Sendable {
    var sshHostname: String
    var sshPort: Int
    var sshUsername: String
    var sshPassword: String
    var sshPrivateKey: String
    var trustedHostKey: String?
    var targetHostname: String
    var targetPort: Int
    var useTLS: Bool
}

enum SSHTunnelError: LocalizedError {
    case invalidPrivateKey
    case unsupportedPrivateKeyType
    case missingAuthentication
    case authenticationFailed
    case hostKeyChanged

    var preventsAutomaticReconnect: Bool { true }

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            "The SSH private key could not be read. Netsplit supports unencrypted OpenSSH Ed25519 and RSA private keys."
        case .unsupportedPrivateKeyType:
            "This SSH private-key type is not supported. Use an OpenSSH Ed25519 or RSA key, or password authentication."
        case .missingAuthentication:
            "Configure an SSH password or private key before connecting through this SSH server."
        case .authenticationFailed:
            "SSH authentication failed. Verify the username and password, or make sure the selected public key is installed in the server account's ~/.ssh/authorized_keys file. If you use an RSA key, the server may require RSA-SHA2; try Ed25519 or password authentication."
        case .hostKeyChanged:
            "The SSH server's host key has changed. The connection was stopped to protect your credentials. Verify the server, then forget the saved host identity in this server profile before reconnecting."
        }
    }
}

/// Owns an authenticated SSH connection and one direct-tcpip child channel that
/// carries the IRC byte stream. No local listening socket is created, which is
/// important for the App Sandbox and avoids exposing a loopback proxy port.
@MainActor
final class SSHTunnelConnection {
    private var client: SSHClient?
    private var channel: Channel?
    private var connectionTask: Task<Void, Never>?
    private var generation = UUID()

    func connect(
        configuration: SSHTunnelConfiguration,
        onReady: @escaping @MainActor () -> Void,
        onData: @escaping @MainActor (Data) -> Void,
        onClose: @escaping @MainActor (Error?) -> Void,
        onHostKeyLearned: @escaping @MainActor (String) -> Void
    ) {
        close()
        let generation = UUID()
        self.generation = generation

        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authenticationAttempts = try Self.authenticationMethods(for: configuration)
                let hostKeyValidator = SSHHostKeyValidator.custom(
                    PinnedSSHHostKeyValidator(
                        trustedKey: configuration.trustedHostKey,
                        onFirstSeen: { key in
                            Task { @MainActor [weak self] in
                                guard let self, self.generation == generation else { return }
                                onHostKeyLearned(key)
                            }
                        }
                    )
                )
                var connectedClient: SSHClient?
                var lastAuthenticationError: Error?
                for authentication in authenticationAttempts {
                    do {
                        let settings = SSHClientSettings(
                            host: configuration.sshHostname,
                            port: configuration.sshPort,
                            authenticationMethod: authentication,
                            hostKeyValidator: hostKeyValidator
                        )
                        connectedClient = try await SSHClient.connect(to: settings)
                        break
                    } catch {
                        guard Self.isAuthenticationFailure(error) else { throw error }
                        lastAuthenticationError = error
                    }
                }
                guard let client = connectedClient else {
                    throw lastAuthenticationError ?? SSHTunnelError.authenticationFailed
                }
                guard !Task.isCancelled, self.generation == generation else {
                    try? await client.close()
                    return
                }
                self.client = client

                let origin = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                let owner = self
                let initializeChannel: @Sendable (Channel) -> EventLoopFuture<Void> = { childChannel in
                    do {
                        let streamHandler = IRCSSHStreamHandler(
                            waitsForTLS: configuration.useTLS,
                            onReady: {
                                Task { @MainActor in
                                    guard owner.generation == generation else { return }
                                    onReady()
                                }
                            },
                            onData: { data in
                                Task { @MainActor in
                                    guard owner.generation == generation else { return }
                                    onData(data)
                                }
                            },
                            onClose: { error in
                                Task { @MainActor in
                                    guard owner.generation == generation else { return }
                                    owner.finish(generation: generation, error: error, onClose: onClose)
                                }
                            }
                        )
                        if configuration.useTLS {
                            var tls = TLSConfiguration.makeClientConfiguration()
                            tls.certificateVerification = .fullVerification
                            let context = try NIOSSLContext(configuration: tls)
                            let tlsHandler = try NIOSSLClientHandler(
                                context: context,
                                serverHostname: configuration.targetHostname
                            )
                            try childChannel.pipeline.syncOperations.addHandler(tlsHandler)
                        }
                        try childChannel.pipeline.syncOperations.addHandler(streamHandler)
                        return childChannel.eventLoop.makeSucceededFuture(())
                    } catch {
                        return childChannel.eventLoop.makeFailedFuture(error)
                    }
                }
                let channel = try await client.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: configuration.targetHostname,
                        targetPort: configuration.targetPort,
                        originatorAddress: origin
                    ),
                    initialize: initializeChannel
                )
                guard !Task.isCancelled, self.generation == generation else {
                    try? await channel.close()
                    try? await client.close()
                    return
                }
                self.channel = channel
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                finish(
                    generation: generation,
                    error: Self.userFacingError(error),
                    onClose: onClose
                )
            }
        }
    }

    func send(_ data: Data, completion: @escaping @MainActor (Bool, Error?) -> Void) {
        guard let channel, channel.isActive else {
            completion(false, nil)
            return
        }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        channel.writeAndFlush(buffer).whenComplete { result in
            Task { @MainActor in
                switch result {
                case .success: completion(true, nil)
                case .failure(let error): completion(false, error)
                }
            }
        }
    }

    func close() {
        generation = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        closeResources()
    }

    private func finish(
        generation: UUID,
        error: Error?,
        onClose: @escaping @MainActor (Error?) -> Void
    ) {
        guard self.generation == generation else { return }
        self.generation = UUID()
        connectionTask = nil
        closeResources()
        onClose(error)
    }

    private func closeResources() {
        let channel = self.channel
        let client = self.client
        self.channel = nil
        self.client = nil
        Task {
            if let channel { try? await channel.close() }
            if let client { try? await client.close() }
        }
    }

    private static func authenticationMethods(
        for configuration: SSHTunnelConfiguration
    ) throws -> [@Sendable () -> SSHAuthenticationMethod] {
        var methods: [@Sendable () -> SSHAuthenticationMethod] = []
        if !configuration.sshPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let keyType: SSHKeyType
            do {
                keyType = try SSHKeyDetection.detectPrivateKeyType(from: configuration.sshPrivateKey)
            } catch {
                throw SSHTunnelError.invalidPrivateKey
            }
            do {
                switch keyType {
                case .ed25519:
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: configuration.sshPrivateKey)
                    let username = configuration.sshUsername
                    methods.append { .ed25519(username: username, privateKey: key) }
                case .rsa:
                    let key = try Insecure.RSA.PrivateKey(sshRsa: configuration.sshPrivateKey)
                    let username = configuration.sshUsername
                    methods.append { .rsa(username: username, privateKey: key) }
                default:
                    throw SSHTunnelError.unsupportedPrivateKeyType
                }
            } catch let error as SSHTunnelError {
                throw error
            } catch {
                throw SSHTunnelError.invalidPrivateKey
            }
        }

        if !configuration.sshPassword.isEmpty {
            let username = configuration.sshUsername
            let password = configuration.sshPassword
            methods.append { .passwordBased(username: username, password: password) }
        }
        if methods.isEmpty {
            throw SSHTunnelError.missingAuthentication
        }
        return methods
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        guard let error = error as? SSHClientError else { return false }
        switch error {
        case .allAuthenticationOptionsFailed,
             .unsupportedPasswordAuthentication,
             .unsupportedPrivateKeyAuthentication,
             .unsupportedHostBasedAuthentication:
            return true
        case .channelCreationFailed:
            return false
        }
    }

    private static func userFacingError(_ error: Error) -> Error {
        if error is SSHTunnelError { return error }
        guard isAuthenticationFailure(error) else { return error }
        return SSHTunnelError.authenticationFailed
    }
}

private nonisolated final class PinnedSSHHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var trustedKey: NIOSSHPublicKey?
    private let onFirstSeen: @Sendable (String) -> Void

    init(trustedKey: String?, onFirstSeen: @escaping @Sendable (String) -> Void) {
        self.trustedKey = trustedKey.flatMap { try? NIOSSHPublicKey(openSSHPublicKey: $0) }
        self.onFirstSeen = onFirstSeen
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let learnedKey: String?
        let isValid: Bool

        lock.lock()
        if let trustedKey {
            learnedKey = nil
            isValid = trustedKey == hostKey
        } else {
            // Pin immediately in memory before authentication continues. Key
            // and password fallback attempts use separate TCP connections, so
            // waiting for profile persistence would leave a window in which a
            // second endpoint could present a different host identity.
            trustedKey = hostKey
            learnedKey = String(openSSHPublicKey: hostKey)
            isValid = true
        }
        lock.unlock()

        if let learnedKey { onFirstSeen(learnedKey) }
        if isValid {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHTunnelError.hostKeyChanged)
        }
    }
}

private nonisolated final class IRCSSHStreamHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let waitsForTLS: Bool
    private let onReady: @Sendable () -> Void
    private let onData: @Sendable (Data) -> Void
    private let onClose: @Sendable (Error?) -> Void
    private var reportedReady = false
    private var reportedClose = false

    init(
        waitsForTLS: Bool,
        onReady: @escaping @Sendable () -> Void,
        onData: @escaping @Sendable (Data) -> Void,
        onClose: @escaping @Sendable (Error?) -> Void
    ) {
        self.waitsForTLS = waitsForTLS
        self.onReady = onReady
        self.onData = onData
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive, !waitsForTLS { reportReady() }
    }

    func channelActive(context: ChannelHandlerContext) {
        if !waitsForTLS { reportReady() }
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case .handshakeCompleted = event as? TLSUserEvent { reportReady() }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
            onData(Data(bytes))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        reportClose(nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        reportClose(error)
        context.close(promise: nil)
    }

    private func reportReady() {
        guard !reportedReady else { return }
        reportedReady = true
        onReady()
    }

    private func reportClose(_ error: Error?) {
        guard !reportedClose else { return }
        reportedClose = true
        onClose(error)
    }
}
