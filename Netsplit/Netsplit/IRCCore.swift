import Foundation

enum IRCSystemSleepPolicy {
    static func shouldRestoreConnection(status: ConnectionStatus, reconnectWasScheduled: Bool) -> Bool {
        switch status {
        case .connecting, .online:
            true
        case .offline, .failed:
            reconnectWasScheduled
        }
    }
}

struct IRCLineBufferOutput {
    var lines: [String] = []
    var exceededMaximumLineLength = false
}

struct IRCLineBuffer {
    private var buffer = Data()
    private let maximumLineBytes: Int
    private static let delimiter = Data([13, 10])

    init(maximumLineBytes: Int) {
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func append(_ data: Data) -> IRCLineBufferOutput {
        buffer.append(data)
        var output = IRCLineBufferOutput()

        while let range = buffer.range(of: Self.delimiter) {
            guard range.lowerBound <= maximumLineBytes else {
                output.exceededMaximumLineLength = true
                return output
            }
            output.lines.append(String(decoding: buffer[..<range.lowerBound], as: UTF8.self))
            buffer.removeSubrange(..<range.upperBound)
        }

        if buffer.count > maximumLineBytes {
            output.exceededMaximumLineLength = true
        }
        return output
    }

    mutating func removeAll() {
        buffer.removeAll()
    }
}

enum IRCCapability {
    static func name(from advertisedValue: String) -> String {
        String(advertisedValue.drop(while: { $0 == "-" }).split(separator: "=", maxSplits: 1).first ?? "")
    }
}

enum IRCMemberParser {
    static func member(from rawName: String) -> ChannelMember {
        let modeByPrefix: [Character: Character] = [
            "~": "q", "&": "a", "@": "o", "%": "h", "+": "v"
        ]
        var nickname = rawName[...]
        var modes = Set<Character>()
        while let first = nickname.first, let mode = modeByPrefix[first] {
            modes.insert(mode)
            nickname = nickname.dropFirst()
        }
        return ChannelMember(nickname: String(nickname), modes: modes)
    }
}

enum IRCTextFraming {
    static let maximumLineBytes = 510

    static func sanitizedSingleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func prefix(_ value: String, fittingUTF8ByteCount limit: Int = maximumLineBytes) -> String {
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

    static func messageChunks(
        _ text: String,
        commandPrefix: String,
        suffix: String = "",
        maximumLineBytes: Int = maximumLineBytes
    ) -> [String] {
        let availableBytes = maximumLineBytes - commandPrefix.utf8.count - suffix.utf8.count
        guard availableBytes > 0 else { return [] }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let logicalLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []

        for line in logicalLines where !line.isEmpty {
            var chunk = ""
            var byteCount = 0
            for character in line {
                let characterByteCount = String(character).utf8.count
                if !chunk.isEmpty, byteCount + characterByteCount > availableBytes {
                    result.append(chunk)
                    chunk = ""
                    byteCount = 0
                }
                guard characterByteCount <= availableBytes else { continue }
                chunk.append(character)
                byteCount += characterByteCount
            }
            if !chunk.isEmpty { result.append(chunk) }
        }
        return result
    }
}

enum IRCCommandTranslator {
    static func onConnectWireCommand(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("/") else { return trimmed }

        let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.uppercased() else { return nil }
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "MSG", "QUERY":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return nil }
            return "PRIVMSG \(fields[0]) :\(fields[1])"
        case "NOTICE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return nil }
            return "NOTICE \(fields[0]) :\(fields[1])"
        case "NS", "NICKSERV":
            guard !argument.isEmpty else { return nil }
            return "PRIVMSG NickServ :\(argument)"
        case "CS", "CHANSERV":
            guard !argument.isEmpty else { return nil }
            return "PRIVMSG ChanServ :\(argument)"
        case "IDENTIFY":
            guard !argument.isEmpty else { return nil }
            return "PRIVMSG NickServ :IDENTIFY \(argument)"
        case "RAW", "QUOTE":
            return argument.isEmpty ? nil : argument
        case "JOIN":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard let rawChannel = fields.first, !rawChannel.isEmpty else { return nil }
            let channel = rawChannel.first.map { "#&+!".contains($0) } == true ? rawChannel : "#\(rawChannel)"
            return fields.count == 2 ? "JOIN \(channel) \(fields[1])" : "JOIN \(channel)"
        default:
            return argument.isEmpty ? command : "\(command) \(argument)"
        }
    }
}

enum IRCSASL {
    static func plainAuthenticationChunks(username: String, password: String) -> [String] {
        let payload = Data(([0] + Array(username.utf8) + [0] + Array(password.utf8))).base64EncodedString()
        var chunks = stride(from: 0, to: payload.count, by: 400).map { start in
            String(payload.dropFirst(start).prefix(400))
        }
        if payload.count.isMultiple(of: 400) { chunks.append("+") }
        return chunks
    }
}

struct IRCMembershipModeChange: Equatable {
    var nickname: String
    var mode: Character
    var adding: Bool
}

enum IRCChannelModeParser {
    static func membershipChanges(modeString: String, arguments: [String]) -> [IRCMembershipModeChange] {
        var adding = true
        var argumentIndex = 0
        var changes: [IRCMembershipModeChange] = []

        for mode in modeString {
            switch mode {
            case "+":
                adding = true
                continue
            case "-":
                adding = false
                continue
            default:
                break
            }

            if "qaohv".contains(mode) {
                guard argumentIndex < arguments.count else { continue }
                changes.append(IRCMembershipModeChange(
                    nickname: arguments[argumentIndex],
                    mode: mode,
                    adding: adding
                ))
                argumentIndex += 1
            } else if channelModeConsumesArgument(mode, adding: adding) {
                argumentIndex += 1
            }
        }
        return changes
    }

    private static func channelModeConsumesArgument(_ mode: Character, adding: Bool) -> Bool {
        switch mode {
        case "b", "e", "I", "k": true
        case "l", "f", "j", "L": adding
        default: false
        }
    }
}

enum IRCReconnectPolicy {
    static func delay(attempt: Int, initialDelay: TimeInterval, maximumDelay: TimeInterval) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return min(initialDelay * pow(2, Double(attempt - 1)), maximumDelay)
    }
}

enum IRCConversationHistory {
    static let retentionLimit = 5_000
    static let trimBatchSize = 250

    static func append(_ message: IRCMessage, to messages: inout [IRCMessage]) {
        messages.append(message)
        let trimThreshold = retentionLimit + trimBatchSize
        if messages.count > trimThreshold {
            messages.removeFirst(messages.count - retentionLimit)
        }
    }

    static func merging(_ first: [IRCMessage], _ second: [IRCMessage], limit: Int) -> [IRCMessage] {
        guard limit > 0 else { return [] }
        var messages = first + second
        messages.sort { $0.timestamp < $1.timestamp }
        if messages.count > limit {
            messages.removeFirst(messages.count - limit)
        }
        return messages
    }
}
