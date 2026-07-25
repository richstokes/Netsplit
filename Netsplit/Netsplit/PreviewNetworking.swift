//
//  PreviewNetworking.swift
//  Netsplit
//

import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IRCRemotePreviewPolicy {
    nonisolated static let maximumURLLength = 4_096

    nonisolated static func isPermitted(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= maximumURLLength,
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host(percentEncoded: false)?.lowercased(),
              !rawHost.isEmpty,
              !rawHost.contains("%") else { return false }

        if let port = url.port {
            guard port == 443 else { return false }
        }

        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        guard !host.isEmpty,
              host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"),
              host != "metadata.amazonaws.com",
              host != "metadata.google.internal" else { return false }

        // Reject alternative numeric forms (for example 127.1 or dotted
        // octal) rather than relying on URL/DNS parsers to agree about them.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isDottedNumeric = labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && $0.isNumber }
        }
        if isDottedNumeric {
            guard labels.count == 4,
                  labels.allSatisfy({ $0.count == 1 || $0.first != "0" }) else { return false }
        }

        if let address = parsedIPAddress(host) {
            return address.isPublic
        }

        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }),
              !isDottedNumeric else { return false }
        return true
    }

    static func isResolvedDestinationPermitted(_ url: URL) async -> Bool {
        guard isPermitted(url),
              let host = normalizedHost(for: url) else { return false }
        if let address = parsedIPAddress(host) {
            return address.isPublic
        }
        return await Task.detached(priority: .utility) {
            resolvedAddressesArePublic(host)
        }.value
    }

    nonisolated static func normalizedNetworkURL(_ url: URL) -> URL? {
        guard isPermitted(url) else { return nil }

        if normalizedHost(for: url) == "youtu.be" {
            return normalizedYouTubeWatchURL(url)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        if let encodedHost = components.percentEncodedHost {
            components.percentEncodedHost = encodedHost.lowercased()
        }
        if components.port == 443 { components.port = nil }
        components.fragment = nil
        return components.url
    }

    nonisolated private static func normalizedYouTubeWatchURL(_ url: URL) -> URL? {
        let pathComponents = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count == 1 else { return nil }

        let videoID = String(pathComponents[0])
        guard videoID.utf8.count == 11,
              videoID.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) ||
                      (48...57).contains(byte) || byte == 95 || byte == 45
              }) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url
    }

    nonisolated static func permitsRedirect(from source: URL, to destination: URL) -> Bool {
        guard isPermitted(source),
              isPermitted(destination),
              let sourceScheme = source.scheme?.lowercased(),
              let destinationScheme = destination.scheme?.lowercased(),
              let sourceHost = normalizedHost(for: source),
              let destinationHost = normalizedHost(for: destination),
              sourceHost == destinationHost else { return false }

        // Redirects stay on the exact host and HTTPS transport.
        return sourceScheme == "https" && destinationScheme == "https"
    }

    nonisolated private static func normalizedHost(for url: URL) -> String? {
        guard let rawHost = url.host(percentEncoded: false)?.lowercased() else { return nil }
        return rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
    }

    nonisolated private static func resolvedAddressesArePublic(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return false }
        defer { freeaddrinfo(result) }

        var foundAddress = false
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let pointer = cursor {
            let entry = pointer.pointee
            defer { cursor = entry.ai_next }
            guard let socketAddress = entry.ai_addr else { continue }

            switch entry.ai_family {
            case AF_INET:
                let address = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in.self)
                    .pointee
                var rawAddress = address.sin_addr.s_addr
                let bytes = withUnsafeBytes(of: &rawAddress) { Array($0) }
                guard bytes.count == 4 else { return false }
                foundAddress = true
                if !ResolvedIPAddress.v4(bytes).isPublic { return false }

            case AF_INET6:
                let address = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in6.self)
                    .pointee
                var rawAddress = address.sin6_addr
                let bytes = withUnsafeBytes(of: &rawAddress) { Array($0) }
                guard bytes.count == 16 else { return false }
                foundAddress = true
                if !ResolvedIPAddress.v6(bytes).isPublic { return false }

            default:
                continue
            }
        }
        return foundAddress
    }

    nonisolated private static func parsedIPAddress(_ host: String) -> ResolvedIPAddress? {
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            var rawAddress = v4.s_addr
            return .v4(withUnsafeBytes(of: &rawAddress) { Array($0) })
        }

        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            return .v6(withUnsafeBytes(of: &v6) { Array($0) })
        }
        return nil
    }

    private enum ResolvedIPAddress {
        case v4([UInt8])
        case v6([UInt8])

        nonisolated var isPublic: Bool {
            // Conservative subset of the IANA IPv4/IPv6 special-purpose
            // registries. Unknown or non-global IPv6 space is denied.
            // https://www.iana.org/assignments/iana-ipv4-special-registry/
            // https://www.iana.org/assignments/iana-ipv6-special-registry/
            switch self {
            case .v4(let bytes):
                guard bytes.count == 4 else { return false }
                let first = bytes[0]
                let second = bytes[1]
                let third = bytes[2]

                if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
                if first == 100 && (64...127).contains(second) { return false }
                if first == 169 && second == 254 { return false }
                if first == 172 && (16...31).contains(second) { return false }
                if first == 192 && second == 0 && third == 0 { return false }
                if first == 192 && second == 168 { return false }
                if first == 192 && second == 0 && third == 2 { return false }
                if first == 192 && second == 88 && third == 99 { return false }
                if first == 198 && (second == 18 || second == 19) { return false }
                if first == 198 && second == 51 && third == 100 { return false }
                if first == 203 && second == 0 && third == 113 { return false }
                return true

            case .v6(let bytes):
                guard bytes.count == 16 else { return false }

                // Only globally routable unicast is eligible. This excludes
                // unspecified, loopback, link-local, ULA, multicast, NAT64,
                // and other special-purpose prefixes by default.
                guard bytes[0] & 0xE0 == 0x20 else { return false }
                // Documentation, Teredo, and 6to4 can embed or tunnel
                // non-public destinations and are unnecessary for previews.
                if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] <= 0x01 {
                    return false
                }
                if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8 {
                    return false
                }
                if bytes[0] == 0x20 && bytes[1] == 0x02 { return false }
                if bytes[0] == 0x26 && bytes[1] == 0x20 &&
                    bytes[2] == 0 && bytes[3] == 0x4F &&
                    bytes[4] == 0x80 && bytes[5] == 0 {
                    return false
                }
                if bytes[0] == 0x3F && bytes[1] & 0xF0 == 0xF0 { return false }
                return true
            }
        }
    }
}

