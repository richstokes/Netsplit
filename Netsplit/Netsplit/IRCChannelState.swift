import Foundation

@MainActor
final class IRCChannelState {
    /// Retained with the transcript for reconnect and /hop.
    var joinKey: String?
    var topic: String? { willSet { onChange?() } }
    var onChange: (() -> Void)?

    /// Replacing this value clears every piece of live membership/request state.
    private struct Session {
        var joinedAt: ContinuousClock.Instant?
        var members: [ChannelMember] = []
        var pendingMembers: [String: ChannelMember]?
        var bans: [IRCBanEntry]?
        var pendingBans: [IRCBanEntry]?
        var banRequestID: UUID?
        var banError: String?
    }

    private var session = Session()
    private var memberSignal: IRCRevisionSignal?

    var joinedAt: ContinuousClock.Instant? {
        get { session.joinedAt }
        set { onChange?(); session.joinedAt = newValue }
    }
    var members: [ChannelMember] { session.members }
    var bans: [IRCBanEntry] { session.bans ?? [] }
    var isRequestingBans: Bool { session.banRequestID != nil }
    var banError: String? { session.banError }
    var memberUpdates: IRCRevisionSignal {
        if let memberSignal { return memberSignal }
        let signal = IRCRevisionSignal()
        memberSignal = signal
        return signal
    }

    func invalidateMembers() { memberSignal?.advance() }

    func disconnect() {
        onChange?()
        session = Session()
        invalidateMembers()
    }

    func prepareToJoin(topic: String, key: String?) {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = topic.isEmpty ? nil : topic
        if let key { joinKey = key }
        session.members = []
        session.pendingMembers = nil
        invalidateMembers()
    }

    func beginBanRequest() -> UUID {
        onChange?()
        let id = UUID()
        session.banRequestID = id
        session.pendingBans = []
        session.banError = nil
        return id
    }

    func failBanRequest(_ message: String, requestID: UUID? = nil) {
        if let requestID, session.banRequestID != requestID { return }
        onChange?()
        session.banRequestID = nil
        session.pendingBans = nil
        session.banError = message
    }

