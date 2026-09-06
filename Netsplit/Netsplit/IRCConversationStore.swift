import Combine
import Foundation

/// Owns the lifetime of each transcript, composer, and channel's live state.
/// Only sidebar-visible changes use objectWillChange. Message/member traffic
/// continues to use conversation-scoped signals so busy servers do not redraw
/// the entire workspace.
@MainActor
final class IRCConversationStore: ObservableObject {
    @Published private(set) var channels: [Conversation] = []
    @Published private(set) var directMessages: [Conversation] = []

    private final class Record {
        var serverID: UUID?
        var messages: [IRCMessage] = []
        var hasInitializedTranscript = false
        var draft = ""
        var history = IRCComposerHistory()
        var messageSignal: IRCRevisionSignal?
        var channel: IRCChannelState?

        init(serverID: UUID?, channel: IRCChannelState? = nil) {
            self.serverID = serverID
            self.channel = channel
        }

        func invalidate() {
            messageSignal?.advance()
            channel?.onChange = nil
            channel?.disconnect()
        }
    }

    private var records: [SidebarItem: Record] = [:]
    private let inactiveSignal = IRCRevisionSignal()

    private func record(for item: SidebarItem) -> Record {
        if let record = records[item] { return record }
        let serverID: UUID?
        if case .server(let id) = item { serverID = id } else { serverID = nil }
        let record = Record(serverID: serverID)
        records[item] = record
        return record
    }

    func addChannel(_ conversation: Conversation) {
        guard !channels.contains(where: { $0.id == conversation.id }) else { return }
        let record = record(for: .channel(conversation.id))
        record.serverID = conversation.serverID
        record.channel = IRCChannelState()
        record.channel?.onChange = { [weak self] in self?.objectWillChange.send() }
        channels.append(conversation)
    }

    func addDirectMessage(_ conversation: Conversation) {
        guard !directMessages.contains(where: { $0.id == conversation.id }) else { return }
        record(for: .directMessage(conversation.id)).serverID = conversation.serverID
        directMessages.append(conversation)
    }

    func channel(_ id: UUID) -> IRCChannelState? {
        records[.channel(id)]?.channel
    }

    func remove(_ item: SidebarItem) {
        // Notify retained views even though the record itself is being retired.
        let removed = records.removeValue(forKey: item)
        switch item {
        case .channel(let id): channels.removeAll { $0.id == id }
        case .directMessage(let id): directMessages.removeAll { $0.id == id }
        case .connectionCenter, .server: break
        }
        removed?.invalidate()
    }

    func removeServer(_ serverID: UUID) {
        let items = records.compactMap { $0.value.serverID == serverID ? $0.key : nil }
        for item in items { remove(item) }
    }

    func disconnectChannels(on serverID: UUID) {
        for conversation in channels where conversation.serverID == serverID {
            channel(conversation.id)?.disconnect()
        }
    }

    private func transcriptRecord(for item: SidebarItem) -> Record? {
        switch item {
        case .server: return record(for: item)
        case .channel, .directMessage:
            guard let record = records[item], record.serverID != nil else { return nil }
            return record
        case .connectionCenter: return nil
        }
    }

    func messages(for item: SidebarItem) -> [IRCMessage] {
        records[item]?.messages ?? []
    }

    func initializeMessages(_ messages: [IRCMessage], for item: SidebarItem) {
        let record = record(for: item)
        guard !record.hasInitializedTranscript else { return }
        record.messages = messages
        record.hasInitializedTranscript = true
        record.messageSignal?.advance()
    }

    func append(_ message: IRCMessage, for item: SidebarItem) {
        guard item != .connectionCenter else { return }
        // Late transport callbacks must not recreate a closed conversation.
        guard let record = transcriptRecord(for: item) else { return }
        record.hasInitializedTranscript = true
        IRCConversationHistory.append(message, to: &record.messages)
        record.messageSignal?.advance()
    }

    func clearTranscript(for item: SidebarItem) {
        guard item != .connectionCenter else { return }
        guard let record = transcriptRecord(for: item) else { return }
        record.hasInitializedTranscript = true
        record.messages = []
        record.messageSignal?.advance()
    }

