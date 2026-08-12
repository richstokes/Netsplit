//
//  IRCTranscriptTable.swift
//  Netsplit
//

import AppKit
import QuartzCore
import SwiftUI

struct IRCTranscriptTableGeometry {
    let visibleBounds: CGRect
    let contentBounds: CGRect
    let documentFrame: CGRect
    let contentIsFlipped: Bool
}

struct IRCTranscriptRowLayoutInvalidation: Equatable {
    let messageID: UUID
    let revision: UInt64
}

/// A view-based AppKit table that realizes only visible transcript rows while
/// retaining the existing SwiftUI row implementation and its interactions.
struct IRCTranscriptTable: NSViewRepresentable {
    /// Identifies the conversation displayed by this retained native table.
    /// A change replaces its content in place instead of rebuilding the
    /// NSScrollView/NSTableView hierarchy.
    let contentIdentity: SidebarItem?
    let messages: [IRCMessage]
    /// Makes the representable update when its conversation-scoped signal
    /// advances without treating that signal as a row-render configuration.
    let updateRevision: Int
    let estimatedRowHeight: CGFloat
    let rowSpacing: CGFloat
    let renderConfiguration: String
    let rowLayoutInvalidation: IRCTranscriptRowLayoutInvalidation?
    let makeRow: (IRCMessage) -> AnyView
    let onInitialPositioned: ((IRCTranscriptTableGeometry) -> Void)?
    let onFollowingTailChange: ((Bool, IRCTranscriptTableGeometry) -> Void)?
    let onTailPositioned: ((Bool, IRCTranscriptTableGeometry) -> Void)?
    let onGeometryChange: ((String, IRCTranscriptTableGeometry) -> Void)?

