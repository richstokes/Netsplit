import Foundation

/// Protocol state belongs to one transport generation. Replacing or removing a
/// session retires its nickname negotiation, registration, setup commands, and
/// request correlation together. Transcripts and reconnect backoff deliberately
/// live outside this value because they survive a transport replacement.
struct IRCServerSession {
    var id: UUID?
    var onConnectCommands: IRCOnConnectCommandPhases?
    var automaticJoins: IRCOnConnectJoinTracker?
    var nickname: String?
    var registeredAt: Date?
    var terminalError: String?
    var attemptedNicknameSuffixes = Set<Int>()
    var sourcePrefix: String?
    var requests = IRCServerRequests()
}
