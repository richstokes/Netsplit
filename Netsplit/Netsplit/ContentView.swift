//
//  ContentView.swift
//  Netsplit
//

import AppKit
import SwiftUI

struct IRCTextMetrics: Equatable {
    let bodySize: CGFloat

    init(bodySize: Double = 16) {
        self.bodySize = CGFloat(bodySize)
    }

    var scale: CGFloat { bodySize / 16 }
    var layoutScale: CGFloat { min(max(scale, 0.8), 1.25) }

    func size(_ points: CGFloat) -> CGFloat {
        max(10, (points * scale).rounded(.toNearestOrAwayFromZero))
    }

    func spacing(_ points: CGFloat) -> CGFloat {
        (points * layoutScale).rounded(.toNearestOrAwayFromZero)
    }
}

private struct IRCTextMetricsKey: EnvironmentKey {
    static let defaultValue = IRCTextMetrics()
}

extension EnvironmentValues {
    var ircTextMetrics: IRCTextMetrics {
        get { self[IRCTextMetricsKey.self] }
        set { self[IRCTextMetricsKey.self] = newValue }
    }
}

struct ContentView: View {
    @ObservedObject var state: IRCAppState
    @State private var showAddServer = false
    @State private var editingProfile: ServerProfile?
    @FocusState private var workspaceFocus: IRCWorkspaceFocus?

