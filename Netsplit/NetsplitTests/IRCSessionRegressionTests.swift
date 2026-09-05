import AppKit
import Foundation
import Network
import Security
import SwiftUI
import Testing
@testable import Netsplit

@Suite("IRC session regressions", .serialized)
@MainActor
struct IRCSessionRegressionTests {
    @Test("Unlabeled message rejections are shown in the recipient's conversation")
    func unlabeledMessageRejection() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        server.messageRejection = "401"
        context.state.send("/query MissingNick hello", to: context.serverItem)
        try await waitForSessionCondition { server.lines.contains("PRIVMSG MissingNick :hello") }
        try await server.synchronize()

        let conversation = try #require(context.state.directMessages.first { $0.name == "MissingNick" })
        let messages = context.messages(in: .directMessage(conversation.id))
        #expect(messages.contains { $0.isSystem && $0.text.contains("401") })
        #expect(!messages.contains { !$0.isSystem && $0.text == "hello" })
    }

    @Test("A channel message rejection reaches the channel transcript")
    func channelMessageRejection() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        server.send(":ReviewUser!u@h JOIN #moderated")
        try await server.synchronize()
        let channel = try #require(context.state.channels.first { $0.name == "#moderated" })
        server.messageRejection = "404"
        context.state.send("hello", to: .channel(channel.id))
        try await waitForSessionCondition { server.lines.contains("PRIVMSG #moderated :hello") }
        try await server.synchronize()
        #expect(context.messages(in: .channel(channel.id)).contains { $0.text.contains("404") })
        #expect(!context.messages(in: .channel(channel.id)).contains { !$0.isSystem && $0.text == "hello" })
    }

    @Test("Unlabeled errors never remove an arbitrary previously sent message")
    func ambiguousRejectionPreservesEarlierMessage() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        context.state.send("/query Alice delivered", to: context.serverItem)
        try await waitForSessionCondition { server.lines.contains("PRIVMSG Alice :delivered") }
        server.messageRejection = "401"
        context.state.send("/query Alice rejected", to: context.serverItem)
        try await waitForSessionCondition { server.lines.contains("PRIVMSG Alice :rejected") }
        try await server.synchronize()
        let conversation = try #require(context.state.directMessages.first { $0.name == "Alice" })
        let messages = context.messages(in: .directMessage(conversation.id))
        #expect(messages.contains { !$0.isSystem && $0.text == "delivered" })
        #expect(messages.contains { $0.isSystem && $0.text.contains("401") })
    }

    @Test("Otherwise unhandled numeric errors remain visible", arguments: ["404", "421", "461", "464", "499", "716"])
    func numericErrorFallback(numeric: String) throws {
        let context = try SessionTestContext()
        defer { context.close() }
        context.state.handle(
            try #require(IRCWireMessage(line: ":review \(numeric) ReviewUser target :Request rejected")),
            profile: context.profile
        )
        #expect(context.messages(in: context.serverItem).contains { $0.text == "\(numeric): Request rejected" })
    }

    @Test("Unrelated command errors do not consume a pending VERSION request")
    func versionErrorCorrelation() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        context.state.send("/query Alice hello", to: context.serverItem)
        let conversation = try #require(context.state.directMessages.first { $0.name == "Alice" })
        let destination = SidebarItem.directMessage(conversation.id)
        context.state.send("/version", to: destination)
        try await waitForSessionCondition { server.lines.contains("VERSION") }
        server.send(":review 421 ReviewUser UNKNOWN :Unknown command\r\n:review 351 ReviewUser review-1.0 review :Server version")
        try await server.synchronize()
        #expect(context.messages(in: context.serverItem).contains { $0.text == "421: Unknown command" })
        #expect(context.messages(in: destination).contains { $0.text.contains("review-1.0") })
        #expect(!context.messages(in: destination).contains { $0.text.contains("request failed") })
    }

    @Test("NAMES lookups do not join channels or suppress a later JOIN")
    func namesLookupMembership() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        context.state.send("/names #lookup", to: context.serverItem)
        try await waitForSessionCondition { server.lines.contains("NAMES #lookup") }
        try await server.synchronize()
        #expect(context.state.channels.isEmpty)
        #expect(!context.state.isJoinedChannel(named: "#lookup", on: context.profile.id))
        #expect(context.messages(in: context.serverItem).contains { $0.text == "Names in #lookup: Alice Bob" })
        context.state.send("/join #lookup", to: context.serverItem)
        try await waitForSessionCondition { server.lines.contains("JOIN #lookup") }
        #expect(!context.state.isJoinedChannel(named: "#lookup", on: context.profile.id))
        server.send(":ReviewUser!u@h JOIN #lookup")
        try await server.synchronize()
        #expect(context.state.isJoinedChannel(named: "#lookup", on: context.profile.id))

        // NAMES can replace the member list; membership still follows our JOIN/PART.
        context.state.send("/names #lookup", to: context.serverItem)
        try await waitForSessionCondition { server.lines.filter { $0 == "NAMES #lookup" }.count == 2 }
        try await server.synchronize()
        server.send(":ReviewUser!u@h PART #lookup :Leaving")
        try await server.synchronize()
        #expect(!context.state.isJoinedChannel(named: "#lookup", on: context.profile.id))
        context.state.send("/join #lookup", to: context.serverItem)
        try await waitForSessionCondition { server.lines.filter { $0 == "JOIN #lookup" }.count == 2 }
    }

    @Test("Failed automatic rejoins retain history and permit a manual retry")
    func failedRejoinCanBeRetried() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        server.send(":ReviewUser!u@h JOIN #retained\r\n:Alice!u@h PRIVMSG #retained :Keep this history")
        try await server.synchronize()
        let channel = try #require(context.state.channels.first { $0.name == "#retained" })
        server.joinRejection = "475"
        context.state.reconnect(context.profile)
        #expect(!context.state.isJoinedChannel(named: "#retained", on: context.profile.id))
        try await waitForSessionCondition { context.isOnline && server.lines.contains("JOIN #retained") }
        try await server.synchronize()
        #expect(!context.state.isJoinedChannel(named: "#retained", on: context.profile.id))
        #expect(context.messages(in: .channel(channel.id)).contains { $0.text.contains("Could not rejoin") })
        server.joinRejection = nil
        server.confirmsJoins = true
        context.state.send("/join #retained correct-key", to: context.serverItem)
        try await waitForSessionCondition { context.state.isJoinedChannel(named: "#retained", on: context.profile.id) }
        #expect(server.lines.contains("JOIN #retained correct-key"))
        #expect(context.state.channels.first { $0.name == "#retained" }?.id == channel.id)
        #expect(context.messages(in: .channel(channel.id)).contains { $0.text == "Keep this history" })
    }

    @Test("Unanswered rejoins time out and allow another attempt without losing history")
    func unansweredRejoinCanBeRetried() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        server.send(":ReviewUser!u@h JOIN #retained\r\n:Alice!u@h PRIVMSG #retained :Keep this history")
        try await server.synchronize()
        let channel = try #require(context.state.channels.first { $0.name == "#retained" })
        context.state.reconnect(context.profile)
        try await waitForSessionCondition(timeout: 25) {
            context.messages(in: .channel(channel.id)).contains { $0.text.contains("did not confirm the join") }
        }
        #expect(!context.state.isJoinedChannel(named: "#retained", on: context.profile.id))
        server.confirmsJoins = true
        context.state.send("/join #retained", to: context.serverItem)
        try await waitForSessionCondition { context.state.isJoinedChannel(named: "#retained", on: context.profile.id) }
        #expect(context.state.channels.first { $0.name == "#retained" }?.id == channel.id)
        #expect(context.messages(in: .channel(channel.id)).contains { $0.text == "Keep this history" })
        #expect(server.lines.filter { $0 == "JOIN #retained" }.count == 2)
    }

    @Test("Channel keys are sent and retained for reconnect")
    func keyedJoinAndReconnect() async throws {
        let server = try SessionTestServer()
        server.confirmsJoins = true
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        context.state.send("/join #locked example-key", to: context.serverItem)
        try await waitForSessionCondition { context.state.isJoinedChannel(named: "#locked", on: context.profile.id) }
        #expect(server.lines.contains("JOIN #locked example-key"))
        context.state.reconnect(context.profile)
        try await waitForSessionCondition {
            context.state.isJoinedChannel(named: "#locked", on: context.profile.id)
                && server.lines.filter { $0 == "JOIN #locked example-key" }.count == 2
        }
        let channel = try #require(context.state.channels.first { $0.name == "#locked" })
        context.state.send("/hop", to: .channel(channel.id))
        try await waitForSessionCondition {
            context.state.isJoinedChannel(named: "#locked", on: context.profile.id)
                && server.lines.filter { $0 == "JOIN #locked example-key" }.count == 3
        }
        #expect(server.lines.contains("PART #locked"))
    }

    @Test("PRIVMSG and NOTICE accept either final-parameter syntax", arguments: ["hello", ":hello"])
    func optionalTrailingColon(text: String) throws {
        let context = try SessionTestContext()
        defer { context.close() }
        context.state.handle(
            try #require(IRCWireMessage(line: ":Alice!u@h PRIVMSG ReviewUser \(text)")),
            profile: context.profile
        )
        context.state.handle(
            try #require(IRCWireMessage(line: ":Bob!u@h NOTICE ReviewUser \(text)")),
            profile: context.profile
        )
        let alice = try #require(context.state.directMessages.first { $0.name == "Alice" })
        #expect(context.messages(in: .directMessage(alice.id)).contains { $0.text == "hello" })
        let bob = try #require(context.state.directMessages.first { $0.name == "Bob" })
        #expect(context.messages(in: .directMessage(bob.id)).contains { $0.text == "hello" && $0.isNotice })
    }

    @Test("Setup echoes stay private with and without labels", arguments: [false, true])
    func setupEchoSuppression(labeled: Bool) async throws {
        let server = try SessionTestServer(labeled: labeled, echoesMessages: true)
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let commands = IRCOnConnectCommandPhases(beforeFavoritesJoined: [
            "/msg NickServ IDENTIFY example-only-secret",
            "/notice NickServ,ChanServ IDENTIFY example-only-secret"
        ])
        let context = try SessionTestContext(port: #require(server.port), commands: commands)
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { server.lines.contains { $0.contains("NOTICE NickServ,ChanServ") } }
        try await server.synchronize()
        #expect(!context.allMessages.contains { $0.text.contains("example-only-secret") })
        #expect(context.state.directMessages.isEmpty)
        // Other clients on a bouncer can legitimately produce untracked self messages.
        server.send(":ReviewUser!u@h PRIVMSG Friend :Visible message")
        try await server.synchronize()
        #expect(context.allMessages.contains { $0.text == "Visible message" })
    }

    @Test("Setup rejection replies cannot repeat credentials", arguments: [false, true])
    func setupRejectionSuppression(labeled: Bool) async throws {
        let server = try SessionTestServer(labeled: labeled, echoesMessages: true)
        server.messageRejection = "401"
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(
            port: #require(server.port),
            commands: IRCOnConnectCommandPhases(beforeFavoritesJoined: ["/msg NickServ IDENTIFY example-only-secret"])
        )
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { server.lines.contains { $0.contains("PRIVMSG NickServ") } }
        try await server.synchronize()
        #expect(!context.allMessages.contains { $0.text.contains("example-only-secret") })
        #expect(context.allMessages.contains { $0.text == "An on-connect command was rejected (401)." })
    }

    @Test("Suppressed setup messages remain tracked beyond ordinary echo expiry")
    func delayedSetupEchoRetention() {
        let sentAt = Date(timeIntervalSince1970: 100)
        var outgoing = IRCOutgoingEchoState(
            message: IRCMessage(sender: "ReviewUser", text: ""),
            presentation: .message
        )
        _ = outgoing.completeWrite(succeeded: true)
        let later = sentAt.addingTimeInterval(600)
        #expect(IRCOutgoingEchoRetentionPolicy.shouldExpire(outgoing, sentAt: sentAt, now: later))
        #expect(!IRCOutgoingEchoRetentionPolicy.shouldExpire(
            outgoing, sentAt: sentAt, now: later, suppressTranscript: true
        ))
    }

    @Test("Standard replies cannot quote setup credentials", arguments: [false, true])
    func setupStandardReplySuppression(labeled: Bool) async throws {
        let server = try SessionTestServer(labeled: labeled, echoesMessages: true)
        server.messageRejection = "FAIL"
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(
            port: #require(server.port),
            commands: IRCOnConnectCommandPhases(beforeFavoritesJoined: ["/identify example-only-secret"])
        )
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { server.lines.contains { $0.contains("PRIVMSG NickServ") } }
        try await server.synchronize()
        #expect(!context.allMessages.contains { $0.text.contains("example-only-secret") })
        #expect(context.allMessages.contains { $0.text == "An on-connect command received FAIL." })
    }

    @Test("Setup response batches stay private after the echo is consumed")
    func setupBatchReplySuppression() async throws {
        let server = try SessionTestServer(labeled: true, echoesMessages: true)
        server.holdsMessageReplies = true
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(
            port: #require(server.port),
            commands: IRCOnConnectCommandPhases(beforeFavoritesJoined: ["/identify example-only-secret"])
        )
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { server.lines.contains { $0.contains("PRIVMSG NickServ") } }
        try await server.synchronize()
        let command = try #require(server.lines.first { $0.contains("PRIVMSG NickServ") })
        let wire = try #require(IRCWireMessage(line: command))
        let label = try #require(wire.tags["label"] ?? nil)
        server.send([
            "@label=\(label) :review BATCH +setup labeled-response",
            "@batch=setup :ReviewUser!u@h PRIVMSG NickServ :IDENTIFY example-only-secret",
            "@batch=setup :ReviewUser!u@h PRIVMSG NickServ :IDENTIFY example-only-secret",
            "@batch=setup :review BATCH +nested draft/example",
            "@batch=nested :review 401 ReviewUser NickServ :Rejected example-only-secret",
            "@batch=nested :review FAIL PRIVMSG REJECTED NickServ :Rejected example-only-secret",
            "@batch=nested :review WARN PRIVMSG WARNING NickServ :Warning example-only-secret",
            "@batch=nested :review NOTE PRIVMSG INFO NickServ :Info example-only-secret",
            "@batch=setup :review BATCH -nested",
            ":review BATCH -setup",
            ":review NOTE * INFO :Unrelated visible reply"
        ].joined(separator: "\r\n"))
        try await server.synchronize()
        #expect(!context.allMessages.contains { $0.text.contains("example-only-secret") })
        #expect(context.state.directMessages.isEmpty)
        #expect(context.allMessages.contains { $0.text == "An on-connect command was rejected (401)." })
        #expect(context.allMessages.contains { $0.text == "An on-connect command received NOTE." })
        #expect(context.allMessages.contains { $0.text == "INFO: Unrelated visible reply" })
    }

    @Test("Large channel lists retain all unique entries and sort on completion")
    func channelListIngestion() async throws {
        let server = try SessionTestServer()
        defer { server.stop() }
        try await waitForSessionCondition { server.port != nil }
        let context = try SessionTestContext(port: #require(server.port))
        defer { context.close() }
        context.state.connect(context.profile)
        try await waitForSessionCondition { context.isOnline }
        context.state.send("/list", to: context.serverItem)
        let wires = (0..<16_000).map {
            IRCWireMessage(line: ":review 322 ReviewUser #channel\($0) \($0 + 1) :Topic")!
        }
        let start = ContinuousClock.now
        for wire in wires { context.state.handle(wire, profile: context.profile) }
        let duration = start.duration(to: .now)
        context.state.handle(
            try #require(IRCWireMessage(line: ":review 322 ReviewUser #CHANNEL0 99999 :Duplicate")),
            profile: context.profile
        )
        context.state.handle(
            try #require(IRCWireMessage(line: ":review 323 ReviewUser :End of LIST")),
            profile: context.profile
        )
        let listings = context.state.channelListings(for: context.profile.id)
        #expect(listings.count == 16_000)
        #expect(listings.first?.name == "#channel15999")
        #expect(listings.last?.name == "#channel0")
        print("LIST regression: 16,000 entries ingested in \(duration)")
    }
}

