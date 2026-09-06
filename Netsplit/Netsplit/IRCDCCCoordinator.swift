import Combine
import Foundation

/// Owns offer presentation, expiration, resource reservations, and receiver
/// lifetimes. Profile/credential access stays at the application boundary.
@MainActor
final class IRCDCCCoordinator: ObservableObject {
    struct Configuration {
        var receivesFiles: Bool
        var automaticallySavesFiles: Bool
        var downloadDirectory: URL
        var usesCustomDirectory: Bool
    }

    private let configuration: () -> Configuration?
    private let makeRoute: (IRCDCCFileOffer) -> IRCDCCFileReceiver.Route?
    private let caseMapping: (UUID) -> IRCCaseMapping
    private let report: (String, UUID) -> Void
    private let ignoreSender: (String, UUID) -> Void
    private let rememberHostKey: (String, UUID) -> Void

    init(
        configuration: @escaping () -> Configuration?,
        makeRoute: @escaping (IRCDCCFileOffer) -> IRCDCCFileReceiver.Route?,
        caseMapping: @escaping (UUID) -> IRCCaseMapping,
        report: @escaping (String, UUID) -> Void,
        ignoreSender: @escaping (String, UUID) -> Void,
        rememberHostKey: @escaping (String, UUID) -> Void
    ) {
        self.configuration = configuration
        self.makeRoute = makeRoute
        self.caseMapping = caseMapping
        self.report = report
        self.ignoreSender = ignoreSender
        self.rememberHostKey = rememberHostKey
    }

    private var receivesDCCFiles: Bool { configuration()?.receivesFiles == true }

    private func appendSystem(_ text: String, for serverID: UUID) { report(text, serverID) }

    @Published var pendingDCCFileOffer: IRCDCCFileOffer?
    @Published private(set) var dccFileOfferPresentationHostID: UUID?
    @Published private(set) var dccFileTransferCount = 0
    let dccFileTransferStore = IRCDCCFileTransferStore()
    private var queuedDCCFileOffers: [IRCDCCFileOffer] = []
    private var dccFileOfferExpirationTasks: [UUID: DispatchWorkItem] = [:]
    private var dccOfferRateLimiter = IRCDCCOfferRateLimiter()
    private var dccResourceBudget = IRCDCCResourceBudget()
    private var activeDCCFileReceivers: [UUID: IRCDCCFileReceiver] = [:]
    private var dccFileOfferPresentationRequest: (@MainActor () -> Void)?
    private var pendingDCCFileOfferPresentationTask: DispatchWorkItem?
    private var pendingDCCFileOfferPresentationTaskID: UUID?
    private var isDCCFileOfferPresentationRequested = false
    private let maximumQueuedDCCFileOffers = IRCDCCOfferRateLimiter.globalLimit