    private var textMetrics: IRCTextMetrics { IRCTextMetrics(bodySize: state.transcriptFontSize) }
    private var hasSelectedChannel: Bool {
        guard let selection = state.selection else { return false }
        if case .channel = selection { return true }
        return false
    }

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { state.showsServerChannelPane ? .all : .detailOnly },
            set: { state.showsServerChannelPane = $0 != .detailOnly }
        )) {
            SidebarView(
                state: state,
                showAddServer: $showAddServer,
                editingProfile: $editingProfile,
                workspaceFocus: $workspaceFocus
            )
                .navigationSplitViewColumnWidth(
                    min: textMetrics.spacing(218),
                    ideal: textMetrics.spacing(250),
                    max: textMetrics.spacing(340)
                )
        } detail: {
            Group {
                if state.selection == .connectionCenter || state.selection == nil {
                    ConnectionCenterView(state: state, showAddServer: $showAddServer, editingProfile: $editingProfile)
                } else if let selection = state.selection {
                    ConversationView(state: state, selection: selection, workspaceFocus: $workspaceFocus)
                        .id(selection)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { state.navigateBack() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(!state.canNavigateBack)
                    .help("Back (⌘[)")
                    .accessibilityHint("Returns to the previously viewed conversation")

                    Button { state.navigateForward() } label: {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(!state.canNavigateForward)
                    .help("Forward (⌘])")
                    .accessibilityHint("Moves to the next conversation in navigation history")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.selectedProfile != nil {
                        Button { state.requestChannelListing() } label: {
                            Label("Browse Channels…", systemImage: "list.bullet.rectangle")
                        }
                        .disabled(!state.canBrowseSelectedChannels)
                        .accessibilityHint("Shows the channel list for the selected server")
                    }
                    if hasSelectedChannel {
                        Toggle(isOn: Binding(
                            get: { state.showsMemberList },
                            set: { _ in state.toggleMemberList() }
                        )) {
                            Label("Members", systemImage: "sidebar.right")
                        }
                        .toggleStyle(.button)
                        .accessibilityLabel(state.showsMemberList ? "Hide Members" : "Show Members")
                        .help(state.showsMemberList ? "Hide member list" : "Show member list")
                    }
                }
            }
        }
        .ircWorkspaceTheme()
        .environment(\.ircTextMetrics, textMetrics)
        .sheet(isPresented: $showAddServer) {
            ServerProfileEditor(state: state)
        }
        .sheet(item: $editingProfile) { profile in
            ServerProfileEditor(state: state, profileToEdit: profile)
        }
        .sheet(isPresented: $state.isChannelBrowserPresented) {
            ChannelBrowser(state: state)
        }
        .sheet(isPresented: $state.isJumpPalettePresented) {
            JumpPalette(state: state)
        }
        .onChange(of: state.workspaceFocusRequest) { _, request in
            guard let request else { return }
            DispatchQueue.main.async {
                guard state.workspaceFocusRequest == request else { return }
                if case .composer(let selection) = request.target,
                   state.selection != selection { return }
                workspaceFocus = request.target
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var state: IRCAppState
    @Binding var showAddServer: Bool
    @Binding var editingProfile: ServerProfile?
    @FocusState.Binding var workspaceFocus: IRCWorkspaceFocus?
    @State private var listSelection: SidebarItem?
    @State private var collapsedProfileIDs: Set<UUID> = []
    @Environment(\.ircTextMetrics) private var textMetrics

    var body: some View {
        List(selection: $listSelection) {
            Section {
                Label("Connections", systemImage: "bolt.horizontal.circle")
                    .font(.system(size: textMetrics.size(16), weight: .medium))
                    .padding(.vertical, textMetrics.spacing(2))
                    .tag(SidebarItem.connectionCenter)
            }

            ForEach(state.activeProfiles) { profile in
                Section {
                    ServerRow(profile: profile, state: state)
                        .tag(SidebarItem.server(profile.id))
                        .contextMenu {
                            Button("Edit Profile…") { editingProfile = profile }
                            Divider()
                            if case .failed = state.status(for: profile) {
                                Button("Retry Now") { state.toggleConnection(for: profile) }
                            }
                            Button(state.isWaitingToReconnect(profile) ? "Stop Reconnecting" : "Disconnect") {
                                state.disconnect(profile)
                            }
                            if !profile.isBuiltIn {
                                Divider()
                                Button("Delete Server Profile", role: .destructive) { state.delete(profile) }
                            }
                    }

                    if !collapsedProfileIDs.contains(profile.id) {
                        ForEach(state.channels(for: profile)) { channel in
                            SidebarChannelLabel(
                                channel: channel,
                                isFavorite: state.isFavorite(channel)
                            )
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(channel.name)
                                .accessibilityValue(channelAccessibilityValue(channel))
                                .tag(SidebarItem.channel(channel.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    state.selectFromSidebar(.channel(channel.id))
                                })
                                .contextMenu {
                                    Button(state.isFavorite(channel) ? "Unfavorite" : "Favorite", systemImage: state.isFavorite(channel) ? "star.slash" : "star") {
                                        state.toggleFavorite(channel)
                                    }
                                    Divider()
                                    Button("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right") {
                                        state.leave(channel)
                                    }
                                }
                        }

                        ForEach(state.directMessages(for: profile)) { message in
                            Label(message.name, systemImage: "person.crop.circle")
                                .foregroundStyle(message.hasUnread ? .primary : .secondary)
                                .font(.system(size: textMetrics.size(15), weight: message.hasUnread ? .semibold : .regular))
                                .padding(.vertical, textMetrics.spacing(1.5))
                                .tag(SidebarItem.directMessage(message.id))
                                .accessibilityValue(message.hasUnread ? "Unread messages" : "No unread messages")
                                .contextMenu {
                                    Button("Mute and Close", systemImage: "speaker.slash") {
                                        state.muteAndClose(message)
                                    }
                                    Divider()
                                    Button("Close Conversation", systemImage: "xmark") {
                                        state.close(message)
                                    }
                                }
                        }
                    }
                } header: {
                    SidebarServerHeader(
                        name: profile.name,
                        isCollapsible: state.activeProfiles.count > 1,
                        isCollapsed: collapsedProfileIDs.contains(profile.id),
                        activity: state.activity(for: profile)
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            if collapsedProfileIDs.contains(profile.id) {
                                collapsedProfileIDs.remove(profile.id)
                            } else {
                                collapsedProfileIDs.insert(profile.id)
                            }
                        }
                    }
                    .font(.system(size: textMetrics.size(11), weight: .semibold))
                    .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .ircSidebarBackground()
        .focused($workspaceFocus, equals: .sidebar)
        .accessibilityLabel("Servers and conversations")
        .accessibilityHint("Use the arrow keys to choose a server or conversation")
        .onAppear { listSelection = state.selection }
        .onChange(of: listSelection) { _, newSelection in
            DispatchQueue.main.async {
                guard listSelection == newSelection,
                      state.selection != newSelection else { return }
                state.selectFromSidebar(newSelection)
            }
        }
        .onChange(of: state.selection) { _, newSelection in
            if listSelection != newSelection { listSelection = newSelection }
            if let selectedProfileID = state.selectedProfile?.id {
                collapsedProfileIDs.remove(selectedProfileID)
            }
        }
        .onChange(of: state.activeProfiles.map(\.id)) { _, activeProfileIDs in
            if activeProfileIDs.count <= 1 {
                collapsedProfileIDs.removeAll()
            } else {
                collapsedProfileIDs.formIntersection(activeProfileIDs)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button { showAddServer = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add Server…")
                    .accessibilityLabel("Add Server")
                    .accessibilityHint("Opens the new server profile form")
                Button { state.showConnections() } label: { Image(systemName: "bolt.horizontal.circle") }
                    .buttonStyle(.borderless)
                    .help("Manage connections")
                    .accessibilityLabel("Manage connections")
                    .accessibilityHint("Shows server profiles and connection controls")
                Spacer()
                Text("\(state.activeProfiles.count) active")
                    .font(.system(size: textMetrics.size(11), weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(state.activeProfiles.count) active server profiles")
            }
            .font(.system(size: textMetrics.size(13)))
            .padding(.horizontal, textMetrics.spacing(13))
            .frame(height: textMetrics.spacing(38))
            .ircBarBackground()
        }
    }

    private func channelAccessibilityValue(_ channel: Conversation) -> String {
        var values: [String] = []
        values.append(channel.hasUnread ? "Unread messages" : "No unread messages")
        if channel.hasMention { values.append("Mentioned you") }
        if state.isFavorite(channel) { values.append("Favorite") }
        return values.joined(separator: ", ")
    }
}

private struct SidebarServerHeader: View {
    let name: String
    let isCollapsible: Bool
    let isCollapsed: Bool
    let activity: IRCServerActivity
    let onToggle: () -> Void
    @Environment(\.ircTextMetrics) private var textMetrics

    var body: some View {
        if isCollapsible {
            Button(action: onToggle) {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: textMetrics.size(9), weight: .semibold))
                        .frame(width: textMetrics.spacing(10))
                    Text(name)
                    Spacer(minLength: 0)
                    if isCollapsed, let indicator = activity.indicator {
                        Image(systemName: indicator == .mention ? "at.circle.fill" : "circle.fill")
                            .font(.system(size: textMetrics.size(indicator == .mention ? 10 : 7), weight: .semibold))
                            .foregroundStyle(indicator == .mention ? Color.accentColor : Color.primary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) server")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isCollapsed ? "Shows this server's conversations" : "Hides this server's conversations")
        } else {
            Text(name)
        }
    }

    private var accessibilityValue: String {
        let disclosureState = isCollapsed ? "Collapsed" : "Expanded"
        guard isCollapsed, let activityDescription = activity.accessibilityDescription else {
            return disclosureState
        }
        return "\(disclosureState), \(activityDescription)"
    }
}

private struct SidebarChannelLabel: View {
    let channel: Conversation
    let isFavorite: Bool

    @Environment(\.ircTextMetrics) private var textMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulseDimmed = false

    var body: some View {
        HStack(spacing: 6) {
            Label(
                channel.name,
                systemImage: channel.hasMention
                    ? "at.circle.fill"
                    : (channel.hasUnread ? "number.circle.fill" : "number.circle")
            )
            .opacity(isPulseDimmed ? 0.42 : 1)

            Spacer(minLength: 0)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: textMetrics.size(10)))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(channel.hasMention ? Color.accentColor : (channel.hasUnread ? Color.primary : Color.secondary))
        .font(.system(size: textMetrics.size(15), weight: channel.hasUnread ? .semibold : .regular))
        .padding(.vertical, textMetrics.spacing(1.5))
        .task(id: channel.hasMention ? channel.mentionRevision : nil) {
            await pulseMention()
        }
    }

    @MainActor
    private func pulseMention() async {
        isPulseDimmed = false
        guard channel.hasMention, !reduceMotion else { return }

        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.5)) {
                isPulseDimmed = true
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                isPulseDimmed = false
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        }
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState
    @Environment(\.ircTextMetrics) private var textMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInvitePulseDimmed = false

    private var unreadInviteCount: Int {
        state.unreadInviteCount(for: profile)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.status(for: profile) == .online ? "circle.inset.filled" : "circle")
                .font(.system(size: textMetrics.size(12)))
                .foregroundStyle(state.status(for: profile).tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.hostname)
                    .font(.system(size: textMetrics.size(15)))
                Text(state.status(for: profile).label)
                    .font(.system(size: textMetrics.size(11)))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if unreadInviteCount > 0 {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: textMetrics.size(13), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isInvitePulseDimmed ? 0.35 : 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, textMetrics.spacing(1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.hostname)
        .accessibilityValue(accessibilityValue)
        .task(id: unreadInviteCount > 0 ? unreadInviteCount : nil) {
            await pulseInvite()
        }
    }

    private var accessibilityValue: String {
        guard unreadInviteCount > 0 else { return state.status(for: profile).label }
        let invitations = unreadInviteCount == 1 ? "channel invitation" : "channel invitations"
        return "\(state.status(for: profile).label), \(unreadInviteCount) unread \(invitations)"
    }

    @MainActor
    private func pulseInvite() async {
        isInvitePulseDimmed = false
        guard unreadInviteCount > 0, !reduceMotion else { return }

        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.5)) {
                isInvitePulseDimmed = true
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                isInvitePulseDimmed = false
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        }
    }
}

private struct ConnectionCenterView: View {
    @ObservedObject var state: IRCAppState
    @Binding var showAddServer: Bool
    @Binding var editingProfile: ServerProfile?

    @Environment(\.ircTextMetrics) private var textMetrics

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: textMetrics.spacing(330), maximum: textMetrics.spacing(480)), spacing: 18)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Connections", systemImage: "bolt.horizontal.circle.fill")
                            .font(.system(size: textMetrics.size(30), weight: .bold))
                            .foregroundStyle(.tint)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose a network to connect, or add a profile for your own server. Active networks and their channels stay focused in the sidebar.")
                            .font(.system(size: textMetrics.size(15)))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Add Server…", systemImage: "plus") { showAddServer = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(textMetrics.scale > 1.15 ? .large : .regular)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Profiles")
                        .font(.system(size: textMetrics.size(20), weight: .semibold))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(state.profiles) { profile in
                            ServerProfileCard(profile: profile, state: state, editingProfile: $editingProfile)
                        }
                    }
                }
            }
            .padding(textMetrics.spacing(32))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ircWindowBackground()
    }
}

