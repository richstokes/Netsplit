import CoreServices
import Darwin
import Foundation
import Testing
@testable import Netsplit

@Suite("DCC file receiving")
struct DCCFileTransferTests {
    @Test("File receiving is opt-in and defaults off")
    func defaultsFileReceivingOff() throws {
        let suiteName = "DCCFileTransferTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!IRCDCCPreferences.receivesFiles(in: defaults))
        defaults.set(true, forKey: IRCDCCPreferences.receivesFilesKey)
        #expect(IRCDCCPreferences.receivesFiles(in: defaults))
    }

    @Test("Parses classic numeric DCC SEND offers")
    func parsesClassicSend() throws {
        let request = try #require(IRCDCCSendParser.request(
            from: "DCC SEND photo.jpg 2130706433 49152 123456"
        ))

        #expect(request == IRCDCCSendRequest(
            filename: "photo.jpg",
            hostname: "127.0.0.1",
            port: 49152,
            size: 123456,
            token: nil
        ))
    }

    @Test("Parses quoted filenames, IPv6 endpoints, and optional tokens")
    func parsesModernSend() throws {
        let request = try #require(IRCDCCSendParser.request(
            from: "DCC SEND \"Summer photo.jpg\" [2001:db8::10] 5000 42 transfer-token"
        ))

        #expect(request.filename == "Summer photo.jpg")
        #expect(request.hostname == "2001:db8::10")
        #expect(request.port == 5000)
        #expect(request.size == 42)
        #expect(request.token == "transfer-token")
    }

    @Test("Preserves quoted Windows paths long enough to sanitize their basename")
    func parsesQuotedWindowsPath() throws {
        let request = try #require(IRCDCCSendParser.request(
            from: #"DCC SEND "C:\Users\sender\Summer photo.jpg" 127.0.0.1 5000 42"#
        ))

        #expect(request.filename == "Summer photo.jpg")
    }

    @Test("Accepts a strictly valid DNS hostname endpoint")
    func parsesHostname() throws {
        let request = try #require(IRCDCCSendParser.request(
            from: "DCC SEND archive.zip dcc.example.org. 5000 42"
        ))

        #expect(request.hostname == "dcc.example.org")
    }

    @Test("Classifies DCC endpoints before consent")
    func classifiesEndpointRisk() {
        #expect(IRCDCCEndpointPolicy.assessment(for: "8.8.8.8") == .publicInternet)
        #expect(IRCDCCEndpointPolicy.assessment(for: "127.0.0.1")
            == .requiresExplicitConsent(.privateOrLocalAddress))
        #expect(IRCDCCEndpointPolicy.assessment(for: "169.254.169.254")
            == .requiresExplicitConsent(.privateOrLocalAddress))
        #expect(IRCDCCEndpointPolicy.assessment(for: "::ffff:127.0.0.1")
            == .requiresExplicitConsent(.privateOrLocalAddress))
        #expect(IRCDCCEndpointPolicy.assessment(for: "dcc.example.org")
            == .requiresExplicitConsent(.hostname))
        #expect(IRCDCCEndpointPolicy.assessment(for: "192.88.99.1")
            == .requiresExplicitConsent(.specialUseAddress))
        #expect(IRCDCCEndpointPolicy.assessment(for: "2002::1")
            == .requiresExplicitConsent(.specialUseAddress))
        #expect(IRCDCCEndpointPolicy.assessment(for: "0.0.0.0") == .prohibited)
        #expect(IRCDCCEndpointPolicy.assessment(for: "ff02::1") == .prohibited)
    }

    @Test("Rejects passive, unbounded, and malformed offers")
    func rejectsUnsupportedSends() {
        let invalidPayloads = [
            "DCC SEND file.txt 127.0.0.1 0 10 passive-token",
            "DCC SEND file.txt 127.0.0.1 5000",
            "DCC SEND \"unterminated file.txt 127.0.0.1 5000 10",
            "DCC SEND file.txt bad/host 5000 10",
            "DCC SEND file.txt 4294967296 5000 10",
            "DCC SEND file.txt 999.999.999.999 5000 10",
            "DCC SEND file.txt -invalid.example 5000 10",
            "DCC GET file.txt 127.0.0.1 5000 10",
            "DCC SEND file.txt 127.0.0.1 65536 10",
            "DCC SEND file.txt 127.0.0.1 5000 ten",
            "DCC SEND file.txt 0.0.0.0 5000 10",
            "DCC SEND file.txt 224.0.0.1 5000 10",
            "DCC SEND file.txt 127.0.0.1 5000 \(IRCDCCResourcePolicy.maximumSingleTransferBytes + 1)"
        ]

        for payload in invalidPayloads {
            #expect(IRCDCCSendParser.request(from: payload) == nil)
        }
    }

    @Test("Reduces sender filenames to safe visible basenames")
    func sanitizesFilenames() {
        #expect(IRCDCCFilename.sanitized("../../.payload.sh") == "payload.sh")
        #expect(IRCDCCFilename.sanitized(#"C:\Users\sender\report.pdf"#) == "report.pdf")
        #expect(IRCDCCFilename.sanitized("  photo.jpg\n") == "photo.jpg")
        #expect(IRCDCCFilename.sanitized("photo\u{202E}gpj.exe") == "photogpj.exe")
        #expect(IRCDCCFilename.sanitized("report:final.txt") == "report-final.txt")
        #expect(IRCDCCFilename.sanitized("../..") == nil)
        #expect(IRCDCCFilename.sanitized("\u{0}\u{7}") == nil)
    }

    @Test("Chooses a collision-free Downloads filename without overwriting")
    func avoidsFilenameCollisions() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "DCCFileTransferTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        #expect(fileManager.createFile(
            atPath: directory.appendingPathComponent("archive.tar.gz").path,
            contents: Data()
        ))
        #expect(fileManager.createFile(
            atPath: directory.appendingPathComponent("archive.tar 2.gz").path,
            contents: Data()
        ))

        let destination = IRCDCCFilename.availableDestination(
            for: "archive.tar.gz",
            in: directory,
            fileManager: fileManager
        )
        #expect(destination.lastPathComponent == "archive.tar 3.gz")
    }

    @Test("Treats dangling symbolic links as occupied download names")
    func avoidsDanglingSymbolicLinkCollisions() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.createSymbolicLink(
            at: directory.appendingPathComponent("report.txt"),
            withDestinationURL: directory.appendingPathComponent("missing-target")
        )

        let destination = IRCDCCFilename.availableDestination(
            for: "report.txt",
            in: directory,
            fileManager: fileManager
        )

        #expect(destination.lastPathComponent == "report 2.txt")
    }

    @Test("Encodes classic cumulative acknowledgements in network byte order")
    func encodesAcknowledgements() {
        #expect(IRCDCCAcknowledgement.data(receivedByteCount: 0x0001_0002)
            == Data([0x00, 0x01, 0x00, 0x02]))
        #expect(IRCDCCAcknowledgement.data(receivedByteCount: 0x1_0000_0001)
            == Data([0x00, 0x00, 0x00, 0x01]))
    }

    @Test("Rejects offers larger than reported available storage")
    func checksAvailableStorage() {
        #expect(IRCDCCStoragePolicy.hasCapacity(for: 42, availableCapacity: 42))
        #expect(!IRCDCCStoragePolicy.hasCapacity(for: 43, availableCapacity: 42))
        #expect(!IRCDCCStoragePolicy.hasCapacity(for: UInt64.max, availableCapacity: nil))
        #expect(!IRCDCCStoragePolicy.hasCapacity(
            for: 42,
            reservedByteCount: 50,
            availableCapacity: 100,
            minimumRemainingCapacity: 10
        ))
    }

    @Test("Reserves aggregate storage and bounds concurrent transfers")
    func reservesTransferResources() throws {
        var budget = IRCDCCResourceBudget()
        let ampleCapacity = Int64(IRCDCCResourcePolicy.minimumRemainingCapacity + 10_000)
        let offerIDs = (0..<IRCDCCResourcePolicy.maximumConcurrentTransfers).map { _ in UUID() }

        for offerID in offerIDs {
            try budget.reserve(
                offerID: offerID,
                byteCount: 1_000,
                availableCapacity: ampleCapacity
            ).get()
        }
        let concurrentResult = budget.reserve(
            offerID: UUID(),
            byteCount: 1,
            availableCapacity: ampleCapacity
        )
        if case .failure(let error) = concurrentResult {
            #expect(error == .tooManyConcurrentTransfers)
        } else {
            Issue.record("Expected the concurrent-transfer limit to reject the reservation")
        }

        budget.release(offerID: offerIDs[0])
        try budget.reserve(
            offerID: UUID(),
            byteCount: 1_000,
            availableCapacity: ampleCapacity
        ).get()

        var unknownCapacityBudget = IRCDCCResourceBudget()
        let unknownCapacityResult = unknownCapacityBudget.reserve(
            offerID: UUID(),
            byteCount: 1,
            availableCapacity: nil
        )
        if case .failure(let error) = unknownCapacityResult {
            #expect(error == .insufficientDiskSpace)
        } else {
            Issue.record("Expected an unknown capacity to fail closed")
        }
    }

    @Test("Storage reservations release bytes as transfers make progress")
    func updatesRemainingTransferReservation() throws {
        var budget = IRCDCCResourceBudget()
        let firstOfferID = UUID()
        let minimumCapacity = IRCDCCResourcePolicy.minimumRemainingCapacity

        try budget.reserve(
            offerID: firstOfferID,
            byteCount: 40,
            availableCapacity: Int64(minimumCapacity + 80)
        ).get()
        budget.recordProgress(offerID: firstOfferID, receivedByteCount: 30)

        #expect(budget.reservedByteCount == 10)
        try budget.reserve(
            offerID: UUID(),
            byteCount: 30,
            availableCapacity: Int64(minimumCapacity + 50)
        ).get()
    }

    @Test("Rate-limits and expires incoming DCC offers")
    func rateLimitsAndExpiresOffers() {
        let serverID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        var limiter = IRCDCCOfferRateLimiter()
        for index in 0..<IRCDCCOfferRateLimiter.perSenderLimit {
            let allowed = limiter.shouldAllow(
                serverID: serverID,
                normalizedSender: "alice",
                at: start.addingTimeInterval(Double(index))
            )
            #expect(allowed)
        }
        let overflowAllowed = limiter.shouldAllow(
            serverID: serverID,
            normalizedSender: "alice",
            at: start.addingTimeInterval(2)
        )
        #expect(!overflowAllowed)
        let allowedAfterWindow = limiter.shouldAllow(
            serverID: serverID,
            normalizedSender: "alice",
            at: start.addingTimeInterval(IRCDCCOfferRateLimiter.observationWindow)
        )
        #expect(allowedAfterWindow)

        let offer = IRCDCCFileOffer(
            serverID: serverID,
            networkName: "Test",
            sender: "Alice",
            request: IRCDCCSendRequest(
                filename: "file.bin",
                hostname: "8.8.8.8",
                port: 5_000,
                size: 42,
                token: nil
            ),
            routesThroughSSH: false,
            receivedAt: start
        )
        #expect(!offer.isExpired(at: start.addingTimeInterval(IRCDCCFileOffer.lifetime - 1)))
        #expect(offer.isExpired(at: start.addingTimeInterval(IRCDCCFileOffer.lifetime)))
    }

    @Test("Terminates sustained trickle transfers after the grace period")
    func detectsTrickleTransfers() {
        #expect(!IRCDCCTransferLivenessPolicy.isBelowMinimumSustainedRate(
            elapsed: .seconds(119),
            bytesPerSecond: 1
        ))
        #expect(IRCDCCTransferLivenessPolicy.isBelowMinimumSustainedRate(
            elapsed: .seconds(120),
            bytesPerSecond: 1
        ))
        #expect(!IRCDCCTransferLivenessPolicy.isBelowMinimumSustainedRate(
            elapsed: .seconds(120),
            bytesPerSecond: IRCDCCResourcePolicy.minimumSustainedBytesPerSecond
        ))
    }

    @Test("Models connecting and bounded transfer progress")
    func modelsTransferProgress() {
        let connecting = IRCDCCTransferProgress.connecting(totalByteCount: 100)
        #expect(connecting.phase == .connecting)
        #expect(connecting.fractionCompleted == nil)

        let halfway = IRCDCCTransferProgress.receiving(
            receivedByteCount: 50,
            totalByteCount: 100,
            bytesPerSecond: 1_024
        )
        #expect(halfway.phase == .receiving)
        #expect(halfway.fractionCompleted == 0.5)
        #expect(halfway.bytesPerSecond == 1_024)

        let bounded = IRCDCCTransferProgress.receiving(
            receivedByteCount: 101,
            totalByteCount: 100
        )
        #expect(bounded.receivedByteCount == 100)
        #expect(bounded.fractionCompleted == 1)
        #expect(IRCDCCTransferProgress.receiving(
            receivedByteCount: 0,
            totalByteCount: 0
        ).fractionCompleted == 1)
        #expect(IRCDCCTransferProgress.receiving(
            receivedByteCount: 0,
            totalByteCount: 1,
            bytesPerSecond: -.infinity
        ).bytesPerSecond == nil)
    }

    @Test("Averages download speed over a recent rolling window")
    func estimatesCurrentTransferRate() {
        var estimator = IRCDCCTransferRateEstimator(window: .seconds(2))

        #expect(estimator.record(byteCount: 0, elapsed: .zero) == nil)
        #expect(estimator.record(
            byteCount: 1_000_000,
            elapsed: .seconds(1)
        ) == 1_000_000)
        #expect(estimator.record(
            byteCount: 1_000_000,
            elapsed: .seconds(3)
        ) == 0)
    }

    @Test("Resets download speed samples when counters move backwards")
    func resetsInvalidTransferRateSamples() {
        var estimator = IRCDCCTransferRateEstimator()
        _ = estimator.record(byteCount: 2_000, elapsed: .seconds(2))

        #expect(estimator.record(byteCount: 1_000, elapsed: .seconds(1)) == nil)
        #expect(estimator.record(
            byteCount: 2_000,
            elapsed: .seconds(2)
        ) == 1_000)
    }

    @Test("Tracks transfer presentation through terminal state")
    @MainActor
    func tracksTransferPresentationState() throws {
        let store = IRCDCCFileTransferStore()
        let serverID = UUID()
        let request = IRCDCCSendRequest(
            filename: "archive.zip",
            hostname: "127.0.0.1",
            port: 5_000,
            size: 100,
            token: nil
        )
        let first = IRCDCCFileTransferPresentation(
            offer: IRCDCCFileOffer(
                serverID: serverID,
                networkName: "Test Network",
                sender: "Alice",
                request: request,
                routesThroughSSH: false
            ),
            progress: .connecting(totalByteCount: request.size),
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let second = IRCDCCFileTransferPresentation(
            offer: IRCDCCFileOffer(
                serverID: serverID,
                networkName: "Test Network",
                sender: "Bob",
                request: request,
                routesThroughSSH: true
            ),
            progress: .connecting(totalByteCount: request.size),
            startedAt: Date(timeIntervalSince1970: 2)
        )

        store.insert(second)
        store.insert(first)
        #expect(store.transfers.map(\.id) == [first.id, second.id])

        store.updateProgress(
            .receiving(receivedByteCount: 50, totalByteCount: 100, bytesPerSecond: 25),
            for: first.id
        )
        #expect(try #require(store.transfers.first).progress.bytesPerSecond == 25)

        let destination = URL(fileURLWithPath: "/tmp/archive.zip")
        store.finish(.completed(destination), offerID: first.id)
        #expect(try #require(store.transfers.first).outcome == .completed(destination))
        store.updateProgress(
            .receiving(receivedByteCount: 75, totalByteCount: 100),
            for: first.id
        )
        #expect(try #require(store.transfers.first).progress.receivedByteCount == 50)

        #expect(store.remove(offerID: first.id)?.id == first.id)
        #expect(store.count == 1)
        store.removeAll()
        #expect(store.transfers.isEmpty)
    }

    @Test("File sink writes atomically and preserves existing downloads")
    func fileSinkWritesAndFinalizes() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let existingURL = directory.appendingPathComponent("payload.bin")
        try Data("existing".utf8).write(to: existingURL)
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let sink = IRCDCCFileSink(
            filename: "payload.bin",
            expectedByteCount: UInt64(payload.count),
            directory: directory
        )

        try await sink.prepare()
        try await sink.write(payload.prefix(100_000))
        try await sink.write(payload.suffix(100_000))
        let destination = try await sink.finalize()

        #expect(destination.lastPathComponent == "payload 2.bin")
        #expect(try Data(contentsOf: destination) == payload)
        #expect(try Data(contentsOf: existingURL) == Data("existing".utf8))
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).allSatisfy {
            !$0.hasPrefix(IRCDCCFileSink.partialFilenamePrefix)
        })
    }

    @Test("Cancel cleanup removes a file committed during finalization")
    func cancelCleanupRemovesFinalizedFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let sink = IRCDCCFileSink(
            filename: "finalized.bin",
            expectedByteCount: 4,
            directory: directory
        )

        try await sink.prepare()
        try await sink.write(Data([1, 2, 3, 4]))
        let destination = try await sink.finalize()
        #expect(fileManager.fileExists(atPath: destination.path))

        await sink.discard(removingFinalizedFile: true)

        #expect(!fileManager.fileExists(atPath: destination.path))
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Stale partial cleanup removes only old Netsplit download files")
    func removesOnlyStalePartialFiles() throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 10_000)
        let oldPartial = directory.appendingPathComponent(".netsplit-download-old.part")
        let recentPartial = directory.appendingPathComponent(".netsplit-download-recent.part")
        let unrelated = directory.appendingPathComponent("unrelated.part")
        for url in [oldPartial, recentPartial, unrelated] {
            #expect(fileManager.createFile(atPath: url.path, contents: Data()))
        }
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-121)],
            ofItemAtPath: oldPartial.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30)],
            ofItemAtPath: recentPartial.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-121)],
            ofItemAtPath: unrelated.path
        )

        IRCDCCFileSink.removeStalePartialFiles(
            in: directory,
            olderThan: 120,
            now: now,
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: oldPartial.path))
        #expect(fileManager.fileExists(atPath: recentPartial.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    @Test("Direct receiver downloads bytes, reports progress, and acknowledges every chunk")
    @MainActor
    func receivesDirectTransferEndToEnd() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let server = try DCCLoopbackServer()
        let senderTask = Task.detached {
            try server.send(payload: payload)
        }
        let offer = makeOffer(port: server.port, size: UInt64(payload.count))

        let (result, progress) = await runReceiver(offer: offer, directory: directory)
        let destination = try result.get()
        let acknowledgements = try await senderTask.value

        #expect(try Data(contentsOf: destination) == payload)
        #expect(acknowledgements.last == UInt32(payload.count))
        #expect(zip(acknowledgements, acknowledgements.dropFirst()).allSatisfy(<))
        #expect(progress.contains { $0.phase == .receiving })
        #expect(progress.last?.phase == .finalizing)
        #expect(progress.last?.fractionCompleted == 1)
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).allSatisfy {
            !$0.hasPrefix(IRCDCCFileSink.partialFilenamePrefix)
        })
    }

    @Test("Direct receiver creates and acknowledges an empty file")
    @MainActor
    func receivesEmptyDirectTransfer() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let server = try DCCLoopbackServer()
        let senderTask = Task.detached {
            try server.send(payload: Data())
        }
        let offer = makeOffer(port: server.port, size: 0)

        let (result, progress) = await runReceiver(offer: offer, directory: directory)
        let destination = try result.get()
        let acknowledgements = try await senderTask.value

        #expect(try Data(contentsOf: destination).isEmpty)
        #expect(acknowledgements == [0])
        #expect(progress.last?.phase == .finalizing)
    }

    @Test("Timed-out receiver removes its partial download")
    @MainActor
    func timedOutReceiverRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let server = try DCCLoopbackServer()
        let senderTask = Task.detached {
            try server.acceptAndStall(for: 0.5)
        }
        let offer = makeOffer(port: server.port, size: 1_024)

        let (result, _) = await runReceiver(
            offer: offer,
            directory: directory,
            connectionTimeout: 1,
            inactivityTimeout: 0.05
        )
        _ = try await senderTask.value

        switch result {
        case .failure(IRCDCCTransferError.timedOut):
            break
        default:
            Issue.record("Expected a DCC inactivity timeout, got \(result)")
        }
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Direct receiver rejects an incomplete transfer and removes its partial file")
    @MainActor
    func incompleteReceiverRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let payload = Data(repeating: 0xa5, count: 1_024)
        let server = try DCCLoopbackServer()
        let senderTask = Task.detached {
            try server.send(payload: payload)
        }
        let offer = makeOffer(port: server.port, size: 2_048)

        let (result, _) = await runReceiver(offer: offer, directory: directory)
        let acknowledgements = try await senderTask.value

        switch result {
        case .failure(IRCDCCTransferError.incomplete(let expected, let received)):
            #expect(expected == 2_048)
            #expect(received == 1_024)
        default:
            Issue.record("Expected an incomplete DCC transfer, got \(result)")
        }
        #expect(acknowledgements == [1_024])
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("SSH receiver applies backpressure, acknowledges chunks, and drains close after data")
    @MainActor
    func receivesSSHTransferEndToEnd() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let first = Data(repeating: 0x41, count: 700)
        let second = Data(repeating: 0x42, count: 900)
        let payload = first + second
        let transport = DCCFakeSSHTransport(events: [
            .data(first),
            .dataAndClose(second)
        ])
        let offer = makeOffer(port: 5_000, size: UInt64(payload.count))

        let (result, progress) = await runReceiver(
            offer: offer,
            directory: directory,
            route: .ssh(makeSSHConfiguration()),
            sshTransportFactory: { transport }
        )
        let destination = try result.get()

        #expect(try Data(contentsOf: destination) == payload)
        #expect(transport.automaticallyReads == false)
        #expect(transport.readRequestCount == 2)
        #expect(transport.acknowledgements == [700, 1_600])
        #expect(transport.didClose)
        #expect(progress.last?.phase == .finalizing)
    }

    @Test("SSH receiver reports an incomplete close and removes its partial file")
    @MainActor
    func incompleteSSHTransferRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let transport = DCCFakeSSHTransport(events: [
            .dataAndClose(Data(repeating: 0x5a, count: 512))
        ])
        let offer = makeOffer(port: 5_000, size: 1_024)

        let (result, _) = await runReceiver(
            offer: offer,
            directory: directory,
            route: .ssh(makeSSHConfiguration()),
            sshTransportFactory: { transport }
        )

        switch result {
        case .failure(IRCDCCTransferError.incomplete(let expected, let received)):
            #expect(expected == 1_024)
            #expect(received == 512)
        default:
            Issue.record("Expected an incomplete tunneled transfer, got \(result)")
        }
        #expect(transport.acknowledgements == [512])
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("SSH receiver times out and removes its partial file")
    @MainActor
    func timedOutSSHTransferRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let transport = DCCFakeSSHTransport(events: [])
        let offer = makeOffer(port: 5_000, size: 1_024)

        let (result, _) = await runReceiver(
            offer: offer,
            directory: directory,
            connectionTimeout: 1,
            inactivityTimeout: 0.05,
            route: .ssh(makeSSHConfiguration()),
            sshTransportFactory: { transport }
        )

        switch result {
        case .failure(IRCDCCTransferError.timedOut):
            break
        default:
            Issue.record("Expected a tunneled DCC inactivity timeout, got \(result)")
        }
        #expect(transport.readRequestCount == 1)
        #expect(transport.didClose)
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Receiver enforces an absolute transfer duration and removes its partial file")
    @MainActor
    func maximumDurationRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let transport = DCCFakeSSHTransport(events: [])
        let offer = makeOffer(port: 5_000, size: 1_024)

        let (result, _) = await runReceiver(
            offer: offer,
            directory: directory,
            connectionTimeout: 1,
            inactivityTimeout: 1,
            maximumTransferDuration: 0.05,
            route: .ssh(makeSSHConfiguration()),
            sshTransportFactory: { transport }
        )

        switch result {
        case .failure(IRCDCCTransferError.maximumDurationExceeded):
            break
        default:
            Issue.record("Expected an absolute DCC duration limit, got \(result)")
        }
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Receiver terminates a sustained trickle and removes its partial file")
    @MainActor
    func lowSpeedTransferRemovesPartialFile() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let transport = DCCFakeSSHTransport(events: [.data(Data([0x01]))])
        let offer = makeOffer(port: 5_000, size: 1_024)

        let (result, _) = await runReceiver(
            offer: offer,
            directory: directory,
            connectionTimeout: 2,
            inactivityTimeout: 2,
            maximumTransferDuration: 5,
            lowSpeedGraceDuration: 0.01,
            minimumSustainedBytesPerSecond: 1_024,
            route: .ssh(makeSSHConfiguration()),
            sshTransportFactory: { transport }
        )

        switch result {
        case .failure(IRCDCCTransferError.transferTooSlow):
            break
        default:
            Issue.record("Expected the DCC low-speed limit, got \(result)")
        }
        #expect(transport.didClose)
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Canceling an SSH receiver closes its transport and awaits file cleanup")
    @MainActor
    func cancelsSSHTransferAndAwaitsCleanup() async throws {
        let fileManager = FileManager.default
        let directory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directory) }
        let transport = DCCFakeSSHTransport(events: [])
        let offer = makeOffer(port: 5_000, size: 1_024)
        var didUnexpectedlyComplete = false
        let receiver = IRCDCCFileReceiver(
            offer: offer,
            downloadDirectory: directory,
            connectionTimeout: 5,
            inactivityTimeout: 5,
            sshTransportFactory: { transport },
            progress: { _ in },
            completion: { _ in didUnexpectedlyComplete = true }
        )
        receiver.start(route: .ssh(makeSSHConfiguration()), onSSHHostKeyLearned: { _ in })

        let readinessDeadline = ContinuousClock.now + .seconds(2)
        while transport.readRequestCount == 0, ContinuousClock.now < readinessDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(transport.readRequestCount == 1)

        var didBeginCancellation = false
        await withCheckedContinuation { continuation in
            didBeginCancellation = receiver.cancel {
                continuation.resume()
            }
        }

        #expect(didBeginCancellation)
        #expect(transport.didClose)
        #expect(!didUnexpectedlyComplete)
        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Marks received files with macOS quarantine metadata")
    func quarantinesReceivedFiles() throws {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "DCC-quarantine-\(UUID().uuidString)"
        )
        #expect(fileManager.createFile(atPath: url.path, contents: Data()))
        defer { try? fileManager.removeItem(at: url) }

        try IRCDCCDownloadedFilePolicy.applyQuarantine(to: url)
        let properties = try #require(
            url.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        )
        #expect(properties[kLSQuarantineAgentNameKey as String] as? String == "Netsplit")
        #expect(!properties.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DCCFileTransferTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeOffer(port: UInt16, size: UInt64) -> IRCDCCFileOffer {
        IRCDCCFileOffer(
            serverID: UUID(),
            networkName: "Loopback",
            sender: "TestSender",
            request: IRCDCCSendRequest(
                filename: "received.bin",
                hostname: "127.0.0.1",
                port: port,
                size: size,
                token: nil
            ),
            routesThroughSSH: false
        )
    }

    private func makeSSHConfiguration() -> SSHTunnelConfiguration {
        SSHTunnelConfiguration(
            sshHostname: "ssh.example.test",
            sshPort: 22,
            sshUsername: "tester",
            sshPassword: "password",
            sshPrivateKey: "",
            trustedHostKey: nil,
            targetHostname: "127.0.0.1",
            targetPort: 5_000,
            useTLS: false
        )
    }

    @MainActor
    private func runReceiver(
        offer: IRCDCCFileOffer,
        directory: URL,
        connectionTimeout: TimeInterval = 2,
        inactivityTimeout: TimeInterval = 2,
        maximumTransferDuration: TimeInterval = IRCDCCResourcePolicy.maximumTransferDuration,
        lowSpeedGraceDuration: TimeInterval = IRCDCCResourcePolicy.lowSpeedGraceDuration,
        minimumSustainedBytesPerSecond: Double = IRCDCCResourcePolicy.minimumSustainedBytesPerSecond,
        route: IRCDCCFileReceiver.Route = .direct,
        sshTransportFactory: @escaping @MainActor @Sendable () -> any IRCDCCSSHTransport = {
            SSHTunnelConnection()
        }
    ) async -> (Result<URL, Error>, [IRCDCCTransferProgress]) {
        await withCheckedContinuation { continuation in
            let lifetime = DCCReceiverLifetime()
            var progressUpdates: [IRCDCCTransferProgress] = []
            let receiver = IRCDCCFileReceiver(
                offer: offer,
                downloadDirectory: directory,
                connectionTimeout: connectionTimeout,
                inactivityTimeout: inactivityTimeout,
                maximumTransferDuration: maximumTransferDuration,
                lowSpeedGraceDuration: lowSpeedGraceDuration,
                minimumSustainedBytesPerSecond: minimumSustainedBytesPerSecond,
                sshTransportFactory: sshTransportFactory,
                progress: { progressUpdates.append($0) },
                completion: { result in
                    lifetime.receiver = nil
                    continuation.resume(returning: (result, progressUpdates))
                }
            )
            lifetime.receiver = receiver
            receiver.start(route: route, onSSHHostKeyLearned: { _ in })
        }
    }
}