    func acceptDCCFileOffer(
        _ offer: IRCDCCFileOffer,
        authorizingRestrictedEndpoint: Bool = false,
        downloadDirectory selectedDownloadDirectory: URL? = nil
    ) -> Bool {
        guard let configuration = configuration() else { return false }
        guard receivesDCCFiles,
              pendingDCCFileOffer?.id == offer.id else {
            resolveDCCFileOffer(offer)
            return false
        }
        guard !offer.isExpired() else {
            resolveDCCFileOffer(offer)
            return false
        }
        let endpointAssessment = offer.endpointSecurityAssessment
        guard !endpointAssessment.isProhibited else {
            resolveDCCFileOffer(offer)
            return false
        }
        guard !endpointAssessment.requiresExplicitConsent
                || authorizingRestrictedEndpoint else { return false }
        // When automatic saving is off, accepting the offer is deliberately a
        // two-step operation: the caller must first obtain a folder from an
        // NSOpenPanel and pass it here.
        guard configuration.automaticallySavesFiles || selectedDownloadDirectory != nil else {
            return false
        }
        guard activeDCCFileReceivers[offer.id] == nil else {
            resolveDCCFileOffer(offer)
            return true
        }
        guard let route = makeRoute(offer) else {
            resolveDCCFileOffer(offer)
            return false
        }

        let downloadDirectory = selectedDownloadDirectory ?? configuration.downloadDirectory
        let securityScopedAccess = selectedDownloadDirectory != nil
                || configuration.usesCustomDirectory
            ? IRCDCCSecurityScopedResourceAccess(url: downloadDirectory)
            : nil
        let reservation = dccResourceBudget.reserve(
            offerID: offer.id,
            byteCount: offer.request.size,
            availableCapacity: IRCDCCStoragePolicy.availableCapacity(in: downloadDirectory)
        )
        if case .failure(let error) = reservation {
            appendSystem(
                "Could not receive \(offer.request.filename): \(error.localizedDescription)",
                for: offer.serverID
            )
            resolveDCCFileOffer(offer)
            return false
        }

        let receiver = IRCDCCFileReceiver(
            offer: offer,
            downloadDirectory: downloadDirectory,
            securityScopedAccess: securityScopedAccess,
            progress: { [weak self] progress in
                guard let self, self.activeDCCFileReceivers[offer.id] != nil else { return }
                self.dccResourceBudget.recordProgress(
                    offerID: offer.id,
                    receivedByteCount: progress.receivedByteCount
                )
                self.dccFileTransferStore.updateProgress(progress, for: offer.id)
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.activeDCCFileReceivers.removeValue(forKey: offer.id)
                self.dccResourceBudget.release(offerID: offer.id)
                switch result {
                case .success(let destination):
                    self.dccFileTransferStore.finish(.completed(destination), offerID: offer.id)
                    self.appendSystem(
                        "Received \(offer.request.filename) from \(offer.sender). "
                            + "Saved it to \(destination.dccDisplayPath).",
                        for: offer.serverID
                    )
                case .failure(let error):
                    self.dccFileTransferStore.finish(
                        .failed(error.localizedDescription),
                        offerID: offer.id
                    )
                    self.appendSystem(
                        "Could not receive \(offer.request.filename) from \(offer.sender): \(error.localizedDescription)",
                        for: offer.serverID
                    )
                }
                self.dccFileTransferCount = self.dccFileTransferStore.count
            }
        )
        activeDCCFileReceivers[offer.id] = receiver
        dccFileTransferStore.insert(IRCDCCFileTransferPresentation(
            offer: offer,
            downloadDirectory: downloadDirectory,
            progress: .connecting(totalByteCount: offer.request.size)
        ))
        dccFileTransferCount = dccFileTransferStore.count
        appendSystem(
            "Receiving \(offer.request.filename) from \(offer.sender)\(offer.routesThroughSSH ? " through the SSH tunnel" : "")…",
            for: offer.serverID
        )
        receiver.start(route: route) { [weak self] key in
            self?.rememberHostKey(key, offer.serverID)
        }
        resolveDCCFileOffer(offer)
        return true
    }

    func cancelDCCFileOffer(_ offer: IRCDCCFileOffer) {
        guard pendingDCCFileOffer?.id == offer.id else { return }
        resolveDCCFileOffer(offer)
    }

    func cancelDCCFileTransfer(_ transfer: IRCDCCFileTransferPresentation) {
        guard let receiver = activeDCCFileReceivers[transfer.id],
              receiver.cancel(onCleanup: { [weak self] in
                  self?.activeDCCFileReceivers.removeValue(forKey: transfer.id)
                  self?.dccResourceBudget.release(offerID: transfer.id)
              }) else { return }
        dccFileTransferStore.finish(.canceled, offerID: transfer.id)
        appendSystem(
            "Canceled the file transfer of \(transfer.offer.request.filename) from \(transfer.offer.sender).",
            for: transfer.offer.serverID
        )
    }

    func dismissDCCFileTransfer(_ transfer: IRCDCCFileTransferPresentation) {
        guard activeDCCFileReceivers[transfer.id] == nil else { return }
        dccFileTransferStore.remove(offerID: transfer.id)
        dccFileTransferCount = dccFileTransferStore.count
    }