private struct ServerProfileCard: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState
    @Binding var editingProfile: ServerProfile?
    @Environment(\.ircTextMetrics) private var textMetrics
    @Environment(\.ircThemePalette) private var themePalette

    private var statusText: String {
        if state.isWaitingToReconnect(profile) { return "Reconnecting" }
        return state.isActive(profile) ? state.status(for: profile).label : "Ready"
    }

    private var statusTint: Color {
        state.isActive(profile) ? state.status(for: profile).tint : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: textMetrics.spacing(16)) {
            HStack(alignment: .top) {
                Image(systemName: profile.useTLS ? "lock.shield.fill" : "network")
                    .font(.system(size: textMetrics.size(20), weight: .medium))
                    .foregroundStyle(profile.useTLS ? Color.accentColor : Color.secondary)
                    .frame(width: textMetrics.spacing(36), height: textMetrics.spacing(36))
                    .background(Color.accentColor.opacity(profile.useTLS ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: textMetrics.size(17), weight: .semibold))
                    Text(profile.hostname)
                        .font(.system(size: textMetrics.size(12)))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(statusText, systemImage: "circle.fill")
                    .font(.system(size: textMetrics.size(11), weight: .medium))
                    .foregroundStyle(statusTint)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusTint.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: textMetrics.spacing(7)) {
                HStack(spacing: 6) {
                    Label(profile.useTLS ? "TLS encrypted" : "Plain-text IRC", systemImage: profile.useTLS ? "lock.fill" : "exclamationmark.triangle")
                    Text(verbatim: "· Port \(profile.port)")
                }
                if let nickname = profile.nicknameOverride, !nickname.isEmpty {
                    Label("Nickname: \(nickname)", systemImage: "person.crop.circle")
                }
                if profile.useSSHTunnel == true, let sshHostname = profile.sshHostname {
                    Label("SSH via \(sshHostname):\(profile.sshPort ?? 22)", systemImage: "point.3.connected.trianglepath.dotted")
                        .lineLimit(1)
                }
            }
            .font(.system(size: textMetrics.size(12)))
            .foregroundStyle(.secondary)

            Divider()
                .ircDivider()

            HStack {
                Spacer()
                Button("Edit…") { editingProfile = profile }
                    .buttonStyle(.bordered)
                if state.isActive(profile) {
                    if case .failed = state.status(for: profile) {
                        Button("Retry") { state.toggleConnection(for: profile) }
                            .buttonStyle(.borderedProminent)
                        Button("Disconnect") { state.disconnect(profile) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Disconnect") { state.toggleConnection(for: profile) }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Connect") { state.toggleConnection(for: profile) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(textMetrics.scale > 1.15 ? .large : .regular)
        }
        .padding(textMetrics.spacing(18))
        .frame(maxWidth: .infinity, minHeight: textMetrics.spacing(168), alignment: .topLeading)
        .ircControlBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if let themePalette {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(themePalette.border, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .contextMenu {
            Button("Edit Profile…") { editingProfile = profile }
            if profile.isBuiltIn && profile.isPresetModified == true {
                Button("Restore Default Profile") { state.restorePreset(profile) }
            }
            if !profile.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) { state.delete(profile) }
            }
        }
    }
}

private struct ConversationView: View {
    @ObservedObject var state: IRCAppState
    let selection: SidebarItem
    @FocusState.Binding var workspaceFocus: IRCWorkspaceFocus?
    @State private var draft = ""
    @State private var tabCompletion: RecipientTabCompletion?
    @State private var commandCompletion: CommandTabCompletion?
    @State private var pendingURL: PendingURL?
    @State private var showsTopic = false
    @Environment(\.ircTextMetrics) private var textMetrics

    private var title: String { state.title(for: selection) }
    private var subtitle: String { state.subtitle(for: selection) }
    private var isChannel: Bool { if case .channel = selection { return true }; return false }
    private var channelTopic: String? { state.topic(for: selection) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: textMetrics.spacing(13)) {
                Image(systemName: selection.icon)
                    .font(.system(size: textMetrics.size(17), weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: textMetrics.spacing(34), height: textMetrics.spacing(34))
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: textMetrics.size(18), weight: .semibold))
                    HStack(spacing: textMetrics.spacing(5)) {
                        Text(subtitle)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let channelTopic {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Button {
                                showsTopic.toggle()
                            } label: {
                                HStack(spacing: textMetrics.spacing(4)) {
                                    Text(IRCMessageTextRenderer.plainText(channelTopic))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: textMetrics.size(8), weight: .semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .layoutPriority(-1)
                            .help("View the full channel topic")
                            .accessibilityLabel("View channel topic")
                            .accessibilityValue(IRCMessageTextRenderer.plainText(channelTopic))
                            .popover(isPresented: $showsTopic, arrowEdge: .bottom) {
                                ChannelTopicPopover(
                                    topic: channelTopic,
                                    rendersIRCFormatting: state.rendersIRCFormatting
                                )
                            }
                        }
                    }
                    .font(.system(size: textMetrics.size(12)))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, textMetrics.spacing(22))
            .padding(.vertical, textMetrics.spacing(13))
            .ircBarBackground()

            Divider()
                .ircDivider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ConversationTranscript(
                        state: state,
                        selection: selection,
                        chatFont: state.chatFont,
                        usesColoredNicknames: state.usesColoredNicknames,
                        usesMonospacedServerMessages: state.usesMonospacedServerMessages,
                        rendersIRCFormatting: state.rendersIRCFormatting,
                        automaticallyPreviewsLinks: state.automaticallyPreviewsLinks,
                        automaticallyPreviewsImages: state.automaticallyPreviewsImages,
                        messageSpacing: state.messageSpacing,
                        channelEventVisibility: state.channelEventVisibility
                    )
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Message \(title)", text: $draft, axis: .vertical)
                            .font(state.chatFont.font(size: textMetrics.size(15)))
                            .textFieldStyle(.plain).lineLimit(1...5)
                            .padding(.horizontal, textMetrics.spacing(12))
                            .padding(.vertical, textMetrics.spacing(9))
                            .ircFieldBackground(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($workspaceFocus, equals: .composer(selection))
                            .accessibilityLabel("Message to \(title)")
                            .accessibilityHint("Type one IRC message. Press Return to send or Tab to complete a command or nickname.")
                            .onSubmit(send)
                            .onKeyPress(.tab) {
                                completeComposer()
                                    ? .handled
                                    : .ignored
                            }
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: textMetrics.size(14), weight: .bold))
                                .frame(width: textMetrics.spacing(30), height: textMetrics.spacing(30))
                        }
                        .buttonStyle(.borderedProminent).clipShape(Circle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send message")
                        .accessibilityHint("Sends the message to \(title)")
                    }
                    .padding(.horizontal, textMetrics.spacing(20))
                    .padding(.vertical, textMetrics.spacing(14))
                    .ircBarBackground()
                }
                if isChannel && state.showsMemberList {
                    Divider()
                        .ircDivider()
                    ChannelMemberList(state: state, selection: selection)
                }
            }
        }
        .onAppear {
            state.markRead(selection)
            draft = state.draft(for: selection)
            workspaceFocus = .composer(selection)
        }
        .onChange(of: selection) { _, newSelection in
            state.markRead(newSelection)
            tabCompletion = nil
            commandCompletion = nil
        }
        .onChange(of: draft) { _, newDraft in
            state.setDraft(newDraft, for: selection)
            if tabCompletion?.completedDraft != newDraft {
                tabCompletion = nil
            }
            if commandCompletion?.completedDraft != newDraft {
                commandCompletion = nil
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            openURL(url)
            return .handled
        })
        .sheet(item: $pendingURL) { pendingURL in
            LinkWarningView(
                url: pendingURL.url,
                onCancel: { self.pendingURL = nil },
                onOpen: { dontShowAgain in
                    if dontShowAgain {
                        state.warnBeforeOpeningLinks = false
                    }
                    self.pendingURL = nil
                    NSWorkspace.shared.open(pendingURL.url)
                }
            )
        }
    }

    private func openURL(_ url: URL) {
        if let channel = IRCInternalLink.channelName(from: url) {
            state.joinChannel(named: channel, from: selection)
            return
        }
        guard Self.isWebURL(url) else { return }
        if state.warnBeforeOpeningLinks {
            pendingURL = PendingURL(url: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.send(text, to: selection)
        draft = ""
    }

    private func completeComposer() -> Bool {
        completeCommand() || completeRecipient()
    }

    private func completeCommand() -> Bool {
        guard draft.first == "/" else { return false }
        let commandStart = draft.index(after: draft.startIndex)
        guard commandStart <= draft.endIndex,
              !draft[commandStart...].contains(where: { $0.isWhitespace }) else { return false }

        let commandRange = commandStart..<draft.endIndex
        if var completion = commandCompletion,
           completion.completedDraft == draft,
           !completion.candidates.isEmpty {
            completion.index = (completion.index + 1) % completion.candidates.count
            draft.replaceSubrange(commandRange, with: completion.candidates[completion.index].lowercased())
            completion.completedDraft = draft
            commandCompletion = completion
            return true
        }

        let prefix = draft[commandRange].uppercased()
        let candidates = Self.supportedCommands.filter { $0.hasPrefix(prefix) }
        guard let firstCandidate = candidates.first else { return false }
        draft.replaceSubrange(commandRange, with: firstCandidate.lowercased())
        commandCompletion = CommandTabCompletion(
            candidates: candidates,
            index: 0,
            completedDraft: draft
        )
        return true
    }

    private static let supportedCommands = [
        "AWAY", "CTCP", "DISCONNECT", "INVITE", "JOIN", "KICK", "KILL", "LIST", "ME",
        "MODE", "MOTD", "MSG", "MUTE", "NAMES", "NICK", "NOTICE", "PART",
        "QUERY", "QUIT", "SHOWMUTES", "SLAP", "TOPIC", "UNMUTE", "VERSION",
        "WHO", "WHOIS"
    ]

    private func completeRecipient() -> Bool {
        guard isChannel, let context = recipientCompletionContext(in: draft) else { return false }

        if var completion = tabCompletion,
           completion.command == context.command,
           completion.completedDraft == draft,
           !completion.candidates.isEmpty {
            completion.index = (completion.index + 1) % completion.candidates.count
            draft.replaceSubrange(context.range, with: completion.candidates[completion.index])
            completion.completedDraft = draft
            tabCompletion = completion
            return true
        }

        let candidates = state.members(for: selection)
            .map(\.nickname)
            .filter { $0.lowercased().hasPrefix(context.prefix.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let firstCandidate = candidates.first else { return false }

        draft.replaceSubrange(context.range, with: firstCandidate)
        tabCompletion = RecipientTabCompletion(
            command: context.command,
            candidates: candidates,
            index: 0,
            completedDraft: draft
        )
        return true
    }

    private func recipientCompletionContext(in input: String) -> RecipientCompletionContext? {
        guard input.first == "/" else { return nil }
        let commandStart = input.index(after: input.startIndex)
        guard commandStart < input.endIndex else { return nil }
        let commandEnd = input[commandStart...].firstIndex(where: { $0.isWhitespace }) ?? input.endIndex
        let command = String(input[commandStart..<commandEnd]).uppercased()
        guard commandEnd < input.endIndex,
              let recipientIndex = recipientArgumentIndex(for: command) else { return nil }

        var tokens: [(text: String, range: Range<String.Index>)] = []
        var index = commandEnd
        while index < input.endIndex {
            while index < input.endIndex, input[index].isWhitespace {
                index = input.index(after: index)
            }
            guard index < input.endIndex else { break }
            let start = index
            while index < input.endIndex, !input[index].isWhitespace {
                index = input.index(after: index)
            }
            tokens.append((String(input[start..<index]), start..<index))
        }

        guard tokens.count == recipientIndex || tokens.count == recipientIndex + 1 else { return nil }
        if tokens.count == recipientIndex + 1 {
            let token = tokens[recipientIndex]
            return RecipientCompletionContext(command: command, prefix: token.text, range: token.range)
        }
        return RecipientCompletionContext(command: command, prefix: "", range: input.endIndex..<input.endIndex)
    }

    private func recipientArgumentIndex(for command: String) -> Int? {
        switch command {
        case "SLAP", "MSG", "QUERY", "NOTICE", "WHOIS", "CTCP", "VERSION", "MUTE", "UNMUTE", "INVITE", "KILL", "WHO", "MODE":
            return 0
        case "KICK":
            return 1
        default:
            return nil
        }
    }
}

private struct ChannelTopicPopover: View {
    let topic: String
    let rendersIRCFormatting: Bool

    private var renderedTopic: AttributedString {
        IRCMessageTextRenderer.linkifiedText(
            for: IRCMessage(sender: "", text: topic),
            rendersIRCFormatting: rendersIRCFormatting
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Channel Topic", systemImage: "text.quote")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(renderedTopic)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Copy Topic", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        IRCMessageTextRenderer.plainText(topic),
                        forType: .string
                    )
                }
            }
        }
        .padding(18)
        .frame(width: 440, alignment: .leading)
    }
}

