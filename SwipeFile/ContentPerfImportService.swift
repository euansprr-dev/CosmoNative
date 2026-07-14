// CosmoOS/SwipeFile/ContentPerfImportService.swift
// The swipe pipeline pointed at your own posts: paste a live post URL and
// the performance sheet fills itself — real numbers via Apify, and the
// transcript pulled through the same transcriber the swipe file uses, so
// the system learns what the winning post actually said. Instagram first
// (the swipe file's home turf); YouTube can ride the InnerTube transcript
// service later.
// July 2026

import Foundation

// MARK: - Imported Performance

struct ImportedPostPerf: Sendable, Equatable {
    var platform: SocialPlatform
    var views: Int
    var likes: Int
    var comments: Int
    var shares: Int?
    var caption: String?
    var videoURL: URL?
    var duration: TimeInterval?

    init(platform: SocialPlatform, post: ImportedPost) {
        self.platform = platform
        self.views = post.engagement.viewsCount ?? 0
        self.likes = post.engagement.likesCount
        self.comments = post.engagement.commentsCount
        self.shares = post.engagement.sharesCount
        self.caption = post.caption
        self.videoURL = post.videoUrl
        self.duration = nil
    }
}

enum ContentPerfImportError: LocalizedError {
    case unsupportedPlatform
    case apifyUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Only Instagram URLs can be pulled automatically for now — enter the numbers by hand for other platforms."
        case .apifyUnavailable:
            return "No Apify key configured — add one in Settings to pull posts automatically."
        }
    }
}

// MARK: - Service

enum ContentPerfImportService {
    /// Which platform a post URL belongs to — nil means we can't auto-pull it.
    static func detectPlatform(from url: URL) -> SocialPlatform? {
        guard let host = url.host()?.lowercased() else { return nil }
        if host.contains("instagram.com") { return .instagram }
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        return nil
    }

    /// Fetch a published post's real numbers. Instagram-only for now.
    static func fetchPerf(url: URL) async throws -> ImportedPostPerf {
        guard detectPlatform(from: url) == .instagram else {
            throw ContentPerfImportError.unsupportedPlatform
        }
        guard APIKeys.hasApify else {
            throw ContentPerfImportError.apifyUnavailable
        }
        let post = try await ApifyInstagramProvider.shared.fetchPost(url: url)
        return ImportedPostPerf(platform: .instagram, post: post)
    }

    /// Overlay for the transcript keys this service owns on a content atom.
    /// Key-merged — sibling metadata (drafts, phase, schedule) survives.
    struct TranscriptOverlay: Encodable {
        var publishedTranscript: String
        var publishedCaption: String?
    }

    /// Transcribe the live post's video and attach the text to the content
    /// atom. Never-block contract: callers fire-and-forget; failures log.
    @MainActor
    static func transcribeAndAttach(
        contentUuid: String,
        videoURL: URL,
        caption: String?,
        duration: TimeInterval?
    ) async {
        let result = await InstagramAutoTranscriber.shared.transcribe(
            videoURL: videoURL,
            duration: duration ?? 60,
            progressHandler: { _ in }
        )
        let transcript = flattenedTranscript(result)
        guard !transcript.isEmpty else {
            print("[ContentPerfImport] transcription came back empty for \(contentUuid) — nothing attached")
            return
        }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: contentUuid) else { return }
        let updated = atom.mergingMetadataKeys(TranscriptOverlay(
            publishedTranscript: transcript,
            publishedCaption: caption?.isEmpty == false ? caption : nil
        ))
        _ = try? await AtomRepository.shared.update(updated)

        // The transcript changes what "top performing" knows — refresh the
        // owning client's dossier so the agent sees it immediately.
        await ClientPerfAggregator.recomputeForContent(updated)
        print("[ContentPerfImport] transcript attached to \(contentUuid) (\(transcript.count) chars)")
    }

    /// One readable text from transcription slides, in slide order.
    static func flattenedTranscript(_ result: TranscriptionResult) -> String {
        result.slides
            .sorted { $0.slideNumber < $1.slideNumber }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

// MARK: - Content Transcript Lens

/// Decode lens: reads only the published-transcript keys off a content atom.
struct ContentTranscriptLens: Codable, Sendable {
    var publishedTranscript: String?
    var publishedCaption: String?
}
