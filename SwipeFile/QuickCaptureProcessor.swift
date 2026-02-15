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

        // Try Instagram extraction (may work for public content)
        do {
            let mediaData = try await InstagramExtractor.shared.extract(from: URL(string: url)!)
            return try await saveInstagramResearch(url: url, mediaData: mediaData, igType: igType)
        } catch {
            // Extraction failed - save URL with basic metadata for manual review
            print("QuickCapture: Instagram extraction failed: \(error)")
            return try await saveBasicInstagramResearch(url: url, contentId: classification.contentId, igType: igType)
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

        if let items = mediaData.carouselItems {
            igData.carouselItems = items
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

        research.processingStatus = "pending" // Mark for manual review

        var richContent = research.richContent ?? ResearchRichContent()
        richContent.sourceType = igType == .reel ? .instagramReel : (igType == .carousel ? .instagramCarousel : .instagramPost)
        richContent.instagramId = contentId
        richContent.instagramType = igType.rawValue

        // Initialize Instagram data for later extraction
        var igData = InstagramData(
            originalURL: URL(string: url)!,
            contentType: mapToInstagramContentType(igType)
        )
        richContent.instagramData = igData
        research.setRichContent(richContent)

        return try await saveResearch(research)
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
        mutableResearch.updatedAt = ISO8601DateFormatter().string(from: Date())
        mutableResearch.createdAt = ISO8601DateFormatter().string(from: Date())

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
        var textToEmbed = ""
        if let title = research.title {
            textToEmbed += title + " "
        }
        if let summary = research.summary {
            textToEmbed += summary
        }

        guard !textToEmbed.isEmpty else { return }

        do {
            try await VectorDatabase.shared.index(
                text: textToEmbed,
                entityType: "research",
                entityId: research.id ?? 0,
                entityUUID: research.uuid
            )
        } catch {
            print("QuickCapture: Failed to generate embedding: \(error)")
        }
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
