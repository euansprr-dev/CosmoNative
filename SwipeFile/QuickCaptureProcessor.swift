// CosmoOS/SwipeFile/QuickCaptureProcessor.swift
// Unified quick capture processor for the command bar
// Detects URLs, classifies content, and creates research atoms

import Foundation
import AppKit
import Combine
import GRDB
import UserNotifications

/// Processes quick capture input from the command bar
/// Detects URLs, classifies content type, and creates research atoms
@MainActor
final class QuickCaptureProcessor: ObservableObject {
    static let shared = QuickCaptureProcessor()

    // MARK: - Published State
    @Published var isProcessing = false
    @Published var processingStatus: ProcessingStatus = .idle
    @Published var lastCreatedResearchUUID: String?

    enum ProcessingStatus: Equatable {
        case idle
        case detecting
        case processing(source: String)
        case complete(title: String)
        case error(String)
    }

    // MARK: - Dependencies
    private let classifier = SwipeURLClassifier()
    private let researchProcessor = ResearchProcessor.shared
    private let database = CosmoDatabase.shared

    private init() {}

    // MARK: - URL Detection

    /// Check if input looks like a URL that should be captured as research
    func isURL(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return classifier.isURL(trimmed)
    }

    // MARK: - Main Entry Point

    /// Process input from quick capture - returns true if it was a URL that was processed
    func processInput(_ input: String) async -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's a URL
        guard classifier.isURL(trimmed) else {
            return false // Not a URL, caller should handle as voice command
        }

        isProcessing = true
        processingStatus = .detecting

        // Classify the URL
        let classification = classifier.classify(trimmed)