    init(
        contentIdentity: SidebarItem? = nil,
        messages: [IRCMessage],
        updateRevision: Int = 0,
        estimatedRowHeight: CGFloat,
        rowSpacing: CGFloat,
        renderConfiguration: String,
        rowLayoutInvalidation: IRCTranscriptRowLayoutInvalidation? = nil,
        makeRow: @escaping (IRCMessage) -> AnyView,
        onInitialPositioned: ((IRCTranscriptTableGeometry) -> Void)? = nil,
        onFollowingTailChange: ((Bool, IRCTranscriptTableGeometry) -> Void)? = nil,
        onTailPositioned: ((Bool, IRCTranscriptTableGeometry) -> Void)? = nil,
        onGeometryChange: ((String, IRCTranscriptTableGeometry) -> Void)? = nil
    ) {
        self.contentIdentity = contentIdentity
        self.messages = messages
        self.updateRevision = updateRevision
        self.estimatedRowHeight = estimatedRowHeight
        self.rowSpacing = rowSpacing
        self.renderConfiguration = renderConfiguration
        self.rowLayoutInvalidation = rowLayoutInvalidation
        self.makeRow = makeRow
        self.onInitialPositioned = onInitialPositioned
        self.onFollowingTailChange = onFollowingTailChange
        self.onTailPositioned = onTailPositioned
        self.onGeometryChange = onGeometryChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TranscriptScrollView {
        let scrollView = TranscriptScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("IRCTranscriptScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        // The table begins at row zero and is positioned at the tail on the
        // next main-loop turn. Do not expose that transient top position.
        scrollView.alphaValue = 0

        let tableView = NSTableView()
        tableView.identifier = NSUserInterfaceItemIdentifier("IRCTranscriptTable")
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.rowHeight = estimatedRowHeight
        tableView.usesAutomaticRowHeights = true
        tableView.autoresizingMask = [.width]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Transcript"))
        column.resizingMask = .autoresizingMask
        column.isEditable = false
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        scrollView.documentView = tableView
        context.coordinator.attach(scrollView: scrollView, tableView: tableView)
        tableView.reloadData()
        context.coordinator.scheduleInitialPosition()
        return scrollView
    }

    func updateNSView(_ scrollView: TranscriptScrollView, context: Context) {
        context.coordinator.update(parent: self)
    }

    static func dismantleNSView(_ nsView: TranscriptScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private struct ReadingAnchor {
            struct Candidate {
                let messageID: UUID
                let viewportOffset: CGFloat
            }

            let candidates: [Candidate]
        }

        /// Exact heights measured by realized hosting views, retained as
        /// estimates for the next visit to the same conversation. AppKit
        /// still verifies every realized row through automatic row heights,
        /// so this cache can accelerate document geometry without becoming a
        /// second source of layout truth.
        private final class ConversationRowHeightCache {
            let viewportWidth: CGFloat
            let renderConfiguration: String
            var heightsByMessageID: [UUID: CGFloat]
            var lastAccess: UInt64

            init(
                viewportWidth: CGFloat,
                renderConfiguration: String,
                heightsByMessageID: [UUID: CGFloat],
                lastAccess: UInt64
            ) {
                self.viewportWidth = viewportWidth
                self.renderConfiguration = renderConfiguration
                self.heightsByMessageID = heightsByMessageID
                self.lastAccess = lastAccess
            }
        }

#if DEBUG
        private struct RowHeightCacheSwitchSnapshot {
            let hasContentIdentity: Bool
            let switchMessageCount: Int
            let switchStartWidth: CGFloat
            let storedCount: Int
            let cachedWidth: CGFloat?
            let cachedRenderConfiguration: String?
        }
#endif

        private static let topInset: CGFloat = 18
        private static let bottomInset: CGFloat = 18
        private static let messageCellIdentifier = NSUserInterfaceItemIdentifier(
            "IRCTranscriptMessageCell"
        )
        private static let detachedContentReleaseDelay: TimeInterval = 2
        private static let settledWidthRefreshDelay: TimeInterval = 0.08
        private static let maximumCachedConversationCount = 24

        private var parent: IRCTranscriptTable
        private var contentIdentity: SidebarItem?
        private var messages: [IRCMessage]
        private var renderConfiguration: String
        private var rowLayoutInvalidation: IRCTranscriptRowLayoutInvalidation?
        private weak var scrollView: TranscriptScrollView?
        private weak var tableView: NSTableView?
        private var observers: [NSObjectProtocol] = []
        private var hasPositionedInitially = false
        private var initialPositionScheduled = false
        private var followingTail: Bool
        private var topSpacerHeight = topInset
        private var lastViewportWidth: CGFloat = 0
        private var lastViewportHeight: CGFloat = 0
        private var pendingHeightMessageIDs = Set<UUID>()
        private var initiallyVerifiedMessageIDs = Set<UUID>()
        private var heightInvalidationScheduled = false
        private var fullHeightRefreshScheduled = false
        private var viewportHeightReconciliationScheduled = false
        private var pendingTailWorkItem: DispatchWorkItem?
        private var lastAnimatedScroll = Date.distantPast
        private var isAwaitingTailPosition = false
        private var pendingTailStartOrigin: NSPoint?
        private var isRestoringReadingPosition = false
        private var tailPositionGeneration = 0
        private var attachmentGeneration = 0
        private var hasPendingPositionReport = false
        private var pendingFollowingTailReport: (Bool, IRCTranscriptTableGeometry)?
#if DEBUG
        private var pendingDebugGeometryWorkItem: DispatchWorkItem?
        private var crossConversationCellsDiscarded = 0
        private var pendingRowHeightCacheSwitchSnapshot: RowHeightCacheSwitchSnapshot?
#endif
        private var hasPendingWidthRefresh = false
        private var pendingWidthRefreshWorkItem: DispatchWorkItem?
        private var widthRefreshGeneration = 0
        /// Width represented by the estimates NSTableView has most recently
        /// loaded. Keep this stable during a debounced pane resize: Apple's
        /// delegate contract requires a row to return the same estimate until
        /// reloadData or noteHeightOfRows invalidates AppKit's cache.
        private var rowHeightEstimateViewportWidth: CGFloat = 0
        private var rowHeightCaches: [SidebarItem: ConversationRowHeightCache] = [:]
        private var rowHeightCacheAccess: UInt64 = 0
        private var appliedRowLayoutRevisions: [SidebarItem: UInt64] = [:]

        init(parent: IRCTranscriptTable) {
            self.parent = parent
            contentIdentity = parent.contentIdentity
            messages = parent.messages
            renderConfiguration = parent.renderConfiguration
            rowLayoutInvalidation = parent.rowLayoutInvalidation
            followingTail = true
        }

        func attach(scrollView: TranscriptScrollView, tableView: NSTableView) {
            attachmentGeneration &+= 1
            self.scrollView = scrollView
            self.tableView = tableView
            scrollView.onViewportWidthChange = { [weak self] width in
                self?.viewportWidthDidChange(width)
            }
            scrollView.onViewportHeightChange = { [weak self] height in
                self?.viewportHeightDidChange(height)
            }
            scrollView.onUserScroll = { [weak self] in
                self?.userDidScroll()
            }

            let center = NotificationCenter.default
            // MainActor.assumeIsolated below requires queue: .main; do not
            // change these observers to synchronous posting-thread delivery.
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollPositionDidChange(event: "bounds-changed")
                }
            })
            observers.append(center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollPositionDidChange(event: "live-scroll-ended")
                }
            })
            observers.append(center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.userDidScroll()
                }
            })
        }

        func detach() {
            attachmentGeneration &+= 1
            pendingTailWorkItem?.cancel()
            pendingTailWorkItem = nil
            isAwaitingTailPosition = false
            pendingTailStartOrigin = nil
            isRestoringReadingPosition = false
            pendingHeightMessageIDs.removeAll()
            initiallyVerifiedMessageIDs.removeAll()
            initialPositionScheduled = false
            heightInvalidationScheduled = false
            fullHeightRefreshScheduled = false
            viewportHeightReconciliationScheduled = false
            tailPositionGeneration &+= 1
#if DEBUG
            pendingDebugGeometryWorkItem?.cancel()
            pendingDebugGeometryWorkItem = nil
            crossConversationCellsDiscarded = 0
            pendingRowHeightCacheSwitchSnapshot = nil
#endif
            hasPendingPositionReport = false
            pendingFollowingTailReport = nil
            pendingWidthRefreshWorkItem?.cancel()
            pendingWidthRefreshWorkItem = nil
            hasPendingWidthRefresh = false
            rowHeightEstimateViewportWidth = 0
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
            scrollView?.onViewportWidthChange = nil
            scrollView?.onViewportHeightChange = nil
            scrollView?.onUserScroll = nil
            tableView?.delegate = nil
            tableView?.dataSource = nil
            scrollView?.documentView = nil
            scrollView = nil
            tableView = nil
        }

        func update(parent: IRCTranscriptTable) {
            let oldMessages = messages
            let contentChanged = contentIdentity != parent.contentIdentity
            let configurationChanged = renderConfiguration != parent.renderConfiguration
            let rowLayoutChanged = rowLayoutInvalidation != parent.rowLayoutInvalidation

            if contentChanged || configurationChanged, let tableView {
                // Capture the outgoing layout before replacing the identity or
                // configuration used to key its measurements.
                cacheRealizedRowHeights(in: tableView)
            }
            self.parent = parent
            contentIdentity = parent.contentIdentity
            renderConfiguration = parent.renderConfiguration
            rowLayoutInvalidation = parent.rowLayoutInvalidation

            guard let tableView, let scrollView else {
                messages = parent.messages
                return
            }

            if contentChanged {
                replaceConversationContent(
                    with: parent.messages,
                    in: tableView,
                    scrollView: scrollView
                )
            } else if configurationChanged {
                let readingAnchor = beginReadingPositionRestoration()
                messages = parent.messages
                tableView.intercellSpacing.height = parent.rowSpacing
                tableView.rowHeight = parent.estimatedRowHeight
                tableView.reloadData()
                adjustTopSpacerForShortContent()
                // Restore before updateNSView can paint the reloaded table.
                // The deferred full-height sweep anchors again around row
                // remeasurement once the new SwiftUI configuration settles.
                finishReadingPositionRestoration(
                    readingAnchor,
                    event: "configuration-reloaded-anchor-restored"
                )
                scheduleHeightRefresh()
            } else if parent.messages != oldMessages {
                applyMessageUpdate(from: oldMessages, to: parent.messages, in: tableView)
            }

            if !contentChanged, rowLayoutChanged, let rowLayoutInvalidation {
                invalidateRowLayout(
                    rowLayoutInvalidation,
                    in: tableView
                )
            }

            if !hasPositionedInitially, !messages.isEmpty {
                scheduleInitialPosition()
            }
        }

        /// Reuse the native transcript hierarchy while giving each
        /// conversation a fresh positioning and row-state lifecycle. The
        /// replacement remains hidden until automatic row heights settle.
        private func replaceConversationContent(
            with newMessages: [IRCMessage],
            in tableView: NSTableView,
            scrollView: TranscriptScrollView
        ) {
            // Invalidate work queued for the outgoing conversation without
            // detaching the observers or native view hierarchy.
            attachmentGeneration &+= 1
            pendingTailWorkItem?.cancel()
            pendingTailWorkItem = nil
            tailPositionGeneration &+= 1
            // The native scroll view is intentionally retained across
            // conversations. A trackpad gesture can therefore keep sending
            // momentum events after the sidebar selection has changed and
            // move the newly positioned transcript away from its tail.
            // Ignore only that inherited momentum; the next direct gesture
            // clears the suppression and scrolls normally.
            scrollView.discardMomentumUntilNextDirectScroll()
#if DEBUG
            pendingDebugGeometryWorkItem?.cancel()
            pendingDebugGeometryWorkItem = nil
            crossConversationCellsDiscarded = 0
            pendingRowHeightCacheSwitchSnapshot = nil
#endif

            scrollView.alphaValue = 0
            hasPositionedInitially = false
            initialPositionScheduled = false
            followingTail = true
            topSpacerHeight = Self.topInset
            pendingHeightMessageIDs.removeAll()
            initiallyVerifiedMessageIDs.removeAll()
            heightInvalidationScheduled = false
            fullHeightRefreshScheduled = false
            viewportHeightReconciliationScheduled = false
            isAwaitingTailPosition = false
            pendingTailStartOrigin = nil
            isRestoringReadingPosition = false
            hasPendingPositionReport = false
            pendingFollowingTailReport = nil
            pendingWidthRefreshWorkItem?.cancel()
            pendingWidthRefreshWorkItem = nil
            hasPendingWidthRefresh = false
            lastAnimatedScroll = .distantPast
            lastViewportWidth = max(0, scrollView.contentView.bounds.width)
            lastViewportHeight = max(0, scrollView.contentView.bounds.height)
            rowHeightEstimateViewportWidth = lastViewportWidth

            messages = newMessages
            pruneCachedRowHeights(to: newMessages)
            applyPendingRowLayoutInvalidation(to: newMessages)
            touchCurrentRowHeightCache()
#if DEBUG
            pendingRowHeightCacheSwitchSnapshot = rowHeightCacheSwitchSnapshot(
                messageCount: newMessages.count
            )
#endif
            tableView.intercellSpacing.height = parent.rowSpacing
            tableView.rowHeight = parent.estimatedRowHeight
            tableView.reloadData()

            // A full sweep gives automatic row heights their final width-aware
            // values before scheduleInitialPosition reveals the new content.
            scheduleHeightRefresh()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            messages.count + 2
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if row == 0 {
                return topSpacerHeight
            }
            if row == messages.count + 1 {
                return Self.bottomInset
            }
            guard let message = message(atTableRow: row) else {
                return -1
            }
            guard let cachedHeight = cachedRowHeight(for: message.id) else {
                // A retained NSTableView keeps automatic-height proposals by
                // row index across reloadData. During initial/replacement
                // layout, an incoming message received while inactive has no
                // cached measurement and can otherwise inherit a wildly
                // different outgoing row's height. Seed every unmeasured row
                // with this transcript's clean estimate while it remains
                // hidden; realized rows publish their exact intrinsic height
                // before initial positioning completes.
                return hasPositionedInitially ? -1 : parent.estimatedRowHeight
            }
            return cachedHeight
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let message = message(atTableRow: row) else {
                return TranscriptSpacerCellView(
                    height: row == 0 ? topSpacerHeight : Self.bottomInset
                )
            }

            let reusableCell = tableView.makeView(
                withIdentifier: Self.messageCellIdentifier,
                owner: self
            ) as? TranscriptMessageCellView
            let cell: TranscriptMessageCellView
            if let reusableCell,
               reusableCell.canReuse(for: contentIdentity) {
                cell = reusableCell
            } else {
                // Row-height measurements are scoped per conversation, so
                // the hosted AppKit view must use the same boundary. Directly
                // retargeting a cell from another conversation can briefly
                // expose its outgoing SwiftUI intrinsic height before the new
                // root settles, leaving an incorrect automatic row height.
                if let reusableCell {
                    reusableCell.releaseHostedContent()
#if DEBUG
                    crossConversationCellsDiscarded += 1
#endif
                }
                cell = TranscriptMessageCellView()
                cell.identifier = Self.messageCellIdentifier
                cell.hostingView.onIntrinsicSizeInvalidated = { [weak self] messageID in
                    self?.scheduleHeightInvalidation(for: messageID)
                }
            }
            cell.assignReuseScope(contentIdentity)
            let cancelledPendingRelease = cell.hostingView.setHostedContent(
                sizedRow(message, width: currentContentWidth(in: tableView)),
                for: message.id
            )
#if DEBUG
            if cancelledPendingRelease {
                reportHostedContentLifecycle(
                    "release-cancelled-reconfigured",
                    messageID: message.id,
                    row: row
                )
            }
#endif
            return cell
        }

        func tableView(
            _ tableView: NSTableView,
            didAdd rowView: NSTableRowView,
            forRow row: Int
        ) {
            for case let cell as TranscriptMessageCellView in rowView.subviews {
                let messageID = cell.hostingView.representedMessageID
                guard cell.hostingView.cancelPendingHostedContentRelease() else { continue }
#if DEBUG
                reportHostedContentLifecycle(
                    "release-cancelled-reattached",
                    messageID: messageID,
                    row: row
                )
#endif
            }
        }

        func tableView(
            _ tableView: NSTableView,
            didRemove rowView: NSTableRowView,
            forRow row: Int
        ) {
            // NSTableView can remove and re-add a row while automatic heights
            // settle. Keep its SwiftUI state alive through that transient
            // churn, then release the graph only if the row stays detached.
            for case let cell as TranscriptMessageCellView in rowView.subviews {
                let messageID = cell.hostingView.representedMessageID
                cell.hostingView.scheduleHostedContentRelease(
                    after: Self.detachedContentReleaseDelay,
                    shouldRelease: { [weak tableView, weak cell] in
                        guard let tableView, let cell else { return true }
                        return tableView.row(for: cell) == -1
                    },
                    completion: { [weak self] released in
#if DEBUG
                        self?.reportHostedContentLifecycle(
                            released ? "released" : "release-skipped-attached",
                            messageID: messageID,
                            row: row
                        )
#endif
                    }
                )
#if DEBUG
                reportHostedContentLifecycle(
                    "release-scheduled",
                    messageID: messageID,
                    row: row
                )
#endif
            }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func scheduleInitialPosition() {
            guard !messages.isEmpty,
                  !hasPositionedInitially,
                  !initialPositionScheduled else { return }
            initialPositionScheduled = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                self.initialPositionScheduled = false
                guard let scrollView = self.scrollView,
                      let tableView = self.tableView,
                      !self.hasPositionedInitially else { return }
                scrollView.layoutSubtreeIfNeeded()
                tableView.layoutSubtreeIfNeeded()
                let viewportSize = scrollView.contentView.bounds.size
                guard viewportSize.width > 1,
                      viewportSize.height > 1,
                      tableView.bounds.width > 1 else {
                    // A newly selected detail can briefly be realized at
                    // zero size. Revealing or tail-positioning in that state
                    // produces a visible second correction after split-view
                    // layout supplies the real viewport.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                        guard let self, self.attachmentGeneration == generation else { return }
                        self.scheduleInitialPosition()
                    }
                    return
                }
                self.positionAtTail()
                self.adjustTopSpacerForShortContent()
                self.positionAtTail()
                // Positioning can realize a new set of tail cells after the
                // deferred full-height sweep has already run. Reconcile every
                // intersecting message now so a recycled cell's previous
                // intrinsic height cannot survive until the next append.
                let visibleRowsNeedAnotherPass = self.reconcileVisibleMessageRows(
                    in: tableView
                )
                tableView.layoutSubtreeIfNeeded()
                if visibleRowsNeedAnotherPass {
                    self.adjustTopSpacerForShortContent()
                    self.positionAtTail()
                    // Invalidating a stale row can bring one more row into the
                    // viewport, while a newly realized SwiftUI root may need
                    // a run-loop turn to publish its intrinsic height. Verify
                    // the now-stable visible set before revealing the table.
                    self.scheduleInitialPosition()
                    return
                }
                guard !self.hasPendingInitialLayoutWork else {
                    // Positioning realizes the tail rows and can discover the
                    // viewport width for the first time. Let the resulting
                    // hosting-view invalidations and full height sweep finish
                    // before exposing geometry based on row estimates.
                    self.scheduleInitialPosition()
                    return
                }
                self.hasPositionedInitially = true
                scrollView.alphaValue = 1
                let geometry = self.geometry()
                self.parent.onInitialPositioned?(geometry)
#if DEBUG
                if let cacheSnapshot = self.pendingRowHeightCacheSwitchSnapshot {
                    self.pendingRowHeightCacheSwitchSnapshot = nil
                    self.parent.onGeometryChange?(
                        self.rowHeightCacheSwitchSummary(
                            cacheSnapshot,
                            attachedMessageCount: self.messages.count,
                            finalWidth: geometry.visibleBounds.width
                        ),
                        geometry
                    )
                }
                if self.crossConversationCellsDiscarded > 0 {
                    self.parent.onGeometryChange?(
                        "cross-conversation-cells-discarded count=\(self.crossConversationCellsDiscarded)",
                        geometry
                    )
                }
                self.parent.onGeometryChange?("attached", geometry)
#endif
            }
        }

        private var hasPendingInitialLayoutWork: Bool {
            hasPendingWidthRefresh
                || fullHeightRefreshScheduled
                || heightInvalidationScheduled
                || !pendingHeightMessageIDs.isEmpty
        }

        // AppKit retains the old automatic-height proposal for both in-place
        // and row-scoped hosted-view invalidation. Preview load notifications
        // are debounced before reaching this fallback so a burst pays for one
        // known-correct full measurement rather than one per resource.
        private func invalidateRowLayout(
            _ invalidation: IRCTranscriptRowLayoutInvalidation,
            in tableView: NSTableView
        ) {
            guard messages.contains(where: { $0.id == invalidation.messageID }) else {
                return
            }
            guard needsApplying(invalidation) else { return }
            // Preview-load notifications are coalesced per conversation, so
            // the final signal can represent several rows changing height.
            // Discard every estimate for that conversation before the full
            // reload rather than leaving earlier previews with stale values.
            removeCurrentRowHeightCache()
            recordApplied(invalidation)
            let readingAnchor = beginReadingPositionRestoration()
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()
            adjustTopSpacerForShortContent()
            finishReadingPositionRestoration(
                readingAnchor,
                event: "row-layout-reloaded-anchor-restored"
            )
            if readingAnchor == nil, followingTail {
                positionAtTail()
            }
#if DEBUG
            parent.onGeometryChange?(
                "row-layout-reloaded message=\(String(invalidation.messageID.uuidString.prefix(8)))",
                geometry()
            )
#endif
        }

        private func applyMessageUpdate(
            from oldMessages: [IRCMessage],
            to newMessages: [IRCMessage],
            in tableView: NSTableView
        ) {
            let preservesMessageIdentity = oldMessages.count == newMessages.count
                && zip(oldMessages, newMessages).allSatisfy { oldMessage, newMessage in
                    oldMessage.id == newMessage.id
                }
            if preservesMessageIdentity {
                let changedIndexes = oldMessages.indices.filter {
                    oldMessages[$0] != newMessages[$0]
                }
                reconfigureMessagesInPlace(
                    at: changedIndexes,
                    with: newMessages,
                    in: tableView
                )
                return
            }

            let appendedCount = newMessages.count - oldMessages.count
            let isSimpleAppend = appendedCount > 0
                && (oldMessages.isEmpty
                    || (newMessages.first?.id == oldMessages.first?.id
                        && newMessages[oldMessages.count - 1].id == oldMessages.last?.id))
            let readingAnchor = isSimpleAppend ? nil : beginReadingPositionRestoration()
            if followingTail, hasPositionedInitially {
                if !isAwaitingTailPosition || pendingTailWorkItem == nil {
                    pendingTailStartOrigin = tailOrigin()
                }
                isAwaitingTailPosition = true
            }

            messages = newMessages
            if isSimpleAppend {
                let insertedRows = IndexSet(
                    integersIn: (oldMessages.count + 1)..<(newMessages.count + 1)
                )
                tableView.insertRows(at: insertedRows, withAnimation: [])
            } else {
                // Appends cannot invalidate any existing measurement. Avoid
                // rebuilding a retained-ID set on the hot arrival path; only
                // deletion, trimming, or replacement needs cache pruning.
                pruneCachedRowHeights(to: newMessages)
                tableView.reloadData()
            }

            adjustTopSpacerForShortContent()
            finishReadingPositionRestoration(
                readingAnchor,
                event: "messages-reloaded-anchor-restored"
            )
            restorePendingTailStartOrigin()
            // Restoration recomputes followingTail from the new geometry.
            // Do not replace a restored reading anchor with a tail jump in
            // the same update merely because it now fits within the viewport.
            if readingAnchor == nil, followingTail, hasPositionedInitially {
                scheduleTailPosition()
            }
        }

        /// Authoritative echo-message delivery replaces an optimistic row's
        /// timestamp and IRCv3 tags while preserving its ID. Rebuilding the
        /// table for that replacement briefly returns visible rows to their
        /// estimated heights and schedules a redundant second tail movement.
        /// Retarget only changed, currently realized hosting views; offscreen
        /// rows pick up the new value when the data source realizes them.
        private func reconfigureMessagesInPlace(
            at messageIndexes: [Int],
            with newMessages: [IRCMessage],
            in tableView: NSTableView
        ) {
            messages = newMessages
            let width = currentContentWidth(in: tableView)
            for messageIndex in messageIndexes {
                let row = messageIndex + 1
                guard let cell = tableView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: false
                ) as? TranscriptMessageCellView else { continue }
                let message = newMessages[messageIndex]
                let cancelledPendingRelease = cell.hostingView.setHostedContent(
                    sizedRow(message, width: width),
                    for: message.id
                )
#if DEBUG
                if cancelledPendingRelease {
                    reportHostedContentLifecycle(
                        "release-cancelled-reconfigured",
                        messageID: message.id,
                        row: row
                    )
                }
#endif
            }
