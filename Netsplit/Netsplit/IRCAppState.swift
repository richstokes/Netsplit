//
//  IRCAppState.swift
//  Netsplit
//

import Combine
import Foundation

@MainActor
final class IRCRevisionSignal: ObservableObject {
    @Published private(set) var revision = 0

    func advance() {
        revision &+= 1
    }
}

@MainActor
final class IRCAppState: ObservableObject {
    @Published private(set) var profiles: [ServerProfile]
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "nickname") }
    }
    @Published var realName: String {
        didSet { UserDefaults.standard.set(realName, forKey: "realName") }
    }
    @Published var quitMessage: String {
        didSet { UserDefaults.standard.set(quitMessage, forKey: "quitMessage") }
    }
    @Published var reconnectAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(reconnectAutomatically, forKey: "reconnectAutomatically")
            if !reconnectAutomatically { cancelAllScheduledReconnects() }
        }
    }
    @Published var warnBeforeOpeningLinks: Bool {
        didSet { UserDefaults.standard.set(warnBeforeOpeningLinks, forKey: "warnBeforeOpeningLinks") }
    }
    @Published var applicationAppearance: IRCApplicationAppearance {
        didSet { UserDefaults.standard.set(applicationAppearance.rawValue, forKey: "applicationAppearance") }
    }
    @Published var messageSpacing: IRCMessageSpacing {
        didSet { UserDefaults.standard.set(messageSpacing.rawValue, forKey: "messageSpacing") }
    }
    @Published var usesColoredNicknames: Bool {
        didSet { UserDefaults.standard.set(usesColoredNicknames, forKey: "usesColoredNicknames") }
    }
    @Published var usesMonospacedServerMessages: Bool {
        didSet { UserDefaults.standard.set(usesMonospacedServerMessages, forKey: "usesMonospacedServerMessages") }
    }
    @Published var rendersIRCFormatting: Bool {
        didSet { UserDefaults.standard.set(rendersIRCFormatting, forKey: "rendersIRCFormatting") }
    }
    @Published var channelEventVisibility: IRCChannelEventVisibility {
        didSet { UserDefaults.standard.set(channelEventVisibility.rawValue, forKey: "channelEventVisibility") }
    }
    @Published var transcriptFontSize: Double
    @Published var selection: SidebarItem? {
        didSet { recordSelectionChange(from: oldValue) }
    }
    @Published var showsMemberList: Bool {
        didSet { UserDefaults.standard.set(showsMemberList, forKey: "showsMemberList") }
    }
    @Published var showsServerChannelPane = true
    @Published private(set) var channels: [Conversation] = []
    @Published private(set) var directMessages: [Conversation] = []
    @Published private(set) var connectionStatuses: [UUID: ConnectionStatus] = [:]
    @Published private var channelTopics: [UUID: String] = [:]
    @Published var isChannelBrowserPresented = false
    @Published private var listedChannelsByServer: [UUID: [ChannelListing]] = [:]
    @Published private var channelListsInProgress: Set<UUID> = []

    private var conversations: [UUID: [IRCMessage]] = [:]
    private var conversationDrafts: [SidebarItem: String] = [:]
    private var channelMembers: [UUID: [ChannelMember]] = [:]
    private var messageUpdateSignals: [UUID: IRCRevisionSignal] = [:]
    private var memberUpdateSignals: [UUID: IRCRevisionSignal] = [:]
    private var muteSnapshotsByServer: [UUID: IRCMuteSnapshot] = [:]
    private let inactiveUpdateSignal = IRCRevisionSignal()
    private var pendingChannelMembers: [UUID: [String: ChannelMember]] = [:]
    private var connections: [UUID: IRCConnection] = [:]
    private var pendingJoins: [String: PendingJoin] = [:]
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
    private var channelListRequestIDs: [UUID: UUID] = [:]
    private var reconnectAttempts: [UUID: Int] = [:]
    private var scheduledReconnects: [UUID: UUID] = [:]
    private var registrationNicknameSuffixes: [UUID: Set<Int>] = [:]
    private var caseMappings: [UUID: IRCCaseMapping] = [:]
    private var sessionIDs: [UUID: UUID] = [:]
    private var sessionOnConnectCommands: [UUID: [String]] = [:]
    private let channelListCacheLifetime: TimeInterval = 120
    private let channelListRequestTimeout: TimeInterval = 30
    private let favoriteJoinInterval: TimeInterval = 0.45
    private let onConnectCommandInterval: TimeInterval = 0.5
    private let favoriteJoinDelayAfterCommands: TimeInterval = 2
    private let initialReconnectDelay: TimeInterval = 2
    private let maximumReconnectDelay: TimeInterval = 60
    private static let defaultQuitMessage = "Closing macOS client"
    private var hasStartedLaunchConnections = false
    private var isSystemSleeping = false
    private var systemSleepServerIDs = Set<UUID>()
    private var systemWakeGeneration: UUID?
    private var backSelectionHistory: [SidebarItem] = []
    private var forwardSelectionHistory: [SidebarItem] = []
    private var isNavigatingSelectionHistory = false
    private let maximumSelectionHistoryCount = 100

    init() {
        let defaults = UserDefaults.standard
        let legacyAccountNickname = NSFullUserName().replacingOccurrences(of: " ", with: "").lowercased()
        let savedNickname = defaults.string(forKey: "nickname")
        if let savedNickname,
           IRCIdentityValidation.isValidNickname(savedNickname),
           savedNickname != legacyAccountNickname {
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
        warnBeforeOpeningLinks = defaults.object(forKey: "warnBeforeOpeningLinks") as? Bool ?? true
        applicationAppearance = defaults.string(forKey: "applicationAppearance").flatMap(IRCApplicationAppearance.init(rawValue:)) ?? .system
        messageSpacing = defaults.string(forKey: "messageSpacing").flatMap(IRCMessageSpacing.init(rawValue:)) ?? .comfortable
        usesColoredNicknames = defaults.object(forKey: "usesColoredNicknames") as? Bool ?? false
        usesMonospacedServerMessages = defaults.object(forKey: "usesMonospacedServerMessages") as? Bool ?? true
        rendersIRCFormatting = defaults.object(forKey: "rendersIRCFormatting") as? Bool ?? false
        channelEventVisibility = defaults.string(forKey: "channelEventVisibility").flatMap(IRCChannelEventVisibility.init(rawValue:)) ?? .alwaysShow
        showsMemberList = defaults.object(forKey: "showsMemberList") as? Bool ?? true
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
        IRCServerOrdering.alphabetically(
            profiles.filter { connections[$0.id] != nil }
        )
    }

    var selectedProfile: ServerProfile? {
        guard let selection else { return nil }
        return profile(for: selection)
    }

    var canBrowseSelectedChannels: Bool {
        guard let profile = selectedProfile else { return false }
        return registeredServerIDs.contains(profile.id)
    }

    var canToggleMemberList: Bool {
        guard case .channel(let id) = selection else { return false }
        return channels.contains { $0.id == id }
    }

    var canCloseActiveSelection: Bool {
        guard let selection else { return false }
        switch selection {
        case .connectionCenter:
            return false
        case .server(let id):
            return profiles.contains { $0.id == id }
        case .channel(let id):
            return channels.contains { $0.id == id }
        case .directMessage(let id):
            return directMessages.contains { $0.id == id }
        }
    }

    var canNavigateBack: Bool {
        backSelectionHistory.contains { isValidNavigationSelection($0) }
    }

    var canNavigateForward: Bool {
        forwardSelectionHistory.contains { isValidNavigationSelection($0) }
    }

    func toggleMemberList() {
        guard canToggleMemberList else { return }
        showsMemberList.toggle()
    }

    func toggleServerChannelPane() {
        showsServerChannelPane.toggle()
    }

    func closeActiveSelection() {
        guard let selection else { return }
        switch selection {
        case .connectionCenter:
            return
        case .server(let id):
            guard let profile = profiles.first(where: { $0.id == id }) else { return }
            disconnect(profile)
            self.selection = .connectionCenter
        case .channel(let id):
            guard let channel = channels.first(where: { $0.id == id }) else { return }
            leave(channel)
        case .directMessage(let id):
            guard let directMessage = directMessages.first(where: { $0.id == id }) else { return }
            close(directMessage)
        }
    }

    func navigateBack() {
        while let destination = backSelectionHistory.popLast() {
            guard isValidNavigationSelection(destination) else { continue }
            if let selection, isValidNavigationSelection(selection) {
                appendToForwardHistory(selection)
            }
            selectFromHistory(destination)
            return
        }
    }

    func navigateForward() {
        while let destination = forwardSelectionHistory.popLast() {
            guard isValidNavigationSelection(destination) else { continue }
            if let selection, isValidNavigationSelection(selection) {
                appendToBackHistory(selection)
            }
            selectFromHistory(destination)
            return
        }
    }

    func status(for profile: ServerProfile) -> ConnectionStatus {
        connectionStatuses[profile.id] ?? .offline
    }

    func isWaitingToReconnect(_ profile: ServerProfile) -> Bool {
        scheduledReconnects[profile.id] != nil
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

    func activity(for profile: ServerProfile) -> IRCServerActivity {
        IRCServerActivity(
            serverID: profile.id,
            conversations: channels + directMessages
        )
    }

    func draft(for item: SidebarItem) -> String {
        conversationDrafts[item] ?? ""
    }

    func setDraft(_ draft: String, for item: SidebarItem) {
        if draft.isEmpty {
            conversationDrafts.removeValue(forKey: item)
        } else {
            conversationDrafts[item] = draft
        }
    }

    func serverPassword(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "server-password"))
    }

    func saslPassword(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "sasl-password"))
    }

    func sshPassword(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "ssh-password"))
    }

    func sshPrivateKey(for profile: ServerProfile) -> String {
        KeychainStore.value(for: credentialAccount(profile: profile, kind: "ssh-private-key"))
    }

    func onConnectCommands(for profile: ServerProfile) -> [String] {
        let encoded = KeychainStore.value(for: credentialAccount(profile: profile, kind: "on-connect-commands"))
        guard let data = encoded.data(using: .utf8),
              let commands = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return commands
    }

    func isFavorite(_ channel: Conversation) -> Bool {
        guard let profile = profiles.first(where: { $0.id == channel.serverID }) else { return false }
        return profile.favoriteChannels?.contains {
            identifiersEqual($0, channel.name, serverID: profile.id)
        } ?? false
    }

    func toggleFavorite(_ channel: Conversation) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == channel.serverID }) else { return }
        var favorites = profiles[profileIndex].favoriteChannels ?? []
        if let index = favorites.firstIndex(where: { identifiersEqual($0, channel.name, serverID: channel.serverID) }) {
            favorites.remove(at: index)
        } else {
            favorites.append(channel.name)
        }
        profiles[profileIndex].favoriteChannels = favorites.isEmpty ? nil : favorites
        saveProfiles()
    }

    func isMuted(_ nickname: String, from item: SidebarItem) -> Bool {
        muteSnapshot(for: item)?.contains(nickname) ?? false
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

        if identifiersEqual(cleanNickname, nickname(for: profiles[profileIndex]), serverID: profile.id) {
            appendSystem("You cannot mute your own nickname.", for: item)
            return
        }

        var mutedNicknames = profiles[profileIndex].mutedNicknames ?? []
        if muted {
            guard !mutedNicknames.contains(where: { identifiersEqual($0, cleanNickname, serverID: profile.id) }) else {
                appendSystem("\(cleanNickname) is already muted.", for: item)
                return
            }
            mutedNicknames.append(cleanNickname)
            appendSystem("Muted \(cleanNickname) on \(profiles[profileIndex].name).", for: item)
        } else {
            guard let index = mutedNicknames.firstIndex(where: { identifiersEqual($0, cleanNickname, serverID: profile.id) }) else {
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
        muteSnapshot(for: profile).contains(nickname)
    }

    func leave(_ channel: Conversation, reason: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == channel.serverID }) else { return }
        let part = reason?.isEmpty == false ? "PART \(channel.name) :\(reason!)" : "PART \(channel.name)"
        connections[profile.id]?.send(command: part)
        removeChannelConversation(channel)
    }

    func close(_ directMessage: Conversation) {
        guard let profile = profiles.first(where: { $0.id == directMessage.serverID }) else { return }
        directMessages.removeAll { $0.id == directMessage.id }
        conversations.removeValue(forKey: directMessage.id)
        conversationDrafts.removeValue(forKey: .directMessage(directMessage.id))
        if selection == .directMessage(directMessage.id) {
            selection = .server(profile.id)
        }
        messagesDidChange(for: directMessage.id)
        messageUpdateSignals.removeValue(forKey: directMessage.id)
    }

    func muteAndClose(_ directMessage: Conversation) {
        mute(directMessage.name, from: .directMessage(directMessage.id))
        close(directMessage)
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
            connect(profile, selectConversation: false)
        }
        selection = originalSelection
    }

    /// A sleeping Mac can retain sockets that look active locally even though
    /// their remote TCP/SSH state has expired. Close them before networking is
    /// frozen, then recreate only the sessions that were active after wake.
    func systemWillSleep() {
        guard !isSystemSleeping else { return }
        isSystemSleeping = true
        systemWakeGeneration = nil

        let reconnectingServerIDs = Set(scheduledReconnects.keys)
        let serverIDsToRestore = Set(connections.keys.filter { serverID in
            IRCSystemSleepPolicy.shouldRestoreConnection(
                status: connectionStatuses[serverID] ?? .offline,
                reconnectWasScheduled: reconnectingServerIDs.contains(serverID)
            )
        })
        systemSleepServerIDs.formUnion(serverIDsToRestore)

        for serverID in serverIDsToRestore {
            cancelScheduledReconnect(for: serverID, resetAttempts: true)
            let transport = connections.removeValue(forKey: serverID)
            sessionIDs.removeValue(forKey: serverID)
            sessionOnConnectCommands.removeValue(forKey: serverID)
            activeNicknames.removeValue(forKey: serverID)
            registeredServerIDs.remove(serverID)
            terminalServerErrors.removeValue(forKey: serverID)
            registrationNicknameSuffixes.removeValue(forKey: serverID)
            connectionStatuses[serverID] = .offline
            prepareChannelsForDisconnectedSession(for: serverID)
            resetChannelListingRequest(for: serverID)
            transport?.disconnect()
        }
    }

    func systemDidWake() {
        guard isSystemSleeping else { return }
        isSystemSleeping = false

        let generation = UUID()
        systemWakeGeneration = generation
        let serverIDsToRestore = systemSleepServerIDs

        // Give Wi-Fi and DNS a short opportunity to become usable. Normal
        // reconnect backoff remains in force if the path needs longer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self,
                  !self.isSystemSleeping,
                  self.systemWakeGeneration == generation else { return }
            self.systemWakeGeneration = nil
            for profile in self.profiles where serverIDsToRestore.contains(profile.id) {
                guard self.systemSleepServerIDs.remove(profile.id) != nil else { continue }
                self.connect(profile, selectConversation: false)
            }
        }
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
        caseMappings[profile.id] = .rfc1459
        sessionIDs[profile.id] = UUID()
        sessionOnConnectCommands[profile.id] = onConnectCommands(for: profile)
        prepareChannelsForDisconnectedSession(for: profile.id)
        resetChannelListingRequest(for: profile.id)
        terminalServerErrors.removeValue(forKey: profile.id)
        registeredServerIDs.remove(profile.id)
        registrationNicknameSuffixes.removeValue(forKey: profile.id)
        activeNicknames[profile.id] = configuredNickname(for: profile)
        let transport = IRCConnection()
        connections[profile.id] = transport
        connectionStatuses[profile.id] = .connecting
        transport.eventHandler = { [weak self, weak transport] event in
            guard let transport else { return }
            self?.handle(event, from: profile, transport: transport)
        }
        let route = profile.useSSHTunnel == true ? " through \(profile.sshHostname ?? "the SSH tunnel")" : ""
        appendSystem("Connecting to \(profile.hostname)\(profile.useTLS ? " securely" : "")\(route)…", for: .server(profile.id))
        if selectConversation, selection.flatMap({ self.profile(for: $0)?.id }) != profile.id {
            selection = .server(profile.id)
        }
        transport.connect(
            profile: profile,
            nickname: nickname(for: profile),
            realName: resolvedRealName(),
            serverPassword: serverPassword(for: profile),
            saslUsername: profile.saslUsername,
            saslPassword: saslPassword(for: profile),
            sshPassword: sshPassword(for: profile),
            sshPrivateKey: sshPrivateKey(for: profile)
        )
    }

    func disconnect(_ profile: ServerProfile, reason: String? = nil) {
        systemSleepServerIDs.remove(profile.id)
        cancelScheduledReconnect(for: profile.id, resetAttempts: true)
        resetChannelListingRequest(for: profile.id)
        prepareChannelsForDisconnectedSession(for: profile.id)
        let transport = connections[profile.id]
        connections.removeValue(forKey: profile.id)
        sessionIDs.removeValue(forKey: profile.id)
        sessionOnConnectCommands.removeValue(forKey: profile.id)
        activeNicknames.removeValue(forKey: profile.id)
        registeredServerIDs.remove(profile.id)
        connectionStatuses.removeValue(forKey: profile.id)
        terminalServerErrors.removeValue(forKey: profile.id)
        registrationNicknameSuffixes.removeValue(forKey: profile.id)
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
        sessionIDs.removeAll()
        sessionOnConnectCommands.removeAll()
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

    func addProfile(name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, serverPassword: String, useSASL: Bool, saslUsername: String, saslPassword: String, onConnectCommands: [String], useSSHTunnel: Bool, sshHostname: String, sshPort: UInt16, sshUsername: String, sshPassword: String, sshPrivateKey: String, sshKeyFilename: String?) {
        var profile = ServerProfile(name: name, hostname: hostname, port: port, useTLS: useTLS, autoConnect: autoConnect)
        profile.useSASL = useSASL
        profile.saslUsername = saslUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : saslUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        applySSHSettings(to: &profile, enabled: useSSHTunnel, hostname: sshHostname, port: sshPort, username: sshUsername, keyFilename: sshKeyFilename)
        profiles.append(profile)
        saveCredentials(for: profile, serverPassword: serverPassword, saslPassword: saslPassword, onConnectCommands: onConnectCommands, sshPassword: sshPassword, sshPrivateKey: sshPrivateKey)
        saveProfiles()
        selection = .connectionCenter
    }

    func delete(_ profile: ServerProfile) {
        guard !profile.isBuiltIn else { return }
        disconnect(profile)
        removeConversations(for: profile.id)
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "server-password"))
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "sasl-password"))
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "on-connect-commands"))
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "ssh-password"))
        KeychainStore.remove(account: credentialAccount(profile: profile, kind: "ssh-private-key"))
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }

    func updateProfile(_ profile: ServerProfile, name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, nicknameOverride: String, serverPassword: String, useSASL: Bool, saslUsername: String, saslPassword: String, onConnectCommands: [String], useSSHTunnel: Bool, sshHostname: String, sshPort: UInt16, sshUsername: String, sshPassword: String, sshPrivateKey: String, sshKeyFilename: String?, resetSSHHostKey: Bool) {
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
        let oldSSHIdentity = "\(profile.sshHostname ?? ""):\(profile.sshPort ?? 22)"
        applySSHSettings(to: &updated, enabled: useSSHTunnel, hostname: sshHostname, port: sshPort, username: sshUsername, keyFilename: sshKeyFilename)
        let newSSHIdentity = "\(updated.sshHostname ?? ""):\(updated.sshPort ?? 22)"
        if oldSSHIdentity != newSSHIdentity || resetSSHHostKey { updated.sshTrustedHostKey = nil }
        if updated.isBuiltIn { updated.isPresetModified = true }
        profiles[index] = updated
        saveCredentials(for: updated, serverPassword: serverPassword, saslPassword: saslPassword, onConnectCommands: onConnectCommands, sshPassword: sshPassword, sshPrivateKey: sshPrivateKey)
        saveProfiles()
    }

    func restorePreset(_ profile: ServerProfile) {
        guard profile.isBuiltIn,
              var preset = Self.preset(matching: profile),
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        preset.id = profile.id
        preset.autoConnect = profile.autoConnect
        preset.favoriteChannels = profile.favoriteChannels
        preset.mutedNicknames = profile.mutedNicknames
        preset.useSASL = profile.useSASL
        preset.saslUsername = profile.saslUsername
        preset.useSSHTunnel = profile.useSSHTunnel
        preset.sshHostname = profile.sshHostname
        preset.sshPort = profile.sshPort
        preset.sshUsername = profile.sshUsername
        preset.sshKeyFilename = profile.sshKeyFilename
        preset.sshTrustedHostKey = profile.sshTrustedHostKey
        preset.isPresetModified = false
        profiles[index] = preset
        saveProfiles()
    }

    func saveIdentity() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if IRCIdentityValidation.isValidNickname(trimmedNickname), nickname != trimmedNickname {
            nickname = trimmedNickname
        }
        guard IRCIdentityValidation.isValidNickname(nickname) else { return }
        UserDefaults.standard.set(nickname, forKey: "nickname")
        UserDefaults.standard.set(resolvedRealName(), forKey: "realName")
    }

    func messages(
        for item: SidebarItem,
        channelEventVisibility visibility: IRCChannelEventVisibility
    ) -> [IRCMessage] {
        guard let id = conversationID(for: item) else { return [] }
        let messages = conversations[id] ?? []
        guard case .channel = item, visibility != .alwaysShow else { return messages }
        return messages.filter { message in
            guard message.channelEventKind != nil else { return true }
            return visibility.shouldShow(memberCount: message.channelMemberCount ?? 0)
        }
    }

    func messageUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        updateSignal(for: conversationID(for: item), in: &messageUpdateSignals)
    }

    func markRead(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
            channels[index].hasUnread = false
            channels[index].hasMention = false
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

    func memberUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        let channelID: UUID?
        if case .channel(let id) = item {
            channelID = id
        } else {
            channelID = nil
        }
        return updateSignal(for: channelID, in: &memberUpdateSignals)
    }

    func muteSnapshot(for item: SidebarItem) -> IRCMuteSnapshot? {
        guard let profile = profile(for: item) else { return nil }
        return muteSnapshot(for: profile)
    }

    func topic(for item: SidebarItem) -> String? {
        guard case .channel(let id) = item,
              let topic = channelTopics[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !topic.isEmpty else { return nil }
        return topic
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

    func join(_ listing: ChannelListing, selectConversation: Bool = true) {
        guard let profile = selectedProfile else { return }
        join(
            listing,
            on: profile,
            selectConversation: selectConversation,
            destination: selection ?? .server(profile.id)
        )
    }

    func joinChannel(named channelName: String, from item: SidebarItem) {
        guard let profile = profile(for: item) else { return }
        let channel = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChannelName(channel) else { return }
        join(
            ChannelListing(name: channel, userCount: 0, topic: ""),
            on: profile,
            selectConversation: true,
            destination: item
        )
    }

    private func runPostRegistrationSequence(for profile: ServerProfile) {
        guard let sessionID = sessionIDs[profile.id] else { return }
        let commands = (sessionOnConnectCommands[profile.id] ?? [])
            .compactMap(IRCCommandTranslator.onConnectWireCommand(from:))

        if !commands.isEmpty {
            appendSystem(
                "Running \(commands.count) on-connect command\(commands.count == 1 ? "" : "s") before joining channels…",
                for: .server(profile.id)
            )
        }

        for (index, command) in commands.enumerated() {
            let delay = Double(index) * onConnectCommandInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.sessionIDs[profile.id] == sessionID,
                      self.registeredServerIDs.contains(profile.id),
                      let connection = self.connections[profile.id] else { return }
                connection.send(command: command) { [weak self] sent in
                    guard !sent,
                          let self,
                          self.sessionIDs[profile.id] == sessionID else { return }
                    self.appendSystem("An on-connect command could not be sent.", for: .server(profile.id))
                }
            }
        }

        let firstJoinDelay: TimeInterval
        if commands.isEmpty {
            firstJoinDelay = 0.25
        } else {
            let lastCommandDelay = Double(commands.count - 1) * onConnectCommandInterval
            firstJoinDelay = lastCommandDelay + favoriteJoinDelayAfterCommands
        }
        joinChannelsAfterRegistration(for: profile, firstJoinDelay: firstJoinDelay)
    }

    private func joinChannelsAfterRegistration(for profile: ServerProfile, firstJoinDelay: TimeInterval) {
        guard let sessionID = sessionIDs[profile.id] else { return }
        var seenChannelNames = Set<String>()
        let retainedChannelNames = channels(for: profile).map(\.name)
        let channelNames = (retainedChannelNames + (profile.favoriteChannels ?? [])).filter { channelName in
            let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seenChannelNames.insert(normalizedIdentifier(trimmed, serverID: profile.id)).inserted
        }

        for (index, channelName) in channelNames.enumerated() {
            let delay = firstJoinDelay + (Double(index) * favoriteJoinInterval)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.sessionIDs[profile.id] == sessionID,
                      self.registeredServerIDs.contains(profile.id),
                      self.connections[profile.id] != nil,
                      let activeProfile = self.profiles.first(where: { $0.id == profile.id }) else { return }
                if let retainedChannel = self.existingChannel(named: channelName, serverID: profile.id) {
                    self.rejoin(retainedChannel, on: activeProfile)
                } else {
                    self.join(ChannelListing(name: channelName, userCount: 0, topic: ""), on: activeProfile, selectConversation: false, destination: .server(profile.id))
                }
            }
        }
    }

    private func rejoin(_ channel: Conversation, on profile: ServerProfile) {
        let key = joinKey(serverID: profile.id, channel: channel.name)
        guard pendingJoins[key] == nil else { return }
        channelTopics.removeValue(forKey: channel.id)
        channelMembers[channel.id] = [ChannelMember(nickname: nickname(for: profile), prefix: nil)]
        let statusMessage = IRCMessage(sender: "System", text: "Rejoining \(channel.name)…", isSystem: true)
        conversations[channel.id, default: []].append(statusMessage)
        pendingJoins[key] = PendingJoin(
            serverID: profile.id,
            channel: channel.name,
            channelID: channel.id,
            destination: .channel(channel.id),
            statusMessageID: statusMessage.id,
            topic: "",
            preservesConversationOnFailure: true
        )
        connections[profile.id]?.send(command: "JOIN \(channel.name)")
        messagesDidChange(for: channel.id)
        membersDidChange(for: channel.id)
    }

    private func join(_ listing: ChannelListing, on profile: ServerProfile, selectConversation: Bool, destination: SidebarItem) {
        guard registeredServerIDs.contains(profile.id), connections[profile.id] != nil else {
            appendSystem("Wait for the server to finish connecting before joining a channel.", for: destination)
            return
        }
        if let channel = channels.first(where: { $0.serverID == profile.id && identifiersEqual($0.name, listing.name, serverID: profile.id) }) {
            if selectConversation { selection = .channel(channel.id) }
            return
        }
        let channel = Conversation(name: listing.name, serverID: profile.id)
        channels.append(channel)
        let listedTopic = listing.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !listedTopic.isEmpty {
            channelTopics[channel.id] = listedTopic
        }
        channelMembers[channel.id] = [ChannelMember(nickname: nickname(for: profile), prefix: nil)]
        let joiningMessage = IRCMessage(sender: "System", text: "Joining \(listing.name)…", isSystem: true)
        conversations[channel.id] = [joiningMessage]
        pendingJoins[joinKey(serverID: profile.id, channel: listing.name)] = PendingJoin(
            serverID: profile.id,
            channel: listing.name,
            channelID: channel.id,
            destination: destination,
            statusMessageID: joiningMessage.id,
            topic: listing.topic
        )
        connections[profile.id]?.send(command: "JOIN \(listing.name)")
        if selectConversation { selection = .channel(channel.id) }
        messagesDidChange(for: channel.id)
    }

    func beginNewConversation() {
        guard let profile = selectedProfile else { return }
        let conversation = Conversation(name: "new-message", serverID: profile.id)
        directMessages.append(conversation)
        conversations[conversation.id] = [IRCMessage(sender: "System", text: "Start a private conversation with /msg nickname your message.", isSystem: true)]
        selection = .directMessage(conversation.id)
        messagesDidChange(for: conversation.id)
    }

    func startDirectMessage(with nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item) else { return }
        let conversation = directMessage(named: nickname, serverID: profile.id)
        if conversations[conversation.id] == nil {
            conversations[conversation.id] = [IRCMessage(sender: "System", text: "Private conversation with \(nickname).", isSystem: true)]
            messagesDidChange(for: conversation.id)
        }
        selection = .directMessage(conversation.id)
    }

    func requestWhois(for nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item), !nickname.isEmpty else { return }
        guard canSendMessages(on: profile, reportingTo: item) else { return }
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
        guard canSendMessages(on: profile, reportingTo: item) else { return }
        let target = title(for: item)
        let sender = nickname(for: profile)
        let sessionID = sessionIDs[profile.id]
        for chunk in outgoingTextChunks(text, commandPrefix: "PRIVMSG \(target) :") {
            connections[profile.id]?.send(command: "PRIVMSG \(target) :\(chunk)") { [weak self] sent in
                guard let self, sent,
                      self.sessionIDs[profile.id] == sessionID,
                      self.registeredServerIDs.contains(profile.id) else { return }
                self.rememberOutgoingEcho(serverID: profile.id, target: target, text: chunk)
                self.append(IRCMessage(sender: sender, text: chunk), for: item, markUnread: false)
            }
        }
    }

    private func executeCommand(_ input: String, in item: SidebarItem) {
        let parts = input.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.uppercased(), let profile = profile(for: item) else { return }
        let argument = parts.count > 1 ? parts[1] : ""
        let localCommands: Set<String> = ["SHOWMUTES", "MUTE", "UNMUTE", "QUIT"]
        if !localCommands.contains(command), !canSendMessages(on: profile, reportingTo: item) {
            return
        }
        let sessionID = sessionIDs[profile.id]
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
            join(
                ChannelListing(name: channel, userCount: 0, topic: ""),
                on: profile,
                selectConversation: true,
                destination: item
            )
        case "LIST":
            requestChannelListing(for: profile, arguments: argument)
        case "MSG", "QUERY":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /msg nickname message", for: item); return }
            let conversation = directMessage(named: fields[0], serverID: profile.id)
            if conversations[conversation.id] == nil {
                conversations[conversation.id] = [IRCMessage(sender: "System", text: "Private conversation with \(fields[0]).", isSystem: true)]
            }
            let sender = nickname(for: profile)
            for chunk in outgoingTextChunks(fields[1], commandPrefix: "PRIVMSG \(fields[0]) :") {
                connections[profile.id]?.send(command: "PRIVMSG \(fields[0]) :\(chunk)") { [weak self] sent in
                    guard let self, sent,
                          self.sessionIDs[profile.id] == sessionID,
                          self.registeredServerIDs.contains(profile.id) else { return }
                    self.rememberOutgoingEcho(serverID: profile.id, target: fields[0], text: chunk)
                    self.append(IRCMessage(sender: sender, text: chunk), for: .directMessage(conversation.id), markUnread: false)
                }
            }
            if command == "QUERY" { selection = .directMessage(conversation.id) }
        case "NOTICE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /notice target message", for: item); return }
            for chunk in outgoingTextChunks(fields[1], commandPrefix: "NOTICE \(fields[0]) :") {
                connections[profile.id]?.send(command: "NOTICE \(fields[0]) :\(chunk)") { [weak self] sent in
                    guard let self, sent,
                          self.sessionIDs[profile.id] == sessionID,
                          self.registeredServerIDs.contains(profile.id) else { return }
                    self.appendSystem("Notice sent to \(fields[0]): \(chunk)", for: item)
                }
            }
        case "ME":
            guard !argument.isEmpty else { return }
            guard isMessageDestination(item) else {
                appendSystem("Select a channel or private message before sending an action.", for: item)
                return
            }
            let target = title(for: item)
            let sender = nickname(for: profile)
            for chunk in outgoingTextChunks(argument, commandPrefix: "PRIVMSG \(target) :\u{01}ACTION ", suffix: "\u{01}") {
                let action = "\u{01}ACTION \(chunk)\u{01}"
                connections[profile.id]?.send(command: "PRIVMSG \(target) :\(action)") { [weak self] sent in
                    guard let self, sent,
                          self.sessionIDs[profile.id] == sessionID,
                          self.registeredServerIDs.contains(profile.id) else { return }
                    self.rememberOutgoingEcho(serverID: profile.id, target: target, text: action)
                    self.append(
                        IRCMessage(sender: "* \(sender)", text: chunk, nicknameColorKey: sender),
                        for: item,
                        markUnread: false
                    )
                }
            }
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
            let sender = nickname(for: profile)
            for chunk in outgoingTextChunks(slap, commandPrefix: "PRIVMSG \(target) :\u{01}ACTION ", suffix: "\u{01}") {
                let action = "\u{01}ACTION \(chunk)\u{01}"
                connections[profile.id]?.send(command: "PRIVMSG \(target) :\(action)") { [weak self] sent in
                    guard let self, sent,
                          self.sessionIDs[profile.id] == sessionID,
                          self.registeredServerIDs.contains(profile.id) else { return }
                    self.rememberOutgoingEcho(serverID: profile.id, target: target, text: action)
                    self.append(
                        IRCMessage(sender: "* \(sender)", text: chunk, nicknameColorKey: sender),
                        for: item,
                        markUnread: false
                    )
                }
            }
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
            if isChannelName(fields[0]) {
                guard let namedChannel = existingChannel(named: fields[0], serverID: profile.id) else {
                    appendSystem("You are not joined to \(fields[0]).", for: item)
                    return
                }
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
        if isChannelName(fields[0]) {
            guard let namedChannel = existingChannel(named: fields[0], serverID: profile.id) else {
                appendSystem("You are not joined to \(fields[0]).", for: item)
                return
            }
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
                if case .offline = status {
                    registeredServerIDs.remove(profile.id)
                    prepareChannelsForDisconnectedSession(for: profile.id)
                    resetChannelListingRequest(for: profile.id)
                }
                if case .failed = status {
                    registeredServerIDs.remove(profile.id)
                    prepareChannelsForDisconnectedSession(for: profile.id)
                    resetChannelListingRequest(for: profile.id)
                }
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
        case .terminalFailure(let message):
            registeredServerIDs.remove(profile.id)
            prepareChannelsForDisconnectedSession(for: profile.id)
            resetChannelListingRequest(for: profile.id)
            connectionStatuses[profile.id] = .failed(message)
            appendSystem(message, for: .server(profile.id))
        case .sshHostKeyLearned(let hostKey):
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            profiles[index].sshTrustedHostKey = hostKey
            saveProfiles()
            appendSystem("Saved the SSH host identity for future connections.", for: .server(profile.id))
        case .received(let wire): handle(wire, profile: profile)
        }
    }

    private func handle(_ wire: IRCWireMessage, profile: ServerProfile) {
        let sender = wire.prefix?.split(separator: "!").first.map(String.init) ?? profile.name
        switch wire.command {
        case "001":
            if let registeredNickname = wire.parameters.first, !registeredNickname.isEmpty {
                activeNicknames[profile.id] = registeredNickname
            }
            registeredServerIDs.insert(profile.id)
            registrationNicknameSuffixes.removeValue(forKey: profile.id)
            connectionStatuses[profile.id] = .online
            cancelScheduledReconnect(for: profile.id, resetAttempts: true)
            appendSystem(wire.trailing ?? "Connected.", for: .server(profile.id))
            runPostRegistrationSequence(for: profile)
        case "005":
            updateCaseMapping(from: wire, serverID: profile.id)
        case "NOTICE":
            guard let target = wire.parameters.first, let text = wire.trailing else { return }
            guard !isMuted(sender, on: profile) else { return }
            guard !handleCTCP(text, from: sender, target: target, profile: profile, canReplyToRequest: false) else { return }

            // IRC notices are delivered as a distinct message type, but they
            // still belong beside the conversation they address. Server notices
            // and recognized network service broadcasts remain in the server log.
            if isChannelName(target) {
                guard !identifiersEqual(sender, nickname(for: profile), serverID: profile.id) else { return }
                let channel = channel(named: target, serverID: profile.id)
                append(
                    IRCMessage(sender: "\(sender) (notice)", text: text, isNotice: true, nicknameColorKey: sender),
                    for: .channel(channel.id),
                    markMention: messageMentionsLocalNickname(text, on: profile)
                )
            } else if let channel = channelReferencedByNotice(text, serverID: profile.id) {
                guard !identifiersEqual(sender, nickname(for: profile), serverID: profile.id) else { return }
                append(
                    IRCMessage(sender: "\(sender) (notice)", text: text, isNotice: true, nicknameColorKey: sender),
                    for: .channel(channel.id),
                    markMention: messageMentionsLocalNickname(text, on: profile)
                )
            } else {
                switch IRCNoticeRoutingPolicy.fallbackDestination(
                    sender: sender,
                    prefix: wire.prefix,
                    caseMapping: caseMappings[profile.id] ?? .rfc1459
                ) {
                case .server:
                    if wire.prefix?.contains("!") == true {
                        append(
                            IRCMessage(
                                sender: "\(sender) (notice)",
                                text: text,
                                isSystem: true,
                                isNotice: true,
                                nicknameColorKey: sender
                            ),
                            for: .server(profile.id)
                        )
                    } else {
                        appendSystem(text, for: .server(profile.id))
                    }
                case .directMessage:
                    guard !identifiersEqual(sender, nickname(for: profile), serverID: profile.id) else { return }
                    let conversation = directMessage(named: sender, serverID: profile.id)
                    append(
                        IRCMessage(sender: "\(sender) (notice)", text: text, isNotice: true, nicknameColorKey: sender),
                        for: .directMessage(conversation.id)
                    )
                }
            }
        case "PRIVMSG":
            guard let target = wire.parameters.first, let text = wire.trailing else { return }
            guard !isMuted(sender, on: profile) else { return }
            if handleCTCP(text, from: sender, target: target, profile: profile, canReplyToRequest: true) { return }
            // Servers with IRCv3 echo-message send our own PRIVMSG back to us.
            // The optimistic local row is already visible, so consume that echo.
            if identifiersEqual(sender, nickname(for: profile), serverID: profile.id),
               consumeOutgoingEcho(serverID: profile.id, target: target, text: text) {
                return
            }
            if isChannelName(target) {
                let channel = channel(named: target, serverID: profile.id)
                let isOwnMessage = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
                append(
                    IRCMessage(sender: sender, text: text),
                    for: .channel(channel.id),
                    markUnread: !isOwnMessage,
                    markMention: !isOwnMessage && messageMentionsLocalNickname(text, on: profile)
                )
            } else if !identifiersEqual(sender, nickname(for: profile), serverID: profile.id) {
                let conversation = directMessage(named: sender, serverID: profile.id)
                append(IRCMessage(sender: sender, text: text), for: .directMessage(conversation.id))
            }
        case "JOIN":
            let channelName = wire.trailing ?? wire.parameters.last ?? ""
            if isChannelName(channelName) {
                let channel = channel(named: channelName, serverID: profile.id)
                addMember(ChannelMember(nickname: sender, prefix: nil), to: channel.id)
                if identifiersEqual(sender, nickname(for: profile), serverID: profile.id) {
                    let pendingJoin = pendingJoins.removeValue(forKey: joinKey(serverID: profile.id, channel: channelName))
                    if let pendingJoin {
                        conversations[channel.id]?.removeAll { $0.id == pendingJoin.statusMessageID }
                    }
                    let topic = pendingJoin?.topic.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let topicSuffix = topic.isEmpty ? "" : " Topic: \(topic)"
                    appendChannelEvent("Joined \(channelName).\(topicSuffix)", kind: .join, channelID: channel.id)
                } else {
                    appendChannelEvent("\(sender) joined \(channelName).", kind: .join, channelID: channel.id)
                }
            }
        case "PART":
            guard let channelName = wire.parameters.first,
                  let channel = existingChannel(named: channelName, serverID: profile.id) else { return }
            let memberCountBeforePart = channelMembers[channel.id]?.count ?? 0
            guard removeMember(named: sender, from: channel.id) else { return }
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            let subject = identifiersEqual(sender, nickname(for: profile), serverID: profile.id) ? "You" : sender
            appendChannelEvent(
                "\(subject) left \(channelName)\(reason).",
                kind: .part,
                channelID: channel.id,
                memberCount: memberCountBeforePart
            )
        case "QUIT":
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            let pendingKillKey = killKey(serverID: profile.id, nickname: sender)
            if let pendingKill = pendingKills.removeValue(forKey: pendingKillKey) {
                appendSystem("Disconnected \(pendingKill.nickname) from the network\(reason).", for: pendingKill.destination)
            }
            for channel in channels(for: profile) {
                let memberCountBeforeQuit = channelMembers[channel.id]?.count ?? 0
                guard removeMember(named: sender, from: channel.id) else { continue }
                appendChannelEvent(
                    "\(sender) disconnected\(reason).",
                    kind: .quit,
                    channelID: channel.id,
                    memberCount: memberCountBeforeQuit
                )
            }
        case "KICK":
            guard wire.parameters.count >= 2,
                  let channel = existingChannel(named: wire.parameters[0], serverID: profile.id) else { return }
            let target = wire.parameters[1]
            let pendingKick = pendingKicks.removeValue(forKey: kickKey(serverID: profile.id, channel: channel.name, nickname: target))
            _ = removeMember(named: target, from: channel.id)
            let reason = wire.trailing.map { " — \($0)" } ?? ""
            if identifiersEqual(target, nickname(for: profile), serverID: profile.id) {
                appendSystem("You were removed from \(channel.name) by \(sender)\(reason).", for: .server(profile.id))
                removeChannelConversation(channel)
                return
            }
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
            let isLocalNicknameChange = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
            let requestedDestination = isLocalNicknameChange ? pendingNickDestinations.removeValue(forKey: profile.id) : nil
            if isLocalNicknameChange {
                activeNicknames[profile.id] = newNickname
            } else {
                renameDirectMessage(from: sender, to: newNickname, serverID: profile.id)
            }
            var deliveredConfirmation = false
            for channel in channels(for: profile) where renameMember(sender, to: newNickname, in: channel.id) {
                if isLocalNicknameChange {
                    appendChannelEvent("You are now known as \(newNickname).", kind: .nickname, channelID: channel.id)
                    if requestedDestination == .channel(channel.id) { deliveredConfirmation = true }
                } else {
                    appendChannelEvent("\(sender) is now known as \(newNickname).", kind: .nickname, channelID: channel.id)
                }
            }
            if isLocalNicknameChange, !deliveredConfirmation {
                appendSystem("You are now known as \(newNickname).", for: requestedDestination ?? .server(profile.id))
            }
        case "TOPIC":
            guard let channelName = wire.parameters.first,
                  let channel = existingChannel(named: channelName, serverID: profile.id),
                  let topic = wire.trailing else { return }
            let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTopic.isEmpty {
                channelTopics.removeValue(forKey: channel.id)
            } else {
                channelTopics[channel.id] = trimmedTopic
            }
            let key = topicKey(serverID: profile.id, channel: channelName)
            let destination = pendingTopicDestinations.removeValue(forKey: key)
            appendChannelEvent("\(sender) changed the topic to: \(topic)", kind: .topic, channelID: channel.id)
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
                appendChannelEvent("\(sender) set mode \(changes) on \(target).", kind: .mode, channelID: channel.id)
                if let destination, destination != .channel(channel.id) {
                    appendSystem("Modes for \(target) changed: \(changes)", for: destination)
                }
            } else {
                appendSystem("Modes for \(target) changed: \(changes)", for: destination ?? .server(profile.id))
            }
        case "353":
            guard wire.parameters.count >= 3 else { return }
            let channel = channel(named: wire.parameters[2], serverID: profile.id)
            stageMembers((wire.trailing ?? "").split(separator: " ").map(String.init).map(IRCMemberParser.member(from:)), for: channel.id)
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
            registeredServerIDs.remove(profile.id)
            prepareChannelsForDisconnectedSession(for: profile.id)
            resetChannelListingRequest(for: profile.id)
            scheduleReconnect(for: profile)
        case "322":
            guard wire.parameters.count >= 3, let users = Int(wire.parameters[2]) else { return }
            let listing = ChannelListing(name: wire.parameters[1], userCount: users, topic: wire.trailing ?? "")
            queueChannelListing(listing, for: profile.id)
        case "323":
            guard channelListsInProgress.contains(profile.id) else { return }
            flushChannelListings(for: profile.id)
            channelListsInProgress.remove(profile.id)
            channelListRequestIDs.removeValue(forKey: profile.id)
            channelListCompletionDates[profile.id] = Date()
        case "263", "416":
            _ = handleChannelListError(wire, serverID: profile.id)
        case "301", "311", "312", "313", "317", "318", "319", "330", "338", "378", "379", "671":
            handleWhoisReply(wire, serverID: profile.id)
        case "401":
            if !handleWhoisReply(wire, serverID: profile.id) {
                if !handleInviteError(wire, serverID: profile.id) {
                    handleModerationError(wire, serverID: profile.id)
                }
            }
        case "403", "473":
            if !handleJoinError(wire, serverID: profile.id),
               !handleInviteError(wire, serverID: profile.id) {
                handleModerationError(wire, serverID: profile.id)
            }
        case "405", "471", "474", "475", "476", "477", "489":
            handleJoinError(wire, serverID: profile.id)
        case "442", "443", "482":
            if !handleInviteError(wire, serverID: profile.id) { handleModerationError(wire, serverID: profile.id) }
        case "441", "481":
            handleModerationError(wire, serverID: profile.id)
        case "437":
            if !handleJoinError(wire, serverID: profile.id) {
                if retryRegistrationWithFallbackNickname(after: wire, profile: profile) { return }
                let destination = pendingNickDestinations.removeValue(forKey: profile.id) ?? .server(profile.id)
                appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
            }
        case "433", "436":
            if retryRegistrationWithFallbackNickname(after: wire, profile: profile) { return }
            let destination = pendingNickDestinations.removeValue(forKey: profile.id) ?? .server(profile.id)
            appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
        case "431", "432":
            let destination = pendingNickDestinations.removeValue(forKey: profile.id) ?? .server(profile.id)
            appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
        case "421", "461":
            if handleChannelListError(wire, serverID: profile.id) { return }
            guard let destination = pendingVersionDestinations.removeValue(forKey: profile.id) else { return }
            pendingVersionRequestIDs.removeValue(forKey: profile.id)
            appendSystem("Server version request failed: \(wire.trailing ?? "The server rejected the request.")", for: destination)
        default: break
        }
    }

    @discardableResult
    private func handleJoinError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        let responseParameters = wire.parameters.dropFirst()
        guard let (key, pendingJoin) = pendingJoins.first(where: { _, pendingJoin in
            pendingJoin.serverID == serverID && responseParameters.contains {
                identifiersEqual($0, pendingJoin.channel, serverID: serverID)
            }
        }) else { return false }

        pendingJoins.removeValue(forKey: key)
        if let channel = channels.first(where: { $0.id == pendingJoin.channelID }) {
            if pendingJoin.preservesConversationOnFailure {
                conversations[channel.id]?.removeAll { $0.id == pendingJoin.statusMessageID }
                appendChannelEvent("Could not rejoin \(pendingJoin.channel): \(wire.trailing ?? "The server rejected the join request.")", channelID: channel.id)
                return true
            } else {
                removeChannelConversation(channel)
            }
        }
        let destination: SidebarItem = pendingJoin.destination == .channel(pendingJoin.channelID)
            ? .server(serverID)
            : pendingJoin.destination
        appendSystem("Could not join \(pendingJoin.channel): \(wire.trailing ?? "The server rejected the join request.")", for: destination)
        return true
    }

    private func retryRegistrationWithFallbackNickname(after wire: IRCWireMessage, profile: ServerProfile) -> Bool {
        guard !registeredServerIDs.contains(profile.id),
              pendingNickDestinations[profile.id] == nil,
              connections[profile.id] != nil else { return false }

        let attemptedSuffixes = registrationNicknameSuffixes[profile.id, default: []]
        let availableSuffixes = Array(0...99).filter { !attemptedSuffixes.contains($0) }
        guard let suffix = availableSuffixes.randomElement() else { return false }

        registrationNicknameSuffixes[profile.id, default: []].insert(suffix)
        let fallbackNickname = configuredNickname(for: profile) + String(format: "%02d", suffix)
        activeNicknames[profile.id] = fallbackNickname
        appendSystem("\(wire.trailing ?? "Nickname is unavailable.") Retrying as \(fallbackNickname)…", for: .server(profile.id))
        connections[profile.id]?.send(command: "NICK \(fallbackNickname)")
        return true
    }

    @discardableResult
    private func handleWhoisReply(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        guard wire.parameters.count >= 2 else { return false }
        let target = wire.parameters[1]
        let key = whoisKey(serverID: serverID, target: target)
        guard let destination = pendingWhoisDestinations[key] else { return false }
        let message: String
        var channelLinks: [String] = []
        switch wire.command {
        case "301": message = "\(target) is away: \(wire.trailing ?? "away")"
        case "311":
            let user = wire.parameters.count > 2 ? wire.parameters[2] : "?"
            let host = wire.parameters.count > 3 ? wire.parameters[3] : "?"
            message = "\(target) is \(user)@\(host)\(wire.trailing.map { " — \($0)" } ?? "")"
        case "312": message = "\(target) is on \(wire.parameters.count > 2 ? wire.parameters[2] : "the server")\(wire.trailing.map { " — \($0)" } ?? "")"
        case "313": message = "\(target) is an IRC operator."
        case "317": message = "\(target) has been idle \(formatIdle(wire.parameters.count > 2 ? Int(wire.parameters[2]) ?? 0 : 0))."
        case "319":
            let channels = wire.trailing ?? "no visible channels"
            channelLinks = IRCWhoisChannelParser.channels(from: channels)
            message = "\(target) is on: \(channels)"
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
        append(
            IRCMessage(sender: "System", text: message, isSystem: true, channelLinks: channelLinks),
            for: destination
        )
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
            if let nickname, identifiersEqual(invitation.nickname, nickname, serverID: serverID) { return true }
            if let channel, identifiersEqual(invitation.channel, channel, serverID: serverID) { return true }
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
            if let nickname, !identifiersEqual(kick.nickname, nickname, serverID: serverID) { return false }
            if let channel, !identifiersEqual(kick.channel, channel, serverID: serverID) { return false }
            return nickname != nil || channel != nil
        }) {
            pendingKicks.removeValue(forKey: key)
            appendSystem("Kick failed: \(wire.trailing ?? "The server rejected the kick.")", for: kick.destination)
            return true
        }

        if let nickname,
           let (key, kill) = pendingKills.first(where: { _, kill in
               kill.serverID == serverID && identifiersEqual(kill.nickname, nickname, serverID: serverID)
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
        if wire.command == "352" {
            let responseTargets = [wire.parameters[1]] + (wire.parameters.count > 5 ? [wire.parameters[5]] : [])
            guard let key = responseTargets
                .map({ whoKey(serverID: serverID, target: $0) })
                .first(where: { pendingWhoDestinations[$0] != nil }),
                  let destination = pendingWhoDestinations[key] else { return }
            let user = wire.parameters.count > 2 ? wire.parameters[2] : "?"
            let host = wire.parameters.count > 3 ? wire.parameters[3] : "?"
            let nickname = wire.parameters.count > 5 ? wire.parameters[5] : "?"
            appendSystem("\(nickname) — \(user)@\(host)\(wire.trailing.map { " — \($0)" } ?? "")", for: destination)
        } else {
            let target = wire.parameters[1]
            let key = whoKey(serverID: serverID, target: target)
            guard let destination = pendingWhoDestinations[key] else { return }
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
        switch wire.command {
        case "331":
            if let channel = existingChannel(named: channelName, serverID: serverID) {
                channelTopics.removeValue(forKey: channel.id)
            }
            if let destination = pendingTopicDestinations.removeValue(forKey: key) {
                appendSystem("\(channelName) has no topic.", for: destination)
            }
        case "332":
            let topic = (wire.trailing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let channel = existingChannel(named: channelName, serverID: serverID) {
                if topic.isEmpty {
                    channelTopics.removeValue(forKey: channel.id)
                } else {
                    channelTopics[channel.id] = topic
                }
            }
            if let destination = pendingTopicDestinations.removeValue(forKey: key) {
                appendSystem("Topic for \(channelName): \(topic)", for: destination)
            }
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
            if identifiersEqual(sender, nickname(for: profile), serverID: profile.id),
               consumeOutgoingEcho(serverID: profile.id, target: target, text: text) {
                return true
            }
            let message = IRCMessage(sender: "* \(sender)", text: command[1], nicknameColorKey: sender)
            if let first = target.first, "#&+!".contains(first) {
                let channel = channel(named: target, serverID: profile.id)
                let isOwnAction = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
                append(
                    message,
                    for: .channel(channel.id),
                    markUnread: !isOwnAction,
                    markMention: !isOwnAction && messageMentionsLocalNickname(command[1], on: profile)
                )
            } else if !identifiersEqual(sender, nickname(for: profile), serverID: profile.id) {
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
        "\(serverID.uuidString)|\(normalizedIdentifier(nickname, serverID: serverID))"
    }

    private func recordSelectionChange(from previousSelection: SidebarItem?) {
        guard !isNavigatingSelectionHistory, previousSelection != selection else { return }
        forwardSelectionHistory.removeAll()
        guard let previousSelection, isValidNavigationSelection(previousSelection) else { return }
        appendToBackHistory(previousSelection)
    }

    private func selectFromHistory(_ destination: SidebarItem) {
        isNavigatingSelectionHistory = true
        selection = destination
        isNavigatingSelectionHistory = false
    }

    private func appendToBackHistory(_ item: SidebarItem) {
        backSelectionHistory.append(item)
        if backSelectionHistory.count > maximumSelectionHistoryCount {
            backSelectionHistory.removeFirst(backSelectionHistory.count - maximumSelectionHistoryCount)
        }
    }

    private func appendToForwardHistory(_ item: SidebarItem) {
        forwardSelectionHistory.append(item)
        if forwardSelectionHistory.count > maximumSelectionHistoryCount {
            forwardSelectionHistory.removeFirst(forwardSelectionHistory.count - maximumSelectionHistoryCount)
        }
    }

    private func isValidNavigationSelection(_ item: SidebarItem) -> Bool {
        switch item {
        case .connectionCenter:
            return true
        case .server(let id):
            return profiles.contains { $0.id == id }
        case .channel(let id):
            return channels.contains { $0.id == id }
        case .directMessage(let id):
            return directMessages.contains { $0.id == id }
        }
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
        if let existing = channels.first(where: { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }) { return existing }
        let conversation = Conversation(name: name, serverID: serverID)
        channels.append(conversation)
        let profileNickname = profiles.first(where: { $0.id == serverID }).map { nickname(for: $0) } ?? nickname
        channelMembers[conversation.id] = [ChannelMember(nickname: profileNickname, prefix: nil)]
        return conversation
    }

    private func existingChannel(named name: String, serverID: UUID) -> Conversation? {
        channels.first { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }
    }

    private func removeChannelConversation(_ channel: Conversation) {
        channels.removeAll { $0.id == channel.id }
        conversations.removeValue(forKey: channel.id)
        conversationDrafts.removeValue(forKey: .channel(channel.id))
        channelTopics.removeValue(forKey: channel.id)
        channelMembers.removeValue(forKey: channel.id)
        pendingChannelMembers.removeValue(forKey: channel.id)
        pendingJoins.removeValue(forKey: joinKey(serverID: channel.serverID, channel: channel.name))
        if selection == .channel(channel.id) { selection = .server(channel.serverID) }
        messagesDidChange(for: channel.id)
        membersDidChange(for: channel.id)
        messageUpdateSignals.removeValue(forKey: channel.id)
        memberUpdateSignals.removeValue(forKey: channel.id)
    }

    private func prepareChannelsForDisconnectedSession(for serverID: UUID) {
        resetPendingRequests(for: serverID)
        let retainedChannels = channels.filter { $0.serverID == serverID }
        guard !retainedChannels.isEmpty || pendingJoins.values.contains(where: { $0.serverID == serverID }) else { return }
        for channel in retainedChannels {
            channelMembers[channel.id] = []
            pendingChannelMembers.removeValue(forKey: channel.id)
        }
        pendingJoins = pendingJoins.filter { $0.value.serverID != serverID }
        membersDidChange(for: retainedChannels.map(\.id))
    }

    private func removeConversations(for serverID: UUID) {
        let wasShowingRemovedServer = selection.flatMap { profile(for: $0)?.id } == serverID
        let removedChannels = channels.filter { $0.serverID == serverID }
        let removedDirectMessages = directMessages.filter { $0.serverID == serverID }
        let removedChannelIDs = Set(removedChannels.map(\.id))
        let removedConversationIDs = removedChannelIDs.union(removedDirectMessages.map(\.id))
        channels.removeAll { $0.serverID == serverID }
        directMessages.removeAll { $0.serverID == serverID }
        for conversationID in removedConversationIDs {
            conversations.removeValue(forKey: conversationID)
            channelTopics.removeValue(forKey: conversationID)
            channelMembers.removeValue(forKey: conversationID)
            pendingChannelMembers.removeValue(forKey: conversationID)
        }
        conversationDrafts = conversationDrafts.filter { item, _ in
            guard let conversationID = conversationID(for: item) else { return true }
            return !removedConversationIDs.contains(conversationID) && conversationID != serverID
        }
        pendingJoins = pendingJoins.filter { $0.value.serverID != serverID }
        if wasShowingRemovedServer {
            selection = .connectionCenter
        }
        messagesDidChange(for: removedConversationIDs)
        membersDidChange(for: removedChannelIDs)
        for id in removedConversationIDs {
            messageUpdateSignals.removeValue(forKey: id)
        }
        for id in removedChannelIDs {
            memberUpdateSignals.removeValue(forKey: id)
        }
    }

    private func resetPendingRequests(for serverID: UUID) {
        let keyPrefix = serverID.uuidString + "|"
        pendingNickDestinations.removeValue(forKey: serverID)
        pendingWhoisDestinations = pendingWhoisDestinations.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingTopicDestinations = pendingTopicDestinations.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingInvites = pendingInvites.filter { $0.value.serverID != serverID }
        pendingModeDestinations = pendingModeDestinations.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingKicks = pendingKicks.filter { $0.value.serverID != serverID }
        pendingKills = pendingKills.filter { $0.value.serverID != serverID }
        pendingWhoDestinations = pendingWhoDestinations.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingMOTDDestinations.removeValue(forKey: serverID)
        pendingVersionDestinations.removeValue(forKey: serverID)
        pendingVersionRequestIDs.removeValue(forKey: serverID)
        pendingClientVersionDestinations = pendingClientVersionDestinations.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingClientVersionRequestIDs = pendingClientVersionRequestIDs.filter { !$0.key.hasPrefix(keyPrefix) }
        pendingOutgoingEchoes.removeValue(forKey: serverID)
    }

    private func resetChannelListingRequest(for serverID: UUID) {
        channelListsInProgress.remove(serverID)
        channelListRequestIDs.removeValue(forKey: serverID)
        pendingChannelListingsByServer.removeValue(forKey: serverID)
        listedChannelsByServer.removeValue(forKey: serverID)
        knownChannelNamesByServer.removeValue(forKey: serverID)
        scheduledChannelListFlushes.remove(serverID)
        channelListCompletionDates.removeValue(forKey: serverID)
    }

    @discardableResult
    private func handleChannelListError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        guard channelListsInProgress.contains(serverID),
              wire.parameters.dropFirst().contains(where: { $0.caseInsensitiveCompare("LIST") == .orderedSame }) else {
            return false
        }
        flushChannelListings(for: serverID)
        channelListsInProgress.remove(serverID)
        channelListRequestIDs.removeValue(forKey: serverID)
        appendSystem("Channel list request failed: \(wire.trailing ?? "The server rejected the LIST request.")", for: .server(serverID))
        return true
    }

    private func isChannelName(_ value: String) -> Bool {
        value.first.map { "#&+!".contains($0) } == true
    }

    /// Some networks deliver channel welcome notices to the user's nickname
    /// instead of the channel target, prefixing the text with "[#channel]".
    /// Route those notices to an existing joined channel without treating every
    /// private NOTICE as channel traffic.
    private func channelReferencedByNotice(_ text: String, serverID: UUID) -> Conversation? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.first == "[",
              let closingBracket = trimmedText.firstIndex(of: "]") else { return nil }
        let channelName = String(trimmedText[trimmedText.index(after: trimmedText.startIndex)..<closingBracket])
        guard isChannelName(channelName) else { return nil }
        return existingChannel(named: channelName, serverID: serverID)
    }

    private func directMessage(named name: String, serverID: UUID) -> Conversation {
        if let existing = directMessages.first(where: { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }) { return existing }
        let conversation = Conversation(name: name, serverID: serverID)
        directMessages.append(conversation)
        return conversation
    }

    private func renameDirectMessage(from oldNickname: String, to newNickname: String, serverID: UUID) {
        guard let oldIndex = directMessages.firstIndex(where: {
            $0.serverID == serverID && identifiersEqual($0.name, oldNickname, serverID: serverID)
        }) else { return }

        let oldConversation = directMessages[oldIndex]
        var affectedConversationIDs = [oldConversation.id]
        var retiresOldConversation = false
        if let newIndex = directMessages.firstIndex(where: {
            $0.id != oldConversation.id
                && $0.serverID == serverID
                && identifiersEqual($0.name, newNickname, serverID: serverID)
        }) {
            let newConversation = directMessages[newIndex]
            affectedConversationIDs.append(newConversation.id)
            retiresOldConversation = true
            conversations[newConversation.id] = IRCConversationHistory.merging(
                conversations[newConversation.id] ?? [],
                conversations[oldConversation.id] ?? [],
                limit: IRCConversationHistory.retentionLimit
            )
            conversations.removeValue(forKey: oldConversation.id)
            let oldDraftKey = SidebarItem.directMessage(oldConversation.id)
            let newDraftKey = SidebarItem.directMessage(newConversation.id)
            if conversationDrafts[newDraftKey]?.isEmpty != false,
               let oldDraft = conversationDrafts[oldDraftKey] {
                conversationDrafts[newDraftKey] = oldDraft
            }
            conversationDrafts.removeValue(forKey: oldDraftKey)
            directMessages[newIndex].hasUnread = directMessages[newIndex].hasUnread || oldConversation.hasUnread
            directMessages.removeAll { $0.id == oldConversation.id }
            if selection == .directMessage(oldConversation.id) {
                selection = .directMessage(newConversation.id)
            }
        } else {
            directMessages[oldIndex].name = newNickname
        }
        messagesDidChange(for: affectedConversationIDs)
        if retiresOldConversation {
            messageUpdateSignals.removeValue(forKey: oldConversation.id)
        }
    }

    private func stageMembers(_ newMembers: [ChannelMember], for channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return }
        var pending = pendingChannelMembers[channelID] ?? [:]
        for member in newMembers {
            upsert(member, into: &pending, serverID: serverID)
        }
        pendingChannelMembers[channelID] = pending
    }

    private func finishStagingMembers(for channelID: UUID) {
        guard let pending = pendingChannelMembers.removeValue(forKey: channelID) else { return }
        channelMembers[channelID] = sortedMembers(Array(pending.values))
        membersDidChange(for: channelID)
    }

    private func addMember(_ member: ChannelMember, to channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return }
        var members = channelMembers[channelID] ?? []
        upsert(member, into: &members, serverID: serverID)
        if var pending = pendingChannelMembers[channelID] {
            upsert(member, into: &pending, serverID: serverID)
            pendingChannelMembers[channelID] = pending
        }
        channelMembers[channelID] = sortedMembers(members)
        membersDidChange(for: channelID)
    }

    @discardableResult
    private func removeMember(named nickname: String, from channelID: UUID) -> Bool {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return false }
        if var pending = pendingChannelMembers[channelID] {
            pending.removeValue(forKey: normalizedIdentifier(nickname, serverID: serverID))
            pendingChannelMembers[channelID] = pending
        }
        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { identifiersEqual($0.nickname, nickname, serverID: serverID) }) else { return false }
        members.remove(at: index)
        channelMembers[channelID] = members
        membersDidChange(for: channelID)
        return true
    }

    @discardableResult
    private func renameMember(_ oldNickname: String, to newNickname: String, in channelID: UUID) -> Bool {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return false }
        if var pending = pendingChannelMembers[channelID], let member = pending.removeValue(forKey: normalizedIdentifier(oldNickname, serverID: serverID)) {
            pending[normalizedIdentifier(newNickname, serverID: serverID)] = ChannelMember(nickname: newNickname, modes: member.modes)
            pendingChannelMembers[channelID] = pending
        }
        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { identifiersEqual($0.nickname, oldNickname, serverID: serverID) }) else { return false }
        members[index].nickname = newNickname
        channelMembers[channelID] = sortedMembers(members)
        membersDidChange(for: channelID)
        return true
    }

    /// Applies channel membership modes such as +o, -v, +h, and +q to the
    /// member list. Non-membership modes consume their IRC parameters so a
    /// mixed MODE command (for example +klo key 50 nick) stays aligned.
    private func applyMembershipModes(_ modeString: String, arguments: [String], to channelID: UUID) {
        for change in IRCChannelModeParser.membershipChanges(modeString: modeString, arguments: arguments) {
            updateMembershipMode(change.mode, for: change.nickname, adding: change.adding, in: channelID)
        }
    }

    private func updateMembershipMode(_ mode: Character, for nickname: String, adding: Bool, in channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return }
        var didChange = false

        let normalizedNickname = normalizedIdentifier(nickname, serverID: serverID)
        if var pending = pendingChannelMembers[channelID], let member = pending[normalizedNickname] {
            var updated = member
            if adding {
                didChange = updated.modes.insert(mode).inserted || didChange
            } else {
                didChange = updated.modes.remove(mode) != nil || didChange
            }
            pending[normalizedIdentifier(updated.nickname, serverID: serverID)] = updated
            pendingChannelMembers[channelID] = pending
        }

        guard var members = channelMembers[channelID], let index = members.firstIndex(where: { identifiersEqual($0.nickname, nickname, serverID: serverID) }) else { return }
        if adding {
            didChange = members[index].modes.insert(mode).inserted || didChange
        } else {
            didChange = members[index].modes.remove(mode) != nil || didChange
        }
        guard didChange else { return }
        channelMembers[channelID] = sortedMembers(members)
        membersDidChange(for: channelID)
    }

    private func upsert(_ member: ChannelMember, into members: inout [ChannelMember], serverID: UUID) {
        if let index = members.firstIndex(where: { identifiersEqual($0.nickname, member.nickname, serverID: serverID) }) {
            if member.prefix != nil { members[index] = member }
        } else {
            members.append(member)
        }
    }

    private func upsert(_ member: ChannelMember, into members: inout [String: ChannelMember], serverID: UUID) {
        let key = normalizedIdentifier(member.nickname, serverID: serverID)
        if let existing = members[key] {
            if member.prefix != nil || existing.prefix == nil { members[key] = member }
        } else {
            members[key] = member
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

    @discardableResult
    private func canSendMessages(on profile: ServerProfile, reportingTo item: SidebarItem) -> Bool {
        guard registeredServerIDs.contains(profile.id), connections[profile.id] != nil else {
            appendSystem("Wait for the server to finish connecting before sending messages or commands.", for: item)
            return false
        }
        return true
    }

    private func nickname(for profile: ServerProfile) -> String {
        activeNicknames[profile.id] ?? configuredNickname(for: profile)
    }

    private func updateSignal(
        for id: UUID?,
        in signals: inout [UUID: IRCRevisionSignal]
    ) -> IRCRevisionSignal {
        guard let id else { return inactiveUpdateSignal }
        if let signal = signals[id] { return signal }
        let signal = IRCRevisionSignal()
        signals[id] = signal
        return signal
    }

    private func messagesDidChange(for conversationID: UUID) {
        messagesDidChange(for: [conversationID])
    }

    private func messagesDidChange<S: Sequence>(for conversationIDs: S) where S.Element == UUID {
        for id in Set(conversationIDs) {
            messageUpdateSignals[id]?.advance()
        }
    }

    private func membersDidChange(for channelID: UUID) {
        membersDidChange(for: [channelID])
    }

    private func membersDidChange<S: Sequence>(for channelIDs: S) where S.Element == UUID {
        for id in Set(channelIDs) {
            memberUpdateSignals[id]?.advance()
        }
    }

    private func muteSnapshot(for profile: ServerProfile) -> IRCMuteSnapshot {
        if let snapshot = muteSnapshotsByServer[profile.id] { return snapshot }
        let currentProfile = profiles.first(where: { $0.id == profile.id }) ?? profile
        let snapshot = IRCMuteSnapshot(
            nicknames: currentProfile.mutedNicknames ?? [],
            caseMapping: caseMappings[profile.id] ?? .rfc1459
        )
        muteSnapshotsByServer[profile.id] = snapshot
        return snapshot
    }

    private func normalizedIdentifier(_ value: String, serverID: UUID) -> String {
        (caseMappings[serverID] ?? .rfc1459).normalize(value)
    }

    private func messageMentionsLocalNickname(_ message: String, on profile: ServerProfile) -> Bool {
        IRCMentionPolicy.containsMention(
            of: nickname(for: profile),
            in: message,
            caseMapping: caseMappings[profile.id] ?? .rfc1459
        )
    }

    private func identifiersEqual(_ lhs: String, _ rhs: String, serverID: UUID) -> Bool {
        normalizedIdentifier(lhs, serverID: serverID) == normalizedIdentifier(rhs, serverID: serverID)
    }

    private func updateCaseMapping(from wire: IRCWireMessage, serverID: UUID) {
        guard let token = wire.parameters.dropFirst().first(where: {
            $0.uppercased().hasPrefix("CASEMAPPING=")
        }), let rawValue = token.split(separator: "=", maxSplits: 1).last else { return }

        switch rawValue.lowercased() {
        case "ascii": caseMappings[serverID] = .ascii
        case "strict-rfc1459": caseMappings[serverID] = .strictRFC1459
        case "rfc1459": caseMappings[serverID] = .rfc1459
        default: break
        }
        muteSnapshotsByServer.removeValue(forKey: serverID)
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
        let delay = IRCReconnectPolicy.delay(
            attempt: attempt,
            initialDelay: initialReconnectDelay,
            maximumDelay: maximumReconnectDelay
        )
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
            self.sessionIDs.removeValue(forKey: profile.id)
            self.sessionOnConnectCommands.removeValue(forKey: profile.id)
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

    private func appendChannelEvent(
        _ text: String,
        kind: IRCChannelEventKind? = nil,
        channelID: UUID,
        memberCount: Int? = nil
    ) {
        let resolvedMemberCount = memberCount ?? channelMembers[channelID]?.count ?? 0
        guard kind == nil || channelEventVisibility.shouldShow(memberCount: resolvedMemberCount) else { return }
        append(
            IRCMessage(
                sender: "•",
                text: text,
                isSystem: true,
                channelEventKind: kind,
                channelMemberCount: resolvedMemberCount
            ),
            for: .channel(channelID)
        )
    }

    private func append(
        _ message: IRCMessage,
        for item: SidebarItem,
        markUnread shouldMarkUnread: Bool = true,
        markMention shouldMarkMention: Bool = false
    ) {
        guard let id = conversationID(for: item) else { return }
        IRCConversationHistory.append(message, to: &conversations[id, default: []])
        if selection != item, !message.isSystem {
            if shouldMarkMention {
                markMention(item)
            } else if shouldMarkUnread {
                markUnread(item)
            }
        }
        messagesDidChange(for: id)
    }

    private func markUnread(_ item: SidebarItem) {
        switch item {
        case .channel(let id):
            guard let index = channels.firstIndex(where: { $0.id == id }),
                  !channels[index].hasUnread else { return }
            channels[index].hasUnread = true
        case .directMessage(let id):
            guard let index = directMessages.firstIndex(where: { $0.id == id }),
                  !directMessages[index].hasUnread else { return }
            directMessages[index].hasUnread = true
        case .connectionCenter, .server:
            break
        }
    }

    private func markMention(_ item: SidebarItem) {
        guard case .channel(let id) = item,
              let index = channels.firstIndex(where: { $0.id == id }) else { return }
        channels[index].hasUnread = true
        channels[index].hasMention = true
        channels[index].mentionRevision &+= 1
    }

    private func formatIdle(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    private func whoisKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(target, serverID: serverID))"
    }

    private func joinKey(serverID: UUID, channel: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(channel, serverID: serverID))"
    }

    private func whoKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(target, serverID: serverID))"
    }

    private func topicKey(serverID: UUID, channel: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(channel, serverID: serverID))"
    }

    private func inviteKey(serverID: UUID, nickname: String, channel: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(nickname, serverID: serverID))|\(normalizedIdentifier(channel, serverID: serverID))"
    }

    private func modeKey(serverID: UUID, target: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(target, serverID: serverID))"
    }

    private func kickKey(serverID: UUID, channel: String, nickname: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(channel, serverID: serverID))|\(normalizedIdentifier(nickname, serverID: serverID))"
    }

    private func killKey(serverID: UUID, nickname: String) -> String {
        "\(serverID.uuidString)|\(normalizedIdentifier(nickname, serverID: serverID))"
    }

    private func outgoingTextChunks(_ text: String, commandPrefix: String, suffix: String = "") -> [String] {
        IRCTextFraming.messageChunks(text, commandPrefix: commandPrefix, suffix: suffix)
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
                  identifiersEqual($0.target, target, serverID: serverID) && $0.text == text
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
        let requestID = UUID()
        let sessionID = sessionIDs[profile.id]
        channelListRequestIDs[profile.id] = requestID
        connections[profile.id]?.send(command: hasArguments ? "LIST \(arguments)" : "LIST") { [weak self] sent in
            guard let self,
                  !sent,
                  self.sessionIDs[profile.id] == sessionID,
                  self.channelListRequestIDs[profile.id] == requestID else { return }
            self.channelListsInProgress.remove(profile.id)
            self.channelListRequestIDs.removeValue(forKey: profile.id)
            self.appendSystem("The channel list request could not be sent.", for: .server(profile.id))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + channelListRequestTimeout) { [weak self] in
            guard let self,
                  self.sessionIDs[profile.id] == sessionID,
                  self.channelListRequestIDs[profile.id] == requestID,
                  self.channelListsInProgress.contains(profile.id) else { return }
            self.flushChannelListings(for: profile.id)
            self.channelListsInProgress.remove(profile.id)
            self.channelListRequestIDs.removeValue(forKey: profile.id)
            self.appendSystem("The channel list request timed out. You can retry the request.", for: .server(profile.id))
        }
    }

    private func queueChannelListing(_ listing: ChannelListing, for serverID: UUID) {
        let key = normalizedIdentifier(listing.name, serverID: serverID)
        var knownNames = knownChannelNamesByServer[serverID] ?? []
        guard knownNames.insert(key).inserted else { return }
        knownChannelNamesByServer[serverID] = knownNames
        pendingChannelListingsByServer[serverID, default: []].append(listing)

        guard scheduledChannelListFlushes.insert(serverID).inserted else { return }
        let sessionID = sessionIDs[serverID]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.sessionIDs[serverID] == sessionID else { return }
            self.flushChannelListings(for: serverID)
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
        muteSnapshotsByServer.removeAll(keepingCapacity: true)
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: "profiles")
    }

    private func saveCredentials(for profile: ServerProfile, serverPassword: String, saslPassword: String, onConnectCommands: [String], sshPassword: String, sshPrivateKey: String) {
        KeychainStore.set(serverPassword, for: credentialAccount(profile: profile, kind: "server-password"))
        KeychainStore.set(saslPassword, for: credentialAccount(profile: profile, kind: "sasl-password"))
        let cleanedCommands = onConnectCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let encodedCommands = (try? JSONEncoder().encode(cleanedCommands))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        KeychainStore.set(cleanedCommands.isEmpty ? "" : encodedCommands, for: credentialAccount(profile: profile, kind: "on-connect-commands"))
        KeychainStore.set(sshPassword, for: credentialAccount(profile: profile, kind: "ssh-password"))
        KeychainStore.set(sshPrivateKey, for: credentialAccount(profile: profile, kind: "ssh-private-key"))
    }

    private func applySSHSettings(to profile: inout ServerProfile, enabled: Bool, hostname: String, port: UInt16, username: String, keyFilename: String?) {
        profile.useSSHTunnel = enabled
        let cleanHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.sshHostname = cleanHostname.isEmpty ? nil : cleanHostname
        profile.sshPort = port
        profile.sshUsername = cleanUsername.isEmpty ? nil : cleanUsername
        profile.sshKeyFilename = keyFilename
    }

    private func credentialAccount(profile: ServerProfile, kind: String) -> String {
        "\(kind).\(profile.id.uuidString)"
    }

    private static func refreshedProfiles(from saved: [ServerProfile]) -> [ServerProfile] {
        let refreshed = saved.map { profile -> ServerProfile in
            guard profile.isBuiltIn, let matchedPreset = preset(matching: profile) else { return profile }
            if profile.isPresetModified == true {
                var migrated = profile
                migrated.presetID = matchedPreset.presetID
                return migrated
            }
            var current = matchedPreset
            current.id = profile.id
            current.autoConnect = profile.autoConnect
            current.favoriteChannels = profile.favoriteChannels
            current.mutedNicknames = profile.mutedNicknames
            current.useSASL = profile.useSASL
            current.saslUsername = profile.saslUsername
            current.useSSHTunnel = profile.useSSHTunnel
            current.sshHostname = profile.sshHostname
            current.sshPort = profile.sshPort
            current.sshUsername = profile.sshUsername
            current.sshKeyFilename = profile.sshKeyFilename
            current.sshTrustedHostKey = profile.sshTrustedHostKey
            return current
        }
        let missing = ServerProfile.recommended.filter { recommended in
            !refreshed.contains { profile in
                profile.isBuiltIn && profile.presetID == recommended.presetID
            }
        }
        return refreshed + missing
    }

    private static func preset(matching profile: ServerProfile) -> ServerProfile? {
        if let presetID = profile.presetID,
           let preset = ServerProfile.recommended.first(where: { $0.presetID == presetID }) {
            return preset
        }
        // Migrate profiles saved before stable preset IDs existed. Hostname is
        // also checked so a renamed built-in can still recover its identity.
        return ServerProfile.recommended.first {
            $0.name.caseInsensitiveCompare(profile.name) == .orderedSame
                || $0.hostname.caseInsensitiveCompare(profile.hostname) == .orderedSame
        }
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

private struct PendingJoin {
    var serverID: UUID
    var channel: String
    var channelID: UUID
    var destination: SidebarItem
    var statusMessageID: UUID
    var topic: String
    var preservesConversationOnFailure = false
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
