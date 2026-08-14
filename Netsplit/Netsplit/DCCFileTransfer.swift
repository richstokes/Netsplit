//
//  DCCFileTransfer.swift
//  Netsplit
//

import Combine
import CoreServices
import Foundation
import Network

enum IRCDCCPreferences {
    static let receivesFilesKey = "receivesDCCFiles"

    static func receivesFiles(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: receivesFilesKey) as? Bool ?? false
    }
}

struct IRCDCCSendRequest: Equatable {
    let filename: String
    let hostname: String
    let port: UInt16
    let size: UInt64
    let token: String?
}

enum IRCDCCSendParser {
    /// Parses the complete CTCP payload, without the surrounding \u{01} bytes.
    /// This pass supports active DCC SEND. Reverse/passive offers use port zero
    /// and require a listening socket, so they are deliberately rejected.
    static func request(from payload: String) -> IRCDCCSendRequest? {
        guard let fields = fields(in: payload),
              fields.count == 6 || fields.count == 7,
              fields[0].caseInsensitiveCompare("DCC") == .orderedSame,
              fields[1].caseInsensitiveCompare("SEND") == .orderedSame,
              let filename = IRCDCCFilename.sanitized(fields[2]),
              let hostname = hostname(from: fields[3]),
              let portValue = UInt16(fields[4]),
              portValue > 0 else { return nil }

        // The file size is mandatory here. Besides being part of the common
        // DCC SEND form, it lets Netsplit reject overlong transfers instead of
        // accepting an unbounded stream from another user.
        guard let size = UInt64(fields[5]) else { return nil }

        return IRCDCCSendRequest(
            filename: filename,
            hostname: hostname,
            port: portValue,
            size: size,
            token: fields.count > 6 ? fields[6] : nil
        )
    }

    private static func hostname(from value: String) -> String? {
        if let numericAddress = UInt32(value) {
            return [24, 16, 8, 0]
                .map { String((numericAddress >> UInt32($0)) & 0xff) }
                .joined(separator: ".")
        }

        var hostname = value
        let wasBracketed = hostname.first == "[" && hostname.last == "]"
        if wasBracketed {
            hostname = String(hostname.dropFirst().dropLast())
        }
        guard !hostname.isEmpty, hostname.utf8.count <= 253 else { return nil }
        if IPv6Address(hostname) != nil { return hostname }
        guard !wasBracketed else { return nil }
        let ipv4Components = hostname.split(separator: ".", omittingEmptySubsequences: false)
        if ipv4Components.count == 4,
           ipv4Components.allSatisfy({ component in
               !component.isEmpty
                   && component.allSatisfy { $0.isASCII && $0.isNumber }
                   && UInt8(component) != nil
           }) {
            return hostname
        }
        guard !hostname.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else {
            return nil
        }

        // Hostnames occasionally appear in place of DCC's traditional IP
        // field. Validate labels strictly so malformed numeric addresses are
        // not handed to the system resolver as surprising alternate forms.
        if hostname.last == "." { hostname.removeLast() }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ label in
            guard (1...63).contains(label.utf8.count),
                  label.first?.isASCII == true,
                  label.first?.isLetter == true || label.first?.isNumber == true,
                  label.last?.isASCII == true,
                  label.last?.isLetter == true || label.last?.isNumber == true else {
                return false
            }
            return label.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }) else { return nil }
        return hostname
    }

    private static func fields(in value: String) -> [String]? {
        var result: [String] = []
        var index = value.startIndex

        func skipWhitespace() {
            while index < value.endIndex, value[index].isWhitespace {
                index = value.index(after: index)
            }
        }

        while true {
            skipWhitespace()
            guard index < value.endIndex else { break }

            var field = ""
            if value[index] == "\"" {
                index = value.index(after: index)
                var didCloseQuote = false
                while index < value.endIndex {
                    let character = value[index]
                    index = value.index(after: index)
                    if character == "\\", index < value.endIndex {
                        let nextCharacter = value[index]
                        if nextCharacter == "\\" || nextCharacter == "\"" {
                            field.append(nextCharacter)
                            index = value.index(after: index)
                        } else {
                            // Preserve ordinary backslashes so quoted Windows
                            // paths can still be reduced to their basename.
                            field.append(character)
                        }
                    } else if character == "\"" {
                        didCloseQuote = true
                        break
                    } else {
                        field.append(character)
                    }
                }
                guard didCloseQuote else { return nil }
                guard index == value.endIndex || value[index].isWhitespace else { return nil }
            } else {
                while index < value.endIndex, !value[index].isWhitespace {
                    field.append(value[index])
                    index = value.index(after: index)
                }
            }
            guard !field.isEmpty else { return nil }
            result.append(field)
            guard result.count <= 7 else { return nil }
        }
        return result
    }
}