struct IRCPreviewHTTPResponse {
    let data: Data
    let url: URL
    let mimeType: String
    let textEncodingName: String?
}

enum IRCPreviewBodyPolicy: Equatable {
    case complete
    case htmlHead
}

enum IRCPreviewTransferPolicy {
    nonisolated static func exceedsLimit(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        maximumBytes: Int64
    ) -> Bool {
        let knownLengthExceedsLimit =
            totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown &&
            totalBytesExpectedToWrite > maximumBytes
        return totalBytesWritten > maximumBytes || knownLengthExceedsLimit
    }
}

struct IRCHTMLHeadTerminator {
    nonisolated private static let closingTag = Array("</head>".utf8)
    private var matchedByteCount = 0

    nonisolated mutating func consume(_ byte: UInt8) -> Bool {
        let normalizedByte = (65...90).contains(byte) ? byte + 32 : byte
        if normalizedByte == Self.closingTag[matchedByteCount] {
            matchedByteCount += 1
            if matchedByteCount == Self.closingTag.count {
                matchedByteCount = 0
                return true
            }
        } else {
            matchedByteCount = normalizedByte == Self.closingTag[0] ? 1 : 0
        }
        return false
    }
}

struct IRCBoundedHTMLHeadCollector {
    let maximumBytes: Int
    private(set) var data = Data()
    private var terminator = IRCHTMLHeadTerminator()