private struct ConversationTranscript: View {
    let state: IRCAppState
    let selection: SidebarItem
    let chatFont: IRCChatFont
    let usesColoredNicknames: Bool
    let usesMonospacedServerMessages: Bool
    let rendersIRCFormatting: Bool
    let automaticallyPreviewsLinks: Bool
    let automaticallyPreviewsImages: Bool
    let messageSpacing: IRCMessageSpacing
    let channelEventVisibility: IRCChannelEventVisibility
    @ObservedObject private var updates: IRCRevisionSignal
    @State private var isFollowingTail = true
    @State private var hasPositionedInitialMessages = false
    @State private var lastAnimatedScroll = Date.distantPast
    @State private var visibleMessageLimit = IRCTranscriptPresentationPolicy.initialVisibleMessageLimit
    @Environment(\.ircTextMetrics) private var textMetrics

    private enum ScrollTarget: Hashable {
        case tail
    }

    init(
        state: IRCAppState,
        selection: SidebarItem,
        chatFont: IRCChatFont,
        usesColoredNicknames: Bool,
        usesMonospacedServerMessages: Bool,
        rendersIRCFormatting: Bool,
        automaticallyPreviewsLinks: Bool,
        automaticallyPreviewsImages: Bool,
        messageSpacing: IRCMessageSpacing,
        channelEventVisibility: IRCChannelEventVisibility
    ) {
        self.state = state
        self.selection = selection
        self.chatFont = chatFont
        self.usesColoredNicknames = usesColoredNicknames
        self.usesMonospacedServerMessages = usesMonospacedServerMessages
        self.rendersIRCFormatting = rendersIRCFormatting
        self.automaticallyPreviewsLinks = automaticallyPreviewsLinks
        self.automaticallyPreviewsImages = automaticallyPreviewsImages
        self.messageSpacing = messageSpacing
        self.channelEventVisibility = channelEventVisibility
        _updates = ObservedObject(wrappedValue: state.messageUpdates(for: selection))
    }