#if DEBUG
            parent.onGeometryChange?(
                "messages-reconfigured-in-place count=\(messageIndexes.count)",
                geometry()
            )
#endif
        }

        private func scheduleTailPosition() {
            pendingTailWorkItem?.cancel()
            tailPositionGeneration &+= 1
            let generation = tailPositionGeneration
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingTailWorkItem = nil
                guard self.followingTail else { return }
                let now = Date()
                let shouldAnimate = IRCTranscriptScrollPolicy.shouldAnimate(
                    lastAnimatedScroll: self.lastAnimatedScroll,
                    now: now
                )
                if shouldAnimate {
                    self.lastAnimatedScroll = now
                }
                self.positionAtTail(animated: shouldAnimate) { [weak self] didAnimate in
                    guard let self, self.tailPositionGeneration == generation else { return }
                    // An asynchronous preview can change the final row's
                    // height while the append animation is in flight. Its
                    // target was calculated from the earlier document
                    // height, so reconcile once more before publishing the
                    // completed tail position. Keep isAwaitingTailPosition
                    // set during this correction so its bounds notifications
                    // cannot be mistaken for a user scroll.
                    self.positionAtTail()
                    self.isAwaitingTailPosition = false
                    self.pendingTailStartOrigin = nil
                    let geometry = self.geometry()
                    self.parent.onTailPositioned?(didAnimate, geometry)
#if DEBUG
                    self.parent.onGeometryChange?("tail-positioned", geometry)
#endif
                }
            }
            pendingTailWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + IRCTranscriptScrollPolicy.coalescingDelay.timeInterval,
                execute: workItem
            )
        }

        private func positionAtTail(
            animated: Bool = false,
            completion: ((Bool) -> Void)? = nil
        ) {
            guard let tableView, let scrollView, tableView.numberOfRows > 0 else { return }
            tableView.layoutSubtreeIfNeeded()
            if animated {
                // NSTableView automatically re-anchors at the new bottom when
                // rows are inserted. Restore the pre-append origin in the same
                // run-loop turn that starts the animation so no intermediate
                // frame is displayed.
                restorePendingTailStartOrigin()
            }
            guard animated else {
                // Realize the final row first, then use the resulting exact
                // document height. scrollRowToVisible alone can leave an
                // automatic-height table overscrolled by the last estimate
                // correction, exposing blank space below the transcript.
                tableView.scrollRowToVisible(tableView.numberOfRows - 1)
                tableView.layoutSubtreeIfNeeded()
                let clipView = scrollView.contentView
                if let targetOrigin = tailOrigin() {
                    let targetBounds = NSRect(
                        origin: targetOrigin,
                        size: clipView.bounds.size
                    )
                    clipView.setBoundsOrigin(
                        clipView.constrainBoundsRect(targetBounds).origin
                    )
                }
                scrollView.reflectScrolledClipView(clipView)
                completion?(false)
                return
            }

            let clipView = scrollView.contentView
            let targetOrigin = tailOrigin() ?? clipView.bounds.origin
            guard abs(targetOrigin.y - clipView.bounds.origin.y) > 0.5 else {
                scrollView.reflectScrolledClipView(clipView)
                completion?(false)
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = IRCTranscriptScrollPolicy.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: { [weak scrollView, weak clipView] in
                guard let scrollView, let clipView else { return }
                scrollView.reflectScrolledClipView(clipView)
                completion?(true)
            }
        }

        private func scrollPositionDidChange(event: String) {
            let geometry = geometry()
            guard hasPositionedInitially else {
#if DEBUG
                scheduleDebugGeometryReport(event: event)
#endif
                return
            }
            if isAwaitingTailPosition || isRestoringReadingPosition {
#if DEBUG
                scheduleDebugGeometryReport(event: event)
#endif
                return
            }
            if let isAtBottom = IRCTranscriptScrollPolicy.followingTailChange(
                from: followingTail,
                visibleBounds: geometry.visibleBounds,
                contentBounds: geometry.contentBounds,
                contentIsFlipped: geometry.contentIsFlipped
            ) {
                followingTail = isAtBottom
                if parent.onFollowingTailChange != nil {
                    pendingFollowingTailReport = (isAtBottom, geometry)
                    schedulePositionReport()
                }
            }
#if DEBUG
            scheduleDebugGeometryReport(event: event)
#endif
        }

        private func userDidScroll() {
            guard isAwaitingTailPosition else { return }
            pendingTailWorkItem?.cancel()
            pendingTailWorkItem = nil
            isAwaitingTailPosition = false
            pendingTailStartOrigin = nil
            tailPositionGeneration &+= 1
        }

        /// AppKit posts bounds changes from inside scrolling and layout. Keep
        /// the coordinator's tail state synchronous, but defer the SwiftUI
        /// state notification until AppKit has unwound its current pass.
        private func schedulePositionReport() {
            guard parent.onFollowingTailChange != nil else { return }
            guard !hasPendingPositionReport else { return }
            hasPendingPositionReport = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                self.hasPendingPositionReport = false
                guard let report = self.pendingFollowingTailReport else { return }
                self.pendingFollowingTailReport = nil
                self.parent.onFollowingTailChange?(report.0, report.1)
            }
        }