@Suite("Credential editing regressions", .serialized)
@MainActor
struct IRCProfileCredentialRegressionTests {
    @Test("The profile editor loads credentials once and keeps them across view updates")
    func editorCredentialLifetime() async throws {
        let context = try SessionTestContext()
        defer { context.close() }
        let account = "server-password.\(context.profile.id.uuidString)"
        context.credentials.values[account] = "example-editor-password"
        let hostingView = NSHostingView(rootView: ServerProfileEditor(state: context.state, profileToEdit: context.profile))
        #expect(context.credentials.reads.isEmpty)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        window.orderFront(nil)
        try await waitForSessionCondition {
            context.credentials.reads.count == 5
                && self.secureFieldValues(in: hostingView).contains("example-editor-password")
        }
        context.credentials.values[account] = "external-change"
        hostingView.rootView = ServerProfileEditor(state: context.state, profileToEdit: context.profile)
        hostingView.layoutSubtreeIfNeeded()
        #expect(context.credentials.reads.count == 5)
        #expect(secureFieldValues(in: hostingView).contains("example-editor-password"))
        #expect(context.credentials.writes.isEmpty)
    }

    private func secureFieldValues(in view: NSView) -> [String] {
        let values = (view as? NSSecureTextField).map { [$0.stringValue] } ?? []
        return values + view.subviews.flatMap { secureFieldValues(in: $0) }
    }