    var body: some View {
        let _ = updates.revision
        let allMessages = state.messages(
            for: selection,
            channelEventVisibility: channelEventVisibility
        )
        let messages = allMessages.suffix(visibleMessageLimit)
        let hiddenMessageCount = allMessages.count - messages.count
        let lastMessageID = messages.last?.id

        ScrollViewReader { scrollView in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: messageSpacing == .compact ? 0 : textMetrics.spacing(3)
                ) {
                    if hiddenMessageCount > 0 {
                        Button {
                            let previousFirstMessageID = messages.first?.id
                            visibleMessageLimit = IRCTranscriptPresentationPolicy.expandedVisibleMessageLimit(
                                current: visibleMessageLimit,
                                total: allMessages.count
                            )
                            guard let previousFirstMessageID else { return }
                            Task { @MainActor in
                                await Task.yield()
                                scrollView.scrollTo(previousFirstMessageID, anchor: .top)
                            }
                        } label: {
                            Label(
                                "Load \(min(hiddenMessageCount, IRCTranscriptPresentationPolicy.earlierMessagePageSize)) earlier messages",
                                systemImage: "arrow.up"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: textMetrics.size(13), weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, textMetrics.spacing(8))
                        .accessibilityHint("Keeps the current reading position")
                    }

                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            state: state,
                            selection: selection,
                            chatFont: chatFont,
                            usesColoredNicknames: usesColoredNicknames,
                            usesMonospacedServerMessages: usesMonospacedServerMessages,
                            rendersIRCFormatting: rendersIRCFormatting,
                            automaticallyPreviewsLinks: automaticallyPreviewsLinks,
                            automaticallyPreviewsImages: automaticallyPreviewsImages,
                            messageSpacing: messageSpacing
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, textMetrics.spacing(24))
                .padding(.top, textMetrics.spacing(18))
                .background {
                    TranscriptLiveScrollObserver { visibleBounds, contentBounds, contentIsFlipped in
                        guard hasPositionedInitialMessages else { return }
                        guard let newValue = IRCTranscriptScrollPolicy.followingTailChange(
                            from: isFollowingTail,
                            visibleBounds: visibleBounds,
                            contentBounds: contentBounds,
                            contentIsFlipped: contentIsFlipped
                        ) else { return }
                        isFollowingTail = newValue
                    }
                }
                Color.clear
                    .frame(height: textMetrics.spacing(18))
                    .id(ScrollTarget.tail)
            }
            .accessibilityAddTraits(.updatesFrequently)
            .defaultScrollAnchor(.bottom)
            .ircCustomWindowBackground()
            .accessibilityLabel("Conversation messages")
            .task(id: lastMessageID) {
                guard lastMessageID != nil else { return }
                guard hasPositionedInitialMessages else {
                    hasPositionedInitialMessages = true
                    await Task.yield()
                    scrollView.scrollTo(ScrollTarget.tail, anchor: .bottom)
                    return
                }
                guard isFollowingTail else { return }

                // Collapse bursts into one tail update after traffic briefly settles.
                // This avoids overlapping animations and repeated lazy-stack ID scans.
                do {
                    try await Task.sleep(for: IRCTranscriptScrollPolicy.coalescingDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled, isFollowingTail else { return }

                let now = Date()
                if IRCTranscriptScrollPolicy.shouldAnimate(lastAnimatedScroll: lastAnimatedScroll, now: now) {
                    lastAnimatedScroll = now
                    withAnimation(.easeOut(duration: IRCTranscriptScrollPolicy.animationDuration)) {
                        scrollView.scrollTo(ScrollTarget.tail, anchor: .bottom)
                    }
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollView.scrollTo(ScrollTarget.tail, anchor: .bottom)
                    }
                }
            }
        }
    }
}