enum IRCDCCFilename {
    static func sanitized(_ offeredFilename: String) -> String? {
        let normalizedSeparators = offeredFilename.replacingOccurrences(of: "\\", with: "/")
        guard var filename = normalizedSeparators.split(separator: "/", omittingEmptySubsequences: true)
            .last.map(String.init) else { return nil }

        filename = String(filename.unicodeScalars.compactMap { scalar -> Character? in
            let value = scalar.value
            guard !CharacterSet.controlCharacters.contains(scalar),
                  !(0x7f...0x9f).contains(value),
                  value != 0x061c,
                  value != 0x200e,
                  value != 0x200f,
                  !(0x202a...0x202e).contains(value),
                  !(0x2066...0x2069).contains(value) else { return nil }
            return scalar == ":" ? "-" : Character(scalar)
        })
        filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        while filename.first == "." { filename.removeFirst() }
        filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, filename != ".", filename != ".." else { return nil }

        // Leave room for collision suffixes and filesystem bookkeeping.
        var bounded = ""
        for character in filename {
            guard bounded.lengthOfBytes(using: .utf8)
                    + String(character).lengthOfBytes(using: .utf8) <= 220 else { break }
            bounded.append(character)
        }
        return bounded.isEmpty ? nil : bounded
    }

    nonisolated static func availableDestination(
        for filename: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let offeredURL = URL(fileURLWithPath: filename)
        let pathExtension = offeredURL.pathExtension
        let stem = offeredURL.deletingPathExtension().lastPathComponent
        var attempt = 1

        while true {
            let candidateName: String
            if attempt == 1 {
                candidateName = filename
            } else if pathExtension.isEmpty {
                candidateName = "\(stem) \(attempt)"
            } else {
                candidateName = "\(stem) \(attempt).\(pathExtension)"
            }
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !destinationExists(candidate, fileManager: fileManager) { return candidate }
            attempt += 1
        }
    }

    private nonisolated static func destinationExists(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.path) { return true }
        // fileExists follows symbolic links and reports false for a dangling
        // link. Treat the link itself as occupied so collision handling cannot
        // repeatedly choose a destination that moveItem will reject.
        return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

struct IRCDCCFileOffer: Identifiable, Equatable {
    let id: UUID
    let serverID: UUID
    let networkName: String
    let sender: String
    let request: IRCDCCSendRequest
    let routesThroughSSH: Bool

    init(
        id: UUID = UUID(),
        serverID: UUID,
        networkName: String,
        sender: String,
        request: IRCDCCSendRequest,
        routesThroughSSH: Bool
    ) {
        self.id = id
        self.serverID = serverID
        self.networkName = networkName
        self.sender = sender
        self.request = request
        self.routesThroughSSH = routesThroughSSH
    }

    var endpointLabel: String {
        let hostname = request.hostname.contains(":") ? "[\(request.hostname)]" : request.hostname
        return "\(hostname):\(request.port)"
    }
}

enum IRCDCCAcknowledgement {
    static func data(receivedByteCount: UInt64) -> Data {
        var networkValue = UInt32(truncatingIfNeeded: receivedByteCount).bigEndian
        return withUnsafeBytes(of: &networkValue) { Data($0) }
    }
}

enum IRCDCCDownloadedFilePolicy {
    nonisolated static func applyQuarantine(to url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Netsplit",
            kLSQuarantineAgentBundleIdentifierKey as String:
                Bundle.main.bundleIdentifier ?? "richstokes.irc",
            kLSQuarantineTimeStampKey as String: Date(),
            kLSQuarantineTypeKey as String: kLSQuarantineTypeInstantMessageAttachment
        ]
        var quarantinedURL = url
        try quarantinedURL.setResourceValues(resourceValues)
    }
}

enum IRCDCCStoragePolicy {
    nonisolated static func hasCapacity(for fileSize: UInt64, availableCapacity: Int64?) -> Bool {
        guard let availableCapacity, availableCapacity >= 0 else { return true }
        return fileSize <= UInt64(availableCapacity)
    }
}