    nonisolated init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        data.reserveCapacity(min(maximumBytes, 64 * 1_024))
    }

    nonisolated mutating func consume(_ chunk: Data) -> Bool {
        guard data.count < maximumBytes else { return true }

        for byte in chunk.prefix(maximumBytes - data.count) {
            data.append(byte)
            if terminator.consume(byte) {
                return true
            }
        }
        return data.count == maximumBytes
    }
}

@MainActor
final class IRCPreviewHTTPClient {
    static let shared = IRCPreviewHTTPClient()

    private static let maximumRedirects = 3
    private static let requestTimeout: TimeInterval = 20
    private static let resourceTimeout: TimeInterval = 30
    private let htmlSessionDelegate: IRCBoundedHTMLSessionDelegate
    private let session: URLSession
    private let limiter = IRCPreviewFetchLimiter(limit: 6)

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        let htmlSessionDelegate = IRCBoundedHTMLSessionDelegate()
        self.htmlSessionDelegate = htmlSessionDelegate
        session = URLSession(
            configuration: configuration,
            delegate: htmlSessionDelegate,
            delegateQueue: nil
        )
    }

    func load(
        url: URL,
        maximumBytes: Int,
        acceptHeader: String,
        bodyPolicy: IRCPreviewBodyPolicy = .complete,
        acceptsMIMEType: @escaping (String) -> Bool
    ) async throws -> IRCPreviewHTTPResponse {
        let permitID = UUID()
        let acquired = await withTaskCancellationHandler {
            await limiter.acquire(id: permitID)
        } onCancel: {
            Task { await self.limiter.cancel(id: permitID) }
        }
        guard acquired else { throw CancellationError() }

        do {
            let response = try await loadPermittedResource(
                url: url,
                maximumBytes: maximumBytes,
                acceptHeader: acceptHeader,
                bodyPolicy: bodyPolicy,
                acceptsMIMEType: acceptsMIMEType
            )
            await limiter.release(id: permitID)
            return response
        } catch {
            await limiter.release(id: permitID)
            throw error
        }
    }

    private func loadPermittedResource(
        url: URL,
        maximumBytes: Int,
        acceptHeader: String,
        bodyPolicy: IRCPreviewBodyPolicy,
        acceptsMIMEType: @escaping (String) -> Bool
    ) async throws -> IRCPreviewHTTPResponse {
        guard maximumBytes > 0,
              var currentURL = IRCRemotePreviewPolicy.normalizedNetworkURL(url) else {
            throw IRCPreviewError.disallowedURL
        }

        for redirectCount in 0...Self.maximumRedirects {
            try Task.checkCancellation()
            guard await IRCRemotePreviewPolicy.isResolvedDestinationPermitted(currentURL) else {
                throw IRCPreviewError.disallowedURL
            }

            var request = URLRequest(url: currentURL)
            request.httpMethod = "GET"
            request.timeoutInterval = Self.requestTimeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
            request.setValue("bytes=0-\(maximumBytes - 1)", forHTTPHeaderField: "Range")
            request.setValue("Netsplit-Link-Preview/1.0", forHTTPHeaderField: "User-Agent")

            if bodyPolicy == .complete {
                let downloadDelegate = IRCBoundedDownloadDelegate(maximumBytes: maximumBytes)
                let temporaryURL: URL
                let response: URLResponse
                do {
                    (temporaryURL, response) = try await session.download(
                        for: request,
                        delegate: downloadDelegate
                    )
                } catch {
                    if downloadDelegate.exceededLimit {
                        throw IRCPreviewError.tooLarge
                    }
                    throw error
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw IRCPreviewError.invalidResponse
                }

                if (300...399).contains(httpResponse.statusCode),
                   let location = httpResponse.value(forHTTPHeaderField: "Location"),
                   let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL {
                    guard redirectCount < Self.maximumRedirects,
                          IRCRemotePreviewPolicy.permitsRedirect(from: currentURL, to: redirectURL) else {
                        throw IRCPreviewError.disallowedRedirect
                    }
                    currentURL = redirectURL
                    continue
                }

                guard (200...299).contains(httpResponse.statusCode),
                      let finalURL = httpResponse.url,
                      IRCRemotePreviewPolicy.isPermitted(finalURL),
                      let mimeType = httpResponse.mimeType?.lowercased(),
                      acceptsMIMEType(mimeType) else {
                    throw IRCPreviewError.invalidResponse
                }
                guard response.expectedContentLength <= Int64(maximumBytes) ||
                        response.expectedContentLength == NSURLSessionTransferSizeUnknown else {
                    throw IRCPreviewError.tooLarge
                }

                let resourceValues = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
                guard let fileSize = resourceValues.fileSize,
                      fileSize <= maximumBytes else {
                    throw IRCPreviewError.tooLarge
                }
                let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
                guard data.count <= maximumBytes else {
                    throw IRCPreviewError.tooLarge
                }
                return IRCPreviewHTTPResponse(
                    data: data,
                    url: finalURL,
                    mimeType: mimeType,
                    textEncodingName: response.textEncodingName
                )
            }

            let (data, response) = try await htmlSessionDelegate.data(
                for: request,
                using: session,
                maximumBytes: maximumBytes
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                throw IRCPreviewError.invalidResponse
            }

            if (300...399).contains(httpResponse.statusCode),
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL {
                guard redirectCount < Self.maximumRedirects,
                      IRCRemotePreviewPolicy.permitsRedirect(from: currentURL, to: redirectURL) else {
                    throw IRCPreviewError.disallowedRedirect
                }
                currentURL = redirectURL
                continue
            }

            guard (200...299).contains(httpResponse.statusCode),
                  let finalURL = httpResponse.url,
                  IRCRemotePreviewPolicy.isPermitted(finalURL),
                  let mimeType = httpResponse.mimeType?.lowercased(),
                  acceptsMIMEType(mimeType) else {
                throw IRCPreviewError.invalidResponse
            }
            return IRCPreviewHTTPResponse(
                data: data,
                url: finalURL,
                mimeType: mimeType,
                textEncodingName: response.textEncodingName
            )
        }
        throw IRCPreviewError.disallowedRedirect
    }
}