    func ignoreDCCFileOfferSender(_ offer: IRCDCCFileOffer) {
        guard pendingDCCFileOffer?.id == offer.id,
              activeDCCFileReceivers[offer.id] == nil else { return }
        let ignoredQueuedOfferIDs = Set(queuedDCCFileOffers.compactMap {
            $0.serverID == offer.serverID
                && caseMapping(offer.serverID).normalize($0.sender) == caseMapping(offer.serverID).normalize(offer.sender)
                ? $0.id
                : nil
        })
        queuedDCCFileOffers.removeAll { ignoredQueuedOfferIDs.contains($0.id) }
        ignoredQueuedOfferIDs.forEach(cancelDCCFileOfferExpiration)
        ignoreSender(offer.sender, offer.serverID)
        resolveDCCFileOffer(offer)
    }

    func dccFileOfferSheetDidDismiss() {
        presentNextDCCFileOfferIfNeeded()
    }

    func registerDCCFileOfferPresentationRequest(
        _ request: @escaping @MainActor () -> Void
    ) {
        // Intentionally retain the scene action after its originating window
        // closes. OpenWindowAction addresses the app scene, not that window.
        dccFileOfferPresentationRequest = request
        requestDCCFileOfferPresentationIfNeeded()
    }

    func registerDCCFileOfferPresentationHost(_ hostID: UUID, preferAsActive: Bool) {
        guard preferAsActive || dccFileOfferPresentationHostID == nil else { return }
        dccFileOfferPresentationHostID = hostID
        isDCCFileOfferPresentationRequested = false
        pendingDCCFileOfferPresentationTask?.cancel()
        pendingDCCFileOfferPresentationTask = nil
        pendingDCCFileOfferPresentationTaskID = nil
    }

    func unregisterDCCFileOfferPresentationHost(_ hostID: UUID) {
        guard dccFileOfferPresentationHostID == hostID else { return }
        dccFileOfferPresentationHostID = nil
        requestDCCFileOfferPresentationIfNeeded()
    }

    func enqueueDCCFileOffer(_ offer: IRCDCCFileOffer) {
        guard receivesDCCFiles else { return }
        let now = Date.now
        pruneExpiredDCCFileOffers(at: now)
        let caseMapping = caseMapping(offer.serverID)
        let existingOffers = [pendingDCCFileOffer].compactMap { $0 }
            + queuedDCCFileOffers
            + activeDCCFileReceivers.values.map(\.offer)
        guard !existingOffers.contains(where: {
            offer.hasSameTransferIdentity(
                as: $0,
                normalizedSender: caseMapping.normalize
            )
        }) else { return }
        guard dccOfferRateLimiter.shouldAllow(
            serverID: offer.serverID,
            normalizedSender: caseMapping.normalize(offer.sender),
            at: now
        ) else { return }

        if pendingDCCFileOffer == nil {
            pendingDCCFileOffer = offer
        } else if queuedDCCFileOffers.count < maximumQueuedDCCFileOffers {
            queuedDCCFileOffers.append(offer)
        } else {
            return
        }
        scheduleDCCFileOfferExpiration(offer)
        requestDCCFileOfferPresentationIfNeeded()
    }

    private func resolveDCCFileOffer(_ offer: IRCDCCFileOffer) {
        guard pendingDCCFileOffer?.id == offer.id else { return }
        pendingDCCFileOffer = nil
        cancelDCCFileOfferExpiration(offer.id)
    }

    private func presentNextDCCFileOfferIfNeeded() {
        pruneExpiredDCCFileOffers()
        guard receivesDCCFiles, pendingDCCFileOffer == nil,
              !queuedDCCFileOffers.isEmpty else { return }
        pendingDCCFileOffer = queuedDCCFileOffers.removeFirst()
        requestDCCFileOfferPresentationIfNeeded()
    }