actor IRCDCCFileSink {
    static let partialFilenamePrefix = ".netsplit-download-"
    static let partialFilenameSuffix = ".part"
    static let stalePartialFileAge: TimeInterval = 24 * 60 * 60

    private let filename: String
    private let expectedByteCount: UInt64
    private let directoryOverride: URL?
    private var fileHandle: FileHandle?
    private var temporaryURL: URL?
    private var downloadDirectory: URL?
    private var finalizedURL: URL?

    init(filename: String, expectedByteCount: UInt64, directory: URL? = nil) {
        self.filename = filename
        self.expectedByteCount = expectedByteCount
        directoryOverride = directory
    }

    func prepare() throws {
        guard fileHandle == nil, temporaryURL == nil else { return }
        let fileManager = FileManager.default
        let directory = directoryOverride ?? Self.downloadsDirectory(fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw IRCDCCTransferError.couldNotCreateDownloadsDirectory
        }
        Self.removeStalePartialFiles(in: directory, fileManager: fileManager)

        let availableCapacity = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        guard IRCDCCStoragePolicy.hasCapacity(
            for: expectedByteCount,
            availableCapacity: availableCapacity
        ) else {
            throw IRCDCCTransferError.insufficientDiskSpace
        }

        let temporaryURL = directory.appendingPathComponent(
            "\(Self.partialFilenamePrefix)\(UUID().uuidString)\(Self.partialFilenameSuffix)",
            isDirectory: false
        )
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw IRCDCCTransferError.couldNotCreateTemporaryFile
        }
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw IRCDCCTransferError.couldNotCreateTemporaryFile
        }
        do {
            try IRCDCCDownloadedFilePolicy.applyQuarantine(to: temporaryURL)
        } catch {
            try? fileHandle?.close()
            fileHandle = nil
            try? fileManager.removeItem(at: temporaryURL)
            throw IRCDCCTransferError.couldNotQuarantineFile
        }
        self.temporaryURL = temporaryURL
        downloadDirectory = directory
    }

    func write(_ data: Data) throws {
        guard let fileHandle else {
            throw IRCDCCTransferError.couldNotCreateTemporaryFile
        }
        try fileHandle.write(contentsOf: data)
    }

    func finalize() throws -> URL {
        guard let fileHandle, let temporaryURL, let downloadDirectory else {
            throw IRCDCCTransferError.couldNotCreateTemporaryFile
        }
        guard !Task.isCancelled else { throw CancellationError() }
        do {
            try fileHandle.synchronize()
            try fileHandle.close()
            self.fileHandle = nil
        } catch {
            try? fileHandle.close()
            self.fileHandle = nil
            throw error
        }
        guard !Task.isCancelled else { throw CancellationError() }

        let fileManager = FileManager.default
        var destination = IRCDCCFilename.availableDestination(
            for: filename,
            in: downloadDirectory,
            fileManager: fileManager
        )
        while true {
            guard !Task.isCancelled else { throw CancellationError() }
            do {
                try fileManager.moveItem(at: temporaryURL, to: destination)
                self.temporaryURL = nil
                finalizedURL = destination
                if Task.isCancelled {
                    try? fileManager.removeItem(at: destination)
                    finalizedURL = nil
                    throw CancellationError()
                }
                return destination
            } catch CocoaError.fileWriteFileExists {
                destination = IRCDCCFilename.availableDestination(
                    for: filename,
                    in: downloadDirectory,
                    fileManager: fileManager
                )
            }
        }
    }

    func discard(removingFinalizedFile: Bool = false) {
        try? fileHandle?.close()
        fileHandle = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
            self.temporaryURL = nil
        }
        if removingFinalizedFile, let finalizedURL {
            try? FileManager.default.removeItem(at: finalizedURL)
            self.finalizedURL = nil
        }
    }

    nonisolated static func removeStalePartialFiles(
        in directory: URL? = nil,
        olderThan maximumAge: TimeInterval = stalePartialFileAge,
        now: Date = .now,
        fileManager: FileManager = .default
    ) {
        let directory = directory ?? downloadsDirectory(fileManager: fileManager)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else { return }
        let cutoff = now.addingTimeInterval(-max(0, maximumAge))
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix(partialFilenamePrefix),
                  name.hasSuffix(partialFilenameSuffix),
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate <= cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private nonisolated static func downloadsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Downloads",
                isDirectory: true
            )
    }
}

struct IRCDCCTransferProgress: Equatable {
    enum Phase: Equatable {
        case connecting
        case receiving
        case finalizing
    }