private final class IRCBoundedHTMLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Output = (Data, URLResponse)

    private struct Transfer {
        var collector: IRCBoundedHTMLHeadCollector
        var response: URLResponse?
        let continuation: CheckedContinuation<Output, Error>
    }

    private let stateLock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    func data(
        for request: URLRequest,
        using session: URLSession,
        maximumBytes: Int
    ) async throws -> Output {
        let cancellationBox = IRCURLSessionTaskCancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                let transfer = Transfer(
                    collector: IRCBoundedHTMLHeadCollector(maximumBytes: maximumBytes),
                    continuation: continuation
                )
                stateLock.withLock {
                    transfers[task.taskIdentifier] = transfer
                }
                cancellationBox.set(task)
                task.resume()
            }
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let isRegistered = stateLock.withLock {
            guard var transfer = transfers[dataTask.taskIdentifier] else { return false }
            transfer.response = response
            transfers[dataTask.taskIdentifier] = transfer
            return true
        }
        completionHandler(isRegistered ? .allow : .cancel)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let completion: (CheckedContinuation<Output, Error>, Output)? = stateLock.withLock {
            guard var transfer = transfers[dataTask.taskIdentifier] else { return nil }
            let isComplete = transfer.collector.consume(data)
            guard isComplete, let response = transfer.response else {
                transfers[dataTask.taskIdentifier] = transfer
                return nil
            }

            transfers[dataTask.taskIdentifier] = nil
            return (
                transfer.continuation,
                (transfer.collector.data, response)
            )
        }

        if let (continuation, output) = completion {
            dataTask.cancel()
            continuation.resume(returning: output)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let transfer = stateLock.withLock {
            transfers.removeValue(forKey: task.taskIdentifier)
        }
        guard let transfer else { return }

        if let error {
            transfer.continuation.resume(throwing: error)
        } else if let response = transfer.response {
            transfer.continuation.resume(returning: (transfer.collector.data, response))
        } else {
            transfer.continuation.resume(throwing: IRCPreviewError.invalidResponse)
        }
    }
}

private final class IRCURLSessionTaskCancellationBox: @unchecked Sendable {
    private let stateLock = NSLock()
    nonisolated(unsafe) private var task: URLSessionTask?
    nonisolated(unsafe) private var isCancelled = false

