//
//  MessagePreviews.swift
//  Netsplit
//

import AppKit
import Foundation
import SwiftUI

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
    static let maximumPreviewsPerMessage = 2
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
        return IRCMessageTextRenderer.webURLs(for: message)
            .compactMap { url -> IRCMessagePreview? in
                guard let networkURL = IRCRemotePreviewPolicy.normalizedNetworkURL(url),
                      seenResources.insert(networkURL).inserted else { return nil }
                if showsImagePreviews, imageExtensions.contains(url.pathExtension.lowercased()) {
                    return .image(url)
                }
                return showsLinkPreviews ? .link(url) : nil
            }
            .prefix(maximumPreviewsPerMessage)
            .map { $0 }
    }
}

struct MessagePreviewStack: View {
    let previews: [IRCMessagePreview]
    @State private var isExpanded = true

    var body: some View {
        if !previews.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    isExpanded.toggle()
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
                                IRCImagePreview(url: url)
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
}

struct IRCLinkPreviewMetadata: Equatable {
    let title: String?
    let summary: String?
    let resolvedURL: URL
}

enum IRCLinkPreviewMetadataParser {
    private static let maximumHTMLBytes = 512 * 1_024
    private static let maximumTitleCharacters = 200
    private static let maximumSummaryCharacters = 280

    static func fetch(url: URL) async throws -> IRCLinkPreviewMetadata {
        let response = try await IRCPreviewHTTPClient.shared.load(
            url: url,
            maximumBytes: maximumHTMLBytes,
            acceptHeader: "text/html, application/xhtml+xml;q=0.9",
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

    private final class Entry {
        let metadata: IRCLinkPreviewMetadata
        init(_ metadata: IRCLinkPreviewMetadata) { self.metadata = metadata }
    }

    private let cache = NSCache<NSURL, Entry>()
    private var inFlight: [URL: Task<IRCLinkPreviewMetadata, Error>] = [:]

    private init() {
        cache.countLimit = 200
    }

    func metadata(for url: URL) async throws -> IRCLinkPreviewMetadata {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        if let cached = cache.object(forKey: key as NSURL) { return cached.metadata }
        if let task = inFlight[key] { return try await task.value }

        let task = Task { try await IRCLinkPreviewMetadataParser.fetch(url: key) }
        inFlight[key] = task
        do {
            let metadata = try await task.value
            cache.setObject(Entry(metadata), forKey: key as NSURL)
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
    @State private var failed = false
    @Environment(\.openURL) private var openURL
    @Environment(\.ircThemePalette) private var themePalette

    var body: some View {
        Group {
            if let metadata {
                Button {
                    openURL(url)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayHost)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(metadata.title ?? displayURL)
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
                            Text(displayURL)
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
                .accessibilityLabel("Link preview: \(metadata.title ?? displayURL)")
            } else if !failed {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: Self.maximumWidth, minHeight: 72)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Loading link preview")
            }
        }
        .task(id: url) {
            do {
                let loadedMetadata = try await IRCLinkPreviewCache.shared.metadata(for: url)
                guard !Task.isCancelled else { return }
                metadata = loadedMetadata
            } catch {
                failed = true
            }
        }
    }

    private var displayHost: String {
        (url.host(percentEncoded: true) ?? "WEB LINK").uppercased()
    }

    private var displayURL: String {
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

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage, Error>] = [:]

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for url: URL) async throws -> NSImage {
        let key = IRCRemotePreviewPolicy.normalizedNetworkURL(url) ?? url
        if let cached = cache.object(forKey: key as NSURL) { return cached }
        if let task = inFlight[key] { return try await task.value }

        let task = Task { try await IRCBoundedImageLoader.load(url: key) }
        inFlight[key] = task
        do {
            let image = try await task.value
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key as NSURL, cost: cost)
            inFlight[key] = nil
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private struct IRCImagePreview: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false
    @Environment(\.openURL) private var openURL
    @Environment(\.ircThemePalette) private var themePalette

    var body: some View {
        Group {
            if let image {
                Button {
                    openURL(url)
                } label: {
                    IRCBoundedImageLayout(aspectRatio: imageAspectRatio) {
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
                .help("Open image in browser")
                .accessibilityLabel("Image preview from \(url.host(percentEncoded: true) ?? "web link")")
            } else if !failed {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: 520, minHeight: 96, maxHeight: 140)
                    .background(imageBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Loading image preview")
            }
        }
        .task(id: url) {
            do {
                let loadedImage = try await IRCImagePreviewCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                image = loadedImage
            } catch {
                failed = true
            }
        }
    }

    private var imageBackground: Color {
        themePalette?.panel ?? Color(nsColor: .controlBackgroundColor)
    }

    private var imageBorder: Color {
        themePalette?.border.opacity(0.7) ?? Color(nsColor: .separatorColor)
    }

    private var imageAspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
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
        let availableSize = CGSize(
            width: min(max(proposal.width ?? maximumSize.width, 0), maximumSize.width),
            height: min(max(proposal.height ?? maximumSize.height, 0), maximumSize.height)
        )
        return Self.fittedSize(aspectRatio: aspectRatio, within: availableSize)
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
}