    let phase: Phase
    let receivedByteCount: UInt64
    let totalByteCount: UInt64
    let bytesPerSecond: Double?

    static func connecting(totalByteCount: UInt64) -> Self {
        Self(
            phase: .connecting,
            receivedByteCount: 0,
            totalByteCount: totalByteCount,
            bytesPerSecond: nil
        )
    }

    static func receiving(
        receivedByteCount: UInt64,
        totalByteCount: UInt64,
        bytesPerSecond: Double? = nil
    ) -> Self {
        Self(
            phase: .receiving,
            receivedByteCount: min(receivedByteCount, totalByteCount),
            totalByteCount: totalByteCount,
            bytesPerSecond: bytesPerSecond.flatMap {
                $0.isFinite && $0 >= 0 ? $0 : nil
            }
        )
    }

    static func finalizing(totalByteCount: UInt64) -> Self {
        Self(
            phase: .finalizing,
            receivedByteCount: totalByteCount,
            totalByteCount: totalByteCount,
            bytesPerSecond: nil
        )
    }

    var fractionCompleted: Double? {
        guard phase != .connecting else { return nil }
        guard totalByteCount > 0 else { return 1 }
        return Double(receivedByteCount) / Double(totalByteCount)
    }
}

enum IRCDCCFileTransferOutcome: Equatable {
    case completed(URL)
    case failed(String)
    case canceled
}

struct IRCDCCFileTransferPresentation: Identifiable, Equatable {
    let offer: IRCDCCFileOffer
    var progress: IRCDCCTransferProgress
    let startedAt: Date
    var outcome: IRCDCCFileTransferOutcome?

    init(
        offer: IRCDCCFileOffer,
        progress: IRCDCCTransferProgress,
        startedAt: Date = .now,
        outcome: IRCDCCFileTransferOutcome? = nil
    ) {
        self.offer = offer
        self.progress = progress
        self.startedAt = startedAt
        self.outcome = outcome
    }

    var id: UUID { offer.id }
}

@MainActor
final class IRCDCCFileTransferStore: ObservableObject {
    @Published private var transfersByOfferID: [UUID: IRCDCCFileTransferPresentation] = [:]

    var transfers: [IRCDCCFileTransferPresentation] {
        transfersByOfferID.values.sorted {
            if $0.startedAt != $1.startedAt {
                return $0.startedAt < $1.startedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var count: Int { transfersByOfferID.count }

    func insert(_ transfer: IRCDCCFileTransferPresentation) {
        transfersByOfferID[transfer.id] = transfer
    }

    func updateProgress(_ progress: IRCDCCTransferProgress, for offerID: UUID) {
        guard var transfer = transfersByOfferID[offerID], transfer.outcome == nil else { return }
        transfer.progress = progress
        transfersByOfferID[offerID] = transfer
    }

    func finish(_ outcome: IRCDCCFileTransferOutcome, offerID: UUID) {
        guard var transfer = transfersByOfferID[offerID], transfer.outcome == nil else { return }
        transfer.outcome = outcome
        transfersByOfferID[offerID] = transfer
    }

    @discardableResult
    func remove(offerID: UUID) -> IRCDCCFileTransferPresentation? {
        transfersByOfferID.removeValue(forKey: offerID)
    }

    func removeAll() {
        transfersByOfferID.removeAll()
    }
}

struct IRCDCCTransferRateEstimator {
    private struct Sample {
        let elapsed: Duration
        let byteCount: UInt64
    }

    private let window: Duration
    private var samples: [Sample] = []

    init(window: Duration = .seconds(2)) {
        self.window = window > .zero ? window : .seconds(2)
    }

    mutating func record(byteCount: UInt64, elapsed: Duration) -> Double? {
        if let last = samples.last,
           elapsed < last.elapsed || byteCount < last.byteCount {
            samples.removeAll()
        }
        samples.append(Sample(elapsed: elapsed, byteCount: byteCount))

        while samples.count > 2,
              samples[1].elapsed + window <= elapsed {
            samples.removeFirst()
        }

        guard let first = samples.first,
              elapsed > first.elapsed,
              byteCount >= first.byteCount else { return nil }
        let duration = elapsed - first.elapsed
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        guard seconds > 0 else { return nil }
        return Double(byteCount - first.byteCount) / seconds
    }
}

enum IRCDCCTransferError: LocalizedError {
    case couldNotCreateDownloadsDirectory
    case couldNotCreateTemporaryFile
    case couldNotQuarantineFile
    case insufficientDiskSpace
    case invalidEndpoint
    case receivedTooMuchData
    case incomplete(expected: UInt64, received: UInt64)
    case timedOut
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDownloadsDirectory:
            "The Downloads directory could not be accessed."
        case .couldNotCreateTemporaryFile:
            "A temporary download file could not be created."
        case .couldNotQuarantineFile:
            "macOS could not mark the received file as an internet download."
        case .insufficientDiskSpace:
            "There is not enough available storage for this file."
        case .invalidEndpoint:
            "The sender provided an invalid file-transfer endpoint."
        case .receivedTooMuchData:
            "The sender transmitted more data than the offered file size."
        case .incomplete(let expected, let received):
            "The sender closed the connection after \(received) of \(expected) bytes."
        case .timedOut:
            "The sender stopped responding."
        case .connectionClosed:
            "The file-transfer connection closed unexpectedly."
        }
    }
}

@MainActor
protocol IRCDCCSSHTransport: AnyObject {
    func connect(
        configuration: SSHTunnelConfiguration,
        automaticallyReads: Bool,
        onReady: @escaping @MainActor () -> Void,
        onData: @escaping @MainActor (Data) -> Void,
        onClose: @escaping @MainActor (Error?) -> Void,
        onHostKeyLearned: @escaping @MainActor (String) -> Void
    )
    func send(_ data: Data, completion: @escaping @MainActor (Bool, Error?) -> Void)
    func requestRead()
    func close()
}

@MainActor
final class IRCDCCFileReceiver {
    enum Route {
        case direct
        case ssh(SSHTunnelConfiguration)
    }