#if DEBUG
        private func reportHostedContentLifecycle(
            _ event: String,
            messageID: UUID?,
            row: Int
        ) {
            guard parent.onGeometryChange != nil else { return }
            let messageDescription = messageID.map {
                String($0.uuidString.prefix(8))
            } ?? "nil"
            parent.onGeometryChange?(
                "hosted-content-\(event) row=\(row) message=\(messageDescription)",
                geometry()
            )
        }

        private func scheduleDebugGeometryReport(event: String) {
            guard parent.onGeometryChange != nil else { return }
            pendingDebugGeometryWorkItem?.cancel()
            let generation = attachmentGeneration
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                self.pendingDebugGeometryWorkItem = nil
                self.parent.onGeometryChange?(event, self.geometry())
            }
            pendingDebugGeometryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
#endif

        private func viewportWidthDidChange(_ width: CGFloat) {
            guard width > 0, abs(width - lastViewportWidth) > 0.5 else { return }
            lastViewportWidth = width
            let shouldDebounce = hasPositionedInitially
            // The initial hidden layout still needs to settle on the next
            // run-loop turn. Once visible, pane animations report a new width
            // every frame; keep replacing the pending refresh so the table is
            // rebuilt once, shortly after the final frame.
            if !shouldDebounce, hasPendingWidthRefresh { return }
            pendingWidthRefreshWorkItem?.cancel()
            widthRefreshGeneration &+= 1
            hasPendingWidthRefresh = true
            let generation = attachmentGeneration
            let refreshGeneration = widthRefreshGeneration
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.attachmentGeneration == generation,
                      self.widthRefreshGeneration == refreshGeneration else { return }
                self.pendingWidthRefreshWorkItem = nil
                defer { self.hasPendingWidthRefresh = false }
                guard let tableView = self.tableView else { return }
                let wasFollowingTail = self.followingTail
                let readingAnchor = self.beginReadingPositionRestoration()
                // NSTableView retains automatic-height proposals across an
                // in-place hosted-root update. Rebuild the virtualized rows
                // so every realized cell is proposed the new width before
                // asking AppKit to measure its height again.
                self.rowHeightEstimateViewportWidth = self.lastViewportWidth
                tableView.reloadData()
                tableView.layoutSubtreeIfNeeded()
                self.adjustTopSpacerForShortContent()
                self.finishReadingPositionRestoration(
                    readingAnchor,
                    event: "width-reloaded-anchor-restored"
                )
                self.scheduleHeightRefresh()
                if readingAnchor == nil, wasFollowingTail {
                    self.followingTail = true
                    self.positionAtTail()
                }
#if DEBUG
                self.parent.onGeometryChange?("width-reloaded", self.geometry())
#endif
            }
            pendingWidthRefreshWorkItem = workItem
            if shouldDebounce {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Self.settledWidthRefreshDelay,
                    execute: workItem
                )
            } else {
                DispatchQueue.main.async(execute: workItem)
            }
        }

        private func viewportHeightDidChange(_ height: CGFloat) {
            guard height > 0, abs(height - lastViewportHeight) > 0.5 else { return }
            lastViewportHeight = height
            guard hasPositionedInitially,
                  followingTail,
                  !viewportHeightReconciliationScheduled else { return }
            viewportHeightReconciliationScheduled = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.attachmentGeneration == generation else { return }
                self.viewportHeightReconciliationScheduled = false
                guard self.hasPositionedInitially,
                      self.followingTail,
                      !self.isRestoringReadingPosition else { return }
                // Height-only layout changes do not invalidate hosted rows,
                // but they do change the spacer needed to keep a short
                // transcript growing upward from the bottom.
                self.adjustTopSpacerForShortContent()
                // A pending append owns the eventual tail move. Updating its
                // short-content spacer is still necessary, but an immediate
                // jump here would bypass the coalesced arrival animation.
                guard !self.isAwaitingTailPosition else { return }
                self.positionAtTail()
            }
        }

        private func currentContentWidth(in tableView: NSTableView) -> CGFloat {
            let width = lastViewportWidth > 0 ? lastViewportWidth : tableView.bounds.width
            return max(1, width)
        }

        private func sizedRow(_ message: IRCMessage, width: CGFloat) -> AnyView {
            AnyView(
                parent.makeRow(message)
                    // The hosting view is reused; message identity gives each
                    // row-local @State a distinct lifetime when retargeted.
                    .id(message.id)
                    .frame(width: width, alignment: .leading)
            )
        }

        private func scheduleHeightRefresh() {
            guard let tableView, !fullHeightRefreshScheduled else { return }
            fullHeightRefreshScheduled = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self else { return }
                guard self.attachmentGeneration == generation,
                      let tableView,
                      self.tableView === tableView else {
                    if self.attachmentGeneration == generation {
                        self.fullHeightRefreshScheduled = false
                    }
                    return
                }
                defer {
                    // SwiftUI can publish the final intrinsic height after
                    // AppKit's full sweep has already measured a rewrapped
                    // row. Preserve those late notifications for one
                    // row-scoped follow-up instead of assuming the sweep
                    // covered them and leaving the row at its old height.
                    let followUpMessageIDs = self.pendingHeightMessageIDs
                    self.pendingHeightMessageIDs.removeAll()
                    self.fullHeightRefreshScheduled = false
                    for messageID in followUpMessageIDs {
                        self.scheduleHeightInvalidation(for: messageID)
                    }
                }
                let readingAnchor = self.beginReadingPositionRestoration()
                let messageAndBottomSpacerRows = IndexSet(
                    integersIn: 1..<tableView.numberOfRows
                )
                // Publish measurements before invalidating AppKit's cached
                // estimates so heightOfRow remains stable between invalidation
                // points, as required by NSTableViewDelegate. Include the
                // bottom spacer: after a conversation swap, it can occupy an
                // index that held a tall message in the outgoing table, and
                // AppKit can otherwise retain that stale automatic-height
                // proposal as invisible space below the tail. The top spacer
                // has its own height adjustment and invalidation path.
                self.cacheRealizedRowHeights(in: tableView)
                self.applyRowHeightChangesWithoutAnimation(
                    messageAndBottomSpacerRows,
                    in: tableView
                )
                self.adjustTopSpacerForShortContent()
                self.finishReadingPositionRestoration(
                    readingAnchor,
                    event: "height-refresh-anchor-restored"
                )
                // A restored reader position wins over any tail classification
                // produced while recalculating the new geometry.
                if readingAnchor == nil, self.followingTail {
                    if self.isAwaitingTailPosition {
                        self.restorePendingTailStartOrigin()
                    } else {
                        self.positionAtTail()
                    }
                }
            }
        }

        private func scheduleHeightInvalidation(for messageID: UUID) {
            pendingHeightMessageIDs.insert(messageID)
            guard !fullHeightRefreshScheduled else { return }
            guard !heightInvalidationScheduled else { return }
            heightInvalidationScheduled = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.attachmentGeneration == generation,
                      let tableView = self.tableView else {
                    if self.attachmentGeneration == generation {
                        self.heightInvalidationScheduled = false
                    }
                    return
                }
                self.heightInvalidationScheduled = false
                let rows = IndexSet(self.pendingHeightMessageIDs.compactMap { messageID in
                    guard let messageIndex = self.messages.firstIndex(where: { $0.id == messageID }) else {
                        return nil
                    }
                    let row = messageIndex + 1
                    guard let hostingView = self.hostingView(at: row, in: tableView) else {
                        return nil
                    }
                    hostingView.layoutSubtreeIfNeeded()
                    let currentHeight = tableView.rect(ofRow: row).height
                    let proposedHeight = hostingView.fittingSize.height
                    guard currentHeight.isFinite,
                          proposedHeight.isFinite,
                          proposedHeight > 0 else {
                        return nil
                    }
                    let previousCachedHeight = self.cachedRowHeight(for: messageID)
                    self.cacheRowHeight(proposedHeight, for: messageID)
                    // A first measurement only seeds a future reload. Only a
                    // changed estimate already exposed to AppKit needs noting.
                    let cachedEstimateChanged = previousCachedHeight.map {
                        abs($0 - proposedHeight) > 0.5
                    } ?? false
                    guard cachedEstimateChanged
                            || abs(currentHeight - proposedHeight) > 0.5 else {
                        return nil
                    }
                    return row
                })
                self.pendingHeightMessageIDs.removeAll()
                guard !rows.isEmpty else { return }
                let readingAnchor = self.beginReadingPositionRestoration()
                self.applyRowHeightChangesWithoutAnimation(rows, in: tableView)
                self.adjustTopSpacerForShortContent()
                self.finishReadingPositionRestoration(
                    readingAnchor,
                    event: "row-height-anchor-restored"
                )
                // Appends already have one coalesced tail move pending. Only
                // genuine later resizes, such as an async preview, reposition
                // from the height path.
                // A restored reader position still wins if its new geometry
                // happens to classify it as being at the tail.
                if readingAnchor == nil, self.followingTail {
                    if self.isAwaitingTailPosition {
                        self.restorePendingTailStartOrigin()
                    } else {
                        self.positionAtTail()
                    }
                }
#if DEBUG
                self.parent.onGeometryChange?("row-height-changed", self.geometry())
#endif
            }
        }

        private func beginReadingPositionRestoration() -> ReadingAnchor? {
            guard hasPositionedInitially,
                  !followingTail,
                  let tableView,
                  let scrollView else { return nil }
            let visibleRect = tableView.visibleRect
            let visibleRows = tableView.rows(in: visibleRect)
            guard visibleRows.location != NSNotFound else { return nil }

            var candidates: [ReadingAnchor.Candidate] = []
            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard let message = message(atTableRow: row) else { continue }
                candidates.append(ReadingAnchor.Candidate(
                    messageID: message.id,
                    viewportOffset: tableView.rect(ofRow: row).minY
                        - scrollView.contentView.bounds.minY
                ))
            }
            guard !candidates.isEmpty else { return nil }
            let anchor = ReadingAnchor(candidates: candidates)
            isRestoringReadingPosition = true
            return anchor
        }

        private func finishReadingPositionRestoration(
            _ anchor: ReadingAnchor?,
            event: String
        ) {
            guard let anchor else { return }
            defer {
                isRestoringReadingPosition = false
                scrollPositionDidChange(event: event)
            }
            restoreReadingPosition(anchor)
        }

        private func restoreReadingPosition(_ anchor: ReadingAnchor) {
            guard let tableView,
                  let scrollView,
                  !messages.isEmpty else { return }

            var survivingCandidate: (messageIndex: Int, viewportOffset: CGFloat)?
            for candidate in anchor.candidates {
                guard let messageIndex = messages.firstIndex(
                    where: { $0.id == candidate.messageID }
                ) else { continue }
                survivingCandidate = (messageIndex, candidate.viewportOffset)
                break
            }
            let target = survivingCandidate ?? (
                messageIndex: messages.startIndex,
                viewportOffset: anchor.candidates[0].viewportOffset
            )
            let row = target.messageIndex + 1

            // First make AppKit realize the ordinal target, then restore the
            // exact partial-row offset the reader had before the mutation.
            tableView.scrollRowToVisible(row)
            tableView.layoutSubtreeIfNeeded()
            let clipView = scrollView.contentView
            let desiredBounds = NSRect(
                x: clipView.bounds.minX,
                y: tableView.rect(ofRow: row).minY - target.viewportOffset,
                width: clipView.bounds.width,
                height: clipView.bounds.height
            )
            let constrainedBounds = clipView.constrainBoundsRect(desiredBounds)
            clipView.setBoundsOrigin(constrainedBounds.origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private func restorePendingTailStartOrigin() {
            guard isAwaitingTailPosition,
                  let pendingTailStartOrigin,
                  let scrollView else { return }
            scrollView.contentView.setBoundsOrigin(pendingTailStartOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func tailOrigin() -> NSPoint? {
            guard let tableView, let scrollView else { return nil }
            let clipView = scrollView.contentView
            let targetY = tableView.isFlipped
                ? max(
                    tableView.bounds.minY,
                    tableView.bounds.minY + tableView.frame.height - clipView.bounds.height
                )
                : tableView.bounds.minY
            return NSPoint(x: clipView.bounds.origin.x, y: targetY)
        }

        private func hostingView(
            at row: Int,
            in tableView: NSTableView
        ) -> IntrinsicInvalidatingHostingView? {
            guard let cell = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? TranscriptMessageCellView else {
                return nil
            }
            return cell.hostingView
        }

        private func reconcileVisibleMessageRows(in tableView: NSTableView) -> Bool {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return false }
            var invalidatedRows = IndexSet()
            var hasUnverifiedRows = false
#if DEBUG
            var verifiedRows: [String] = []
            var unverifiedRows: [String] = []
#endif
            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard let message = message(atTableRow: row) else { continue }
                guard let cell = tableView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: true
                ) as? TranscriptMessageCellView,
                      cell.hostingView.hasHostedContent,
                      cell.hostingView.representedMessageID == message.id else {
                    hasUnverifiedRows = true
#if DEBUG
                    unverifiedRows.append("\(row)/\(String(message.id.uuidString.prefix(8)))")
#endif
                    continue
                }

                cell.hostingView.layoutSubtreeIfNeeded()
                let proposedHeight = cell.hostingView.fittingSize.height
                guard proposedHeight.isFinite, proposedHeight > 0 else {
                    hasUnverifiedRows = true
#if DEBUG
                    unverifiedRows.append("\(row)/\(String(message.id.uuidString.prefix(8)))")
#endif
                    continue
                }

                let currentHeight = max(
                    0,
                    tableView.rect(ofRow: row).height
                        - tableView.intercellSpacing.height
                )
                let previousCachedHeight = cachedRowHeight(for: message.id)
#if DEBUG
                reportLargeHeightDisagreementIfNeeded(
                    row: row,
                    messageID: message.id,
                    tableHeight: currentHeight,
                    cachedHeight: previousCachedHeight,
                    proposedHeight: proposedHeight,
                    source: "initial-visible-verification"
                )
#endif
                cacheRowHeight(proposedHeight, for: message.id)
                let isFirstInitialVerification = initiallyVerifiedMessageIDs.insert(
                    message.id
                ).inserted
                let cachedHeightChanged = previousCachedHeight.map {
                    abs($0 - proposedHeight) > 0.5
                } ?? false
                guard isFirstInitialVerification
                      || cachedHeightChanged
                      || abs(currentHeight - proposedHeight) > 0.5 else { continue }
                invalidatedRows.insert(row)
#if DEBUG
                verifiedRows.append(
                    "\(row)/\(String(message.id.uuidString.prefix(8)))"
                        + "/\(String(format: "%.1f", currentHeight))"
                        + "->\(String(format: "%.1f", proposedHeight))"
                )
#endif
            }

            if !invalidatedRows.isEmpty {
                // NSTableView can retain a stale automatic-height proposal by
                // row index even when its rect happens to agree with the new
                // hosting view during the first layout pass. Explicitly
                // invalidate each initially visible message once per
                // attachment so AppKit adopts the conversation-scoped cache.
                applyRowHeightChangesWithoutAnimation(
                    invalidatedRows,
                    in: tableView
                )
            }
#if DEBUG
            if !invalidatedRows.isEmpty || hasUnverifiedRows {
                parent.onGeometryChange?(
                    "initial-visible-row-heights-verified "
                        + "invalidated=\(invalidatedRows.count) "
                        + "pending=\(unverifiedRows.count) "
                        + "rows=\(verifiedRows.prefix(4).joined(separator: ",")) "
                        + "pendingRows=\(unverifiedRows.prefix(4).joined(separator: ","))",
                    geometry()
                )
            }
#endif
            return !invalidatedRows.isEmpty || hasUnverifiedRows
        }

        private func applyRowHeightChangesWithoutAnimation(
            _ rows: IndexSet,
            in tableView: NSTableView
        ) {
            guard !rows.isEmpty else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                tableView.noteHeightOfRows(withIndexesChanged: rows)
                tableView.layoutSubtreeIfNeeded()
            }
        }

        private func cachedRowHeight(for messageID: UUID) -> CGFloat? {
            guard let contentIdentity,
                  let cache = rowHeightCaches[contentIdentity],
                  rowHeightCacheMatchesCurrentLayout(cache) else { return nil }
            return cache.heightsByMessageID[messageID]
        }

        private func cacheRowHeight(_ height: CGFloat, for messageID: UUID) {
            guard height.isFinite,
                  height > 0,
                  !hasPendingWidthRefresh,
                  let contentIdentity else { return }
            let viewportWidth = currentRowHeightCacheWidth
            guard viewportWidth > 0 else { return }

            rowHeightCacheAccess &+= 1
            if let cache = rowHeightCaches[contentIdentity],
               rowHeightCacheMatchesCurrentLayout(cache) {
                cache.heightsByMessageID[messageID] = height
                cache.lastAccess = rowHeightCacheAccess
            } else {
                rowHeightCaches[contentIdentity] = ConversationRowHeightCache(
                    viewportWidth: viewportWidth,
                    renderConfiguration: renderConfiguration,
                    heightsByMessageID: [messageID: height],
                    lastAccess: rowHeightCacheAccess
                )
            }
            evictOldRowHeightCachesIfNeeded()
        }

        private func cacheRealizedRowHeights(in tableView: NSTableView) {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard let message = message(atTableRow: row),
                      let hostingView = hostingView(at: row, in: tableView),
                      hostingView.hasHostedContent,
                      hostingView.representedMessageID == message.id else { continue }
                hostingView.layoutSubtreeIfNeeded()
                let proposedHeight = hostingView.fittingSize.height
#if DEBUG
                reportLargeHeightDisagreementIfNeeded(
                    row: row,
                    messageID: message.id,
                    tableHeight: tableView.rect(ofRow: row).height,
                    cachedHeight: cachedRowHeight(for: message.id),
                    proposedHeight: proposedHeight,
                    source: "realized-cache"
                )
#endif
                cacheRowHeight(proposedHeight, for: message.id)
            }
        }

