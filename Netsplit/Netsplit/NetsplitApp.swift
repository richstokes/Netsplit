//
//  NetsplitApp.swift
//  Netsplit
//
//  Created by Richard Stokes on 7/16/26.
//

import AppKit
import SwiftUI

final class NetsplitAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: IRCAppState?
    private var isTerminating = false
    private var hasRepliedToTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notifications.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        state?.systemWillSleep()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        state?.systemDidWake()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        guard let state else { return .terminateNow }
        isTerminating = true

        state.quitAllConnections { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasRepliedToTermination else { return }
                self.hasRepliedToTermination = true
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct NetsplitApp: App {
    @StateObject private var state = IRCAppState()
    @NSApplicationDelegateAdaptor(NetsplitAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 920, minHeight: 620)
                .onAppear {
                    appDelegate.state = state
                }
                .task {
                    state.connectProfilesConfiguredForLaunch()
                }
        }
        .commands {
            CommandMenu("Connection") {
                Button("Connect") { state.showConnections() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Browse Channels") {
                    state.requestChannelListing()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!state.canBrowseSelectedChannels)
                Button("Show Connections") { state.showConnections() }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { state.adjustTranscriptFontSize(by: 1) }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { state.adjustTranscriptFontSize(by: -1) }
                    .keyboardShortcut("-", modifiers: [.command])
                Divider()
                Button("Actual Size") { state.resetTranscriptFontSize() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }
        Settings {
            SettingsView(state: state)
        }
    }
}
