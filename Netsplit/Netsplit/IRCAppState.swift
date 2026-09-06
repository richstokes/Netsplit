//
//  IRCAppState.swift
//  Netsplit
//

import AppKit
import Combine
import Foundation
import OSLog
import UserNotifications

@MainActor
final class IRCAppState: ObservableObject {
    struct KeychainAccessIssue: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct IRCURLConnectionConfirmation: Identifiable {
        let id = UUID()
        let request: IRCURLRequest

        var endpointLabel: String {
            let hostname = request.endpoint.hostname
            let displayedHostname = hostname.contains(":") ? "[\(hostname)]" : hostname
            return "\(displayedHostname):\(request.endpoint.port)"
        }
    }

    private struct ScheduledReconnect {
        let requestID: UUID
        let reason: IRCReconnectReason
    }

    @Published private(set) var profiles: [ServerProfile]
    @Published var nickname: String {
        didSet { defaults.set(nickname, forKey: "nickname") }
    }
    @Published var realName: String {
        didSet { defaults.set(realName, forKey: "realName") }
    }
    @Published var quitMessage: String {
        didSet { defaults.set(quitMessage, forKey: "quitMessage") }
    }
    @Published var reconnectAutomatically: Bool {
        didSet {
            defaults.set(reconnectAutomatically, forKey: "reconnectAutomatically")
            if !reconnectAutomatically { cancelAllScheduledReconnects() }
        }
    }
    @Published var warnBeforeOpeningLinks: Bool {
        didSet { defaults.set(warnBeforeOpeningLinks, forKey: "warnBeforeOpeningLinks") }
    }
    @Published var showsCTCPCommandsInUserMenu: Bool {
        didSet {
            defaults.set(
                showsCTCPCommandsInUserMenu,
                forKey: "showsCTCPCommandsInUserMenu"
            )
        }
    }
    @Published var receivesDCCFiles: Bool {
        didSet {
            defaults.set(
                receivesDCCFiles,
                forKey: IRCDCCPreferences.receivesFilesKey
            )
            if receivesDCCFiles {
                removeStaleDCCPartialFiles()
            } else {
                stopAllDCCFileSharingActivity()
            }
        }
    }
    @Published var automaticallySavesDCCFiles: Bool {
        didSet {
            defaults.set(
                automaticallySavesDCCFiles,
                forKey: IRCDCCPreferences.automaticallySavesFilesKey
            )
        }
    }
    @Published private(set) var customDCCDownloadDirectory: URL?
    @Published var mentionNotificationsEnabled: Bool {
        didSet {
            defaults.set(mentionNotificationsEnabled, forKey: "mentionNotificationsEnabled")
            if mentionNotificationsEnabled { requestNotificationAuthorization() }
        }
    }
    @Published var directMessageNotificationsEnabled: Bool {
        didSet {
            defaults.set(directMessageNotificationsEnabled, forKey: "directMessageNotificationsEnabled")
            if directMessageNotificationsEnabled { requestNotificationAuthorization() }
        }
    }
    @Published var applicationAppearance: IRCApplicationAppearance {
        didSet { defaults.set(applicationAppearance.rawValue, forKey: "applicationAppearance") }
    }
    @Published var messageSpacing: IRCMessageSpacing {
        didSet { defaults.set(messageSpacing.rawValue, forKey: "messageSpacing") }
    }
    @Published var chatFont: IRCChatFont {
        didSet { defaults.set(chatFont.rawValue, forKey: "chatFont") }
    }
    @Published var usesColoredNicknames: Bool {
        didSet { defaults.set(usesColoredNicknames, forKey: "usesColoredNicknames") }
    }
    @Published var usesMonospacedServerMessages: Bool {
        didSet { defaults.set(usesMonospacedServerMessages, forKey: "usesMonospacedServerMessages") }
    }
    @Published var rendersIRCFormatting: Bool {
        didSet { defaults.set(rendersIRCFormatting, forKey: "rendersIRCFormatting") }
    }
    @Published var automaticallyPreviewsLinks: Bool {
        didSet { defaults.set(automaticallyPreviewsLinks, forKey: "automaticallyPreviewsLinks") }
    }
    @Published var automaticallyPreviewsImages: Bool {
        didSet { defaults.set(automaticallyPreviewsImages, forKey: "automaticallyPreviewsImages") }
    }
    @Published var channelEventVisibility: IRCChannelEventVisibility {
        didSet { defaults.set(channelEventVisibility.rawValue, forKey: "channelEventVisibility") }
    }
    @Published var transcriptFontSize: Double
    @Published var selection: SidebarItem? {
        didSet { recordSelectionChange(from: oldValue) }
    }
    @Published var showsMemberList: Bool {
        didSet { defaults.set(showsMemberList, forKey: "showsMemberList") }
    }
    @Published var showsServerChannelPane = true
    @Published var isJumpPalettePresented = false
    @Published private(set) var workspaceFocusRequest: IRCWorkspaceFocusRequest?
    @Published private(set) var connectionStatuses: [UUID: ConnectionStatus] = [:]
    @Published private var automaticReconnectResumeDates: [UUID: Date] = [:]
    @Published private var unreadInviteCountsByServer: [UUID: Int] = [:]
    @Published var isChannelBrowserPresented = false
    @Published private(set) var channelBrowserProfileID: UUID?
    @Published var keychainAccessIssue: KeychainAccessIssue?
    @Published var pendingIRCURLConnectionConfirmation: IRCURLConnectionConfirmation?

    private lazy var dccCoordinator = IRCDCCCoordinator(
        configuration: { [weak self] in
            guard let self else { return nil }
            return IRCDCCCoordinator.Configuration(
                receivesFiles: self.receivesDCCFiles,
                automaticallySavesFiles: self.automaticallySavesDCCFiles,
                downloadDirectory: self.dccDownloadDirectory,
                usesCustomDirectory: self.customDCCDownloadDirectory != nil
            )
        },
        makeRoute: { [weak self] in self?.dccReceiverRoute(for: $0) },
        caseMapping: { [weak self] in self?.features(for: $0).caseMapping ?? .rfc1459 },
        report: { [weak self] in self?.appendSystem($0, for: .server($1)) },
        ignoreSender: { [weak self] in self?.ignore($0, from: .server($1)) },
        rememberHostKey: { [weak self] in self?.rememberDCCSSHHostKey($0, for: $1) }
    )
    var pendingDCCFileOffer: IRCDCCFileOffer? {
        get { dccCoordinator.pendingDCCFileOffer }
        set { dccCoordinator.pendingDCCFileOffer = newValue }
    }
    var dccFileOfferPresentationHostID: UUID? { dccCoordinator.dccFileOfferPresentationHostID }
    var dccFileTransferCount: Int { dccCoordinator.dccFileTransferCount }
    var dccFileTransferStore: IRCDCCFileTransferStore { dccCoordinator.dccFileTransferStore }

    private let channelDirectory = IRCChannelDirectory()
    private let conversationStore = IRCConversationStore()
    private var storeSubscriptions = Set<AnyCancellable>()
    var channels: [Conversation] { conversationStore.channels }
    var directMessages: [Conversation] { conversationStore.directMessages }

