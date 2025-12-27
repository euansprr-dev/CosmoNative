// CosmoOS/Cosmo/ResearchProcessor.swift
// Unified research processor - coordinates all URL types
// YouTube, Websites, Twitter, PDFs -> Research entities with rich content

import Foundation
import AppKit
import GRDB

// MARK: - Research Processor
@MainActor
class ResearchProcessor: ObservableObject {
    static let shared = ResearchProcessor()

    @Published var isProcessing = false
    @Published var currentStep: ProcessingStep?
    @Published var progress: Double = 0

    private let database = CosmoDatabase.shared
    private let youtubeProcessor: YouTubeProcessor
    private let websiteCapture: WebsiteCapture

    private init() {
        self.youtubeProcessor = YouTubeProcessor.shared
        self.websiteCapture = WebsiteCapture.shared
    }

    // MARK: - Process URL
    /// Main entry point - detects URL type and processes accordingly
    @MainActor
    func processURL(_ urlString: String) async throws -> Research {
        guard let url = URL(string: urlString),
              let urlType = URLClassifier.classify(urlString) else {
            throw ProcessingError.invalidURL
        }

        return try await processURL(url, type: urlType)
    }

    /// Process URL with known type
    @MainActor
    func processURL(_ url: URL, type: URLType) async throws -> Research {
        // Backwards-compatible behavior: create a pending record immediately, then process into it.
        let pending = try await createPendingResearch(urlString: url.absoluteString, type: type)
        guard let id = pending.id else { throw ProcessingError.saveFailed }
        try await processURL(into: id, url: url, type: type)

        // Return the updated record
        if let updated = try? await database.asyncRead({ db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == id)
                .fetchOne(db)
                .map { ResearchWrapper(atom: $0) }
        }) {
            return updated
        }