    @Test("An unrelated edit after denied reads preserves every saved credential")
    func preservesUnavailableCredentials() throws {
        let context = try SessionTestContext(commands: IRCOnConnectCommandPhases(beforeFavoritesJoined: ["/identify secret"]))
        defer { context.close() }
        for kind in ["server-password", "sasl-password", "ssh-password", "ssh-private-key"] {
            context.credentials.values["\(kind).\(context.profile.id.uuidString)"] = "saved-\(kind)"
        }
        let savedValues = context.credentials.values
        context.credentials.rejectsReads = true
        let snapshot = context.state.credentialSnapshot(for: context.profile)
        #expect(snapshot.hasUnavailableValues)
        #expect(context.state.keychainAccessIssue != nil)
        context.credentials.rejectsReads = false
        let changes = snapshot.changes(
            serverPassword: "", saslPassword: "", onConnectCommands: IRCOnConnectCommandPhases(),
            sshPassword: "", sshPrivateKey: ""
        )
        #expect(context.save(changes: changes, name: "Renamed"))
        #expect(context.credentials.values == savedValues)
        #expect(context.credentials.writes.isEmpty)
        #expect(context.state.profiles.first { $0.id == context.profile.id }?.name == "Renamed")
    }

    @Test("Clearing a loaded password is explicit and unchanged secrets are not written")
    func savesOnlyEditedFields() throws {
        let context = try SessionTestContext()
        defer { context.close() }
        let account = "server-password.\(context.profile.id.uuidString)"
        context.credentials.values[account] = "old-password"
        let snapshot = context.state.credentialSnapshot(for: context.profile)
        let changes = snapshot.changes(
            serverPassword: "", saslPassword: "", onConnectCommands: IRCOnConnectCommandPhases(),
            sshPassword: "", sshPrivateKey: ""
        )
        #expect(context.save(changes: changes))
        #expect(context.credentials.writes == [account])
        #expect(context.credentials.values[account] == nil)
    }