    private enum SSHClosure {
        case clean
        case failed(Error)
    }

    private nonisolated static let defaultConnectionTimeout: TimeInterval = 30
    private nonisolated static let defaultInactivityTimeout: TimeInterval = 60
    private static let maximumReceiveBytes = 64 * 1024
    // Keep large or local transfers from invalidating the entire SwiftUI view
    // tree once per network chunk while still making the bar feel immediate.
    private static let progressUpdateInterval: TimeInterval = 0.1
    private static let speedRefreshInterval: TimeInterval = 1

    let offer: IRCDCCFileOffer

    private let progress: @MainActor (IRCDCCTransferProgress) -> Void
    private let completion: @MainActor (Result<URL, Error>) -> Void
    private let fileSink: IRCDCCFileSink
    private let sshTransportFactory: @MainActor @Sendable () -> any IRCDCCSSHTransport
    private let connectionTimeout: TimeInterval
    private let inactivityTimeout: TimeInterval
    private var directConnection: NWConnection?
    private var sshConnection: (any IRCDCCSSHTransport)?
    private var fileOperationTask: Task<Void, Never>?
    private var receivedByteCount: UInt64 = 0
    private var queuedSSHData: [Data] = []
    private var pendingSSHClosure: SSHClosure?
    private var lastProgressReport: ContinuousClock.Instant?
    private var pendingProgressUpdate: DispatchWorkItem?
    private var speedRefresh: DispatchWorkItem?
    private var receivingStartedAt: ContinuousClock.Instant?
    private var rateEstimator = IRCDCCTransferRateEstimator()
    private var timeoutTimer: DispatchSourceTimer?
    private var didStart = false
    private var didFinish = false
    private var didComplete = false
    private var isCanceling = false
    private var didStartDirectReceiveLoop = false
    private var isProcessingSSHData = false
    private var cancellationCompletions: [@MainActor () -> Void] = []

    init(
        offer: IRCDCCFileOffer,
        downloadDirectory: URL? = nil,
        connectionTimeout: TimeInterval = IRCDCCFileReceiver.defaultConnectionTimeout,
        inactivityTimeout: TimeInterval = IRCDCCFileReceiver.defaultInactivityTimeout,
        sshTransportFactory: @escaping @MainActor @Sendable () -> any IRCDCCSSHTransport = {
            SSHTunnelConnection()
        },
        progress: @escaping @MainActor (IRCDCCTransferProgress) -> Void,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        self.offer = offer
        fileSink = IRCDCCFileSink(
            filename: offer.request.filename,
            expectedByteCount: offer.request.size,
            directory: downloadDirectory
        )
        self.connectionTimeout = max(0.01, connectionTimeout)
        self.inactivityTimeout = max(0.01, inactivityTimeout)
        self.sshTransportFactory = sshTransportFactory
        self.progress = progress
        self.completion = completion
    }