    @discardableResult
    func replaceMessage(_ message: IRCMessage, matchingID id: UUID, for item: SidebarItem) -> Bool {
        guard let record = records[item],
              let index = record.messages.firstIndex(where: { $0.id == id }) else { return false }
        record.messages[index] = message
        record.messageSignal?.advance()
        return true
    }

    func removeMessage(matchingID id: UUID, from item: SidebarItem) {
        guard let record = records[item],
              record.messages.contains(where: { $0.id == id }) else { return }
        record.messages.removeAll { $0.id == id }
        record.messageSignal?.advance()
    }

    func messageUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        guard item != .connectionCenter else { return inactiveSignal }
        let record = record(for: item)
        if let signal = record.messageSignal { return signal }
        let signal = IRCRevisionSignal(
            minimumPublicationInterval: IRCTranscriptUpdatePolicy.burstPublicationInterval
        )
        record.messageSignal = signal
        return signal
    }

    func memberUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        guard case .channel(let id) = item, let channel = channel(id) else { return inactiveSignal }
        return channel.memberUpdates
    }

    func draft(for item: SidebarItem) -> String { records[item]?.draft ?? "" }

    func setDraft(_ draft: String, for item: SidebarItem) {
        record(for: item).draft = draft
    }

    func recordComposerInput(_ input: String, for item: SidebarItem) {
        let input = IRCTextFraming.sanitizedSingleLine(input)
        guard !input.isEmpty else { return }
        record(for: item).history.record(input)
    }

    func navigateComposerHistory(
        _ direction: IRCComposerHistoryDirection, from draft: String, for item: SidebarItem
    ) -> String? {
        records[item]?.history.navigate(direction, from: draft)
    }

    func resetComposerHistoryNavigation(for item: SidebarItem) {
        records[item]?.history.resetNavigation()
    }

    /// The destination's draft wins; history and transcript content are retained
    /// from both conversations before the source record is retired as a whole.
    func mergeDirectMessage(_ source: Conversation, into destination: Conversation, isMuted: Bool) {
        let sourceItem = SidebarItem.directMessage(source.id)
        let destinationItem = SidebarItem.directMessage(destination.id)
        let target = record(for: destinationItem)
        if let old = records[sourceItem] {
            target.messages = IRCConversationHistory.merging(
                target.messages, old.messages, limit: IRCConversationHistory.retentionLimit
            )
            target.hasInitializedTranscript = true
            if target.draft.isEmpty { target.draft = old.draft }
            target.history.merge(old.history)
        }
        if let index = directMessages.firstIndex(where: { $0.id == destination.id }) {
            directMessages[index].hasUnread = IRCConversationActivityPolicy.mergedUnreadState(
                existingHasUnread: directMessages[index].hasUnread,
                incomingHasUnread: source.hasUnread,
                conversationIsMuted: isMuted
            )
        }
        target.messageSignal?.advance()
        remove(sourceItem)
    }

    func renameDirectMessage(_ id: UUID, to nickname: String) {
        guard let index = directMessages.firstIndex(where: { $0.id == id }) else { return }
        directMessages[index].name = nickname
        records[.directMessage(id)]?.messageSignal?.advance()
    }

    func markRead(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }),
                  channels[index].hasUnread || channels[index].hasMention else { return }
            channels[index].hasUnread = false
            channels[index].hasMention = false
        case .directMessage(let id):
            guard let index = directMessages.firstIndex(where: { $0.id == id }),
                  directMessages[index].hasUnread else { return }
            directMessages[index].hasUnread = false
        case .connectionCenter, .server: break
        }
    }

    func markAllRead(on serverID: UUID) {
        IRCConversationActivityPolicy.clearActivity(for: serverID, in: &channels)
        IRCConversationActivityPolicy.clearActivity(for: serverID, in: &directMessages)
    }

    func markUnread(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }), !channels[index].hasUnread else { return }
            channels[index].hasUnread = true
        case .directMessage(let id):
            guard let index = directMessages.firstIndex(where: { $0.id == id }), !directMessages[index].hasUnread else { return }
            directMessages[index].hasUnread = true
        case .connectionCenter, .server: break
        }
    }

    func markMention(_ item: SidebarItem) {
        guard case .channel(let id) = item,
              let index = channels.firstIndex(where: { $0.id == id }) else { return }
        channels[index].hasUnread = true
        channels[index].hasMention = true
        channels[index].mentionRevision &+= 1
    }
}