    @Test("Credential save failures leave profile changes uncommitted and allow retry")
    func failedSaveCanBeRetried() throws {
        let context = try SessionTestContext()
        defer { context.close() }
        context.credentials.rejectsReads = true
        _ = context.state.credentialSnapshot(for: context.profile)
        context.state.keychainAccessIssue = nil
        context.credentials.rejectsReads = false
        context.credentials.rejectsWrites = true
        let changes = IRCProfileCredentialChanges(serverPassword: "replacement")
        #expect(!context.save(changes: changes, name: "Not yet saved"))
        #expect(context.state.profiles.first { $0.id == context.profile.id }?.name == context.profile.name)
        #expect(context.state.keychainAccessIssue?.title == "Couldn’t Save Credentials")
        context.credentials.rejectsWrites = false
        #expect(context.save(changes: changes, name: "Saved"))
        #expect(context.state.profiles.first { $0.id == context.profile.id }?.name == "Saved")
        #expect(context.credentials.values["server-password.\(context.profile.id.uuidString)"] == "replacement")
    }

    @Test("Retry after a partial save can restore the user's original password")
    func partialSaveTracksSuccessfulWrites() throws {
        let context = try SessionTestContext()
        defer { context.close() }
        let serverAccount = "server-password.\(context.profile.id.uuidString)"
        let saslAccount = "sasl-password.\(context.profile.id.uuidString)"
        context.credentials.values[serverAccount] = "original"
        var snapshot = context.state.credentialSnapshot(for: context.profile)
        context.credentials.rejectedWriteAccounts = [saslAccount]
        let changes = snapshot.changes(
            serverPassword: "replacement", saslPassword: "new-sasl",
            onConnectCommands: IRCOnConnectCommandPhases(), sshPassword: "", sshPrivateKey: ""
        )
        let result = context.saveResult(changes: changes, name: "Not saved yet")
        #expect(!result.succeeded)
        #expect(result.savedCredentials.serverPassword == "replacement")
        #expect(result.savedCredentials.saslPassword == nil)
        #expect(context.credentials.values[serverAccount] == "replacement")
        snapshot.recordSavedChanges(result.savedCredentials)
        let retry = snapshot.changes(
            serverPassword: "original", saslPassword: "new-sasl",
            onConnectCommands: IRCOnConnectCommandPhases(), sshPassword: "", sshPrivateKey: ""
        )
        context.credentials.rejectedWriteAccounts = []
        #expect(context.save(changes: retry))
        #expect(context.credentials.values[serverAccount] == "original")
        #expect(context.credentials.values[saslAccount] == "new-sasl")
    }