        do {
            let research = try await processClassifiedURL(trimmed, classification: classification)

            lastCreatedResearchUUID = research.uuid
            processingStatus = .complete(title: research.title ?? "Research saved")

            // Show success notification
            await showSuccessNotification(for: research, classification: classification)

            // Reset status after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            processingStatus = .idle
            isProcessing = false

            return true

        } catch {
            print("QuickCapture: Failed to process URL: \(error)")
            processingStatus = .error(error.localizedDescription)

            // Reset status after delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            processingStatus = .idle
            isProcessing = false

            return true // Still consumed the URL, even if processing failed
        }
    }

    // MARK: - URL Processing

    private func processClassifiedURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        switch classification.sourceType {
        case .youtube, .youtubeShort:
            return try await processYouTubeURL(url, classification: classification)

        case .xPost, .twitter:
            return try await processXURL(url, classification: classification)

        case .instagramReel, .instagramPost, .instagramCarousel:
            return try await processInstagramURL(url, classification: classification)

        case .threads:
            return try await processThreadsURL(url, classification: classification)

        case .loom:
            return try await processLoomURL(url, classification: classification)

        case .website:
            return try await processWebsiteURL(url)

        default:
            // Treat as generic website
            return try await processWebsiteURL(url)
        }
    }

    // MARK: - YouTube Processing

    private func processYouTubeURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        processingStatus = .processing(source: "YouTube")

        // Use ResearchProcessor which handles full transcript fetching
        return try await researchProcessor.processURL(url)
    }

    // MARK: - X/Twitter Processing

    private func processXURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        processingStatus = .processing(source: "X")

        guard let tweetId = classification.contentId else {
            throw QuickCaptureError.invalidContent("Could not extract tweet ID")
        }

        // Create research via ResearchProcessor
        return try await researchProcessor.processURL(url)
    }

    // MARK: - Instagram Processing

    private func processInstagramURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        let sourceName: String
        switch classification.sourceType {
        case .instagramReel: sourceName = "Instagram Reel"
        case .instagramCarousel: sourceName = "Instagram Carousel"
        default: sourceName = "Instagram"
        }
        processingStatus = .processing(source: sourceName)

        // For Instagram, we create a research atom and try to extract content
        // Instagram blocks programmatic access, so we save the URL and attempt extraction

        let igType: ResearchRichContent.InstagramContentType
        switch classification.sourceType {
        case .instagramReel: igType = .reel
        case .instagramCarousel: igType = .carousel
        default: igType = .post
        }

        // Same URL captured before? Surface the existing swipe — never a duplicate.
        if let existing = await Self.findExistingLiveSwipe(url: url) {
            print("QuickCapture: URL already swiped — returning existing \(existing.uuid.prefix(8))")
            return existing
        }

        // V2: capture is instant — save a pending atom (with an instantly
        // resolved thumbnail) and kick the Railway worker, exactly like the
        // iPhone. The local extraction pipeline remains the fallback tier via
        // scanForPendingSwipes when the worker doesn't claim the swipe.
        return try await saveBasicInstagramResearch(url: url, contentId: classification.contentId, igType: igType)
    }

    /// Instagram serves the post thumbnail at /<p|reel>/<code>/media/?size=l as
    /// a bare 302 to the CDN JPEG — no auth, sub-second. Resolve WITHOUT
    /// following the redirect so we capture the CDN URL itself.
    nonisolated static func resolveInstantThumbnailURL(for url: String) async -> String? {
        guard let shortcode = SwipeURLClassifier().extractInstagramId(url) else { return nil }
        for kind in ["p", "reel"] {
            guard let mediaURL = URL(string: "https://www.instagram.com/\(kind)/\(shortcode)/media/?size=l") else { continue }
            var request = URLRequest(url: mediaURL)
            request.timeoutInterval = 3
            let session = URLSession(configuration: .ephemeral, delegate: RedirectCatcher.shared, delegateQueue: nil)
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse,
               (300...399).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               location.hasPrefix("http"), !location.contains("/accounts/login") {
                return location
            }
        }
        return nil
    }

    /// URLSession delegate that refuses redirects so the Location header
    /// survives into the response.
    private final class RedirectCatcher: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = RedirectCatcher()
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// Normalize a swipe URL for dedup: host lowercased, tracking params and
    /// trailing slash dropped, /reels/ folded into /reel/.
    nonisolated static func normalizedSwipeURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return raw
        }
        components.query = nil
        components.fragment = nil
        components.host = components.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        var path = components.path.replacingOccurrences(of: "/reels/", with: "/reel/")
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        components.path = path
        return components.string ?? raw
    }

    /// Find a live (non-deleted) swipe already saved for this URL.
    nonisolated static func findExistingLiveSwipe(url: String) async -> Research? {
        let normalized = normalizedSwipeURL(url)
        let shortcode = SwipeURLClassifier().extractInstagramId(url)
        let rows = try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(Column("metadata").like("%\"isSwipeFile\":true%"))
                .order(Column("created_at").desc)
                .limit(400)
                .fetchAll(db)
        }
        return rows?.first { atom in
            guard let existingURL = atom.researchMetadata?.url else { return false }
            if normalizedSwipeURL(existingURL) == normalized { return true }
            if let shortcode, existingURL.contains("/\(shortcode)") { return true }
            return false
        }
    }

    private func saveInstagramResearch(url: String, mediaData: InstagramMediaData, igType: ResearchRichContent.InstagramContentType) async throws -> Research {
        var research = Research.new(
            title: mediaData.caption?.prefix(100).description ?? "Instagram \(igType.rawValue.capitalized)",
            query: nil,
            url: url,
            sourceType: igType == .reel ? .instagramReel : (igType == .carousel ? .instagramCarousel : .instagramPost)
        )

        research.processingStatus = "complete"

        var richContent = research.richContent ?? ResearchRichContent()
        richContent.sourceType = igType == .reel ? .instagramReel : (igType == .carousel ? .instagramCarousel : .instagramPost)
        richContent.author = mediaData.authorUsername
        richContent.thumbnailUrl = mediaData.thumbnailURL?.absoluteString
        richContent.instagramId = extractInstagramId(from: url)
        richContent.instagramType = igType.rawValue

        // Store Instagram-specific data
        var igData = richContent.instagramData ?? InstagramData(
            originalURL: URL(string: url)!,
            contentType: mapToInstagramContentType(igType)
        )
        igData.authorUsername = mediaData.authorUsername
        igData.caption = mediaData.caption
        igData.extractedMediaURL = mediaData.videoURL
        igData.extractedAt = Date()
        igData.expectedCarouselItemCount = mediaData.expectedCarouselItemCount

        if let items = mediaData.carouselItems {
            igData.carouselItems = items
            let cachedSlideCount = await InstagramCarouselImageCache.cacheCarouselImages(
                items: items,
                shortcode: richContent.instagramId
            )
            if cachedSlideCount > 0 {
                print("QuickCapture: Cached \(cachedSlideCount) carousel media images for \(richContent.instagramId ?? "unknown")")
            }
        }

        richContent.instagramData = igData
        research.setRichContent(richContent)

        return try await saveResearch(research)
    }

    private func saveBasicInstagramResearch(url: String, contentId: String?, igType: ResearchRichContent.InstagramContentType) async throws -> Research {
        var research = Research.new(
            title: "Instagram \(igType.rawValue.capitalized)",
            query: nil,
            url: url,
            sourceType: igType == .reel ? .instagramReel : (igType == .carousel ? .instagramCarousel : .instagramPost)
        )

        research.processingStatus = "pending" // the cloud worker (or scan fallback) takes it from here

        var richContent = research.richContent ?? ResearchRichContent()
        richContent.sourceType = igType == .reel ? .instagramReel : (igType == .carousel ? .instagramCarousel : .instagramPost)
        richContent.instagramId = contentId
        richContent.instagramType = igType.rawValue

        // Instant thumbnail: the grid shows an image the moment the card lands.
        if let cdnThumbnail = await Self.resolveInstantThumbnailURL(for: url) {
            richContent.thumbnailUrl = cdnThumbnail
            research.thumbnailUrl = cdnThumbnail
        }

        // Initialize Instagram data for later extraction
        let igData = InstagramData(
            originalURL: URL(string: url)!,
            contentType: mapToInstagramContentType(igType)
        )
        richContent.instagramData = igData
        research.setRichContent(richContent)

        let saved = try await saveResearch(research)
        CloudSwipeAPI.kickProcessing(swipeUUID: saved.uuid)
        return saved
    }

    private func mapToInstagramContentType(_ igType: ResearchRichContent.InstagramContentType) -> InstagramContentType {
        switch igType {
        case .reel: return .reel
        case .carousel: return .carousel
        case .post: return .image
        case .story: return .story
        }
    }

    private func extractInstagramId(from url: String) -> String? {
        return classifier.extractInstagramId(url)
    }

    // MARK: - Threads Processing

    private func processThreadsURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        processingStatus = .processing(source: "Threads")

        // Threads has no public API, save URL only
        var research = Research.new(
            title: "Threads Post",
            query: nil,
            url: url,
            sourceType: .threads
        )

        research.processingStatus = "pending"

        var richContent = research.richContent ?? ResearchRichContent()
        richContent.sourceType = .threads
        richContent.threadsId = classification.contentId
        research.setRichContent(richContent)

        return try await saveResearch(research)
    }

    // MARK: - Loom Processing

    private func processLoomURL(_ url: String, classification: SwipeURLClassifier.Classification) async throws -> Research {
        processingStatus = .processing(source: "Loom")

        // Use ResearchProcessor for Loom handling
        return try await researchProcessor.processURL(url)
    }

    // MARK: - Website Processing

    private func processWebsiteURL(_ url: String) async throws -> Research {
        processingStatus = .processing(source: "Website")

        // Use ResearchProcessor which handles screenshots
        return try await researchProcessor.processURL(url)
    }

    // MARK: - Database Operations

    private func saveResearch(_ research: Research) async throws -> Research {
        var mutableResearch = research
        mutableResearch.updatedAt = ISO8601.string(from: Date())
        mutableResearch.createdAt = ISO8601.string(from: Date())

        let researchToSave = mutableResearch
        let uuid = research.uuid

        try await database.asyncWrite { db in
            try researchToSave.insert(db)
        }

        // Re-fetch to get the ID
        let inserted = try await database.asyncRead { db -> Research? in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
                .map { ResearchWrapper(atom: $0) }
        } ?? mutableResearch

        // Index for semantic search
        Task {
            await generateEmbedding(for: inserted)
        }

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .researchCreated,
            object: nil,
            userInfo: ["research": inserted, "uuid": inserted.uuid]
        )

        return inserted
    }

    private func generateEmbedding(for research: Research) async {
        // Recall index: the drain re-reads the atom, so this is just an enqueue.
        await RecallIndexer.shared.noteAtomChanged(uuid: research.uuid)
    }

    // MARK: - Notifications

    private func showSuccessNotification(for research: Research, classification: SwipeURLClassifier.Classification) async {
        let content = UNMutableNotificationContent()
        content.title = "Captured Research"
        content.body = research.title ?? classification.sourceType.displayName
        content.sound = .default
        content.categoryIdentifier = SwipeFileEngine.captureNotificationCategory
        content.userInfo = ["atomUUID": research.uuid]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("QuickCapture: Failed to show notification: \(error)")
        }
    }
}

