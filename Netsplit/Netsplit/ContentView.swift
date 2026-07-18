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

    private var textMetrics: IRCTextMetrics { IRCTextMetrics(bodySize: state.transcriptFontSize) }
    private var hasSelectedChannel: Bool {
        guard let selection = state.selection else { return false }
        if case .channel = selection { return true }
        return false
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(state: state, showAddServer: $showAddServer, editingProfile: $editingProfile)
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
                    ConversationView(state: state, selection: selection)
                        .id(selection)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.selectedProfile != nil {
                        Button { state.requestChannelListing() } label: {
                            Label("Browse channels", systemImage: "list.bullet.rectangle")
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
    }
}

private struct SidebarView: View {
    @ObservedObject var state: IRCAppState
    @Binding var showAddServer: Bool
    @Binding var editingProfile: ServerProfile?
    @State private var listSelection: SidebarItem?
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

                    ForEach(state.channels(for: profile)) { channel in
                        HStack(spacing: 6) {
                            Label(channel.name, systemImage: channel.hasUnread ? "number.circle.fill" : "number.circle")
                            Spacer(minLength: 0)
                            if state.isFavorite(channel) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(channel.name)
                            .accessibilityValue(channelAccessibilityValue(channel))
                            .foregroundStyle(channel.hasUnread ? .primary : .secondary)
                            .font(.system(size: textMetrics.size(15), weight: channel.hasUnread ? .semibold : .regular))
                            .padding(.vertical, textMetrics.spacing(1.5))
                            .tag(SidebarItem.channel(channel.id))
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
                } header: {
                    Text(profile.name)
                        .font(.system(size: textMetrics.size(11), weight: .semibold))
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { listSelection = state.selection }
        .onChange(of: listSelection) { _, newSelection in
            DispatchQueue.main.async { state.selection = newSelection }
        }
        .onChange(of: state.selection) { _, newSelection in
            if listSelection != newSelection { listSelection = newSelection }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button { showAddServer = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add server")
                    .accessibilityLabel("Add server")
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
            .background(.bar)
        }
    }

    private func channelAccessibilityValue(_ channel: Conversation) -> String {
        var values: [String] = []
        values.append(channel.hasUnread ? "Unread messages" : "No unread messages")
        if state.isFavorite(channel) { values.append("Favorite") }
        return values.joined(separator: ", ")
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState
    @Environment(\.ircTextMetrics) private var textMetrics

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
        }
        .padding(.vertical, textMetrics.spacing(1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.hostname)
        .accessibilityValue(state.status(for: profile).label)
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
                    Button("Add Server", systemImage: "plus") { showAddServer = true }
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ServerProfileCard: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState
    @Binding var editingProfile: ServerProfile?
    @Environment(\.ircTextMetrics) private var textMetrics

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

            HStack {
                Spacer()
                Button("Edit") { editingProfile = profile }
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
    @State private var draft = ""
    @State private var tabCompletion: RecipientTabCompletion?
    @State private var pendingURL: PendingURL?
    @FocusState private var composerFocused: Bool
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
                            .fixedSize(horizontal: true, vertical: false)
                        if let channelTopic {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(channelTopic)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(-1)
                                .help(channelTopic)
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
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: textMetrics.spacing(3)) {
                                ForEach(state.messages(for: selection)) { message in
                                    MessageRow(message: message).id(message.id)
                                }
                            }
                            .padding(.horizontal, textMetrics.spacing(24))
                            .padding(.vertical, textMetrics.spacing(18))
                            .accessibilityAddTraits(.updatesFrequently)
                        }
                        .accessibilityLabel("Conversation messages")
                        .onAppear {
                            scrollToLatest(using: proxy)
                        }
                        .onChange(of: state.messageRevision) {
                            scrollToLatest(using: proxy)
                        }
                        .onChange(of: selection) {
                            scrollToLatest(using: proxy)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Message \(title)", text: $draft, axis: .vertical)
                            .font(.system(size: textMetrics.size(15)))
                            .textFieldStyle(.plain).lineLimit(1...5)
                            .padding(.horizontal, textMetrics.spacing(12))
                            .padding(.vertical, textMetrics.spacing(9))
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($composerFocused)
                            .accessibilityLabel("Message to \(title)")
                            .accessibilityHint("Type a message. Press Return to send. In commands with a nickname, press Tab to complete the nickname.")
                            .onSubmit(send)
                            .onKeyPress(.tab) {
                                completeRecipient()
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
                    .background(.bar)
                }
                if isChannel && state.showsMemberList {
                    Divider()
                    ChannelMemberList(members: state.members(for: selection), state: state, selection: selection)
                }
            }
        }
        .onAppear {
            state.markRead(selection)
            composerFocused = true
        }
        .onChange(of: selection) { _, newSelection in
            state.markRead(newSelection)
            tabCompletion = nil
        }
        .onChange(of: draft) { _, newDraft in
            if tabCompletion?.completedDraft != newDraft {
                tabCompletion = nil
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

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = state.messages(for: selection).last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

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

private struct ChannelMemberList: View {
    let members: [ChannelMember]
    @ObservedObject var state: IRCAppState
    let selection: SidebarItem
    @State private var search = ""
    @Environment(\.ircTextMetrics) private var textMetrics

    private var filteredMembers: [ChannelMember] {
        guard !search.isEmpty else { return members }
        return members.filter { $0.nickname.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredMembers) { member in
                        ChannelMemberRow(member: member, state: state, selection: selection)
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
        .background(.bar)
    }
}

private struct ChannelMemberRow: View {
    let member: ChannelMember
    @ObservedObject var state: IRCAppState
    let selection: SidebarItem
    @State private var isHovered = false
    @Environment(\.ircTextMetrics) private var textMetrics

    private var isMuted: Bool { state.isMuted(member.nickname, from: selection) }

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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, textMetrics.spacing(6))
                    .padding(.vertical, textMetrics.spacing(2))
                    .background(.quaternary, in: Capsule())
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
            Button("Message \(member.nickname)", systemImage: "message") {
                state.startDirectMessage(with: member.nickname, from: selection)
            }
            Button("Whois \(member.nickname)", systemImage: "person.text.rectangle") {
                state.requestWhois(for: member.nickname, from: selection)
            }
            Divider()
            if isMuted {
                Button("Unmute \(member.nickname)", systemImage: "speaker.wave.2") {
                    state.unmute(member.nickname, from: selection)
                }
            } else {
                Button("Mute \(member.nickname)", systemImage: "speaker.slash") {
                    state.mute(member.nickname, from: selection)
                }
            }
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

private struct MessageRow: View {
    let message: IRCMessage
    @Environment(\.ircTextMetrics) private var textMetrics

    private var timestampFontSize: CGFloat { textMetrics.size(11) }
    private var timestampColumnWidth: CGFloat { textMetrics.spacing(64) }
    private var senderColumnWidth: CGFloat { textMetrics.spacing(116) }

    private var systemText: String {
        let genericSenders = ["System", "•"]
        return genericSenders.contains(message.sender) ? message.text : "\(message.sender) \(message.text)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: textMetrics.spacing(10)) {
            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: timestampFontSize, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: timestampColumnWidth, alignment: .trailing)

            if message.isSystem {
                Image(systemName: "circle.fill")
                    .font(.system(size: textMetrics.size(5)))
                    .foregroundStyle(.tertiary)
                    .frame(width: textMetrics.spacing(10))
                    .accessibilityHidden(true)
                Text(linkified(systemText))
                    .font(.system(size: textMetrics.size(14)))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(message.sender)
                    .font(.system(size: textMetrics.size(15), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: senderColumnWidth, alignment: .leading)
                    .help(message.sender)
                Text(linkifiedText)
                    .font(.system(size: textMetrics.bodySize))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, textMetrics.spacing(message.isSystem ? 1 : 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.timestamp.formatted(date: .omitted, time: .shortened)), \(message.sender): \(message.text)")
    }

    private var linkifiedText: AttributedString { linkified(message.text) }

    private func linkified(_ text: String) -> AttributedString {
        var attributedText = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributedText
        }

        let fullRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: fullRange) {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: attributedText) else { continue }
            attributedText[attributedRange].link = url
        }
        return attributedText
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

    private var destination: String {
        url.host(percentEncoded: false) ?? url.absoluteString
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
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(destination)
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Toggle("Don’t show this warning again", isOn: $dontShowAgain)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Open Link") { onOpen(dontShowAgain) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 490)
    }
}

#Preview {
    ContentView(state: IRCAppState()).frame(width: 1150, height: 720)
}
