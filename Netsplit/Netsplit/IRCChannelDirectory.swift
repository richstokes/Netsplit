import Combine
import Foundation

/// Owns LIST response staging, deduplication, caching, and request generations.
/// Buffered network rows publish only when flushed into the visible list.
@MainActor
final class IRCChannelDirectory: ObservableObject {
    private struct ListingState {
        var entries: [ChannelListing] = []
        var pending: [ChannelListing] = []
        var knownNames = Set<String>()
        var requestID: UUID?
        var flushID: UUID?
        var completedAt: Date?
    }

    private var servers: [UUID: ListingState] = [:]
    private let cacheLifetime: TimeInterval = 120

    func entries(for serverID: UUID) -> [ChannelListing] { servers[serverID]?.entries ?? [] }
    func isRequesting(_ serverID: UUID) -> Bool { servers[serverID]?.requestID != nil }

    func beginRequest(on serverID: UUID, hasArguments: Bool, forceRefresh: Bool, now: Date = .now) -> UUID? {
        guard !isRequesting(serverID) else { return nil }
        if !hasArguments, !forceRefresh, let completedAt = servers[serverID]?.completedAt,
           now.timeIntervalSince(completedAt) < cacheLifetime { return nil }
        objectWillChange.send()
        let requestID = UUID()
        servers[serverID] = ListingState(requestID: requestID)
        return requestID
    }

    func reset(_ serverID: UUID) {
        guard servers[serverID] != nil else { return }
        objectWillChange.send()
        servers.removeValue(forKey: serverID)
    }

    func enqueue(_ entry: ChannelListing, on serverID: UUID, caseMapping: IRCCaseMapping) {
        let key = caseMapping.normalize(entry.name)
        guard servers[serverID, default: .init()].knownNames.insert(key).inserted else { return }
        servers[serverID, default: .init()].pending.append(entry)
        guard servers[serverID]?.flushID == nil else { return }
        let flushID = UUID()
        servers[serverID]?.flushID = flushID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.servers[serverID]?.flushID == flushID else { return }
            self.flush(serverID)
        }
    }

    func complete(_ serverID: UUID, now: Date = .now) {
        guard isRequesting(serverID) else { return }
        flush(serverID)
        objectWillChange.send()
        servers[serverID]?.requestID = nil
        servers[serverID]?.completedAt = now
    }

    @discardableResult
    func fail(_ serverID: UUID, requestID: UUID? = nil, flushPending: Bool = true) -> Bool {
        guard isRequesting(serverID) else { return false }
        if let requestID, servers[serverID]?.requestID != requestID { return false }
        if flushPending { flush(serverID) }
        objectWillChange.send()
        servers[serverID]?.requestID = nil
        return true
    }

    private func flush(_ serverID: UUID) {
        guard let pending = servers[serverID]?.pending else { return }
        servers[serverID]?.flushID = nil
        guard !pending.isEmpty else { return }
        objectWillChange.send()
        servers[serverID]?.pending = []
        servers[serverID]?.entries.append(contentsOf: pending)
        servers[serverID]?.entries.sort {
            $0.userCount == $1.userCount
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.userCount > $1.userCount
        }
    }
}
