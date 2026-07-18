//
//  Sheets.swift
//  Netsplit
//

import AppKit
import SwiftUI

private struct EditableOnConnectCommand: Identifiable {
    let id = UUID()
    var text: String
}

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
    @State private var onConnectCommands: [EditableOnConnectCommand]
    @State private var useSSHTunnel: Bool
    @State private var sshHostname: String
    @State private var sshPort: String
    @State private var sshUsername: String
    @State private var sshPassword: String
    @State private var sshPrivateKey: String
    @State private var sshKeyFilename: String?
    @State private var sshKeyError: String?
    @State private var resetSSHHostKey = false

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
        _onConnectCommands = State(initialValue: profileToEdit.map {
            state.onConnectCommands(for: $0).map { EditableOnConnectCommand(text: $0) }
        } ?? [])
        _useSSHTunnel = State(initialValue: profileToEdit?.useSSHTunnel ?? false)
        _sshHostname = State(initialValue: profileToEdit?.sshHostname ?? "")
        _sshPort = State(initialValue: String(profileToEdit?.sshPort ?? 22))
        _sshUsername = State(initialValue: profileToEdit?.sshUsername ?? "")
        _sshPassword = State(initialValue: profileToEdit.map { state.sshPassword(for: $0) } ?? "")
        _sshPrivateKey = State(initialValue: profileToEdit.map { state.sshPrivateKey(for: $0) } ?? "")
        _sshKeyFilename = State(initialValue: profileToEdit?.sshKeyFilename)
    }

    private var isEditing: Bool { profileToEdit != nil }
    private var hasSSHAuthentication: Bool {
        !sshPassword.isEmpty || !sshPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var nicknameOverrideError: String? {
        let nickname = nicknameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? nil : IRCIdentityValidation.nicknameError(nickname)
    }
    private var ircPort: UInt16? {
        guard let value = UInt16(port), value > 0 else { return nil }
        return value
    }
    private var parsedSSHPort: UInt16? {
        guard let value = UInt16(sshPort), value > 0 else { return nil }
        return value
    }
    private var canSave: Bool {
        guard !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard ircPort != nil, nicknameOverrideError == nil else { return false }
        guard !useSASL || !saslPassword.isEmpty else { return false }
        guard useSSHTunnel else { return true }
        return !sshHostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sshUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedSSHPort != nil
            && hasSSHAuthentication
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isEditing ? "Edit Server Profile" : "Add a Server")
                    .font(.title2.weight(.semibold))
                Text(isEditing ? "Profile changes apply the next time you connect." : "Create a connection profile for any IRC network.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    connectionSection
                    identitySection
                    authenticationSection
                    onConnectSection
                    sshSection
                }
                .padding(24)
            }

            Divider()

            HStack {
                if let profileToEdit, profileToEdit.isBuiltIn, profileToEdit.isPresetModified == true {
                    Button("Restore Default") {
                        state.restorePreset(profileToEdit)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save Changes" : "Add Server", action: saveProfile)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 680, height: 720)
        .alert("Could Not Import SSH Key", isPresented: Binding(
            get: { sshKeyError != nil },
            set: { if !$0 { sshKeyError = nil } }
        )) {
            Button("OK", role: .cancel) { sshKeyError = nil }
        } message: {
            Text(sshKeyError ?? "")
        }
    }

    private var connectionSection: some View {
        ServerEditorSection(title: "Connection", systemImage: "network") {
            ServerEditorFieldRow("Name") {
                TextField("My IRC Network", text: $name, prompt: Text("My IRC Network"))
            }
            ServerEditorFieldRow("Server address") {
                TextField("irc.example.org", text: $hostname, prompt: Text("irc.example.org"))
            }
            ServerEditorFieldRow("Port") {
                TextField("6697", text: $port)
            }
            if ircPort == nil {
                ServerEditorHelpText("Enter an IRC port between 1 and 65535.", tint: .red)
            }
            ServerEditorToggleRow("Use encrypted connection (TLS)", isOn: $useTLS)
            ServerEditorToggleRow("Connect automatically at launch", isOn: $autoConnect)
        }
    }

    private var identitySection: some View {
        ServerEditorSection(title: "Identity", systemImage: "person.crop.circle") {
            ServerEditorFieldRow("Nickname") {
                TextField("Use global nickname", text: $nicknameOverride, prompt: Text("Use global nickname"))
            }
            if let nicknameOverrideError {
                ServerEditorHelpText(nicknameOverrideError, tint: .red)
            }
            ServerEditorHelpText("Leave blank to use the global nickname from Settings. Set a value here when this network requires a different identity.")
        }
    }

    private var authenticationSection: some View {
        ServerEditorSection(title: "Server Authentication", systemImage: "key") {
            ServerEditorFieldRow("Server password") {
                SecureField("Optional", text: $serverPassword)
            }
            ServerEditorToggleRow("Authenticate with SASL", isOn: $useSASL)
            if useSASL {
                ServerEditorFieldRow("SASL username") {
                    TextField("Use server nickname", text: $saslUsername, prompt: Text("Use server nickname"))
                }
                ServerEditorFieldRow("SASL password") {
                    SecureField("Required for SASL", text: $saslPassword)
                }
                if saslPassword.isEmpty {
                    ServerEditorHelpText("Enter a SASL password or turn off SASL authentication.", tint: .red)
                }
            }
            ServerEditorHelpText("Passwords are stored in your macOS Keychain. SASL PLAIN is requested only when the IRC server advertises SASL support.")
        }
    }

    private var sshSection: some View {
        ServerEditorSection(title: "SSH Tunnel", systemImage: "point.3.connected.trianglepath.dotted") {
            ServerEditorToggleRow("Connect through an SSH tunnel", isOn: $useSSHTunnel)
            if useSSHTunnel {
                ServerEditorFieldRow("SSH hostname") {
                    TextField("ssh.example.org", text: $sshHostname, prompt: Text("ssh.example.org"))
                }
                ServerEditorFieldRow("SSH port") {
                    TextField("22", text: $sshPort)
                }
                if parsedSSHPort == nil {
                    ServerEditorHelpText("Enter an SSH port between 1 and 65535.", tint: .red)
                }
                ServerEditorFieldRow("SSH username") {
                    TextField("Username", text: $sshUsername)
                }
                ServerEditorFieldRow("SSH password") {
                    SecureField("Optional when using a key", text: $sshPassword)
                }
                ServerEditorFieldRow("Private key") {
                    HStack(spacing: 10) {
                        Button(sshKeyFilename == nil ? "Choose Key…" : "Replace Key…") {
                            chooseSSHKey()
                        }
                        if let sshKeyFilename {
                            Text(sshKeyFilename)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button("Remove") {
                                self.sshKeyFilename = nil
                                sshPrivateKey = ""
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !hasSSHAuthentication {
                    ServerEditorHelpText("Add an SSH password or private key to connect.", tint: .red)
                }
                ServerEditorHelpText("SSH credentials are stored in Keychain. Unencrypted OpenSSH Ed25519 keys are recommended; many modern servers reject the legacy signature used by this transport for RSA keys.")
                ServerEditorHelpText("The SSH host identity is learned on first connection and pinned to this server profile.")
                if profileToEdit?.sshTrustedHostKey != nil {
                    ServerEditorFieldRow("Host identity") {
                        Button(resetSSHHostKey ? "Will Be Forgotten When Saved" : "Forget Saved Identity") {
                            resetSSHHostKey = true
                        }
                        .disabled(resetSSHHostKey)
                    }
                }
            } else {
                ServerEditorHelpText("IRC connects directly to the server when this option is off.")
            }
        }
    }

    private var onConnectSection: some View {
        ServerEditorSection(title: "On Connect", systemImage: "terminal") {
            if onConnectCommands.isEmpty {
                ServerEditorHelpText("No custom commands will be sent when this server connects.")
            } else {
                ForEach(Array(onConnectCommands.enumerated()), id: \.element.id) { index, command in
                    ServerEditorFieldRow("Command \(index + 1)") {
                        HStack(spacing: 8) {
                            TextField(
                                "/msg NickServ IDENTIFY password",
                                text: Binding(
                                    get: { commandText(for: command.id) },
                                    set: { setCommandText($0, for: command.id) }
                                ),
                                prompt: Text("/msg NickServ IDENTIFY password")
                            )
                            Button {
                                moveOnConnectCommand(command.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move command earlier")

                            Button {
                                moveOnConnectCommand(command.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == onConnectCommands.count - 1)
                            .help("Move command later")

                            Button(role: .destructive) {
                                onConnectCommands.removeAll { $0.id == command.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove command")
                        }
                    }
                }
            }

            ServerEditorFieldRow("") {
                Button {
                    onConnectCommands.append(EditableOnConnectCommand(text: ""))
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
            }
            ServerEditorHelpText("Commands run in this order after the IRC server accepts the connection. Netsplit waits 0.5 seconds between commands and 2 seconds after the final command before joining favorite channels.")
            ServerEditorHelpText("Client commands such as /msg, /nickserv and /identify are accepted, as are raw IRC commands. Commands are stored securely in your macOS Keychain and are not written to the server log.")
        }
    }

    private func saveProfile() {
        let cleanHost = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ircPort else { return }
        let savedSSHPort: UInt16
        if useSSHTunnel {
            guard let parsedSSHPort else { return }
            savedSSHPort = parsedSSHPort
        } else {
            savedSSHPort = parsedSSHPort ?? 22
        }
        if let profileToEdit {
            state.updateProfile(profileToEdit, name: displayName.isEmpty ? cleanHost : displayName, hostname: cleanHost, port: ircPort, useTLS: useTLS, autoConnect: autoConnect, nicknameOverride: nicknameOverride, serverPassword: serverPassword, useSASL: useSASL, saslUsername: saslUsername, saslPassword: saslPassword, onConnectCommands: onConnectCommands.map(\.text), useSSHTunnel: useSSHTunnel, sshHostname: sshHostname, sshPort: savedSSHPort, sshUsername: sshUsername, sshPassword: sshPassword, sshPrivateKey: sshPrivateKey, sshKeyFilename: sshKeyFilename, resetSSHHostKey: resetSSHHostKey)
        } else {
            state.addProfile(name: displayName.isEmpty ? cleanHost : displayName, hostname: cleanHost, port: ircPort, useTLS: useTLS, autoConnect: autoConnect, serverPassword: serverPassword, useSASL: useSASL, saslUsername: saslUsername, saslPassword: saslPassword, onConnectCommands: onConnectCommands.map(\.text), useSSHTunnel: useSSHTunnel, sshHostname: sshHostname, sshPort: savedSSHPort, sshUsername: sshUsername, sshPassword: sshPassword, sshPrivateKey: sshPrivateKey, sshKeyFilename: sshKeyFilename)
        }
        dismiss()
    }

    private func commandText(for id: UUID) -> String {
        onConnectCommands.first(where: { $0.id == id })?.text ?? ""
    }

    private func setCommandText(_ text: String, for id: UUID) {
        guard let index = onConnectCommands.firstIndex(where: { $0.id == id }) else { return }
        onConnectCommands[index].text = text
    }

    private func moveOnConnectCommand(_ id: UUID, by offset: Int) {
        guard let source = onConnectCommands.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard onConnectCommands.indices.contains(destination) else { return }
        onConnectCommands.swapAt(source, destination)
    }

    private func chooseSSHKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose an SSH Private Key"
        panel.message = "Select the private key, such as id_ed25519 or id_rsa — not the matching .pub file."
        panel.prompt = "Choose Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // Give this picker its own state instead of inheriting the last folder
        // used by an unrelated NSOpenPanel elsewhere in the app.
        panel.identifier = NSUserInterfaceItemIdentifier("Netsplit.SSHPrivateKeyPicker")

        let defaultSSHDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
        if FileManager.default.fileExists(atPath: defaultSSHDirectory.path) {
            panel.directoryURL = defaultSSHDirectory
            let preferredKeyNames = ["id_ed25519", "id_rsa"]
            if let preferredKeyName = preferredKeyNames.first(where: {
                FileManager.default.fileExists(
                    atPath: defaultSSHDirectory.appendingPathComponent($0).path
                )
            }) {
                panel.nameFieldStringValue = preferredKeyName
            }
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importSSHPrivateKey(from: url)
        }
    }

    private func importSSHPrivateKey(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 256 * 1024, let key = String(data: data, encoding: .utf8) else {
                sshKeyError = "The selected file could not be read as a text SSH private key."
                return
            }
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.pathExtension.lowercased() == "pub"
                || trimmedKey.hasPrefix("ssh-rsa ")
                || trimmedKey.hasPrefix("ssh-ed25519 ")
                || trimmedKey.hasPrefix("ecdsa-sha2-") {
                sshKeyError = "That is an SSH public key. Select the matching private key instead — usually the file with the same name but without the .pub extension."
                return
            }
            guard trimmedKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else {
                sshKeyError = "Netsplit currently supports unencrypted OpenSSH private keys. Select id_ed25519 (recommended) or id_rsa, not a .pub file."
                return
            }
            sshPrivateKey = key
            sshKeyFilename = url.lastPathComponent
        } catch {
            sshKeyError = "The selected file could not be read as an SSH private key."
        }
    }
}

private struct ServerEditorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.vertical, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private struct ServerEditorFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .frame(width: 140, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ServerEditorToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 140, height: 1)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
            Spacer()
        }
    }
}

private struct ServerEditorHelpText: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Color.clear.frame(width: 140, height: 1)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .padding(.top, 1)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(tint)
            .help(text)
            Spacer(minLength: 0)
        }
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
                if let nicknameError = IRCIdentityValidation.nicknameError(state.nickname) {
                    Text(nicknameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                Toggle("Reconnect automatically", isOn: $state.reconnectAutomatically)
                Text("After an unexpected disconnect, Netsplit retries after 2, 4, 8 seconds and so on, up to once per minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("Links") {
                Toggle("Warn before opening links", isOn: $state.warnBeforeOpeningLinks)
                Text("Links open in your default browser. The warning can help protect you from deceptive or malicious content shared in chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 450)
        .padding()
    }
}