#if DEBUG
        private func rowHeightCacheSwitchSnapshot(
            messageCount: Int
        ) -> RowHeightCacheSwitchSnapshot {
            guard let contentIdentity else {
                return RowHeightCacheSwitchSnapshot(
                    hasContentIdentity: false,
                    switchMessageCount: messageCount,
                    switchStartWidth: currentRowHeightCacheWidth,
                    storedCount: 0,
                    cachedWidth: nil,
                    cachedRenderConfiguration: nil
                )
            }
            let cache = rowHeightCaches[contentIdentity]
            return RowHeightCacheSwitchSnapshot(
                hasContentIdentity: true,
                switchMessageCount: messageCount,
                switchStartWidth: currentRowHeightCacheWidth,
                storedCount: cache?.heightsByMessageID.count ?? 0,
                cachedWidth: cache?.viewportWidth,
                cachedRenderConfiguration: cache?.renderConfiguration
            )
        }

        private func rowHeightCacheSwitchSummary(
            _ snapshot: RowHeightCacheSwitchSnapshot,
            attachedMessageCount: Int,
            finalWidth: CGFloat
        ) -> String {
            let switchWidthDescription = String(format: "%.1f", snapshot.switchStartWidth)
            let finalWidthDescription = String(format: "%.1f", finalWidth)
            let messageDescription = "messages=\(snapshot.switchMessageCount) "
                + "attachedMessages=\(attachedMessageCount)"
            guard snapshot.hasContentIdentity else {
                return "row-height-cache-switch status=no-identity \(messageDescription) "
                    + "switchWidth=\(switchWidthDescription) finalWidth=\(finalWidthDescription)"
            }
            guard let cachedWidth = snapshot.cachedWidth,
                  let cachedRenderConfiguration = snapshot.cachedRenderConfiguration else {
                return "row-height-cache-switch status=miss \(messageDescription) "
                    + "usable=0 stored=0 coverage=0.0 "
                    + "switchWidth=\(switchWidthDescription) finalWidth=\(finalWidthDescription)"
            }

            // Evaluate the cache against the layout actually revealed to the
            // user. Channel/DM inspector changes can make the width at switch
            // start differ from the width after the hidden refresh settles.
            let widthMatches = abs(cachedWidth - finalWidth) <= 0.5
            let configurationMatches = cachedRenderConfiguration == renderConfiguration
            let layoutMatches = widthMatches && configurationMatches
            let usableCount = layoutMatches ? snapshot.storedCount : 0
            let coverage = attachedMessageCount > 0
                ? 100 * Double(usableCount) / Double(attachedMessageCount)
                : 100
            let status = layoutMatches ? "hit" : "layout-mismatch"
            let coverageDescription = String(format: "%.1f", coverage)
            let cachedWidthDescription = String(format: "%.1f", cachedWidth)
            return "row-height-cache-switch status=\(status) \(messageDescription) "
                + "usable=\(usableCount) stored=\(snapshot.storedCount) "
                + "coverage=\(coverageDescription) "
                + "switchWidth=\(switchWidthDescription) "
                + "finalWidth=\(finalWidthDescription) "
                + "cachedWidth=\(cachedWidthDescription) "
                + "widthMatch=\(widthMatches) configurationMatch=\(configurationMatches)"
        }

        private func reportLargeHeightDisagreementIfNeeded(
            row: Int,
            messageID: UUID,
            tableHeight: CGFloat,
            cachedHeight: CGFloat?,
            proposedHeight: CGFloat,
            source: String
        ) {
            guard proposedHeight.isFinite, proposedHeight > 0 else { return }
            let tableDelta = abs(tableHeight - proposedHeight)
            let cacheDelta = cachedHeight.map { abs($0 - proposedHeight) } ?? 0
            guard max(tableDelta, cacheDelta) > 40 else { return }
            let messageDescription = String(messageID.uuidString.prefix(8))
            let cachedDescription = cachedHeight.map {
                String(format: "%.1f", $0)
            } ?? "nil"
            let tableDescription = String(format: "%.1f", tableHeight)
            let proposedDescription = String(format: "%.1f", proposedHeight)
            parent.onGeometryChange?(
                "large-row-height-disagreement source=\(source) row=\(row) "
                    + "message=\(messageDescription) table=\(tableDescription) "
                    + "cached=\(cachedDescription) proposed=\(proposedDescription)",
                geometry()
            )
        }