    @Test("Adding a profile after a failed save retries the same credential accounts")
    func newProfileSaveRetry() throws {
        let context = try SessionTestContext()
        defer { context.close() }
        let newID = UUID()
        func save() -> IRCProfileSaveResult {
            context.state.addProfile(
                id: newID, name: "New server", hostname: "example.org", port: 6697, useTLS: true,
                autoConnect: false, nicknameOverride: "", realNameOverride: "", mentionNotificationsOverride: nil,
                credentials: IRCProfileCredentialChanges(serverPassword: "new-password"),
                useSASL: false, saslUsername: "", useSSHTunnel: false, sshHostname: "",
                sshPort: 22, sshUsername: "", sshKeyFilename: nil
            )
        }
        context.credentials.rejectsWrites = true
        #expect(!save().succeeded)
        #expect(!context.state.profiles.contains { $0.id == newID })
        context.credentials.rejectsWrites = false
        #expect(save().succeeded)
        #expect(context.state.profiles.filter { $0.id == newID }.count == 1)
        #expect(context.credentials.values["server-password.\(newID.uuidString)"] == "new-password")
    }

    @Test("Unreadable command data is preserved on unrelated edits")
    func preservesUndecodableCommands() throws {
        let context = try SessionTestContext()
        defer { context.close() }
        let account = "on-connect-commands.\(context.profile.id.uuidString)"
        context.credentials.values[account] = "unrecognized format"
        let snapshot = context.state.credentialSnapshot(for: context.profile)
        #expect(snapshot.onConnectCommands == nil)
        let changes = snapshot.changes(
            serverPassword: "", saslPassword: "", onConnectCommands: IRCOnConnectCommandPhases(),
            sshPassword: "", sshPrivateKey: ""
        )
        #expect(context.save(changes: changes))
        #expect(context.credentials.values[account] == "unrecognized format")
        #expect(context.credentials.writes.isEmpty)
    }
}