    nonisolated init() {}

    nonisolated func set(_ task: URLSessionTask) {
        let shouldCancel = stateLock.withLock {
            guard !isCancelled else { return true }
            self.task = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    nonisolated func cancel() {
        let task = stateLock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }
}

private final class IRCBoundedDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let maximumBytes: Int64
    private let stateLock = NSLock()
    private var _exceededLimit = false

    init(maximumBytes: Int) {
        self.maximumBytes = Int64(maximumBytes)
    }

    var exceededLimit: Bool {
        stateLock.withLock { _exceededLimit }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard IRCPreviewTransferPolicy.exceedsLimit(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite,
            maximumBytes: maximumBytes
        ) else { return }

        stateLock.withLock {
            _exceededLimit = true
        }
        downloadTask.cancel()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

private actor IRCPreviewFetchLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var available: Int
    private var holders = Set<UUID>()
    private var cancelled = Set<UUID>()
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        available = max(1, limit)
    }

    func acquire(id: UUID) async -> Bool {
        if cancelled.remove(id) != nil { return false }
        if available > 0 {
            available -= 1
            holders.insert(id)
            return true
        }
        return await withCheckedContinuation { continuation in
            if cancelled.remove(id) != nil {
                continuation.resume(returning: false)
            } else {
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }
    }

    func cancel(id: UUID) {
        if holders.contains(id) { return }
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else {
            cancelled.insert(id)
        }
    }

    func release(id: UUID) {
        guard holders.remove(id) != nil else { return }
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            if cancelled.remove(waiter.id) != nil {
                waiter.continuation.resume(returning: false)
                continue
            }
            holders.insert(waiter.id)
            waiter.continuation.resume(returning: true)
            return
        }
        available = min(limit, available + 1)
    }
}

struct IRCLoadedImage {
    let image: NSImage
    let sourcePixelSize: CGSize
    let sourceData: Data
    let mimeType: String
    let resolvedURL: URL
}

enum IRCBoundedImageLoader {
    static let maximumDownloadBytes = 12 * 1_024 * 1_024
    nonisolated static let maximumDecodedDimension = 1_200
    nonisolated static let maximumSourceDimension = 50_000
    nonisolated static let maximumSourcePixels = 100_000_000
    nonisolated static let maximumFrameCount = 200

    static func loadResource(url: URL) async throws -> IRCLoadedImage {
        let response = try await IRCPreviewHTTPClient.shared.load(
            url: url,
            maximumBytes: maximumDownloadBytes,
            acceptHeader: "image/*",
            acceptsMIMEType: { $0.hasPrefix("image/") }
        )
        guard let decodedImage = decodedImage(from: response.data) else {
            throw IRCPreviewError.invalidImage
        }
        return IRCLoadedImage(
            image: decodedImage.image,
            sourcePixelSize: decodedImage.sourcePixelSize,
            sourceData: response.data,
            mimeType: response.mimeType,
            resolvedURL: response.url
        )
    }

    nonisolated static func thumbnail(from data: Data) -> NSImage? {
        decodedImage(from: data)?.image
    }

    nonisolated private static func decodedImage(
        from data: Data
    ) -> (image: NSImage, sourcePixelSize: CGSize)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return decodedImage(from: source)
    }

    nonisolated private static func decodedImage(
        from source: CGImageSource
    ) -> (image: NSImage, sourcePixelSize: CGSize)? {
        guard CGImageSourceGetCount(source) > 0,
              CGImageSourceGetCount(source) <= maximumFrameCount,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let contentType = UTType(typeIdentifier),
              contentType.conforms(to: .image),
              !typeIdentifier.lowercased().contains("svg"),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= maximumSourceDimension,
              height <= maximumSourceDimension,
              Double(width) * Double(height) <= Double(maximumSourcePixels) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDecodedDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return (
            NSImage(cgImage: cgImage, size: .zero),
            CGSize(width: width, height: height)
        )
    }
}

enum IRCPreviewError: Error {
    case disallowedURL
    case disallowedRedirect
    case invalidResponse
    case invalidImage
    case tooLarge
}
