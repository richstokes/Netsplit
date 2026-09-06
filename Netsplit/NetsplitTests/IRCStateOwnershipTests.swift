import Combine
import Foundation
import Testing
@testable import Netsplit

@Suite("State ownership")
@MainActor
struct IRCStateOwnershipTests {
    @Test("Channel directory changes reach a retained UI subscription")
    func channelDirectoryObservation() throws {
        let directory = IRCChannelDirectory()
        let serverID = UUID()
        var publications = 0
        let subscription = directory.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        _ = try #require(directory.beginRequest(on: serverID, hasArguments: false, forceRefresh: false))
        #expect(publications == 1)
        directory.enqueue(ChannelListing(name: "#swift", userCount: 5, topic: "Swift"), on: serverID, caseMapping: .rfc1459)
        #expect(publications == 1)
        directory.complete(serverID)
        #expect(publications == 3)
        directory.reset(serverID)
        #expect(publications == 4)
    }

    @Test("Disconnect resets live channel state while retaining history, composer, and rejoin information")
    func disconnectRetainsConversation() throws {
        let store = IRCConversationStore()
        let conversation = Conversation(name: "#shared", serverID: UUID())
        let other = Conversation(name: "#shared", serverID: UUID())
        store.addChannel(conversation)
        store.addChannel(other)
        let item = SidebarItem.channel(conversation.id)
        let channel = try #require(store.channel(conversation.id))
        let otherChannel = try #require(store.channel(other.id))
        channel.prepareToJoin(topic: "Retained topic", key: "rejoin-key")
        channel.joinedAt = ContinuousClock().now
        channel.addMember(ChannelMember(nickname: "Alice"), caseMapping: .rfc1459)
        channel.stageMembers([ChannelMember(nickname: "Pending")], caseMapping: .rfc1459)
        let oldRequest = channel.beginBanRequest()
        channel.receiveBan(IRCBanEntry(channel: "#shared", mask: "*!*@example.invalid"))
        otherChannel.joinedAt = ContinuousClock().now
        otherChannel.addMember(ChannelMember(nickname: "Bob"), caseMapping: .rfc1459)
        store.append(IRCMessage(sender: "Alice", text: "Retained message"), for: item)
        store.setDraft("Unsent draft", for: item)
        store.recordComposerInput("Earlier input", for: item)
        let messages = store.messageUpdates(for: item)
        let members = store.memberUpdates(for: item)

        store.disconnectChannels(on: conversation.serverID)

        #expect(store.channel(conversation.id) === channel)
        #expect(channel.joinedAt == nil)
        #expect(channel.members.isEmpty)
        #expect(channel.bans.isEmpty)
        #expect(!channel.isRequestingBans)
        #expect(channel.banError == nil)
        #expect(channel.topic == "Retained topic")
        #expect(channel.joinKey == "rejoin-key")
        #expect(store.messages(for: item).map(\.text) == ["Retained message"])
        #expect(store.draft(for: item) == "Unsent draft")
        #expect(store.navigateComposerHistory(.previous, from: "", for: item) == "Earlier input")
        #expect(store.messageUpdates(for: item) === messages)
        #expect(store.memberUpdates(for: item) === members)
        #expect(messages.revision == 0)
        #expect(members.revision == 1)
        #expect(otherChannel.joinedAt != nil)
        #expect(otherChannel.members.map(\.nickname) == ["Bob"])

        // A delayed NAMES completion or timeout cannot restore the old session.
        channel.finishStagingMembers()
        channel.failBanRequest("Stale timeout", requestID: oldRequest)
        #expect(channel.members.isEmpty)
        #expect(channel.banError == nil)
        let newRequest = channel.beginBanRequest()
        channel.failBanRequest("Old timeout after rejoin", requestID: oldRequest)
        #expect(channel.isRequestingBans)
        channel.failBanRequest("Current timeout", requestID: newRequest)
        #expect(channel.banError == "Current timeout")
    }

    @Test("Removing one server retires all its conversations and server transcript without touching another server")
    func removeServer() throws {
        let store = IRCConversationStore()
        let serverID = UUID()
        let channel = Conversation(name: "#shared", serverID: serverID)
        let direct = Conversation(name: "Alice", serverID: serverID)
        let other = Conversation(name: "#shared", serverID: UUID())
        store.addChannel(channel)
        store.addDirectMessage(direct)
        store.addChannel(other)
        let items: [SidebarItem] = [.server(serverID), .channel(channel.id), .directMessage(direct.id)]
        for item in items {
            store.append(IRCMessage(sender: "Alice", text: "Old transcript"), for: item)
            store.setDraft("Old draft", for: item)
            store.recordComposerInput("Old input", for: item)
        }
        let signals = items.map { store.messageUpdates(for: $0) }
        let channelState = try #require(store.channel(channel.id))
        let requestID = channelState.beginBanRequest()
        let otherItem = SidebarItem.channel(other.id)
        store.append(IRCMessage(sender: "Bob", text: "Keep me"), for: otherItem)
        store.setDraft("Keep draft", for: otherItem)
        let otherSignal = store.messageUpdates(for: otherItem)

        store.removeServer(serverID)

        #expect(store.channels == [other])
        #expect(store.directMessages.isEmpty)
        #expect(store.channel(channel.id) == nil)
        for (index, item) in items.enumerated() {
            #expect(store.messages(for: item).isEmpty)
            #expect(store.draft(for: item).isEmpty)
            #expect(store.navigateComposerHistory(.previous, from: "", for: item) == nil)
            #expect(signals[index].revision == 1)
        }
        #expect(store.messages(for: otherItem).map(\.text) == ["Keep me"])
        #expect(store.draft(for: otherItem) == "Keep draft")
        #expect(otherSignal.revision == 0)

        store.append(IRCMessage(sender: "Alice", text: "Late delivery"), for: .channel(channel.id))
        #expect(store.messages(for: .channel(channel.id)).isEmpty)
        channelState.failBanRequest("Late timeout", requestID: requestID)
        #expect(channelState.banError == nil)
    }