    func start(route: Route, onSSHHostKeyLearned: @escaping @MainActor (String) -> Void) {
        guard !didStart, !didFinish else { return }
        didStart = true
        scheduleTimeout(after: connectionTimeout)
        let fileSink = self.fileSink
        fileOperationTask = Task { [weak self] in
            do {
                try await fileSink.prepare()
                guard !Task.isCancelled, let self, !self.didFinish else {
                    await fileSink.discard()
                    return
                }
                self.fileOperationTask = nil
                switch route {
                case .direct:
                    self.startDirectConnection()
                case .ssh(let configuration):
                    self.startSSHConnection(
                        configuration: configuration,
                        onHostKeyLearned: onSSHHostKeyLearned
                    )
                }
            } catch {
                guard !Task.isCancelled, let self, !self.didFinish else {
                    await fileSink.discard()
                    return
                }
                self.fileOperationTask = nil
                self.fail(error)
            }
        }
    }

    @discardableResult
    func cancel(onCleanup: @escaping @MainActor () -> Void = {}) -> Bool {
        guard !didComplete else {
            onCleanup()
            return false
        }
        cancellationCompletions.append(onCleanup)
        guard !isCanceling else { return true }

        isCanceling = true
        didFinish = true
        closeTransports()
        fileOperationTask?.cancel()
        let fileSink = self.fileSink
        fileOperationTask = Task { [self] in
            // finalize() is actor-isolated and may already have atomically moved
            // the file by the time this cleanup is serviced. In that case the
            // cancellation still wins and removes the just-committed download.
            await fileSink.discard(removingFinalizedFile: true)
            fileOperationTask = nil
            didComplete = true
            let completions = cancellationCompletions
            cancellationCompletions.removeAll()
            completions.forEach { $0() }
        }
        return true
    }