/// Reports only live, user-driven scrolling. Transcript layout changes and
/// programmatic tail scrolling must not be mistaken for the reader scrolling up.
private struct TranscriptLiveScrollObserver: NSViewRepresentable {
    let onScroll: (_ visibleBounds: CGRect, _ contentBounds: CGRect, _ contentIsFlipped: Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onScroll: onScroll)
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onScroll = onScroll
        nsView.attachToEnclosingScrollViewIfNeeded()
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator: ()) {
        nsView.detach()
    }

    final class ObserverView: NSView {
        var onScroll: (_ visibleBounds: CGRect, _ contentBounds: CGRect, _ contentIsFlipped: Bool) -> Void
        private weak var observedScrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var attachmentGeneration = 0
        private var hasPendingReport = false

        init(onScroll: @escaping (_ visibleBounds: CGRect, _ contentBounds: CGRect, _ contentIsFlipped: Bool) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachToEnclosingScrollViewIfNeeded()
            if observedScrollView == nil, window != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.attachToEnclosingScrollViewIfNeeded()
                }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func attachToEnclosingScrollViewIfNeeded() {
            guard let scrollView = enclosingScrollView,
                  scrollView !== observedScrollView else { return }
            detach()
            observedScrollView = scrollView
            let center = NotificationCenter.default
            for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
                observers.append(center.addObserver(
                    forName: name,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    self?.schedulePositionReport()
                })
            }
        }

        func detach() {
            attachmentGeneration &+= 1
            hasPendingReport = false
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
            observedScrollView = nil
        }

        /// AppKit can post live-scroll notifications while the scroll view is
        /// still in its layout pass. Publishing SwiftUI state from that stack
        /// can make the hosting view try to lay out recursively, so defer and
        /// coalesce the report until the next main-queue turn.
        private func schedulePositionReport() {
            guard !hasPendingReport else { return }
            hasPendingReport = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                self.hasPendingReport = false
                self.reportPosition()
            }
        }

        private func reportPosition() {
            guard let scrollView = observedScrollView,
                  let documentView = scrollView.documentView else { return }
            onScroll(
                scrollView.contentView.documentVisibleRect,
                documentView.bounds,
                documentView.isFlipped
            )
        }

        deinit {
            detach()
        }
    }
}

private struct RecipientCompletionContext {
    let command: String
    let prefix: String
    let range: Range<String.Index>
}

private struct RecipientTabCompletion {
    let command: String
    let candidates: [String]
    var index: Int
    var completedDraft: String
}

private struct CommandTabCompletion {
    let candidates: [String]
    var index: Int
    var completedDraft: String
}

private struct ChannelMemberList: View {
    @ObservedObject var state: IRCAppState
    let selection: SidebarItem
    @ObservedObject private var updates: IRCRevisionSignal
    @State private var search = ""
    @Environment(\.ircTextMetrics) private var textMetrics

    init(state: IRCAppState, selection: SidebarItem) {
        self.state = state
        self.selection = selection
        _updates = ObservedObject(wrappedValue: state.memberUpdates(for: selection))
    }

