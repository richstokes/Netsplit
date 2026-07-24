import Foundation

struct IRCOnConnectCommandPhases: Codable, Equatable {
  var beforeFavoritesJoined: [String]
  var afterFavoritesJoined: [String]

  init(
    beforeFavoritesJoined: [String] = [],
    afterFavoritesJoined: [String] = []
  ) {
    self.beforeFavoritesJoined = beforeFavoritesJoined
    self.afterFavoritesJoined = afterFavoritesJoined
  }

  init(from decoder: Decoder) throws {
    let singleValueContainer = try decoder.singleValueContainer()
    if let legacyCommands = try? singleValueContainer.decode([String].self) {
      beforeFavoritesJoined = legacyCommands
      afterFavoritesJoined = []
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    beforeFavoritesJoined =
      try container.decodeIfPresent([String].self, forKey: .beforeFavoritesJoined) ?? []
    afterFavoritesJoined =
      try container.decodeIfPresent([String].self, forKey: .afterFavoritesJoined) ?? []
  }

  var removingBlankCommands: Self {
    Self(
      beforeFavoritesJoined: Self.cleaned(beforeFavoritesJoined),
      afterFavoritesJoined: Self.cleaned(afterFavoritesJoined)
    )
  }

  var isEmpty: Bool {
    beforeFavoritesJoined.isEmpty && afterFavoritesJoined.isEmpty
  }

  private static func cleaned(_ commands: [String]) -> [String] {
    commands
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

struct IRCOnConnectJoinTracker: Equatable {
  private(set) var pendingChannelNames: [String]

  init(channelNames: [String]) {
    pendingChannelNames = channelNames
  }

  var isComplete: Bool {
    pendingChannelNames.isEmpty
  }

  mutating func complete(_ channelName: String, caseMapping: IRCCaseMapping) {
    let normalizedChannelName = caseMapping.normalize(channelName)
    guard let index = pendingChannelNames.firstIndex(where: {
      caseMapping.normalize($0) == normalizedChannelName
    }) else { return }
    pendingChannelNames.remove(at: index)
  }
}

enum IRCClientVersion {
  static var ctcpReply: String {
    ctcpReply(infoDictionary: Bundle.main.infoDictionary)
  }

  static func ctcpReply(infoDictionary: [String: Any]?) -> String {
    let marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    return "Netsplit \(marketingVersion) for macOS - https://github.com/richstokes/Netsplit"
  }
}

enum IRCSystemSleepPolicy {
  static func shouldRestoreConnection(status: ConnectionStatus, reconnectWasScheduled: Bool) -> Bool
  {
    switch status {
    case .connecting, .online:
      true
    case .offline, .failed:
      reconnectWasScheduled
    }
  }
}

struct IRCOneOffServerEndpoint: Equatable {
  var hostname: String
  var port: UInt16
  var useTLS: Bool
}

struct IRCOneOffServerCommandError: Error, Equatable {
  var message: String
}

enum IRCOneOffServerCommand {
  static let usage = "Usage: /server hostname [port] [--tls|--no-tls]"

  static func endpoint(
    from argument: String
  ) -> Result<IRCOneOffServerEndpoint, IRCOneOffServerCommandError> {
    let tokens = argument.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !tokens.isEmpty else { return .failure(.init(message: usage)) }

    var positionalArguments: [String] = []
    var explicitTLS: Bool?
    for token in tokens {
      switch token.lowercased() {
      case "--tls":
        guard explicitTLS != false else {
          return .failure(.init(message: "Use either --tls or --no-tls, not both."))
        }
        explicitTLS = true
      case "--no-tls":
        guard explicitTLS != true else {
          return .failure(.init(message: "Use either --tls or --no-tls, not both."))
        }
        explicitTLS = false
      default:
        guard !token.hasPrefix("-") else {
          return .failure(.init(message: "Unknown /server option: \(token). \(usage)"))
        }
        positionalArguments.append(token)
      }
    }

    guard (1...2).contains(positionalArguments.count) else {
      return .failure(.init(message: usage))
    }
    let hostname = positionalArguments[0]
    guard !hostname.isEmpty else { return .failure(.init(message: usage)) }

    let port: UInt16
    if positionalArguments.count == 2 {
      guard let parsedPort = UInt16(positionalArguments[1]), parsedPort > 0 else {
        return .failure(.init(message: "The server port must be between 1 and 65535."))
      }
      port = parsedPort
    } else {
      port = explicitTLS == false ? 6667 : 6697
    }

    return .success(IRCOneOffServerEndpoint(
      hostname: hostname,
      port: port,
      useTLS: explicitTLS ?? (port == 6697)
    ))
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
  /// Capabilities for features the client actively implements. Keeping this
  /// list separate from CAP negotiation makes it harder to accidentally ask
  /// a server for response formats that are not parsed.
  static let preferred = [
    "message-tags",
    "server-time",
    "multi-prefix",
    "userhost-in-names",
    "chghost",
    "echo-message",
  ]

  static func name(from advertisedValue: String) -> String {
    String(
      advertisedValue.drop(while: { $0 == "-" }).split(separator: "=", maxSplits: 1).first ?? "")
  }
}

enum IRCServerTimeParser {
  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static let wholeSecondsFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static func date(from value: String?) -> Date? {
    guard let value else { return nil }
    return fractionalFormatter.date(from: value)
      ?? wholeSecondsFormatter.date(from: value)
  }
}

struct IRCMembershipConfiguration: Hashable {
  struct Entry: Hashable {
    var mode: Character
    var prefix: Character
  }

  static let rfc1459 = IRCMembershipConfiguration(entries: [
    Entry(mode: "o", prefix: "@"),
    Entry(mode: "v", prefix: "+"),
  ])
  static let common = IRCMembershipConfiguration(entries: [
    Entry(mode: "q", prefix: "~"),
    Entry(mode: "a", prefix: "&"),
    Entry(mode: "o", prefix: "@"),
    Entry(mode: "h", prefix: "%"),
    Entry(mode: "v", prefix: "+"),
  ])

  var entries: [Entry]

  init(entries: [Entry]) {
    self.entries = entries
  }

  init?(advertisedValue: String) {
    guard advertisedValue.first == "(",
      let closingParenthesis = advertisedValue.firstIndex(of: ")")
    else { return nil }
    let modeStart = advertisedValue.index(after: advertisedValue.startIndex)
    let modes = Array(advertisedValue[modeStart..<closingParenthesis])
    let prefixes = Array(advertisedValue[advertisedValue.index(after: closingParenthesis)...])
    guard modes.count == prefixes.count,
      Set(modes).count == modes.count,
      Set(prefixes).count == prefixes.count
    else { return nil }
    entries = zip(modes, prefixes).map { Entry(mode: $0.0, prefix: $0.1) }
  }

  var modes: Set<Character> {
    Set(entries.map(\.mode))
  }

  var prefixes: Set<Character> {
    Set(entries.map(\.prefix))
  }

  var operatorMode: Character? {
    entries.first(where: { $0.mode == "o" })?.mode
      ?? entries.first(where: { $0.prefix == "@" })?.mode
  }

  var voiceMode: Character? {
    entries.first(where: { $0.mode == "v" })?.mode
      ?? entries.first(where: { $0.prefix == "+" })?.mode
  }

  func mode(for prefix: Character) -> Character? {
    entries.first(where: { $0.prefix == prefix })?.mode
  }

  func prefix(for mode: Character) -> Character? {
    entries.first(where: { $0.mode == mode })?.prefix
  }

  func highestEntry(in modes: Set<Character>) -> Entry? {
    entries.first(where: { modes.contains($0.mode) })
  }

  func rank(of modes: Set<Character>) -> Int? {
    entries.firstIndex(where: { modes.contains($0.mode) })
  }

  func hasOperatorPrivileges(_ modes: Set<Character>) -> Bool {
    guard let operatorMode,
      let operatorRank = entries.firstIndex(where: { $0.mode == operatorMode }),
      let memberRank = rank(of: modes)
    else { return false }
    return memberRank <= operatorRank
  }

  func roleName(for mode: Character) -> String {
    switch mode {
    case "q": "Owner"
    case "a": "Admin"
    case "o": "Operator"
    case "h": "Half-op"
    case "v": "Voice"
    default: "Mode +\(mode)"
    }
  }
}

struct IRCChannelModeCapabilities: Equatable {
  static let legacyFallback = IRCChannelModeCapabilities(
    // Preserve the conservative pre-ISUPPORT behavior for older servers.
    // e/I and f/j/L are common extensions rather than RFC 1459 modes, but
    // treating them as parameterized prevents later nickname arguments in
    // a mixed MODE command from becoming misaligned.
    listModes: Set("beI"),
    alwaysParameterizedModes: ["k"],
    setOnlyParameterizedModes: Set("lfjL"),
    parameterlessModes: Set("imnpst")
  )

  var listModes: Set<Character>
  var alwaysParameterizedModes: Set<Character>
  var setOnlyParameterizedModes: Set<Character>
  var parameterlessModes: Set<Character>

  init(
    listModes: Set<Character>,
    alwaysParameterizedModes: Set<Character>,
    setOnlyParameterizedModes: Set<Character>,
    parameterlessModes: Set<Character>
  ) {
    self.listModes = listModes
    self.alwaysParameterizedModes = alwaysParameterizedModes
    self.setOnlyParameterizedModes = setOnlyParameterizedModes
    self.parameterlessModes = parameterlessModes
  }

  init?(advertisedValue: String) {
    let groups = advertisedValue.split(separator: ",", omittingEmptySubsequences: false)
    guard groups.count == 4 else { return nil }
    listModes = Set(groups[0])
    alwaysParameterizedModes = Set(groups[1])
    setOnlyParameterizedModes = Set(groups[2])
    parameterlessModes = Set(groups[3])
  }

  func consumesArgument(for mode: Character, adding: Bool) -> Bool {
    listModes.contains(mode)
      || alwaysParameterizedModes.contains(mode)
      || (adding && setOnlyParameterizedModes.contains(mode))
  }
}

struct IRCServerFeatures: Equatable {
  static let defaults = IRCServerFeatures()

  var caseMapping: IRCCaseMapping = .rfc1459
  var membership: IRCMembershipConfiguration = .rfc1459
  var channelModes: IRCChannelModeCapabilities = .legacyFallback
  var channelTypes: Set<Character> = ["#", "&"]
  var statusMessagePrefixes: Set<Character> = []
  var networkName: String?
  var maximumNicknameLength: Int?
  var maximumChannelLength: Int?
  var maximumModesPerCommand: Int?

  mutating func apply(parameters: ArraySlice<String>) {
    for parameter in parameters {
      apply(parameter: parameter)
    }
  }

  func isChannelName(_ value: String) -> Bool {
    value.first.map(channelTypes.contains) ?? false
  }

  func channelName(fromMessageTarget target: String) -> String? {
    var candidate = target[...]
    while let first = candidate.first, statusMessagePrefixes.contains(first) {
      candidate = candidate.dropFirst()
    }
    let channel = String(candidate)
    return isChannelName(channel) ? channel : nil
  }

  var preferredChannelPrefix: Character {
    if channelTypes.contains("#") { return "#" }
    return channelTypes.sorted().first ?? "#"
  }

  private mutating func apply(parameter: String) {
    let removing = parameter.hasPrefix("-")
    let token = removing ? String(parameter.dropFirst()) : parameter
    let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard let rawName = parts.first, !rawName.isEmpty else { return }
    let name = rawName.uppercased()
    let value = parts.count == 2 ? String(parts[1]) : nil

    if removing {
      reset(name)
      return
    }

    switch name {
    case "CASEMAPPING":
      switch value?.lowercased() {
      case "ascii": caseMapping = .ascii
      case "strict-rfc1459": caseMapping = .strictRFC1459
      case "rfc1459": caseMapping = .rfc1459
      default: break
      }
    case "PREFIX":
      if let value, let parsed = IRCMembershipConfiguration(advertisedValue: value) {
        membership = parsed
      } else if value == nil {
        membership = IRCMembershipConfiguration(entries: [])
      }
    case "CHANMODES":
      if let value, let parsed = IRCChannelModeCapabilities(advertisedValue: value) {
        channelModes = parsed
      }
    case "CHANTYPES":
      channelTypes = Set(value ?? "")
    case "STATUSMSG":
      statusMessagePrefixes = Set(value ?? "")
    case "NETWORK":
      networkName = value
    case "NICKLEN":
      maximumNicknameLength = positiveInteger(value)
    case "CHANNELLEN":
      maximumChannelLength = positiveInteger(value)
    case "MODES":
      maximumModesPerCommand = positiveInteger(value)
    default:
      break
    }
  }

  private mutating func reset(_ name: String) {
    let defaults = Self.defaults
    switch name {
    case "CASEMAPPING": caseMapping = defaults.caseMapping
    case "PREFIX": membership = defaults.membership
    case "CHANMODES": channelModes = defaults.channelModes
    case "CHANTYPES": channelTypes = defaults.channelTypes
    case "STATUSMSG": statusMessagePrefixes = defaults.statusMessagePrefixes
    case "NETWORK": networkName = nil
    case "NICKLEN": maximumNicknameLength = nil
    case "CHANNELLEN": maximumChannelLength = nil
    case "MODES": maximumModesPerCommand = nil
    default: break
    }
  }

  private func positiveInteger(_ value: String?) -> Int? {
    guard let value, let parsed = Int(value), parsed > 0 else { return nil }
    return parsed
  }
}

enum IRCMemberParser {
  static func member(
    from rawName: String,
    membership: IRCMembershipConfiguration = .common
  ) -> ChannelMember {
    var nickmask = rawName[...]
    var modes = Set<Character>()
    while let first = nickmask.first, let mode = membership.mode(for: first) {
      modes.insert(mode)
      nickmask = nickmask.dropFirst()
    }

    let identity = String(nickmask)
    let nicknameAndUser = identity.split(
      separator: "!",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    let nickname = String(nicknameAndUser[0])
    guard nicknameAndUser.count == 2 else {
      return ChannelMember(nickname: nickname, modes: modes, membership: membership)
    }

    let userAndHost = nicknameAndUser[1].split(
      separator: "@",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    return ChannelMember(
      nickname: nickname,
      modes: modes,
      membership: membership,
      username: userAndHost.first.map(String.init),
      hostname: userAndHost.count == 2 ? String(userAndHost[1]) : nil
    )
  }
}

enum IRCTextFraming {
  static let maximumLineBytes = 510

  static func sanitizedSingleLine(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
  }

  static func prefix(_ value: String, fittingUTF8ByteCount limit: Int = maximumLineBytes) -> String
  {
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

    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let logicalLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init)
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
  static func onConnectWireCommand(
    from input: String,
    channelTypes: Set<Character> = Set("#&+!"),
    preferredChannelPrefix: Character = "#"
  ) -> String? {
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
      let channel =
        rawChannel.first.map(channelTypes.contains) == true
        ? rawChannel
        : "\(preferredChannelPrefix)\(rawChannel)"
      return fields.count == 2 ? "JOIN \(channel) \(fields[1])" : "JOIN \(channel)"
    default:
      return argument.isEmpty ? command : "\(command) \(argument)"
    }
  }
}

enum IRCCTCPPing {
  static func payload(token: String) -> String {
    "\u{01}PING \(token)\u{01}"
  }

  static func roundTripMilliseconds(sentAt: Date, receivedAt: Date) -> Int {
    max(0, Int((receivedAt.timeIntervalSince(sentAt) * 1_000).rounded()))
  }
}

enum IRCCTCPEchoPolicy {
  static func isSelfEcho(
    sender: String,
    localNickname: String,
    caseMapping: IRCCaseMapping,
    canReplyToRequest: Bool
  ) -> Bool {
    canReplyToRequest && caseMapping.normalize(sender) == caseMapping.normalize(localNickname)
  }
}

enum IRCSASL {
  static func plainAuthenticationChunks(username: String, password: String) -> [String] {
    let payload = Data(([0] + Array(username.utf8) + [0] + Array(password.utf8)))
      .base64EncodedString()
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

struct IRCParsedChannelModeChange: Equatable {
  var mode: Character
  var adding: Bool
  var argument: String?
}

enum IRCChannelModeParser {
  static func changes(
    modeString: String,
    arguments: [String],
    membership: IRCMembershipConfiguration = .common,
    channelModes: IRCChannelModeCapabilities = .legacyFallback
  ) -> [IRCParsedChannelModeChange] {
    var adding = true
    var argumentIndex = 0
    var changes: [IRCParsedChannelModeChange] = []

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

      let consumesArgument =
        membership.modes.contains(mode)
        || channelModes.consumesArgument(for: mode, adding: adding)
      let argument: String?
      if consumesArgument, argumentIndex < arguments.count {
        argument = arguments[argumentIndex]
        argumentIndex += 1
      } else {
        argument = nil
      }
      changes.append(
        IRCParsedChannelModeChange(
          mode: mode,
          adding: adding,
          argument: argument
        ))
    }
    return changes
  }

  static func membershipChanges(
    modeString: String,
    arguments: [String],
    membership: IRCMembershipConfiguration = .common,
    channelModes: IRCChannelModeCapabilities = .legacyFallback
  ) -> [IRCMembershipModeChange] {
    changes(
      modeString: modeString,
      arguments: arguments,
      membership: membership,
      channelModes: channelModes
    ).compactMap { change in
      guard membership.modes.contains(change.mode),
        let nickname = change.argument
      else { return nil }
      return IRCMembershipModeChange(
        nickname: nickname,
        mode: change.mode,
        adding: change.adding
      )
    }
  }
}

enum IRCReconnectPolicy {
  static func delay(attempt: Int, initialDelay: TimeInterval, maximumDelay: TimeInterval)
    -> TimeInterval
  {
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