    private func startDirectConnection() {
        guard let port = NWEndpoint.Port(rawValue: offer.request.port) else {
            fail(IRCDCCTransferError.invalidEndpoint)
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        let connection = NWConnection(
            host: NWEndpoint.Host(offer.request.hostname),
            port: port,
            using: NWParameters(tls: nil, tcp: tcp)
        )
        directConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            DispatchQueue.main.async { [weak self, weak connection] in
                MainActor.assumeIsolated {
                    guard let self, let connection, self.directConnection === connection,
                          !self.didFinish else { return }
                    switch state {
                    case .ready:
                        self.scheduleTimeout(after: self.inactivityTimeout)
                        self.beginSpeedUpdates()
                        self.reportReceivingProgress(force: true)
                        if self.offer.request.size == 0 {
                            self.acknowledgeEmptyTransferAndSucceed()
                        } else if !self.didStartDirectReceiveLoop {
                            self.didStartDirectReceiveLoop = true
                            self.receiveDirectData(from: connection)
                        }
                    case .failed(let error):
                        self.fail(error)
                    case .cancelled:
                        self.peerClosed()
                    case .setup, .preparing, .waiting:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func receiveDirectData(from connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.maximumReceiveBytes
        ) { [weak self, weak connection] data, _, isComplete, error in
            DispatchQueue.main.async { [weak self, weak connection] in
                MainActor.assumeIsolated {
                    guard let self, let connection, self.directConnection === connection,
                          !self.didFinish else { return }
                    if let data, !data.isEmpty {
                        self.consume(data) { [weak self, weak connection] in
                            guard let self, let connection,
                                  self.directConnection === connection,
                                  !self.didFinish else { return }
                            if let error {
                                self.fail(error)
                            } else if isComplete {
                                self.peerClosed()
                            } else if self.receivedByteCount < self.offer.request.size {
                                self.receiveDirectData(from: connection)
                            }
                        }
                    } else if let error {
                        self.fail(error)
                    } else if isComplete {
                        self.peerClosed()
                    } else {
                        self.receiveDirectData(from: connection)
                    }
                }
            }
        }
    }

    private func startSSHConnection(
        configuration: SSHTunnelConfiguration,
        onHostKeyLearned: @escaping @MainActor (String) -> Void
    ) {
        let tunnel = sshTransportFactory()
        sshConnection = tunnel
        tunnel.connect(
            configuration: configuration,
            automaticallyReads: false,
            onReady: { [weak self, weak tunnel] in
                guard let self, let tunnel, self.sshConnection === tunnel,
                      !self.didFinish else { return }
                self.scheduleTimeout(after: self.inactivityTimeout)
                self.beginSpeedUpdates()
                self.reportReceivingProgress(force: true)
                if self.offer.request.size == 0 {
                    self.acknowledgeEmptyTransferAndSucceed()
                } else {
                    tunnel.requestRead()
                }
            },
            onData: { [weak self, weak tunnel] data in
                guard let self, let tunnel, self.sshConnection === tunnel,
                      !self.didFinish else { return }
                self.queuedSSHData.append(data)
                self.processNextSSHData()
            },
            onClose: { [weak self, weak tunnel] error in
                guard let self, let tunnel, self.sshConnection === tunnel,
                      !self.didFinish else { return }
                self.handleSSHClosure(error.map(SSHClosure.failed) ?? .clean)
            },
            onHostKeyLearned: { [weak self, weak tunnel] key in
                guard let self, let tunnel, self.sshConnection === tunnel,
                      !self.didFinish else { return }
                onHostKeyLearned(key)
            }
        )
    }

    private func processNextSSHData() {
        guard !didFinish, !isProcessingSSHData else { return }
        guard !queuedSSHData.isEmpty else {
            if let pendingSSHClosure {
                self.pendingSSHClosure = nil
                finishSSHClosure(pendingSSHClosure)
            } else {
                sshConnection?.requestRead()
            }
            return
        }

        isProcessingSSHData = true
        let data = queuedSSHData.removeFirst()
        consume(data) { [weak self] in
            guard let self, !self.didFinish else { return }
            self.isProcessingSSHData = false
            self.processNextSSHData()
        }
    }

    private func handleSSHClosure(_ closure: SSHClosure) {
        guard !didFinish else { return }
        if isProcessingSSHData || !queuedSSHData.isEmpty {
            pendingSSHClosure = closure
        } else {
            finishSSHClosure(closure)
        }
    }

    private func finishSSHClosure(_ closure: SSHClosure) {
        switch closure {
        case .clean:
            peerClosed()
        case .failed(let error):
            fail(error)
        }
    }

    private func consume(_ data: Data, then continuation: @escaping @MainActor () -> Void) {
        guard !didFinish else { return }
        guard receivedByteCount <= offer.request.size else {
            fail(IRCDCCTransferError.receivedTooMuchData)
            return
        }
        let remaining = offer.request.size - receivedByteCount
        guard UInt64(data.count) <= remaining else {
            fail(IRCDCCTransferError.receivedTooMuchData)
            return
        }

        let fileSink = self.fileSink
        fileOperationTask = Task { [weak self] in
            do {
                try await fileSink.write(data)
                guard !Task.isCancelled, let self, !self.didFinish else { return }
                self.fileOperationTask = nil
                self.receivedByteCount += UInt64(data.count)
                self.reportReceivingProgress()
                self.scheduleTimeout(after: self.inactivityTimeout)
                let acknowledgedByteCount = self.receivedByteCount

                self.sendAcknowledgement { [weak self] error in
                    guard let self, !self.didFinish else { return }
                    if let error {
                        if acknowledgedByteCount == self.offer.request.size {
                            // The bytes are complete even if a sender closes without
                            // waiting for the final acknowledgement to flush.
                            self.succeed()
                        } else if self.pendingSSHClosure != nil {
                            // Drain data already delivered by the SSH channel before
                            // reporting its closure. No further read will be issued.
                            continuation()
                        } else {
                            self.fail(error)
                        }
                    } else if acknowledgedByteCount == self.offer.request.size {
                        self.succeed()
                    } else {
                        continuation()
                    }
                }
            } catch {
                guard !Task.isCancelled, let self, !self.didFinish else { return }
                self.fileOperationTask = nil
                self.fail(error)
            }
        }
    }

    private func sendAcknowledgement(completion: @escaping @MainActor (Error?) -> Void) {
        let acknowledgedByteCount = receivedByteCount
        let acknowledgement = IRCDCCAcknowledgement.data(receivedByteCount: acknowledgedByteCount)
        if let connection = directConnection {
            connection.send(content: acknowledgement, completion: .contentProcessed { error in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { completion(error) }
                }
            })
        } else if let tunnel = sshConnection {
            tunnel.send(acknowledgement) { sent, error in
                completion(sent ? nil : (error ?? IRCDCCTransferError.connectionClosed))
            }
        } else {
            completion(IRCDCCTransferError.connectionClosed)
        }
    }

    private func acknowledgeEmptyTransferAndSucceed() {
        sendAcknowledgement { [weak self] _ in
            // There are no file bytes left to recover if the peer closes
            // before observing the zero-byte cumulative acknowledgement.
            self?.succeed()
        }
    }

    private func reportReceivingProgress(force: Bool = false) {
        guard !didFinish else { return }
        let now = ContinuousClock.now
        let intervalHasElapsed: Bool
        if let lastProgressReport {
            intervalHasElapsed = lastProgressReport.duration(to: now) >= .milliseconds(100)
        } else {
            intervalHasElapsed = true
        }
        let shouldReport = force
            || receivedByteCount == offer.request.size
            || intervalHasElapsed
        guard shouldReport else {
            scheduleTrailingProgressUpdate()
            return
        }

        pendingProgressUpdate?.cancel()
        pendingProgressUpdate = nil
        lastProgressReport = now
        let speed: Double?
        if let receivingStartedAt {
            speed = rateEstimator.record(
                byteCount: receivedByteCount,
                elapsed: receivingStartedAt.duration(to: now)
            )
        } else {
            speed = nil
        }
        progress(.receiving(
            receivedByteCount: receivedByteCount,
            totalByteCount: offer.request.size,
            bytesPerSecond: speed
        ))
    }

    private func beginSpeedUpdates() {
        guard receivingStartedAt == nil else { return }
        receivingStartedAt = .now
        scheduleSpeedRefresh()
    }

    private func scheduleSpeedRefresh() {
        guard !didFinish, speedRefresh == nil else { return }
        let refresh = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.speedRefresh = nil
            guard !self.didFinish else { return }
            self.reportReceivingProgress(force: true)
            self.scheduleSpeedRefresh()
        }
        speedRefresh = refresh
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.speedRefreshInterval,
            execute: refresh
        )
    }

    private func scheduleTrailingProgressUpdate() {
        guard pendingProgressUpdate == nil else { return }
        let update = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingProgressUpdate = nil
            self.reportReceivingProgress(force: true)
        }
        pendingProgressUpdate = update
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.progressUpdateInterval,
            execute: update
        )
    }