    @Test("Merging private conversations retains destination draft and both histories, and retires the source")
    func mergeDirectMessages() {
        let store = IRCConversationStore()
        let serverID = UUID()
        let source = Conversation(name: "OldNick", serverID: serverID)
        let destination = Conversation(name: "NewNick", serverID: serverID)
        store.addDirectMessage(source)
        store.addDirectMessage(destination)
        let oldItem = SidebarItem.directMessage(source.id)
        let newItem = SidebarItem.directMessage(destination.id)
        store.append(IRCMessage(sender: "OldNick", text: "Old message"), for: oldItem)
        store.append(IRCMessage(sender: "NewNick", text: "New message"), for: newItem)
        store.setDraft("Source draft", for: oldItem)
        store.setDraft("Destination draft", for: newItem)
        store.recordComposerInput("Source input", for: oldItem)
        store.recordComposerInput("Destination input", for: newItem)
        let oldSignal = store.messageUpdates(for: oldItem)
        let newSignal = store.messageUpdates(for: newItem)

        store.mergeDirectMessage(source, into: destination, isMuted: false)

        #expect(store.directMessages == [destination])
        #expect(Set(store.messages(for: newItem).map(\.text)) == ["Old message", "New message"])
        #expect(store.draft(for: newItem) == "Destination draft")
        let recalled = [
            store.navigateComposerHistory(.previous, from: "", for: newItem),
            store.navigateComposerHistory(.previous, from: "", for: newItem)
        ].compactMap { $0 }
        #expect(Set(recalled) == ["Source input", "Destination input"])
        #expect(store.messages(for: oldItem).isEmpty)
        #expect(store.draft(for: oldItem).isEmpty)
        #expect(store.navigateComposerHistory(.previous, from: "", for: oldItem) == nil)
        #expect(oldSignal.revision == 1)
        #expect(newSignal.revision == 1)
    }

    @Test("Transcript and member traffic stay local while topic and sidebar changes publish globally")
    func scopedObservation() throws {
        let store = IRCConversationStore()
        let conversation = Conversation(name: "#shared", serverID: UUID())
        store.addChannel(conversation)
        let item = SidebarItem.channel(conversation.id)
        let channel = try #require(store.channel(conversation.id))
        let messageSignal = store.messageUpdates(for: item)
        let memberSignal = store.memberUpdates(for: item)
        var publications = 0
        let subscription = store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        store.append(IRCMessage(sender: "Alice", text: "Hello"), for: item)
        channel.addMember(ChannelMember(nickname: "Alice"), caseMapping: .rfc1459)
        #expect(publications == 0)
        #expect(messageSignal.revision == 1)
        #expect(memberSignal.revision == 1)
        channel.topic = "Changed topic"
        #expect(publications == 1)
        store.markUnread(item)
        #expect(publications == 2)
    }

    @Test("A completed or superseded LIST request cannot be failed by its old callback")
    func listingRequestGenerations() throws {
        let directory = IRCChannelDirectory()
        let firstServer = UUID()
        let secondServer = UUID()
        let oldRequest = try #require(directory.beginRequest(on: firstServer, hasArguments: false, forceRefresh: false))
        directory.enqueue(ChannelListing(name: "#stale", userCount: 1, topic: ""), on: firstServer, caseMapping: .rfc1459)
        directory.reset(firstServer)
        let currentRequest = try #require(directory.beginRequest(on: firstServer, hasArguments: false, forceRefresh: false))
        _ = directory.beginRequest(on: secondServer, hasArguments: false, forceRefresh: false)
        directory.enqueue(ChannelListing(name: "#current", userCount: 5, topic: ""), on: firstServer, caseMapping: .rfc1459)
        directory.enqueue(ChannelListing(name: "#CURRENT", userCount: 99, topic: ""), on: firstServer, caseMapping: .rfc1459)
        #expect(!directory.fail(firstServer, requestID: oldRequest))
        #expect(directory.isRequesting(firstServer))
        directory.complete(firstServer)
        #expect(directory.entries(for: firstServer).map(\.name) == ["#current"])
        #expect(!directory.fail(firstServer, requestID: currentRequest))
        #expect(directory.isRequesting(secondServer))
        #expect(directory.beginRequest(on: firstServer, hasArguments: false, forceRefresh: false) == nil)
        #expect(directory.beginRequest(on: firstServer, hasArguments: false, forceRefresh: true) != nil)
    }
}