#endif

        private func removeCurrentRowHeightCache() {
            guard let contentIdentity else { return }
            rowHeightCaches.removeValue(forKey: contentIdentity)
        }

        private func applyPendingRowLayoutInvalidation(to messages: [IRCMessage]) {
            guard let invalidation = rowLayoutInvalidation,
                  messages.contains(where: { $0.id == invalidation.messageID }),
                  needsApplying(invalidation) else { return }
            removeCurrentRowHeightCache()
            recordApplied(invalidation)
        }

        private func needsApplying(
            _ invalidation: IRCTranscriptRowLayoutInvalidation
        ) -> Bool {
            guard let contentIdentity else { return true }
            return appliedRowLayoutRevisions[contentIdentity] != invalidation.revision
        }

        private func recordApplied(_ invalidation: IRCTranscriptRowLayoutInvalidation) {
            guard let contentIdentity else { return }
            appliedRowLayoutRevisions[contentIdentity] = invalidation.revision
        }

        private func pruneCachedRowHeights(to messages: [IRCMessage]) {
            guard let contentIdentity,
                  let cache = rowHeightCaches[contentIdentity] else { return }
            let retainedMessageIDs = Set(messages.map(\.id))
            cache.heightsByMessageID = cache.heightsByMessageID.filter {
                retainedMessageIDs.contains($0.key)
            }
        }

        private func touchCurrentRowHeightCache() {
            guard let contentIdentity,
                  let cache = rowHeightCaches[contentIdentity],
                  rowHeightCacheMatchesCurrentLayout(cache) else { return }
            rowHeightCacheAccess &+= 1
            cache.lastAccess = rowHeightCacheAccess
        }

        private var currentRowHeightCacheWidth: CGFloat {
            if rowHeightEstimateViewportWidth > 0 {
                return rowHeightEstimateViewportWidth
            }
            return max(0, tableView?.bounds.width ?? 0)
        }

        private func rowHeightCacheMatchesCurrentLayout(
            _ cache: ConversationRowHeightCache
        ) -> Bool {
            abs(cache.viewportWidth - currentRowHeightCacheWidth) <= 0.5
                && cache.renderConfiguration == renderConfiguration
        }

        private func evictOldRowHeightCachesIfNeeded() {
            while rowHeightCaches.count > Self.maximumCachedConversationCount,
                  let oldestIdentity = rowHeightCaches.min(
                    by: { $0.value.lastAccess < $1.value.lastAccess }
                  )?.key {
                rowHeightCaches.removeValue(forKey: oldestIdentity)
            }
        }

        private func adjustTopSpacerForShortContent() {
            guard let tableView, let scrollView, tableView.numberOfRows >= 2 else { return }
            let viewportHeight = scrollView.contentView.bounds.height
            tableView.layoutSubtreeIfNeeded()
            let bottomRow = tableView.numberOfRows - 1
            let measuredHeight = tableView.rect(ofRow: bottomRow).maxY
                - (topSpacerHeight - Self.topInset)
            let desiredHeight = Self.topInset
                + max(0, viewportHeight - measuredHeight)
            guard abs(desiredHeight - topSpacerHeight) > 0.5 else { return }
            topSpacerHeight = desiredHeight
            // View-based NSTableView animates noteHeightOfRows by default.
            // This spacer can grow by almost the full viewport when switching
            // to a short transcript, so allowing that animation makes the
            // messages visibly slide from the top to their bottom alignment
            // after the scroll view is revealed.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                if let topSpacer = tableView.view(
                    atColumn: 0,
                    row: 0,
                    makeIfNecessary: false
                ) as? TranscriptSpacerCellView {
                    topSpacer.height = desiredHeight
                }
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
                tableView.layoutSubtreeIfNeeded()
            }
        }

        private func message(atTableRow row: Int) -> IRCMessage? {
            let messageIndex = row - 1
            guard messages.indices.contains(messageIndex) else { return nil }
            return messages[messageIndex]
        }

        private func geometry() -> IRCTranscriptTableGeometry {
            guard let scrollView, let tableView else {
                return IRCTranscriptTableGeometry(
                    visibleBounds: .zero,
                    contentBounds: .zero,
                    documentFrame: .zero,
                    contentIsFlipped: true
                )
            }
            return IRCTranscriptTableGeometry(
                visibleBounds: scrollView.contentView.bounds,
                contentBounds: tableView.bounds,
                documentFrame: tableView.frame,
                contentIsFlipped: tableView.isFlipped
            )
        }
    }
}