private enum SessionTestError: Error { case timeout }

@MainActor
private func waitForSessionCondition(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw SessionTestError.timeout }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private final class SessionTestCredentials: IRCCredentialStore {
    var values: [String: String] = [:]
    var reads: [String] = []
    var writes: [String] = []
    var rejectsReads = false
    var rejectsWrites = false
    var rejectedWriteAccounts = Set<String>()

    func value(for account: String) throws -> String {
        reads.append(account)
        if rejectsReads { throw KeychainStore.AccessError(operation: .read, status: errSecInteractionNotAllowed) }
        return values[account] ?? ""
    }

    func set(_ value: String, for account: String) throws {
        if rejectsWrites || rejectedWriteAccounts.contains(account) { throw KeychainStore.AccessError(operation: .save, status: errSecInteractionNotAllowed) }
        writes.append(account)
        values[account] = value.isEmpty ? nil : value
    }
}

@MainActor
private final class SessionTestContext {
    let suiteName = "Netsplit.SessionTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let credentials: SessionTestCredentials
    let profile: ServerProfile
    let state: IRCAppState

    init(port: UInt16 = 9, commands: IRCOnConnectCommandPhases? = nil) throws {
        let profile = ServerProfile(name: "Review Server", hostname: "127.0.0.1", port: port, useTLS: false)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(try JSONEncoder().encode([profile]), forKey: "profiles")
        defaults.set("ReviewUser", forKey: "nickname")
        defaults.set("Review User", forKey: "realName")
        defaults.set(false, forKey: "reconnectAutomatically")
        defaults.set(false, forKey: "mentionNotificationsEnabled")
        defaults.set(false, forKey: "directMessageNotificationsEnabled")
        defaults.set(false, forKey: "receivesDCCFiles")
        let credentials = SessionTestCredentials()
        if let commands {
            credentials.values["on-connect-commands.\(profile.id.uuidString)"] =
                String(decoding: try JSONEncoder().encode(commands), as: UTF8.self)
        }
        self.defaults = defaults
        self.credentials = credentials
        self.profile = profile
        self.state = IRCAppState(defaults: defaults, credentialStore: credentials)
    }