// MARK: - Quick Capture Error

enum QuickCaptureError: LocalizedError {
    case invalidContent(String)
    case extractionFailed(String)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidContent(let msg): return "Invalid content: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .saveFailed: return "Failed to save research"
        }
    }
}

// MARK: - Quick Capture Notification

extension Notification.Name {
    /// Posted when quick capture creates a new research atom
    static let quickCaptureComplete = Notification.Name("quickCaptureComplete")
}

// MARK: - Cloud Swipe API (Railway worker)

/// Thin client for the Railway swipe worker (SWIPE_V2_PLAN.md). Both calls
/// are fire-and-forget from capture paths — the worker's 15s cron catches
/// anything a failed kick misses.
enum CloudSwipeAPI {
    static var baseURL: String {
        let configured = APIKeys.discoveryApiBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = configured.isEmpty ? "https://cosmonative-production.up.railway.app" : configured
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    /// Start processing a freshly captured swipe immediately (skip the cron wait).
    static func kickProcessing(swipeUUID: String) {
        post(path: "/api/swipes/process", swipeUUID: swipeUUID)
    }

    /// Awaitable kick for user-initiated retries: the caller needs to know
    /// whether the worker accepted before deciding to fall back to the local
    /// pipeline. POST /process bypasses fetchCandidates, so it also revives
    /// swipes the worker retired (needs_manual_retry).
    @discardableResult
    static func kickProcessingAwaiting(swipeUUID: String) async -> Bool {
        await postAwaiting(path: "/api/swipes/process", swipeUUID: swipeUUID)
    }

    /// Re-fetch engagement stats for a swipe. Await-able: callers refresh UI after.
    @discardableResult
    static func refreshStats(swipeUUID: String) async -> Bool {
        await postAwaiting(path: "/api/swipes/refresh-stats", swipeUUID: swipeUUID)
    }

    private static func post(path: String, swipeUUID: String) {
        Task.detached(priority: .utility) {
            _ = await postAwaiting(path: path, swipeUUID: swipeUUID)
        }
    }

    private static func postAwaiting(path: String, swipeUUID: String) async -> Bool {
        guard let url = URL(string: baseURL + path),
              let key = APIKeys.supabaseServiceRoleKey, !key.isEmpty else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["swipeUUID": swipeUUID])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