    func receiveBan(_ entry: IRCBanEntry) {
        var entries = session.pendingBans ?? []
        if let index = entries.firstIndex(where: { $0.mask.caseInsensitiveCompare(entry.mask) == .orderedSame }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        session.pendingBans = entries
    }

    func finishBanList() {
        onChange?()
        session.bans = (session.pendingBans ?? []).sorted {
            $0.mask.localizedCaseInsensitiveCompare($1.mask) == .orderedAscending
        }
        session.pendingBans = nil
        session.banRequestID = nil
        session.banError = nil
    }

    func applyBanModes(_ modeString: String, arguments: [String], channelName: String, features: IRCServerFeatures) {
        guard session.bans != nil || session.pendingBans != nil else { return }
        let changes = IRCChannelModeParser.changes(
            modeString: modeString, arguments: arguments,
            membership: features.membership, channelModes: features.channelModes
        ).filter { $0.mode == "b" && $0.argument != nil }
        guard !changes.isEmpty else { return }
        if let cached = session.bans {
            onChange?()
            session.bans = IRCBanListMutation.applying(changes, to: cached, channelName: channelName)
        }
        if let pending = session.pendingBans {
            session.pendingBans = IRCBanListMutation.applying(changes, to: pending, channelName: channelName)
        }
    }

    func stageMembers(_ newMembers: [ChannelMember], caseMapping: IRCCaseMapping) {
        var pending = session.pendingMembers ?? [:]
        for member in newMembers {
            let key = caseMapping.normalize(member.nickname)
            if let existing = pending[key] {
                if member.prefix != nil || existing.prefix == nil { pending[key] = member }
            } else { pending[key] = member }
        }
        session.pendingMembers = pending
    }

    func finishStagingMembers() {
        guard let pending = session.pendingMembers else { return }
        session.pendingMembers = nil
        session.members = Self.sortedMembers(Array(pending.values))
        invalidateMembers()
    }

    func addMember(_ member: ChannelMember, caseMapping: IRCCaseMapping) {
        let key = caseMapping.normalize(member.nickname)
        if let index = session.members.firstIndex(where: { caseMapping.normalize($0.nickname) == key }) {
            if member.prefix != nil { session.members[index] = member }
        } else { session.members.append(member) }
        if session.pendingMembers != nil { stageMembers([member], caseMapping: caseMapping) }
        session.members = Self.sortedMembers(session.members)
        invalidateMembers()
    }

    @discardableResult
    func removeMember(named nickname: String, caseMapping: IRCCaseMapping) -> Bool {
        let key = caseMapping.normalize(nickname)
        session.pendingMembers?.removeValue(forKey: key)
        guard let index = session.members.firstIndex(where: { caseMapping.normalize($0.nickname) == key }) else { return false }
        session.members.remove(at: index)
        invalidateMembers()
        return true
    }

    @discardableResult
    func renameMember(_ nickname: String, to newNickname: String, caseMapping: IRCCaseMapping) -> Bool {
        let key = caseMapping.normalize(nickname)
        if var member = session.pendingMembers?.removeValue(forKey: key) {
            member.nickname = newNickname
            session.pendingMembers?[caseMapping.normalize(newNickname)] = member
        }
        guard let index = session.members.firstIndex(where: { caseMapping.normalize($0.nickname) == key }) else { return false }
        session.members[index].nickname = newNickname
        session.members = Self.sortedMembers(session.members)
        invalidateMembers()
        return true
    }

    func applyMembershipModes(_ modeString: String, arguments: [String], features: IRCServerFeatures) {
        for change in IRCChannelModeParser.membershipChanges(
            modeString: modeString, arguments: arguments,
            membership: features.membership, channelModes: features.channelModes
        ) {
            updateMembershipMode(change.mode, for: change.nickname, adding: change.adding, caseMapping: features.caseMapping)
        }
    }

    private func updateMembershipMode(_ mode: Character, for nickname: String, adding: Bool, caseMapping: IRCCaseMapping) {
        let key = caseMapping.normalize(nickname)
        var didChange = false
        if var member = session.pendingMembers?[key] {
            if adding { didChange = member.modes.insert(mode).inserted }
            else { didChange = member.modes.remove(mode) != nil }
            session.pendingMembers?[key] = member
        }
        guard let index = session.members.firstIndex(where: { caseMapping.normalize($0.nickname) == key }) else { return }
        if adding { didChange = session.members[index].modes.insert(mode).inserted || didChange }
        else { didChange = session.members[index].modes.remove(mode) != nil || didChange }
        guard didChange else { return }
        session.members = Self.sortedMembers(session.members)
        invalidateMembers()
    }

    func updateMemberIdentity(named nickname: String, username: String, hostname: String, caseMapping: IRCCaseMapping) {
        let key = caseMapping.normalize(nickname)
        var didChange = false
        if let index = session.members.firstIndex(where: { caseMapping.normalize($0.nickname) == key }) {
            session.members[index].username = username
            session.members[index].hostname = hostname
            didChange = true
        }
        if var member = session.pendingMembers?[key] {
            member.username = username
            member.hostname = hostname
            session.pendingMembers?[key] = member
            didChange = true
        }
        if didChange { invalidateMembers() }
    }

    func updateFeatures(_ features: IRCServerFeatures) {
        for index in session.members.indices { session.members[index].membership = features.membership }
        session.members = Self.sortedMembers(session.members)
        if let pending = session.pendingMembers {
            var rekeyed: [String: ChannelMember] = [:]
            for var member in pending.values {
                member.membership = features.membership
                rekeyed[features.caseMapping.normalize(member.nickname)] = member
            }
            session.pendingMembers = rekeyed
        }
        invalidateMembers()
    }

    private static func sortedMembers(_ members: [ChannelMember]) -> [ChannelMember] {
        members.sorted {
            let lhsRank = $0.privilegeRank ?? Int.max
            let rhsRank = $1.privilegeRank ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
    }
}