    private func requestDCCFileOfferPresentationIfNeeded() {
        guard receivesDCCFiles,
              pendingDCCFileOffer != nil,
              dccFileOfferPresentationHostID == nil,
              dccFileOfferPresentationRequest != nil,
              !isDCCFileOfferPresentationRequested,
              pendingDCCFileOfferPresentationTask == nil else { return }
        // Give an existing ContentView one run-loop turn to register itself
        // before creating a replacement WindowGroup scene.
        let taskID = UUID()
        let task = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingDCCFileOfferPresentationTaskID == taskID else { return }
            let shouldRun = self.pendingDCCFileOfferPresentationTask?.isCancelled == false
            self.pendingDCCFileOfferPresentationTask = nil
            self.pendingDCCFileOfferPresentationTaskID = nil
            guard shouldRun,
                  self.receivesDCCFiles,
                  self.pendingDCCFileOffer != nil,
                  self.dccFileOfferPresentationHostID == nil else { return }
            self.isDCCFileOfferPresentationRequested = true
            self.dccFileOfferPresentationRequest?()
        }
        pendingDCCFileOfferPresentationTask = task
        pendingDCCFileOfferPresentationTaskID = taskID
        DispatchQueue.main.async(execute: task)
    }

    func removePendingDCCFileOffers(for serverID: UUID) {
        let removedPendingOffer = pendingDCCFileOffer?.serverID == serverID
        var removedOfferIDs = Set(queuedDCCFileOffers.compactMap {
            $0.serverID == serverID ? $0.id : nil
        })
        if removedPendingOffer, let pendingOfferID = pendingDCCFileOffer?.id {
            removedOfferIDs.insert(pendingOfferID)
        }
        if removedPendingOffer { pendingDCCFileOffer = nil }
        queuedDCCFileOffers.removeAll { $0.serverID == serverID }
        removedOfferIDs.forEach(cancelDCCFileOfferExpiration)
        if removedPendingOffer {
            DispatchQueue.main.async { [weak self] in
                self?.presentNextDCCFileOfferIfNeeded()
            }
        }
    }

    func stopAllDCCFileSharingActivity(cleanupGroup: DispatchGroup? = nil) {
        pendingDCCFileOffer = nil
        queuedDCCFileOffers.removeAll()
        dccFileOfferExpirationTasks.values.forEach { $0.cancel() }
        dccFileOfferExpirationTasks.removeAll()
        pendingDCCFileOfferPresentationTask?.cancel()
        pendingDCCFileOfferPresentationTask = nil
        pendingDCCFileOfferPresentationTaskID = nil
        isDCCFileOfferPresentationRequested = false
        dccOfferRateLimiter = IRCDCCOfferRateLimiter()
        activeDCCFileReceivers.values.forEach { receiver in
            let offerID = receiver.offer.id
            if let cleanupGroup {
                cleanupGroup.enter()
                _ = receiver.cancel { [weak self] in
                    self?.dccResourceBudget.release(offerID: offerID)
                    cleanupGroup.leave()
                }
            } else {
                receiver.cancel { [weak self] in
                    self?.dccResourceBudget.release(offerID: offerID)
                }
            }
        }
        activeDCCFileReceivers.removeAll()
        dccFileTransferStore.removeAll()
        dccFileTransferCount = 0
    }

    private func scheduleDCCFileOfferExpiration(_ offer: IRCDCCFileOffer) {
        cancelDCCFileOfferExpiration(offer.id)
        let delay = max(0, IRCDCCFileOffer.lifetime - Date.now.timeIntervalSince(offer.receivedAt))
        let expiration = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dccFileOfferExpirationTasks.removeValue(forKey: offer.id)
            let wasPending = self.pendingDCCFileOffer?.id == offer.id
            if wasPending { self.pendingDCCFileOffer = nil }
            self.queuedDCCFileOffers.removeAll { $0.id == offer.id }
            if wasPending {
                DispatchQueue.main.async { [weak self] in
                    self?.presentNextDCCFileOfferIfNeeded()
                }
            }
        }
        dccFileOfferExpirationTasks[offer.id] = expiration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: expiration)
    }

    private func pruneExpiredDCCFileOffers(at date: Date = .now) {
        if pendingDCCFileOffer?.isExpired(at: date) == true {
            if let offerID = pendingDCCFileOffer?.id {
                cancelDCCFileOfferExpiration(offerID)
            }
            pendingDCCFileOffer = nil
        }
        let expiredQueuedOfferIDs = Set(queuedDCCFileOffers.compactMap {
            $0.isExpired(at: date) ? $0.id : nil
        })
        queuedDCCFileOffers.removeAll { expiredQueuedOfferIDs.contains($0.id) }
        expiredQueuedOfferIDs.forEach(cancelDCCFileOfferExpiration)
    }

    private func cancelDCCFileOfferExpiration(_ offerID: UUID) {
        dccFileOfferExpirationTasks.removeValue(forKey: offerID)?.cancel()
    }
}