    var isOnline: Bool { state.status(for: profile) == .online }
    var serverItem: SidebarItem { .server(profile.id) }
    var allMessages: [IRCMessage] {
        messages(in: serverItem)
            + state.channels.flatMap { messages(in: .channel($0.id)) }
            + state.directMessages.flatMap { messages(in: .directMessage($0.id)) }
    }

    func messages(in item: SidebarItem) -> [IRCMessage] {
        state.messages(for: item, channelEventVisibility: .alwaysShow)
    }

    func save(changes: IRCProfileCredentialChanges, name: String = "Review Server") -> Bool {
        saveResult(changes: changes, name: name).succeeded
    }

    func saveResult(changes: IRCProfileCredentialChanges, name: String = "Review Server") -> IRCProfileSaveResult {
        state.updateProfile(
            profile, name: name, hostname: profile.hostname, port: profile.port, useTLS: profile.useTLS,
            autoConnect: false, nicknameOverride: "", realNameOverride: "", mentionNotificationsOverride: nil,
            credentials: changes, useSASL: false, saslUsername: "", useSSHTunnel: false,
            sshHostname: "", sshPort: 22, sshUsername: "", sshKeyFilename: nil, resetSSHHostKey: false
        )
    }

    func close() {
        state.disconnect(profile)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class SessionTestServer {
    private let listener: NWListener
    private var connection: NWConnection?
    private var buffer = Data()
    private var hasUser = false
    private var hasEndedCAP = false
    private var hasRegistered = false
    private let capabilities: [String]
    private let echoesMessages: Bool
    private(set) var port: UInt16?
    private(set) var lines: [String] = []
    var confirmsJoins = false
    var joinRejection: String?
    var messageRejection: String?
    var holdsMessageReplies = false

    init(labeled: Bool = false, echoesMessages: Bool = false) throws {
        self.echoesMessages = echoesMessages
        capabilities = (echoesMessages ? ["echo-message"] : [])
            + (labeled ? ["message-tags", "batch", "labeled-response"] : [])
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .ready = status { self.port = self.listener.port?.rawValue }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            DispatchQueue.main.async {
                guard let self else { return }
                self.connection = connection
                self.buffer = Data()
                self.hasUser = false
                self.hasEndedCAP = false
                self.hasRegistered = false
                connection.start(queue: .main)
                self.receive(connection)
            }
        }
        listener.start(queue: .main)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            DispatchQueue.main.async {
                guard let self, self.connection === connection else { return }
                if let data {
                    self.buffer.append(data)
                    while let end = self.buffer.firstIndex(of: 10) {
                        let line = String(decoding: self.buffer[..<end], as: UTF8.self).trimmingCharacters(in: .newlines)
                        self.buffer.removeSubrange(...end)
                        self.lines.append(line)
                        self.handle(line)
                    }
                }
                if !done && error == nil { self.receive(connection) }
            }
        }
    }

