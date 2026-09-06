import Foundation

/// All in-flight requests for one server session. Disconnect discards this
/// value after settling outgoing echoes; adding a request kind cannot leave
/// another server-keyed dictionary behind during teardown.
struct IRCServerRequests {
    var joins: [String: PendingJoin] = [:]
    var whois: [String: SidebarItem] = [:]
    var topics: [String: SidebarItem] = [:]
    var invites: [String: PendingInvite] = [:]
    var modes: [String: SidebarItem] = [:]
    var maskBans: [String: [PendingMaskBan]] = [:]
    var maskBanWhoIDs: [String: UUID] = [:]
    var kicks: [String: PendingKick] = [:]
    var kills: [String: PendingKill] = [:]
    var who: [String: SidebarItem] = [:]
    var clientVersions: [String: PendingReplyRequest] = [:]
    var userPings: [String: PendingUserPing] = [:]
    var ctcp: [String: PendingReplyRequest] = [:]
    var nick: SidebarItem?
    var motd: SidebarItem?
    var version: PendingReplyRequest?
    var outgoingEchoes: [PendingOutgoingEcho]?
    var selfTargetedConfirmations: [IRCRecentSelfTargetedConfirmation]?
    var batches: [String: IRCIncomingBatch]?

    mutating func removeChannel(named key: String) {
        joins.removeValue(forKey: key)
        modes.removeValue(forKey: key)
        maskBans.removeValue(forKey: key)
        maskBanWhoIDs.removeValue(forKey: key)
    }

    mutating func appendOutgoingEcho(_ echo: PendingOutgoingEcho) {
        if outgoingEchoes == nil { outgoingEchoes = [] }
        outgoingEchoes?.append(echo)
    }

    mutating func appendSelfTargetedConfirmation(_ confirmation: IRCRecentSelfTargetedConfirmation) {
        if selfTargetedConfirmations == nil { selfTargetedConfirmations = [] }
        selfTargetedConfirmations?.append(confirmation)
    }

    mutating func insertBatch(id: String, batch: IRCIncomingBatch) {
        if batches == nil { batches = [:] }
        batches?[id] = batch
    }

    @discardableResult
    mutating func takeNick() -> SidebarItem? {
        defer { nick = nil }
        return nick
    }

    @discardableResult
    mutating func takeMotd() -> SidebarItem? {
        defer { motd = nil }
        return motd
    }

    @discardableResult
    mutating func takeVersion() -> PendingReplyRequest? {
        defer { version = nil }
        return version
    }

    @discardableResult
    mutating func takeOutgoingEchoes() -> [PendingOutgoingEcho]? {
        defer { outgoingEchoes = nil }
        return outgoingEchoes
    }

    @discardableResult
    mutating func takeSelfTargetedConfirmations() -> [IRCRecentSelfTargetedConfirmation]? {
        defer { selfTargetedConfirmations = nil }
        return selfTargetedConfirmations
    }

    @discardableResult
    mutating func takeBatches() -> [String: IRCIncomingBatch]? {
        defer { batches = nil }
        return batches
    }
}

struct PendingOutgoingEcho {
    var id: UUID
    var target: String
    var wireText: String
    var label: String?
    var state: IRCOutgoingEchoState
    var destination: SidebarItem
    var sentAt: Date
    var suppressTranscript = false
    var hasConsumedSelfTargetedDelivery = false
}

struct IRCIncomingBatch {
    var label: String?
    var destination: SidebarItem?
    // A first reply can consume the pending echo before the batch is finished.
    var suppressTranscript: Bool
    var completesLabeledResponse: Bool
    var parentID: String?
}

struct PendingUserPing {
    var token: String
    var sentAt: Date
    var destination: SidebarItem
}

struct PendingReplyRequest {
    var requestID: UUID
    var destination: SidebarItem
}

struct PendingJoin {
    var serverID: UUID
    var channel: String
    var channelID: UUID
    var destination: SidebarItem
    var statusMessageID: UUID
    var topic: String
    var preservesConversationOnFailure = false
    var selectsConversationOnSuccess = false
    var redirectedFromChannels: [String] = []
}

struct PendingInvite {
    var serverID: UUID
    var nickname: String
    var channel: String
    var destination: SidebarItem
}

struct PendingKick {
    var serverID: UUID
    var channel: String
    var nickname: String
    var destination: SidebarItem
}

struct PendingMaskBan {
    var serverID: UUID
    var channel: String
    var mask: String
    var reason: String?
    var destination: SidebarItem
    var state: PendingMaskBanState
}

enum PendingMaskBanState {
    case waitingForWho
    case ready
    case awaitingModeConfirmation
}

struct PendingKill {
    var serverID: UUID
    var nickname: String
    var destination: SidebarItem
}
