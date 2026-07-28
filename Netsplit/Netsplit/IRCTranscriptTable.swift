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

/// A view-based AppKit table that realizes only visible transcript rows while
/// retaining the existing SwiftUI row implementation and its interactions.
struct IRCTranscriptTable: NSViewRepresentable {
    let messages: [IRCMessage]
    /// Makes the representable update when its conversation-scoped signal
    /// advances without treating that signal as a row-render configuration.
    let updateRevision: Int
    let estimatedRowHeight: CGFloat
    let rowSpacing: CGFloat
    let renderConfiguration: String
    let makeRow: (IRCMessage) -> AnyView
    let onInitialPositioned: ((IRCTranscriptTableGeometry) -> Void)?
    let onFollowingTailChange: ((Bool, IRCTranscriptTableGeometry) -> Void)?
    let onTailPositioned: ((Bool, IRCTranscriptTableGeometry) -> Void)?
    let onGeometryChange: ((String, IRCTranscriptTableGeometry) -> Void)?

    init(
        messages: [IRCMessage],
        updateRevision: Int = 0,
        estimatedRowHeight: CGFloat,
        rowSpacing: CGFloat,
        renderConfiguration: String,
        makeRow: @escaping (IRCMessage) -> AnyView,
        onInitialPositioned: ((IRCTranscriptTableGeometry) -> Void)? = nil,
        onFollowingTailChange: ((Bool, IRCTranscriptTableGeometry) -> Void)? = nil,
        onTailPositioned: ((Bool, IRCTranscriptTableGeometry) -> Void)? = nil,
        onGeometryChange: ((String, IRCTranscriptTableGeometry) -> Void)? = nil
    ) {
        self.messages = messages
        self.updateRevision = updateRevision
        self.estimatedRowHeight = estimatedRowHeight
        self.rowSpacing = rowSpacing
        self.renderConfiguration = renderConfiguration
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
        private static let topInset: CGFloat = 18
        private static let bottomInset: CGFloat = 18

        private var parent: IRCTranscriptTable
        private var messages: [IRCMessage]
        private var renderConfiguration: String
        private weak var scrollView: TranscriptScrollView?
        private weak var tableView: NSTableView?
        private var observers: [NSObjectProtocol] = []
        private var hasPositionedInitially = false
        private var followingTail: Bool
        private var topSpacerHeight = topInset
        private var lastViewportWidth: CGFloat = 0
        private var pendingHeightMessageIDs = Set<UUID>()
        private var heightInvalidationScheduled = false
        private var pendingTailWorkItem: DispatchWorkItem?
        private var lastAnimatedScroll = Date.distantPast
        private var isAwaitingTailPosition = false
        private var pendingTailStartOrigin: NSPoint?
        private var tailPositionGeneration = 0
        private var attachmentGeneration = 0
        private var hasPendingPositionReport = false
        private var pendingFollowingTailReport: (Bool, IRCTranscriptTableGeometry)?
#if DEBUG
        private var pendingDebugGeometryWorkItem: DispatchWorkItem?
#endif
        private var hasPendingWidthRefresh = false

        init(parent: IRCTranscriptTable) {
            self.parent = parent
            messages = parent.messages
            renderConfiguration = parent.renderConfiguration
            followingTail = true
        }

        func attach(scrollView: TranscriptScrollView, tableView: NSTableView) {
            attachmentGeneration &+= 1
            self.scrollView = scrollView
            self.tableView = tableView
            scrollView.onViewportWidthChange = { [weak self] width in
                self?.viewportWidthDidChange(width)
            }
            scrollView.onUserScroll = { [weak self] in
                self?.userDidScroll()
            }

            let center = NotificationCenter.default
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
            tailPositionGeneration &+= 1
#if DEBUG
            pendingDebugGeometryWorkItem?.cancel()
            pendingDebugGeometryWorkItem = nil
#endif
            hasPendingPositionReport = false
            pendingFollowingTailReport = nil
            hasPendingWidthRefresh = false
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
            scrollView?.onViewportWidthChange = nil
            scrollView?.onUserScroll = nil
            tableView?.delegate = nil
            tableView?.dataSource = nil
            scrollView?.documentView = nil
            scrollView = nil
            tableView = nil
        }

        func update(parent: IRCTranscriptTable) {
            let oldMessages = messages
            let configurationChanged = renderConfiguration != parent.renderConfiguration
            self.parent = parent
            renderConfiguration = parent.renderConfiguration

            guard let tableView else {
                messages = parent.messages
                return
            }

            if configurationChanged {
                messages = parent.messages
                tableView.intercellSpacing.height = parent.rowSpacing
                tableView.rowHeight = parent.estimatedRowHeight
                tableView.reloadData()
                scheduleHeightRefresh()
            } else if parent.messages != oldMessages {
                applyMessageUpdate(from: oldMessages, to: parent.messages, in: tableView)
            }

            if !hasPositionedInitially, !messages.isEmpty {
                scheduleInitialPosition()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            messages.count + 2
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

            let cell = NSTableCellView()
            let hostingView = IntrinsicInvalidatingHostingView(
                rootView: sizedRow(message, width: currentContentWidth(in: tableView))
            )
            hostingView.identifier = NSUserInterfaceItemIdentifier("IRCTranscriptHostedRow")
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.sizingOptions = [.intrinsicContentSize]
            hostingView.onIntrinsicSizeInvalidated = { [weak self] in
                self?.scheduleHeightInvalidation(for: message.id)
            }
            cell.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: cell.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
            ])
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func scheduleInitialPosition() {
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let scrollView = self.scrollView,
                      self.tableView != nil,
                      !self.hasPositionedInitially else { return }
                self.positionAtTail()
                self.adjustTopSpacerForShortContent()
                self.positionAtTail()
                self.hasPositionedInitially = true
                scrollView.alphaValue = 1
                let geometry = self.geometry()
                self.parent.onInitialPositioned?(geometry)
#if DEBUG
                self.parent.onGeometryChange?("attached", geometry)
#endif
            }
        }