    private func handle(_ line: String) {
        guard let wire = IRCWireMessage(line: line) else { return }
        let label = (wire.tags["label"] ?? nil).map { "@label=\($0) " } ?? ""
        switch wire.command {
        case "CAP":
            switch wire.parameter(at: 0) {
            case "LS": send(":review CAP * LS :\(capabilities.joined(separator: " "))")
            case "REQ": send(":review CAP * ACK :\(wire.parameter(at: 1) ?? "")")
            case "END": hasEndedCAP = true
            default: break
            }
        case "USER": hasUser = true
        case "MOTD": send(":review 422 ReviewUser :No MOTD")
        case "NAMES":
            if let channel = wire.parameter(at: 0) {
                send(":review 353 ReviewUser = \(channel) :Alice Bob\r\n:review 366 ReviewUser \(channel) :End of NAMES")
            }
        case "JOIN":
            if let channel = wire.parameter(at: 0) {
                if let joinRejection { send(":review \(joinRejection) ReviewUser \(channel) :Join rejected") }
                else if confirmsJoins { send(":ReviewUser!u@h JOIN \(channel)") }
            }
        case "PRIVMSG", "NOTICE":
            guard !holdsMessageReplies else { break }
            if let targets = wire.parameter(at: 0), let text = wire.parameter(at: 1) {
                let targets = targets.split(separator: ",")
                let batchID = !label.isEmpty && targets.count > 1 ? UUID().uuidString : nil
                if let batchID { send("\(label):review BATCH +\(batchID) labeled-response") }
                let responseTags = batchID.map { "@batch=\($0) " } ?? label
                for target in targets {
                    if messageRejection == "FAIL" {
                        send("\(responseTags):review FAIL \(wire.command) REJECTED \(target) :Rejected message: \(text)")
                    } else if let messageRejection {
                        send("\(responseTags):review \(messageRejection) ReviewUser \(target) :Rejected message: \(text)")
                    } else if echoesMessages {
                        send("\(responseTags):ReviewUser!u@h \(wire.command) \(target) :\(text)")
                    }
                }
                if let batchID { send(":review BATCH -\(batchID)") }
            }
        case "QUIT": connection?.cancel()
        default: break
        }
        if hasUser && hasEndedCAP && !hasRegistered {
            hasRegistered = true
            send(":review 001 ReviewUser :Welcome")
        }
    }

    func send(_ line: String) {
        connection?.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { _ in })
    }

    func synchronize() async throws {
        let token = "test-fence-\(UUID().uuidString)"
        send("PING :\(token)")
        try await waitForSessionCondition { self.lines.contains("PONG :\(token)") }
    }

    func stop() {
        listener.cancel()
        connection?.cancel()
    }
}
