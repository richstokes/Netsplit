//
//  MessagePreviews.swift
//  Netsplit
//

import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum IRCMessagePreview: Hashable, Identifiable {
    case link(URL)
    case image(URL)

    var id: String {
        switch self {
        case .link(let url): return "link:\(url.absoluteString)"
        case .image(let url): return "image:\(url.absoluteString)"
        }
    }
}

enum IRCMessagePreviewPolicy {
    static let maximumPreviewsPerMessage = 3
    private static let webURLCache = IRCMessageWebURLCache(countLimit: 5_500)
    private static let imageExtensions = Set([
        "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ])

    static func previews(
        for message: IRCMessage,
        in destination: SidebarItem,
        showsLinkPreviews: Bool,
        showsImagePreviews: Bool
    ) -> [IRCMessagePreview] {
        guard showsLinkPreviews || showsImagePreviews,
              !message.isSystem,
              !message.isNotice else { return [] }

        switch destination {
        case .channel, .directMessage:
            break
        case .connectionCenter, .server:
            return []
        }

        var seenResources = Set<URL>()
        return webURLCache.webURLs(for: message)
            .compactMap { url -> IRCMessagePreview? in
                guard let networkURL = IRCRemotePreviewPolicy.normalizedNetworkURL(url),
                      seenResources.insert(networkURL).inserted else { return nil }
                let pathExtension = url.pathExtension.lowercased()
                if imageExtensions.contains(pathExtension) {
                    return showsImagePreviews ? .image(url) : nil
                }
                guard !isKnownBinaryResource(pathExtension: pathExtension) else { return nil }
                return showsLinkPreviews ? .link(url) : nil
            }
            .prefix(maximumPreviewsPerMessage)
            .map { $0 }
    }

    private static func isKnownBinaryResource(pathExtension: String) -> Bool {
        guard !pathExtension.isEmpty,
              let contentType = UTType(filenameExtension: pathExtension),
              !contentType.isDynamic else { return false }
        return !contentType.conforms(to: .text)
    }
}

enum IRCPreviewFailureReason: Equatable {
    case timedOut
    case tooLarge
    case blocked
    case unavailable

    init(error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.timedOut.rawValue {
            self = .timedOut
            return
        }

        switch error as? IRCPreviewError {
        case .tooLarge:
            self = .tooLarge
        case .disallowedURL, .disallowedRedirect:
            self = .blocked
        default:
            self = .unavailable
        }
    }

    var message: String {
        switch self {
        case .timedOut:
            return "The preview took too long to load."
        case .tooLarge:
            return "The preview is too large to load safely."
        case .blocked:
            return "The preview was blocked for safety."
        case .unavailable:
            return "A preview isn’t available for this link."
        }
    }
}

struct IRCMessagePreviewLayoutChange: Equatable {
    let selection: SidebarItem
    let messageID: UUID
    let revision: UInt64
}

/// A small, deterministic memory cache for preview state that must survive a
/// native transcript-row rebuild. `NSCache` may discard any entry at any time;
/// when that happened to two visible previews, each completed load rebuilt the
/// table and discarded the other preview's row-local state, creating a reload
/// loop. This cache keeps the same hard bounds while evicting the least recently
/// used entry first.
@MainActor
struct IRCPreviewMemoryCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
        var lastAccess: UInt64
    }

    private let countLimit: Int
    private let totalCostLimit: Int
    private var entries: [Key: Entry] = [:]
    private var totalCost = 0
    private var accessCounter: UInt64 = 0

    init(countLimit: Int, totalCostLimit: Int = .max) {
        self.countLimit = max(0, countLimit)
        self.totalCostLimit = max(0, totalCostLimit)
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, cost: Int = 0) {
        let boundedCost = max(0, cost)
        if let existing = entries.removeValue(forKey: key) {
            totalCost -= existing.cost
        }
        accessCounter &+= 1
        entries[key] = Entry(
            value: value,
            cost: boundedCost,
            lastAccess: accessCounter
        )
        totalCost += boundedCost
        evictIfNeeded()
    }

