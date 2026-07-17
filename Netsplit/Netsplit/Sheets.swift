//
//  Sheets.swift
//  Netsplit
//

import SwiftUI

struct ServerProfileEditor: View {
    @ObservedObject var state: IRCAppState
    let profileToEdit: ServerProfile?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hostname: String
    @State private var port: String
    @State private var useTLS: Bool
    @State private var autoConnect: Bool
    @State private var nicknameOverride: String
    @State private var serverPassword: String
    @State private var useSASL: Bool
    @State private var saslUsername: String
    @State private var saslPassword: String

    init(state: IRCAppState, profileToEdit: ServerProfile? = nil) {
        self.state = state
        self.profileToEdit = profileToEdit
        _name = State(initialValue: profileToEdit?.name ?? "")
        _hostname = State(initialValue: profileToEdit?.hostname ?? "")
        _port = State(initialValue: String(profileToEdit?.port ?? 6697))
        _useTLS = State(initialValue: profileToEdit?.useTLS ?? true)
        _autoConnect = State(initialValue: profileToEdit?.autoConnect ?? false)
        _nicknameOverride = State(initialValue: profileToEdit?.nicknameOverride ?? "")
        _serverPassword = State(initialValue: profileToEdit.map { state.serverPassword(for: $0) } ?? "")
        _useSASL = State(initialValue: profileToEdit?.useSASL ?? false)
        _saslUsername = State(initialValue: profileToEdit?.saslUsername ?? "")
        _saslPassword = State(initialValue: profileToEdit.map { state.saslPassword(for: $0) } ?? "")
    }

    private var isEditing: Bool { profileToEdit != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Server Profile" : "Add a Server").font(.title2.weight(.semibold))
            Text(isEditing ? "Profile changes apply the next time you connect." : "Create a connection profile for any IRC network.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name, prompt: Text("My IRC Network"))
                TextField("Server address", text: $hostname, prompt: Text("irc.example.org"))
                TextField("Port", text: $port)
                Toggle("Use encrypted connection (TLS)", isOn: $useTLS)
                Toggle("Connect automatically at launch", isOn: $autoConnect)
                Divider()
                TextField("Nickname for this server", text: $nicknameOverride, prompt: Text("Use global nickname"))
                Text("Leave blank to use the nickname in Settings. This is useful when different networks require different identities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                SecureField("Server password (optional)", text: $serverPassword)
                Toggle("Authenticate with SASL", isOn: $useSASL)
                if useSASL {
                    TextField("SASL username", text: $saslUsername, prompt: Text("Use server nickname"))
                    SecureField("SASL password", text: $saslPassword)
                }
                Text("Passwords are stored in your macOS Keychain. SASL PLAIN is requested only when the server advertises SASL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let profileToEdit, profileToEdit.isBuiltIn, profileToEdit.isPresetModified == true {
                    Button("Restore Default") {
                        state.restorePreset(profileToEdit)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save Changes" : "Add Server") {
                    let cleanHost = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let profileToEdit {
                        state.updateProfile(profileToEdit, name: displayName.isEmpty ? cleanHost : displayName, hostname: cleanHost, port: UInt16(port) ?? (useTLS ? 6697 : 6667), useTLS: useTLS, autoConnect: autoConnect, nicknameOverride: nicknameOverride, serverPassword: serverPassword, useSASL: useSASL, saslUsername: saslUsername, saslPassword: saslPassword)
                    } else {
                        state.addProfile(name: displayName.isEmpty ? cleanHost : displayName, hostname: cleanHost, port: UInt16(port) ?? (useTLS ? 6697 : 6667), useTLS: useTLS, autoConnect: autoConnect, serverPassword: serverPassword, useSASL: useSASL, saslUsername: saslUsername, saslPassword: saslPassword)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct ChannelBrowser: View {
    @ObservedObject var state: IRCAppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var profile: ServerProfile? { state.selectedProfile }
    private var availableChannels: [ChannelListing] { state.channelListings(for: profile?.id) }
    private var isLoading: Bool { state.isChannelListingInProgress(for: profile?.id) }

    private var results: [ChannelListing] {
        search.isEmpty ? availableChannels : availableChannels.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.topic.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browse Channels").font(.title2.weight(.semibold))
                    Text(isLoading ? "Receiving the live channel list from \(profile?.name ?? "the server")…" : "\(availableChannels.count) live results · double-click a channel to join.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search channels", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .disabled(availableChannels.isEmpty)
                if isLoading { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }
            }
            .padding(20)

            Group {
                if !results.isEmpty {
                    List(results) { channel in
                        HStack(spacing: 14) {
                            Image(systemName: "number.circle.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.name).fontWeight(.medium)
                                Text(channel.topic).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("\(channel.userCount)", systemImage: "person.2")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { state.join(channel); dismiss() }
                    }
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Fetching channels").font(.title3.weight(.semibold))
                        Text("Large networks can take a moment to return their list.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No Channels Returned", systemImage: "number.circle")
                    } description: {
                        Text("The server did not return any channels for this request.")
                    } actions: {
                        Button("Try Again") { state.requestChannelListing(forceRefresh: true) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.bottom, 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 610, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct SettingsView: View {
    @ObservedObject var state: IRCAppState

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Nickname", text: $state.nickname)
                    .onSubmit(state.saveIdentity)
                TextField("Real name", text: $state.realName)
                    .onSubmit(state.saveIdentity)
                Text("Used when you connect to an IRC network. Some networks may require registration for preferred nicknames.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Connection") {
                TextField("Quit message", text: $state.quitMessage)
                Text("Sent when you disconnect or quit Netsplit. A reason supplied with /quit overrides this message once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Reconnect automatically", isOn: .constant(true))
                    .disabled(true)
                Text("Netsplit requests standard IRCv3 capabilities when supported by the server, including server timestamps and message tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Chat Appearance") {
                HStack {
                    Text("Message text size")
                    Spacer()
                    Text("\(Int(state.transcriptFontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { state.transcriptFontSize },
                        set: { state.setTranscriptFontSize($0) }
                    ),
                    in: 12...24,
                    step: 1
                )
                Button("Reset Text Size") { state.resetTranscriptFontSize() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
        .padding()
    }
}
