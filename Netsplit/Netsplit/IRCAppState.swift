//
//  IRCAppState.swift
//  Netsplit
//

import Combine
import Foundation

@MainActor
final class IRCAppState: ObservableObject {
    @Published private(set) var profiles: [ServerProfile]
    @Published var nickname: String
    @Published var realName: String
    @Published var quitMessage: String {
        didSet { UserDefaults.standard.set(quitMessage, forKey: "quitMessage") }
    }
    @Published var reconnectAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(reconnectAutomatically, forKey: "reconnectAutomatically")
            if !reconnectAutomatically { cancelAllScheduledReconnects() }
        }
    }
    @Published var transcriptFontSize: Double
    @Published var selection: SidebarItem?
    @Published private(set) var channels: [Conversation] = []
    @Published private(set) var directMessages: [Conversation] = []
    @Published private(set) var connectionStatuses: [UUID: ConnectionStatus] = [:]
    @Published private(set) var messageRevision = 0
    @Published private(set) var memberRevision = 0
    @Published var isChannelBrowserPresented = false
    @Published private var listedChannelsByServer: [UUID: [ChannelListing]] = [:]
    @Published private var channelListsInProgress: Set<UUID> = []

    private var conversations: [UUID: [IRCMessage]] = [:]
    private var channelMembers: [UUID: [ChannelMember]] = [:]
    private var pendingChannelMembers: [UUID: [String: ChannelMember]] = [:]
    private var connections: [UUID: IRCConnection] = [:]
    private var activeNicknames: [UUID: String] = [:]
    private var registeredServerIDs = Set<UUID>()
    private var pendingNickDestinations: [UUID: SidebarItem] = [:]
    private var pendingWhoisDestinations: [String: SidebarItem] = [:]
    private var pendingTopicDestinations: [String: SidebarItem] = [:]
    private var pendingInvites: [String: PendingInvite] = [:]
    private var pendingModeDestinations: [String: SidebarItem] = [:]
    private var pendingKicks: [String: PendingKick] = [:]
    private var pendingKills: [String: PendingKill] = [:]
    private var pendingWhoDestinations: [String: SidebarItem] = [:]
    private var pendingMOTDDestinations: [UUID: SidebarItem] = [:]
    private var pendingVersionDestinations: [UUID: SidebarItem] = [:]
    private var pendingVersionRequestIDs: [UUID: UUID] = [:]
    private var pendingClientVersionDestinations: [String: SidebarItem] = [:]
    private var pendingClientVersionRequestIDs: [String: UUID] = [:]
    private var terminalServerErrors: [UUID: String] = [:]
    private var pendingOutgoingEchoes: [UUID: [PendingOutgoingEcho]] = [:]
    private var pendingChannelListingsByServer: [UUID: [ChannelListing]] = [:]
    private var knownChannelNamesByServer: [UUID: Set<String>] = [:]
    private var scheduledChannelListFlushes: Set<UUID> = []
    private var channelListCompletionDates: [UUID: Date] = [:]
    private var reconnectAttempts: [UUID: Int] = [:]
    private var scheduledReconnects: [UUID: UUID] = [:]
    private let channelListCacheLifetime: TimeInterval = 120
    private let favoriteJoinInterval: TimeInterval = 0.45
    private let initialReconnectDelay: TimeInterval = 2
    private let maximumReconnectDelay: TimeInterval = 60
    private static let defaultQuitMessage = "Closing macOS client"
    private var hasStartedLaunchConnections = false

    init() {
        let defaults = UserDefaults.standard
        let legacyAccountNickname = NSFullUserName().replacingOccurrences(of: " ", with: "").lowercased()
        let savedNickname = defaults.string(forKey: "nickname")
        if let savedNickname, !savedNickname.isEmpty, savedNickname != legacyAccountNickname {
            nickname = savedNickname
        } else {
            let anonymousNickname = Self.anonymousNickname()
            nickname = anonymousNickname
            defaults.set(anonymousNickname, forKey: "nickname")
        }
        let savedRealName = defaults.string(forKey: "realName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if savedRealName.isEmpty {
            let anonymousRealName = Self.anonymousRealName()
            realName = anonymousRealName
            defaults.set(anonymousRealName, forKey: "realName")
        } else {
            realName = savedRealName
        }
        let savedQuitMessage = defaults.string(forKey: "quitMessage")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        quitMessage = savedQuitMessage.isEmpty ? Self.defaultQuitMessage : savedQuitMessage
        reconnectAutomatically = defaults.object(forKey: "reconnectAutomatically") as? Bool ?? true
        let savedTranscriptFontSize = defaults.object(forKey: "transcriptFontSize") as? Double ?? 16
        transcriptFontSize = min(max(savedTranscriptFontSize, 12), 24)

        if let data = defaults.data(forKey: "profiles"), let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = Self.refreshedProfiles(from: saved)
        } else {
            profiles = ServerProfile.recommended
        }
        selection = .connectionCenter
    }

    var activeProfiles: [ServerProfile] {
        profiles.filter { connections[$0.id] != nil }
    }

    var selectedProfile: ServerProfile? {
        guard let selection else { return nil }
        return profile(for: selection)
    }

    var canBrowseSelectedChannels: Bool {
        guard let profile = selectedProfile else { return false }
        return registeredServerIDs.contains(profile.id)
    }

    func status(for profile: ServerProfile) -> ConnectionStatus {
        connectionStatuses[profile.id] ?? .offline
    }

    func isActive(_ profile: ServerProfile) -> Bool {
        connections[profile.id] != nil
    }

    func channels(for profile: ServerProfile) -> [Conversation] {
        channels
            .filter { $0.serverID == profile.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func directMessages(for profile: ServerProfile) -> [Conversation] {
        directMessages.filter { $0.serverID == profile.id }
    }

    func serverPassword(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "server-password"))
    }

    func saslPassword(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "sasl-password"))
    }

    func isFavorite(_ channel: Conversation) -> Bool {
        guard let profile = profiles.first(where: { $0.id == channel.serverID }) else { return false }
        return profile.favoriteChannels?.contains {
            $0.caseInsensitiveCompare(channel.name) == .orderedSame
        } ?? false
    }

    func toggleFavorite(_ channel: Conversation) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == channel.serverID }) else { return }
        var favorites = profiles[profileIndex].favoriteChannels ?? []
        if let index = favorites.firstIndex(where: { $0.caseInsensitiveCompare(channel.name) == .orderedSame }) {
            favorites.remove(at: index)
        } else {
            favorites.append(channel.name)
        }
        profiles[profileIndex].favoriteChannels = favorites.isEmpty ? nil : favorites
        saveProfiles()
    }

    func isMuted(_ nickname: String, from item: SidebarItem) -> Bool {
        guard let profile = profile(for: item) else { return false }
        return profile.mutedNicknames?.contains {
            $0.caseInsensitiveCompare(nickname) == .orderedSame
        } ?? false
    }

    func mute(_ nickname: String, from item: SidebarItem) {
        setMute(nickname, muted: true, from: item)
    }

    func unmute(_ nickname: String, from item: SidebarItem) {
        setMute(nickname, muted: false, from: item)
    }

    private func setMute(_ targetNickname: String, muted: Bool, from item: SidebarItem) {
        guard let profile = profile(for: item),
              let profileIndex = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let cleanNickname = targetNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNickname.isEmpty else { return }

        if cleanNickname.caseInsensitiveCompare(nickname(for: profiles[profileIndex])) == .orderedSame {
            appendSystem("You cannot mute your own nickname.", for: item)
            return
        }

        var mutedNicknames = profiles[profileIndex].mutedNicknames ?? []
        if muted {
            guard !mutedNicknames.contains(where: { $0.caseInsensitiveCompare(cleanNickname) == .orderedSame }) else {
                appendSystem("\(cleanNickname) is already muted.", for: item)
                return
            }
            mutedNicknames.append(cleanNickname)
            appendSystem("Muted \(cleanNickname) on \(profiles[profileIndex].name).", for: item)
        } else {
            guard let index = mutedNicknames.firstIndex(where: { $0.caseInsensitiveCompare(cleanNickname) == .orderedSame }) else {
                appendSystem("\(cleanNickname) is not muted.", for: item)
                return
            }
            mutedNicknames.remove(at: index)
            appendSystem("Unmuted \(cleanNickname) on \(profiles[profileIndex].name).", for: item)
        }
        profiles[profileIndex].mutedNicknames = mutedNicknames.isEmpty ? nil : mutedNicknames
        saveProfiles()
    }

    private func isMuted(_ nickname: String, on profile: ServerProfile) -> Bool {
        let currentProfile = profiles.first(where: { $0.id == profile.id }) ?? profile
        return currentProfile.mutedNicknames?.contains {
            $0.caseInsensitiveCompare(nickname) == .orderedSame
        } ?? false
    }

    func leave(_ channel: Conversation, reason: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == channel.serverID }) else { return }
        let part = reason?.isEmpty == false ? "PART \(channel.name) :\(reason!)" : "PART \(channel.name)"
        connections[profile.id]?.send(command: part)
        channels.removeAll { $0.id == channel.id }
        conversations.removeValue(forKey: channel.id)
        channelMembers.removeValue(forKey: channel.id)
        if selection == .channel(channel.id) {
            selection = .server(profile.id)
        }
        messageRevision += 1
        memberRevision += 1
    }

    func close(_ directMessage: Conversation) {
        guard let profile = profiles.first(where: { $0.id == directMessage.serverID }) else { return }
        directMessages.removeAll { $0.id == directMessage.id }
        conversations.removeValue(forKey: directMessage.id)
        if selection == .directMessage(directMessage.id) {
            selection = .server(profile.id)
        }
        messageRevision += 1
    }

    func connectSelectedProfile() {
        guard let profile = selectedProfile, connections[profile.id] == nil else { return }
        connect(profile)
    }

    func adjustTranscriptFontSize(by amount: Double) {
        setTranscriptFontSize(transcriptFontSize + amount)
    }

    func resetTranscriptFontSize() {
        setTranscriptFontSize(16)
    }

    func setTranscriptFontSize(_ size: Double) {
        let clampedSize = min(max(size.rounded(), 12), 24)
        guard transcriptFontSize != clampedSize else { return }
        transcriptFontSize = clampedSize
        UserDefaults.standard.set(clampedSize, forKey: "transcriptFontSize")
    }

    func connectProfilesConfiguredForLaunch() {
        guard !hasStartedLaunchConnections else { return }
        hasStartedLaunchConnections = true

        let originalSelection = selection
        for profile in profiles where profile.autoConnect {
            connect(profile)
        }
        selection = originalSelection
    }

    func toggleConnection(for profile: ServerProfile) {
        if connections[profile.id] != nil {
            if case .failed = status(for: profile) {
                disconnect(profile)
                connect(profile)
            } else {
                disconnect(profile)
            }
        } else {
            connect(profile)
        }
    }

    func connect(_ profile: ServerProfile, selectConversation: Bool = true, isAutomaticRetry: Bool = false) {
        guard connections[profile.id] == nil else { return }
        if !isAutomaticRetry { cancelScheduledReconnect(for: profile.id, resetAttempts: true) }
        terminalServerErrors.removeValue(forKey: profile.id)
        registeredServerIDs.remove(profile.id)
        activeNicknames[profile.id] = configuredNickname(for: profile)
        let transport = IRCConnection()
        connections[profile.id] = transport
        connectionStatuses[profile.id] = .connecting
        transport.eventHandler = { [weak self, weak transport] event in
            guard let transport else { return }
            DispatchQueue.main.async {
                self?.handle(event, from: profile, transport: transport)
            }
        }
        appendSystem("Connecting to \(profile.hostname)\(profile.useTLS ? " securely" : "")…", for: .server(profile.id))
        if selectConversation { selection = .server(profile.id) }
        transport.connect(profile: profile, nickname: nickname(for: profile), realName: resolvedRealName(), serverPassword: serverPassword(for: profile), saslUsername: profile.saslUsername, saslPassword: saslPassword(for: profile))
    }

    func disconnect(_ profile: ServerProfile, reason: String? = nil) {
        cancelScheduledReconnect(for: profile.id, resetAttempts: true)
        let transport = connections[profile.id]
        connections.removeValue(forKey: profile.id)
        activeNicknames.removeValue(forKey: profile.id)
        registeredServerIDs.remove(profile.id)
        connectionStatuses.removeValue(forKey: profile.id)
        terminalServerErrors.removeValue(forKey: profile.id)
        if let selection, self.profile(for: selection)?.id == profile.id {
            self.selection = .connectionCenter
        }
        transport?.quit(reason: reason ?? resolvedQuitMessage())
    }

    /// Used by the application delegate during termination. Completion is
    /// guaranteed quickly so quitting the app is never held up by a network
    /// problem, while active connections still get a real IRC QUIT command.
    func quitAllConnections(completion: @escaping () -> Void) {
        let activeConnections = connections.values
        guard !activeConnections.isEmpty else {
            completion()
            return
        }

        cancelAllScheduledReconnects()
        connections.removeAll()
        activeNicknames.removeAll()
        registeredServerIDs.removeAll()
        connectionStatuses.removeAll()
        terminalServerErrors.removeAll()

        let group = DispatchGroup()
        for connection in activeConnections {
            group.enter()
            connection.quit(reason: resolvedQuitMessage()) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            completion()
        }
    }

    func showConnections() {
        selection = .connectionCenter
    }

    func addProfile(name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, serverPassword: String, useSASL: Bool, saslUsername: String, saslPassword: String) {
        var profile = ServerProfile(name: name, hostname: hostname, port: port, useTLS: useTLS, autoConnect: autoConnect)
        profile.useSASL = useSASL
        profile.saslUsername = saslUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : saslUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles.append(profile)
        saveCredentials(for: profile, serverPassword: serverPassword, saslPassword: saslPassword)
        saveProfiles()
        selection = .connectionCenter
    }

    func delete(_ profile: ServerProfile) {
        guard !profile.isBuiltIn else { return }
        disconnect(profile)
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "server-password"))
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "sasl-password"))
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }

    func updateProfile(_ profile: ServerProfile, name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, nicknameOverride: String, serverPassword: String, useSASL: Bool, saslUsername: String, saslPassword: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.name = name
        updated.hostname = hostname
        updated.port = port
        updated.useTLS = useTLS
        updated.autoConnect = autoConnect
        let cleanNickname = nicknameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nicknameOverride = cleanNickname.isEmpty ? nil : cleanNickname
        updated.useSASL = useSASL
        let cleanSASLUsername = saslUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.saslUsername = cleanSASLUsername.isEmpty ? nil : cleanSASLUsername
        if updated.isBuiltIn { updated.isPresetModified = true }
        profiles[index] = updated
        saveCredentials(for: updated, serverPassword: serverPassword, saslPassword: saslPassword)
        saveProfiles()
    }

    func restorePreset(_ profile: ServerProfile) {
        guard profile.isBuiltIn,
              var preset = ServerProfile.recommended.first(where: { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }),
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        preset.id = profile.id
        preset.autoConnect = profile.autoConnect
        preset.favoriteChannels = profile.favoriteChannels
        preset.mutedNicknames = profile.mutedNicknames
        preset.useSASL = profile.useSASL
        preset.saslUsername = profile.saslUsername
        preset.isPresetModified = false
        profiles[index] = preset
        saveProfiles()
    }

    func saveIdentity() {
        UserDefaults.standard.set(nickname, forKey: "nickname")
        UserDefaults.standard.set(resolvedRealName(), forKey: "realName")
    }

    func messages(for item: SidebarItem) -> [IRCMessage] {
        guard let id = conversationID(for: item) else { return [] }
        return conversations[id] ?? []
    }

    func markRead(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }), channels[index].hasUnread else { return }
            channels[index].hasUnread = false
        case .directMessage(let id):
            guard let index = directMessages.firstIndex(where: { $0.id == id }), directMessages[index].hasUnread else { return }
            directMessages[index].hasUnread = false
        case .connectionCenter, .server:
            break
        }
    }

    func members(for item: SidebarItem) -> [ChannelMember] {
        guard case .channel(let id) = item else { return [] }
        let fallbackNickname = profile(for: item).map { nickname(for: $0) } ?? nickname
        return channelMembers[id] ?? [ChannelMember(nickname: fallbackNickname, prefix: nil)]
    }

    func channelListings(for profileID: UUID?) -> [ChannelListing] {
        guard let profileID else { return [] }
        return listedChannelsByServer[profileID] ?? []
    }

    func isChannelListingInProgress(for profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return channelListsInProgress.contains(profileID)
    }

    func requestChannelListing(forceRefresh: Bool = false) {
        guard let profile = selectedProfile else { return }
        requestChannelListing(for: profile, forceRefresh: forceRefresh)
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .connectionCenter: return "Connections"
        case .server(let id): return profiles.first { $0.id == id }?.name ?? "Server"
        case .channel(let id): return channels.first { $0.id == id }?.name ?? "Channel"
        case .directMessage(let id): return directMessages.first { $0.id == id }?.name ?? "Message"
        }
    }

    func subtitle(for item: SidebarItem) -> String {
        switch item {
        case .connectionCenter: return "Connect to a network or manage your profiles"
        case .server(let id):
            guard let profile = profiles.first(where: { $0.id == id }) else { return "" }
            return "\(profile.hostname) · \(profile.useTLS ? "TLS" : "Unencrypted")"
        case .channel, .directMessage: return profile(for: item)?.name ?? ""
        }
    }

    func join(_ listing: ChannelListing) {
        guard let profile = selectedProfile else { return }
        join(listing, on: profile, selectConversation: true)
    }

    private func joinFavoriteChannels(for profile: ServerProfile) {
        var seenChannelNames = Set<String>()
        let favoriteChannelNames = (profile.favoriteChannels ?? []).filter { channelName in
            let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seenChannelNames.insert(trimmed.lowercased()).inserted
        }

        for (index, channelName) in favoriteChannelNames.enumerated() {
            let delay = 0.25 + (Double(index) * favoriteJoinInterval)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.registeredServerIDs.contains(profile.id),
                      self.connections[profile.id] != nil,
                      let activeProfile = self.profiles.first(where: { $0.id == profile.id }) else { return }
                self.join(ChannelListing(name: channelName, userCount: 0, topic: ""), on: activeProfile, selectConversation: false)
            }
        }
    }

    private func join(_ listing: ChannelListing, on profile: ServerProfile, selectConversation: Bool) {
        if let channel = channels.first(where: { $0.name.caseInsensitiveCompare(listing.name) == .orderedSame && $0.serverID == profile.id }) {
            if selectConversation { selection = .channel(channel.id) }
            return
        }
        let channel = Conversation(name: listing.name, serverID: profile.id)
        channels.append(channel)
        channelMembers[channel.id] = [ChannelMember(nickname: nickname(for: profile), prefix: nil)]
        conversations[channel.id] = [IRCMessage(sender: "System", text: "Joined \(listing.name). \(listing.topic)", isSystem: true)]
        connections[profile.id]?.send(command: "JOIN \(listing.name)")
        if selectConversation { selection = .channel(channel.id) }
        messageRevision += 1
    }

    func beginNewConversation() {
        guard let profile = selectedProfile else { return }
        let conversation = Conversation(name: "new-message", serverID: profile.id)
        directMessages.append(conversation)
        conversations[conversation.id] = [IRCMessage(sender: "System", text: "Start a private conversation with /msg nickname your message.", isSystem: true)]
        selection = .directMessage(conversation.id)
        messageRevision += 1
    }

    func startDirectMessage(with nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item) else { return }
        let conversation = directMessage(named: nickname, serverID: profile.id)
        if conversations[conversation.id] == nil {
            conversations[conversation.id] = [IRCMessage(sender: "System", text: "Private conversation with \(nickname).", isSystem: true)]
            messageRevision += 1
        }
        selection = .directMessage(conversation.id)
    }

    func requestWhois(for nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item), !nickname.isEmpty else { return }
        pendingWhoisDestinations[whoisKey(serverID: profile.id, target: nickname)] = item
        connections[profile.id]?.send(command: "WHOIS \(nickname)")
        appendSystem("Looking up \(nickname)…", for: item)
    }

    func send(_ text: String, to item: SidebarItem) {
        if text.hasPrefix("/") {
            executeCommand(text, in: item)
            return
        }
        guard isMessageDestination(item), let profile = profile(for: item) else {
            appendSystem("Select a channel or private message before sending text.", for: item)
            return
        }
        let target = title(for: item)
        rememberOutgoingEcho(serverID: profile.id, target: target, text: text)
        connections[profile.id]?.send(command: "PRIVMSG \(target) :\(text)")
        append(IRCMessage(sender: nickname(for: profile), text: text), for: item)
    }

    private func executeCommand(_ input: String, in item: SidebarItem) {
        let parts = input.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.uppercased(), let profile = profile(for: item) else { return }
        let argument = parts.count > 1 ? parts[1] : ""
        switch command {
        case "SHOWMUTES":
            let mutedNicknames = (profile.mutedNicknames ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if mutedNicknames.isEmpty {
                appendSystem("No users are muted on \(profile.name).", for: item)
            } else {
                appendSystem("Muted on \(profile.name): \(mutedNicknames.joined(separator: ", ")).", for: item)
            }
        case "MUTE":
            guard !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /mute nickname", for: item)
                return
            }
            mute(argument, from: item)
        case "UNMUTE":
            guard !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /unmute nickname", for: item)
                return
            }
            unmute(argument, from: item)
        case "JOIN":
            let rawChannel = argument.split(separator: " ").first.map(String.init) ?? ""
            guard !rawChannel.isEmpty else {
                appendSystem("Usage: /join channel", for: item)
                return
            }
            let channel = rawChannel.first.map { "#&+!".contains($0) } == true ? rawChannel : "#\(rawChannel)"
            join(ChannelListing(name: channel, userCount: 0, topic: ""))
        case "LIST":
            requestChannelListing(for: profile, arguments: argument)
        case "MSG", "QUERY":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /msg nickname message", for: item); return }
            let conversation = directMessage(named: fields[0], serverID: profile.id)
            if conversations[conversation.id] == nil {
                conversations[conversation.id] = [IRCMessage(sender: "System", text: "Private conversation with \(fields[0]).", isSystem: true)]
            }
            rememberOutgoingEcho(serverID: profile.id, target: fields[0], text: fields[1])
            connections[profile.id]?.send(command: "PRIVMSG \(fields[0]) :\(fields[1])")
            append(IRCMessage(sender: nickname(for: profile), text: fields[1]), for: .directMessage(conversation.id))
            if command == "QUERY" { selection = .directMessage(conversation.id) }
        case "NOTICE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /notice target message", for: item); return }
            connections[profile.id]?.send(command: "NOTICE \(fields[0]) :\(fields[1])")
            appendSystem("Notice sent to \(fields[0]): \(fields[1])", for: item)
        case "ME":
            guard !argument.isEmpty else { return }
            guard isMessageDestination(item) else {
                appendSystem("Select a channel or private message before sending an action.", for: item)
                return
            }
            let target = title(for: item)
            let action = "\u{01}ACTION \(argument)\u{01}"
            rememberOutgoingEcho(serverID: profile.id, target: target, text: action)
            connections[profile.id]?.send(command: "PRIVMSG \(target) :\(action)")
            append(IRCMessage(sender: "* \(nickname(for: profile))", text: argument), for: item)
        case "SLAP":
            let recipient = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty else {
                appendSystem("Usage: /slap nickname", for: item)
                return
            }
            guard isMessageDestination(item) else {
                appendSystem("Select a channel or private message before sending a slap.", for: item)
                return
            }
            let target = title(for: item)
            let slap = "slaps \(recipient) around a bit with a large trout"
            let action = "\u{01}ACTION \(slap)\u{01}"
            rememberOutgoingEcho(serverID: profile.id, target: target, text: action)
            connections[profile.id]?.send(command: "PRIVMSG \(target) :\(action)")
            append(IRCMessage(sender: "* \(nickname(for: profile))", text: slap), for: item)
        case "VERSION":
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.isEmpty {
                requestServerVersion(for: profile, from: item)
            } else {
                requestClientVersion(of: target, on: profile, from: item)
            }
        case "CTCP":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2, fields[1].caseInsensitiveCompare("VERSION") == .orderedSame else {
                appendSystem("Usage: /ctcp nickname version", for: item)
                return
            }
            requestClientVersion(of: fields[0], on: profile, from: item)
        case "WHOIS":
            guard let target = argument.split(separator: " ").first.map(String.init), !target.isEmpty else {
                appendSystem("Usage: /whois nickname", for: item)
                return
            }
            requestWhois(for: target, from: item)
        case "WHO":
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { appendSystem("Usage: /who channel-or-nickname", for: item); return }
            pendingWhoDestinations[whoKey(serverID: profile.id, target: target)] = item
            connections[profile.id]?.send(command: "WHO \(target)")
            appendSystem("Looking up \(target)…", for: item)
        case "MOTD":
            pendingMOTDDestinations[profile.id] = item
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            connections[profile.id]?.send(command: target.isEmpty ? "MOTD" : "MOTD \(target)")
            appendSystem("Requesting the message of the day…", for: item)
        case "TOPIC":
            executeTopic(argument, on: profile, from: item)
        case "MODE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard let target = fields.first, !target.isEmpty else {
                appendSystem("Usage: /mode nickname flags or /mode #channel flags [arguments]", for: item)
                return
            }
            pendingModeDestinations[modeKey(serverID: profile.id, target: target)] = item
            connections[profile.id]?.send(command: "MODE \(argument)")
            let action = fields.count == 1 ? "Requesting modes for \(target)…" : "Changing modes for \(target)…"
            appendSystem(action, for: item)
        case "INVITE":
            let fields = argument.split(separator: " ", maxSplits: 2).map(String.init)
            guard fields.count == 2 else {
                appendSystem("Usage: /invite nickname #channel", for: item)
                return
            }
            let invitation = PendingInvite(serverID: profile.id, nickname: fields[0], channel: fields[1], destination: item)
            pendingInvites[inviteKey(serverID: profile.id, nickname: fields[0], channel: fields[1])] = invitation
            connections[profile.id]?.send(command: "INVITE \(fields[0]) \(fields[1])")
            appendSystem("Inviting \(fields[0]) to \(fields[1])…", for: item)
        case "KICK":
            let fields = argument.split(separator: " ", maxSplits: 2).map(String.init)
            guard fields.count >= 2 else {
                appendSystem("Usage: /kick #channel nickname [reason]", for: item)
                return
            }
            let reason = fields.count > 2 ? fields[2] : nil
            let key = kickKey(serverID: profile.id, channel: fields[0], nickname: fields[1])
            pendingKicks[key] = PendingKick(serverID: profile.id, channel: fields[0], nickname: fields[1], destination: item)
            let command = reason.map { "KICK \(fields[0]) \(fields[1]) :\($0)" } ?? "KICK \(fields[0]) \(fields[1])"
            connections[profile.id]?.send(command: command)
            appendSystem("Kicking \(fields[1]) from \(fields[0])…", for: item)
        case "KILL":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else {
                appendSystem("Usage: /kill nickname reason", for: item)
                return
            }
            let key = killKey(serverID: profile.id, nickname: fields[0])
            pendingKills[key] = PendingKill(serverID: profile.id, nickname: fields[0], destination: item)
            connections[profile.id]?.send(command: "KILL \(fields[0]) :\(fields[1])")
            appendSystem("Disconnecting \(fields[0]) from the network…", for: item)
        case "NICK":
            let newNickname = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newNickname.isEmpty else {
                appendSystem("Usage: /nick nickname", for: item)
                return
            }
            pendingNickDestinations[profile.id] = item
            connections[profile.id]?.send(command: "NICK \(newNickname)")
            appendSystem("Changing nickname to \(newNickname)…", for: item)
        case "PART":
            executePart(argument, on: profile, from: item)
        case "QUIT":
            let reason = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            disconnect(profile, reason: reason.isEmpty ? nil : reason)
        case "AWAY", "NAMES":
            connections[profile.id]?.send(command: "\(command) \(argument)")
            appendSystem("Sent /\(command.lowercased()) \(argument)", for: item)
        default:
            connections[profile.id]?.send(command: "\(command) \(argument)")
        }
    }

    private func executeTopic(_ argument: String, on profile: ServerProfile, from item: SidebarItem) {
        let trimmedArgument = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentChannel: Conversation? = {
            guard case .channel(let id) = item else { return nil }
            return channels.first(where: { $0.id == id && $0.serverID == profile.id })
        }()

        let targetChannel: Conversation
        let newTopic: String?
        if trimmedArgument.isEmpty {
            guard let currentChannel else {
                appendSystem("Usage: /topic #channel [topic]", for: item)
                return
            }
            targetChannel = currentChannel
            newTopic = nil
        } else {
            let fields = trimmedArgument.split(separator: " ", maxSplits: 1).map(String.init)
            if let namedChannel = existingChannel(named: fields[0], serverID: profile.id) {
                targetChannel = namedChannel
                newTopic = fields.count > 1 ? fields[1] : nil
            } else if let currentChannel {
                targetChannel = currentChannel
                newTopic = trimmedArgument
            } else {
                appendSystem("Join or select a channel, or use /topic #channel [topic].", for: item)
                return
            }
        }

        let key = topicKey(serverID: profile.id, channel: targetChannel.name)
        pendingTopicDestinations[key] = item
        if let newTopic {
            connections[profile.id]?.send(command: "TOPIC \(targetChannel.name) :\(newTopic)")
            appendSystem("Changing the topic for \(targetChannel.name)…", for: item)
        } else {
            connections[profile.id]?.send(command: "TOPIC \(targetChannel.name)")
            appendSystem("Requesting the topic for \(targetChannel.name)…", for: item)
        }
    }

    private func executePart(_ argument: String, on profile: ServerProfile, from item: SidebarItem) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentChannel: Conversation? = {
            guard case .channel(let id) = item else { return nil }
            return channels.first(where: { $0.id == id && $0.serverID == profile.id })
        }()
        if trimmed.isEmpty {
            guard let currentChannel else { appendSystem("Usage: /part [#channel] [reason]", for: item); return }
            leave(currentChannel)
            return
        }
        let fields = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        if let namedChannel = existingChannel(named: fields[0], serverID: profile.id) {
            leave(namedChannel, reason: fields.count > 1 ? fields[1] : nil)
        } else if let currentChannel {
            leave(currentChannel, reason: trimmed)
        } else {
            appendSystem("Join or select a channel, or use /part #channel [reason].", for: item)
        }
    }

    private func handle(_ event: IRCTransportEvent, from profile: ServerProfile, transport: IRCConnection) {
        guard connections[profile.id] === transport else { return }
        switch event {
        case .status(let status):
            if case .offline = status, terminalServerErrors[profile.id] != nil { return }
            if case .online = status {
                terminalServerErrors.removeValue(forKey: profile.id)
                connectionStatuses[profile.id] = registeredServerIDs.contains(profile.id) ? .online : .connecting
            } else {
                if case .offline = status { registeredServerIDs.remove(profile.id) }
                if case .failed = status { registeredServerIDs.remove(profile.id) }
                connectionStatuses[profile.id] = status
            }
            switch status {
            case .failed(let message):
                appendSystem(message, for: .server(profile.id))
                scheduleReconnect(for: profile)
            case .offline:
                appendSystem("Connection closed.", for: .server(profile.id))
                scheduleReconnect(for: profile)
            case .connecting, .online:
                break
            }
        case .notice(let text): appendSystem(text, for: .server(profile.id))
        case .received(let wire): handle(wire, profile: profile)
        }
    }

    private func handle(_ wire: IRCWireMessage, profile: ServerProfile) {
        let sender = wire.prefix?.split(separator: "!").first.map(String.init) ?? profile.name
        switch wire.command {
        case "001":
            registeredServerIDs.insert(profile.id)
            connectionStatuses[profile.id] = .online
            cancelScheduledReconnect(for: profile.id, resetAttempts: true)
            appendSystem(wire.trailing ?? "Connected.", for: .server(profile.id))
            joinFavoriteChannels(for: profile)
        case "NOTICE":
            guard let target = wire.parameters.first, let text = wire.trailing else { return }
            guard !isMuted(sender, on: profile) else { return }
            guard !handleCTCP(text, from: sender, target: target, profile: profile, canReplyToRequest: false) else { return }

            // IRC notices are delivered as a distinct message type, but they
            // still belong beside the conversation they address. Server notices
            // have no user mask and remain in the server log.
            if let first = target.first, "#&+!".contains(first) {
                guard sender.caseInsensitiveCompare(nickname(for: profile)) != .orderedSame else { return }
                let channel = channel(named: target, serverID: profile.id)
                append(IRCMessage(sender: "\(sender) (notice)", text: text), for: .channel(channel.id))
            } else if wire.prefix?.contains("!") == true,
                      sender.caseInsensitiveCompare(nickname(for: profile)) != .orderedSame {
                let conversation = directMessage(named: sender, serverID: profile.id)
                append(IRCMessage(sender: "\(sender) (notice)", text: text), for: .directMessage(conversation.id))
            } else {
                appendSystem(text, for: .server(profile.id))
            }
        case "PRIVMSG":
            guard let target = wire.parameters.first, let text = wire.trailing else { return }
            guard !isMuted(sender, on: profile) else { return }
            if handleCTCP(text, from: sender, target: target, profile: profile, canReplyToRequest: true) { return }
            // Servers with IRCv3 echo-message send our own PRIVMSG back to us.
            // The optimistic local row is already visible, so consume that echo.
            if sender.caseInsensitiveCompare(nickname(for: profile)) == .orderedSame,
               consumeOutgoingEcho(serverID: profile.id, target: target, text: text) {
                return
            }
            if target.hasPrefix("#") {
                let channel = channel(named: target, serverID: profile.id)
                append(IRCMessage(sender: sender, text: text), for: .channel(channel.id))
            } else if sender.caseInsensitiveCompare(nickname(for: profile)) != .orderedSame {
                let conversation = directMessage(named: sender, serverID: profile.id)
                append(IRCMessage(sender: sender, text: text), for: .directMessage(conversation.id))
            }
        case "JOIN":
            let channelName = wire.trailing ?? wire.parameters.last ?? ""
            if channelName.hasPrefix("#") {
                let channel = channel(named: channelName, serverID: profile.id)
                addMember(ChannelMember(nickname: sender, prefix: nil), to: channel.id)
                if sender.caseInsensitiveCompare(nickname(for: profile)) != .orderedSame {
                    appendChannelEvent("\(sender) joined \(channelName).", channelID: channel.id)
                }
            }
        case "PART":
            guard let channelName = wire.parameters.first,
                  let channel = existingChannel(named: channelName, serverID: profile.id) else { return }
            guard removeMember(named: sender, from: channel.id) else { return }
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            let subject = sender.caseInsensitiveCompare(nickname(for: profile)) == .orderedSame ? "You" : sender
            appendChannelEvent("\(subject) left \(channelName)\(reason).", channelID: channel.id)
        case "QUIT":
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            let pendingKillKey = killKey(serverID: profile.id, nickname: sender)
            if let pendingKill = pendingKills.removeValue(forKey: pendingKillKey) {
                appendSystem("Disconnected \(pendingKill.nickname) from the network\(reason).", for: pendingKill.destination)
            }
            for channel in channels(for: profile) where removeMember(named: sender, from: channel.id) {
                appendChannelEvent("\(sender) disconnected\(reason).", channelID: channel.id)
            }
        case "KICK":
            guard wire.parameters.count >= 2,
                  let channel = existingChannel(named: wire.parameters[0], serverID: profile.id) else { return }
            let target = wire.parameters[1]
            let pendingKick = pendingKicks.removeValue(forKey: kickKey(serverID: profile.id, channel: channel.name, nickname: target))
            _ = removeMember(named: target, from: channel.id)
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            appendChannelEvent("\(sender) removed \(target)\(reason).", channelID: channel.id)
            if let pendingKick, pendingKick.destination != .channel(channel.id) {
                appendSystem("Kicked \(pendingKick.nickname) from \(pendingKick.channel)\(reason).", for: pendingKick.destination)
            }
        case "KILL":
            guard let target = wire.parameters.first else { return }
            let key = killKey(serverID: profile.id, nickname: target)
            if let pendingKill = pendingKills.removeValue(forKey: key) {
                let reason = wire.trailing.map { " — \($0)" } ?? ""
                appendSystem("Disconnected \(pendingKill.nickname) from the network\(reason).", for: pendingKill.destination)
            }
        case "NICK":
            guard let newNickname = wire.trailing ?? wire.parameters.first, !newNickname.isEmpty else { return }
            let isLocalNicknameChange = sender.caseInsensitiveCompare(nickname(for: profile)) == .orderedSame
            let requestedDestination = isLocalNicknameChange ? pendingNickDestinations.removeValue(forKey: profile.id) : nil
            if isLocalNicknameChange {
                activeNicknames[profile.id] = newNickname
            }
            var deliveredConfirmation = false
            for channel in channels(for: profile) where renameMember(sender, to: newNickname, in: channel.id) {
                if isLocalNicknameChange {
                    appendChannelEvent("You are now known as \(newNickname).", channelID: channel.id)
                    if requestedDestination == .channel(channel.id) { deliveredConfirmation = true }
                } else {
                    appendChannelEvent("\(sender) is now known as \(newNickname).", channelID: channel.id)
                }
            }
            if isLocalNicknameChange, !deliveredConfirmation {
                appendSystem("You are now known as \(newNickname).", for: requestedDestination ?? .server(profile.id))
            }
        case "TOPIC":
            guard let channelName = wire.parameters.first,
                  let channel = existingChannel(named: channelName, serverID: profile.id),
                  let topic = wire.trailing else { return }
            let key = topicKey(serverID: profile.id, channel: channelName)
            let destination = pendingTopicDestinations.removeValue(forKey: key)
            appendChannelEvent("\(sender) changed the topic to: \(topic)", channelID: channel.id)
            if let destination, destination != .channel(channel.id) {
                appendSystem("Topic for \(channel.name): \(topic)", for: destination)
            }
        case "MODE":
            guard let target = wire.parameters.first else { return }
            let modeString = wire.parameters.dropFirst().first ?? ""
            let modeArguments = Array(wire.parameters.dropFirst(2)) + (wire.trailing.map { [$0] } ?? [])
            let changes = ([modeString] + modeArguments).joined(separator: " ")
            guard !changes.isEmpty else { return }
            let key = modeKey(serverID: profile.id, target: target)
            let destination = pendingModeDestinations.removeValue(forKey: key)
            if let channel = existingChannel(named: target, serverID: profile.id) {
                applyMembershipModes(modeString, arguments: modeArguments, to: channel.id)
                appendChannelEvent("\(sender) set mode \(changes) on \(target).", channelID: channel.id)
                if let destination, destination != .channel(channel.id) {
                    appendSystem("Modes for \(target) changed: \(changes)", for: destination)
                }
            } else {
                appendSystem("Modes for \(target) changed: \(changes)", for: destination ?? .server(profile.id))
            }
        case "353":
            guard wire.parameters.count >= 3 else { return }
            let channel = channel(named: wire.parameters[2], serverID: profile.id)
            stageMembers((wire.trailing ?? "").split(separator: " ").map(String.init).map(channelMember(from:)), for: channel.id)
        case "366":
            guard wire.parameters.count >= 2,
                  let channel = existingChannel(named: wire.parameters[1], serverID: profile.id) else { return }
            finishStagingMembers(for: channel.id)
        case "351":
            handleVersionReply(wire, serverID: profile.id)
        case "331", "332":
            handleTopicReply(wire, serverID: profile.id)
        case "341":
            handleInviteReply(wire, serverID: profile.id)
        case "221", "324":
            handleModeReply(wire, serverID: profile.id)
        case "352", "315":
            handleWhoReply(wire, serverID: profile.id)
        case "375", "372", "376", "422":
            handleMOTDReply(wire, serverID: profile.id)
        case "ERROR":
            let error = wire.trailing ?? "Server closed the connection."
            appendSystem(error, for: .server(profile.id))
            terminalServerErrors[profile.id] = error
            connectionStatuses[profile.id] = .failed(error)
            scheduleReconnect(for: profile)
        case "322":
            guard wire.parameters.count >= 3, let users = Int(wire.parameters[2]) else { return }
            let listing = ChannelListing(name: wire.parameters[1], userCount: users, topic: wire.trailing ?? "")
            queueChannelListing(listing, for: profile.id)
        case "323":
            flushChannelListings(for: profile.id)
            channelListsInProgress.remove(profile.id)
            channelListCompletionDates[profile.id] = Date()
        case "301", "311", "312", "313", "317", "318", "319", "330", "338", "378", "379", "671":
            handleWhoisReply(wire, serverID: profile.id)
        case "401":
            if !handleWhoisReply(wire, serverID: profile.id) {
                if !handleInviteError(wire, serverID: profile.id) {
                    handleModerationError(wire, serverID: profile.id)
                }
            }
        case "403", "442", "443", "473", "482":
            if !handleInviteError(wire, serverID: profile.id) {
                handleModerationError(wire, serverID: profile.id)
            }
        case "441", "481":
            handleModerationError(wire, serverID: profile.id)
        case "431", "432", "433", "436", "437":
            let destination = pendingNickDestinations.removeValue(forKey: profile.id) ?? .server(profile.id)
            appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
        case "421", "461":
            guard let destination = pendingVersionDestinations.removeValue(forKey: profile.id) else { return }
            pendingVersionRequestIDs.removeValue(forKey: profile.id)
            appendSystem("Server version request failed: \(wire.trailing ?? "The server rejected the request.")", for: destination)
        default: break
        }
    }

    @discardableResult
    private func handleWhoisReply(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        guard wire.parameters.count >= 2 else { return false }
        let target = wire.parameters[1]
        let key = whoisKey(serverID: serverID, target: target)
        guard let destination = pendingWhoisDestinations[key] else { return false }
        let message: String
        switch wire.command {
        case "301": message = "\(target) is away: \(wire.trailing ?? "away")"
        case "311":
            let user = wire.parameters.count > 2 ? wire.parameters[2] : "?"
            let host = wire.parameters.count > 3 ? wire.parameters[3] : "?"
            message = "\(target) is \(user)@\(host)\(wire.trailing.map { " — \($0)" } ?? "")"
        case "312": message = "\(target) is on \(wire.parameters.count > 2 ? wire.parameters[2] : "the server")\(wire.trailing.map { " — \($0)" } ?? "")"
        case "313": message = "\(target) is an IRC operator."
        case "317": message = "\(target) has been idle \(formatIdle(wire.parameters.count > 2 ? Int(wire.parameters[2]) ?? 0 : 0))."
        case "319": message = "\(target) is on: \(wire.trailing ?? "no visible channels")"
        case "330": message = "\(target) is logged in as \(wire.parameters.count > 2 ? wire.parameters[2] : "an account")."
        case "671": message = "\(target) is using a secure connection."
        case "318":
            message = "End of /WHOIS for \(target)."
            pendingWhoisDestinations.removeValue(forKey: key)
        case "401":
            message = wire.trailing ?? "No such nick: \(target)."
            pendingWhoisDestinations.removeValue(forKey: key)
        default: message = wire.trailing ?? "WHOIS information for \(target)."
        }
        appendSystem(message, for: destination)
        return true
    }

    private func handleInviteReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard wire.parameters.count >= 3 else { return }
        let nickname = wire.parameters[1]
        let channel = wire.parameters[2]
        let key = inviteKey(serverID: serverID, nickname: nickname, channel: channel)
        guard let invitation = pendingInvites.removeValue(forKey: key) else { return }
        appendSystem("Invited \(invitation.nickname) to \(invitation.channel).", for: invitation.destination)
    }

    @discardableResult
    private func handleInviteError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        let nickname = wire.command == "401" && wire.parameters.count > 1 ? wire.parameters[1] : nil
        let channel: String? = switch wire.command {
        case "403", "442", "473", "482": wire.parameters.count > 1 ? wire.parameters[1] : nil
        case "443": wire.parameters.count > 2 ? wire.parameters[2] : nil
        default: nil
        }
        guard let (key, invitation) = pendingInvites.first(where: { _, invitation in
            guard invitation.serverID == serverID else { return false }
            if let nickname, invitation.nickname.caseInsensitiveCompare(nickname) == .orderedSame { return true }
            if let channel, invitation.channel.caseInsensitiveCompare(channel) == .orderedSame { return true }
            return false
        }) else { return false }
        pendingInvites.removeValue(forKey: key)
        appendSystem("Invite failed: \(wire.trailing ?? "The server rejected the invite.")", for: invitation.destination)
        return true
    }

    @discardableResult
    private func handleModerationError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        let nickname: String? = switch wire.command {
        case "401": wire.parameters.count > 1 ? wire.parameters[1] : nil
        case "441": wire.parameters.count > 1 ? wire.parameters[1] : nil
        default: nil
        }
        let channel: String? = switch wire.command {
        case "403", "442", "482": wire.parameters.count > 1 ? wire.parameters[1] : nil
        case "441": wire.parameters.count > 2 ? wire.parameters[2] : nil
        default: nil
        }

        if let (key, kick) = pendingKicks.first(where: { _, kick in
            guard kick.serverID == serverID else { return false }
            if let nickname, kick.nickname.caseInsensitiveCompare(nickname) != .orderedSame { return false }
            if let channel, kick.channel.caseInsensitiveCompare(channel) != .orderedSame { return false }
            return nickname != nil || channel != nil
        }) {
            pendingKicks.removeValue(forKey: key)
            appendSystem("Kick failed: \(wire.trailing ?? "The server rejected the kick.")", for: kick.destination)
            return true
        }

        if let nickname,
           let (key, kill) = pendingKills.first(where: { _, kill in
               kill.serverID == serverID && kill.nickname.caseInsensitiveCompare(nickname) == .orderedSame
           }) {
            pendingKills.removeValue(forKey: key)
            appendSystem("Kill failed: \(wire.trailing ?? "The server rejected the kill.")", for: kill.destination)
            return true
        }
        if wire.command == "481", let (key, kill) = pendingKills.first(where: { _, kill in
            kill.serverID == serverID
        }) {
            pendingKills.removeValue(forKey: key)
            appendSystem("Kill failed: \(wire.trailing ?? "IRC operator privileges are required.")", for: kill.destination)
            return true
        }
        return false
    }

    private func handleModeReply(_ wire: IRCWireMessage, serverID: UUID) {
        let target: String
        let modes: String
        let arguments: String
        switch wire.command {
        case "221":
            guard let nickname = wire.parameters.first,
                  let userModes = wire.trailing ?? (wire.parameters.count > 1 ? wire.parameters[1] : nil) else { return }
            target = nickname
            modes = userModes
            arguments = ""
        case "324":
            guard wire.parameters.count >= 3 else { return }
            target = wire.parameters[1]
            modes = wire.parameters[2]
            arguments = (Array(wire.parameters.dropFirst(3)) + (wire.trailing.map { [$0] } ?? [])).joined(separator: " ")
        default:
            return
        }
        let key = modeKey(serverID: serverID, target: target)
        if let channel = existingChannel(named: target, serverID: serverID) {
            applyMembershipModes(modes, arguments: arguments.split(separator: " ").map(String.init), to: channel.id)
        }
        guard let destination = pendingModeDestinations.removeValue(forKey: key) else { return }
        let suffix = arguments.isEmpty ? "" : " \(arguments)"
        appendSystem("Modes for \(target): \(modes)\(suffix)", for: destination)
    }

    private func handleWhoReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard wire.parameters.count >= 2 else { return }
        let target = wire.command == "352" ? wire.parameters[1] : wire.parameters[1]
        let key = whoKey(serverID: serverID, target: target)
        guard let destination = pendingWhoDestinations[key] else { return }
        if wire.command == "352" {
            let user = wire.parameters.count > 2 ? wire.parameters[2] : "?"
            let host = wire.parameters.count > 3 ? wire.parameters[3] : "?"
            let nickname = wire.parameters.count > 5 ? wire.parameters[5] : "?"
            appendSystem("\(nickname) — \(user)@\(host)\(wire.trailing.map { " — \($0)" } ?? "")", for: destination)
        } else {
            pendingWhoDestinations.removeValue(forKey: key)
            appendSystem("End of /WHO for \(target).", for: destination)
        }
    }

    private func handleMOTDReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard let destination = pendingMOTDDestinations[serverID] else { return }
        switch wire.command {
        case "375":
            appendSystem(wire.trailing ?? "Message of the day:", for: destination)
        case "372":
            appendSystem(wire.trailing ?? "", for: destination)
        case "376":
            pendingMOTDDestinations.removeValue(forKey: serverID)
        case "422":
            pendingMOTDDestinations.removeValue(forKey: serverID)
            appendSystem(wire.trailing ?? "This server has no message of the day.", for: destination)
        default:
            break
        }
    }

    private func handleTopicReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard wire.parameters.count >= 2 else { return }
        let channelName = wire.parameters[1]
        let key = topicKey(serverID: serverID, channel: channelName)
        guard let destination = pendingTopicDestinations.removeValue(forKey: key) else { return }
        switch wire.command {
        case "331":
            appendSystem("\(channelName) has no topic.", for: destination)
        case "332":
            appendSystem("Topic for \(channelName): \(wire.trailing ?? "")", for: destination)
        default:
            break
        }
    }

    private func handleVersionReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard let destination = pendingVersionDestinations.removeValue(forKey: serverID) else { return }
        pendingVersionRequestIDs.removeValue(forKey: serverID)
        let version = wire.parameters.count > 1 ? wire.parameters[1] : "Unknown"
        let server = wire.parameters.count > 2 ? wire.parameters[2] : "the server"
        let details = wire.trailing.map { " — \($0)" } ?? ""
        appendSystem("\(server) is running \(version)\(details)", for: destination)
    }

    private func requestServerVersion(for profile: ServerProfile, from item: SidebarItem) {
        let requestID = UUID()
        pendingVersionDestinations[profile.id] = item
        pendingVersionRequestIDs[profile.id] = requestID
        connections[profile.id]?.send(command: "VERSION")
        appendSystem("Requesting server version…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.pendingVersionRequestIDs[profile.id] == requestID,
                  let destination = self.pendingVersionDestinations.removeValue(forKey: profile.id) else { return }
            self.pendingVersionRequestIDs.removeValue(forKey: profile.id)
            self.appendSystem("The server did not return a version reply.", for: destination)
        }
    }

    private func requestClientVersion(of nickname: String, on profile: ServerProfile, from item: SidebarItem) {
        let target = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let key = clientVersionKey(serverID: profile.id, nickname: target)
        let requestID = UUID()
        pendingClientVersionDestinations[key] = item
        pendingClientVersionRequestIDs[key] = requestID
        connections[profile.id]?.send(command: "PRIVMSG \(target) :\u{01}VERSION\u{01}")
        appendSystem("Requesting \(target)'s client version…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.pendingClientVersionRequestIDs[key] == requestID,
                  let destination = self.pendingClientVersionDestinations.removeValue(forKey: key) else { return }
            self.pendingClientVersionRequestIDs.removeValue(forKey: key)
            self.appendSystem("\(target) did not return a client version reply.", for: destination)
        }
    }

    @discardableResult
    private func handleCTCP(_ text: String, from sender: String, target: String, profile: ServerProfile, canReplyToRequest: Bool) -> Bool {
        guard text.first == "\u{01}", text.last == "\u{01}" else { return false }
        let payload = String(text.dropFirst().dropLast())
        let command = payload.split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = command.first?.uppercased() else { return false }

        switch name {
        case "ACTION":
            guard canReplyToRequest, command.count > 1 else { return false }
            if sender.caseInsensitiveCompare(nickname(for: profile)) == .orderedSame,
               consumeOutgoingEcho(serverID: profile.id, target: target, text: text) {
                return true
            }
            let message = IRCMessage(sender: "* \(sender)", text: command[1])
            if let first = target.first, "#&+!".contains(first) {
                let channel = channel(named: target, serverID: profile.id)
                append(message, for: .channel(channel.id))
            } else if sender.caseInsensitiveCompare(nickname(for: profile)) != .orderedSame {
                let conversation = directMessage(named: sender, serverID: profile.id)
                append(message, for: .directMessage(conversation.id))
            }
        case "VERSION":
            // A bare VERSION is a CTCP request. Reply privately with concise
            // client information; never send it back into a channel.
            if command.count == 1 {
                guard canReplyToRequest else { return false }
                connections[profile.id]?.send(command: "NOTICE \(sender) :\u{01}VERSION Netsplit 1.0 for macOS\u{01}")
                appendSystem("\(sender) requested Netsplit's version.", for: .server(profile.id))
            } else {
                let version = command[1]
                let key = clientVersionKey(serverID: profile.id, nickname: sender)
                let destination = pendingClientVersionDestinations.removeValue(forKey: key) ?? .server(profile.id)
                pendingClientVersionRequestIDs.removeValue(forKey: key)
                appendSystem("Version reply from \(sender): \(version)", for: destination)
            }
        default:
            return false
        }
        return true
    }

    private func clientVersionKey(serverID: UUID, nickname: String) -> String {
        "\(serverID.uuidString)|\(nickname.lowercased())"
    }

    private func profile(for item: SidebarItem) -> ServerProfile? {
        switch item {
        case .connectionCenter: return nil
        case .server(let id): return profiles.first { $0.id == id }
        case .channel(let id): return profiles.first { $0.id == channels.first { $0.id == id }?.serverID }
        case .directMessage(let id): return profiles.first { $0.id == directMessages.first { $0.id == id }?.serverID }
        }
    }

    private func conversationID(for item: SidebarItem) -> UUID? {
        switch item {
        case .connectionCenter: return nil
        case .server(let id), .channel(let id), .directMessage(let id): return id
        }
    }

    private func channel(named name: String, serverID: UUID) -> Conversation {
        if let existing = channels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.serverID == serverID }) { return existing }
        let conversation = Conversation(name: name, serverID: serverID)
        channels.append(conversation)
        let profileNickname = profiles.first(where: { $0.id == serverID }).map { nickname(for: $0) } ?? nickname
        channelMembers[conversation.id] = [ChannelMember(nickname: profileNickname, prefix: nil)]
        return conversation
    }

    private func existingChannel(named name: String, serverID: UUID) -> Conversation? {
        channels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.serverID == serverID }
    }

    private func directMessage(named name: String, serverID: UUID) -> Conversation {
        if let existing = directMessages.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.serverID == serverID }) { return existing }
        let conversation = Conversation(name: name, serverID: serverID)
        directMessages.append(conversation)
        return conversation
    }

    private func channelMember(from rawName: String) -> ChannelMember {
        guard let first = rawName.first, "~&@%+".contains(first) else { return ChannelMember(nickname: rawName, prefix: nil) }
        return ChannelMember(nickname: String(rawName.dropFirst()), prefix: first)
    }

    private func stageMembers(_ newMembers: [ChannelMember], for channelID: UUID) {
        var pending = pendingChannelMembers[channelID] ?? Dictionary(
            uniqueKeysWithValues: (channelMembers[channelID] ?? []).map { ($0.id, $0) }
        )
        for member in newMembers {
            upsert(member, into: &pending)
        }
        pendingChannelMembers[channelID] = pending
    }

    private func finishStagingMembers(for channelID: UUID) {
        guard let pending = pendingChannelMembers.removeValue(forKey: channelID) else { return }
        channelMembers[channelID] = sortedMembers(Array(pending.values))
        memberRevision += 1
    }

    private func addMember(_ member: ChannelMember, to channelID: UUID) {
        var members = channelMembers[channelID] ?? []
        upsert(member, into: &members)
        if var pending = pendingChannelMembers[channelID] {
            upsert(member, into: &pending)
            pendingChannelMembers[channelID] = pending
        }
        channelMembers[channelID] = sortedMembers(members)
        memberRevision += 1
    }

    @discardableResult
    private func removeMember(named nickname: String, from channelID: UUID) -> Bool {
        if var pending = pendingChannelMembers[channelID] {
            pending.removeValue(forKey: nickname.lowercased())
            pendingChannelMembers[channelID] = pending
        }
        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { $0.nickname.caseInsensitiveCompare(nickname) == .orderedSame }) else { return false }
        members.remove(at: index)
        channelMembers[channelID] = members
        memberRevision += 1
        return true
    }

    @discardableResult
    private func renameMember(_ oldNickname: String, to newNickname: String, in channelID: UUID) -> Bool {
        if var pending = pendingChannelMembers[channelID], let member = pending.removeValue(forKey: oldNickname.lowercased()) {
            pending[newNickname.lowercased()] = ChannelMember(nickname: newNickname, modes: member.modes)
            pendingChannelMembers[channelID] = pending
        }
        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { $0.nickname.caseInsensitiveCompare(oldNickname) == .orderedSame }) else { return false }
        members[index].nickname = newNickname
        channelMembers[channelID] = sortedMembers(members)
        memberRevision += 1
        return true
    }

    /// Applies channel membership modes such as +o, -v, +h, and +q to the
    /// member list. Non-membership modes consume their IRC parameters so a
    /// mixed MODE command (for example +klo key 50 nick) stays aligned.
    private func applyMembershipModes(_ modeString: String, arguments: [String], to channelID: UUID) {
        var adding = true
        var argumentIndex = 0

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
                let nickname = arguments[argumentIndex]
                argumentIndex += 1
                updateMembershipMode(mode, for: nickname, adding: adding, in: channelID)
            } else if channelModeConsumesArgument(mode, adding: adding) {
                argumentIndex += 1
            }
        }
    }

    private func channelModeConsumesArgument(_ mode: Character, adding: Bool) -> Bool {
        switch mode {
        case "b", "e", "I", "k": true
        case "l", "f", "j", "L": adding
        default: false
        }
    }

    private func updateMembershipMode(_ mode: Character, for nickname: String, adding: Bool, in channelID: UUID) {
        var didChange = false

        if var pending = pendingChannelMembers[channelID], let member = pending[nickname.lowercased()] {
            var updated = member
            if adding {
                didChange = updated.modes.insert(mode).inserted || didChange
            } else {
                didChange = updated.modes.remove(mode) != nil || didChange
            }
            pending[updated.id] = updated
            pendingChannelMembers[channelID] = pending
        }

        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { $0.nickname.caseInsensitiveCompare(nickname) == .orderedSame }) else { return }
        if adding {
            didChange = members[index].modes.insert(mode).inserted || didChange
        } else {
            didChange = members[index].modes.remove(mode) != nil || didChange
        }
        guard didChange else { return }
        channelMembers[channelID] = sortedMembers(members)
        memberRevision += 1
    }

    private func upsert(_ member: ChannelMember, into members: inout [ChannelMember]) {
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            if member.prefix != nil { members[index] = member }
        } else {
            members.append(member)
        }
    }

    private func upsert(_ member: ChannelMember, into members: inout [String: ChannelMember]) {
        if let existing = members[member.id] {
            if member.prefix != nil || existing.prefix == nil { members[member.id] = member }
        } else {
            members[member.id] = member
        }
    }

    private func sortedMembers(_ members: [ChannelMember]) -> [ChannelMember] {
        members.sorted { lhs, rhs in
            if (lhs.role != nil) != (rhs.role != nil) { return lhs.role != nil }
            return lhs.nickname.localizedCaseInsensitiveCompare(rhs.nickname) == .orderedAscending
        }
    }

    private func isMessageDestination(_ item: SidebarItem) -> Bool {
        if case .channel = item { return true }
        if case .directMessage = item { return true }
        return false
    }

    private func nickname(for profile: ServerProfile) -> String {
        activeNicknames[profile.id] ?? configuredNickname(for: profile)
    }

    private func configuredNickname(for profile: ServerProfile) -> String {
        let override = profile.nicknameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? nickname : override
    }

    private func resolvedRealName() -> String {
        let trimmedRealName = realName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRealName.isEmpty else {
            let anonymousRealName = Self.anonymousRealName()
            realName = anonymousRealName
            UserDefaults.standard.set(anonymousRealName, forKey: "realName")
            return anonymousRealName
        }
        return trimmedRealName
    }

    private func resolvedQuitMessage() -> String {
        let trimmedMessage = quitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? Self.defaultQuitMessage : trimmedMessage
    }

    private func scheduleReconnect(for profile: ServerProfile) {
        guard reconnectAutomatically,
              connections[profile.id] != nil,
              scheduledReconnects[profile.id] == nil else { return }

        let attempt = reconnectAttempts[profile.id, default: 0] + 1
        reconnectAttempts[profile.id] = attempt
        let delay = min(initialReconnectDelay * pow(2, Double(attempt - 1)), maximumReconnectDelay)
        let requestID = UUID()
        scheduledReconnects[profile.id] = requestID
        appendSystem("Connection lost. Reconnecting in \(Int(delay)) seconds (attempt \(attempt))…", for: .server(profile.id))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.reconnectAutomatically,
                  self.scheduledReconnects[profile.id] == requestID,
                  let activeProfile = self.profiles.first(where: { $0.id == profile.id }),
                  let failedTransport = self.connections.removeValue(forKey: profile.id) else { return }
            self.scheduledReconnects.removeValue(forKey: profile.id)
            self.activeNicknames.removeValue(forKey: profile.id)
            self.registeredServerIDs.remove(profile.id)
            self.terminalServerErrors.removeValue(forKey: profile.id)
            failedTransport.disconnect()
            self.connect(activeProfile, selectConversation: false, isAutomaticRetry: true)
        }
    }

    private func cancelScheduledReconnect(for serverID: UUID, resetAttempts: Bool) {
        scheduledReconnects.removeValue(forKey: serverID)
        if resetAttempts { reconnectAttempts.removeValue(forKey: serverID) }
    }

    private func cancelAllScheduledReconnects() {
        scheduledReconnects.removeAll()
        reconnectAttempts.removeAll()
    }

    private func appendSystem(_ text: String, for item: SidebarItem) {
        append(IRCMessage(sender: "System", text: text, isSystem: true), for: item)
    }

    private func appendChannelEvent(_ text: String, channelID: UUID) {
        append(IRCMessage(sender: "•", text: text, isSystem: true), for: .channel(channelID))
    }

    private func append(_ message: IRCMessage, for item: SidebarItem) {
        guard let id = conversationID(for: item) else { return }
        conversations[id, default: []].append(message)
        if !message.isSystem && selection != item { markUnread(item) }
        messageRevision += 1
    }

    private func markUnread(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
            channels[index].hasUnread = true
        case .directMessage(let id):
            guard let index = directMessages.firstIndex(where: { $0.id == id }) else { return }
            directMessages[index].hasUnread = true
        case .connectionCenter, .server:
            break
        }
    }

    private func formatIdle(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    private func whoisKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(target.lowercased())"
    }

    private func whoKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(target.lowercased())"
    }

    private func topicKey(serverID: UUID, channel: String) -> String {
        "\(serverID.uuidString)|\(channel.lowercased())"
    }

    private func inviteKey(serverID: UUID, nickname: String, channel: String) -> String {
        "\(serverID.uuidString)|\(nickname.lowercased())|\(channel.lowercased())"
    }

    private func modeKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(target.lowercased())"
    }

    private func kickKey(serverID: UUID, channel: String, nickname: String) -> String {
        "\(serverID.uuidString)|\(channel.lowercased())|\(nickname.lowercased())"
    }

    private func killKey(serverID: UUID, nickname: String) -> String {
        "\(serverID.uuidString)|\(nickname.lowercased())"
    }

    private func rememberOutgoingEcho(serverID: UUID, target: String, text: String) {
        pruneOutgoingEchoes(for: serverID)
        pendingOutgoingEchoes[serverID, default: []].append(
            PendingOutgoingEcho(target: target, text: text, sentAt: Date())
        )
    }

    private func consumeOutgoingEcho(serverID: UUID, target: String, text: String) -> Bool {
        pruneOutgoingEchoes(for: serverID)
        guard var pending = pendingOutgoingEchoes[serverID],
              let index = pending.firstIndex(where: {
                  $0.target.caseInsensitiveCompare(target) == .orderedSame && $0.text == text
              }) else { return false }
        pending.remove(at: index)
        pendingOutgoingEchoes[serverID] = pending
        return true
    }

    private func pruneOutgoingEchoes(for serverID: UUID) {
        pendingOutgoingEchoes[serverID]?.removeAll { Date().timeIntervalSince($0.sentAt) > 30 }
    }

    private func requestChannelListing(for profile: ServerProfile, arguments: String = "", forceRefresh: Bool = false) {
        guard registeredServerIDs.contains(profile.id) else {
            appendSystem("Wait for the server to finish connecting before browsing channels.", for: .server(profile.id))
            return
        }
        isChannelBrowserPresented = true
        guard !channelListsInProgress.contains(profile.id) else { return }

        let hasArguments = !arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasArguments,
           !forceRefresh,
           let completionDate = channelListCompletionDates[profile.id],
           Date().timeIntervalSince(completionDate) < channelListCacheLifetime {
            return
        }

        listedChannelsByServer[profile.id] = []
        pendingChannelListingsByServer[profile.id] = []
        knownChannelNamesByServer[profile.id] = []
        scheduledChannelListFlushes.remove(profile.id)
        channelListsInProgress.insert(profile.id)
        connections[profile.id]?.send(command: hasArguments ? "LIST \(arguments)" : "LIST")
    }

    private func queueChannelListing(_ listing: ChannelListing, for serverID: UUID) {
        let key = listing.name.lowercased()
        var knownNames = knownChannelNamesByServer[serverID] ?? []
        guard knownNames.insert(key).inserted else { return }
        knownChannelNamesByServer[serverID] = knownNames
        pendingChannelListingsByServer[serverID, default: []].append(listing)

        guard scheduledChannelListFlushes.insert(serverID).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.flushChannelListings(for: serverID)
        }
    }

    private func flushChannelListings(for serverID: UUID) {
        scheduledChannelListFlushes.remove(serverID)
        guard let pending = pendingChannelListingsByServer[serverID], !pending.isEmpty else { return }
        pendingChannelListingsByServer[serverID] = []
        var listings = listedChannelsByServer[serverID] ?? []
        listings.append(contentsOf: pending)
        listings.sort {
            $0.userCount == $1.userCount
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.userCount > $1.userCount
        }
        listedChannelsByServer[serverID] = listings
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: "profiles")
    }

    private func saveCredentials(for profile: ServerProfile, serverPassword: String, saslPassword: String) {
        KeychainStore.set(serverPassword, for: credentialAccount(profile: profile, kind: "server-password"))
        KeychainStore.set(saslPassword, for: credentialAccount(profile: profile, kind: "sasl-password"))
    }

    private func credentialAccount(profile: ServerProfile, kind: String) -> String {
        "\(kind).\(profile.id.uuidString)"
    }

    private static func refreshedProfiles(from saved: [ServerProfile]) -> [ServerProfile] {
        let refreshed = saved.map { profile -> ServerProfile in
            guard profile.isBuiltIn,
                  profile.isPresetModified != true,
                  var current = ServerProfile.recommended.first(where: { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }) else { return profile }
            current.id = profile.id
            current.autoConnect = profile.autoConnect
            current.favoriteChannels = profile.favoriteChannels
            current.mutedNicknames = profile.mutedNicknames
            current.useSASL = profile.useSASL
            current.saslUsername = profile.saslUsername
            return current
        }
        let missing = ServerProfile.recommended.filter { recommended in
            !refreshed.contains { $0.isBuiltIn && $0.name.caseInsensitiveCompare(recommended.name) == .orderedSame }
        }
        return refreshed + missing
    }

    private static func anonymousNickname() -> String {
        "netsplit" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
    }

    private static func anonymousRealName() -> String {
        "Netsplit User " + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
    }
}

private struct PendingOutgoingEcho {
    var target: String
    var text: String
    var sentAt: Date
}

private struct PendingInvite {
    var serverID: UUID
    var nickname: String
    var channel: String
    var destination: SidebarItem
}

private struct PendingKick {
    var serverID: UUID
    var channel: String
    var nickname: String
    var destination: SidebarItem
}

private struct PendingKill {
    var serverID: UUID
    var nickname: String
    var destination: SidebarItem
}