    private var ignoreSnapshotsByServer: [UUID: IRCIgnoreSnapshot] = [:]
    private var sessions: [UUID: IRCServerSession] = [:]
    private var connections: [UUID: IRCConnection] = [:]
    private var disconnectingConnections: [UUID: IRCConnection] = [:]
    private var disconnectCompletionWaiters: [UUID: [@MainActor () -> Void]] = [:]
    private var oneOffServerIDs = Set<UUID>()
    private var shouldFocusComposerAfterJumpPaletteDismissal = false
    private var pendingIRCURLTargets: [UUID: [IRCURLTarget]] = [:]
    private var ctcpResponseRateLimiter = IRCCTCPResponseRateLimiter()
    private var reconnectAttempts: [UUID: Int] = [:]
    private var automaticReconnectLimiters: [UUID: IRCAutomaticReconnectLimiter] = [:]
    private var reconnectStabilityGenerations: [UUID: UUID] = [:]
    private var scheduledReconnects: [UUID: ScheduledReconnect] = [:]
    private var pendingLaunchConnectionIDs = Set<UUID>()
    private var serverFeatures: [UUID: IRCServerFeatures] = [:]
    private var incomingMessageTimestamp: Date?
    private let channelListRequestTimeout: TimeInterval = 30
    private let channelBanListRequestTimeout: TimeInterval = 15
    private let maskBanWhoRequestTimeout: TimeInterval = 10
    private let maximumTrackedIncomingBatchesPerServer = 256
    private let favoriteJoinInterval: TimeInterval = 0.45
    private let autoConnectStagger: TimeInterval = 2
    private let onConnectCommandInterval: TimeInterval = 0.5
    private let favoriteJoinDelayAfterCommands: TimeInterval = 2
    private let automaticJoinCompletionTimeout: TimeInterval = 20
    private let initialReconnectDelay: TimeInterval = 2
    private let maximumReconnectDelay: TimeInterval = 60
    private let wakeRecoveryStagger: TimeInterval = 0.2
    private static let defaultQuitMessage = "Closing Netsplit macOS client"
    private var hasStartedLaunchConnections = false
    private var hasReportedKeychainAccessIssue = false
    private var systemSleepState = IRCSystemSleepStateMachine()
    private var sleepPausedReconnectReasons: [UUID: IRCReconnectReason] = [:]
    private var pendingWakeRestoreServerIDs = Set<UUID>()
    private var wakeRestoreGeneration: UUID?
    private var backSelectionHistory: [SidebarItem] = []
    private var forwardSelectionHistory: [SidebarItem] = []
    private var isNavigatingSelectionHistory = false
    private let maximumSelectionHistoryCount = 100
    private var lastConversationSelectionByServerID: [UUID: SidebarItem] = [:]
    private var pendingMentionNotificationDestination: IRCMentionNotificationDestination?
    private static let connectionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Netsplit",
        category: "ConnectionRecovery"
    )

    private let defaults: UserDefaults
    private let ownedDefaultsSuiteName: String?
    private let credentialStore: any IRCCredentialStore

    init(defaults suppliedDefaults: UserDefaults? = nil, credentialStore: (any IRCCredentialStore)? = nil) {
        let isTesting = NetsplitLaunchEnvironment.currentProcessIsInTestMode
        let suiteName = suppliedDefaults == nil && isTesting
            ? "Netsplit.AppStateTests.\(UUID().uuidString)" : nil
        let defaults: UserDefaults
        if let suppliedDefaults {
            defaults = suppliedDefaults
        } else if let suiteName {
            guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
                fatalError("Could not create isolated test preferences")
            }
            defaults = isolatedDefaults
        } else {
            defaults = .standard
        }
        self.defaults = defaults
        self.ownedDefaultsSuiteName = suiteName
        self.credentialStore = credentialStore
            ?? (isTesting ? IRCInMemoryCredentialStore() : IRCKeychainCredentialStore())
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
        showsCTCPCommandsInUserMenu = defaults.object(forKey: "showsCTCPCommandsInUserMenu") as? Bool ?? false
        receivesDCCFiles = IRCDCCPreferences.receivesFiles(in: defaults)
        automaticallySavesDCCFiles = IRCDCCPreferences.automaticallySavesFiles(in: defaults)
        customDCCDownloadDirectory = IRCDCCPreferences.downloadDirectory(in: defaults)
        mentionNotificationsEnabled = defaults.object(forKey: "mentionNotificationsEnabled") as? Bool ?? false
        directMessageNotificationsEnabled = defaults.object(forKey: "directMessageNotificationsEnabled") as? Bool ?? false
        applicationAppearance = defaults.string(forKey: "applicationAppearance").flatMap(IRCApplicationAppearance.init(rawValue:)) ?? .system
        messageSpacing = defaults.string(forKey: "messageSpacing").flatMap(IRCMessageSpacing.init(rawValue:)) ?? .comfortable
        chatFont = defaults.string(forKey: "chatFont").flatMap(IRCChatFont.init(rawValue:)) ?? .default
        usesColoredNicknames = defaults.object(forKey: "usesColoredNicknames") as? Bool ?? false
        usesMonospacedServerMessages = defaults.object(forKey: "usesMonospacedServerMessages") as? Bool ?? true
        rendersIRCFormatting = defaults.object(forKey: "rendersIRCFormatting") as? Bool ?? false
        automaticallyPreviewsLinks = defaults.object(forKey: "automaticallyPreviewsLinks") as? Bool ?? false
        automaticallyPreviewsImages = defaults.object(forKey: "automaticallyPreviewsImages") as? Bool ?? false
        channelEventVisibility = defaults.string(forKey: "channelEventVisibility").flatMap(IRCChannelEventVisibility.init(rawValue:)) ?? .alwaysShow
        showsMemberList = defaults.object(forKey: "showsMemberList") as? Bool ?? true
        let savedTranscriptFontSize = defaults.object(forKey: "transcriptFontSize") as? Double ?? 16
        transcriptFontSize = min(max(savedTranscriptFontSize, 12), 24)

        profiles = ServerProfileStore.load(from: defaults)
        selection = .connectionCenter
        conversationStore.objectWillChange
            .merge(with: channelDirectory.objectWillChange, dccCoordinator.objectWillChange)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &storeSubscriptions)

        if mentionNotificationsEnabled
            || directMessageNotificationsEnabled
            || profiles.contains(where: { $0.mentionNotificationsOverride == true }) {
            requestNotificationAuthorization()
        }
        if receivesDCCFiles { removeStaleDCCPartialFiles() }
    }

    deinit {
        if let ownedDefaultsSuiteName {
            defaults.removePersistentDomain(forName: ownedDefaultsSuiteName)
        }
    }

    var activeProfiles: [ServerProfile] {
        IRCServerOrdering.alphabetically(
            profiles.filter { connections[$0.id] != nil }
        )
    }

    var dccDownloadDirectory: URL {
        customDCCDownloadDirectory ?? IRCDCCStoragePolicy.downloadsDirectory()
    }

    var dccDownloadDirectoryDisplayPath: String {
        dccDownloadDirectory.dccDisplayPath
    }

    func setDCCDownloadDirectory(_ directory: URL) throws {
        let bookmark = try IRCDCCPreferences.bookmark(for: directory)
        defaults.set(bookmark, forKey: IRCDCCPreferences.downloadDirectoryBookmarkKey)
        customDCCDownloadDirectory = directory
    }

    func resetDCCDownloadDirectory() {
        defaults.removeObject(forKey: IRCDCCPreferences.downloadDirectoryBookmarkKey)
        customDCCDownloadDirectory = nil
    }

    var storedProfiles: [ServerProfile] {
        profiles.filter { !oneOffServerIDs.contains($0.id) }
    }

    func isOneOffServer(_ profile: ServerProfile) -> Bool {
        oneOffServerIDs.contains(profile.id)
    }

    var selectedProfile: ServerProfile? {
        guard let selection else { return nil }
        return profile(for: selection)
    }

    var selectedChannel: Conversation? {
        guard case .channel(let id) = selection else { return nil }
        return channels.first(where: { $0.id == id })
    }

    var jumpDestinations: [IRCJumpDestination] {
        activeProfiles.flatMap { profile in
            var destinations = [IRCJumpDestination(
                selection: .server(profile.id),
                title: profile.name,
                serverName: profile.name,
                kind: .server
            )]
            destinations.append(contentsOf: channels(for: profile).map {
                IRCJumpDestination(
                    selection: .channel($0.id),
                    title: $0.name,
                    serverName: profile.name,
                    kind: .channel
                )
            })
            destinations.append(contentsOf: directMessages(for: profile).map {
                IRCJumpDestination(
                    selection: .directMessage($0.id),
                    title: $0.name,
                    serverName: profile.name,
                    kind: .directMessage
                )
            })
            return destinations
        }
    }

    var canBrowseSelectedChannels: Bool {
        guard let profile = selectedProfile else { return false }
        return canBrowseChannels(for: profile)
    }

    var channelBrowserProfile: ServerProfile? {
        guard let channelBrowserProfileID else { return nil }
        return profiles.first { $0.id == channelBrowserProfileID }
    }

    func canBrowseChannels(for profile: ServerProfile) -> Bool {
        sessions[profile.id]?.registeredAt != nil
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

    func presentJumpPalette() {
        shouldFocusComposerAfterJumpPaletteDismissal = false
        isJumpPalettePresented = true
    }

    func jumpDestinations(matching query: String) -> [IRCJumpDestination] {
        IRCJumpSearch.results(in: jumpDestinations, matching: query)
    }

    func jump(to destination: IRCJumpDestination) {
        guard isValidNavigationSelection(destination.selection) else { return }
        selection = destination.selection
        shouldFocusComposerAfterJumpPaletteDismissal = true
        isJumpPalettePresented = false
    }

    func jumpPaletteDidDismiss() {
        guard shouldFocusComposerAfterJumpPaletteDismissal else { return }
        shouldFocusComposerAfterJumpPaletteDismissal = false
        requestComposerFocus()
    }

    @discardableResult
    func selectActiveServer(number: Int) -> Bool {
        guard (1...9).contains(number), activeProfiles.indices.contains(number - 1) else { return false }
        selectServerRestoringLastConversation(activeProfiles[number - 1])
        return true
    }

    func selectServerRestoringLastConversation(_ profile: ServerProfile) {
        if let remembered = lastConversationSelectionByServerID[profile.id],
           isValidNavigationSelection(remembered),
           self.profile(for: remembered)?.id == profile.id {
            selection = remembered
        } else {
            selection = .server(profile.id)
        }
        requestComposerFocus()
    }

    func selectFromSidebar(_ newSelection: SidebarItem?) {
        selection = newSelection
        requestComposerFocus()
    }

    func openMentionNotification(_ destination: IRCMentionNotificationDestination) {
        guard profiles.contains(where: { $0.id == destination.serverID }) else { return }
        pendingMentionNotificationDestination = destination
        if !resolvePendingMentionNotificationDestination() {
            selection = .server(destination.serverID)
        }
    }

    func openDirectMessageNotification(_ destination: IRCDirectMessageNotificationDestination) {
        guard profiles.contains(where: { $0.id == destination.serverID }) else { return }
        let conversation = directMessage(named: destination.nickname, serverID: destination.serverID)
        selection = .directMessage(conversation.id)
    }

    func requestSidebarFocus() {
        showsServerChannelPane = true
        workspaceFocusRequest = IRCWorkspaceFocusRequest(target: .sidebar)
    }

    func requestComposerFocus() {
        guard let selection, selection != .connectionCenter else { return }
        workspaceFocusRequest = IRCWorkspaceFocusRequest(target: .composer(selection))
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
            || sleepPausedReconnectReasons[profile.id] != nil
    }

    func isAutomaticReconnectPaused(_ profile: ServerProfile) -> Bool {
        automaticReconnectResumeDates[profile.id] != nil
    }

    func isActive(_ profile: ServerProfile) -> Bool {
        connections[profile.id] != nil
    }

    func channels(for profile: ServerProfile) -> [Conversation] {
        channels
            .filter { $0.serverID == profile.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isJoinedChannel(named channelName: String, on serverID: UUID?) -> Bool {
        guard let serverID,
              let channel = existingChannel(named: channelName, serverID: serverID) else { return false }
        // Only our own JOIN confirms membership. A retained transcript is not a membership record.
        return conversationStore.channel(channel.id)?.joinedAt != nil
    }

    func directMessages(for profile: ServerProfile) -> [Conversation] {
        directMessages.filter { $0.serverID == profile.id }
    }

    func activity(for profile: ServerProfile) -> IRCServerActivity {
        IRCServerActivity(
            serverID: profile.id,
            conversations: (channels + directMessages).filter { !isMuted($0) }
        )
    }

    func hasUnreadActivity(for profile: ServerProfile) -> Bool {
        unreadInviteCountsByServer[profile.id, default: 0] > 0
            || channels.contains {
                $0.serverID == profile.id && ($0.hasUnread || $0.hasMention)
            }
            || directMessages.contains {
                $0.serverID == profile.id && ($0.hasUnread || $0.hasMention)
            }
    }

    func unreadInviteCount(for profile: ServerProfile) -> Int {
        unreadInviteCountsByServer[profile.id, default: 0]
    }

    func draft(for item: SidebarItem) -> String {
        conversationStore.draft(for: item)
    }

    func setDraft(_ draft: String, for item: SidebarItem) {
        conversationStore.setDraft(draft, for: item)
    }

    func recordComposerInput(_ input: String, for item: SidebarItem) {
        conversationStore.recordComposerInput(input, for: item)
    }

    func navigateComposerHistory(
        _ direction: IRCComposerHistoryDirection,
        from currentDraft: String,
        for item: SidebarItem
    ) -> String? {
        conversationStore.navigateComposerHistory(direction, from: currentDraft, for: item)
            .map { boundedComposerDraft($0, for: item) }
    }

    func resetComposerHistoryNavigation(for item: SidebarItem) {
        conversationStore.resetComposerHistoryNavigation(for: item)
    }

    func maximumMessageBytes(for item: SidebarItem) -> Int? {
        guard isMessageDestination(item), let profile = profile(for: item) else { return nil }
        let commandPrefix = "PRIVMSG \(title(for: item)) :"
        return IRCTextFraming.messageContentByteLimit(
            commandPrefix: commandPrefix,
            maximumLineLength: features(for: profile.id).maximumLineLength,
            sourcePrefix: localSourcePrefix(for: profile)
        )
    }

    func boundedComposerDraft(_ draft: String, for item: SidebarItem) -> String {
        // Slash commands have command-specific framing and are bounded again
        // when translated to the wire. The normal composer path represents one
        // PRIVMSG, so enforce its exact UTF-8 payload budget while editing.
        guard draft.first != "/", let maximumBytes = maximumMessageBytes(for: item) else {
            return draft
        }
        return IRCTextFraming.prefix(draft, fittingUTF8ByteCount: maximumBytes)
    }

    func serverPassword(for profile: ServerProfile) -> String {
        credentialValue(for: profile, kind: "server-password")
    }

    func saslPassword(for profile: ServerProfile) -> String {
        credentialValue(for: profile, kind: "sasl-password")
    }

    func sshPassword(for profile: ServerProfile) -> String {
        credentialValue(for: profile, kind: "ssh-password")
    }

    func sshPrivateKey(for profile: ServerProfile) -> String {
        credentialValue(for: profile, kind: "ssh-private-key")
    }

    func onConnectCommands(for profile: ServerProfile) -> IRCOnConnectCommandPhases {
        let encoded = credentialValue(for: profile, kind: "on-connect-commands")
        guard let data = encoded.data(using: .utf8),
              let commands = try? JSONDecoder().decode(IRCOnConnectCommandPhases.self, from: data) else {
            return IRCOnConnectCommandPhases()
        }
        return commands
    }

    func credentialSnapshot(for profile: ServerProfile) -> IRCProfileCredentialSnapshot {
        let encodedCommands = readCredential(for: profile, kind: "on-connect-commands")
        let commands: IRCOnConnectCommandPhases? = encodedCommands.flatMap { encoded in
            if encoded.isEmpty { return IRCOnConnectCommandPhases() }
            return try? JSONDecoder().decode(IRCOnConnectCommandPhases.self, from: Data(encoded.utf8))
        }
        return IRCProfileCredentialSnapshot(
            serverPassword: readCredential(for: profile, kind: "server-password"),
            saslPassword: readCredential(for: profile, kind: "sasl-password"),
            onConnectCommands: commands,
            sshPassword: readCredential(for: profile, kind: "ssh-password"),
            sshPrivateKey: readCredential(for: profile, kind: "ssh-private-key")
        )
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

    func isFavoriteDirectMessage(_ directMessage: Conversation) -> Bool {
        guard let profile = profiles.first(where: { $0.id == directMessage.serverID }) else { return false }
        return profile.favoriteDirectMessages?.contains {
            identifiersEqual($0, directMessage.name, serverID: profile.id)
        } ?? false
    }

    func toggleFavoriteDirectMessage(_ directMessage: Conversation) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == directMessage.serverID }) else { return }
        var favorites = profiles[profileIndex].favoriteDirectMessages ?? []
        if let index = favorites.firstIndex(where: {
            identifiersEqual($0, directMessage.name, serverID: directMessage.serverID)
        }) {
            favorites.remove(at: index)
        } else {
            favorites.append(directMessage.name)
        }
        profiles[profileIndex].favoriteDirectMessages = favorites.isEmpty ? nil : favorites
        saveProfiles()
    }

    func isIgnored(_ nickname: String, from item: SidebarItem) -> Bool {
        ignoreSnapshot(for: item)?.contains(nickname) ?? false
    }

    func ignoredNicknames(for profile: ServerProfile) -> [String] {
        (profiles.first(where: { $0.id == profile.id })?.ignoredNicknames ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func ignore(_ nickname: String, from item: SidebarItem) {
        setIgnore(nickname, ignored: true, from: item)
    }

    func unignore(_ nickname: String, from item: SidebarItem) {
        setIgnore(nickname, ignored: false, from: item)
    }

    @discardableResult
    func acceptDCCFileOffer(
        _ offer: IRCDCCFileOffer,
        authorizingRestrictedEndpoint: Bool = false,
        downloadDirectory selectedDownloadDirectory: URL? = nil
    ) -> Bool {
        dccCoordinator.acceptDCCFileOffer(
            offer, authorizingRestrictedEndpoint: authorizingRestrictedEndpoint,
            downloadDirectory: selectedDownloadDirectory
        )
    }

    func cancelDCCFileOffer(_ offer: IRCDCCFileOffer) {
        dccCoordinator.cancelDCCFileOffer(offer)
    }

    func cancelDCCFileTransfer(_ transfer: IRCDCCFileTransferPresentation) {
        dccCoordinator.cancelDCCFileTransfer(transfer)
    }

    func dismissDCCFileTransfer(_ transfer: IRCDCCFileTransferPresentation) {
        dccCoordinator.dismissDCCFileTransfer(transfer)
    }

    func ignoreDCCFileOfferSender(_ offer: IRCDCCFileOffer) {
        dccCoordinator.ignoreDCCFileOfferSender(offer)
    }

    func dccFileOfferSheetDidDismiss() {
        dccCoordinator.dccFileOfferSheetDidDismiss()
    }

    func registerDCCFileOfferPresentationRequest(
        _ request: @escaping @MainActor () -> Void
    ) {
        dccCoordinator.registerDCCFileOfferPresentationRequest(request)
    }

    func registerDCCFileOfferPresentationHost(_ hostID: UUID, preferAsActive: Bool) {
        dccCoordinator.registerDCCFileOfferPresentationHost(hostID, preferAsActive: preferAsActive)
    }

    func unregisterDCCFileOfferPresentationHost(_ hostID: UUID) {
        dccCoordinator.unregisterDCCFileOfferPresentationHost(hostID)
    }

    func removeAllIgnores(for profile: ServerProfile) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profile.id }),
              profiles[profileIndex].ignoredNicknames?.isEmpty == false else { return }
        profiles[profileIndex].ignoredNicknames = nil
        saveProfiles()
        appendSystem("Cleared all ignores on \(profiles[profileIndex].name).", for: .server(profile.id))
    }

    private func setIgnore(_ targetNickname: String, ignored: Bool, from item: SidebarItem) {
        guard let profile = profile(for: item),
              let profileIndex = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let cleanNickname = targetNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNickname.isEmpty else { return }

        if identifiersEqual(cleanNickname, nickname(for: profiles[profileIndex]), serverID: profile.id) {
            appendSystem("You cannot ignore your own nickname.", for: item)
            return
        }

        var ignoredNicknames = profiles[profileIndex].ignoredNicknames ?? []
        if ignored {
            guard !ignoredNicknames.contains(where: { identifiersEqual($0, cleanNickname, serverID: profile.id) }) else {
                appendSystem("\(cleanNickname) is already ignored.", for: item)
                return
            }
            ignoredNicknames.append(cleanNickname)
            appendSystem("Ignored \(cleanNickname) on \(profiles[profileIndex].name).", for: item)
        } else {
            guard let index = ignoredNicknames.firstIndex(where: { identifiersEqual($0, cleanNickname, serverID: profile.id) }) else {
                appendSystem("\(cleanNickname) is not ignored.", for: item)
                return
            }
            ignoredNicknames.remove(at: index)
            appendSystem("Stopped ignoring \(cleanNickname) on \(profiles[profileIndex].name).", for: item)
        }
        profiles[profileIndex].ignoredNicknames = ignoredNicknames.isEmpty ? nil : ignoredNicknames
        saveProfiles()
    }

    private func isIgnored(_ nickname: String, on profile: ServerProfile) -> Bool {
        ignoreSnapshot(for: profile).contains(nickname)
    }

    private func enqueueDCCFileOffer(_ offer: IRCDCCFileOffer) {
        dccCoordinator.enqueueDCCFileOffer(offer)
    }

    private func removePendingDCCFileOffers(for serverID: UUID) {
        dccCoordinator.removePendingDCCFileOffers(for: serverID)
    }

    private func stopAllDCCFileSharingActivity(cleanupGroup: DispatchGroup? = nil) {
        dccCoordinator.stopAllDCCFileSharingActivity(cleanupGroup: cleanupGroup)
    }

    private func removeStaleDCCPartialFiles() {
        guard !NetsplitLaunchEnvironment.currentProcessIsInTestMode else { return }
        Task.detached(priority: .utility) {
            IRCDCCFileSink.removeStalePartialFiles()
        }
    }

    private func dccReceiverRoute(for offer: IRCDCCFileOffer) -> IRCDCCFileReceiver.Route? {
        guard let profile = profiles.first(where: { $0.id == offer.serverID }) else {
            return nil
        }

        if offer.routesThroughSSH {
            guard let sshHostname = profile.sshHostname?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshHostname.isEmpty,
                  let sshUsername = profile.sshUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sshUsername.isEmpty else {
                appendSystem(
                    "Could not receive \(offer.request.filename): the SSH tunnel profile is incomplete.",
                    for: .server(profile.id)
                )
                return nil
            }
            return .ssh(SSHTunnelConfiguration(
                sshHostname: sshHostname,
                sshPort: Int(profile.sshPort ?? 22),
                sshUsername: sshUsername,
                sshPassword: sshPassword(for: profile),
                sshPrivateKey: sshPrivateKey(for: profile),
                trustedHostKey: profile.sshTrustedHostKey,
                targetHostname: offer.request.hostname,
                targetPort: Int(offer.request.port),
                useTLS: false
            ))
        } else {
            return .direct
        }
    }

    private func rememberDCCSSHHostKey(_ key: String, for serverID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == serverID }),
              profiles[profileIndex].sshTrustedHostKey == nil else { return }
        profiles[profileIndex].sshTrustedHostKey = key
        saveProfiles()
        appendSystem(
            "Saved the SSH host identity for future connections.",
            for: .server(serverID)
        )
    }

    func isMuted(_ conversation: Conversation) -> Bool {
        guard let profile = profiles.first(where: { $0.id == conversation.serverID }) else { return false }
        return profile.mutedConversationNames?.contains {
            identifiersEqual($0, conversation.name, serverID: conversation.serverID)
        } ?? false
    }

    func mute(_ conversation: Conversation) {
        setMuted(true, for: conversation)
    }

    func unmute(_ conversation: Conversation) {
        setMuted(false, for: conversation)
    }

    private func setMuted(_ muted: Bool, for conversation: Conversation) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == conversation.serverID }) else { return }
        var mutedNames = profiles[profileIndex].mutedConversationNames ?? []
        if muted {
            guard !mutedNames.contains(where: {
                identifiersEqual($0, conversation.name, serverID: conversation.serverID)
            }) else { return }
            mutedNames.append(conversation.name)
            clearActivity(for: conversation)
        } else {
            guard let index = mutedNames.firstIndex(where: {
                identifiersEqual($0, conversation.name, serverID: conversation.serverID)
            }) else { return }
            mutedNames.remove(at: index)
        }
        profiles[profileIndex].mutedConversationNames = mutedNames.isEmpty ? nil : mutedNames
        saveProfiles()
    }

    private func clearActivity(for conversation: Conversation) {
        conversationStore.markRead(.channel(conversation.id))
        conversationStore.markRead(.directMessage(conversation.id))
    }

    func leave(_ channel: Conversation, reason: String? = nil) {
        guard let profile = profiles.first(where: { $0.id == channel.serverID }) else { return }
        let part: String
        if let reason, !reason.isEmpty {
            part = "PART \(channel.name) :\(reason)"
        } else {
            part = "PART \(channel.name)"
        }
        connections[profile.id]?.send(command: part)
        removeChannelConversation(channel)
    }

    func close(_ directMessage: Conversation) {
        guard let profile = profiles.first(where: { $0.id == directMessage.serverID }) else { return }
        conversationStore.remove(.directMessage(directMessage.id))
        if selection == .directMessage(directMessage.id) {
            selection = .server(profile.id)
        }
    }

    func ignoreAndClose(_ directMessage: Conversation) {
        ignore(directMessage.name, from: .directMessage(directMessage.id))
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
        defaults.set(clampedSize, forKey: "transcriptFontSize")
    }

    func connectProfilesConfiguredForLaunch() {
        guard !hasStartedLaunchConnections else { return }
        hasStartedLaunchConnections = true

        let originalSelection = selection
        let launchProfiles = profiles.filter(\.autoConnect)
        let delays = IRCAutoConnectPolicy.launchDelays(
            for: launchProfiles,
            stagger: autoConnectStagger
        )
        for (profile, delay) in zip(launchProfiles, delays) {
            let sshHost = profile.useSSHTunnel == true
                ? profile.sshHostname ?? "unconfigured"
                : "direct"
            Self.connectionLogger.info(
                "Launch auto-connect scheduled server=\(profile.name, privacy: .public) sshHost=\(sshHost, privacy: .public) delay=\(delay, privacy: .public)"
            )
            guard delay > 0 else {
                Self.connectionLogger.info(
                    "Launch auto-connect starting server=\(profile.name, privacy: .public) sshHost=\(sshHost, privacy: .public)"
                )
                connect(profile, selectConversation: false)
                continue
            }

            pendingLaunchConnectionIDs.insert(profile.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.pendingLaunchConnectionIDs.remove(profile.id) != nil,
                      self.connections[profile.id] == nil,
                      let currentProfile = self.profiles.first(where: { $0.id == profile.id }) else { return }
                Self.connectionLogger.info(
                    "Launch auto-connect starting server=\(currentProfile.name, privacy: .public) sshHost=\(sshHost, privacy: .public)"
                )
                self.connect(currentProfile, selectConversation: false)
            }
        }
        selection = originalSelection
    }

    /// Preserve established transports through sleep, but pause app-level
    /// watchdogs and reconnect work until the system is fully awake. On wake,
    /// each established session is validated with a staggered IRC heartbeat.
    func systemWillSleep() {
        let reconnectingServerIDs = Set(scheduledReconnects.keys)
        let serverIDsToRestore = Set(connections.keys.filter { serverID in
            IRCSystemSleepPolicy.shouldRestoreConnection(
                status: connectionStatuses[serverID] ?? .offline,
                reconnectWasScheduled: reconnectingServerIDs.contains(serverID)
            )
        }).union(pendingWakeRestoreServerIDs)
        guard systemSleepState.beginSleep(restoring: serverIDsToRestore) != nil else { return }

        wakeRestoreGeneration = nil
        pendingWakeRestoreServerIDs.removeAll()
        for (serverID, request) in scheduledReconnects {
            // Invalidates the already-enqueued closure without resetting the
            // attempt count. The same attempt resumes after wake.
            sleepPausedReconnectReasons[serverID] = request.reason
        }
        scheduledReconnects.removeAll()
        for serverID in serverIDsToRestore {
            // Time spent asleep does not demonstrate a healthy IRC session.
            // Invalidate the stability timer and restart it after wake for any
            // session that still needs its reconnect history forgiven.
            reconnectStabilityGenerations.removeValue(forKey: serverID)
            connections[serverID]?.systemWillSleep()
        }
        Self.connectionLogger.info(
            "System sleep paused sessions=\(serverIDsToRestore.count, privacy: .public) reconnects=\(reconnectingServerIDs.count, privacy: .public)"
        )
    }

    func systemDidWake() {
        guard let serverIDsToRestore = systemSleepState.beginWake() else { return }
        let wakeGeneration = UUID()
        wakeRestoreGeneration = wakeGeneration
        let profilesToRestore = profiles
            .filter { serverIDsToRestore.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Self.connectionLogger.info(
            "System wake resuming sessions=\(profilesToRestore.count, privacy: .public)"
        )
        for (index, profile) in profilesToRestore.enumerated() {
            if let reason = sleepPausedReconnectReasons.removeValue(forKey: profile.id) {
                scheduleReconnect(
                    for: profile,
                    reason: reason,
                    reuseCurrentAttempt: true
                )
            } else if let transport = connections[profile.id] {
                if sessions[profile.id]?.registeredAt != nil {
                    scheduleReconnectStateResetAfterStability(for: profile)
                }
                transport.systemDidWake(after: Double(index) * wakeRecoveryStagger)
            } else {
                // A desired session should normally retain its transport. If a
                // framework callback removed it while sleeping, restore it with
                // the same stagger used for wake probes.
                let delay = Double(index) * wakeRecoveryStagger
                pendingWakeRestoreServerIDs.insert(profile.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          self.wakeRestoreGeneration == wakeGeneration,
                          !self.systemSleepState.isSleeping,
                          self.pendingWakeRestoreServerIDs.remove(profile.id) != nil,
                          self.connections[profile.id] == nil,
                          self.profiles.contains(where: { $0.id == profile.id }) else { return }
                    Self.connectionLogger.info(
                        "Restoring missing transport after wake server=\(profile.name, privacy: .public)"
                    )
                    self.connect(profile, selectConversation: false)
                }
            }
        }
    }

    @discardableResult
    func openIRCURL(_ url: URL) -> Bool {
        guard let request = IRCURLParser.request(from: url) else { return false }
        let endpoint = request.endpoint
        if let existingProfile = profiles.first(where: {
            $0.hostname.compare(endpoint.hostname, options: [.caseInsensitive]) == .orderedSame
                && $0.port == endpoint.port
                && $0.useTLS == endpoint.useTLS
        }) {
            openIRCURLRequest(request, on: existingProfile)
        } else {
            pendingIRCURLConnectionConfirmation = IRCURLConnectionConfirmation(request: request)
        }
        return true
    }

    func confirmIRCURLConnection(_ confirmation: IRCURLConnectionConfirmation) {
        guard pendingIRCURLConnectionConfirmation?.id == confirmation.id else { return }
        pendingIRCURLConnectionConfirmation = nil
        let endpoint = confirmation.request.endpoint
        let profile = ServerProfile(
            name: endpoint.hostname,
            hostname: endpoint.hostname,
            port: endpoint.port,
            useTLS: endpoint.useTLS
        )
        oneOffServerIDs.insert(profile.id)
        profiles.append(profile)
        openIRCURLRequest(confirmation.request, on: profile)
    }

    func cancelIRCURLConnection(_ confirmation: IRCURLConnectionConfirmation) {
        guard pendingIRCURLConnectionConfirmation?.id == confirmation.id else { return }
        pendingIRCURLConnectionConfirmation = nil
    }

    private func openIRCURLRequest(_ request: IRCURLRequest, on profile: ServerProfile) {
        selection = .server(profile.id)
        if !request.targets.isEmpty {
            var pending = pendingIRCURLTargets[profile.id, default: []]
            for target in request.targets where !pending.contains(target) {
                pending.append(target)
            }
            pendingIRCURLTargets[profile.id] = pending
        }

        if sessions[profile.id]?.registeredAt != nil {
            openPendingIRCURLTargets(for: profile)
        } else if case .failed = status(for: profile) {
            reconnect(profile)
        } else if connections[profile.id] == nil {
            connect(profile)
        }
    }

    func toggleConnection(for profile: ServerProfile) {
        if connections[profile.id] != nil {
            if case .failed = status(for: profile) {
                reconnect(profile)
            } else {
                disconnect(profile)
            }
        } else {
            connect(profile)
        }
    }

    func reconnect(_ profile: ServerProfile) {
        let wasOneOffServer = isOneOffServer(profile)
        disconnect(profile, moveSelection: false)
        if wasOneOffServer {
            oneOffServerIDs.insert(profile.id)
            profiles.append(profile)
        }
        connect(profile)
    }

    func connect(_ profile: ServerProfile, selectConversation: Bool = true, isAutomaticRetry: Bool = false) {
        pendingLaunchConnectionIDs.remove(profile.id)
        guard connections[profile.id] == nil else { return }
        if !isAutomaticRetry { cancelScheduledReconnect(for: profile.id, resetAttempts: true) }
        // A new transport cannot inherit stability time from the previous
        // connection, including when this is an automatic retry.
        reconnectStabilityGenerations.removeValue(forKey: profile.id)
        serverFeatures[profile.id] = .defaults
        prepareChannelsForDisconnectedSession(for: profile.id)
        resetChannelListingRequest(for: profile.id)
        sessions[profile.id] = IRCServerSession(
            id: UUID(), onConnectCommands: onConnectCommands(for: profile),
            nickname: configuredNickname(for: profile)
        )
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
            realName: realName(for: profile),
            serverPassword: serverPassword(for: profile),
            saslUsername: profile.saslUsername,
            saslPassword: saslPassword(for: profile),
            sshPassword: sshPassword(for: profile),
            sshPrivateKey: sshPrivateKey(for: profile)
        )
    }

    private func connectOneOffServer(_ argument: String, reportingTo item: SidebarItem) {
        switch IRCOneOffServerCommand.endpoint(from: argument) {
        case .failure(let error):
            appendSystem(error.message, for: item)
        case .success(let endpoint):
            let profile = ServerProfile(
                name: endpoint.hostname,
                hostname: endpoint.hostname,
                port: endpoint.port,
                useTLS: endpoint.useTLS
            )
            oneOffServerIDs.insert(profile.id)
            profiles.append(profile)
            connect(profile)
        }
    }

    func disconnect(
        _ profile: ServerProfile,
        reason: String? = nil,
        moveSelection: Bool = true
    ) {
        let orderedActiveServerIDs = activeProfiles.map(\.id)
        let selectedServerID = selection.flatMap { self.profile(for: $0)?.id }
        pendingLaunchConnectionIDs.remove(profile.id)
        systemSleepState.remove(profile.id)
        pendingWakeRestoreServerIDs.remove(profile.id)
        cancelScheduledReconnect(for: profile.id, resetAttempts: true)
        resetChannelListingRequest(for: profile.id)
        prepareChannelsForDisconnectedSession(for: profile.id)
        let transport = connections[profile.id]
        connections.removeValue(forKey: profile.id)
        sessions.removeValue(forKey: profile.id)
        connectionStatuses.removeValue(forKey: profile.id)
        if let transport {
            retainWhileQuitting(transport, reason: reason ?? resolvedQuitMessage())
        }
        if moveSelection,
           let fallback = IRCDisconnectSelectionPolicy.fallback(
               afterDisconnecting: profile.id,
               selectedServerID: selectedServerID,
               orderedActiveServerIDs: orderedActiveServerIDs
           ) {
            removeNavigationHistory(for: profile.id)
            selectWithoutRecordingHistory(fallback)
        }
        if oneOffServerIDs.remove(profile.id) != nil {
            automaticReconnectLimiters.removeValue(forKey: profile.id)
            removeConversations(for: profile.id)

            serverFeatures.removeValue(forKey: profile.id)
            ignoreSnapshotsByServer.removeValue(forKey: profile.id)
            profiles.removeAll { $0.id == profile.id }
        }
    }

    /// Used by the application delegate during termination. Completion is
    /// guaranteed quickly so quitting the app is never held up by a network
    /// problem, while active connections still get a real IRC QUIT command.
    func quitAllConnections(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        stopAllDCCFileSharingActivity(cleanupGroup: group)
        pendingLaunchConnectionIDs.removeAll()
        let activeConnections = Array(connections.values)
        let inFlightQuitIDs = Array(disconnectingConnections.keys)

        cancelAllScheduledReconnects()
        systemSleepState = IRCSystemSleepStateMachine()
        wakeRestoreGeneration = nil
        pendingWakeRestoreServerIDs.removeAll()
        connections.removeAll()
        // Settle server-confirmed messages before their request records retire.
        for serverID in Array(sessions.keys) { resetPendingRequests(for: serverID) }
        sessions.removeAll()
        connectionStatuses.removeAll()

        for quitID in inFlightQuitIDs {
            group.enter()
            disconnectCompletionWaiters[quitID, default: []].append {
                group.leave()
            }
        }
        for connection in activeConnections {
            group.enter()
            retainWhileQuitting(connection, reason: resolvedQuitMessage()) {
                group.leave()
            }
        }

        var didComplete = false
        let completeOnce = {
            guard !didComplete else { return }
            didComplete = true
            completion()
        }
        group.notify(queue: .main) {
            completeOnce()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            completeOnce()
        }
    }

    func showConnections() {
        selection = .connectionCenter
    }

    @discardableResult
    func addProfile(id: UUID = UUID(), name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, nicknameOverride: String, realNameOverride: String, mentionNotificationsOverride: Bool?, credentials: IRCProfileCredentialChanges, useSASL: Bool, saslUsername: String, useSSHTunnel: Bool, sshHostname: String, sshPort: UInt16, sshUsername: String, sshKeyFilename: String?) -> IRCProfileSaveResult {
        var profile = ServerProfile(name: name, hostname: hostname, port: port, useTLS: useTLS, autoConnect: autoConnect)
        profile.id = id
        let cleanNickname = nicknameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.nicknameOverride = cleanNickname.isEmpty ? nil : cleanNickname
        let cleanRealName = realNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.realNameOverride = cleanRealName.isEmpty ? nil : cleanRealName
        profile.mentionNotificationsOverride = mentionNotificationsOverride
        profile.useSASL = useSASL
        profile.saslUsername = saslUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : saslUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        applySSHSettings(to: &profile, enabled: useSSHTunnel, hostname: sshHostname, port: sshPort, username: sshUsername, keyFilename: sshKeyFilename)
        let result = saveCredentials(credentials, for: profile)
        guard result.succeeded else { return result }
        profiles.append(profile)
        saveProfiles()
        selection = .connectionCenter
        if mentionNotificationsOverride == true { requestNotificationAuthorization() }
        return result
    }

    func delete(_ profile: ServerProfile) {
        guard !isOneOffServer(profile), profiles.contains(where: { $0.id == profile.id }) else {
            return
        }
        ServerProfileStore.recordDeletedPreset(matching: profile, in: defaults)
        disconnect(profile)
        removeConversations(for: profile.id)
        removeCredential(for: profile, kind: "server-password")
        removeCredential(for: profile, kind: "sasl-password")
        removeCredential(for: profile, kind: "on-connect-commands")
        removeCredential(for: profile, kind: "ssh-password")
        removeCredential(for: profile, kind: "ssh-private-key")
        profiles.removeAll { $0.id == profile.id }
        automaticReconnectLimiters.removeValue(forKey: profile.id)
        saveProfiles()
    }

    @discardableResult
    func updateProfile(_ profile: ServerProfile, name: String, hostname: String, port: UInt16, useTLS: Bool, autoConnect: Bool, nicknameOverride: String, realNameOverride: String, mentionNotificationsOverride: Bool?, credentials: IRCProfileCredentialChanges, useSASL: Bool, saslUsername: String, useSSHTunnel: Bool, sshHostname: String, sshPort: UInt16, sshUsername: String, sshKeyFilename: String?, resetSSHHostKey: Bool) -> IRCProfileSaveResult {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return IRCProfileSaveResult(succeeded: false) }
        var updated = profile
        updated.name = name
        updated.hostname = hostname
        updated.port = port
        updated.useTLS = useTLS
        updated.autoConnect = autoConnect
        let cleanNickname = nicknameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nicknameOverride = cleanNickname.isEmpty ? nil : cleanNickname
        let cleanRealName = realNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.realNameOverride = cleanRealName.isEmpty ? nil : cleanRealName
        updated.mentionNotificationsOverride = mentionNotificationsOverride
        updated.useSASL = useSASL
        let cleanSASLUsername = saslUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.saslUsername = cleanSASLUsername.isEmpty ? nil : cleanSASLUsername
        let oldSSHIdentity = "\(profile.sshHostname ?? ""):\(profile.sshPort ?? 22)"
        applySSHSettings(to: &updated, enabled: useSSHTunnel, hostname: sshHostname, port: sshPort, username: sshUsername, keyFilename: sshKeyFilename)
        let newSSHIdentity = "\(updated.sshHostname ?? ""):\(updated.sshPort ?? 22)"
        if oldSSHIdentity != newSSHIdentity || resetSSHHostKey { updated.sshTrustedHostKey = nil }
        if updated.isBuiltIn { updated.isPresetModified = true }
        let result = saveCredentials(credentials, for: updated)
        guard result.succeeded else { return result }
        profiles[index] = updated
        saveProfiles()
        if mentionNotificationsOverride == true { requestNotificationAuthorization() }
        return result
    }

    func restorePreset(_ profile: ServerProfile) {
        guard profile.isBuiltIn,
              var preset = ServerProfileStore.preset(matching: profile),
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        preset.id = profile.id
        preset.autoConnect = profile.autoConnect
        preset.mentionNotificationsOverride = profile.mentionNotificationsOverride
        preset.favoriteChannels = profile.favoriteChannels
        preset.favoriteDirectMessages = profile.favoriteDirectMessages
        preset.ignoredNicknames = profile.ignoredNicknames
        preset.mutedConversationNames = profile.mutedConversationNames
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
        defaults.set(nickname, forKey: "nickname")
        defaults.set(resolvedRealName(), forKey: "realName")
    }

    func messages(
        for item: SidebarItem,
        channelEventVisibility visibility: IRCChannelEventVisibility
    ) -> [IRCMessage] {
        guard conversationID(for: item) != nil else { return [] }
        let messages = conversationStore.messages(for: item)
        guard case .channel = item, visibility != .alwaysShow else { return messages }
        return messages.filter { message in
            guard message.channelEventKind != nil else { return true }
            return visibility.shouldShow(memberCount: message.channelMemberCount ?? 0)
        }
    }

    func messageUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        conversationStore.messageUpdates(for: item)
    }

    func markRead(_ item: SidebarItem) {
        conversationStore.markRead(item)
        if case .server(let id) = item {
            unreadInviteCountsByServer.removeValue(forKey: id)
        }
    }

    func markAllRead(for profile: ServerProfile) {
        conversationStore.markAllRead(on: profile.id)
        unreadInviteCountsByServer.removeValue(forKey: profile.id)
    }

    func members(for item: SidebarItem) -> [ChannelMember] {
        guard case .channel(let id) = item else { return [] }
        guard let profile = profile(for: item) else { return [] }
        return conversationStore.channel(id)?.members ?? [
            ChannelMember(
                nickname: nickname(for: profile),
                membership: features(for: profile.id).membership
            )
        ]
    }

    func canManageChannel(in item: SidebarItem) -> Bool {
        guard let profile = profile(for: item),
              let localMember = member(named: nickname(for: profile), in: item) else { return false }
        return localMember.hasOperatorPrivileges
    }

    func canModerate(_ targetNickname: String, in item: SidebarItem) -> Bool {
        guard case .channel(let channelID) = item,
              let profile = profile(for: item),
              let members = conversationStore.channel(channelID)?.members else { return false }
        return IRCChannelModerationPolicy.canModerate(
            localNickname: nickname(for: profile),
            targetNickname: targetNickname,
            members: members,
            caseMapping: features(for: profile.id).caseMapping
        )
    }

    func moderationState(
        for targetNickname: String,
        in item: SidebarItem
    ) -> IRCMemberModerationState? {
        member(named: targetNickname, in: item).map(IRCMemberModerationState.init(member:))
    }

    func setOperator(_ enabled: Bool, for targetNickname: String, in item: SidebarItem) {
        guard canModerate(targetNickname, in: item),
              let profile = profile(for: item),
              let operatorMode = features(for: profile.id).membership.operatorMode,
              case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }) else { return }
        executeCommand("/mode \(channel.name) \(enabled ? "+" : "-")\(operatorMode) \(targetNickname)", in: item)
    }

    private func member(named targetNickname: String, in item: SidebarItem) -> ChannelMember? {
        guard case .channel(let channelID) = item,
              let profile = profile(for: item),
              let members = conversationStore.channel(channelID)?.members else { return nil }
        let target = normalizedIdentifier(targetNickname, serverID: profile.id)
        return members.first(where: {
            normalizedIdentifier($0.nickname, serverID: profile.id) == target
        })
    }

    func setVoice(_ enabled: Bool, for targetNickname: String, in item: SidebarItem) {
        guard canModerate(targetNickname, in: item),
              let profile = profile(for: item),
              let voiceMode = features(for: profile.id).membership.voiceMode,
              case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }) else { return }
        executeCommand("/mode \(channel.name) \(enabled ? "+" : "-")\(voiceMode) \(targetNickname)", in: item)
    }

    func kick(_ targetNickname: String, from item: SidebarItem) {
        guard canModerate(targetNickname, in: item),
              case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }) else { return }
        executeCommand("/kick \(channel.name) \(targetNickname)", in: item)
    }

    func ban(_ targetNickname: String, from item: SidebarItem) {
        guard canModerate(targetNickname, in: item),
              case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }) else { return }
        let mask = member(named: targetNickname, in: item)
            .map(IRCChannelModerationPolicy.banMask(for:))
            ?? IRCChannelModerationPolicy.banMask(for: targetNickname)
        executeCommand("/mode \(channel.name) +b \(mask)", in: item)
    }

    func banAndKick(_ targetNickname: String, from item: SidebarItem) {
        guard canModerate(targetNickname, in: item) else { return }
        ban(targetNickname, from: item)
        kick(targetNickname, from: item)
    }

    func bans(for item: SidebarItem) -> [IRCBanEntry] {
        guard case .channel(let channelID) = item else { return [] }
        return conversationStore.channel(channelID)?.bans ?? []
    }

    func isRequestingBans(for item: SidebarItem) -> Bool {
        guard case .channel(let channelID) = item else { return false }
        return conversationStore.channel(channelID)?.isRequestingBans == true
    }

    func banListError(for item: SidebarItem) -> String? {
        guard case .channel(let channelID) = item else { return nil }
        return conversationStore.channel(channelID)?.banError
    }

    func requestBanList(for item: SidebarItem) {
        guard case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }),
              let state = conversationStore.channel(channelID),
              let profile = profile(for: item) else { return }
        guard canSendMessages(on: profile, reportingTo: item) else {
            state.failBanRequest("Connect to the server before requesting the ban list.")
            return
        }
        let requestID = state.beginBanRequest()
        connections[profile.id]?.send(command: "MODE \(channel.name) +b")
        DispatchQueue.main.asyncAfter(deadline: .now() + channelBanListRequestTimeout) { [weak state] in
            state?.failBanRequest("The server did not finish the ban-list response.", requestID: requestID)
        }
    }

    func removeBan(_ ban: IRCBanEntry, from item: SidebarItem) {
        guard canManageChannel(in: item),
              case .channel(let channelID) = item,
              let channel = channels.first(where: { $0.id == channelID }) else { return }
        executeCommand("/mode \(channel.name) -b \(ban.mask)", in: item)
    }

    func memberUpdates(for item: SidebarItem) -> IRCRevisionSignal {
        conversationStore.memberUpdates(for: item)
    }

    func ignoreSnapshot(for item: SidebarItem) -> IRCIgnoreSnapshot? {
        guard let profile = profile(for: item) else { return nil }
        return ignoreSnapshot(for: profile)
    }

    func topic(for item: SidebarItem) -> String? {
        guard case .channel(let id) = item,
              let topic = conversationStore.channel(id)?.topic?.trimmingCharacters(in: .whitespacesAndNewlines),
              !topic.isEmpty else { return nil }
        return topic
    }

    func channelTypes(for item: SidebarItem) -> Set<Character> {
        profile(for: item).map { features(for: $0.id).channelTypes } ?? Set("#&+!")
    }

    func channelListings(for profileID: UUID?) -> [ChannelListing] {
        guard let profileID else { return [] }
        return channelDirectory.entries(for: profileID)
    }

    func isChannelListingInProgress(for profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return channelDirectory.isRequesting(profileID)
    }

    func requestChannelListing(forceRefresh: Bool = false) {
        guard let profile = selectedProfile else { return }
        requestChannelListing(for: profile, forceRefresh: forceRefresh)
    }

    func requestChannelListing(for profile: ServerProfile, forceRefresh: Bool = false) {
        requestChannelListing(for: profile, arguments: "", forceRefresh: forceRefresh)
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
        guard isChannelName(channel, serverID: profile.id) else { return }
        join(
            ChannelListing(name: channel, userCount: 0, topic: ""),
            on: profile,
            selectConversation: true,
            destination: item
        )
    }

    private func runPostRegistrationSequence(for profile: ServerProfile) {
        guard let sessionID = sessions[profile.id]?.id else { return }
        let commands = translatedOnConnectCommands(
            sessions[profile.id, default: .init()].onConnectCommands?.beforeFavoritesJoined ?? [],
            serverID: profile.id
        )

        if !commands.isEmpty {
            appendSystem(
                "Running \(commands.count) pre-join command\(commands.count == 1 ? "" : "s")…",
                for: .server(profile.id)
            )
        }

        sendOnConnectCommands(
            commands,
            phaseDescription: "pre-join",
            for: profile,
            sessionID: sessionID
        )

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
        guard let sessionID = sessions[profile.id]?.id else { return }
        var seenChannelNames = Set<String>()
        let retainedChannelNames = channels(for: profile).map(\.name)
        let channelNames = (retainedChannelNames + (profile.favoriteChannels ?? [])).filter { channelName in
            let trimmed = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seenChannelNames.insert(normalizedIdentifier(trimmed, serverID: profile.id)).inserted
        }
        let hasPostJoinCommands = !translatedOnConnectCommands(
            sessions[profile.id, default: .init()].onConnectCommands?.afterFavoritesJoined ?? [],
            serverID: profile.id
        ).isEmpty
        if hasPostJoinCommands {
            sessions[profile.id, default: .init()].automaticJoins = IRCOnConnectJoinTracker(
                channelNames: channelNames
            )
        } else {
            sessions[profile.id]?.automaticJoins = nil
        }

        if channelNames.isEmpty {
            guard hasPostJoinCommands else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + firstJoinDelay) { [weak self] in
                self?.runAfterFavoriteChannelsJoinedCommandsIfReady(
                    for: profile,
                    sessionID: sessionID
                )
            }
            return
        }

        for (index, channelName) in channelNames.enumerated() {
            let delay = firstJoinDelay + (Double(index) * favoriteJoinInterval)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.sessions[profile.id]?.id == sessionID,
                      self.sessions[profile.id]?.registeredAt != nil,
                      self.connections[profile.id] != nil,
                      let activeProfile = self.profiles.first(where: { $0.id == profile.id }) else { return }
                if let retainedChannel = self.existingChannel(named: channelName, serverID: profile.id) {
                    self.rejoin(retainedChannel, on: activeProfile)
                } else {
                    self.join(ChannelListing(name: channelName, userCount: 0, topic: ""), on: activeProfile, selectConversation: false, destination: .server(profile.id))
                }
                let key = self.joinKey(serverID: profile.id, channel: channelName)
                if self.sessions[profile.id, default: .init()].requests.joins[key] == nil {
                    self.completeAutomaticJoinAttempt(
                        channelName,
                        for: activeProfile,
                        sessionID: sessionID
                    )
                }
            }
        }

        guard hasPostJoinCommands else { return }
        let finalJoinDelay = firstJoinDelay + (Double(channelNames.count - 1) * favoriteJoinInterval)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + finalJoinDelay + automaticJoinCompletionTimeout
        ) { [weak self] in
            guard let self,
                  self.sessions[profile.id]?.id == sessionID,
                  self.sessions[profile.id]?.registeredAt != nil,
                  self.connections[profile.id] != nil,
                  let pending = self.sessions[profile.id, default: .init()].automaticJoins,
                  !pending.isComplete else { return }
            self.appendSystem(
                "Some channels did not finish joining; continuing with post-join commands.",
                for: .server(profile.id)
            )
            self.sessions[profile.id, default: .init()].automaticJoins = IRCOnConnectJoinTracker(
                channelNames: []
            )
            self.runAfterFavoriteChannelsJoinedCommandsIfReady(
                for: profile,
                sessionID: sessionID
            )
        }
    }

    private func completeAutomaticJoinAttempt(
        _ channelName: String,
        for profile: ServerProfile,
        sessionID: UUID
    ) {
        guard sessions[profile.id]?.id == sessionID,
              var pending = sessions[profile.id, default: .init()].automaticJoins else { return }
        pending.complete(
            channelName,
            caseMapping: features(for: profile.id).caseMapping
        )
        sessions[profile.id, default: .init()].automaticJoins = pending
        runAfterFavoriteChannelsJoinedCommandsIfReady(for: profile, sessionID: sessionID)
    }

    private func runAfterFavoriteChannelsJoinedCommandsIfReady(
        for profile: ServerProfile,
        sessionID: UUID
    ) {
        guard sessions[profile.id]?.id == sessionID,
              sessions[profile.id]?.registeredAt != nil,
              let pending = sessions[profile.id, default: .init()].automaticJoins,
              pending.isComplete else { return }
        sessions[profile.id]?.automaticJoins = nil

        let commands = translatedOnConnectCommands(
            sessions[profile.id, default: .init()].onConnectCommands?.afterFavoritesJoined ?? [],
            serverID: profile.id
        )
        guard !commands.isEmpty else { return }
        appendSystem(
            "Running \(commands.count) post-join command\(commands.count == 1 ? "" : "s")…",
            for: .server(profile.id)
        )
        sendOnConnectCommands(
            commands,
            phaseDescription: "post-join",
            for: profile,
            sessionID: sessionID
        )
    }

    private func translatedOnConnectCommands(_ commands: [String], serverID: UUID) -> [String] {
        let serverFeatures = features(for: serverID)
        return commands.compactMap {
            IRCCommandTranslator.onConnectWireCommand(
                from: $0,
                channelTypes: serverFeatures.channelTypes,
                preferredChannelPrefix: serverFeatures.preferredChannelPrefix
            )
        }
    }

    private func sendOnConnectCommands(
        _ commands: [String],
        phaseDescription: String,
        for profile: ServerProfile,
        sessionID: UUID
    ) {
        for (index, command) in commands.enumerated() {
            let delay = Double(index) * onConnectCommandInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.sessions[profile.id]?.id == sessionID,
                      self.sessions[profile.id]?.registeredAt != nil,
                      let connection = self.connections[profile.id] else { return }
                var command = IRCTextFraming.sanitizedSingleLine(command)
                var echoIDs: [UUID] = []
                let hiddenMessage = IRCMessage(sender: self.nickname(for: profile), text: "")
                if let wire = IRCWireMessage(line: command),
                   wire.command == "PRIVMSG" || wire.command == "NOTICE",
                   let targets = wire.parameter(at: 0), let text = wire.parameter(at: 1) {
                    let label = self.outgoingEchoLabel(for: profile.id, id: UUID())
                    for target in targets.split(separator: ",").map(String.init) {
                        echoIDs.append(self.rememberOutgoingEcho(
                            serverID: profile.id,
                            target: target,
                            wireText: text,
                            message: hiddenMessage,
                            destination: .server(profile.id),
                            presentation: wire.command == "NOTICE" ? .notice(target: target) : .message,
                            suppressTranscript: true,
                            label: label ?? (wire.tags["label"] ?? nil)
                        ))
                    }
                    if let label {
                        if command.hasPrefix("@"), let separator = command.firstIndex(of: " ") {
                            let existingTags = command[command.index(after: command.startIndex)..<separator]
                                .split(separator: ";").filter { $0.split(separator: "=", maxSplits: 1).first != "label" }
                            command = "@" + (existingTags.map(String.init) + ["label=\(label)"]).joined(separator: ";") + command[separator...]
                        } else {
                            command = "@label=\(label) \(command)"
                        }
                    }
                }
                connection.send(command: command) { [weak self] sent in
                    guard let self, self.sessions[profile.id]?.id == sessionID else { return }
                    for echoID in echoIDs {
                        self.handleOutgoingWriteCompletion(
                            serverID: profile.id,
                            id: echoID,
                            succeeded: sent,
                            fallbackMessage: hiddenMessage,
                            fallbackDestination: .server(profile.id),
                            suppressTranscript: true
                        )
                    }
                    if !sent {
                        self.appendSystem("A \(phaseDescription) command could not be sent.", for: .server(profile.id))
                    }
                }
            }
        }
    }

    private func rejoin(_ channel: Conversation, on profile: ServerProfile) {
        join(
            ChannelListing(name: channel.name, userCount: 0, topic: ""),
            on: profile,
            selectConversation: false,
            destination: .channel(channel.id)
        )
    }

    private func join(_ listing: ChannelListing, on profile: ServerProfile, selectConversation: Bool, destination: SidebarItem) {
        join(listing, key: nil, on: profile, selectConversation: selectConversation, destination: destination)
    }

    private func join(_ listing: ChannelListing, key: String?, on profile: ServerProfile, selectConversation: Bool, destination: SidebarItem) {
        guard sessions[profile.id]?.registeredAt != nil, let connection = connections[profile.id] else {
            appendSystem("Wait for the server to finish connecting before joining a channel.", for: destination)
            return
        }
        guard validateChannelName(listing.name, serverID: profile.id, reportingTo: destination) else { return }
        let requestKey = joinKey(serverID: profile.id, channel: listing.name)
        let existing = existingChannel(named: listing.name, serverID: profile.id)
        if let existing, conversationStore.channel(existing.id)?.joinedAt != nil || sessions[profile.id, default: .init()].requests.joins[requestKey] != nil {
            if selectConversation { selection = .channel(existing.id) }
            return
        }
        let channel = existing ?? Conversation(name: listing.name, serverID: profile.id)
        if existing == nil { conversationStore.addChannel(channel) }
        conversationStore.channel(channel.id)?.prepareToJoin(topic: listing.topic, key: key)
        let verb = existing == nil ? "Joining" : "Rejoining"
        let joiningMessage = IRCMessage(sender: "System", text: "\(verb) \(listing.name)…", isSystem: true)
        conversationStore.append(joiningMessage, for: .channel(channel.id))
        sessions[profile.id, default: .init()].requests.joins[requestKey] = PendingJoin(
            serverID: profile.id,
            channel: listing.name,
            channelID: channel.id,
            destination: destination,
            statusMessageID: joiningMessage.id,
            topic: listing.topic,
            preservesConversationOnFailure: existing != nil,
            selectsConversationOnSuccess: selectConversation
        )
        // Keep keys only with the in-memory conversation so reconnect and /hop can rejoin it.
        let joinCommand = conversationStore.channel(channel.id)?.joinKey.map { "JOIN \(listing.name) \($0)" } ?? "JOIN \(listing.name)"

        let sessionID = sessions[profile.id]?.id
        connection.send(command: joinCommand) { [weak self] sent in
            guard let self, !sent, self.sessions[profile.id]?.id == sessionID,
                  let pendingJoin = self.sessions[profile.id, default: .init()].requests.joins[requestKey],
                  pendingJoin.statusMessageID == joiningMessage.id else { return }
            self.failPendingJoin(pendingJoin, reason: "The join request could not be sent.")
        }
        scheduleJoinTimeout(statusMessageID: joiningMessage.id, serverID: profile.id)
    }

    private func scheduleJoinTimeout(statusMessageID: UUID, serverID: UUID) {
        let sessionID = sessions[serverID]?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + automaticJoinCompletionTimeout) { [weak self] in
            guard let self, self.sessions[serverID]?.id == sessionID,
                  let pendingJoin = self.sessions[serverID, default: .init()].requests.joins.values.first(where: {
                      $0.serverID == serverID && $0.statusMessageID == statusMessageID
                  }) else { return }
            self.failPendingJoin(pendingJoin, reason: "The server did not confirm the join. Try joining again.")
        }
    }

    private func openPendingIRCURLTargets(for profile: ServerProfile) {
        guard sessions[profile.id]?.registeredAt != nil,
              connections[profile.id] != nil,
              let targets = pendingIRCURLTargets.removeValue(forKey: profile.id) else { return }
        for (index, target) in targets.enumerated() {
            let selectConversation = index == targets.indices.last
            switch target {
            case .channel(let channel):
                join(
                    ChannelListing(name: channel.name, userCount: 0, topic: ""),
                    key: channel.key,
                    on: profile,
                    selectConversation: selectConversation,
                    destination: .server(profile.id)
                )
            case .directMessage(let nickname):
                let conversation = openDirectMessage(named: nickname, serverID: profile.id)
                if selectConversation { selection = .directMessage(conversation.id) }
            }
        }
    }

    func beginNewConversation() {
        guard let profile = selectedProfile else { return }
        let conversation = Conversation(name: "new-message", serverID: profile.id)
        conversationStore.addDirectMessage(conversation)
        conversationStore.initializeMessages([IRCMessage(sender: "System", text: "Start a private conversation with /msg nickname your message.", isSystem: true)], for: .directMessage(conversation.id))
        selection = .directMessage(conversation.id)

    }

    func startDirectMessage(with nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item) else { return }
        let conversation = openDirectMessage(named: nickname, serverID: profile.id)
        selection = .directMessage(conversation.id)
    }

    private func openFavoriteDirectMessages(for serverID: UUID) {
        guard let favoriteNames = profiles.first(where: { $0.id == serverID })?.favoriteDirectMessages else { return }
        var openedNames = Set<String>()
        for favoriteName in favoriteNames {
            let nickname = favoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nickname.isEmpty,
                  openedNames.insert(normalizedIdentifier(nickname, serverID: serverID)).inserted else { continue }
            openDirectMessage(named: nickname, serverID: serverID)
        }
    }

    func requestWhois(for nickname: String, from item: SidebarItem) {
        guard let profile = profile(for: item), !nickname.isEmpty else { return }
        guard canSendMessages(on: profile, reportingTo: item) else { return }
        sessions[profile.id, default: .init()].requests.whois[whoisKey(serverID: profile.id, target: nickname)] = item
        connections[profile.id]?.send(command: "WHOIS \(nickname)")
        appendSystem("Looking up \(nickname)…", for: item)
    }

    func requestCTCP(_ command: IRCCTCPCommand, of nickname: String, from item: SidebarItem) {
        let target = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = profile(for: item), !target.isEmpty else { return }
        guard canSendMessages(on: profile, reportingTo: item) else { return }

        switch command {
        case .version:
            requestClientVersion(of: target, on: profile, from: item)
        case .ping:
            requestUserPing(of: target, on: profile, from: item)
        case .time, .clientInfo:
            requestSimpleCTCP(command, of: target, on: profile, from: item)
        }
    }

    @discardableResult
    func send(_ text: String, to item: SidebarItem) -> Bool {
        if text.hasPrefix("/") {
            recordComposerInput(text, for: item)
            executeCommand(text, in: item)
            return true
        }
        guard isMessageDestination(item), let profile = profile(for: item) else {
            appendSystem("Select a channel or private message before sending text.", for: item)
            return false
        }
        let messageText = IRCTextFraming.sanitizedSingleLine(text)
        if let maximumBytes = maximumMessageBytes(for: item),
           messageText.utf8.count > maximumBytes {
            appendSystem(
                "That message is too long for this server. Shorten it to \(maximumBytes) UTF-8 bytes.",
                for: item
            )
            return false
        }
        guard canSendMessages(on: profile, reportingTo: item) else { return false }
        let target = title(for: item)
        let sender = nickname(for: profile)
        let sessionID = sessions[profile.id]?.id
        let optimisticMessage = IRCMessage(sender: sender, text: messageText)
        let echoID = rememberOutgoingEcho(
            serverID: profile.id,
            target: target,
            wireText: messageText,
            message: optimisticMessage,
            destination: item
        )
        let labelPrefix = outgoingLabelPrefix(
            for: profile.id,
            label: outgoingEchoLabel(for: profile.id, id: echoID)
        )
        connections[profile.id]?.send(
            command: "\(labelPrefix)PRIVMSG \(target) :\(messageText)"
        ) { [weak self] sent in
            guard let self else { return }
            self.handleOutgoingWriteCompletion(
                serverID: profile.id,
                id: echoID,
                succeeded: sent
                    && self.sessions[profile.id]?.id == sessionID
                    && self.sessions[profile.id]?.registeredAt != nil,
                fallbackMessage: optimisticMessage,
                fallbackDestination: item
            )
        }
        recordComposerInput(text, for: item)
        return true
    }

    private func executeCommand(_ input: String, in item: SidebarItem) {
        let parts = input.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first?.uppercased() else { return }
        let argument = parts.count > 1 ? parts[1] : ""
        if command == "SERVER" {
            connectOneOffServer(argument, reportingTo: item)
            return
        }
        guard let profile = profile(for: item) else { return }
        let localCommands: Set<String> = [
            "CLEAR",
            "SHOWIGNORES", "IGNORE", "UNIGNORE",
            "SHOWMUTES", "MUTE", "UNMUTE",
            "QUIT", "DISCONNECT"
        ]
        if !localCommands.contains(command), !canSendMessages(on: profile, reportingTo: item) {
            return
        }
        let sessionID = sessions[profile.id]?.id
        switch command {
        case "CLEAR":
            guard argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /clear", for: item)
                return
            }
            clearTranscript(for: item)
        case "SHOWIGNORES":
            let ignoredNicknames = (profile.ignoredNicknames ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if ignoredNicknames.isEmpty {
                appendSystem("No users are ignored on \(profile.name).", for: item)
            } else {
                appendSystem("Ignored on \(profile.name): \(ignoredNicknames.joined(separator: ", ")).", for: item)
            }
        case "IGNORE":
            guard !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /ignore nickname", for: item)
                return
            }
            ignore(argument, from: item)
        case "UNIGNORE":
            guard !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /unignore nickname", for: item)
                return
            }
            unignore(argument, from: item)
        case "SHOWMUTES":
            let mutedNames = (profile.mutedConversationNames ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if mutedNames.isEmpty {
                appendSystem("No conversations are muted on \(profile.name).", for: item)
            } else {
                appendSystem("Muted on \(profile.name): \(mutedNames.joined(separator: ", ")).", for: item)
            }
        case "MUTE", "UNMUTE":
            guard argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                appendSystem("Usage: /\(command.lowercased())", for: item)
                return
            }
            guard let conversation = conversation(for: item) else {
                appendSystem("Select a channel or direct message first.", for: item)
                return
            }
            setMuted(command == "MUTE", for: conversation)
        case "JOIN":
            let fields = argument.split(separator: " ").map(String.init)
            guard let rawChannel = fields.first, fields.count <= 2 else {
                appendSystem("Usage: /join channel [key]", for: item)
                return
            }
            let serverFeatures = features(for: profile.id)
            let channel = serverFeatures.isChannelName(rawChannel)
                ? rawChannel
                : "\(serverFeatures.preferredChannelPrefix)\(rawChannel)"
            join(
                ChannelListing(name: channel, userCount: 0, topic: ""),
                key: fields.count == 2 ? fields[1] : nil,
                on: profile,
                selectConversation: true,
                destination: item
            )
        case "LIST":
            requestChannelListing(for: profile, arguments: argument)
        case "MSG", "QUERY":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /msg nickname message", for: item); return }
            let conversation = openDirectMessage(named: fields[0], serverID: profile.id)
            let sender = nickname(for: profile)
            for chunk in outgoingTextChunks(
                fields[1],
                commandPrefix: "PRIVMSG \(fields[0]) :",
                maximumLineLength: features(for: profile.id).maximumLineLength,
                sourcePrefix: localSourcePrefix(for: profile)
            ) {
                let destination = SidebarItem.directMessage(conversation.id)
                let optimisticMessage = IRCMessage(sender: sender, text: chunk)
                let echoID = rememberOutgoingEcho(
                    serverID: profile.id,
                    target: fields[0],
                    wireText: chunk,
                    message: optimisticMessage,
                    destination: destination
                )
                let labelPrefix = outgoingLabelPrefix(
                    for: profile.id,
                    label: outgoingEchoLabel(for: profile.id, id: echoID)
                )
                connections[profile.id]?.send(
                    command: "\(labelPrefix)PRIVMSG \(fields[0]) :\(chunk)"
                ) { [weak self] sent in
                    guard let self else { return }
                    self.handleOutgoingWriteCompletion(
                        serverID: profile.id,
                        id: echoID,
                        succeeded: sent
                            && self.sessions[profile.id]?.id == sessionID
                            && self.sessions[profile.id]?.registeredAt != nil,
                        fallbackMessage: optimisticMessage,
                        fallbackDestination: destination
                    )
                }
            }
            if command == "QUERY" { selection = .directMessage(conversation.id) }
        case "NOTICE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { appendSystem("Usage: /notice target message", for: item); return }
            for chunk in outgoingTextChunks(
                fields[1],
                commandPrefix: "NOTICE \(fields[0]) :",
                maximumLineLength: features(for: profile.id).maximumLineLength,
                sourcePrefix: localSourcePrefix(for: profile)
            ) {
                let optimisticMessage = IRCMessage(
                    sender: "System",
                    text: "Notice sent to \(fields[0]): \(chunk)",
                    isSystem: true,
                    isNotice: true
                )
                let echoID = rememberOutgoingEcho(
                    serverID: profile.id,
                    target: fields[0],
                    wireText: chunk,
                    message: optimisticMessage,
                    destination: item,
                    presentation: .notice(target: fields[0])
                )
                let labelPrefix = outgoingLabelPrefix(
                    for: profile.id,
                    label: outgoingEchoLabel(for: profile.id, id: echoID)
                )
                connections[profile.id]?.send(
                    command: "\(labelPrefix)NOTICE \(fields[0]) :\(chunk)"
                ) { [weak self] sent in
                    guard let self else { return }
                    self.handleOutgoingWriteCompletion(
                        serverID: profile.id,
                        id: echoID,
                        succeeded: sent
                            && self.sessions[profile.id]?.id == sessionID
                            && self.sessions[profile.id]?.registeredAt != nil,
                        fallbackMessage: optimisticMessage,
                        fallbackDestination: item
                    )
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
            for chunk in outgoingTextChunks(
                argument,
                commandPrefix: "PRIVMSG \(target) :\u{01}ACTION ",
                suffix: "\u{01}",
                maximumLineLength: features(for: profile.id).maximumLineLength,
                sourcePrefix: localSourcePrefix(for: profile)
            ) {
                let action = "\u{01}ACTION \(chunk)\u{01}"
                let optimisticMessage = IRCMessage(
                    sender: "* \(sender)",
                    text: chunk,
                    nicknameColorKey: sender
                )
                let echoID = rememberOutgoingEcho(
                    serverID: profile.id,
                    target: target,
                    wireText: action,
                    message: optimisticMessage,
                    destination: item,
                    presentation: .action
                )
                let labelPrefix = outgoingLabelPrefix(
                    for: profile.id,
                    label: outgoingEchoLabel(for: profile.id, id: echoID)
                )
                connections[profile.id]?.send(
                    command: "\(labelPrefix)PRIVMSG \(target) :\(action)"
                ) { [weak self] sent in
                    guard let self else { return }
                    self.handleOutgoingWriteCompletion(
                        serverID: profile.id,
                        id: echoID,
                        succeeded: sent
                            && self.sessions[profile.id]?.id == sessionID
                            && self.sessions[profile.id]?.registeredAt != nil,
                        fallbackMessage: optimisticMessage,
                        fallbackDestination: item
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
            for chunk in outgoingTextChunks(
                slap,
                commandPrefix: "PRIVMSG \(target) :\u{01}ACTION ",
                suffix: "\u{01}",
                maximumLineLength: features(for: profile.id).maximumLineLength,
                sourcePrefix: localSourcePrefix(for: profile)
            ) {
                let action = "\u{01}ACTION \(chunk)\u{01}"
                let optimisticMessage = IRCMessage(
                    sender: "* \(sender)",
                    text: chunk,
                    nicknameColorKey: sender
                )
                let echoID = rememberOutgoingEcho(
                    serverID: profile.id,
                    target: target,
                    wireText: action,
                    message: optimisticMessage,
                    destination: item,
                    presentation: .action
                )
                let labelPrefix = outgoingLabelPrefix(
                    for: profile.id,
                    label: outgoingEchoLabel(for: profile.id, id: echoID)
                )
                connections[profile.id]?.send(
                    command: "\(labelPrefix)PRIVMSG \(target) :\(action)"
                ) { [weak self] sent in
                    guard let self else { return }
                    self.handleOutgoingWriteCompletion(
                        serverID: profile.id,
                        id: echoID,
                        succeeded: sent
                            && self.sessions[profile.id]?.id == sessionID
                            && self.sessions[profile.id]?.registeredAt != nil,
                        fallbackMessage: optimisticMessage,
                        fallbackDestination: item
                    )
                }
            }
        case "PING":
            let fields = argument.split(whereSeparator: \.isWhitespace)
            guard fields.count == 1 else {
                appendSystem("Usage: /ping nickname", for: item)
                return
            }
            requestUserPing(of: String(fields[0]), on: profile, from: item)
        case "VERSION":
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.isEmpty {
                requestServerVersion(for: profile, from: item)
            } else {
                requestClientVersion(of: target, on: profile, from: item)
            }
        case "CTCP":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2,
                  let ctcpCommand = IRCCTCPCommand(rawValue: fields[1].uppercased()) else {
                appendSystem("Usage: /ctcp nickname version|ping|time|clientinfo", for: item)
                return
            }
            requestCTCP(ctcpCommand, of: fields[0], from: item)
        case "WHOIS":
            guard let target = argument.split(separator: " ").first.map(String.init), !target.isEmpty else {
                appendSystem("Usage: /whois nickname", for: item)
                return
            }
            requestWhois(for: target, from: item)
        case "WHO":
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { appendSystem("Usage: /who channel-or-nickname", for: item); return }
            sessions[profile.id, default: .init()].requests.who[whoKey(serverID: profile.id, target: target)] = item
            connections[profile.id]?.send(command: "WHO \(target)")
            appendSystem("Looking up \(target)…", for: item)
        case "MOTD":
            let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            requestMOTD(
                from: profile,
                target: target,
                deliveringTo: item,
                announcesRequest: true
            )
        case "TOPIC":
            executeTopic(argument, on: profile, from: item)
        case "MODE":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard let target = fields.first, !target.isEmpty else {
                appendSystem("Usage: /mode nickname flags or /mode #channel flags [arguments]", for: item)
                return
            }
            sessions[profile.id, default: .init()].requests.modes[modeKey(serverID: profile.id, target: target)] = item
            connections[profile.id]?.send(command: "MODE \(argument)")
            let action = fields.count == 1 ? "Requesting modes for \(target)…" : "Changing modes for \(target)…"
            appendSystem(action, for: item)
        case "OP", "DEOP", "VOICE", "DEVOICE":
            let defaultChannel: String? = if case .channel(let channelID) = item {
                channels.first(where: { $0.id == channelID })?.name
            } else {
                nil
            }
            guard let memberMode = IRCMemberModeCommand.parse(
                argument,
                defaultChannel: defaultChannel,
                channelTypes: features(for: profile.id).channelTypes
            ) else {
                appendSystem("Usage: /\(command.lowercased()) [#channel] nickname", for: item)
                return
            }
            guard let operation = IRCMemberModeOperation(command: command) else { return }
            let membership = features(for: profile.id).membership
            guard let wireCommand = memberMode.wireCommand(
                for: operation,
                membership: membership
            ) else {
                appendSystem("This server does not advertise a \(operation.roleName) channel mode.", for: item)
                return
            }
            sessions[profile.id, default: .init()].requests.modes[modeKey(serverID: profile.id, target: memberMode.channel)] = item
            connections[profile.id]?.send(command: wireCommand)
            appendSystem("Changing modes for \(memberMode.channel)…", for: item)
        case "BAN":
            let defaultChannel: String? = if case .channel(let channelID) = item {
                channels.first(where: { $0.id == channelID })?.name
            } else {
                nil
            }
            guard let ban = IRCBanCommand.parse(
                argument,
                defaultChannel: defaultChannel,
                channelTypes: features(for: profile.id).channelTypes
            ) else {
                appendSystem("Usage: /ban mask [#channel] [reason]", for: item)
                return
            }
            guard let channel = existingChannel(named: ban.channel, serverID: profile.id) else {
                appendSystem("Join \(ban.channel) before banning members from it.", for: item)
                return
            }
            let key = modeKey(serverID: profile.id, target: channel.name)
            let currentMembers = conversationStore.channel(channel.id)?.members ?? []
            let needsIdentityLookup = currentMembers.isEmpty || currentMembers.contains {
                $0.username?.isEmpty != false || $0.hostname?.isEmpty != false
            }
            sessions[profile.id, default: .init()].requests.maskBans[key, default: []].append(PendingMaskBan(
                serverID: profile.id,
                channel: channel.name,
                mask: ban.mask,
                reason: ban.reason,
                destination: item,
                state: needsIdentityLookup ? .waitingForWho : .ready
            ))
            if needsIdentityLookup {
                beginMaskBanIdentityLookup(for: channel, profile: profile)
            } else {
                sendNextPendingMaskBan(forKey: key, profile: profile)
            }
            appendSystem("Banning \(ban.mask) from \(channel.name)…", for: item)
        case "INVITE":
            let fields = argument.split(separator: " ", maxSplits: 2).map(String.init)
            guard fields.count == 2 else {
                appendSystem("Usage: /invite nickname #channel", for: item)
                return
            }
            let invitation = PendingInvite(serverID: profile.id, nickname: fields[0], channel: fields[1], destination: item)
            sessions[profile.id, default: .init()].requests.invites[inviteKey(serverID: profile.id, nickname: fields[0], channel: fields[1])] = invitation
            connections[profile.id]?.send(command: "INVITE \(fields[0]) \(fields[1])")
            appendSystem("Inviting \(fields[0]) to \(fields[1])…", for: item)
        case "KICK":
            let defaultChannel: String? = if case .channel(let channelID) = item {
                channels.first(where: { $0.id == channelID })?.name
            } else {
                nil
            }
            guard let kick = IRCKickCommand.parse(
                argument,
                defaultChannel: defaultChannel,
                channelTypes: features(for: profile.id).channelTypes
            ) else {
                appendSystem("Usage: /kick [#channel] nickname [reason]", for: item)
                return
            }
            let key = kickKey(serverID: profile.id, channel: kick.channel, nickname: kick.nickname)
            sessions[profile.id, default: .init()].requests.kicks[key] = PendingKick(
                serverID: profile.id,
                channel: kick.channel,
                nickname: kick.nickname,
                destination: item
            )
            let command = kick.reason.map {
                "KICK \(kick.channel) \(kick.nickname) :\($0)"
            } ?? "KICK \(kick.channel) \(kick.nickname)"
            connections[profile.id]?.send(command: command)
            appendSystem("Kicking \(kick.nickname) from \(kick.channel)…", for: item)
        case "KILL":
            let fields = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard fields.count == 2 else {
                appendSystem("Usage: /kill nickname reason", for: item)
                return
            }
            let key = killKey(serverID: profile.id, nickname: fields[0])
            sessions[profile.id, default: .init()].requests.kills[key] = PendingKill(serverID: profile.id, nickname: fields[0], destination: item)
            connections[profile.id]?.send(command: "KILL \(fields[0]) :\(fields[1])")
            appendSystem("Disconnecting \(fields[0]) from the network…", for: item)
        case "NICK":
            let newNickname = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newNickname.isEmpty else {
                appendSystem("Usage: /nick nickname", for: item)
                return
            }
            if let error = IRCIdentityValidation.nicknameError(newNickname) {
                appendSystem(error, for: item)
                return
            }
            if let maximumLength = features(for: profile.id).maximumNicknameLength,
               newNickname.count > maximumLength {
                appendSystem(
                    "This server limits nicknames to \(maximumLength) characters.",
                    for: item
                )
                return
            }
            sessions[profile.id, default: .init()].requests.nick = item
            connections[profile.id]?.send(command: "NICK \(newNickname)")
            appendSystem("Changing nickname to \(newNickname)…", for: item)
        case "PART":
            executePart(argument, on: profile, from: item)
        case "HOP":
            executeHop(argument, on: profile, from: item)
        case "QUIT", "DISCONNECT":
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
            if isChannelName(fields[0], serverID: profile.id) {
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
        sessions[profile.id, default: .init()].requests.topics[key] = item
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
        if isChannelName(fields[0], serverID: profile.id) {
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

    private func executeHop(_ argument: String, on profile: ServerProfile, from item: SidebarItem) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentChannel: Conversation? = {
            guard case .channel(let id) = item else { return nil }
            return channels.first(where: { $0.id == id && $0.serverID == profile.id })
        }()

        let targetChannel: Conversation
        let reason: String?
        if trimmed.isEmpty {
            guard let currentChannel else {
                appendSystem("Usage: /hop [#channel] [message]", for: item)
                return
            }
            targetChannel = currentChannel
            reason = nil
        } else {
            let fields = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            if isChannelName(fields[0], serverID: profile.id) {
                guard let namedChannel = existingChannel(named: fields[0], serverID: profile.id) else {
                    appendSystem("You are not joined to \(fields[0]).", for: item)
                    return
                }
                targetChannel = namedChannel
                reason = fields.count > 1 ? fields[1] : nil
            } else if let currentChannel {
                targetChannel = currentChannel
                reason = trimmed
            } else {
                appendSystem("Join or select a channel, or use /hop #channel [message].", for: item)
                return
            }
        }

        let key = joinKey(serverID: profile.id, channel: targetChannel.name)
        guard sessions[profile.id, default: .init()].requests.joins[key] == nil else {
            appendSystem("Wait for \(targetChannel.name) to finish joining before hopping.", for: item)
            return
        }

        let part = reason.map { "PART \(targetChannel.name) :\($0)" }
            ?? "PART \(targetChannel.name)"
        connections[profile.id]?.send(command: part)
        conversationStore.channel(targetChannel.id)?.joinedAt = nil
        rejoin(targetChannel, on: profile)
    }

    private func handle(_ event: IRCTransportEvent, from profile: ServerProfile, transport: IRCConnection) {
        guard connections[profile.id] === transport else { return }
        switch event {
        case .status(let status):
            if case .offline = status, sessions[profile.id, default: .init()].terminalError != nil { return }
            if case .online = status {
                sessions[profile.id]?.terminalError = nil
                connectionStatuses[profile.id] = sessions[profile.id]?.registeredAt != nil ? .online : .connecting
            } else {
                if case .offline = status {

                    sessions[profile.id]?.registeredAt = nil
                    prepareChannelsForDisconnectedSession(for: profile.id)
                    resetChannelListingRequest(for: profile.id)
                }
                if case .failed = status {

                    sessions[profile.id]?.registeredAt = nil
                    prepareChannelsForDisconnectedSession(for: profile.id)
                    resetChannelListingRequest(for: profile.id)
                }
                connectionStatuses[profile.id] = status
            }
            switch status {
            case .failed(let message):
                appendSystem(message, for: .server(profile.id))
                scheduleReconnect(for: profile, reason: .connectionStatus)
            case .offline:
                appendSystem("Connection closed.", for: .server(profile.id))
                scheduleReconnect(for: profile, reason: .connectionStatus)
            case .connecting, .online:
                break
            }
        case .notice(let text): appendSystem(text, for: .server(profile.id))
        case .recoverableFailure(let message, let reason):
            // IRC ERROR already records the server-provided explanation and
            // schedules recovery. Suppress the transport's follow-on close so
            // the same disconnect is not presented twice.
            guard sessions[profile.id, default: .init()].terminalError == nil else { return }

            sessions[profile.id]?.registeredAt = nil
            prepareChannelsForDisconnectedSession(for: profile.id)
            resetChannelListingRequest(for: profile.id)
            connectionStatuses[profile.id] = .failed(message)
            appendSystem(message, for: .server(profile.id))
            scheduleReconnect(for: profile, reason: reason)
        case .terminalFailure(let message):

            sessions[profile.id]?.registeredAt = nil
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

    func handle(_ incomingWire: IRCWireMessage, profile: ServerProfile) {
        var wire = incomingWire
        if let batchID = wire.tags["batch"] ?? nil,
           wire.tags["label"] == nil,
           let label = sessions[profile.id, default: .init()].requests.batches?[batchID]?.label {
            wire.tags["label"] = label
        }
        let previousIncomingMessageTimestamp = incomingMessageTimestamp
        incomingMessageTimestamp = IRCServerTimeParser.date(from: wire.tags["time"] ?? nil)
        defer { incomingMessageTimestamp = previousIncomingMessageTimestamp }
        let sender = wire.prefix?.split(separator: "!").first.map(String.init) ?? profile.name
        rememberLocalSourcePrefix(wire.prefix, sender: sender, profile: profile)
        if handleLabeledOutgoingError(wire, profile: profile) { return }
        switch wire.command {
        case "001":
            if let registeredNickname = wire.parameters.first, !registeredNickname.isEmpty {
                sessions[profile.id, default: .init()].nickname = registeredNickname
            }

            sessions[profile.id, default: .init()].registeredAt = Date()
            sessions[profile.id]?.attemptedNicknameSuffixes.removeAll()
            connectionStatuses[profile.id] = .online
            // Registration alone is not enough to call a connection healthy.
            // Preserve backoff through short-lived sleep/wake and path-loss
            // cycles, then reset it after a sustained online interval.
            cancelScheduledReconnect(for: profile.id, resetAttempts: false)
            scheduleReconnectStateResetAfterStability(for: profile)
            appendSystem(wire.trailing ?? "Connected.", for: .server(profile.id))
            openFavoriteDirectMessages(for: profile.id)
            requestMOTD(
                from: profile,
                deliveringTo: .server(profile.id),
                announcesRequest: false
            )
            runPostRegistrationSequence(for: profile)
            openPendingIRCURLTargets(for: profile)
        case "005":
            updateServerFeatures(from: wire, serverID: profile.id)
        case "BATCH":
            updateIncomingBatchState(
                from: wire,
                serverID: profile.id,
                hasExplicitLabel: incomingWire.tags["label"] != nil
            )
        case "ACK":
            if let label = wire.tags["label"] ?? nil {
                _ = reconcileOutgoingAcknowledgement(
                    serverID: profile.id,
                    label: label
                )
            }
        case "NOTICE":
            guard let target = wire.parameter(at: 0), let text = wire.parameter(at: 1) else { return }
            let isOwnNotice = identifiersEqual(
                sender,
                nickname(for: profile),
                serverID: profile.id
            )
            if isOwnNotice,
               isDuplicateSelfTargetedDelivery(
                serverID: profile.id,
                target: target,
                wireText: text,
                presentation: .notice(target: target),
                tags: wire.tags
            ) {
                return
            }
            if isOwnNotice,
               reconcileOutgoingEcho(
                serverID: profile.id,
                target: target,
                wireText: text,
                tags: wire.tags,
                timestamp: incomingMessageTimestamp,
                maximumEchoBytes: relayedMessageByteLimit(
                    target: target,
                    sourcePrefix: wire.prefix,
                    profile: profile,
                    command: "NOTICE"
                )
               ) {
                return
            }
            if isOwnNotice, suppressesOnConnectResponse(wire, serverID: profile.id) { return }
            guard !isIgnored(sender, on: profile) else { return }
            guard !handleCTCP(
                text,
                from: sender,
                target: target,
                profile: profile,
                canReplyToRequest: false,
                tags: wire.tags
            ) else { return }

            // IRC notices are delivered as a distinct message type, but they
            // still belong beside the conversation they address. Server notices
            // and recognized network service broadcasts remain in the server log.
            if let channelTarget = features(for: profile.id).channelName(fromMessageTarget: target) {
                let channel = channel(named: channelTarget, serverID: profile.id)
                append(
                    IRCMessage(
                        sender: "\(sender) (notice)",
                        text: text,
                        isNotice: true,
                        nicknameColorKey: sender,
                        ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                    ),
                    for: .channel(channel.id),
                    markUnread: !isOwnNotice,
                    markMention: !isOwnNotice && messageMentionsLocalNickname(text, on: profile)
                )
            } else if !isOwnNotice,
                      let channel = channelReferencedByNotice(text, serverID: profile.id) {
                append(
                    IRCMessage(
                        sender: "\(sender) (notice)",
                        text: text,
                        isNotice: true,
                        nicknameColorKey: sender,
                        ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                    ),
                    for: .channel(channel.id),
                    markMention: messageMentionsLocalNickname(text, on: profile)
                )
            } else if isOwnNotice {
                let conversation = directMessage(named: target, serverID: profile.id)
                append(
                    IRCMessage(
                        sender: "\(sender) (notice)",
                        text: text,
                        isNotice: true,
                        nicknameColorKey: sender,
                        ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                    ),
                    for: .directMessage(conversation.id),
                    markUnread: false
                )
            } else {
                switch IRCNoticeRoutingPolicy.fallbackDestination(
                    sender: sender,
                    prefix: wire.prefix,
                    caseMapping: features(for: profile.id).caseMapping
                ) {
                case .server:
                    if wire.prefix?.contains("!") == true {
                        append(
                            IRCMessage(
                                sender: "\(sender) (notice)",
                                text: text,
                                isSystem: true,
                                isNotice: true,
                                nicknameColorKey: sender,
                                ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                            ),
                            for: .server(profile.id)
                        )
                    } else {
                        append(
                            IRCMessage(
                                sender: "System",
                                text: text,
                                isSystem: true,
                                isNotice: true,
                                ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                            ),
                            for: .server(profile.id)
                        )
                    }
                case .directMessage:
                    let conversation = directMessage(named: sender, serverID: profile.id)
                    append(
                        IRCMessage(
                            sender: "\(sender) (notice)",
                            text: text,
                            isNotice: true,
                            nicknameColorKey: sender,
                            ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                        ),
                        for: .directMessage(conversation.id),
                        notifyDirectMessage: true
                    )
                }
            }
        case "PRIVMSG":
            guard let target = wire.parameter(at: 0), let text = wire.parameter(at: 1) else { return }
            let isOwnMessage = identifiersEqual(
                sender,
                nickname(for: profile),
                serverID: profile.id
            )
            if isOwnMessage,
               isDuplicateSelfTargetedDelivery(
                serverID: profile.id,
                target: target,
                wireText: text,
                presentation: incomingEchoPresentation(forPrivmsgText: text),
                tags: wire.tags
            ) {
                return
            }
            if isOwnMessage,
               reconcileOutgoingEcho(
                serverID: profile.id,
                target: target,
                wireText: text,
                tags: wire.tags,
                timestamp: incomingMessageTimestamp,
                maximumEchoBytes: relayedMessageByteLimit(
                    target: target,
                    sourcePrefix: wire.prefix,
                    profile: profile
                )
               ) {
                return
            }
            if isOwnMessage, suppressesOnConnectResponse(wire, serverID: profile.id) { return }
            guard !isIgnored(sender, on: profile) else { return }
            if handleCTCP(
                text,
                from: sender,
                target: target,
                profile: profile,
                canReplyToRequest: true,
                tags: wire.tags
            ) { return }
            if let channelTarget = features(for: profile.id).channelName(fromMessageTarget: target) {
                let channel = channel(named: channelTarget, serverID: profile.id)
                append(
                    IRCMessage(
                        sender: sender,
                        text: text,
                        ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                    ),
                    for: .channel(channel.id),
                    markUnread: !isOwnMessage,
                    markMention: !isOwnMessage && messageMentionsLocalNickname(text, on: profile)
                )
            } else {
                let peer = isOwnMessage ? target : sender
                let conversation = directMessage(named: peer, serverID: profile.id)
                append(
                    IRCMessage(
                        sender: sender,
                        text: text,
                        ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                    ),
                    for: .directMessage(conversation.id),
                    markUnread: !isOwnMessage,
                    notifyDirectMessage: !isOwnMessage
                )
            }
        case "FAIL", "WARN", "NOTE":
            guard let reply = IRCStandardReply(wire: wire) else { return }
            let label = wire.tags["label"] ?? nil
            let suppressTranscript = suppressesOnConnectResponse(wire, serverID: profile.id)
            let destination = labeledResponseDestination(for: wire, profile: profile)
                ?? .server(profile.id)
            if let label {
                switch reply.kind {
                case .failure:
                    _ = reconcileOutgoingRejection(serverID: profile.id, label: label)
                case .warning, .note:
                    if !isInsideTrackedLabeledResponseBatch(wire, serverID: profile.id) {
                        _ = reconcileOutgoingAcknowledgement(serverID: profile.id, label: label)
                    }
                }
            }
            append(
                IRCMessage(
                    sender: "System",
                    text: suppressTranscript ? "An on-connect command received \(wire.command)." : reply.displayText,
                    isSystem: true,
                    ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
                ),
                for: destination
            )
        case "INVITE":
            guard let invite = IRCIncomingInvite(
                wire: wire,
                localNickname: nickname(for: profile),
                caseMapping: features(for: profile.id).caseMapping,
                channelTypes: features(for: profile.id).channelTypes
            ), !isIgnored(invite.inviter, on: profile) else { return }

            append(
                IRCMessage(
                    sender: invite.inviter,
                    text: "invited you to join \(invite.channel).",
                    channelLinks: [invite.channel]
                ),
                for: .server(profile.id)
            )
            if selection != .server(profile.id) {
                unreadInviteCountsByServer[profile.id, default: 0] += 1
            }
        case "JOIN":
            let channelName = wire.parameters.first ?? wire.trailing ?? ""
            if isChannelName(channelName, serverID: profile.id) {
                let channel = channel(named: channelName, serverID: profile.id)
                let member = IRCMemberParser.member(
                    from: wire.prefix ?? sender,
                    membership: features(for: profile.id).membership
                )
                addMember(member, to: channel.id)
                if identifiersEqual(sender, nickname(for: profile), serverID: profile.id) {
                    conversationStore.channel(channel.id)?.joinedAt = ContinuousClock().now
                    let pendingJoin = sessions[profile.id, default: .init()].requests.joins.removeValue(forKey: joinKey(serverID: profile.id, channel: channelName))
                    if let pendingJoin {
                        conversationStore.removeMessage(matchingID: pendingJoin.statusMessageID, from: .channel(channel.id))
                        let confirmedSelection = IRCJoinSelectionPolicy.selectionAfterSuccessfulJoin(
                            currentSelection: selection,
                            requestDestination: pendingJoin.destination,
                            joinedChannelID: channel.id,
                            selectsConversation: pendingJoin.selectsConversationOnSuccess
                        )
                        if selection != confirmedSelection {
                            selection = confirmedSelection
                        }
                    }
                    let topic = pendingJoin?.topic.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let topicSuffix = topic.isEmpty ? "" : " Topic: \(topic)"
                    appendChannelEvent("Joined \(channelName).\(topicSuffix)", kind: .join, channelID: channel.id)
                    if let sessionID = sessions[profile.id]?.id {
                        for name in [channelName] + (pendingJoin?.redirectedFromChannels ?? []) {
                            completeAutomaticJoinAttempt(name, for: profile, sessionID: sessionID)
                        }
                    }
                } else {
                    appendChannelEvent("\(sender) joined \(channelName).", kind: .join, channelID: channel.id)
                }
            }
        case "PART":
            guard let channelName = wire.parameters.first,
                  let channel = existingChannel(named: channelName, serverID: profile.id) else { return }
            let memberCountBeforePart = conversationStore.channel(channel.id)?.members.count ?? 0
            let isOwnPart = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
            if isOwnPart { conversationStore.channel(channel.id)?.joinedAt = nil }
            let removedMember = removeMember(named: sender, from: channel.id)
            guard removedMember || isOwnPart else { return }
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
            if let pendingKill = sessions[profile.id, default: .init()].requests.kills.removeValue(forKey: pendingKillKey) {
                appendSystem("Disconnected \(pendingKill.nickname) from the network\(reason).", for: pendingKill.destination)
            }
            for channel in channels(for: profile) {
                let memberCountBeforeQuit = conversationStore.channel(channel.id)?.members.count ?? 0
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
            let pendingKick = sessions[profile.id, default: .init()].requests.kicks.removeValue(forKey: kickKey(serverID: profile.id, channel: channel.name, nickname: target))
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
            if let pendingKill = sessions[profile.id, default: .init()].requests.kills.removeValue(forKey: key) {
                let reason = wire.trailing.map { " — \($0)" } ?? ""
                appendSystem("Disconnected \(pendingKill.nickname) from the network\(reason).", for: pendingKill.destination)
            }
        case "NICK":
            guard let newNickname = wire.trailing ?? wire.parameters.first, !newNickname.isEmpty else { return }
            let isLocalNicknameChange = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
            let requestedDestination = isLocalNicknameChange ? sessions[profile.id, default: .init()].requests.takeNick() : nil
            if isLocalNicknameChange {
                sessions[profile.id, default: .init()].nickname = newNickname
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
                  let topic = wire.parameter(at: 1) else { return }
            let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTopic.isEmpty {
                conversationStore.channel(channel.id)?.topic = nil
            } else {
                conversationStore.channel(channel.id)?.topic = trimmedTopic
            }
            let key = topicKey(serverID: profile.id, channel: channelName)
            let destination = sessions[profile.id, default: .init()].requests.topics.removeValue(forKey: key)
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
            let destination = sessions[profile.id, default: .init()].requests.modes.removeValue(forKey: key)
            if let channel = existingChannel(named: target, serverID: profile.id) {
                applyMembershipModes(modeString, arguments: modeArguments, to: channel.id)
                applyBanModes(modeString, arguments: modeArguments, to: channel)
                if identifiersEqual(sender, nickname(for: profile), serverID: profile.id) {
                    kickMembersMatchingConfirmedBans(
                        modeString,
                        arguments: modeArguments,
                        from: channel,
                        profile: profile
                    )
                }
                appendChannelEvent("\(sender) set mode \(changes) on \(target).", kind: .mode, channelID: channel.id)
                if let destination, destination != .channel(channel.id) {
                    appendSystem("Modes for \(target) changed: \(changes)", for: destination)
                }
            } else {
                appendSystem("Modes for \(target) changed: \(changes)", for: destination ?? .server(profile.id))
            }
        case "CHGHOST":
            guard wire.parameters.count >= 2 else { return }
            updateMemberIdentity(
                named: sender,
                username: wire.parameters[0],
                hostname: wire.parameters[1],
                serverID: profile.id
            )
        case "353":
            guard let channelName = wire.parameter(at: 2), let names = wire.parameter(at: 3) else { return }
            guard let channel = existingChannel(named: channelName, serverID: profile.id),
                  isJoinedChannel(named: channelName, on: profile.id) else {
                appendSystem("Names in \(channelName): \(names)", for: .server(profile.id))
                return
            }
            let membership = features(for: profile.id).membership
            let members = names.split(separator: " ").map {
                IRCMemberParser.member(from: String($0), membership: membership)
            }
            stageMembers(members, for: channel.id)
        case "366":
            guard wire.parameters.count >= 2,
                  let channel = existingChannel(named: wire.parameters[1], serverID: profile.id) else { return }
            finishStagingMembers(for: channel.id)
        case "367":
            handleBanListEntry(wire, serverID: profile.id)
        case "368":
            handleBanListEnd(wire, serverID: profile.id)
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
            sessions[profile.id, default: .init()].terminalError = error
            connectionStatuses[profile.id] = .failed(error)

            sessions[profile.id]?.registeredAt = nil
            prepareChannelsForDisconnectedSession(for: profile.id)
            resetChannelListingRequest(for: profile.id)
            scheduleReconnect(for: profile, reason: .serverError)
        case "322":
            guard wire.parameters.count >= 3, let users = Int(wire.parameters[2]) else { return }
            let listing = ChannelListing(name: wire.parameters[1], userCount: users, topic: wire.trailing ?? "")
            queueChannelListing(listing, for: profile.id)
        case "323":
            channelDirectory.complete(profile.id)
        case "263", "416":
            if !handleChannelListError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "301", "311", "312", "313", "317", "318", "319", "330", "338", "378", "379", "671":
            handleWhoisReply(wire, serverID: profile.id)
        case "401":
            if !handleWhoisReply(wire, serverID: profile.id),
               !handleInviteError(wire, serverID: profile.id),
               !handleModerationError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "403", "473":
            if !handleJoinError(wire, serverID: profile.id),
               !handleInviteError(wire, serverID: profile.id),
               !handleModerationError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "470":
            if !handleJoinRedirect(wire, profile: profile) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "405", "471", "474", "475", "476", "477", "489":
            if !handleJoinError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "442", "443", "482":
            if !handleInviteError(wire, serverID: profile.id),
               !handleModerationError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "441", "472", "478", "481":
            if !handleModerationError(wire, serverID: profile.id) {
                appendUnhandledNumericError(wire, profile: profile)
            }
        case "437":
            if !handleJoinError(wire, serverID: profile.id) {
                if retryRegistrationWithFallbackNickname(after: wire, profile: profile) { return }
                let destination = sessions[profile.id, default: .init()].requests.takeNick() ?? .server(profile.id)
                appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
            }
        case "433", "436":
            if retryRegistrationWithFallbackNickname(after: wire, profile: profile) { return }
            let destination = sessions[profile.id, default: .init()].requests.takeNick() ?? .server(profile.id)
            appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
        case "431", "432":
            let destination = sessions[profile.id, default: .init()].requests.takeNick() ?? .server(profile.id)
            appendSystem("Nickname change failed: \(wire.trailing ?? "The server rejected that nickname.")", for: destination)
        case "421", "461":
            if handleChannelListError(wire, serverID: profile.id) { return }
            guard wire.parameter(at: 1)?.uppercased() == "VERSION",
                  let destination = sessions[profile.id, default: .init()].requests.takeVersion()?.destination else {
                appendUnhandledNumericError(wire, profile: profile)
                return
            }

            appendSystem("Server version request failed: \(wire.trailing ?? "The server rejected the request.")", for: destination)
        default:
            if IRCNumericReply.isError(wire.command) { appendUnhandledNumericError(wire, profile: profile) }
        }
    }

    private func appendUnhandledNumericError(_ wire: IRCWireMessage, profile: ServerProfile) {
        var destination = SidebarItem.server(profile.id)
        let target = wire.parameter(at: 1)
        var suppressTranscript = false
        // These replies identify a rejected message's recipient. Without a label,
        // only reconcile a single candidate; never remove an arbitrary earlier message.
        if ["401", "404", "407", "408", "486", "531", "716"].contains(wire.command), let target {
            if let channel = existingChannel(named: target, serverID: profile.id) {
                destination = .channel(channel.id)
            } else if let directMessage = directMessages.first(where: {
                $0.serverID == profile.id && identifiersEqual($0.name, target, serverID: profile.id)
            }) {
                destination = .directMessage(directMessage.id)
            }
            pruneOutgoingEchoes(for: profile.id)
            if var pending = sessions[profile.id, default: .init()].requests.outgoingEchoes {
                let candidates = pending.indices.filter {
                    pending[$0].label == nil && !pending[$0].state.hasReceivedServerConfirmation
                        && identifiersEqual(pending[$0].target, target, serverID: profile.id)
                }
                suppressTranscript = candidates.contains { pending[$0].suppressTranscript }
                if candidates.count == 1, let index = candidates.first,
                   let transition = pending[index].state.receiveRejection() {
                    let rejected = pending[index]
                    destination = rejected.destination
                    if transition.isComplete { pending.remove(at: index) }
                    sessions[profile.id, default: .init()].requests.outgoingEchoes = pending
                    applyOutgoingEchoTransition(transition, pending: rejected)
                }
            }
        }
        let detail = wire.trailing ?? wire.parameter(at: wire.parameters.count - 1) ?? "The server rejected the request."
        let text = suppressTranscript
            ? "An on-connect command was rejected (\(wire.command))."
            : "\(wire.command): \(detail)"
        appendSystem(text, for: destination)
    }

    private func labeledResponseDestination(
        for wire: IRCWireMessage,
        profile: ServerProfile
    ) -> SidebarItem? {
        if let batchID = wire.tags["batch"] ?? nil,
           let destination = sessions[profile.id, default: .init()].requests.batches?[batchID]?.destination {
            return destination
        }
        let label = wire.tags["label"] ?? nil
        guard let label,
              let pending = sessions[profile.id, default: .init()].requests.outgoingEchoes?.first(where: {
                  $0.label == label
              }) else { return nil }
        return pending.destination
    }

    private func suppressesOnConnectResponse(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        if let batchID = wire.tags["batch"] ?? nil,
           sessions[serverID, default: .init()].requests.batches?[batchID]?.suppressTranscript == true {
            return true
        }
        if let label = wire.tags["label"] ?? nil {
            return sessions[serverID, default: .init()].requests.outgoingEchoes?.contains {
                $0.label == label && $0.suppressTranscript
            } == true
        }
        // Standard replies may be sent without labeled-response. Their command
        // and optional recipient context can still identify a private setup reply.
        guard let reply = IRCStandardReply(wire: wire),
              reply.command == "PRIVMSG" || reply.command == "NOTICE" else { return false }
        return sessions[serverID, default: .init()].requests.outgoingEchoes?.contains { pending in
            guard pending.suppressTranscript, pending.label == nil else { return false }
            let command: String
            if case .notice = pending.state.presentation { command = "NOTICE" }
            else { command = "PRIVMSG" }
            return reply.command == command && (reply.context.isEmpty || reply.context.contains {
                identifiersEqual($0, pending.target, serverID: serverID)
            })
        } == true
    }

    @discardableResult
    private func handleLabeledOutgoingError(
        _ wire: IRCWireMessage,
        profile: ServerProfile
    ) -> Bool {
        guard IRCNumericReply.isError(wire.command),
              let label = wire.tags["label"] ?? nil else { return false }
        guard let destination = labeledResponseDestination(for: wire, profile: profile) else {
            return false
        }

        let suppressTranscript = suppressesOnConnectResponse(wire, serverID: profile.id)
        _ = reconcileOutgoingRejection(serverID: profile.id, label: label)
        append(
            IRCMessage(
                sender: "System",
                text: suppressTranscript
                    ? "An on-connect command was rejected (\(wire.command))."
                    : "\(wire.command): \(wire.trailing ?? "The server rejected the message.")",
                isSystem: true,
                ircv3Tags: IRCMessageTag.canonicalizing(wire.tags)
            ),
            for: destination
        )
        return true
    }

    private func isInsideTrackedLabeledResponseBatch(
        _ wire: IRCWireMessage,
        serverID: UUID
    ) -> Bool {
        guard let batchID = wire.tags["batch"] ?? nil else { return false }
        return sessions[serverID, default: .init()].requests.batches?[batchID]?.label != nil
    }

    private func updateIncomingBatchState(
        from wire: IRCWireMessage,
        serverID: UUID,
        hasExplicitLabel: Bool
    ) {
        guard let token = wire.parameters.first, token.count > 1 else { return }
        let id = String(token.dropFirst())
        switch token.first {
        case "+":
            guard sessions[serverID, default: .init()].requests.batches?[id] == nil else { return }
            let existingCount = sessions[serverID, default: .init()].requests.batches?.count ?? 0
            guard existingCount < maximumTrackedIncomingBatchesPerServer else {
                return
            }
            let label = wire.tags["label"] ?? nil
            let parentID = wire.tags["batch"] ?? nil
            if let parentID,
               sessions[serverID, default: .init()].requests.batches?[parentID] == nil {
                return
            }
            let inheritedDestination = parentID.flatMap {
                sessions[serverID, default: .init()].requests.batches?[$0]?.destination
            }
            let labeledDestination = label.flatMap {
                pendingOutgoingDestination(serverID: serverID, label: $0)
            }
            let destination: SidebarItem?
            let suppressTranscript: Bool
            let labeledSuppression = label.map { label in
                sessions[serverID, default: .init()].requests.outgoingEchoes?.contains { $0.label == label && $0.suppressTranscript } == true
            } ?? false
            if hasExplicitLabel {
                destination = labeledDestination
                suppressTranscript = labeledSuppression
            } else {
                destination = inheritedDestination ?? labeledDestination
                suppressTranscript = labeledSuppression || parentID.flatMap {
                    sessions[serverID, default: .init()].requests.batches?[$0]?.suppressTranscript
                } == true
            }
            sessions[serverID, default: .init()].requests.insertBatch(id: id, batch: IRCIncomingBatch(
                label: label,
                destination: destination,
                suppressTranscript: suppressTranscript,
                completesLabeledResponse: hasExplicitLabel && label != nil,
                parentID: parentID
            ))
        case "-":
            guard let completedBatch = sessions[serverID, default: .init()].requests.batches?[id],
                  completedBatch.parentID == (wire.tags["batch"] ?? nil),
                  sessions[serverID, default: .init()].requests.batches?.values.contains(where: {
                      $0.parentID == id
                  }) != true else {
                return
            }
            sessions[serverID, default: .init()].requests.batches?.removeValue(forKey: id)
            if sessions[serverID, default: .init()].requests.batches?.isEmpty == true {
                sessions[serverID, default: .init()].requests.takeBatches()
            }
            if completedBatch.completesLabeledResponse,
               let label = completedBatch.label {
                _ = reconcileOutgoingAcknowledgement(serverID: serverID, label: label)
            }
        default:
            break
        }
    }

    private func pendingOutgoingDestination(
        serverID: UUID,
        label: String
    ) -> SidebarItem? {
        sessions[serverID, default: .init()].requests.outgoingEchoes?.first(where: { $0.label == label })?.destination
    }

    private func handleJoinRedirect(_ wire: IRCWireMessage, profile: ServerProfile) -> Bool {
        let serverID = profile.id
        // 470 <nick> <requested channel> <destination channel> :reason
        guard wire.parameters.count >= 3,
              let sourceName = wire.parameter(at: 1),
              let targetName = wire.parameter(at: 2),
              isChannelName(sourceName, serverID: serverID),
              isChannelName(targetName, serverID: serverID),
              !identifiersEqual(sourceName, targetName, serverID: serverID),
              var pending = sessions[serverID, default: .init()].requests.joins[joinKey(serverID: serverID, channel: sourceName)],
              let source = channels.first(where: { $0.id == pending.channelID }),
              conversationStore.channel(source.id)?.joinedAt == nil else { return false }

        let shouldSelect = selection == .channel(source.id)
            || (pending.selectsConversationOnSuccess && selection == pending.destination)
        let targetKey = joinKey(serverID: serverID, channel: targetName)
        let existingTarget = existingChannel(named: targetName, serverID: serverID)
        let target = existingTarget ?? channel(named: targetName, serverID: serverID)
        let targetPending = sessions[serverID, default: .init()].requests.joins[targetKey]
        let redirectMessage = "Redirected from \(sourceName) to \(targetName)."

        sessions[serverID, default: .init()].requests.joins.removeValue(forKey: joinKey(serverID: serverID, channel: sourceName))
        conversationStore.removeMessage(matchingID: pending.statusMessageID, from: .channel(source.id))
        if pending.preservesConversationOnFailure {
            // A rejoin can be forwarded too; keep the original transcript in its own channel.
            appendSystem(redirectMessage, for: .channel(source.id))
        } else {
            removeChannelConversation(source)
        }
        if shouldSelect { selection = .channel(target.id) }
        appendSystem(redirectMessage, for: .channel(target.id))

        pending.redirectedFromChannels += [pending.channel] + (targetPending?.redirectedFromChannels ?? [])
        pending.channel = targetName
        pending.channelID = target.id
        pending.topic = targetPending?.topic ?? "" // Only retain the destination's listed topic.
        pending.preservesConversationOnFailure = targetPending?.preservesConversationOnFailure ?? (existingTarget != nil)
        if let targetPending {
            conversationStore.removeMessage(matchingID: targetPending.statusMessageID, from: .channel(target.id))
            if !shouldSelect {
                pending.destination = targetPending.destination
                pending.selectsConversationOnSuccess = targetPending.selectsConversationOnSuccess
            }
        }
        if pending.destination == .channel(source.id) && !channels.contains(where: { $0.id == source.id }) {
            pending.destination = .server(serverID)
        }
        if conversationStore.channel(target.id)?.joinedAt != nil {
            sessions[serverID, default: .init()].requests.joins.removeValue(forKey: targetKey)
            if let sessionID = sessions[serverID]?.id {
                for name in [targetName] + pending.redirectedFromChannels {
                    completeAutomaticJoinAttempt(name, for: profile, sessionID: sessionID)
                }
            }
        } else {
            let joining = IRCMessage(sender: "System", text: "Joining \(targetName)…", isSystem: true)
            pending.statusMessageID = joining.id
            sessions[serverID, default: .init()].requests.joins[targetKey] = pending
            append(joining, for: .channel(target.id))
            // The server performs the forwarded JOIN; only wait for its confirmation.
            scheduleJoinTimeout(statusMessageID: joining.id, serverID: serverID)
        }
        return true
    }

    @discardableResult
    private func handleJoinError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        let responseParameters = wire.parameters.dropFirst()
        guard let pendingJoin = sessions[serverID, default: .init()].requests.joins.values.first(where: { pendingJoin in
            pendingJoin.serverID == serverID && responseParameters.contains {
                identifiersEqual($0, pendingJoin.channel, serverID: serverID)
            }
        }) else { return false }
        failPendingJoin(pendingJoin, reason: wire.trailing ?? "The server rejected the join request.")
        return true
    }

    private func failPendingJoin(_ pendingJoin: PendingJoin, reason: String) {
        let serverID = pendingJoin.serverID
        sessions[serverID, default: .init()].requests.joins.removeValue(forKey: joinKey(serverID: serverID, channel: pendingJoin.channel))
        if let profile = profiles.first(where: { $0.id == serverID }),
           let sessionID = sessions[serverID]?.id {
            for name in [pendingJoin.channel] + pendingJoin.redirectedFromChannels {
                completeAutomaticJoinAttempt(name, for: profile, sessionID: sessionID)
            }
        }
        if let channel = channels.first(where: { $0.id == pendingJoin.channelID }) {
            if pendingJoin.preservesConversationOnFailure {
                conversationStore.removeMessage(matchingID: pendingJoin.statusMessageID, from: .channel(channel.id))
                appendChannelEvent("Could not rejoin \(pendingJoin.channel): \(reason)", channelID: channel.id)
                return
            } else {
                removeChannelConversation(channel)
            }
        }
        let destination: SidebarItem = pendingJoin.destination == .channel(pendingJoin.channelID)
            ? .server(serverID)
            : pendingJoin.destination
        appendSystem("Could not join \(pendingJoin.channel): \(reason)", for: destination)
    }

    private func retryRegistrationWithFallbackNickname(after wire: IRCWireMessage, profile: ServerProfile) -> Bool {
        guard sessions[profile.id]?.registeredAt == nil,
              sessions[profile.id, default: .init()].requests.nick == nil,
              connections[profile.id] != nil else { return false }

        let attemptedSuffixes = sessions[profile.id, default: .init()].attemptedNicknameSuffixes
        let availableSuffixes = Array(0...99).filter { !attemptedSuffixes.contains($0) }
        guard let suffix = availableSuffixes.randomElement() else { return false }

        sessions[profile.id, default: .init()].attemptedNicknameSuffixes.insert(suffix)
        let fallbackNickname = configuredNickname(for: profile) + String(format: "%02d", suffix)
        sessions[profile.id, default: .init()].nickname = fallbackNickname
        appendSystem("\(wire.trailing ?? "Nickname is unavailable.") Retrying as \(fallbackNickname)…", for: .server(profile.id))
        connections[profile.id]?.send(command: "NICK \(fallbackNickname)")
        return true
    }

    @discardableResult
    private func handleWhoisReply(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        guard wire.parameters.count >= 2 else { return false }
        let target = wire.parameters[1]
        let key = whoisKey(serverID: serverID, target: target)
        guard let destination = sessions[serverID, default: .init()].requests.whois[key] else { return false }
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
            let serverFeatures = features(for: serverID)
            channelLinks = IRCWhoisChannelParser.channels(
                from: channels,
                membership: serverFeatures.membership,
                channelTypes: serverFeatures.channelTypes
            )
            message = "\(target) is on: \(channels)"
        case "330": message = "\(target) is logged in as \(wire.parameters.count > 2 ? wire.parameters[2] : "an account")."
        case "671": message = "\(target) is using a secure connection."
        case "318":
            message = "End of /WHOIS for \(target)."
            sessions[serverID, default: .init()].requests.whois.removeValue(forKey: key)
        case "401":
            message = wire.trailing ?? "No such nick: \(target)."
            sessions[serverID, default: .init()].requests.whois.removeValue(forKey: key)
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
        guard let invitation = sessions[serverID, default: .init()].requests.invites.removeValue(forKey: key) else { return }
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
        guard let (key, invitation) = sessions[serverID, default: .init()].requests.invites.first(where: { _, invitation in
            guard invitation.serverID == serverID else { return false }
            if let nickname, identifiersEqual(invitation.nickname, nickname, serverID: serverID) { return true }
            if let channel, identifiersEqual(invitation.channel, channel, serverID: serverID) { return true }
            return false
        }) else { return false }
        sessions[serverID, default: .init()].requests.invites.removeValue(forKey: key)
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
        case "403", "442", "478", "482": wire.parameters.count > 1 ? wire.parameters[1] : nil
        case "441": wire.parameters.count > 2 ? wire.parameters[2] : nil
        default: nil
        }

        if let (key, kick) = sessions[serverID, default: .init()].requests.kicks.first(where: { _, kick in
            guard kick.serverID == serverID else { return false }
            if let nickname, !identifiersEqual(kick.nickname, nickname, serverID: serverID) { return false }
            if let channel, !identifiersEqual(kick.channel, channel, serverID: serverID) { return false }
            return nickname != nil || channel != nil
        }) {
            sessions[serverID, default: .init()].requests.kicks.removeValue(forKey: key)
            appendSystem("Kick failed: \(wire.trailing ?? "The server rejected the kick.")", for: kick.destination)
            return true
        }

        if let channel {
            let key = modeKey(serverID: serverID, target: channel)
            if failAwaitingMaskBan(
                forKey: key,
                serverID: serverID,
                message: wire.trailing ?? "The server rejected the ban."
            ) {
                return true
            }
            if let destination = sessions[serverID, default: .init()].requests.modes.removeValue(forKey: key) {
                appendSystem("Mode change failed: \(wire.trailing ?? "The server rejected the mode change.")", for: destination)
                return true
            }
        }

        if IRCBanListRequestErrorPolicy.isListRequestFailure(wire.command),
           let channel,
           let conversation = existingChannel(named: channel, serverID: serverID),
           let state = conversationStore.channel(conversation.id), state.isRequestingBans {
            state.failBanRequest(wire.trailing ?? "The server rejected the ban-list request.")
            return true
        }

        if wire.command == "472",
           let key = sessions[serverID, default: .init()].requests.maskBans.first(where: { _, bans in
               bans.contains(where: {
                   $0.serverID == serverID && $0.state == .awaitingModeConfirmation
               })
           })?.key {
            if failAwaitingMaskBan(
                forKey: key,
                serverID: serverID,
                message: wire.trailing ?? "The server does not support that mode."
            ) {
                return true
            }
        }

        if wire.command == "472",
           let (key, destination) = sessions[serverID, default: .init()].requests.modes.first(where: { _, destination in
               profile(for: destination)?.id == serverID
           }) {
            sessions[serverID, default: .init()].requests.modes.removeValue(forKey: key)
            appendSystem(
                "Mode change failed: \(wire.trailing ?? "The server does not support that mode.")",
                for: destination
            )
            return true
        }

        if let nickname,
           let (key, kill) = sessions[serverID, default: .init()].requests.kills.first(where: { _, kill in
               kill.serverID == serverID && identifiersEqual(kill.nickname, nickname, serverID: serverID)
           }) {
            sessions[serverID, default: .init()].requests.kills.removeValue(forKey: key)
            appendSystem("Kill failed: \(wire.trailing ?? "The server rejected the kill.")", for: kill.destination)
            return true
        }
        if wire.command == "481", let (key, kill) = sessions[serverID, default: .init()].requests.kills.first(where: { _, kill in
            kill.serverID == serverID
        }) {
            sessions[serverID, default: .init()].requests.kills.removeValue(forKey: key)
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
        guard let destination = sessions[serverID, default: .init()].requests.modes.removeValue(forKey: key) else { return }
        let suffix = arguments.isEmpty ? "" : " \(arguments)"
        appendSystem("Modes for \(target): \(modes)\(suffix)", for: destination)
    }

    private func handleBanListEntry(_ wire: IRCWireMessage, serverID: UUID) {
        guard var entry = IRCBanListParser.entry(from: wire),
              let channel = existingChannel(named: entry.channel, serverID: serverID) else { return }
        entry.channel = channel.name
        conversationStore.channel(channel.id)?.receiveBan(entry)
    }

    private func handleBanListEnd(_ wire: IRCWireMessage, serverID: UUID) {
        guard let channelName = IRCBanListParser.endChannel(from: wire),
              let channel = existingChannel(named: channelName, serverID: serverID) else { return }
        conversationStore.channel(channel.id)?.finishBanList()
    }

    private func handleWhoReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard wire.parameters.count >= 2 else { return }
        if wire.command == "352" {
            if wire.parameters.count > 5 {
                updateMemberIdentity(
                    named: wire.parameters[5],
                    username: wire.parameters[2],
                    hostname: wire.parameters[3],
                    serverID: serverID
                )
            }
            let responseTargets = [wire.parameters[1]] + (wire.parameters.count > 5 ? [wire.parameters[5]] : [])
            guard let key = responseTargets
                .map({ whoKey(serverID: serverID, target: $0) })
                .first(where: { sessions[serverID, default: .init()].requests.who[$0] != nil }),
                  let destination = sessions[serverID, default: .init()].requests.who[key] else { return }
            let user = wire.parameters.count > 2 ? wire.parameters[2] : "?"
            let host = wire.parameters.count > 3 ? wire.parameters[3] : "?"
            let nickname = wire.parameters.count > 5 ? wire.parameters[5] : "?"
            appendSystem("\(nickname) — \(user)@\(host)\(wire.trailing.map { " — \($0)" } ?? "")", for: destination)
        } else {
            let target = wire.parameters[1]
            completeMaskBanIdentityLookup(channelName: target, serverID: serverID)
            let key = whoKey(serverID: serverID, target: target)
            guard let destination = sessions[serverID, default: .init()].requests.who[key] else { return }
            sessions[serverID, default: .init()].requests.who.removeValue(forKey: key)
            appendSystem("End of /WHO for \(target).", for: destination)
        }
    }

    private func handleMOTDReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard let destination = sessions[serverID, default: .init()].requests.motd else { return }
        switch wire.command {
        case "375":
            appendSystem(wire.trailing ?? "Message of the day:", for: destination)
        case "372":
            appendSystem(wire.trailing ?? "", for: destination)
        case "376":
            sessions[serverID, default: .init()].requests.takeMotd()
        case "422":
            sessions[serverID, default: .init()].requests.takeMotd()
            appendSystem(wire.trailing ?? "This server has no message of the day.", for: destination)
        default:
            break
        }
    }

    private func requestMOTD(
        from profile: ServerProfile,
        target: String = "",
        deliveringTo destination: SidebarItem,
        announcesRequest: Bool
    ) {
        sessions[profile.id, default: .init()].requests.motd = destination
        connections[profile.id]?.send(command: target.isEmpty ? "MOTD" : "MOTD \(target)")
        if announcesRequest {
            appendSystem("Requesting the message of the day…", for: destination)
        }
    }

    private func handleTopicReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard wire.parameters.count >= 2 else { return }
        let channelName = wire.parameters[1]
        let key = topicKey(serverID: serverID, channel: channelName)
        switch wire.command {
        case "331":
            if let channel = existingChannel(named: channelName, serverID: serverID) {
                conversationStore.channel(channel.id)?.topic = nil
            }
            if let destination = sessions[serverID, default: .init()].requests.topics.removeValue(forKey: key) {
                appendSystem("\(channelName) has no topic.", for: destination)
            }
        case "332":
            let topic = (wire.trailing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let channel = existingChannel(named: channelName, serverID: serverID) {
                if topic.isEmpty {
                    conversationStore.channel(channel.id)?.topic = nil
                } else {
                    conversationStore.channel(channel.id)?.topic = topic
                }
            }
            if let destination = sessions[serverID, default: .init()].requests.topics.removeValue(forKey: key) {
                appendSystem("Topic for \(channelName): \(topic)", for: destination)
            }
        default:
            break
        }
    }

    private func handleVersionReply(_ wire: IRCWireMessage, serverID: UUID) {
        guard let destination = sessions[serverID, default: .init()].requests.takeVersion()?.destination else { return }

        let version = wire.parameters.count > 1 ? wire.parameters[1] : "Unknown"
        let server = wire.parameters.count > 2 ? wire.parameters[2] : "the server"
        let details = wire.trailing.map { " — \($0)" } ?? ""
        appendSystem("\(server) is running \(version)\(details)", for: destination)
    }

    private func requestServerVersion(for profile: ServerProfile, from item: SidebarItem) {
        let requestID = UUID()
        sessions[profile.id, default: .init()].requests.version = PendingReplyRequest(requestID: requestID, destination: item)
        connections[profile.id]?.send(command: "VERSION")
        appendSystem("Requesting server version…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.sessions[profile.id, default: .init()].requests.version?.requestID == requestID,
                  let destination = self.sessions[profile.id, default: .init()].requests.takeVersion()?.destination else { return }

            self.appendSystem("The server did not return a version reply.", for: destination)
        }
    }

    private func requestClientVersion(of nickname: String, on profile: ServerProfile, from item: SidebarItem) {
        let target = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let key = ctcpRequestKey(serverID: profile.id, nickname: target)
        let requestID = UUID()
        sessions[profile.id, default: .init()].requests.clientVersions[key] = PendingReplyRequest(requestID: requestID, destination: item)
        connections[profile.id]?.send(command: "PRIVMSG \(target) :\u{01}VERSION\u{01}")
        appendSystem("Requesting \(target)'s client version…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.sessions[profile.id, default: .init()].requests.clientVersions[key]?.requestID == requestID,
                  let destination = self.sessions[profile.id, default: .init()].requests.clientVersions.removeValue(forKey: key)?.destination else { return }

            self.appendSystem("\(target) did not return a client version reply.", for: destination)
        }
    }

    private func requestUserPing(of nickname: String, on profile: ServerProfile, from item: SidebarItem) {
        let target = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let key = ctcpRequestKey(serverID: profile.id, nickname: target)
        let token = UUID().uuidString
        sessions[profile.id, default: .init()].requests.userPings[key] = PendingUserPing(
            token: token,
            sentAt: Date(),
            destination: item
        )
        connections[profile.id]?.send(
            command: "PRIVMSG \(target) :\(IRCCTCPPing.payload(token: token))"
        )
        appendSystem("Pinging \(target)…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.sessions[profile.id, default: .init()].requests.userPings[key]?.token == token,
                  self.sessions[profile.id, default: .init()].requests.userPings.removeValue(forKey: key) != nil else { return }
            self.appendSystem("\(target) did not return a ping reply.", for: item)
        }
    }

    private func requestSimpleCTCP(
        _ command: IRCCTCPCommand,
        of nickname: String,
        on profile: ServerProfile,
        from item: SidebarItem
    ) {
        precondition(command == .time || command == .clientInfo)
        let key = ctcpRequestKey(serverID: profile.id, nickname: nickname, command: command)
        let requestID = UUID()
        sessions[profile.id, default: .init()].requests.ctcp[key] = PendingReplyRequest(requestID: requestID, destination: item)
        connections[profile.id]?.send(
            command: "PRIVMSG \(nickname) :\u{01}\(command.rawValue)\u{01}"
        )
        appendSystem("Requesting \(nickname)'s CTCP \(command.label.lowercased())…", for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.sessions[profile.id, default: .init()].requests.ctcp[key]?.requestID == requestID,
                  self.sessions[profile.id, default: .init()].requests.ctcp.removeValue(forKey: key) != nil else { return }
            self.appendSystem(
                "\(nickname) did not return a CTCP \(command.label.lowercased()) reply.",
                for: item
            )
        }
    }

    @discardableResult
    private func handleCTCP(
        _ text: String,
        from sender: String,
        target: String,
        profile: ServerProfile,
        canReplyToRequest: Bool,
        tags: [String: String?] = [:]
    ) -> Bool {
        guard text.first == "\u{01}", text.last == "\u{01}" else { return false }
        let payload = String(text.dropFirst().dropLast())
        let command = payload.split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = command.first?.uppercased() else { return false }

        let isSelfEcho = IRCCTCPEchoPolicy.isSelfEcho(
            sender: sender,
            target: target,
            localNickname: nickname(for: profile),
            caseMapping: features(for: profile.id).caseMapping,
            canReplyToRequest: canReplyToRequest
        )
        if isSelfEcho, name != "ACTION" {
            // IRCv3 echo-message reflects our outgoing PRIVMSG back with our
            // own nickname. It is not a CTCP request from the target user.
            return true
        }

        switch name {
        case "ACTION":
            guard canReplyToRequest, command.count > 1 else { return false }
            let message = IRCMessage(
                sender: "* \(sender)",
                text: command[1],
                nicknameColorKey: sender,
                ircv3Tags: IRCMessageTag.canonicalizing(tags)
            )
            if let channelTarget = features(for: profile.id).channelName(fromMessageTarget: target) {
                let channel = channel(named: channelTarget, serverID: profile.id)
                let isOwnAction = identifiersEqual(sender, nickname(for: profile), serverID: profile.id)
                append(
                    message,
                    for: .channel(channel.id),
                    markUnread: !isOwnAction,
                    markMention: !isOwnAction && messageMentionsLocalNickname(command[1], on: profile)
                )
            } else {
                let peer = isSelfEcho ? target : sender
                let conversation = directMessage(named: peer, serverID: profile.id)
                append(
                    message,
                    for: .directMessage(conversation.id),
                    markUnread: !isSelfEcho,
                    notifyDirectMessage: !isSelfEcho
                )
            }
        case "DCC":
            // DCC is fully dormant until the global opt-in is enabled. Still
            // consume its CTCP envelope so raw file-sharing control text does
            // not appear as a normal chat message while the feature is off.
            guard receivesDCCFiles else { return true }
            guard canReplyToRequest,
                  identifiersEqual(
                    target,
                    nickname(for: profile),
                    serverID: profile.id
                  ),
                  let request = IRCDCCSendParser.request(from: payload) else { return true }
            enqueueDCCFileOffer(IRCDCCFileOffer(
                serverID: profile.id,
                networkName: profile.name,
                sender: sender,
                request: request,
                routesThroughSSH: profile.useSSHTunnel == true
            ))
        case "VERSION":
            // A bare VERSION is a CTCP request. Reply privately with concise
            // client information; never send it back into a channel.
            if command.count == 1 {
                guard canReplyToCTCPRequest(
                    from: sender,
                    target: target,
                    profile: profile,
                    canReplyToRequest: canReplyToRequest
                ) else { return true }
                connections[profile.id]?.send(command: "NOTICE \(sender) :\u{01}VERSION \(IRCClientVersion.ctcpReply)\u{01}")
                appendSystem("\(sender) requested Netsplit's version.", for: .server(profile.id))
            } else {
                guard !canReplyToRequest,
                      isDirectCTCPTarget(target, profile: profile) else { return true }
                let version = command[1]
                let key = ctcpRequestKey(serverID: profile.id, nickname: sender)
                guard let destination = sessions[profile.id, default: .init()].requests.clientVersions
                    .removeValue(forKey: key)?.destination else { return true }
                appendSystem("Version reply from \(sender): \(version)", for: destination)
            }
        case "PING":
            guard command.count == 2, !command[1].isEmpty else { return true }
            let token = command[1]
            if canReplyToRequest {
                guard canReplyToCTCPRequest(
                    from: sender,
                    target: target,
                    profile: profile,
                    canReplyToRequest: canReplyToRequest
                ) else { return true }
                connections[profile.id]?.send(
                    command: "NOTICE \(sender) :\(IRCCTCPPing.payload(token: token))"
                )
                appendSystem("\(sender) pinged you.", for: .server(profile.id))
            } else {
                guard isDirectCTCPTarget(target, profile: profile) else { return true }
                let key = ctcpRequestKey(serverID: profile.id, nickname: sender)
                guard let pending = sessions[profile.id, default: .init()].requests.userPings[key], pending.token == token else { return true }
                sessions[profile.id, default: .init()].requests.userPings.removeValue(forKey: key)
                let milliseconds = IRCCTCPPing.roundTripMilliseconds(
                    sentAt: pending.sentAt,
                    receivedAt: Date()
                )
                appendSystem("Ping reply from \(sender): \(milliseconds) ms.", for: pending.destination)
            }
        case "TIME", "CLIENTINFO":
            guard let ctcpCommand = IRCCTCPCommand(rawValue: name) else { return false }
            if command.count == 1 {
                guard canReplyToCTCPRequest(
                    from: sender,
                    target: target,
                    profile: profile,
                    canReplyToRequest: canReplyToRequest
                ) else { return true }
                let reply: String
                switch ctcpCommand {
                case .time:
                    reply = Date().formatted(date: .complete, time: .complete)
                case .clientInfo:
                    reply = IRCCTCPCommand.supportedReply
                case .version, .ping:
                    return false
                }
                connections[profile.id]?.send(
                    command: "NOTICE \(sender) :\u{01}\(name) \(reply)\u{01}"
                )
                appendSystem("\(sender) requested Netsplit's CTCP \(ctcpCommand.label.lowercased()).", for: .server(profile.id))
            } else {
                guard !canReplyToRequest,
                      isDirectCTCPTarget(target, profile: profile) else { return true }
                let key = ctcpRequestKey(
                    serverID: profile.id,
                    nickname: sender,
                    command: ctcpCommand
                )
                guard let destination = sessions[profile.id, default: .init()].requests.ctcp.removeValue(forKey: key)?.destination
                else { return true }
                appendSystem(
                    "CTCP \(ctcpCommand.label) reply from \(sender): \(command[1])",
                    for: destination
                )
            }
        default:
            return false
        }
        return true
    }

    private func canReplyToCTCPRequest(
        from sender: String,
        target: String,
        profile: ServerProfile,
        canReplyToRequest: Bool
    ) -> Bool {
        let caseMapping = features(for: profile.id).caseMapping
        guard IRCCTCPRequestPolicy.isDirectRequest(
            target: target,
            localNickname: nickname(for: profile),
            caseMapping: caseMapping,
            canReplyToRequest: canReplyToRequest
        ) else { return false }
        return ctcpResponseRateLimiter.shouldAllow(
            serverID: profile.id,
            normalizedSender: caseMapping.normalize(sender)
        )
    }

    private func isDirectCTCPTarget(_ target: String, profile: ServerProfile) -> Bool {
        IRCCTCPRequestPolicy.isDirectTarget(
            target,
            localNickname: nickname(for: profile),
            caseMapping: features(for: profile.id).caseMapping
        )
    }

    private func ctcpRequestKey(serverID: UUID, nickname: String) -> String {
        normalizedIdentifier(nickname, serverID: serverID)
    }

    private func ctcpRequestKey(
        serverID: UUID,
        nickname: String,
        command: IRCCTCPCommand
    ) -> String {
        "\(ctcpRequestKey(serverID: serverID, nickname: nickname))|\(command.rawValue)"
    }

    private func recordSelectionChange(from previousSelection: SidebarItem?) {
        rememberConversationSelection(selection)
        guard !isNavigatingSelectionHistory, previousSelection != selection else { return }
        forwardSelectionHistory.removeAll()
        guard let previousSelection, isValidNavigationSelection(previousSelection) else { return }
        appendToBackHistory(previousSelection)
    }

    private func rememberConversationSelection(_ item: SidebarItem?) {
        guard let item, let profile = profile(for: item) else { return }
        switch item {
        case .channel, .directMessage:
            lastConversationSelectionByServerID[profile.id] = item
        case .connectionCenter, .server:
            break
        }
    }

    private func selectFromHistory(_ destination: SidebarItem) {
        selectWithoutRecordingHistory(destination)
        requestComposerFocus()
    }

    private func selectWithoutRecordingHistory(_ destination: SidebarItem) {
        isNavigatingSelectionHistory = true
        selection = destination
        isNavigatingSelectionHistory = false
    }

    private func removeNavigationHistory(for serverID: UUID) {
        backSelectionHistory.removeAll { profile(for: $0)?.id == serverID }
        forwardSelectionHistory.removeAll { profile(for: $0)?.id == serverID }
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

    private func conversation(for item: SidebarItem) -> Conversation? {
        switch item {
        case .channel(let id):
            return channels.first { $0.id == id }
        case .directMessage(let id):
            return directMessages.first { $0.id == id }
        case .connectionCenter, .server:
            return nil
        }
    }

    private func conversationID(for item: SidebarItem) -> UUID? {
        switch item {
        case .connectionCenter: return nil
        case .server(let id), .channel(let id), .directMessage(let id): return id
        }
    }

    private func channel(named name: String, serverID: UUID) -> Conversation {
        if let existing = channels.first(where: { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }) {
            resolvePendingMentionNotificationDestination()
            return existing
        }
        let conversation = Conversation(name: name, serverID: serverID)
        conversationStore.addChannel(conversation)
        resolvePendingMentionNotificationDestination()
        return conversation
    }

    @discardableResult
    private func resolvePendingMentionNotificationDestination() -> Bool {
        guard let destination = pendingMentionNotificationDestination,
              let channelID = IRCMentionNotificationPolicy.channelID(
                for: destination,
                in: channels,
                caseMapping: features(for: destination.serverID).caseMapping
              ) else { return false }
        pendingMentionNotificationDestination = nil
        selection = .channel(channelID)
        return true
    }

    private func existingChannel(named name: String, serverID: UUID) -> Conversation? {
        channels.first { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }
    }

    private func removeChannelConversation(_ channel: Conversation) {
        conversationStore.remove(.channel(channel.id))
        sessions[channel.serverID]?.requests.removeChannel(
            named: normalizedIdentifier(channel.name, serverID: channel.serverID)
        )
        if selection == .channel(channel.id) { selection = .server(channel.serverID) }
    }

    private func prepareChannelsForDisconnectedSession(for serverID: UUID) {
        resetPendingRequests(for: serverID)
        removePendingDCCFileOffers(for: serverID)
        conversationStore.disconnectChannels(on: serverID)
    }

    private func removeConversations(for serverID: UUID) {
        let wasShowingRemovedServer = selection.flatMap { profile(for: $0)?.id } == serverID
        removeNavigationHistory(for: serverID)
        conversationStore.removeServer(serverID)
        unreadInviteCountsByServer.removeValue(forKey: serverID)
        lastConversationSelectionByServerID.removeValue(forKey: serverID)
        if wasShowingRemovedServer { selection = .connectionCenter }
    }

    private func resetPendingRequests(for serverID: UUID) {
        ctcpResponseRateLimiter.remove(serverID: serverID)
        finalizePendingOutgoingEchoes(for: serverID)
        sessions[serverID]?.requests = IRCServerRequests()
    }

    private func resetChannelListingRequest(for serverID: UUID) {
        channelDirectory.reset(serverID)
    }

    @discardableResult
    private func handleChannelListError(_ wire: IRCWireMessage, serverID: UUID) -> Bool {
        guard channelDirectory.isRequesting(serverID),
              wire.parameters.dropFirst().contains(where: { $0.caseInsensitiveCompare("LIST") == .orderedSame }) else {
            return false
        }
        channelDirectory.fail(serverID)
        appendSystem("Channel list request failed: \(wire.trailing ?? "The server rejected the LIST request.")", for: .server(serverID))
        return true
    }

    private func isChannelName(_ value: String, serverID: UUID) -> Bool {
        features(for: serverID).isChannelName(value)
    }

    private func validateChannelName(
        _ channelName: String,
        serverID: UUID,
        reportingTo destination: SidebarItem
    ) -> Bool {
        let serverFeatures = features(for: serverID)
        guard serverFeatures.isChannelName(channelName) else {
            appendSystem("This server does not recognize \(channelName) as a channel name.", for: destination)
            return false
        }
        if let maximumLength = serverFeatures.maximumChannelLength,
           channelName.count > maximumLength {
            appendSystem(
                "This server limits channel names to \(maximumLength) characters.",
                for: destination
            )
            return false
        }
        return true
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
        guard isChannelName(channelName, serverID: serverID) else { return nil }
        return existingChannel(named: channelName, serverID: serverID)
    }

    private func directMessage(named name: String, serverID: UUID) -> Conversation {
        if let existing = directMessages.first(where: { $0.serverID == serverID && identifiersEqual($0.name, name, serverID: serverID) }) { return existing }
        let conversation = Conversation(name: name, serverID: serverID)
        conversationStore.addDirectMessage(conversation)
        return conversation
    }

    @discardableResult
    private func openDirectMessage(named nickname: String, serverID: UUID) -> Conversation {
        let conversation = directMessage(named: nickname, serverID: serverID)
        conversationStore.initializeMessages([IRCMessage(
            sender: "System", text: "Private conversation with \(nickname).", isSystem: true
        )], for: .directMessage(conversation.id))
        return conversation
    }

    private func renameDirectMessage(from oldNickname: String, to newNickname: String, serverID: UUID) {
        guard let oldConversation = directMessages.first(where: {
            $0.serverID == serverID && identifiersEqual($0.name, oldNickname, serverID: serverID)
        }) else { return }
        renameMutedConversation(from: oldNickname, to: newNickname, serverID: serverID)
        renameFavoriteDirectMessage(from: oldNickname, to: newNickname, serverID: serverID)
        if let destination = directMessages.first(where: {
            $0.id != oldConversation.id && $0.serverID == serverID
                && identifiersEqual($0.name, newNickname, serverID: serverID)
        }) {
            conversationStore.mergeDirectMessage(oldConversation, into: destination, isMuted: isMuted(destination))
            if selection == .directMessage(oldConversation.id) { selection = .directMessage(destination.id) }
        } else {
            conversationStore.renameDirectMessage(oldConversation.id, to: newNickname)
        }
    }

    private func renameMutedConversation(from oldName: String, to newName: String, serverID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == serverID }),
              var mutedNames = profiles[profileIndex].mutedConversationNames,
              let oldIndex = mutedNames.firstIndex(where: {
                  identifiersEqual($0, oldName, serverID: serverID)
              }) else { return }

        if mutedNames.indices.contains(where: {
            $0 != oldIndex && identifiersEqual(mutedNames[$0], newName, serverID: serverID)
        }) {
            mutedNames.remove(at: oldIndex)
        } else {
            mutedNames[oldIndex] = newName
        }
        profiles[profileIndex].mutedConversationNames = mutedNames.isEmpty ? nil : mutedNames
        saveProfiles()
    }

    private func renameFavoriteDirectMessage(from oldName: String, to newName: String, serverID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == serverID }),
              var favoriteNames = profiles[profileIndex].favoriteDirectMessages,
              let oldIndex = favoriteNames.firstIndex(where: {
                  identifiersEqual($0, oldName, serverID: serverID)
              }) else { return }

        if favoriteNames.indices.contains(where: {
            $0 != oldIndex && identifiersEqual(favoriteNames[$0], newName, serverID: serverID)
        }) {
            favoriteNames.remove(at: oldIndex)
        } else {
            favoriteNames[oldIndex] = newName
        }
        profiles[profileIndex].favoriteDirectMessages = favoriteNames.isEmpty ? nil : favoriteNames
        saveProfiles()
    }

    private func stageMembers(_ newMembers: [ChannelMember], for channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return  }
        conversationStore.channel(channelID)?.stageMembers(newMembers, caseMapping: features(for: serverID).caseMapping)
    }

    private func finishStagingMembers(for channelID: UUID) {
        conversationStore.channel(channelID)?.finishStagingMembers()
    }

    private func addMember(_ member: ChannelMember, to channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return  }
        conversationStore.channel(channelID)?.addMember(member, caseMapping: features(for: serverID).caseMapping)
    }

    @discardableResult
    private func removeMember(named nickname: String, from channelID: UUID) -> Bool {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return false }
        return conversationStore.channel(channelID)?.removeMember(named: nickname, caseMapping: features(for: serverID).caseMapping) ?? false
    }

    @discardableResult
    private func renameMember(_ oldNickname: String, to newNickname: String, in channelID: UUID) -> Bool {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return false }
        return conversationStore.channel(channelID)?.renameMember(oldNickname, to: newNickname, caseMapping: features(for: serverID).caseMapping) ?? false
    }

    /// Applies channel membership modes such as +o, -v, +h, and +q to the
    /// member list. Non-membership modes consume their IRC parameters so a
    /// mixed MODE command (for example +klo key 50 nick) stays aligned.
    private func applyMembershipModes(_ modeString: String, arguments: [String], to channelID: UUID) {
        guard let serverID = channels.first(where: { $0.id == channelID })?.serverID else { return  }
        conversationStore.channel(channelID)?.applyMembershipModes(modeString, arguments: arguments, features: features(for: serverID))
    }

    private func applyBanModes(_ modeString: String, arguments: [String], to channel: Conversation) {
        conversationStore.channel(channel.id)?.applyBanModes(
            modeString, arguments: arguments, channelName: channel.name, features: features(for: channel.serverID)
        )
    }

    private func beginMaskBanIdentityLookup(
        for channel: Conversation,
        profile: ServerProfile
    ) {
        let key = modeKey(serverID: profile.id, target: channel.name)
        guard sessions[profile.id, default: .init()].requests.maskBanWhoIDs[key] == nil else { return }
        let requestID = UUID()
        sessions[profile.id, default: .init()].requests.maskBanWhoIDs[key] = requestID
        connections[profile.id]?.send(command: "WHO \(channel.name)")
        DispatchQueue.main.asyncAfter(deadline: .now() + maskBanWhoRequestTimeout) { [weak self] in
            guard let self,
                  self.sessions[profile.id, default: .init()].requests.maskBanWhoIDs[key] == requestID else { return }
            self.sessions[profile.id, default: .init()].requests.maskBanWhoIDs.removeValue(forKey: key)
            let destinations = Set((self.sessions[profile.id, default: .init()].requests.maskBans[key] ?? []).compactMap {
                $0.state == .waitingForWho ? $0.destination : nil
            })
            for destination in destinations {
                self.appendSystem(
                    "The member identity lookup timed out; setting the ban with the identities currently available.",
                    for: destination
                )
            }
            self.releaseMaskBansWaitingForWho(forKey: key, profile: profile)
        }
    }

    private func completeMaskBanIdentityLookup(channelName: String, serverID: UUID) {
        let key = modeKey(serverID: serverID, target: channelName)
        guard sessions[serverID, default: .init()].requests.maskBanWhoIDs.removeValue(forKey: key) != nil,
              let profile = profiles.first(where: { $0.id == serverID }) else { return }
        releaseMaskBansWaitingForWho(forKey: key, profile: profile)
    }

    private func releaseMaskBansWaitingForWho(forKey key: String, profile: ServerProfile) {
        guard var pendingBans = sessions[profile.id, default: .init()].requests.maskBans[key] else { return }
        var didRelease = false
        for index in pendingBans.indices where pendingBans[index].state == .waitingForWho {
            pendingBans[index].state = .ready
            didRelease = true
        }
        guard didRelease else { return }
        sessions[profile.id, default: .init()].requests.maskBans[key] = pendingBans
        sendNextPendingMaskBan(forKey: key, profile: profile)
    }

    private func sendNextPendingMaskBan(forKey key: String, profile: ServerProfile) {
        guard var pendingBans = sessions[profile.id, default: .init()].requests.maskBans[key],
              !pendingBans.contains(where: { $0.state == .awaitingModeConfirmation }),
              let nextIndex = pendingBans.firstIndex(where: { $0.state == .ready }) else { return }
        pendingBans[nextIndex].state = .awaitingModeConfirmation
        let ban = pendingBans[nextIndex]
        sessions[profile.id, default: .init()].requests.maskBans[key] = pendingBans
        sessions[profile.id, default: .init()].requests.modes[key] = ban.destination
        connections[profile.id]?.send(command: "MODE \(ban.channel) +b \(ban.mask)")
    }

    @discardableResult
    private func failAwaitingMaskBan(
        forKey key: String,
        serverID: UUID,
        message: String
    ) -> Bool {
        guard var pendingBans = sessions[serverID, default: .init()].requests.maskBans[key],
              let failedIndex = pendingBans.firstIndex(where: {
                  $0.serverID == serverID && $0.state == .awaitingModeConfirmation
              }) else { return false }
        let failedBan = pendingBans.remove(at: failedIndex)
        sessions[serverID, default: .init()].requests.modes.removeValue(forKey: key)
        appendSystem("Ban failed: \(message)", for: failedBan.destination)
        if pendingBans.isEmpty {
            sessions[serverID, default: .init()].requests.maskBans.removeValue(forKey: key)
        } else {
            sessions[serverID, default: .init()].requests.maskBans[key] = pendingBans
        }
        if let profile = profiles.first(where: { $0.id == serverID }) {
            sendNextPendingMaskBan(forKey: key, profile: profile)
        }
        return true
    }

    private func kickMembersMatchingConfirmedBans(
        _ modeString: String,
        arguments: [String],
        from channel: Conversation,
        profile: ServerProfile
    ) {
        let key = modeKey(serverID: profile.id, target: channel.name)
        guard var pendingBans = sessions[profile.id, default: .init()].requests.maskBans[key], !pendingBans.isEmpty else { return }
        let serverFeatures = features(for: profile.id)
        let confirmedMasks = IRCChannelModeParser.changes(
            modeString: modeString,
            arguments: arguments,
            membership: serverFeatures.membership,
            channelModes: serverFeatures.channelModes
        ).compactMap { change in
            change.adding && change.mode == "b" ? change.argument : nil
        }
        guard !confirmedMasks.isEmpty else { return }

        for confirmedMask in confirmedMasks {
            let awaitingIndices = pendingBans.indices.filter {
                pendingBans[$0].state == .awaitingModeConfirmation
            }
            let awaitingMasks = awaitingIndices.map { pendingBans[$0].mask }
            guard let relativeIndex = IRCBanConfirmationPolicy.pendingMaskIndex(
                in: awaitingMasks,
                confirmedMask: confirmedMask,
                caseMapping: serverFeatures.caseMapping
            ) else { continue }
            let pendingIndex = awaitingIndices[relativeIndex]
            let ban = pendingBans.remove(at: pendingIndex)
            let localNickname = nickname(for: profile)
            let matchingMembers = (conversationStore.channel(channel.id)?.members ?? []).filter {
                IRCChannelModerationPolicy.mask(
                    confirmedMask,
                    matches: $0,
                    caseMapping: serverFeatures.caseMapping
                )
            }
            let orderedMembers = matchingMembers.filter {
                !identifiersEqual($0.nickname, localNickname, serverID: profile.id)
            } + matchingMembers.filter {
                identifiersEqual($0.nickname, localNickname, serverID: profile.id)
            }
            for member in orderedMembers {
                let reason = ban.reason.map { " \($0)" } ?? ""
                executeCommand("/kick \(channel.name) \(member.nickname)\(reason)", in: ban.destination)
            }
        }

        if pendingBans.isEmpty {
            sessions[profile.id, default: .init()].requests.maskBans.removeValue(forKey: key)
        } else {
            sessions[profile.id, default: .init()].requests.maskBans[key] = pendingBans
        }
        sendNextPendingMaskBan(forKey: key, profile: profile)
    }

    private func updateMemberIdentity(
        named nickname: String,
        username: String,
        hostname: String,
        serverID: UUID
    ) {
        for channel in channels where channel.serverID == serverID {
            conversationStore.channel(channel.id)?.updateMemberIdentity(
                named: nickname, username: username, hostname: hostname,
                caseMapping: features(for: serverID).caseMapping
            )
        }
    }

    private func isMessageDestination(_ item: SidebarItem) -> Bool {
        if case .channel = item { return true }
        if case .directMessage = item { return true }
        return false
    }

    @discardableResult
    private func canSendMessages(on profile: ServerProfile, reportingTo item: SidebarItem) -> Bool {
        guard sessions[profile.id]?.registeredAt != nil, connections[profile.id] != nil else {
            appendSystem("Wait for the server to finish connecting before sending messages or commands.", for: item)
            return false
        }
        return true
    }

    private func nickname(for profile: ServerProfile) -> String {
        sessions[profile.id, default: .init()].nickname ?? configuredNickname(for: profile)
    }

    private func ignoreSnapshot(for profile: ServerProfile) -> IRCIgnoreSnapshot {
        if let snapshot = ignoreSnapshotsByServer[profile.id] { return snapshot }
        let currentProfile = profiles.first(where: { $0.id == profile.id }) ?? profile
        let snapshot = IRCIgnoreSnapshot(
            nicknames: currentProfile.ignoredNicknames ?? [],
            caseMapping: features(for: profile.id).caseMapping
        )
        ignoreSnapshotsByServer[profile.id] = snapshot
        return snapshot
    }

    private func normalizedIdentifier(_ value: String, serverID: UUID) -> String {
        features(for: serverID).caseMapping.normalize(value)
    }

    private func features(for serverID: UUID) -> IRCServerFeatures {
        serverFeatures[serverID] ?? .defaults
    }

    private func messageMentionsLocalNickname(_ message: String, on profile: ServerProfile) -> Bool {
        IRCMentionPolicy.containsMention(
            of: nickname(for: profile),
            in: message,
            caseMapping: features(for: profile.id).caseMapping
        )
    }

    private func identifiersEqual(_ lhs: String, _ rhs: String, serverID: UUID) -> Bool {
        normalizedIdentifier(lhs, serverID: serverID) == normalizedIdentifier(rhs, serverID: serverID)
    }

    private func updateServerFeatures(from wire: IRCWireMessage, serverID: UUID) {
        let previous = features(for: serverID)
        var updated = previous
        updated.apply(parameters: wire.parameters.dropFirst())
        serverFeatures[serverID] = updated
        connections[serverID]?.setMaximumLineLength(updated.maximumLineLength)
        ignoreSnapshotsByServer.removeValue(forKey: serverID)

        guard updated.membership != previous.membership
                || updated.caseMapping != previous.caseMapping else { return }
        for channel in channels where channel.serverID == serverID {
            conversationStore.channel(channel.id)?.updateFeatures(updated)
        }
    }

    private func configuredNickname(for profile: ServerProfile) -> String {
        let override = profile.nicknameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? nickname : override
    }

    private func realName(for profile: ServerProfile) -> String {
        let override = profile.realNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? resolvedRealName() : override
    }

    private func resolvedRealName() -> String {
        let trimmedRealName = realName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRealName.isEmpty else {
            let anonymousRealName = Self.anonymousRealName()
            realName = anonymousRealName
            defaults.set(anonymousRealName, forKey: "realName")
            return anonymousRealName
        }
        return trimmedRealName
    }

    private func resolvedQuitMessage() -> String {
        let trimmedMessage = quitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? Self.defaultQuitMessage : trimmedMessage
    }

    private func retainWhileQuitting(
        _ connection: IRCConnection,
        reason: String,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        let quitID = UUID()
        disconnectingConnections[quitID] = connection
        connection.quit(reason: reason) { [weak self, weak connection] in
            if let self,
               let connection,
               self.disconnectingConnections[quitID] === connection {
                self.disconnectingConnections.removeValue(forKey: quitID)
                let waiters = self.disconnectCompletionWaiters.removeValue(forKey: quitID) ?? []
                waiters.forEach { $0() }
            }
            completion()
        }
    }

    private func scheduleReconnect(
        for profile: ServerProfile,
        reason: IRCReconnectReason,
        reuseCurrentAttempt: Bool = false
    ) {
        guard reconnectAutomatically,
              connections[profile.id] != nil,
              scheduledReconnects[profile.id] == nil,
              sleepPausedReconnectReasons[profile.id] == nil else { return }

        let attempt = IRCReconnectPolicy.attempt(
            after: reconnectAttempts[profile.id, default: 0],
            reusingCurrent: reuseCurrentAttempt
        )
        reconnectAttempts[profile.id] = attempt
        if systemSleepState.isSleeping {
            sleepPausedReconnectReasons[profile.id] = reason
            Self.connectionLogger.info(
                "Reconnect paused until wake server=\(profile.name, privacy: .public) reason=\(reason.rawValue, privacy: .public) attempt=\(attempt, privacy: .public)"
            )
            appendSystem(
                "Connection lost. Reconnect attempt \(attempt) will resume after system wake.",
                for: .server(profile.id)
            )
            return
        }

        let baseDelay = IRCReconnectPolicy.delay(
            attempt: attempt,
            initialDelay: initialReconnectDelay,
            maximumDelay: maximumReconnectDelay
        )
        let delay = IRCReconnectPolicy.jitteredDelay(
            baseDelay: baseDelay,
            randomUnit: Double.random(in: 0...1)
        )
        let now = Date()
        let resumeDate = automaticReconnectResumeDate(for: profile.id, at: now)
        let scheduledDelay: TimeInterval
        if let resumeDate {
            scheduledDelay = max(delay, resumeDate.timeIntervalSince(now))
            automaticReconnectResumeDates[profile.id] = resumeDate
        } else {
            scheduledDelay = delay
            automaticReconnectResumeDates.removeValue(forKey: profile.id)
        }
        let requestID = UUID()
        scheduledReconnects[profile.id] = ScheduledReconnect(
            requestID: requestID,
            reason: reason
        )
        Self.connectionLogger.info(
            "Reconnect scheduled server=\(profile.name, privacy: .public) reason=\(reason.rawValue, privacy: .public) attempt=\(attempt, privacy: .public) delay=\(scheduledDelay, privacy: .public) rateLimited=\(resumeDate != nil, privacy: .public)"
        )
        if let resumeDate {
            let observationMinutes = Int(IRCAutomaticReconnectLimiter.observationWindow / 60)
            let resumeTime = resumeDate.formatted(date: .omitted, time: .shortened)
            let message =
                "Automatic reconnect paused after \(IRCAutomaticReconnectLimiter.maximumAttempts) "
                + "attempts in \(observationMinutes) minutes. Netsplit will try again after "
                + "\(resumeTime), or you can choose Retry Now when the connection is stable."
            appendSystem(
                message,
                for: .server(profile.id)
            )
        } else {
            appendSystem(
                "Connection lost. Reconnecting in \(Int(ceil(scheduledDelay))) seconds (attempt \(attempt))…",
                for: .server(profile.id)
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + scheduledDelay) { [weak self] in
            guard let self,
                  self.reconnectAutomatically,
                  self.scheduledReconnects[profile.id]?.requestID == requestID,
                  let activeProfile = self.profiles.first(where: { $0.id == profile.id }),
                  let failedTransport = self.connections.removeValue(forKey: profile.id) else { return }
            self.scheduledReconnects.removeValue(forKey: profile.id)
            self.automaticReconnectResumeDates.removeValue(forKey: profile.id)
            self.recordAutomaticReconnectAttempt(for: profile.id, at: Date())
            Self.connectionLogger.info(
                "Reconnect starting server=\(activeProfile.name, privacy: .public) reason=\(reason.rawValue, privacy: .public) attempt=\(attempt, privacy: .public)"
            )
            self.resetPendingRequests(for: profile.id)
            self.sessions.removeValue(forKey: profile.id)
            failedTransport.disconnect()
            self.connect(activeProfile, selectConversation: false, isAutomaticRetry: true)
        }
    }

    private func automaticReconnectResumeDate(for serverID: UUID, at date: Date) -> Date? {
        guard var limiter = automaticReconnectLimiters[serverID] else { return nil }
        let resumeDate = limiter.nextAllowedAttemptDate(at: date)
        if limiter.recentAttemptDates.isEmpty {
            automaticReconnectLimiters.removeValue(forKey: serverID)
        } else {
            automaticReconnectLimiters[serverID] = limiter
        }
        return resumeDate
    }

    private func recordAutomaticReconnectAttempt(for serverID: UUID, at date: Date) {
        var limiter = automaticReconnectLimiters[serverID] ?? IRCAutomaticReconnectLimiter()
        limiter.recordAttempt(at: date)
        automaticReconnectLimiters[serverID] = limiter
    }

    private func scheduleReconnectStateResetAfterStability(for profile: ServerProfile) {
        let hasReconnectState = reconnectAttempts[profile.id] != nil
            || automaticReconnectLimiters[profile.id] != nil
        guard !systemSleepState.isSleeping, hasReconnectState else {
            reconnectStabilityGenerations.removeValue(forKey: profile.id)
            return
        }
        let generation = UUID()
        reconnectStabilityGenerations[profile.id] = generation
        DispatchQueue.main.asyncAfter(
            deadline: .now() + IRCReconnectPolicy.stableConnectionDuration
        ) { [weak self] in
            guard let self,
                  self.reconnectStabilityGenerations[profile.id] == generation else { return }
            self.reconnectStabilityGenerations.removeValue(forKey: profile.id)
            guard self.sessions[profile.id]?.registeredAt != nil,
                  self.connections[profile.id] != nil else { return }
            self.reconnectAttempts.removeValue(forKey: profile.id)
            self.automaticReconnectLimiters.removeValue(forKey: profile.id)
            Self.connectionLogger.info(
                "Reconnect state reset after stable connection server=\(profile.name, privacy: .public)"
            )
        }
    }

    private func cancelScheduledReconnect(for serverID: UUID, resetAttempts: Bool) {
        scheduledReconnects.removeValue(forKey: serverID)
        sleepPausedReconnectReasons.removeValue(forKey: serverID)
        automaticReconnectResumeDates.removeValue(forKey: serverID)
        if resetAttempts {
            reconnectAttempts.removeValue(forKey: serverID)
            reconnectStabilityGenerations.removeValue(forKey: serverID)
        }
    }

    private func cancelAllScheduledReconnects() {
        scheduledReconnects.removeAll()
        sleepPausedReconnectReasons.removeAll()
        automaticReconnectResumeDates.removeAll()
        reconnectAttempts.removeAll()
        automaticReconnectLimiters.removeAll()
        reconnectStabilityGenerations.removeAll()
    }

    private func appendSystem(_ text: String, for item: SidebarItem) {
        append(IRCMessage(sender: "System", text: text, isSystem: true), for: item)
    }

    private func clearTranscript(for item: SidebarItem) {
        conversationStore.clearTranscript(for: item)
    }

    private func appendChannelEvent(
        _ text: String,
        kind: IRCChannelEventKind? = nil,
        channelID: UUID,
        memberCount: Int? = nil
    ) {
        let resolvedMemberCount = memberCount ?? conversationStore.channel(channelID)?.members.count ?? 0
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
        markMention shouldMarkMention: Bool = false,
        notifyDirectMessage shouldNotifyDirectMessage: Bool = false
    ) {
        guard conversationID(for: item) != nil else { return }
        var resolvedMessage = message
        if let incomingMessageTimestamp {
            resolvedMessage.timestamp = incomingMessageTimestamp
        }
        if resolvedMessage.channelTypes == nil, let profile = profile(for: item) {
            resolvedMessage.channelTypes = features(for: profile.id).channelTypes
        }
        conversationStore.append(resolvedMessage, for: item)
        let conversationIsMuted = conversation(for: item).map(isMuted) ?? false
        let canAccumulateActivity: Bool
        if case .channel(let channelID) = item {
            canAccumulateActivity = IRCConversationActivityPolicy.shouldAccumulateChannelActivity(
                joinedAt: conversationStore.channel(channelID)?.joinedAt,
                now: ContinuousClock().now
            )
        } else {
            canAccumulateActivity = true
        }
        if canAccumulateActivity, !conversationIsMuted, selection != item, !resolvedMessage.isSystem {
            if shouldMarkMention {
                markMention(item)
            } else if shouldMarkUnread {
                markUnread(item)
            }
        }
        if shouldMarkMention, !conversationIsMuted {
            postMentionNotification(for: resolvedMessage, in: item)
        }
        if shouldNotifyDirectMessage, !conversationIsMuted {
            postDirectMessageNotification(for: resolvedMessage, in: item)
        }

    }

    private func postMentionNotification(for message: IRCMessage, in item: SidebarItem) {
        guard case .channel(let conversationID) = item,
              let channel = channels.first(where: { $0.id == conversationID }),
              let profile = profiles.first(where: { $0.id == channel.serverID }),
              IRCInitialNotificationSuppressionPolicy.shouldAllowNotification(
                connectedAt: sessions[profile.id]?.registeredAt
              ) else { return }

        let enabled = IRCMentionNotificationPolicy.isEnabled(
            globalSetting: mentionNotificationsEnabled,
            serverOverride: profile.mentionNotificationsOverride
        )
        guard IRCMentionNotificationPolicy.shouldNotify(
            isEnabled: enabled,
            applicationIsActive: NSApplication.shared.isActive,
            conversationIsSelected: selection == item
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(IRCMessageTextRenderer.plainText(message.sender)) mentioned you"
        content.subtitle = "\(channel.name) on \(profile.name)"
        content.body = IRCMessageTextRenderer.plainText(message.text)
        content.sound = .default
        content.threadIdentifier = "\(profile.id.uuidString).\(channel.name)"
        content.userInfo = [
            "serverID": profile.id.uuidString,
            "channelName": channel.name
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func postDirectMessageNotification(for message: IRCMessage, in item: SidebarItem) {
        guard case .directMessage(let conversationID) = item,
              let conversation = directMessages.first(where: { $0.id == conversationID }),
              let profile = profiles.first(where: { $0.id == conversation.serverID }),
              IRCInitialNotificationSuppressionPolicy.shouldAllowNotification(
                connectedAt: sessions[profile.id]?.registeredAt
              ),
              IRCDirectMessageNotificationPolicy.shouldNotify(
                isEnabled: directMessageNotificationsEnabled,
                applicationIsActive: NSApplication.shared.isActive,
                conversationIsSelected: selection == item
              ) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Direct message from \(conversation.name)"
        content.subtitle = profile.name
        content.body = IRCMessageTextRenderer.plainText(message.text)
        content.sound = .default
        content.threadIdentifier = "\(profile.id.uuidString).dm.\(conversation.name)"
        content.userInfo = [
            "serverID": profile.id.uuidString,
            "directMessageNickname": conversation.name
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func markUnread(_ item: SidebarItem) {
        conversationStore.markUnread(item)
    }

    private func markMention(_ item: SidebarItem) {
        conversationStore.markMention(item)
    }

    private func formatIdle(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    private func whoisKey(serverID: UUID, target: String) -> String {
        normalizedIdentifier(target, serverID: serverID)
    }

    private func joinKey(serverID: UUID, channel: String) -> String {
        normalizedIdentifier(channel, serverID: serverID)
    }

    private func whoKey(serverID: UUID, target: String) -> String {
        normalizedIdentifier(target, serverID: serverID)
    }

    private func topicKey(serverID: UUID, channel: String) -> String {
        normalizedIdentifier(channel, serverID: serverID)
    }

    private func inviteKey(serverID: UUID, nickname: String, channel: String) -> String {
        "\(normalizedIdentifier(nickname, serverID: serverID))|\(normalizedIdentifier(channel, serverID: serverID))"
    }

    private func modeKey(serverID: UUID, target: String) -> String {
        normalizedIdentifier(target, serverID: serverID)
    }

    private func kickKey(serverID: UUID, channel: String, nickname: String) -> String {
        "\(normalizedIdentifier(channel, serverID: serverID))|\(normalizedIdentifier(nickname, serverID: serverID))"
    }

    private func killKey(serverID: UUID, nickname: String) -> String {
        normalizedIdentifier(nickname, serverID: serverID)
    }

    private func outgoingEchoLabel(for serverID: UUID, id: UUID) -> String? {
        guard connections[serverID]?.isCapabilityEnabled("labeled-response") == true else {
            return nil
        }
        return id.uuidString.lowercased()
    }

    private func outgoingLabelPrefix(for serverID: UUID, label: String?) -> String {
        guard let label,
              connections[serverID]?.isCapabilityEnabled("labeled-response") == true else {
            return ""
        }
        return "@label=\(label) "
    }

    private func outgoingTextChunks(
        _ text: String,
        commandPrefix: String,
        suffix: String = "",
        maximumLineLength: Int,
        sourcePrefix: String?
    ) -> [String] {
        IRCTextFraming.messageChunks(
            text,
            commandPrefix: commandPrefix,
            suffix: suffix,
            maximumLineBytes: max(
                0,
                maximumLineLength - IRCTextFraming.lineTerminatorBytes
            ),
            sourcePrefix: sourcePrefix
        )
    }

    private func localSourcePrefix(for profile: ServerProfile) -> String? {
        if let observedPrefix = sessions[profile.id, default: .init()].sourcePrefix {
            return observedPrefix
        }
        let localNickname = nickname(for: profile)
        for channel in channels(for: profile) {
            guard let member = conversationStore.channel(channel.id)?.members.first(where: {
                identifiersEqual($0.nickname, localNickname, serverID: profile.id)
            }), let username = member.username, let hostname = member.hostname else {
                continue
            }
            return "\(localNickname)!\(username)@\(hostname)"
        }
        return nil
    }

    private func rememberLocalSourcePrefix(
        _ prefix: String?,
        sender: String,
        profile: ServerProfile
    ) {
        guard identifiersEqual(sender, nickname(for: profile), serverID: profile.id),
              let prefix,
              prefix.contains("!"),
              prefix.contains("@") else { return }
        sessions[profile.id, default: .init()].sourcePrefix = prefix
    }

    private func relayedMessageByteLimit(
        target: String,
        sourcePrefix: String?,
        profile: ServerProfile,
        command: String = "PRIVMSG"
    ) -> Int? {
        guard let sourcePrefix else { return nil }
        return IRCTextFraming.messageContentByteLimit(
            commandPrefix: "\(command) \(target) :",
            maximumLineLength: features(for: profile.id).maximumLineLength,
            sourcePrefix: sourcePrefix
        )
    }

    private func rememberOutgoingEcho(
        serverID: UUID,
        target: String,
        wireText: String,
        message: IRCMessage,
        destination: SidebarItem,
        presentation: IRCOutgoingEchoPresentation = .message,
        suppressTranscript: Bool = false,
        label: String? = nil
    ) -> UUID {
        pruneOutgoingEchoes(for: serverID)
        let id = UUID()
        let pending = PendingOutgoingEcho(
            id: id,
            target: target,
            wireText: wireText,
            label: label ?? outgoingEchoLabel(for: serverID, id: id),
            state: IRCOutgoingEchoState(
                message: message,
                presentation: presentation
            ),
            destination: destination,
            sentAt: Date(),
            suppressTranscript: suppressTranscript
        )
        sessions[serverID, default: .init()].requests.appendOutgoingEcho(pending)
        return pending.id
    }

    private func handleOutgoingWriteCompletion(
        serverID: UUID,
        id: UUID,
        succeeded: Bool,
        fallbackMessage: IRCMessage,
        fallbackDestination: SidebarItem,
        suppressTranscript: Bool = false
    ) {
        guard var pending = sessions[serverID, default: .init()].requests.outgoingEchoes,
              let index = pending.firstIndex(where: { $0.id == id }) else {
            if succeeded && !suppressTranscript {
                append(fallbackMessage, for: fallbackDestination, markUnread: false)
            }
            return
        }
        let transition = pending[index].state.completeWrite(
            succeeded: succeeded || pending[index].hasConsumedSelfTargetedDelivery
        )
        let resolvedPending = pending[index]
        if transition.isComplete {
            pending.remove(at: index)
        } else {
            pending[index] = resolvedPending
        }
        sessions[serverID, default: .init()].requests.outgoingEchoes = pending
        applyOutgoingEchoTransition(transition, pending: resolvedPending)
    }

    private func reconcileOutgoingEcho(
        serverID: UUID,
        target: String,
        wireText: String,
        tags: [String: String?],
        timestamp: Date?,
        maximumEchoBytes: Int? = nil
    ) -> Bool {
        pruneOutgoingEchoes(for: serverID)
        guard var pending = sessions[serverID, default: .init()].requests.outgoingEchoes else { return false }
        let candidates = pending.map {
            IRCOutgoingEchoCandidate(
                target: $0.target,
                wireText: $0.wireText,
                label: $0.label,
                hasReceivedServerConfirmation: $0.state.hasReceivedServerConfirmation,
                presentation: $0.state.presentation
            )
        }
        let index = IRCOutgoingEchoCorrelationPolicy.matchingIndex(
            in: candidates,
            target: target,
            wireText: wireText,
            label: tags["label"] ?? nil,
            maximumEchoBytes: maximumEchoBytes,
            caseMapping: features(for: serverID).caseMapping
        )
        guard let index else { return false }
        guard let transition = pending[index].state.receiveEcho(
            wireText: wireText,
            tags: tags,
            timestamp: timestamp
        ) else { return false }
        let resolvedPending = pending[index]
        let shouldExpectSecondSelfTargetedCopy = tags["label"] != nil
            || connections[serverID]?.isCapabilityEnabled("echo-message") == true
        if shouldExpectSecondSelfTargetedCopy,
           !resolvedPending.hasConsumedSelfTargetedDelivery,
           isLocalNickname(target, serverID: serverID) {
            rememberSelfTargetedConfirmation(
                serverID: serverID,
                target: target,
                wireText: wireText
            )
        }
        if transition.isComplete {
            pending.remove(at: index)
        } else {
            pending[index] = resolvedPending
        }
        sessions[serverID, default: .init()].requests.outgoingEchoes = pending
        applyOutgoingEchoTransition(transition, pending: resolvedPending)
        return true
    }

    private func reconcileOutgoingAcknowledgement(
        serverID: UUID,
        label: String
    ) -> Bool {
        pruneOutgoingEchoes(for: serverID)
        guard var pending = sessions[serverID, default: .init()].requests.outgoingEchoes,
              let index = pending.firstIndex(where: {
                  $0.label == label && !$0.state.hasReceivedServerConfirmation
              }) else {
            return false
        }
        if !pending[index].hasConsumedSelfTargetedDelivery,
           isLocalNickname(pending[index].target, serverID: serverID) {
            rememberSelfTargetedConfirmation(
                serverID: serverID,
                target: pending[index].target,
                wireText: pending[index].wireText
            )
        }
        guard let transition = pending[index].state.receiveAcknowledgement() else {
            return false
        }
        let resolvedPending = pending[index]
        if transition.isComplete {
            pending.remove(at: index)
        } else {
            pending[index] = resolvedPending
        }
        sessions[serverID, default: .init()].requests.outgoingEchoes = pending
        applyOutgoingEchoTransition(transition, pending: resolvedPending)
        return true
    }

    private func reconcileOutgoingRejection(
        serverID: UUID,
        label: String
    ) -> Bool {
        pruneOutgoingEchoes(for: serverID)
        guard var pending = sessions[serverID, default: .init()].requests.outgoingEchoes,
              let index = pending.firstIndex(where: {
                  $0.label == label && !$0.state.hasReceivedServerConfirmation
              }),
              let transition = pending[index].state.receiveRejection() else {
            return false
        }
        let resolvedPending = pending[index]
        if transition.isComplete {
            pending.remove(at: index)
        } else {
            pending[index] = resolvedPending
        }
        sessions[serverID, default: .init()].requests.outgoingEchoes = pending
        applyOutgoingEchoTransition(transition, pending: resolvedPending)
        return true
    }

    private func applyOutgoingEchoTransition(
        _ transition: IRCOutgoingEchoTransition,
        pending: PendingOutgoingEcho
    ) {
        guard !pending.suppressTranscript else { return }
        switch transition.transcriptMutation {
        case .none:
            break
        case .append(let message):
            if !containsMessage(
                serverMessageID: message.serverMessageID,
                in: pending.destination
            ) {
                append(message, for: pending.destination, markUnread: false)
            }
        case .replace(let message):
            if containsMessage(
                serverMessageID: message.serverMessageID,
                excludingID: message.id,
                in: pending.destination
            ) {
                removeMessage(matchingID: message.id, from: pending.destination)
            } else if !replaceMessage(
                message,
                matchingID: message.id,
                for: pending.destination
            ) {
                append(message, for: pending.destination, markUnread: false)
            }
        case .remove(let id):
            removeMessage(matchingID: id, from: pending.destination)
        }
    }

    /// A server reply can beat the transport's asynchronous write callback.
    /// Preserve that authoritative result when a disconnect tears down the
    /// session; the later callback is session-gated and cannot append it again.
    private func finalizePendingOutgoingEchoes(for serverID: UUID) {
        guard let pending = sessions[serverID, default: .init()].requests.takeOutgoingEchoes() else {
            return
        }
        for var outgoing in pending {
            let transition = outgoing.state.completeWrite(
                succeeded: outgoing.hasConsumedSelfTargetedDelivery
            )
            applyOutgoingEchoTransition(transition, pending: outgoing)
        }
    }

    @discardableResult
    private func replaceMessage(
        _ message: IRCMessage,
        matchingID id: UUID,
        for item: SidebarItem
    ) -> Bool {
        conversationStore.replaceMessage(message, matchingID: id, for: item)
    }

    private func removeMessage(matchingID id: UUID, from item: SidebarItem) {
        conversationStore.removeMessage(matchingID: id, from: item)
    }

    private func isDuplicateSelfTargetedDelivery(
        serverID: UUID,
        target: String,
        wireText: String,
        presentation: IRCOutgoingEchoPresentation,
        tags: [String: String?]
    ) -> Bool {
        guard isLocalNickname(target, serverID: serverID) else { return false }
        pruneOutgoingEchoes(for: serverID)
        let label = tags["label"] ?? nil
        if let label,
           sessions[serverID, default: .init()].requests.outgoingEchoes?.contains(where: {
               $0.label == label && !$0.state.hasReceivedServerConfirmation
           }) == true {
            return false
        }

        if label == nil {
            let pendingCandidates = (sessions[serverID, default: .init()].requests.outgoingEchoes ?? []).map {
                IRCOutgoingEchoCandidate(
                    target: $0.target,
                    wireText: $0.wireText,
                    label: $0.label,
                    hasReceivedServerConfirmation: $0.state.hasReceivedServerConfirmation,
                    presentation: $0.state.presentation
                )
            }
            if let index = IRCSelfTargetedEchoDuplicatePolicy.matchingPendingIndex(
                in: pendingCandidates,
                target: target,
                wireText: wireText,
                presentation: presentation,
                caseMapping: features(for: serverID).caseMapping
            ) {
                sessions[serverID, default: .init()].requests.outgoingEchoes?[index].hasConsumedSelfTargetedDelivery = true
                return true
            }
            pruneRecentSelfTargetedConfirmations(for: serverID)
            if var recent = sessions[serverID, default: .init()].requests.selfTargetedConfirmations,
               let index = IRCSelfTargetedEchoDuplicatePolicy.matchingIndex(
                   in: recent,
                   target: target,
                   wireText: wireText,
                   now: Date(),
                   maximumAge: 30,
                   caseMapping: features(for: serverID).caseMapping
               ) {
                recent.remove(at: index)
                if recent.isEmpty {
                    sessions[serverID, default: .init()].requests.takeSelfTargetedConfirmations()
                } else {
                    sessions[serverID, default: .init()].requests.selfTargetedConfirmations = recent
                }
                return true
            }
        }

        guard let messageID = tags["msgid"] ?? nil else { return false }
        if sessions[serverID, default: .init()].requests.outgoingEchoes?.contains(where: {
            $0.state.message.serverMessageID == messageID
        }) == true {
            return true
        }
        guard let conversation = directMessages.first(where: {
            $0.serverID == serverID
                && identifiersEqual($0.name, target, serverID: serverID)
        }) else { return false }
        return containsMessage(
            serverMessageID: messageID,
            in: .directMessage(conversation.id)
        )
    }

    private func isLocalNickname(_ target: String, serverID: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == serverID }) else { return false }
        return identifiersEqual(target, nickname(for: profile), serverID: serverID)
    }

    private func incomingEchoPresentation(
        forPrivmsgText text: String
    ) -> IRCOutgoingEchoPresentation {
        if text.hasPrefix("\u{01}ACTION "), text.hasSuffix("\u{01}") {
            return .action
        }
        return .message
    }

    private func rememberSelfTargetedConfirmation(
        serverID: UUID,
        target: String,
        wireText: String
    ) {
        pruneRecentSelfTargetedConfirmations(for: serverID)
        sessions[serverID, default: .init()].requests.appendSelfTargetedConfirmation(
            IRCRecentSelfTargetedConfirmation(
                target: target,
                wireText: wireText,
                recordedAt: Date()
            )
        )
        if (sessions[serverID]?.requests.selfTargetedConfirmations?.count ?? 0) > 256 {
            sessions[serverID, default: .init()].requests.selfTargetedConfirmations?.removeFirst()
        }
    }

    private func pruneRecentSelfTargetedConfirmations(for serverID: UUID) {
        let now = Date()
        sessions[serverID, default: .init()].requests.selfTargetedConfirmations?.removeAll {
            now.timeIntervalSince($0.recordedAt) > 30
        }
        if sessions[serverID, default: .init()].requests.selfTargetedConfirmations?.isEmpty == true {
            sessions[serverID, default: .init()].requests.takeSelfTargetedConfirmations()
        }
    }

    private func containsMessage(
        serverMessageID: String?,
        excludingID: UUID? = nil,
        in item: SidebarItem
    ) -> Bool {
        guard let serverMessageID,
              conversationID(for: item) != nil else { return false }
        return conversationStore.messages(for: item).contains {
            $0.id != excludingID && $0.serverMessageID == serverMessageID
        }
    }

    private func pruneOutgoingEchoes(for serverID: UUID) {
        let now = Date()
        // Never expire an entry that is still awaiting its asynchronous write
        // callback. A server echo/ACK may already be held in that state, and
        // removing it would either lose the confirmed row or let the eventual
        // callback append a duplicate fallback. Keep unconfirmed setup commands
        // until the session ends so a delayed echo cannot expose credentials.
        sessions[serverID, default: .init()].requests.outgoingEchoes?.removeAll {
            IRCOutgoingEchoRetentionPolicy.shouldExpire(
                $0.state,
                sentAt: $0.sentAt,
                now: now,
                suppressTranscript: $0.suppressTranscript
            )
        }
        if sessions[serverID, default: .init()].requests.outgoingEchoes?.isEmpty == true {
            sessions[serverID, default: .init()].requests.takeOutgoingEchoes()
        }
        pruneRecentSelfTargetedConfirmations(for: serverID)
    }

    private func requestChannelListing(for profile: ServerProfile, arguments: String = "", forceRefresh: Bool = false) {
        guard sessions[profile.id]?.registeredAt != nil else {
            appendSystem("Wait for the server to finish connecting before browsing channels.", for: .server(profile.id))
            return
        }
        channelBrowserProfileID = profile.id
        isChannelBrowserPresented = true
        let hasArguments = !arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard let requestID = channelDirectory.beginRequest(
            on: profile.id, hasArguments: hasArguments, forceRefresh: forceRefresh
        ) else { return }
        let sessionID = sessions[profile.id]?.id
        connections[profile.id]?.send(command: hasArguments ? "LIST \(arguments)" : "LIST") { [weak self] sent in
            guard let self, !sent, self.sessions[profile.id]?.id == sessionID,
                  self.channelDirectory.fail(profile.id, requestID: requestID, flushPending: false) else { return }
            self.appendSystem("The channel list request could not be sent.", for: .server(profile.id))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + channelListRequestTimeout) { [weak self] in
            guard let self, self.sessions[profile.id]?.id == sessionID,
                  self.channelDirectory.fail(profile.id, requestID: requestID) else { return }
            self.appendSystem("The channel list request timed out. You can retry the request.", for: .server(profile.id))
        }
    }

    private func queueChannelListing(_ listing: ChannelListing, for serverID: UUID) {
        channelDirectory.enqueue(listing, on: serverID, caseMapping: features(for: serverID).caseMapping)
    }

    private func saveProfiles() {
        ignoreSnapshotsByServer.removeAll(keepingCapacity: true)
        ServerProfileStore.save(storedProfiles, to: defaults)
    }

    private func saveCredentials(_ changes: IRCProfileCredentialChanges, for profile: ServerProfile) -> IRCProfileSaveResult {
        var savedKinds = Set<String>()
        do {
            for (kind, value) in try changes.encodedValues() {
                try credentialStore.set(value, for: credentialAccount(profile: profile, kind: kind))
                savedKinds.insert(kind)
            }
            return IRCProfileSaveResult(succeeded: true, savedCredentials: changes)
        } catch {
            reportKeychainAccessIssue(error, force: true)
            return IRCProfileSaveResult(succeeded: false, savedCredentials: changes.restricted(to: savedKinds))
        }
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

    private func credentialValue(for profile: ServerProfile, kind: String) -> String {
        readCredential(for: profile, kind: kind) ?? ""
    }

    private func readCredential(for profile: ServerProfile, kind: String) -> String? {
        do {
            return try credentialStore.value(for: credentialAccount(profile: profile, kind: kind))
        } catch {
            reportKeychainAccessIssue(error)
            return nil
        }
    }

    private func removeCredential(for profile: ServerProfile, kind: String) {
        do {
            try credentialStore.set("", for: credentialAccount(profile: profile, kind: kind))
        } catch {
            reportKeychainAccessIssue(error)
        }
    }

    private func reportKeychainAccessIssue(_ error: Error, force: Bool = false) {
        guard force || !hasReportedKeychainAccessIssue else { return }
        hasReportedKeychainAccessIssue = true

        let operation = (error as? KeychainStore.AccessError)?.operation
        let isSaving = force || operation == .save
        keychainAccessIssue = KeychainAccessIssue(
            title: isSaving ? "Couldn’t Save Credentials" : "Couldn’t Access Saved Credentials",
            message: """
            macOS did not allow Netsplit to \(isSaving ? "save information in" : "access information from") your login Keychain. Your server profiles are still safe, but passwords, SSH credentials, or on-connect commands may be unavailable.

            This can happen after switching between development and App Store builds. If macOS asks again, choose “Always Allow”, or re-enter the affected credential in the server profile.
            """
        )
    }

    private static func anonymousNickname() -> String {
        "netsplit" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
    }

    private static func anonymousRealName() -> String {
        "Netsplit User " + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
    }
}
