//
//  ContentView.swift
//  Netsplit
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var state: IRCAppState
    @State private var showAddServer = false
    @State private var editingProfile: ServerProfile?

    var body: some View {
        NavigationSplitView {
            SidebarView(state: state, showAddServer: $showAddServer, editingProfile: $editingProfile)
                .navigationSplitViewColumnWidth(min: 218, ideal: 250, max: 320)
        } detail: {
            Group {
                if state.selection == .connectionCenter || state.selection == nil {
                    ConnectionCenterView(state: state, showAddServer: $showAddServer, editingProfile: $editingProfile)
                } else if let selection = state.selection {
                    ConversationView(state: state, selection: selection)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.selectedProfile != nil {
                        Button { state.requestChannelListing() } label: {
                            Label("Browse channels", systemImage: "list.bullet.rectangle")
                        }
                        .disabled(!state.canBrowseSelectedChannels)
                    }
                }
            }
        }
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

    var body: some View {
        List(selection: $listSelection) {
            Section {
                Label("Connections", systemImage: "bolt.horizontal.circle")
                    .tag(SidebarItem.connectionCenter)
            }

            ForEach(state.activeProfiles) { profile in
                Section(profile.name) {
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
                            }
                        }
                            .foregroundStyle(channel.hasUnread ? .primary : .secondary)
                            .font(channel.hasUnread ? .body.weight(.semibold) : .body)
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
                            .font(message.hasUnread ? .body.weight(.semibold) : .body)
                            .tag(SidebarItem.directMessage(message.id))
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
                Button { state.showConnections() } label: { Image(systemName: "bolt.horizontal.circle") }
                    .buttonStyle(.borderless)
                    .help("Manage connections")
                Spacer()
                Text("\(state.activeProfiles.count) active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(.bar)
        }
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.status(for: profile) == .online ? "circle.inset.filled" : "circle")
                .font(.caption)
                .foregroundStyle(state.status(for: profile).tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.hostname)
                Text(state.status(for: profile).label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConnectionCenterView: View {
    @ObservedObject var state: IRCAppState
    @Binding var showAddServer: Bool
    @Binding var editingProfile: ServerProfile?

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Connections", systemImage: "bolt.horizontal.circle.fill")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.tint)
                        Text("Choose a network to connect, or add a profile for your own server. Active networks and their channels stay focused in the sidebar.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Add Server", systemImage: "plus") { showAddServer = true }
                        .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Profiles")
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(state.profiles) { profile in
                            ServerProfileCard(profile: profile, state: state, editingProfile: $editingProfile)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ServerProfileCard: View {
    let profile: ServerProfile
    @ObservedObject var state: IRCAppState
    @Binding var editingProfile: ServerProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                Image(systemName: profile.useTLS ? "lock.shield.fill" : "network")
                    .font(.title2)
                    .foregroundStyle(profile.useTLS ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.headline)
                    Text(profile.hostname).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isActive(profile) {
                    Circle().fill(state.status(for: profile).tint).frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 6) {
                Label(profile.useTLS ? "TLS encrypted" : "Plain-text IRC", systemImage: profile.useTLS ? "lock.fill" : "exclamationmark.triangle")
                Text(verbatim: "· \(profile.port)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let nickname = profile.nicknameOverride, !nickname.isEmpty {
                Label("Nick: \(nickname)", systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if profile.useSSHTunnel == true, let sshHostname = profile.sshHostname {
                Label("SSH via \(sshHostname):\(profile.sshPort ?? 22)", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Text(
                    state.isWaitingToReconnect(profile)
                        ? "Waiting to reconnect"
                        : (state.isActive(profile) ? state.status(for: profile).label : "Ready to connect")
                )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(state.isActive(profile) ? state.status(for: profile).tint : .secondary)
                Spacer()
                if state.isActive(profile) {
                    if case .failed = state.status(for: profile) {
                        Button("Retry") { state.toggleConnection(for: profile) }
                            .buttonStyle(.borderedProminent)
                        Button("Disconnect") { state.disconnect(profile) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Edit") { editingProfile = profile }
                            .buttonStyle(.borderless)
                        Button("Disconnect") { state.toggleConnection(for: profile) }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Edit") { editingProfile = profile }
                        .buttonStyle(.borderless)
                    Button("Connect") { state.toggleConnection(for: profile) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    @State private var showsMemberList = true
    @State private var pendingURL: PendingURL?
    @FocusState private var composerFocused: Bool

    private var title: String { state.title(for: selection) }
    private var subtitle: String { state.subtitle(for: selection) }
    private var isChannel: Bool { if case .channel = selection { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: selection.icon).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isChannel {
                    Label("\(state.members(for: selection).count)", systemImage: "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { showsMemberList.toggle() } label: {
                        Label(showsMemberList ? "Hide members" : "Show members", systemImage: "sidebar.right")
                    }
                    .labelStyle(.iconOnly)
                    .help(showsMemberList ? "Hide member list" : "Show member list")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14).background(.bar)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(state.messages(for: selection)) { message in
                                    MessageRow(message: message, fontSize: state.transcriptFontSize).id(message.id)
                                }
                            }
                            .padding(.horizontal, 24).padding(.vertical, 20)
                        }
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
                            .textFieldStyle(.plain).lineLimit(1...5)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .focused($composerFocused)
                            .onSubmit(send)
                            .onKeyPress(.tab) {
                                completeRecipient()
                                    ? .handled
                                    : .ignored
                            }
                        Button(action: send) {
                            Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.borderedProminent).clipShape(Circle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14).background(.bar)
                }
                if isChannel && showsMemberList {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Members").font(.headline)
                Spacer()
                Text("\(members.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(members) { member in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(state.isMuted(member.nickname, from: selection) ? Color.secondary : Color.green)
                                .frame(width: 7, height: 7)
                            Text(member.nickname).font(.subheadline)
                            Spacer(minLength: 4)
                            if let role = member.role { Text(role).font(.caption2.weight(.medium)).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            state.startDirectMessage(with: member.nickname, from: selection)
                        }
                        .contextMenu {
                            Button("Message \(member.nickname)", systemImage: "message") {
                                state.startDirectMessage(with: member.nickname, from: selection)
                            }
                            Button("Whois \(member.nickname)", systemImage: "person.text.rectangle") {
                                state.requestWhois(for: member.nickname, from: selection)
                            }
                            Divider()
                            if state.isMuted(member.nickname, from: selection) {
                                Button("Unmute \(member.nickname)", systemImage: "speaker.wave.2") {
                                    state.unmute(member.nickname, from: selection)
                                }
                            } else {
                                Button("Mute \(member.nickname)", systemImage: "speaker.slash") {
                                    state.mute(member.nickname, from: selection)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 190, idealWidth: 218, maxWidth: 270)
        .background(.bar)
    }
}

private struct MessageRow: View {
    let message: IRCMessage
    let fontSize: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: max(fontSize - 4, 10), design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: 52, alignment: .trailing)
            Text(message.sender).font(.system(size: max(fontSize - 1, 11), weight: .semibold))
                .foregroundStyle(message.isSystem ? Color.secondary : Color.accentColor).frame(minWidth: 64, alignment: .leading)
            Text(linkifiedText)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .foregroundStyle(message.isSystem ? .secondary : .primary)
        }
    }

    private var linkifiedText: AttributedString {
        var attributedText = AttributedString(message.text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributedText
        }

        let fullRange = NSRange(message.text.startIndex..., in: message.text)
        for match in detector.matches(in: message.text, range: fullRange) {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let stringRange = Range(match.range, in: message.text),
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
                VStack(alignment: .leading, spacing: 7) {
                    Text("Open External Link?")
                        .font(.title2.weight(.semibold))
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