@MainActor
private final class DCCFakeSSHTransport: IRCDCCSSHTransport {
    enum Event {
        case data(Data)
        case dataAndClose(Data)
    }

    private var events: [Event]
    private var onData: (@MainActor (Data) -> Void)?
    private var onClose: (@MainActor (Error?) -> Void)?
    private(set) var automaticallyReads: Bool?
    private(set) var readRequestCount = 0
    private(set) var acknowledgements: [UInt32] = []
    private(set) var didClose = false

    init(events: [Event]) {
        self.events = events
    }

    func connect(
        configuration: SSHTunnelConfiguration,
        automaticallyReads: Bool,
        onReady: @escaping @MainActor () -> Void,
        onData: @escaping @MainActor (Data) -> Void,
        onClose: @escaping @MainActor (Error?) -> Void,
        onHostKeyLearned: @escaping @MainActor (String) -> Void
    ) {
        self.automaticallyReads = automaticallyReads
        self.onData = onData
        self.onClose = onClose
        onReady()
    }

    func send(_ data: Data, completion: @escaping @MainActor (Bool, Error?) -> Void) {
        guard data.count == MemoryLayout<UInt32>.size else {
            completion(false, IRCDCCTransferError.connectionClosed)
            return
        }
        let value = data.withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        acknowledgements.append(value)
        completion(true, nil)
    }