    private func filteredMembers(from members: [ChannelMember]) -> [ChannelMember] {
        guard !search.isEmpty else { return members }
        return members.filter { $0.nickname.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let _ = updates.revision
        let members = state.members(for: selection)
        let muteSnapshot = state.muteSnapshot(for: selection)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Members")
                    .font(.system(size: textMetrics.size(16), weight: .semibold))
                Spacer()
                Text("\(members.count)")
                    .font(.system(size: textMetrics.size(11), design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, textMetrics.spacing(16))
            .padding(.top, textMetrics.spacing(15))
            .padding(.bottom, textMetrics.spacing(10))

            TextField("Filter members", text: $search)
                .font(.system(size: textMetrics.size(13)))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, textMetrics.spacing(12))
                .padding(.bottom, textMetrics.spacing(10))

            Divider()
                .ircDivider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredMembers(from: members)) { member in
                        ChannelMemberRow(
                            member: member,
                            isMuted: muteSnapshot?.contains(member.nickname) ?? false,
                            state: state,
                            selection: selection
                        )
                    }
                }
                .padding(.vertical, textMetrics.spacing(5))
            }
        }
        .frame(
            minWidth: textMetrics.spacing(210),
            idealWidth: textMetrics.spacing(238),
            maxWidth: textMetrics.spacing(310)
        )
        .ircBarBackground()
    }
}

private struct ChannelMemberRow: View {
    let member: ChannelMember
    let isMuted: Bool
    let state: IRCAppState
    let selection: SidebarItem
    @State private var isHovered = false
    @Environment(\.ircTextMetrics) private var textMetrics

    var body: some View {
        HStack(spacing: textMetrics.spacing(8)) {
            Group {
                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: textMetrics.size(10)))
                } else {
                    Text(member.prefix.map(String.init) ?? "")
                        .font(.system(size: textMetrics.size(12), weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(member.role == nil || isMuted ? Color.secondary : Color.accentColor)
            .frame(width: textMetrics.spacing(14), alignment: .center)

            Text(member.nickname)
                .font(.system(size: textMetrics.size(14)))
                .foregroundStyle(isMuted ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let role = member.role {
                Text(role)
                    .font(.system(size: textMetrics.size(10), weight: .medium))
                    .padding(.horizontal, textMetrics.spacing(6))
                    .padding(.vertical, textMetrics.spacing(2))
                    .ircBadgeStyle()
            }
        }
        .padding(.horizontal, textMetrics.spacing(12))
        .padding(.vertical, textMetrics.spacing(6))
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, textMetrics.spacing(5))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            startDirectMessage()
        }
        .focusable()
        .onKeyPress(.return) {
            startDirectMessage()
            return .handled
        }
        .onKeyPress(.space) {
            startDirectMessage()
            return .handled
        }
        .contextMenu {
            NicknameContextMenu(
                nickname: member.nickname,
                isMuted: isMuted,
                state: state,
                selection: selection
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(member.role.map { "\(member.nickname), \($0)" } ?? member.nickname)
        .accessibilityValue(isMuted ? "Muted" : "Not muted")
        .accessibilityHint("Starts a private message")
        .accessibilityAction {
            startDirectMessage()
        }
        .accessibilityAction(named: "View Whois") {
            state.requestWhois(for: member.nickname, from: selection)
        }
        .accessibilityAction(named: isMuted ? "Unmute" : "Mute") {
            if isMuted {
                state.unmute(member.nickname, from: selection)
            } else {
                state.mute(member.nickname, from: selection)
            }
        }
    }

    private func startDirectMessage() {
        state.startDirectMessage(with: member.nickname, from: selection)
    }
}

private struct NicknameContextMenu: View {
    let nickname: String
    let isMuted: Bool
    let state: IRCAppState
    let selection: SidebarItem

    var body: some View {
        Button("Message \(nickname)", systemImage: "message") {
            state.startDirectMessage(with: nickname, from: selection)
        }
        Button("Whois \(nickname)", systemImage: "person.text.rectangle") {
            state.requestWhois(for: nickname, from: selection)
        }
        Divider()
        if isMuted {
            Button("Unmute \(nickname)", systemImage: "speaker.wave.2") {
                state.unmute(nickname, from: selection)
            }
        } else {
            Button("Mute \(nickname)", systemImage: "speaker.slash") {
                state.mute(nickname, from: selection)
            }
        }
        if state.canModerate(nickname, in: selection) {
            Divider()
            Button("Kick \(nickname)", systemImage: "rectangle.portrait.and.arrow.right") {
                state.kick(nickname, from: selection)
            }
            Button("Ban \(nickname)", systemImage: "nosign") {
                state.ban(nickname, from: selection)
            }
        }
    }
}

private struct MessageRow: View {
    let message: IRCMessage
    let state: IRCAppState
    let selection: SidebarItem
    let chatFont: IRCChatFont
    let usesColoredNicknames: Bool
    let usesMonospacedServerMessages: Bool
    let rendersIRCFormatting: Bool
    let automaticallyPreviewsLinks: Bool
    let automaticallyPreviewsImages: Bool
    let messageSpacing: IRCMessageSpacing
    @State private var isSenderHovered = false
    @State private var showsFullSender = false
    @Environment(\.ircTextMetrics) private var textMetrics
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.ircThemePalette) private var themePalette

    private var timestampFontSize: CGFloat { textMetrics.size(11) }
    private var timestampColumnWidth: CGFloat { textMetrics.spacing(64) }
    private var senderColumnWidth: CGFloat { textMetrics.spacing(116) }

    var body: some View {
        let previews = IRCMessagePreviewPolicy.previews(
            for: message,
            in: selection,
            showsLinkPreviews: automaticallyPreviewsLinks,
            showsImagePreviews: automaticallyPreviewsImages
        )

        HStack(alignment: .firstTextBaseline, spacing: textMetrics.spacing(8)) {
            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: timestampFontSize, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: timestampColumnWidth, alignment: .trailing)

            if message.isSystem {
                VStack(alignment: .leading, spacing: textMetrics.spacing(8)) {
                    HStack(alignment: .firstTextBaseline, spacing: textMetrics.spacing(10)) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: textMetrics.size(5)))
                            .foregroundStyle(.tertiary)
                            .frame(width: textMetrics.spacing(10))
                            .accessibilityHidden(true)
                        Text(linkifiedText)
                            .font(serverMessageFont)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    MessagePreviewStack(previews: previews)
                        .padding(.leading, textMetrics.spacing(20))
                }
            } else {
                VStack(alignment: .leading, spacing: textMetrics.spacing(8)) {
                    HStack(alignment: .firstTextBaseline, spacing: textMetrics.spacing(10)) {
                        interactiveSenderText
                            .onHover { isHovered in
                                isSenderHovered = isHovered
                                if !isHovered { showsFullSender = false }
                            }
                            .task(id: isSenderHovered) {
                                guard isSenderHovered, isSenderTruncated else { return }
                                try? await Task.sleep(for: .milliseconds(400))
                                guard !Task.isCancelled, isSenderHovered else { return }
                                showsFullSender = true
                            }
                            .popover(isPresented: $showsFullSender, arrowEdge: .bottom) {
                                Text(message.sender)
                                    .font(chatFont.font(size: textMetrics.size(13), weight: .medium))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, textMetrics.spacing(11))
                                    .padding(.vertical, textMetrics.spacing(7))
                            }
                        Text(linkifiedText)
                            .font(chatFont.font(size: textMetrics.bodySize))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    MessagePreviewStack(previews: previews)
                        .padding(.leading, senderColumnWidth + textMetrics.spacing(10))
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: previews.isEmpty ? .combine : .contain)
        .accessibilityLabel(accessibilityText)
    }