        return pending
    }

    // MARK: - Pending + In-place Processing

    /// Inserts a Research row immediately so the UI can render it instantly.
    func createPendingResearch(urlString: String, type: URLType) async throws -> Research {
        guard let url = URL(string: urlString) else { throw ProcessingError.invalidURL }

        let titleHint = URLClassifier.suggestedTitle(from: url)

        var research = Research.new(
            title: titleHint,
            query: nil,
            url: url.absoluteString,
            sourceType: type.researchSourceType
        )

        // Mark processing started
        research.processingStatus = "processing"

        // Prime rich content (IDs, etc.)
        var rich = research.richContent ?? ResearchRichContent()
        rich.sourceType = type.researchSourceType

        switch type {
        case .youtube(let videoId):
            rich.videoId = videoId
            research.thumbnailUrl = URLClassifier.youtubeThumbnailURL(videoId: videoId, quality: .maxRes)?.absoluteString
        case .twitter(let tweetId):
            rich.tweetId = tweetId
        case .loom(let videoId):
            rich.loomId = videoId
            research.thumbnailUrl = URLClassifier.loomThumbnailURL(videoId: videoId)?.absoluteString
        default:
            break
        }

        research.setRichContent(rich)
        research.updatedAt = ISO8601DateFormatter().string(from: Date())
        research.createdAt = ISO8601DateFormatter().string(from: Date())

        // Capture as immutable for Sendable closure
        let researchToInsert = research
        let researchUUID = research.uuid
        try await database.asyncWrite { db in
            try researchToInsert.insert(db)
        }

        // Re-fetch to get the ID
        let inserted = try await database.asyncRead { db -> Research? in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("uuid") == researchUUID)
                .fetchOne(db)
                .map { ResearchWrapper(atom: $0) }
        } ?? researchToInsert

        NotificationCenter.default.post(
            name: .researchProcessingStarted,
            object: nil,
            userInfo: ["researchId": inserted.id ?? 0, "url": urlString, "type": type.displayName]
        )

        return inserted
    }

    /// Runs processing and updates an existing Research row in-place (no duplicates).
    func processURL(into researchId: Int64, url: URL, type: URLType) async throws {
        isProcessing = true
        progress = 0
        defer {
            isProcessing = false
            currentStep = nil
            progress = 1.0
        }

        postProgress(researchId: researchId, step: "Starting…", progress: 0.05)

        let processed: Research

        switch type {
        case .youtube(let videoId):
            processed = try await processYouTube(videoId: videoId, url: url, researchId: researchId)
        case .twitter(let tweetId):
            processed = try await processTwitter(tweetId: tweetId, url: url, researchId: researchId)
        case .loom(let videoId):
            processed = try await processLoom(videoId: videoId, url: url, researchId: researchId)
        case .pdf:
            processed = try await processPDF(url: url, researchId: researchId)
        case .website:
            processed = try await processWebsite(url: url, researchId: researchId)
        }

        // Index embeddings after final write.
        await SemanticSearchEngine.shared.indexResearch(processed)

        NotificationCenter.default.post(
            name: .researchProcessingComplete,
            object: nil,
            userInfo: ["research": processed, "title": processed.title ?? "Research"]
        )
    }

    // MARK: - YouTube Processing
    private func processYouTube(videoId: String, url: URL, researchId: Int64) async throws -> Research {
        currentStep = .youtube(.fetchingMetadata)

        let data = try await youtubeProcessor.process(videoId: videoId) { step in
            Task { @MainActor in
                self.currentStep = .youtube(step)
                self.progress = step.progress
                self.postProgress(researchId: researchId, step: step.description, progress: step.progress)
            }
        }

        // Update the existing row in-place
        let updated = try await database.asyncWrite { db -> Research in
            guard let atom = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
            else {
                throw ProcessingError.saveFailed
            }
            var research = ResearchWrapper(atom: atom)

            research.title = data.title
            research.url = url.absoluteString
            research.researchType = ResearchRichContent.SourceType.youtube.rawValue
            research.summary = data.summary
            research.thumbnailUrl = data.thumbnailURL?.absoluteString
            research.body = data.transcript.jsonString
            research.processingStatus = "complete"
            research.updatedAt = ISO8601DateFormatter().string(from: Date())
            research.localVersion += 1

            var richContent = research.richContent ?? ResearchRichContent()
            richContent.sourceType = .youtube
            richContent.videoId = videoId
            richContent.author = data.channelName
            richContent.duration = data.duration
            richContent.publishedAt = data.publishedAt
            richContent.formattedTranscript = data.formattedTranscript
            richContent.transcriptSections = data.transcriptSections
            research.setRichContent(richContent)

            try research.update(db)
            return research
        }

        print("✅ YouTube research updated: \(data.title)")
        return updated
    }

    // MARK: - Loom Processing
    private func processLoom(videoId: String, url: URL, researchId: Int64) async throws -> Research {
        postProgress(researchId: researchId, step: "Fetching Loom metadata...", progress: 0.2)

        // Loom provides an oEmbed API for metadata
        let oEmbedURL = URL(string: "https://www.loom.com/v1/oembed?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!

        var title = "Loom Recording"
        var author: String?
        var thumbnailUrl: String?
        var duration: Int?

        // Try to fetch oEmbed metadata
        do {
            var request = URLRequest(url: oEmbedURL)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                title = (json["title"] as? String) ?? title
                author = json["author_name"] as? String
                thumbnailUrl = json["thumbnail_url"] as? String
                duration = json["duration"] as? Int
            }
        } catch {
            print("⚠️ Could not fetch Loom oEmbed data: \(error.localizedDescription)")
            // Continue with basic metadata
        }

        postProgress(researchId: researchId, step: "Saving Loom research...", progress: 0.8)

        // Capture values for async context (Swift 6 concurrency)
        let capturedTitle = title
        let capturedAuthor = author
        let capturedThumbnailUrl = thumbnailUrl
        let capturedDuration = duration

        let updated = try await database.asyncWrite { db -> Research in
            guard let atom = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
            else {
                throw ProcessingError.saveFailed
            }
            var research = ResearchWrapper(atom: atom)

            research.title = capturedTitle
            research.url = url.absoluteString
            research.researchType = ResearchRichContent.SourceType.loom.rawValue
            research.thumbnailUrl = capturedThumbnailUrl ?? URLClassifier.loomThumbnailURL(videoId: videoId)?.absoluteString
            research.processingStatus = "complete"
            research.updatedAt = ISO8601DateFormatter().string(from: Date())
            research.localVersion += 1

            var richContent = research.richContent ?? ResearchRichContent()
            richContent.sourceType = .loom
            richContent.loomId = videoId
            richContent.author = capturedAuthor
            richContent.duration = capturedDuration
            research.setRichContent(richContent)

            try research.update(db)
            return research
        }

        print("✅ Loom research saved: \(title)")
        return updated
    }

    // MARK: - Website Processing
    private func processWebsite(url: URL, researchId: Int64) async throws -> Research {
        currentStep = .website(.capturingScreenshot)

        let data = try await websiteCapture.process(url: url) { step in
            Task { @MainActor in
                self.currentStep = .website(step)
                self.progress = step.progress
                self.postProgress(researchId: researchId, step: step.description, progress: step.progress)
            }
        }

        let updated = try await database.asyncWrite { db -> Research in
            guard let atom = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
            else {
                throw ProcessingError.saveFailed
            }
            var research = ResearchWrapper(atom: atom)

            research.title = data.title
            research.url = url.absoluteString
            research.researchType = ResearchRichContent.SourceType.website.rawValue
            research.summary = data.summary
            research.processingStatus = "complete"
            research.updatedAt = ISO8601DateFormatter().string(from: Date())
            research.localVersion += 1

            var richContent = research.richContent ?? ResearchRichContent()
            richContent.sourceType = .website
            if let screenshot = data.screenshot {
                let scaledImage = screenshot.scaled(toFit: CGSize(width: 800, height: 600))
                richContent.screenshotBase64 = scaledImage.base64String
            }
            research.setRichContent(richContent)

            try research.update(db)
            return research
        }

        print("✅ Website research updated: \(updated.title ?? "Untitled")")
        return updated
    }

    // MARK: - Twitter Processing
    private func processTwitter(tweetId: String, url: URL, researchId: Int64) async throws -> Research {
        currentStep = .twitter
        postProgress(researchId: researchId, step: "Processing tweet…", progress: 0.4)

        let updated = try await database.asyncWrite { db -> Research in
            guard let atom = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
            else {
                throw ProcessingError.saveFailed
            }
            var research = ResearchWrapper(atom: atom)

            research.title = (research.title ?? "").isEmpty ? "Tweet" : research.title
            research.url = url.absoluteString
            research.researchType = ResearchRichContent.SourceType.twitter.rawValue
            research.processingStatus = "complete"
            research.updatedAt = ISO8601DateFormatter().string(from: Date())
            research.localVersion += 1

            var richContent = research.richContent ?? ResearchRichContent()
            richContent.sourceType = .twitter
            richContent.tweetId = tweetId
            richContent.embedHtml = """
            <blockquote class="twitter-tweet">
                <a href="\(url.absoluteString)"></a>
            </blockquote>
            <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
            """
            research.setRichContent(richContent)

            try research.update(db)
            return research
        }

        postProgress(researchId: researchId, step: "Complete", progress: 1.0)
        print("✅ Twitter research updated: Tweet \(tweetId)")
        return updated
    }

    // MARK: - PDF Processing
    private func processPDF(url: URL, researchId: Int64) async throws -> Research {
        currentStep = .pdf
        postProgress(researchId: researchId, step: "Processing PDF…", progress: 0.4)

        // Extract title from URL
        let filename = (url.path as NSString).lastPathComponent
        let title = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let updated = try await database.asyncWrite { db -> Research in
            guard let atom = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("id") == researchId)
                .fetchOne(db)
            else {
                throw ProcessingError.saveFailed
            }
            var research = ResearchWrapper(atom: atom)

            research.title = title
            research.url = url.absoluteString
            research.researchType = ResearchRichContent.SourceType.pdf.rawValue
            research.processingStatus = "complete"
            research.updatedAt = ISO8601DateFormatter().string(from: Date())
            research.localVersion += 1

            var richContent = research.richContent ?? ResearchRichContent()
            richContent.sourceType = .pdf
            research.setRichContent(richContent)

            try research.update(db)
            return research
        }

        postProgress(researchId: researchId, step: "Complete", progress: 1.0)
        print("✅ PDF research updated: \(title)")
        return updated
    }

    // MARK: - Progress Notifications
    private func postProgress(researchId: Int64, step: String, progress: Double) {
        NotificationCenter.default.post(
            name: .researchProcessingProgress,
            object: nil,
            userInfo: [
                "researchId": researchId,
                "step": step,
                "progress": progress
            ]
        )
    }
}

// MARK: - Processing Steps
enum ProcessingStep {
    case youtube(YouTubeProcessingStep)
    case website(WebsiteProcessingStep)
    case twitter
    case pdf

    var description: String {
        switch self {
        case .youtube(let step): return step.description
        case .website(let step): return step.description
        case .twitter: return "Processing tweet..."
        case .pdf: return "Processing PDF..."
        }
    }

    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .website: return "globe"
        case .twitter: return "bubble.left.fill"
        case .pdf: return "doc.fill"
        }
    }
}

// MARK: - Errors
enum ProcessingError: LocalizedError {
    case invalidURL
    case processingFailed(String)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        case .saveFailed: return "Failed to save research"
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let researchCreated = Notification.Name("researchCreated")
    static let researchProcessingStarted = Notification.Name("researchProcessingStarted")
    static let researchProcessingComplete = Notification.Name("researchProcessingComplete")
    static let createResearchBlock = Notification.Name("createResearchBlock")
}
