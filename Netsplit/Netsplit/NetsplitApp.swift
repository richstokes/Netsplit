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
    weak var mainWindow: NSWindow?
    private var isTerminating = false
    private var hasRepliedToTermination = false
    private var shortcutMonitor: Any?
    private let swipeCommitThreshold: CGFloat = 0.25

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

        // Handle conversation and history shortcuts before AppKit turns
        // Command-W into Close Window or delivers navigation input elsewhere.
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
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 920, minHeight: 620)
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
                Button("Browse Channels") {
                    state.requestChannelListing()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!state.canBrowseSelectedChannels)
                Button("Show Connections") { state.showConnections() }
                    .keyboardShortcut("k", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
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
        }
    }
}
