//
//  NetsplitApp.swift
//  Netsplit
//
//  Created by Richard Stokes on 7/16/26.
//

import AppKit
import SwiftUI
import UserNotifications

private enum AppSceneID {
    // SwiftUI uses this identity for persisted window state. Keep it stable.
    static let mainWindow = "main"
}

final class NetsplitAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var state: IRCAppState? {
        didSet { deliverPendingMentionNotificationDestination() }
    }
    weak var mainWindow: NSWindow?
    private var isTerminating = false
    private var hasRepliedToTermination = false
    private var shortcutMonitor: Any?
    private var pendingMentionNotificationDestination: IRCMentionNotificationDestination?
    private let swipeCommitThreshold: CGFloat = 0.25

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
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

        // Handle conversation, server, pane, and history shortcuts before
        // AppKit turns Command-W into Close Window or delivers shortcut input
        // elsewhere.
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .otherMouseDown, .scrollWheel, .swipe]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event)
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        state?.systemWillSleep()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        state?.systemDidWake()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let serverIDValue = response.notification.request.content.userInfo["serverID"] as? String,
              let channelName = response.notification.request.content.userInfo["channelName"] as? String,
              let serverID = UUID(uuidString: serverIDValue),
              !channelName.isEmpty else {
            completionHandler()
            return
        }

        let destination = IRCMentionNotificationDestination(serverID: serverID, channelName: channelName)

        DispatchQueue.main.async { [weak self] in
            self?.openMentionNotification(destination)
            NSApp.activate(ignoringOtherApps: true)
            self?.mainWindow?.makeKeyAndOrderFront(nil)
            completionHandler()
        }
    }

    private func openMentionNotification(_ destination: IRCMentionNotificationDestination) {
        guard let state else {
            pendingMentionNotificationDestination = destination
            return
        }
        pendingMentionNotificationDestination = nil
        state.openMentionNotification(destination)
    }

    private func deliverPendingMentionNotificationDestination() {
        guard let pendingMentionNotificationDestination, state != nil else { return }
        openMentionNotification(pendingMentionNotificationDestination)
    }

    private func handleShortcutEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === mainWindow, mainWindow?.attachedSheet == nil else { return event }

        switch event.type {
        case .keyDown:
            let shortcutModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !event.isARepeat,
                  shortcutModifiers == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w" where state?.canCloseActiveSelection == true:
                state?.closeActiveSelection()
                return nil
            case "e":
                state?.toggleServerChannelPane()
                return nil
            case "k":
                state?.presentJumpPalette()
                return nil
            case "[":
                if state?.canNavigateBack == true {
                    state?.navigateBack()
                }
                return nil
            case "]":
                if state?.canNavigateForward == true {
                    state?.navigateForward()
                }
                return nil
            case let digit? where digit.count == 1 && ("1"..."9").contains(digit):
                guard let number = Int(digit), state?.selectActiveServer(number: number) == true else {
                    return event
                }
                return nil
            default:
                return event
            }

        case .otherMouseDown:
            switch event.buttonNumber {
            case 3 where state?.canNavigateBack == true:
                state?.navigateBack()
                return nil
            case 4 where state?.canNavigateForward == true:
                state?.navigateForward()
                return nil
            default:
                return event
            }

        case .scrollWheel:
            return beginSwipeTracking(with: event) ? nil : event

        case .swipe:
            if event.deltaX > 0, state?.canNavigateBack == true {
                state?.navigateBack()
                return nil
            }
            if event.deltaX < 0, state?.canNavigateForward == true {
                state?.navigateForward()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func beginSwipeTracking(with event: NSEvent) -> Bool {
        guard event.phase == .began || event.phase == .changed,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              let state else { return false }

        let canGoBack = state.canNavigateBack
        let canGoForward = state.canNavigateForward
        guard (event.scrollingDeltaX > 0 && canGoBack) ||
              (event.scrollingDeltaX < 0 && canGoForward) else { return false }

        var didNavigate = false
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canGoForward ? -1 : 0,
            max: canGoBack ? 1 : 0
        ) { [weak self] amount, phase, isComplete, _ in
            guard let self, !didNavigate else { return }

            // Commit once the gesture is clearly intentional instead of
            // waiting for finger lift or AppKit's settling animation. Keep the
            // completed amount as a fallback so a short, fast flick still
            // follows system behavior.
            let reachedPhysicalThreshold = phase == .changed && abs(amount) >= swipeCommitThreshold
            let systemCommittedSwipe = isComplete && abs(amount) >= 1
            guard reachedPhysicalThreshold || systemCommittedSwipe else { return }

            didNavigate = true
            if amount > 0 {
                state.navigateBack()
            } else if amount < 0 {
                state.navigateForward()
            }
        }
        return true
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
        WindowGroup(id: AppSceneID.mainWindow) {
            ContentView(state: state)
                .frame(minWidth: 920, minHeight: 620)
                .ircApplicationAppearance(state.applicationAppearance)
                .onAppear {
                    appDelegate.state = state
                    DispatchQueue.main.async {
                        appDelegate.mainWindow = NSApp.keyWindow
                    }
                }
                .task {
                    state.connectProfilesConfiguredForLaunch()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Close Current Conversation") {
                    state.closeActiveSelection()
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!state.canCloseActiveSelection)
            }
            CommandMenu("Connection") {
                Button("Browse Channels…") {
                    state.requestChannelListing()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!state.canBrowseSelectedChannels)
                Button("Show Connections") { state.showConnections() }
            }
            CommandMenu("Navigate") {
                Button("Jump to Server or Conversation…") { state.presentJumpPalette() }
                    .keyboardShortcut("k", modifiers: [.command])
                Divider()
                Button("Back") { state.navigateBack() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!state.canNavigateBack)
                Button("Forward") { state.navigateForward() }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!state.canNavigateForward)
                if !state.activeProfiles.isEmpty {
                    Divider()
                    ForEach(Array(state.activeProfiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                        Button("Server \(index + 1): \(profile.name)") {
                            state.selectActiveServer(number: index + 1)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                    }
                }
                Divider()
                Button("Move Focus to Sidebar") { state.requestSidebarFocus() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Move Focus to Message Field") { state.requestComposerFocus() }
                    .keyboardShortcut("m", modifiers: [.command, .control])
                    .disabled(state.selection == nil || state.selection == .connectionCenter)
            }
            CommandGroup(after: .toolbar) {
                Button(state.showsServerChannelPane ? "Hide Server/Channel Pane" : "Show Server/Channel Pane") {
                    state.toggleServerChannelPane()
                }
                .keyboardShortcut("e", modifiers: [.command])
                Divider()
                Button(state.showsMemberList ? "Hide Members" : "Show Members") {
                    state.toggleMemberList()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!state.canToggleMemberList)
                Divider()
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
                .ircApplicationAppearance(state.applicationAppearance)
        }
    }
}