    private func peerClosed() {
        guard !didFinish else { return }
        if receivedByteCount == offer.request.size {
            succeed()
        } else {
            fail(IRCDCCTransferError.incomplete(
                expected: offer.request.size,
                received: receivedByteCount
            ))
        }
    }

    private func scheduleTimeout(after duration: TimeInterval) {
        let timer: DispatchSourceTimer
        if let timeoutTimer {
            timer = timeoutTimer
        } else {
            let newTimer = DispatchSource.makeTimerSource(queue: .main)
            newTimer.setEventHandler { [weak self] in
                guard let self, !self.didFinish else { return }
                self.fail(IRCDCCTransferError.timedOut)
            }
            newTimer.resume()
            timeoutTimer = newTimer
            timer = newTimer
        }
        timer.schedule(deadline: .now() + max(0.01, duration), leeway: .milliseconds(100))
    }

    private func succeed() {
        guard !didFinish else { return }
        didFinish = true
        closeTransports()
        progress(.finalizing(totalByteCount: offer.request.size))
        let fileSink = self.fileSink
        fileOperationTask = Task { [weak self] in
            do {
                let destination = try await fileSink.finalize()
                guard !Task.isCancelled, let self, !self.isCanceling else { return }
                self.fileOperationTask = nil
                self.didComplete = true
                self.completion(.success(destination))
            } catch {
                await fileSink.discard()
                guard !Task.isCancelled, let self, !self.isCanceling else { return }
                self.fileOperationTask = nil
                self.didComplete = true
                self.completion(.failure(error))
            }
        }
    }

    private func fail(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        closeTransports()
        fileOperationTask?.cancel()
        fileOperationTask = nil
        let fileSink = self.fileSink
        fileOperationTask = Task { [weak self] in
            await fileSink.discard()
            guard !Task.isCancelled, let self, !self.isCanceling else { return }
            self.fileOperationTask = nil
            self.didComplete = true
            self.completion(.failure(error))
        }
    }

    private func closeTransports() {
        directConnection?.stateUpdateHandler = nil
        directConnection?.cancel()
        directConnection = nil
        sshConnection?.close()
        sshConnection = nil
        queuedSSHData.removeAll()
        pendingSSHClosure = nil
        isProcessingSSHData = false
        pendingProgressUpdate?.cancel()
        pendingProgressUpdate = nil
        speedRefresh?.cancel()
        speedRefresh = nil
        timeoutTimer?.setEventHandler {}
        timeoutTimer?.cancel()
        timeoutTimer = nil
    }
}
