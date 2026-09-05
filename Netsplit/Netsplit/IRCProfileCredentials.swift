import Foundation

@MainActor
protocol IRCCredentialStore {
    func value(for account: String) throws -> String
    func set(_ value: String, for account: String) throws
}

struct IRCKeychainCredentialStore: IRCCredentialStore {
    func value(for account: String) throws -> String {
        try KeychainStore.value(for: account)
    }

    func set(_ value: String, for account: String) throws {
        try KeychainStore.set(value, for: account)
    }
}

/// Used by test-host state instances so they cannot read or alter saved credentials.
final class IRCInMemoryCredentialStore: IRCCredentialStore {
    private var values: [String: String] = [:]

    func value(for account: String) throws -> String {
        values[account] ?? ""
    }

    func set(_ value: String, for account: String) throws {
        values[account] = value.isEmpty ? nil : value
    }
}

/// A nil field means its saved value could not be read, not that it is empty.
struct IRCProfileCredentialSnapshot {
    var serverPassword: String? = ""
    var saslPassword: String? = ""
    var onConnectCommands: IRCOnConnectCommandPhases? = IRCOnConnectCommandPhases()
    var sshPassword: String? = ""
    var sshPrivateKey: String? = ""

    var hasUnavailableValues: Bool {
        serverPassword == nil || saslPassword == nil || onConnectCommands == nil
            || sshPassword == nil || sshPrivateKey == nil
    }

    /// Advance the editor's baseline even if a later Keychain write failed.
    /// A retry can then restore an earlier value the user has put back in the form.
    mutating func recordSavedChanges(_ changes: IRCProfileCredentialChanges) {
        if let value = changes.serverPassword { serverPassword = value }
        if let value = changes.saslPassword { saslPassword = value }
        if let value = changes.onConnectCommands { onConnectCommands = value }
        if let value = changes.sshPassword { sshPassword = value }
        if let value = changes.sshPrivateKey { sshPrivateKey = value }
    }

    func changes(
        serverPassword: String,
        saslPassword: String,
        onConnectCommands: IRCOnConnectCommandPhases,
        sshPassword: String,
        sshPrivateKey: String
    ) -> IRCProfileCredentialChanges {
        let commands = onConnectCommands.removingBlankCommands
        return IRCProfileCredentialChanges(
            serverPassword: serverPassword == (self.serverPassword ?? "") ? nil : serverPassword,
            saslPassword: saslPassword == (self.saslPassword ?? "") ? nil : saslPassword,
            onConnectCommands: commands == (self.onConnectCommands ?? IRCOnConnectCommandPhases()).removingBlankCommands
                ? nil : commands,
            sshPassword: sshPassword == (self.sshPassword ?? "") ? nil : sshPassword,
            sshPrivateKey: sshPrivateKey == (self.sshPrivateKey ?? "") ? nil : sshPrivateKey
        )
    }
}

/// Only explicitly changed fields are written. An empty string explicitly clears a value.
struct IRCProfileCredentialChanges {
    var serverPassword: String?
    var saslPassword: String?
    var onConnectCommands: IRCOnConnectCommandPhases?
    var sshPassword: String?
    var sshPrivateKey: String?

    func restricted(to kinds: Set<String>) -> Self {
        Self(
            serverPassword: kinds.contains("server-password") ? serverPassword : nil,
            saslPassword: kinds.contains("sasl-password") ? saslPassword : nil,
            onConnectCommands: kinds.contains("on-connect-commands") ? onConnectCommands : nil,
            sshPassword: kinds.contains("ssh-password") ? sshPassword : nil,
            sshPrivateKey: kinds.contains("ssh-private-key") ? sshPrivateKey : nil
        )
    }

    func encodedValues() throws -> [(kind: String, value: String)] {
        var values: [(String, String)] = []
        if let serverPassword { values.append(("server-password", serverPassword)) }
        if let saslPassword { values.append(("sasl-password", saslPassword)) }
        if let commands = onConnectCommands?.removingBlankCommands {
            let encoded = commands.isEmpty ? "" : String(decoding: try JSONEncoder().encode(commands), as: UTF8.self)
            values.append(("on-connect-commands", encoded))
        }
        if let sshPassword { values.append(("ssh-password", sshPassword)) }
        if let sshPrivateKey { values.append(("ssh-private-key", sshPrivateKey)) }
        return values
    }
}

struct IRCProfileSaveResult {
    var succeeded: Bool
    var savedCredentials = IRCProfileCredentialChanges()
}
