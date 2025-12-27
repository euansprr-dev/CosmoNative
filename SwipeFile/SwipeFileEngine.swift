// CosmoOS/SwipeFile/SwipeFileEngine.swift
// Main orchestrator for the Swipe File system
// Handles clipboard capture, URL classification, content fetching, and storage

import Foundation
import AppKit
import UserNotifications
import Combine
import GRDB

/// Main orchestrator for the Swipe File system
/// Handles global hotkey capture, URL classification, and content ingestion
@MainActor
final class SwipeFileEngine: ObservableObject {
    static let shared = SwipeFileEngine()

    // MARK: - Published State
    @Published var isProcessing = false
    @Published var lastSavedItem: Research?
    @Published var pendingInstagramItem: Research?
    @Published var showInstagramModal = false
    @Published var processingStatus: ProcessingStatus = .idle

    enum ProcessingStatus: Equatable {
        case idle
        case reading
        case classifying
        case fetching(source: String)
        case saving
        case complete
        case error(String)
    }

    // MARK: - Dependencies
    private let database: CosmoDatabase
    private let classifier: SwipeURLClassifier
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.database = CosmoDatabase.shared
        self.classifier = SwipeURLClassifier()
        setupNotifications()
    }

    // MARK: - Notification Setup
    private func setupNotifications() {
        // Request notification permission on init
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("SwipeFile: Notification permission error: \(error)")
            } else if granted {
                print("SwipeFile: Notification permission granted")
            }
        }
    }

    // MARK: - Main Entry Point: Clipboard Capture

    /// Called when Cmd+Shift+S is pressed
    /// Reads clipboard, classifies content, and initiates ingestion
    func captureFromClipboard() async {
        print("📋 SwipeFileEngine.captureFromClipboard() called!")

        guard !isProcessing else {
            print("SwipeFile: Already processing, ignoring capture request")
            return
        }

        isProcessing = true
        processingStatus = .reading

        // Read clipboard
        guard let clipboardContent = readClipboard() else {
            await showNotification(title: "Cosmo", body: "Nothing to save", isError: true)
            processingStatus = .idle
            isProcessing = false
            return
        }

        print("SwipeFile: Captured clipboard content: \(clipboardContent.prefix(100))...")

        // Classify the content
        processingStatus = .classifying
        let classification = classifier.classify(clipboardContent)

        print("SwipeFile: Classified as \(classification.sourceType.displayName)")

        // Handle based on classification
        await processClassifiedContent(clipboardContent, classification: classification)

        isProcessing = false
    }

    // MARK: - Clipboard Reading

    private func readClipboard() -> String? {
        let pasteboard = NSPasteboard.general

        // Try to get string content
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try URL
        if let url = pasteboard.string(forType: .URL) {
            return url
        }

        return nil
    }

    // MARK: - Content Processing

    private func processClassifiedContent(_ content: String, classification: SwipeURLClassifier.Classification) async {
        switch classification.sourceType {
        case .instagramReel, .instagramPost, .instagramCarousel:
            // Instagram requires manual entry - show modal
            await handleInstagramContent(content, classification: classification)

        case .youtube, .youtubeShort:
            // YouTube - auto-fetch transcript
            await handleYouTubeContent(content, classification: classification)

        case .xPost, .twitter:
            // X/Twitter - auto-fetch embed
            await handleXContent(content, classification: classification)

        case .threads:
            // Threads - similar to X
            await handleThreadsContent(content, classification: classification)

        case .rawNote:
            // Raw text - direct save
            await handleRawTextContent(content)

        default:
            // Website or unknown URL
            await handleWebsiteContent(content, classification: classification)
        }
    }

    // MARK: - Instagram Handling (Manual Entry Required)

    private func handleInstagramContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        // Determine Instagram content type
        let igType: ResearchRichContent.InstagramContentType
        switch classification.sourceType {
        case .instagramReel: igType = .reel
        case .instagramCarousel: igType = .carousel
        default: igType = .post
        }

        // Create pending item for modal
        let item = Research.swipeFromInstagram(
            instagramId: classification.contentId ?? UUID().uuidString,
            url: url,
            hook: nil,
            type: igType
        )

        // Show Instagram modal for manual entry
        pendingInstagramItem = item
        showInstagramModal = true
        processingStatus = .idle

        // Notification will be shown after modal completion
    }

    /// Called from Instagram modal when user saves
    func completeInstagramSave(hook: String, transcript: String?) async {
        guard var item = pendingInstagramItem else { return }

        processingStatus = .saving

        item.hook = hook
        item.title = hook

        if let transcript = transcript, !transcript.isEmpty {
            var richContent = item.richContent ?? ResearchRichContent()
            richContent.transcript = transcript
            item.setRichContent(richContent)
            item.summary = transcript.prefix(500).description
        }

        // Save to database
        await saveSwipeItem(item)

        pendingInstagramItem = nil
        showInstagramModal = false
    }

    /// Called from Instagram modal when user cancels
    func cancelInstagramSave() {
        pendingInstagramItem = nil
        showInstagramModal = false
        processingStatus = .idle
    }

    // MARK: - YouTube Handling

    private func handleYouTubeContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        guard let videoId = classification.contentId else {
            await handleWebsiteContent(url, classification: classification)
            return
        }

        processingStatus = .fetching(source: "YouTube")

        var item = Research.swipeFromYouTube(
            videoId: videoId,
            url: url,
            hook: nil,
            isShort: classification.sourceType == .youtubeShort
        )

        // Try to fetch transcript
        do {
            let transcriptResult = try await YouTubeTranscriptFetcher.shared.fetchTranscript(videoId: videoId)

            var richContent = item.richContent ?? ResearchRichContent()
            richContent.transcript = transcriptResult.fullText
            richContent.duration = transcriptResult.duration
            richContent.author = transcriptResult.author
            item.setRichContent(richContent)

            // Use first line of transcript as hook if we got one
            if let firstLine = transcriptResult.fullText.components(separatedBy: .newlines).first {
                item.hook = String(firstLine.prefix(200))
                item.title = item.hook ?? "YouTube Video"
            }

            item.summary = transcriptResult.fullText.prefix(500).description
            item.processingStatus = "complete"
        } catch {
            print("SwipeFile: Failed to fetch YouTube transcript: \(error)")
            item.processingStatus = "pending"
            // Still save without transcript
        }

        await saveSwipeItem(item)
    }

    // MARK: - X/Twitter Handling

    private func handleXContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        guard let tweetId = classification.contentId else {
            await handleWebsiteContent(url, classification: classification)
            return
        }

        processingStatus = .fetching(source: "X")

        var item = Research.swipeFromXPost(tweetId: tweetId, url: url, hook: nil)

        // Try to fetch embed/content
        do {
            let embedResult = try await XEmbedFetcher.shared.fetchEmbed(url: url)

            var richContent = item.richContent ?? ResearchRichContent()
            richContent.embedHtml = embedResult.html
            richContent.author = embedResult.authorName
            item.setRichContent(richContent)

            // Use tweet text as hook
            if let tweetText = embedResult.text {
                item.hook = String(tweetText.prefix(280))
                item.title = item.hook ?? "X Post"
                item.summary = tweetText
            }

            item.processingStatus = "complete"
        } catch {
            print("SwipeFile: Failed to fetch X embed: \(error)")
            item.processingStatus = "pending"
        }

        await saveSwipeItem(item)
    }

    // MARK: - Threads Handling

    private func handleThreadsContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        processingStatus = .fetching(source: "Threads")

        var item = Research.swipeFromThreads(
            threadId: classification.contentId ?? UUID().uuidString,
            url: url,
            hook: nil
        )

        // Threads doesn't have a public embed API, save URL only
        item.title = "Threads Post"
        item.processingStatus = "pending"

        await saveSwipeItem(item)
    }

    // MARK: - Raw Text Handling

    private func handleRawTextContent(_ text: String) async {
        processingStatus = .saving

        // Extract potential hook from first sentence or line
        let hook = extractHook(from: text)
        let item = Research.swipeFromRawText(text: text, hook: hook)

        await saveSwipeItem(item)
    }

    // MARK: - Website Handling

    private func handleWebsiteContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        processingStatus = .fetching(source: "Website")

        var item = Research.newSwipeFile(
            url: url,
            hook: nil,
            sourceType: .website,
            contentSource: .clipboard
        )

        item.title = url
        item.processingStatus = "pending"

        await saveSwipeItem(item)
    }

    // MARK: - Database Operations

    private func saveSwipeItem(_ item: Research) async {
        processingStatus = .saving

        do {
            var mutableItem = item
            mutableItem.isSwipeFile = true
            mutableItem.contentSource = SwipeContentSource.clipboard.rawValue
            mutableItem.updatedAt = ISO8601DateFormatter().string(from: Date())

            // Capture by value for async context
            let itemToSave = mutableItem
            try await database.asyncWrite { db in
                var dbItem = itemToSave
                try dbItem.insert(db)
                dbItem.id = db.lastInsertedRowID
            }

            lastSavedItem = mutableItem
            processingStatus = .complete

            // Show success notification
            let sourceType = item.richContent?.sourceType?.displayName ?? "Content"
            await showNotification(
                title: "Saved to Swipe File",
                body: item.hook ?? sourceType,
                isError: false
            )

            print("SwipeFile: Saved item with ID: \(mutableItem.id ?? -1)")

            // Trigger semantic embedding in background
            Task {
                await generateEmbedding(for: mutableItem)
            }

        } catch {
            print("SwipeFile: Failed to save item: \(error)")
            processingStatus = .error(error.localizedDescription)
            await showNotification(title: "Cosmo", body: "Failed to save", isError: true)
        }

        // Reset status after delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        processingStatus = .idle
    }

    // MARK: - Semantic Embedding

    private func generateEmbedding(for item: Research) async {
        // Combine hook + content for embedding
        var textToEmbed = ""
        if let hook = item.hook {
            textToEmbed += hook + " "
        }
        if let summary = item.summary {
            textToEmbed += summary
        }

        guard !textToEmbed.isEmpty else { return }

        // Use existing vector database for embedding
        // This integrates with the telepathic semantic layer
        do {
            try await VectorDatabase.shared.index(
                text: textToEmbed,
                entityType: "research",
                entityId: item.id ?? 0,
                entityUUID: item.uuid
            )
            print("SwipeFile: Generated embedding for item \(item.id ?? -1)")
        } catch {
            print("SwipeFile: Failed to generate embedding: \(error)")
        }
    }

    // MARK: - Hook Extraction

    private func extractHook(from text: String) -> String {
        // Try to extract first sentence or meaningful opening
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        if let firstLine = lines.first {
            // If first line is short enough, use it
            if firstLine.count <= 200 {
                return firstLine
            }

            // Otherwise, try to find first sentence
            let sentences = firstLine.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            if let firstSentence = sentences.first, !firstSentence.isEmpty {
                return String(firstSentence.prefix(200))
            }

            return String(firstLine.prefix(200))
        }

        return String(text.prefix(200))
    }

    // MARK: - macOS Notifications

    private func showNotification(title: String, body: String, isError: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if !isError {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("SwipeFile: Failed to show notification: \(error)")
        }
    }

    // MARK: - Query Methods

    /// Fetch all swipe file items
    func fetchSwipeFiles(
        filter: SwipeFileFilter = .init(),
        limit: Int = 50
    ) async throws -> [Research] {
        try await database.asyncRead { db in
            // Query research atoms, filter for swipe files in memory (isSwipeFile is in JSON metadata)
            let sortColumn = filter.sortBy == .recent ? Column("created_at").desc : Column("created_at").asc

            let researchAtoms = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .order(sortColumn)
                .fetchAll(db)
                .map { ResearchWrapper(atom: $0) }

            // Filter for swipe files and apply additional filters in memory
            var results = researchAtoms.filter { $0.isSwipeFile }

            if let sourceType = filter.sourceType {
                results = results.filter { $0.sourceType == sourceType }
            }

            if let emotion = filter.emotionTone {
                results = results.filter { $0.emotionTone == emotion.rawValue }
            }

            if let structure = filter.structureType {
                results = results.filter { $0.structureType == structure.rawValue }
            }

            return Array(results.prefix(limit))
        }
    }

    /// Search swipe files by text query
    func searchSwipeFiles(query: String, limit: Int = 20) async throws -> [Research] {
        try await database.asyncRead { db in
            let researchAtoms = try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(
                    Column("title").like("%\(query)%") ||
                    Column("body").like("%\(query)%")
                )
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { ResearchWrapper(atom: $0) }

            // Filter for swipe files in memory and search hook/summary
            let searchLower = query.lowercased()
            return Array(researchAtoms
                .filter { $0.isSwipeFile }
                .filter { item in
                    (item.title?.lowercased().contains(searchLower) ?? false) ||
                    (item.hook?.lowercased().contains(searchLower) ?? false) ||
                    (item.summary?.lowercased().contains(searchLower) ?? false)
                }
                .prefix(limit))
        }
    }
}

// MARK: - Filter Model

struct SwipeFileFilter {
    var sourceType: ResearchRichContent.SourceType?
    var emotionTone: SwipeEmotionTone?
    var structureType: SwipeStructureType?
    var sortBy: SortOption = .recent

    enum SortOption {
        case recent
        case oldest
    }
}