    private mutating func evictIfNeeded() {
        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let oldestKey = entries.min(
                by: { $0.value.lastAccess < $1.value.lastAccess }
            )?.key,
            let removed = entries.removeValue(forKey: oldestKey) else { return }
            totalCost -= removed.cost
        }
    }
}

final class IRCMessagePreviewExpansionStore: ObservableObject {
    private struct PendingPreviewLayoutInvalidation {
        let messageID: UUID
        let workItem: DispatchWorkItem
    }

    private static let previewLoadLayoutDelay: TimeInterval = 0.35

    @Published private(set) var latestLayoutChange: IRCMessagePreviewLayoutChange?
    private var latestLayoutChangesBySelection: [
        SidebarItem: IRCMessagePreviewLayoutChange
    ] = [:]
    private var collapsedMessageIDsBySelection: [SidebarItem: Set<UUID>] = [:]
    private var pendingPreviewLayoutInvalidations: [
        SidebarItem: PendingPreviewLayoutInvalidation
    ] = [:]
    private var nextLayoutRevision: UInt64 = 0

    func isExpanded(for messageID: UUID, in selection: SidebarItem) -> Bool {
        !(collapsedMessageIDsBySelection[selection]?.contains(messageID) ?? false)
    }

    func toggle(for messageID: UUID, in selection: SidebarItem) {
        setExpanded(
            !isExpanded(for: messageID, in: selection),
            for: messageID,
            in: selection
        )
    }

    func setExpanded(
        _ isExpanded: Bool,
        for messageID: UUID,
        in selection: SidebarItem
    ) {
        guard isExpanded != self.isExpanded(for: messageID, in: selection) else {
            return
        }
        if isExpanded {
            collapsedMessageIDsBySelection[selection]?.remove(messageID)
            if collapsedMessageIDsBySelection[selection]?.isEmpty == true {
                collapsedMessageIDsBySelection.removeValue(forKey: selection)
            }
        } else {
            collapsedMessageIDsBySelection[selection, default: []].insert(messageID)
        }
        invalidateLayout(for: messageID, in: selection)
    }

    func invalidateLayout(for messageID: UUID, in selection: SidebarItem) {
        cancelPendingPreviewLayoutInvalidation(in: selection)
        nextLayoutRevision &+= 1
        let change = IRCMessagePreviewLayoutChange(
            selection: selection,
            messageID: messageID,
            revision: nextLayoutRevision
        )
        latestLayoutChangesBySelection[selection] = change
        latestLayoutChange = change
    }

    func latestLayoutChange(for selection: SidebarItem) -> IRCMessagePreviewLayoutChange? {
        latestLayoutChangesBySelection[selection]
    }

    /// Image preview resources in a newly realized transcript commonly
    /// complete in a short burst. AppKit needs a full native-table measurement
    /// to accept their new automatic heights, so collapse that burst into one
    /// refresh.
    /// Disclosure changes continue to use invalidateLayout directly and stay
    /// immediate.
    func schedulePreviewLayoutInvalidation(
        for messageID: UUID,
        in selection: SidebarItem
    ) {
        cancelPendingPreviewLayoutInvalidation(in: selection)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingPreviewLayoutInvalidations[selection]?.messageID == messageID
            else { return }
            self.pendingPreviewLayoutInvalidations.removeValue(forKey: selection)
            self.invalidateLayout(for: messageID, in: selection)
        }
        pendingPreviewLayoutInvalidations[selection] = PendingPreviewLayoutInvalidation(
            messageID: messageID,
            workItem: workItem
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.previewLoadLayoutDelay,
            execute: workItem
        )
    }

    func retainMessages(withIDs messageIDs: Set<UUID>, in selection: SidebarItem) {
        collapsedMessageIDsBySelection[selection]?.formIntersection(messageIDs)
        if collapsedMessageIDsBySelection[selection]?.isEmpty == true {
            collapsedMessageIDsBySelection.removeValue(forKey: selection)
        }
        if let pending = pendingPreviewLayoutInvalidations[selection],
           !messageIDs.contains(pending.messageID) {
            cancelPendingPreviewLayoutInvalidation(in: selection)
        }
    }

    private func cancelPendingPreviewLayoutInvalidation(in selection: SidebarItem) {
        pendingPreviewLayoutInvalidations.removeValue(forKey: selection)?.workItem.cancel()
    }
}