struct IRCTranscriptScrollMomentumPolicy {
    private(set) var discardsMomentum = false

    mutating func discardMomentumUntilNextDirectScroll() {
        discardsMomentum = true
    }

    mutating func shouldForwardScroll(hasMomentum: Bool) -> Bool {
        guard hasMomentum else {
            discardsMomentum = false
            return true
        }
        return !discardsMomentum
    }
}

final class TranscriptScrollView: NSScrollView {
    var onViewportWidthChange: ((CGFloat) -> Void)?
    var onViewportHeightChange: ((CGFloat) -> Void)?
    var onUserScroll: (() -> Void)?
    private var lastReportedViewportWidth: CGFloat = 0
    private var lastReportedViewportHeight: CGFloat = 0
    private var momentumPolicy = IRCTranscriptScrollMomentumPolicy()

    func discardMomentumUntilNextDirectScroll() {
        momentumPolicy.discardMomentumUntilNextDirectScroll()
    }

    override func layout() {
        super.layout()
        let viewportSize = contentView.bounds.size
        if viewportSize.width > 0,
           abs(viewportSize.width - lastReportedViewportWidth) > 0.5 {
            lastReportedViewportWidth = viewportSize.width
            onViewportWidthChange?(viewportSize.width)
        }
        if viewportSize.height > 0,
           abs(viewportSize.height - lastReportedViewportHeight) > 0.5 {
            lastReportedViewportHeight = viewportSize.height
            onViewportHeightChange?(viewportSize.height)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard momentumPolicy.shouldForwardScroll(
            hasMomentum: !event.momentumPhase.isEmpty
        ) else { return }
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}

final class IntrinsicInvalidatingHostingView: NSHostingView<AnyView> {
    private(set) var representedMessageID: UUID?
    private(set) var hasHostedContent = false
    private(set) var hasPendingHostedContentRelease = false
    var onIntrinsicSizeInvalidated: ((UUID) -> Void)?
    private var pendingHostedContentRelease: DispatchWorkItem?
    private var hostedContentReleaseGeneration: UInt = 0

    @discardableResult
    func setHostedContent(_ content: AnyView, for messageID: UUID) -> Bool {
        let cancelledPendingRelease = cancelPendingHostedContentRelease()
        representedMessageID = messageID
        hasHostedContent = true
        rootView = content
        return cancelledPendingRelease
    }

    func scheduleHostedContentRelease(
        after delay: TimeInterval,
        shouldRelease: @escaping () -> Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        cancelPendingHostedContentRelease()
        guard hasHostedContent else { return }

        hostedContentReleaseGeneration &+= 1
        let generation = hostedContentReleaseGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.hostedContentReleaseGeneration == generation else { return }
            self.pendingHostedContentRelease = nil
            self.hasPendingHostedContentRelease = false
            guard shouldRelease() else {
                completion?(false)
                return
            }
            self.releaseHostedContent()
            completion?(true)
        }
        pendingHostedContentRelease = workItem
        hasPendingHostedContentRelease = true
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    @discardableResult
    func cancelPendingHostedContentRelease() -> Bool {
        guard let pendingHostedContentRelease else { return false }
        hostedContentReleaseGeneration &+= 1
        pendingHostedContentRelease.cancel()
        self.pendingHostedContentRelease = nil
        hasPendingHostedContentRelease = false
        return true
    }

    func releaseHostedContent() {
        cancelPendingHostedContentRelease()
        representedMessageID = nil
        guard hasHostedContent else { return }
        hasHostedContent = false
        // This view is no longer associated with a table row. Keeping the
        // outgoing row's height in a placeholder can leak a tall preview's
        // intrinsic size into the next message when NSTableView reuses the
        // cell, until SwiftUI publishes the replacement view's size.
        rootView = AnyView(EmptyView())
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard let representedMessageID else { return }
        onIntrinsicSizeInvalidated?(representedMessageID)
    }
}

private final class TranscriptMessageCellView: NSTableCellView {
    let hostingView: IntrinsicInvalidatingHostingView
    private var representedContentIdentity: SidebarItem?
    private var hasRepresentedContentIdentity = false

    override init(frame frameRect: NSRect) {
        hostingView = IntrinsicInvalidatingHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: frameRect)
        hostingView.identifier = NSUserInterfaceItemIdentifier("IRCTranscriptHostedRow")
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.sizingOptions = [.intrinsicContentSize]
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func canReuse(for contentIdentity: SidebarItem?) -> Bool {
        hasRepresentedContentIdentity
            && representedContentIdentity == contentIdentity
    }

    func assignReuseScope(_ contentIdentity: SidebarItem?) {
        representedContentIdentity = contentIdentity
        hasRepresentedContentIdentity = true
    }

    // Deliberately keep the existing root through prepareForReuse so viewFor
    // retargets it directly. Replacing it there adds a second root-view update
    // and lets the outgoing row's intrinsic height win the sizing pass. Rows
    // that remain detached are still emptied by the delayed release.
    func releaseHostedContent() {
        hostingView.releaseHostedContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TranscriptSpacerCellView: NSTableCellView {
    private let heightConstraint: NSLayoutConstraint

    var height: CGFloat {
        get { heightConstraint.constant }
        set { heightConstraint.constant = newValue }
    }

    init(height: CGFloat) {
        let spacer = NSView(frame: .zero)
        spacer.translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = spacer.heightAnchor.constraint(equalToConstant: height)
        super.init(frame: .zero)
        addSubview(spacer)
        NSLayoutConstraint.activate([
            spacer.leadingAnchor.constraint(equalTo: leadingAnchor),
            spacer.trailingAnchor.constraint(equalTo: trailingAnchor),
            spacer.topAnchor.constraint(equalTo: topAnchor),
            spacer.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