        private func applyMessageUpdate(
            from oldMessages: [IRCMessage],
            to newMessages: [IRCMessage],
            in tableView: NSTableView
        ) {
            let appendedCount = newMessages.count - oldMessages.count
            let isSimpleAppend = appendedCount > 0
                && (oldMessages.isEmpty
                    || (newMessages.first?.id == oldMessages.first?.id
                        && newMessages[oldMessages.count - 1].id == oldMessages.last?.id))
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
                tableView.reloadData()
            }

            adjustTopSpacerForShortContent()
            restorePendingTailStartOrigin()
            if followingTail, hasPositionedInitially {
                scheduleTailPosition()
            }
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
                tableView.scrollRowToVisible(tableView.numberOfRows - 1)
                scrollView.reflectScrolledClipView(scrollView.contentView)
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
            if isAwaitingTailPosition {
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
            guard !hasPendingWidthRefresh else { return }
            hasPendingWidthRefresh = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attachmentGeneration == generation else { return }
                self.hasPendingWidthRefresh = false
                self.refreshVisibleRowsForCurrentWidth()
                self.scheduleHeightRefresh()
            }
        }

        private func refreshVisibleRowsForCurrentWidth() {
            guard let tableView else { return }
            let visibleRect = tableView.visibleRect
            let refreshRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)
            let visibleRows = tableView.rows(in: refreshRect)
            guard visibleRows.location != NSNotFound else { return }
            let width = currentContentWidth(in: tableView)
            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard let message = message(atTableRow: row),
                      let cell = tableView.view(
                          atColumn: 0,
                          row: row,
                          makeIfNecessary: false
                      ),
                      let hostingView = cell.subviews.first(
                          where: { $0 is IntrinsicInvalidatingHostingView }
                      ) as? IntrinsicInvalidatingHostingView else { continue }
                hostingView.rootView = sizedRow(message, width: width)
            }
        }

        private func currentContentWidth(in tableView: NSTableView) -> CGFloat {
            let width = lastViewportWidth > 0 ? lastViewportWidth : tableView.bounds.width
            return max(1, width)
        }

        private func sizedRow(_ message: IRCMessage, width: CGFloat) -> AnyView {
            AnyView(
                parent.makeRow(message)
                    .frame(width: width, alignment: .leading)
            )
        }

        private func scheduleHeightRefresh() {
            guard let tableView else { return }
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                let messageRows = IndexSet(
                    integersIn: 1..<(self.messages.count + 1)
                )
                tableView.noteHeightOfRows(withIndexesChanged: messageRows)
                tableView.layoutSubtreeIfNeeded()
                self.adjustTopSpacerForShortContent()
                if self.followingTail {
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
            guard !heightInvalidationScheduled else { return }
            heightInvalidationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let tableView = self.tableView else { return }
                self.heightInvalidationScheduled = false
                let rows = IndexSet(self.pendingHeightMessageIDs.compactMap { messageID in
                    guard let messageIndex = self.messages.firstIndex(where: { $0.id == messageID }) else {
                        return nil
                    }
                    let row = messageIndex + 1
                    guard let hostingView = self.hostingView(at: row, in: tableView) else {
                        return nil
                    }
                    let currentHeight = tableView.rect(ofRow: row).height
                    let proposedHeight = hostingView.fittingSize.height
                    guard currentHeight.isFinite,
                          proposedHeight.isFinite,
                          abs(currentHeight - proposedHeight) > 0.5 else {
                        return nil
                    }
                    return row
                })
                self.pendingHeightMessageIDs.removeAll()
                guard !rows.isEmpty else { return }
                tableView.noteHeightOfRows(withIndexesChanged: rows)
                tableView.layoutSubtreeIfNeeded()
                self.adjustTopSpacerForShortContent()
                // Appends already have one coalesced tail move pending. Only
                // genuine later resizes, such as an async preview, reposition
                // from the height path.
                if self.followingTail {
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
            ) else {
                return nil
            }
            return cell.subviews.first {
                $0 is IntrinsicInvalidatingHostingView
            } as? IntrinsicInvalidatingHostingView
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

final class TranscriptScrollView: NSScrollView {
    var onViewportWidthChange: ((CGFloat) -> Void)?
    var onUserScroll: (() -> Void)?
    private var lastReportedViewportWidth: CGFloat = 0

    override func layout() {
        super.layout()
        let width = contentView.bounds.width
        guard width > 0, abs(width - lastReportedViewportWidth) > 0.5 else { return }
        lastReportedViewportWidth = width
        onViewportWidthChange?(width)
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}

private final class IntrinsicInvalidatingHostingView: NSHostingView<AnyView> {
    var onIntrinsicSizeInvalidated: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeInvalidated?()
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