struct MessagePreviewStack: View {
    let previews: [IRCMessagePreview]
    let messageID: UUID
    let selection: SidebarItem
    @ObservedObject var expansion: IRCMessagePreviewExpansionStore

    private var isExpanded: Bool {
        expansion.isExpanded(for: messageID, in: selection)
    }

    var body: some View {
        if !previews.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    expansion.toggle(for: messageID, in: selection)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10)
                        Text(previewLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide previews" : "Show previews")
                .accessibilityLabel(isExpanded ? "Hide previews" : "Show previews")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(previews) { preview in
                            switch preview {
                            case .link(let url):
                                IRCLinkPreviewCard(url: url)
                            case .image(let url):
                                IRCImagePreview(
                                    url: url,
                                    onLoad: invalidateRowLayout
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private var previewLabel: String {
        previews.count == 1 ? "Preview" : "\(previews.count) previews"
    }

    private func invalidateRowLayout() {
        expansion.schedulePreviewLayoutInvalidation(
            for: messageID,
            in: selection
        )
    }
}

struct IRCLinkPreviewMetadata: Equatable {
    let title: String?
    let summary: String?
    let resolvedURL: URL
}

enum IRCLinkPreviewMetadataParser {
    private static let maximumHTMLBytes = 1_024 * 1_024
    private static let maximumOEmbedBytes = 64 * 1_024
    private static let maximumTitleCharacters = 200
    private static let maximumSummaryCharacters = 280

    static func fetch(url: URL) async throws -> IRCLinkPreviewMetadata {
        if let oEmbedURL = redditOEmbedURL(for: url) {
            let response = try await IRCPreviewHTTPClient.shared.load(
                url: oEmbedURL,
                maximumBytes: maximumOEmbedBytes,
                acceptHeader: "application/json",
                acceptsMIMEType: { $0 == "application/json" }
            )
            return try parseRedditOEmbed(data: response.data, originalURL: url)
        }

        let response = try await IRCPreviewHTTPClient.shared.load(
            url: url,
            maximumBytes: maximumHTMLBytes,
            acceptHeader: "text/html, application/xhtml+xml;q=0.9",
            bodyPolicy: .htmlHead,
            acceptsMIMEType: { mimeType in
                mimeType == "text/html" || mimeType == "application/xhtml+xml"
            }
        )
        return parse(
            data: response.data,
            responseURL: response.url,
            textEncodingName: response.textEncodingName
        )
    }

    static func parse(
        data: Data,
        responseURL: URL,
        textEncodingName: String? = nil
    ) -> IRCLinkPreviewMetadata {
        let html = decode(data: data, textEncodingName: textEncodingName)
        var metaValues: [String: String] = [:]

        for tag in matches(pattern: #"<meta\b[^>]{0,8192}>"#, in: html, limit: 200) {
            let attributes = parsedAttributes(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"],
                  metaValues[key] == nil else { continue }
            metaValues[key] = content
        }

        let rawTitle = metaValues["og:title"] ?? metaValues["twitter:title"] ??
            firstCapture(pattern: #"<title\b[^>]{0,8192}>(.{0,8192}?)</title\s*>"#, in: html)
        let rawSummary = metaValues["og:description"] ?? metaValues["twitter:description"] ??
            metaValues["description"]

        return IRCLinkPreviewMetadata(
            title: rawTitle.flatMap { sanitizedText($0, maximumCharacters: maximumTitleCharacters) },
            summary: rawSummary.flatMap { sanitizedText($0, maximumCharacters: maximumSummaryCharacters) },
            resolvedURL: responseURL
        )
    }

    static func redditOEmbedURL(for url: URL) -> URL? {
        guard let normalizedURL = IRCRemotePreviewPolicy.normalizedNetworkURL(url),
              let host = normalizedURL.host(percentEncoded: false)?.lowercased(),
              ["reddit.com", "www.reddit.com", "old.reddit.com", "np.reddit.com"].contains(host)
        else { return nil }

        let pathComponents = normalizedURL.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let commentsIndex = pathComponents.firstIndex(of: "comments"),
              pathComponents.indices.contains(commentsIndex + 1)
        else { return nil }

        let postID = pathComponents[commentsIndex + 1]
        guard (5...16).contains(postID.utf8.count),
              postID.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
              })
        else { return nil }

        var permalinkComponents = URLComponents(
            url: normalizedURL,
            resolvingAgainstBaseURL: false
        )
        permalinkComponents?.query = nil
        guard let permalink = permalinkComponents?.url else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.reddit.com"
        components.path = "/oembed"
        components.queryItems = [URLQueryItem(name: "url", value: permalink.absoluteString)]
        guard let oEmbedURL = components.url,
              IRCRemotePreviewPolicy.isPermitted(oEmbedURL)
        else { return nil }
        return oEmbedURL
    }

    static func parseRedditOEmbed(data: Data, originalURL: URL) throws -> IRCLinkPreviewMetadata {
        struct Response: Decodable {
            let title: String?
            let authorName: String?

            enum CodingKeys: String, CodingKey {
                case title
                case authorName = "author_name"
            }
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw IRCPreviewError.invalidResponse
        }

        guard let title = response.title.flatMap({
            sanitizedText($0, maximumCharacters: maximumTitleCharacters)
        }) else {
            throw IRCPreviewError.invalidResponse
        }

        let summary = response.authorName
            .flatMap { sanitizedText($0, maximumCharacters: maximumSummaryCharacters) }
            .map { $0.hasPrefix("u/") ? "Posted by \($0)" : "Posted by u/\($0)" }

        return IRCLinkPreviewMetadata(
            title: title,
            summary: summary,
            resolvedURL: originalURL
        )
    }

    private static func decode(data: Data, textEncodingName: String?) -> String {
        if let textEncodingName {
            let coreFoundationEncoding = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if coreFoundationEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(
                    rawValue: CFStringConvertEncodingToNSStringEncoding(coreFoundationEncoding)
                )
                if let decoded = String(data: data, encoding: encoding) { return decoded }
            }
        }
        return String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .windowsCP1252) ??
            String(decoding: data, as: UTF8.self)
    }

    private static func matches(pattern: String, in value: String, limit: Int) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        var results: [String] = []
        expression.enumerateMatches(in: value, range: range) { match, _, stop in
            guard let match,
                  let swiftRange = Range(match.range, in: value) else { return }
            results.append(String(value[swiftRange]))
            if results.count >= limit {
                stop.pointee = true
            }
        }
        return results
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func parsedAttributes(in tag: String) -> [String: String] {
        let pattern = #"\b([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }

        var attributes: [String: String] = [:]
        for match in expression.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)).prefix(50) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = tag[nameRange].lowercased()
            for captureIndex in 2..<match.numberOfRanges where match.range(at: captureIndex).location != NSNotFound {
                if let valueRange = Range(match.range(at: captureIndex), in: tag) {
                    attributes[name] = String(tag[valueRange])
                    break
                }
            }
        }
        return attributes
    }

    private static func sanitizedText(_ rawValue: String, maximumCharacters: Int) -> String? {
        let decoded = decodeHTMLEntities(rawValue)
        let withoutTags = decoded.replacingOccurrences(
            of: #"<[^>]{0,2048}>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let scalars = withoutTags.unicodeScalars.filter { scalar in
            let value = scalar.value
            guard value != 0,
                  !(value < 0x20 && value != 0x09 && value != 0x0A && value != 0x0D),
                  !(0x7F...0x9F).contains(value),
                  value != 0x061C,
                  value != 0x200E,
                  value != 0x200F,
                  !(0x202A...0x202E).contains(value),
                  !(0x2066...0x2069).contains(value) else { return false }
            return true
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(String.UnicodeScalarView(collapsed.unicodeScalars.prefix(maximumCharacters)))
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        let namedEntities: [String: String] = [
            "amp": "&", "apos": "'", "gt": ">", "hellip": "…", "lt": "<",
            "mdash": "—", "nbsp": " ", "ndash": "–", "quot": "\""
        ]
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "&",
                  let semicolon = value[index...].prefix(16).firstIndex(of: ";") else {
                result.append(value[index])
                index = value.index(after: index)
                continue
            }

            let entityStart = value.index(after: index)
            let entity = String(value[entityStart..<semicolon])
            let replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16)
                    .flatMap(UnicodeScalar.init)
                    .map(String.init)
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst())
                    .flatMap(UnicodeScalar.init)
                    .map(String.init)
            } else {
                replacement = namedEntities[entity.lowercased()]
            }

            if let replacement {
                result.append(replacement)
                index = value.index(after: semicolon)
            } else {
                result.append("&")
                index = entityStart
            }
        }
        return result
    }
}

