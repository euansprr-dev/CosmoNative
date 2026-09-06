// CosmoOS/Core/Components/ImageSave/ImageSaveKit.swift
// The one contract behind every "save this image" affordance: a surface hands
// over WHERE the original bytes live, the resolver turns that into typed data
// with an honest filename, and a platform saver writes it. Twin of
// CosmoiOS/Sources/Shared/ImageSave/ImageSaveKit.swift — keep the grammar
// (sources, naming rules, sniffing) in lockstep.

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where an image's ORIGINAL bytes live. Surfaces describe the source; they
/// never re-encode a decoded bitmap when a file exists — a save should hand
/// back exactly what was captured (same format, same pixels, same EXIF).
enum ImageSaveSource {
    /// A file on disk (ImageStore, MediaAssetStore, attachment originals).
    case file(URL)
    /// Bytes already in hand (type is sniffed from the data).
    case data(Data)
    /// A remote original — fetched with the project's auth when it's
    /// Supabase-hosted, with the browser headers Instagram's CDN expects
    /// otherwise.
    case remote(URL)
    /// A rich-document image: the device-local file when present, else the
    /// cross-device mirror.
    case reference(RichImageReference)
    /// A captured page / screenshot: the full-resolution original.
    case attachment(MediaAttachment)
    /// Anything else — the surface resolves its own payload.
    case custom(@MainActor () async -> ImageSavePayload?)
}

/// A save request: the source plus the human context that names the file
/// when the stored name is a UUID ("How I grew to 100k.jpg", not
/// "7F3A….jpg").
struct ImageSaveRequest {
    var source: ImageSaveSource
    var title: String?

    init(_ source: ImageSaveSource, title: String? = nil) {
        self.source = source
        self.title = title
    }
}

/// Resolved, typed bytes ready to write anywhere.
struct ImageSavePayload: Sendable {
    let data: Data
    let type: UTType
    /// Filename without extension.
    let stem: String

    var filename: String {
        "\(stem).\(type.preferredFilenameExtension ?? "png")"
    }
}

/// Source → payload. Main-actor because every source store in the app
/// (ImageStore, AttachmentCloudStore, Supabase client) is reached from there;
/// the byte work itself hops off.
@MainActor
enum ImageSaveResolver {

    static func resolve(_ request: ImageSaveRequest) async -> ImageSavePayload? {
        switch request.source {
        case .file(let url):
            return await payload(fromFile: url, title: request.title)

        case .data(let data):
            return payload(from: data, preferredStem: nil, title: request.title)

        case .remote(let url):
            return await payload(fromRemote: url, title: request.title)

        case .reference(let reference):
            if !reference.path.isEmpty,
               FileManager.default.fileExists(atPath: reference.path) {
                return await payload(fromFile: URL(fileURLWithPath: reference.path), title: request.title)
            }
            if let remote = reference.remoteURL, let url = URL(string: remote) {
                return await payload(fromRemote: url, title: request.title)
            }
            return nil

        case .attachment(let attachment):
            guard let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment) else { return nil }
            return await payload(fromFile: url, title: request.title)

        case .custom(let resolver):
            return await resolver()
        }
    }

    // MARK: - Sources

    private static func payload(fromFile url: URL, title: String?) async -> ImageSavePayload? {
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        guard let data, !data.isEmpty else { return nil }
        return payload(from: data, preferredStem: url.deletingPathExtension().lastPathComponent, title: title)
    }

    private static func payload(fromRemote url: URL, title: String?) async -> ImageSavePayload? {
        let request: URLRequest
        if let client = SupabaseClient.shared, client.isSupabaseHostedURL(url) {
            request = client.authorizedRequest(for: url)
        } else {
            request = InstagramCarouselImageCache.request(for: url)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
              !data.isEmpty else { return nil }
        return payload(from: data, preferredStem: url.deletingPathExtension().lastPathComponent, title: title)
    }

    private static func payload(from data: Data, preferredStem: String?, title: String?) -> ImageSavePayload? {
        guard let type = ImageSaveNaming.imageType(of: data) else { return nil }
        return ImageSavePayload(
            data: data,
            type: type,
            stem: ImageSaveNaming.stem(preferred: preferredStem, title: title)
        )
    }
}

/// Filename + type rules shared by both platforms (pure, testable).
enum ImageSaveNaming {

    /// The image's real type, read from the bytes — never from an extension
    /// a store happened to pick. Nil when the data isn't an image at all.
    static func imageType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image) else { return nil }
        return type
    }

    /// A stored name wins when it means something to a person; UUIDs, cache
    /// keys and CDN digit-soup fall through to the surface's title, and then
    /// to the Screenshot-style date stamp.
    static func stem(preferred: String?, title: String?, now: Date = Date()) -> String {
        if let preferred, isMeaningful(preferred) { return sanitized(preferred) }
        if let title {
            let clean = sanitized(title)
            if !clean.isEmpty { return clean }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cosmo Image \(formatter.string(from: now))"
    }

    static func isMeaningful(_ stem: String) -> Bool {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        if UUID(uuidString: trimmed) != nil { return false }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("thumb-") || lowered.hasPrefix("ig-img-") { return false }
        // Digit / hex soup (CDN object names, cache digests): no letters at
        // all, or a long run of hex characters only.
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.isEmpty { return false }
        let hexOnly = trimmed.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF-_").contains($0) }
        if hexOnly && trimmed.count >= 12 { return false }
        return true
    }

    /// Finder-safe: no path separators or colons, collapsed whitespace, capped.
    static func sanitized(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let collapsed = replaced.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String(trimmed.prefix(80))
    }

    /// Safari's convention for a name that's already taken: "Image-1.png",
    /// "Image-2.png" — never Finder's "copy".
    static func uniqueFilename(_ filename: String, taken: (String) -> Bool) -> String {
        guard taken(filename) else { return filename }
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            if !taken(candidate) { return candidate }
            counter += 1
        }
    }
}
