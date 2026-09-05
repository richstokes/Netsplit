import Foundation
import Security

enum KeychainStore {
    enum Operation: Equatable {
        case read
        case save
        case remove
    }

    struct AccessError: Error {
        let operation: Operation
        let status: OSStatus
    }

    // The App Store bundle ID remains richstokes.irc, preserving existing credentials.
    // Development builds and test hosts must never share that service.
    static let service = serviceName(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        isTestMode: NetsplitLaunchEnvironment.currentProcessIsInTestMode
    )

    static func serviceName(bundleIdentifier: String?, isTestMode: Bool) -> String {
        if isTestMode { return "richstokes.irc.tests" }
        return bundleIdentifier ?? "richstokes.irc.development"
    }

    static func value(for account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else {
            throw AccessError(operation: .read, status: status)
        }
        guard let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AccessError(operation: .remove, status: status)
            }
            return
        }
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            let metadata = itemMetadata(for: account)
            newItem[kSecAttrLabel] = metadata.label
            newItem[kSecAttrDescription] = metadata.description
            newItem[kSecValueData] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AccessError(operation: .save, status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw AccessError(operation: .save, status: updateStatus)
        }
    }

    static func remove(account: String) throws {
        try set("", for: account)
    }

    static func itemMetadata(for account: String) -> (label: String, description: String) {
        let purpose: String
        switch account.split(separator: ".", maxSplits: 1).first {
        case "server-password":
            purpose = "Server Password"
        case "sasl-password":
            purpose = "SASL Password"
        case "ssh-password":
            purpose = "SSH Password"
        case "ssh-private-key":
            purpose = "SSH Private Key"
        case "on-connect-commands":
            purpose = "On-Connect Commands"
        default:
            purpose = "Saved Credential"
        }
        return (
            label: "Netsplit \(purpose)",
            description: "Secure connection information saved by Netsplit"
        )
    }
}