@MainActor
private final class IRCLinkPreviewCache {
    static let shared = IRCLinkPreviewCache()

    private var cache = IRCPreviewMemoryCache<URL, IRCLinkPreviewMetadata>(
        countLimit: 200
    )
    private var inFlight: [URL: Task<IRCLinkPreviewMetadata, Error>] = [:]

    private init() {}

    func cachedMetadata(for url: URL) -> IRCLinkPreviewMetadata? {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        return cache.value(for: key)
    }

    func metadata(for url: URL) async throws -> IRCLinkPreviewMetadata {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        if let cached = cachedMetadata(for: key) { return cached }
        if let task = inFlight[key] { return try await task.value }

        let task = Task { try await IRCLinkPreviewMetadataParser.fetch(url: key) }
        inFlight[key] = task
        do {
            let metadata = try await task.value
            cache.insert(metadata, for: key)
            inFlight[key] = nil
            return metadata
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private struct IRCLinkPreviewCard: View {
    private static let maximumWidth: CGFloat = 440

    let url: URL
    @State private var metadata: IRCLinkPreviewMetadata?
    @State private var failureReason: IRCPreviewFailureReason?
    @State private var retryCount = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.ircThemePalette) private var themePalette

    var body: some View {
        Group {
            if let displayedMetadata {
                loadedPreview(for: displayedMetadata)
            } else if let failureReason {
                IRCPreviewFailureView(
                    reason: failureReason,
                    maximumWidth: Self.maximumWidth,
                    minimumHeight: 72,
                    retry: retry
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: Self.maximumWidth, minHeight: 72)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Loading link preview")
            }
        }
        .task(id: loadID) {
            failureReason = nil
            do {
                let loadedMetadata = try await IRCLinkPreviewCache.shared.metadata(for: url)
                guard !Task.isCancelled else { return }
                // The hosting view propagates this intrinsic-size change to
                // its table row. A separate delayed reload would resize the
                // same link card a second time.
                metadata = loadedMetadata
            } catch {
                guard !Task.isCancelled else { return }
                failureReason = IRCPreviewFailureReason(error: error)
            }
        }
    }

    private var loadID: String {
        "\(url.absoluteString)#\(retryCount)"
    }

    private var displayedMetadata: IRCLinkPreviewMetadata? {
        metadata ?? IRCLinkPreviewCache.shared.cachedMetadata(for: url)
    }

    private func retry() {
        failureReason = nil
        retryCount += 1
    }

    private func loadedPreview(for metadata: IRCLinkPreviewMetadata) -> some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayHost)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(previewTitle(for: metadata))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let summary = metadata.summary {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(displayURL(for: metadata))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
            .frame(
                maxWidth: Self.maximumWidth,
                minHeight: 82,
                maxHeight: 128,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help("Open \(url.absoluteString)")
        .accessibilityLabel("Link preview: \(previewTitle(for: metadata))")
    }

    private var displayHost: String {
        (url.host(percentEncoded: true) ?? "WEB LINK").uppercased()
    }

    private func previewTitle(for metadata: IRCLinkPreviewMetadata) -> String {
        metadata.title ?? displayURL(for: metadata)
    }

    private func displayURL(for metadata: IRCLinkPreviewMetadata?) -> String {
        guard let components = URLComponents(url: metadata?.resolvedURL ?? url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let path = components.path == "/" ? "" : components.path
        return (components.percentEncodedHost ?? components.host ?? "") + path
    }

    private var cardBackground: Color {
        themePalette?.panel ?? Color(nsColor: .controlBackgroundColor)
    }

    private var cardBorder: Color {
        themePalette?.border.opacity(0.7) ?? Color(nsColor: .separatorColor)
    }
}

@MainActor
private final class IRCImagePreviewCache {
    static let shared = IRCImagePreviewCache()

    private var cache = IRCPreviewMemoryCache<URL, IRCLoadedImage>(
        countLimit: 100,
        totalCostLimit: 64 * 1_024 * 1_024
    )
    private var inFlight: [URL: Task<IRCLoadedImage, Error>] = [:]

    private init() {}

    func cachedResource(for url: URL) -> IRCLoadedImage? {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        return cache.value(for: key)
    }

    func resource(for url: URL) async throws -> IRCLoadedImage {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        if let cached = cachedResource(for: key) { return cached }
        if let task = inFlight[key] { return try await task.value }

        let task = Task { try await IRCBoundedImageLoader.loadResource(url: key) }
        inFlight[key] = task
        do {
            let resource = try await task.value
            let imageCost = Int(resource.image.size.width * resource.image.size.height * 4)
            cache.insert(
                resource,
                for: key,
                cost: imageCost + resource.sourceData.count
            )
            inFlight[key] = nil
            return resource
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private struct IRCImagePreview: View {
    let url: URL
    let onLoad: () -> Void
    @State private var resource: IRCLoadedImage?
    @State private var failureReason: IRCPreviewFailureReason?
    @State private var retryCount = 0
    @State private var isShowingViewer = false
    @Environment(\.ircThemePalette) private var themePalette

    var body: some View {
        Group {
            if let displayedResource {
                loadedPreview(for: displayedResource.image)
            } else if let failureReason {
                IRCPreviewFailureView(
                    reason: failureReason,
                    maximumWidth: 520,
                    minimumHeight: 96,
                    retry: retry
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: 520, minHeight: 96, maxHeight: 140)
                    .background(imageBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Loading image preview")
            }
        }
        .task(id: loadID) {
            failureReason = nil
            let wasCached = IRCImagePreviewCache.shared.cachedResource(for: url) != nil
            do {
                let loadedResource = try await IRCImagePreviewCache.shared.resource(for: url)
                guard !Task.isCancelled else { return }
                resource = loadedResource
                if !wasCached {
                    onLoad()
                }
            } catch {
                guard !Task.isCancelled else { return }
                failureReason = IRCPreviewFailureReason(error: error)
            }
        }
        .sheet(isPresented: $isShowingViewer) {
            if let displayedResource {
                IRCImageViewer(url: url, resource: displayedResource)
            }
        }
    }

    private var loadID: String {
        "\(url.absoluteString)#\(retryCount)"
    }

    private var displayedResource: IRCLoadedImage? {
        resource ?? IRCImagePreviewCache.shared.cachedResource(for: url)
    }

    private func retry() {
        failureReason = nil
        retryCount += 1
    }

    private func loadedPreview(for image: NSImage) -> some View {
        Button {
            isShowingViewer = true
        } label: {
            IRCBoundedImageLayout(aspectRatio: Self.aspectRatio(for: image)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .background(imageBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(imageBorder, lineWidth: 1)
        }
        .help("View larger image")
        .accessibilityLabel("Image preview from \(url.host(percentEncoded: true) ?? "web link")")
        .accessibilityHint("Opens a larger image viewer")
    }

    private var imageBackground: Color {
        themePalette?.panel ?? Color(nsColor: .controlBackgroundColor)
    }

    private var imageBorder: Color {
        themePalette?.border.opacity(0.7) ?? Color(nsColor: .separatorColor)
    }

    private static func aspectRatio(for image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }
}

private struct IRCPreviewFailureView: View {
    let reason: IRCPreviewFailureReason
    let maximumWidth: CGFloat
    let minimumHeight: CGFloat
    let retry: () -> Void

    @Environment(\.ircThemePalette) private var themePalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview unavailable")
                    .font(.system(size: 12, weight: .semibold))
                Text(reason.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: maximumWidth, minHeight: minimumHeight, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
        .accessibilityLabel("Preview unavailable. \(reason.message)")
    }

    private var cardBackground: Color {
        themePalette?.panel ?? Color(nsColor: .controlBackgroundColor)
    }

    private var cardBorder: Color {
        themePalette?.border.opacity(0.7) ?? Color(nsColor: .separatorColor)
    }
}

private struct IRCImageViewer: View {
    let url: URL
    let resource: IRCLoadedImage
    private let modalSize: CGSize

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.ircThemePalette) private var themePalette
    @State private var saveError: String?

    init(url: URL, resource: IRCLoadedImage) {
        self.url = url
        self.resource = resource
        let visibleScreenSize = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.size ??
            IRCImageViewerSizingPolicy.compactModalSize
        modalSize = IRCImageViewerSizingPolicy.preferredModalSize(
            imagePixelSize: resource.sourcePixelSize,
            screenVisibleSize: visibleScreenSize
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            enlargedImage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(viewerBackground)
                .accessibilityLabel("Enlarged image from \(url.host(percentEncoded: true) ?? "web link")")

            Divider()

            HStack(spacing: 12) {
                Text(IRCImageSavePolicy.suggestedFilename(
                    for: resource.resolvedURL,
                    mimeType: resource.mimeType
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer()

                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }

                Button {
                    saveImage()
                } label: {
                    Label("Save Image…", systemImage: "square.and.arrow.down")
                }

                Button {
                    copyImageAndClose()
                } label: {
                    Label("Copy and Close", systemImage: "doc.on.doc")
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: modalSize.width, height: modalSize.height)
        .alert(
            "Couldn’t Save Image",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "The image could not be saved.")
        }
    }

    @ViewBuilder
    private var enlargedImage: some View {
        if IRCEnlargedImagePolicy.shouldAnimate(
            mimeType: resource.mimeType,
            frameCount: resource.sourceFrameCount
        ) {
            IRCAnimatedGIFView(
                data: resource.sourceData,
                fallbackImage: resource.image
            )
        } else {
            Image(nsImage: resource.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private var viewerBackground: Color {
        themePalette?.background ?? Color(nsColor: .windowBackgroundColor)
    }

    private func copyImageAndClose() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([resource.image])
        dismiss()
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = IRCImageSavePolicy.suggestedFilename(
            for: resource.resolvedURL,
            mimeType: resource.mimeType
        )
        if let contentType = IRCImageSavePolicy.contentType(for: resource.mimeType) {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            try resource.sourceData.write(to: destinationURL, options: .atomic)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

enum IRCEnlargedImagePolicy {
    nonisolated static func shouldAnimate(mimeType: String, frameCount: Int) -> Bool {
        mimeType.lowercased() == "image/gif" && frameCount > 1
    }
}

private struct IRCAnimatedGIFView: NSViewRepresentable {
    let data: Data
    let fallbackImage: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.image = NSImage(data: data) ?? fallbackImage
        imageView.animates = true
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.animates = true
    }
}

enum IRCImageViewerSizingPolicy {
    nonisolated static let compactModalSize = CGSize(width: 900, height: 700)
    private nonisolated static let screenCoverage: CGFloat = 0.75
    private nonisolated static let minimumResolutionCoverage: CGFloat = 0.75
    private nonisolated static let imageAreaInsets = CGSize(width: 48, height: 112)

    nonisolated static func preferredModalSize(
        imagePixelSize: CGSize,
        screenVisibleSize: CGSize
    ) -> CGSize {
        guard screenVisibleSize.width.isFinite,
              screenVisibleSize.height.isFinite,
              screenVisibleSize.width > 0,
              screenVisibleSize.height > 0 else { return compactModalSize }

        let expandedSize = CGSize(
            width: floor(screenVisibleSize.width * screenCoverage),
            height: floor(screenVisibleSize.height * screenCoverage)
        )
        let compactSize = CGSize(
            width: min(compactModalSize.width, expandedSize.width),
            height: min(compactModalSize.height, expandedSize.height)
        )
        let availableImageSize = CGSize(
            width: max(0, expandedSize.width - imageAreaInsets.width),
            height: max(0, expandedSize.height - imageAreaInsets.height)
        )
        guard imagePixelSize.width.isFinite,
              imagePixelSize.height.isFinite,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0,
              availableImageSize.width > 0,
              availableImageSize.height > 0 else { return compactSize }

        let displayedImageSize = IRCBoundedImageLayout.fittedSize(
            aspectRatio: imagePixelSize.width / imagePixelSize.height,
            within: availableImageSize
        )
        guard displayedImageSize.width > 0,
              displayedImageSize.height > 0,
              imagePixelSize.width >= displayedImageSize.width * minimumResolutionCoverage,
              imagePixelSize.height >= displayedImageSize.height * minimumResolutionCoverage else {
            return compactSize
        }
        return expandedSize
    }
}

enum IRCImageSavePolicy {
    nonisolated static func contentType(for mimeType: String) -> UTType? {
        guard let type = UTType(mimeType: mimeType), type.conforms(to: .image) else {
            return nil
        }
        return type
    }

    nonisolated static func suggestedFilename(for url: URL, mimeType: String) -> String {
        let contentType = contentType(for: mimeType)
        let preferredExtension = contentType?.preferredFilenameExtension
        var filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty || filename == "/" || filename == "." || filename == ".." {
            filename = "image"
        }

        let invalidCharacters = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/:")
        )
        filename = String(filename.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        })

        let existingExtension = (filename as NSString).pathExtension
        if let preferredExtension,
           existingExtension.isEmpty {
            filename += ".\(preferredExtension)"
        }

        let maximumLength = 180
        if filename.count > maximumLength {
            let pathExtension = (filename as NSString).pathExtension
            let extensionSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
            if extensionSuffix.count < maximumLength {
                let stemLimit = maximumLength - extensionSuffix.count
                let stem = (filename as NSString).deletingPathExtension
                filename = String(stem.prefix(stemLimit)) + extensionSuffix
            } else {
                filename = String(filename.prefix(maximumLength))
            }
        }
        return filename
    }
}

struct IRCBoundedImageLayout: Layout {
    let aspectRatio: CGFloat
    var maximumSize = CGSize(width: 520, height: 280)

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        Self.fittedSize(
            aspectRatio: aspectRatio,
            proposal: proposal,
            maximumSize: maximumSize
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(bounds.size)
        )
    }

    static func fittedSize(aspectRatio: CGFloat, within availableSize: CGSize) -> CGSize {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              availableSize.width.isFinite,
              availableSize.height.isFinite,
              availableSize.width > 0,
              availableSize.height > 0 else { return .zero }

        let availableAspectRatio = availableSize.width / availableSize.height
        if aspectRatio > availableAspectRatio {
            return CGSize(
                width: availableSize.width,
                height: availableSize.width / aspectRatio
            )
        }
        return CGSize(
            width: availableSize.height * aspectRatio,
            height: availableSize.height
        )
    }

    static func fittedSize(
        aspectRatio: CGFloat,
        proposal: ProposedViewSize,
        maximumSize: CGSize = CGSize(width: 520, height: 280)
    ) -> CGSize {
        // An automatic-height table can propose the row's current height while
        // remeasuring an asynchronously loaded image. That height belongs to
        // the loading placeholder; accepting it creates a feedback loop that
        // leaves the image thumbnail-sized until the row is reconstructed.
        // Width is a real parent constraint, but preview height is intrinsic.
        let availableSize = CGSize(
            width: min(max(proposal.width ?? maximumSize.width, 0), maximumSize.width),
            height: maximumSize.height
        )
        return fittedSize(aspectRatio: aspectRatio, within: availableSize)
    }
}