    func requestRead() {
        readRequestCount += 1
        guard !events.isEmpty else { return }
        switch events.removeFirst() {
        case .data(let data):
            onData?(data)
        case .dataAndClose(let data):
            onData?(data)
            onClose?(nil)
        }
    }

    func close() {
        didClose = true
        onData = nil
        onClose = nil
    }
}

@MainActor
private final class DCCReceiverLifetime {
    var receiver: IRCDCCFileReceiver?
}

private nonisolated struct DCCLoopbackServer: @unchecked Sendable {
    private let listeningSocket: Int32
    let port: UInt16

    init() throws {
        let listeningSocket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listeningSocket >= 0 else { throw DCCLoopbackServerError("socket") }

        var reuseAddress: Int32 = 1
        guard Darwin.setsockopt(
            listeningSocket,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout.size(ofValue: reuseAddress))
        ) == 0 else {
            Darwin.close(listeningSocket)
            throw DCCLoopbackServerError("setsockopt")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listeningSocket,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else {
            let errorNumber = errno
            Darwin.close(listeningSocket)
            throw DCCLoopbackServerError("bind", errorNumber: errorNumber)
        }
        guard Darwin.listen(listeningSocket, 1) == 0 else {
            let errorNumber = errno
            Darwin.close(listeningSocket)
            throw DCCLoopbackServerError("listen", errorNumber: errorNumber)
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(listeningSocket, $0, &boundAddressLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(listeningSocket)
            throw DCCLoopbackServerError("getsockname")
        }

        self.listeningSocket = listeningSocket
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    func send(payload: Data) throws -> [UInt32] {
        let socket = try acceptConnection()
        defer {
            Darwin.close(socket)
            Darwin.close(listeningSocket)
        }
        try writeAll(payload, to: socket)

        let expectedAcknowledgement = UInt32(truncatingIfNeeded: payload.count)
        var acknowledgements: [UInt32] = []
        repeat {
            let data = try readExactly(4, from: socket)
            let acknowledgement = data.reduce(UInt32.zero) { value, byte in
                (value << 8) | UInt32(byte)
            }
            acknowledgements.append(acknowledgement)
        } while acknowledgements.last != expectedAcknowledgement
        return acknowledgements
    }

    func acceptAndStall(for duration: TimeInterval) throws {
        let socket = try acceptConnection()
        defer {
            Darwin.close(socket)
            Darwin.close(listeningSocket)
        }
        Thread.sleep(forTimeInterval: duration)
    }

    private func acceptConnection() throws -> Int32 {
        let socket = Darwin.accept(listeningSocket, nil, nil)
        guard socket >= 0 else { throw DCCLoopbackServerError("accept") }
        var noSignal: Int32 = 1
        guard Darwin.setsockopt(
            socket,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout.size(ofValue: noSignal))
        ) == 0 else {
            Darwin.close(socket)
            throw DCCLoopbackServerError("setsockopt")
        }
        return socket
    }

    private func writeAll(_ data: Data, to socket: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var sentByteCount = 0
            while sentByteCount < bytes.count {
                guard let baseAddress = bytes.baseAddress else { return }
                let result = Darwin.send(
                    socket,
                    baseAddress.advanced(by: sentByteCount),
                    bytes.count - sentByteCount,
                    0
                )
                guard result > 0 else { throw DCCLoopbackServerError("send") }
                sentByteCount += result
            }
        }
    }

    private func readExactly(_ count: Int, from socket: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var receivedByteCount = 0
            while receivedByteCount < count {
                guard let baseAddress = bytes.baseAddress else { return }
                let result = Darwin.recv(
                    socket,
                    baseAddress.advanced(by: receivedByteCount),
                    count - receivedByteCount,
                    0
                )
                guard result > 0 else { throw DCCLoopbackServerError("recv") }
                receivedByteCount += result
            }
        }
        return data
    }
}

private nonisolated struct DCCLoopbackServerError: LocalizedError {
    let operation: String
    let errorNumber: Int32

    init(_ operation: String, errorNumber: Int32 = errno) {
        self.operation = operation
        self.errorNumber = errorNumber
    }

    var errorDescription: String? {
        "Loopback DCC server \(operation) failed with errno \(errorNumber)."
    }
}
