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

        // Register notification categories with "Open" action
        registerNotificationCategories()

        // Set up delegate for handling notification actions
        UNUserNotificationCenter.current().delegate = CaptureNotificationDelegate.shared
    }

    // MARK: - Main Entry Point: Clipboard Capture

    /// Capture content from the clipboard
    /// - Parameter asSwipe: If true, saves as swipe file. If false, saves as regular research.
    func captureFromClipboard(asSwipe: Bool = true) async {
        let captureType = asSwipe ? "swipe" : "research"
        print("📋 SwipeFileEngine.captureFromClipboard(asSwipe: \(asSwipe)) called!")

        guard !isProcessing else {
            print("SwipeFile: Already processing, ignoring capture request")
            return
        }

        isProcessing = true
        processingStatus = .reading

        // Read clipboard
        guard let clipboardContent = readClipboard() else {
            await showCaptureNotification(
                title: "Cosmo",
                body: "Nothing in clipboard to capture",
                atomUUID: nil,
                isError: true
            )
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
        await processClassifiedContent(clipboardContent, classification: classification, asSwipe: asSwipe)

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

    private func processClassifiedContent(_ content: String, classification: SwipeURLClassifier.Classification, asSwipe: Bool = true) async {
        switch classification.sourceType {
        case .instagramReel, .instagramPost, .instagramCarousel:
            // Instagram requires manual entry - show modal
            await handleInstagramContent(content, classification: classification)

        case .youtube, .youtubeShort:
            // YouTube - auto-fetch transcript
            await handleYouTubeContent(content, classification: classification, asSwipe: asSwipe)

        case .xPost, .twitter:
            // X/Twitter - auto-fetch embed
            await handleXContent(content, classification: classification, asSwipe: asSwipe)

        case .threads:
            // Threads - similar to X
            await handleThreadsContent(content, classification: classification, asSwipe: asSwipe)

        case .rawNote:
            // Raw text - direct save
            await handleRawTextContent(content, asSwipe: asSwipe)

        default:
            // Website or unknown URL
            await handleWebsiteContent(content, classification: classification, asSwipe: asSwipe)
        }
    }

    // MARK: - Instagram Handling (Instant Save + Deferred Transcription)

    private func handleInstagramContent(_ url: String, classification: SwipeURLClassifier.Classification) async {
        // Determine Instagram content type
        let igType: ResearchRichContent.InstagramContentType
        let sourceType: ResearchRichContent.SourceType
        switch classification.sourceType {
        case .instagramReel:
            igType = .reel
            sourceType = .instagramReel
        case .instagramCarousel:
            igType = .carousel
            sourceType = .instagramCarousel
        default:
            igType = .post
            sourceType = .instagramPost
        }

        processingStatus = .fetching(source: "Instagram")

        // Create atom immediately — no modal blocking
        var item = Research.swipeFromInstagram(
            instagramId: classification.contentId ?? UUID().uuidString,
            url: url,
            hook: nil,
            type: igType
        )

        // Mark as needing manual transcription (Instagram has no auto-transcript API)
        item.processingStatus = "pending"

        var richContent = item.richContent ?? ResearchRichContent()
        richContent.sourceType = sourceType
        richContent.instagramType = igType.rawValue
        richContent.instagramId = classification.contentId
        item.setRichContent(richContent)

        // Attempt oEmbed metadata fetch (title, author) — non-fatal
        do {
            let oEmbedUrl = "https://api.instagram.com/oembed/?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
            if let oEmbedURL = URL(string: oEmbedUrl) {
                let (data, _) = try await URLSession.shared.data(from: oEmbedURL)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let title = json["title"] as? String, !title.isEmpty {
                        item.title = title
                        item.hook = String(title.prefix(200))
                    }
                    if let authorName = json["author_name"] as? String {
                        var richContent = item.richContent ?? ResearchRichContent()
                        richContent.author = authorName
                        item.setRichContent(richContent)
                    }
                    if let thumbnailUrl = json["thumbnail_url"] as? String {
                        item.thumbnailUrl = thumbnailUrl
                        var richContent = item.richContent ?? ResearchRichContent()
                        richContent.thumbnailUrl = thumbnailUrl
                        item.setRichContent(richContent)
                    }
                }
            }
        } catch {
            print("SwipeFile: Instagram oEmbed fetch failed (non-fatal): \(error)")
        }

        // Attempt direct media extraction up-front so Swipe Study opens with video + metadata ready.
        if let igURL = URL(string: url) {
            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: igURL)
                var richContent = item.richContent ?? ResearchRichContent()
                var igData = richContent.instagramData ?? InstagramData(
                    originalURL: igURL,
                    contentType: mapToInstagramContentType(igType)
                )

                if let author = mediaData.authorUsername, !author.isEmpty {
                    richContent.author = author
                    igData.authorUsername = author
                }
                if let caption = mediaData.caption, !caption.isEmpty {
                    igData.caption = caption
                    if (item.title ?? "").isEmpty || item.title == "Instagram" {
                        item.title = String(caption.prefix(100))
                    }
                }
                if let thumb = mediaData.thumbnailURL?.absoluteString, !thumb.isEmpty {
                    item.thumbnailUrl = thumb
                    richContent.thumbnailUrl = thumb
                }

                igData.extractedMediaURL = mediaData.videoURL
                igData.extractedAt = mediaData.extractedAt
                if let carouselItems = mediaData.carouselItems {
                    igData.carouselItems = carouselItems
                }

                richContent.instagramData = igData
                item.setRichContent(richContent)
            } catch {
                print("SwipeFile: Instagram media extraction failed at capture time: \(error)")
            }
        }

        // Save immediately — transcript will be entered later in SwipeStudyFocusModeView
        await saveItem(item, asSwipe: true)
    }

    private func mapToInstagramContentType(_ igType: ResearchRichContent.InstagramContentType) -> InstagramContentType {
        switch igType {
        case .reel: return .reel
        case .carousel: return .carousel
        case .post: return .image
        case .story: return .story
        }
    }

    /// Called from Instagram modal when user saves (legacy support)
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

        // Save to database (Instagram is always swipe)
        await saveItem(item, asSwipe: true)

        pendingInstagramItem = nil
        showInstagramModal = false
    }

    /// Called from Instagram modal when user cancels (legacy support)
    func cancelInstagramSave() {
        pendingInstagramItem = nil
        showInstagramModal = false
        processingStatus = .idle
    }

    // MARK: - YouTube Handling

    private func handleYouTubeContent(_ url: String, classification: SwipeURLClassifier.Classification, asSwipe: Bool = true) async {
        guard let videoId = classification.contentId else {
            await handleWebsiteContent(url, classification: classification, asSwipe: asSwipe)
            return
        }

        processingStatus = .fetching(source: "YouTube")

        var item = Research.swipeFromYouTube(
            videoId: videoId,
            url: url,
            hook: nil,
            isShort: classification.sourceType == .youtubeShort
        )

        // Pre-enrich with thumbnail and oEmbed metadata before transcript fetch
        let thumbnailUrl = "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
        item.thumbnailUrl = thumbnailUrl

        var richContent = item.richContent ?? ResearchRichContent()
        richContent.thumbnailUrl = thumbnailUrl

        // Fetch oEmbed metadata (title, author) — non-fatal if it fails
        do {
            let metadata = try await YouTubeProcessor.shared.fetchMetadata(videoId: videoId)
            item.title = metadata.title
            richContent.title = metadata.title
            richContent.author = metadata.channelName
        } catch {
            print("SwipeFile: oEmbed metadata fetch failed (non-fatal): \(error)")
        }

        item.setRichContent(richContent)

        // Try to fetch transcript
        do {
            let segments = await YouTubeProcessor.shared.fetchCaptions(videoId: videoId)
            guard let segments = segments, !segments.isEmpty else {
                throw SwipeFileError.transcriptUnavailable
            }

            let fullText = segments.map(\.text).joined(separator: " ")
            var updatedRichContent = item.richContent ?? richContent
            updatedRichContent.transcript = fullText
            updatedRichContent.transcriptStatus = "available"
            item.setRichContent(updatedRichContent)

            // Use first line of transcript as hook if we got one
            if let firstLine = fullText.components(separatedBy: .newlines).first {
                item.hook = String(firstLine.prefix(200))
            }

            item.summary = fullText.prefix(500).description
            item.body = segments.jsonString
            item.processingStatus = "complete"
        } catch {
            print("SwipeFile: Failed to fetch YouTube transcript: \(error)")
            item.processingStatus = "pending"
            // Pre-enriched data (title, thumbnail, author) survives
        }

        await saveItem(item, asSwipe: asSwipe)
    }

    // MARK: - X/Twitter Handling

    private func handleXContent(_ url: String, classification: SwipeURLClassifier.Classification, asSwipe: Bool = true) async {
        guard let tweetId = classification.contentId else {
            await handleWebsiteContent(url, classification: classification, asSwipe: asSwipe)
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

        await saveItem(item, asSwipe: asSwipe)
    }

    // MARK: - Threads Handling

    private func handleThreadsContent(_ url: String, classification: SwipeURLClassifier.Classification, asSwipe: Bool = true) async {
        processingStatus = .fetching(source: "Threads")

        var item = Research.swipeFromThreads(
            threadId: classification.contentId ?? UUID().uuidString,
            url: url,
            hook: nil
        )

        // Threads doesn't have a public embed API, save URL only
        item.title = "Threads Post"
        item.processingStatus = "pending"

        await saveItem(item, asSwipe: asSwipe)
    }

    // MARK: - Raw Text Handling

    private func handleRawTextContent(_ text: String, asSwipe: Bool = true) async {
        processingStatus = .saving

        // Extract potential hook from first sentence or line
        let hook = extractHook(from: text)
        let item = Research.swipeFromRawText(text: text, hook: hook)

        await saveItem(item, asSwipe: asSwipe)
    }

    // MARK: - Website Handling

    private func handleWebsiteContent(_ url: String, classification: SwipeURLClassifier.Classification, asSwipe: Bool = true) async {
        processingStatus = .fetching(source: "Website")

        var item = Research.newSwipeFile(
            url: url,
            hook: nil,
            sourceType: .website,
            contentSource: .clipboard
        )

        item.title = url
        item.processingStatus = "pending"

        await saveItem(item, asSwipe: asSwipe)
    }

    // MARK: - Database Operations

    private func saveItem(_ item: Research, asSwipe: Bool = true) async {
        processingStatus = .saving

        do {
            var mutableItem = item
            if asSwipe {
                mutableItem.isSwipeFile = true
            }
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

            // Show success notification with "Open" action
            let sourceType = item.richContent?.sourceType?.displayName ?? "Content"
            let captureLabel = asSwipe ? "Captured Swipe" : "Captured Research"
            await showCaptureNotification(
                title: captureLabel,
                body: item.hook ?? item.title ?? sourceType,
                atomUUID: mutableItem.uuid,
                isError: false
            )

            print("SwipeFile: Saved \(asSwipe ? "swipe" : "research") with ID: \(mutableItem.id ?? -1)")

            // Trigger semantic embedding in background
            Task {
                await generateEmbedding(for: mutableItem)
            }

            // Auto-link to matching ideas (IdeaForge integration)
            if asSwipe, let savedAtom = try? await AtomRepository.shared.fetch(uuid: mutableItem.uuid) {
                Task {
                    await IdeaInsightEngine.shared.findIdeasForSwipe(swipeAtom: savedAtom)
                }
            }

            // Post notification for UI updates
            NotificationCenter.default.post(
                name: .researchCreated,
                object: nil,
                userInfo: ["research": mutableItem, "uuid": mutableItem.uuid]
            )

        } catch {
            print("SwipeFile: Failed to save item: \(error)")
            processingStatus = .error(error.localizedDescription)
            await showCaptureNotification(
                title: "Cosmo",
                body: "Failed to save",
                atomUUID: nil,
                isError: true
            )
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

    /// Notification category identifier for capture notifications with "Open" action
    static let captureNotificationCategory = "cosmo_capture"

    /// Register notification categories with "Open" action button
    func registerNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "open_capture",
            title: "Open",
            options: [.foreground]
        )

        let captureCategory = UNNotificationCategory(
            identifier: Self.captureNotificationCategory,
            actions: [openAction],
            intentIdentifiers: []
        )

        // Merge with existing categories
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var categories = existing
            categories.insert(captureCategory)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    private func showCaptureNotification(title: String, body: String, atomUUID: String?, isError: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if !isError {
            content.sound = .default
            content.categoryIdentifier = Self.captureNotificationCategory

            // Store atom UUID so "Open" action can navigate to it
            if let uuid = atomUUID {
                content.userInfo = ["atomUUID": uuid]
            }
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

    /// Delete a swipe file and clean up all references app-wide
    func deleteSwipe(atomUUID: String) async throws {
        // 1. Look up the atom's row ID before soft-deleting (needed for vector cleanup)
        let entityId: Int64? = try await database.asyncRead { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM atoms WHERE uuid = ?", arguments: [atomUUID])
        }

        // 2. Soft-delete the atom in the database
        try await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE atoms SET is_deleted = 1, updated_at = ? WHERE uuid = ?",
                arguments: [ISO8601DateFormatter().string(from: Date()), atomUUID]
            )
        }

        // 3. Remove from canvas — soft-delete all canvas blocks referencing this entity UUID
        let removedBlockIds: [String] = try await database.asyncRead { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM canvas_blocks WHERE entity_uuid = ? AND is_deleted = 0
            """, arguments: [atomUUID])
        }

        if !removedBlockIds.isEmpty {
            try await database.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE canvas_blocks SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP WHERE entity_uuid = ?",
                    arguments: [atomUUID]
                )
            }

            // Notify canvas to refresh and remove the blocks from memory
            for blockId in removedBlockIds {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": blockId]
                )
            }
        }

        // 4. Remove vector embedding
        if let entityId = entityId {
            Task {
                try? await VectorDatabase.shared.deleteEntity(entityType: "research", entityId: entityId)
            }
        }

        // 5. Post notification for UI refresh (gallery, search results, etc.)
        NotificationCenter.default.post(
            name: Notification.Name("swipeDeleted"),
            object: nil,
            userInfo: ["uuid": atomUUID]
        )

        print("SwipeFile: Deleted swipe \(atomUUID) and cleaned up references")
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

// MARK: - SwipeFile Errors

enum SwipeFileError: LocalizedError {
    case transcriptUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriptUnavailable:
            return "Could not fetch transcript for this video"
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

// MARK: - Notification Delegate

/// Handles "Open" action from capture notifications
final class CaptureNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CaptureNotificationDelegate()

    /// Called when user taps the notification or an action button
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "open_capture", UNNotificationDefaultActionIdentifier:
            // User tapped "Open" or the notification itself — navigate to the atom
            if let uuid = userInfo["atomUUID"] as? String {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                        object: nil,
                        userInfo: ["atomUUID": uuid]
                    )
                }
            }

        default:
            break
        }

        completionHandler()
    }

    /// Allow notifications to show even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