    private static let attributedTextCache = IRCMessageTextCache(countLimit: 5_500)

    private var serverMessageFont: Font {
        let design: Font.Design = usesMonospacedServerMessages ? .monospaced : chatFont.design
        return .system(size: textMetrics.size(14), design: design)
    }

    @ViewBuilder
    private var interactiveSenderText: some View {
        if let nickname = message.interactiveNickname {
            senderText.contextMenu {
                NicknameContextMenu(
                    nickname: nickname,
                    isMuted: state.isMuted(nickname, from: selection),
                    state: state,
                    selection: selection
                )
            }
        } else {
            senderText
        }
    }

    private var senderText: some View {
        Text(message.sender)
            .font(chatFont.font(size: textMetrics.size(15), weight: .semibold))
            .foregroundStyle(nicknameColor)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: senderColumnWidth, alignment: .leading)
    }

    private var isSenderTruncated: Bool {
        IRCNicknameTruncationPolicy.isTruncated(
            message.sender,
            availableWidth: senderColumnWidth,
            font: chatFont.nsFont(size: textMetrics.size(15), weight: .semibold)
        )
    }

    private var linkifiedText: AttributedString {
        Self.attributedTextCache.attributedText(
            for: message,
            rendersIRCFormatting: rendersIRCFormatting
        )
    }

    private var accessibilityText: String {
        let time = message.timestamp.formatted(date: .omitted, time: .shortened)
        let sender = IRCMessageTextRenderer.plainText(message.sender)
        let text = IRCMessageTextRenderer.plainText(message.text)
        return "\(time), \(sender): \(text)"
    }

    private var verticalPadding: CGFloat {
        guard messageSpacing == .comfortable else { return 0 }
        return textMetrics.spacing(message.isSystem ? 1 : 2)
    }

    private var nicknameColor: Color {
        guard usesColoredNicknames else { return .accentColor }
        let palette = themePalette?.nicknameColors
            ?? (colorScheme == .dark ? Self.darkNicknamePalette : Self.lightNicknamePalette)
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in message.resolvedNicknameColorKey.lowercased().unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    // Tailwind's 700/800 shades remain readable on light backgrounds, while
    // the corresponding 300 shades preserve contrast in dark appearance.
    private static let lightNicknamePalette: [Color] = [
        Color(red: 0.114, green: 0.306, blue: 0.847),
        Color(red: 0.494, green: 0.133, blue: 0.808),
        Color(red: 0.604, green: 0.204, blue: 0.071),
        Color(red: 0.745, green: 0.094, blue: 0.365),
        Color(red: 0.086, green: 0.396, blue: 0.204),
        Color(red: 0.263, green: 0.220, blue: 0.792),
        Color(red: 0.067, green: 0.369, blue: 0.349),
        Color(red: 0.725, green: 0.110, blue: 0.110)
    ]

    private static let darkNicknamePalette: [Color] = [
        Color(red: 0.576, green: 0.773, blue: 0.992),
        Color(red: 0.847, green: 0.706, blue: 0.996),
        Color(red: 0.992, green: 0.729, blue: 0.455),
        Color(red: 0.976, green: 0.659, blue: 0.831),
        Color(red: 0.525, green: 0.937, blue: 0.675),
        Color(red: 0.647, green: 0.706, blue: 0.988),
        Color(red: 0.369, green: 0.918, blue: 0.831),
        Color(red: 0.988, green: 0.647, blue: 0.647)
    ]

}

enum IRCNicknameTruncationPolicy {
    static func isTruncated(
        _ nickname: String,
        availableWidth: CGFloat,
        fontSize: CGFloat
    ) -> Bool {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return isTruncated(nickname, availableWidth: availableWidth, font: font)
    }

    static func isTruncated(
        _ nickname: String,
        availableWidth: CGFloat,
        font: NSFont
    ) -> Bool {
        guard availableWidth > 0, !nickname.isEmpty else { return false }
        let renderedWidth = (nickname as NSString).size(withAttributes: [.font: font]).width
        return renderedWidth.rounded(.up) > availableWidth.rounded(.down)
    }
}

private struct PendingURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LinkWarningView: View {
    let url: URL
    let onCancel: () -> Void
    let onOpen: (Bool) -> Void
    @State private var dontShowAgain = false
    @Environment(\.ircThemePalette) private var themePalette

    private var destination: String {
        url.host(percentEncoded: true) ?? url.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Open External Link?")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Links in IRC messages can lead to deceptive or malicious content. Only continue if you trust the sender and destination.")
                        .ircWarningSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(destination)
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .modifier(LinkWarningURLTextModifier())
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ircEmphasizedCallout(in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Toggle("Don’t show this warning again", isOn: $dontShowAgain)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if let themePalette {
                    Button { onOpen(dontShowAgain) } label: {
                        Text("Open Link")
                            .foregroundStyle(themePalette.prominentButtonText)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Link") { onOpen(dontShowAgain) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 490)
    }
}

private struct LinkWarningURLTextModifier: ViewModifier {
    @Environment(\.ircThemePalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if let palette {
            content.foregroundStyle(palette.emphasizedText)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView(state: IRCAppState()).frame(width: 1150, height: 720)
}
