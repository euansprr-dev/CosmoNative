// CosmoOS/SwipeFile/SwipeProcessingService.swift
// Background processing service for auto-transcription + analysis of swipe files on capture
// February 2026 — March 2026 parallel batch support

import Foundation
import GRDB

// MARK: - Transcription Output

/// Data produced by Phase 1 (transcription) and consumed by Phase 2 (persist + analyze).
/// All types are Sendable so this can cross actor boundaries safely.
struct SwipeTranscriptionOutput: Sendable {
    let uuid: String
    let result: TranscriptionResult
    let carouselItems: [CarouselItem]?
    let mediaData: InstagramMediaData
    let sourceURL: URL
}

// MARK: - SwipeProcessingService

/// Singleton service that processes swipe files in the background after capture.
/// Handles transcription (video or carousel), Claude cleanup, analysis, and re-indexing.
///
/// Architecture:
/// - Phase 1 (transcription): Runs off MainActor via nonisolated methods for true parallelism
/// - Phase 2 (persist + analyze): Runs on MainActor for safe DB/NLP/classification access
@MainActor
final class SwipeProcessingService {
    static let shared = SwipeProcessingService()

    /// UUIDs currently being processed — prevents duplicate work
    private var inFlightUUIDs: Set<String> = []

    private init() {}

    nonisolated static func isLikelyCarouselPostURL(_ url: URL) -> Bool {
        InstagramMediaResolution.isInstagramPostURL(url)
    }

    nonisolated static func shouldUseThumbnailFallback(
        mediaData: InstagramMediaData,
        sourceURL: URL,
        existingCarouselItems: [CarouselItem]? = nil
    ) -> Bool {
        InstagramMediaResolution.shouldUseThumbnailFallback(
            mediaData: mediaData,
            sourceURL: sourceURL,
            existingCarouselItems: existingCarouselItems
        )
    }

    nonisolated static func shouldSkipExistingTranscript(
        sourceURL: URL?,
        transcriptStatus: String?,
        transcriptSlideCount: Int,
        carouselItemCount: Int?,
        expectedCarouselItemCount: Int?
    ) -> Bool {
        guard transcriptStatus == "available", transcriptSlideCount > 0 else {
            return false
        }

        guard let sourceURL, isLikelyCarouselPostURL(sourceURL) else {
            return true
        }

        if let expectedCarouselItemCount {
            return transcriptSlideCount >= expectedCarouselItemCount
        }

        if let carouselItemCount, carouselItemCount > 1 {
            return transcriptSlideCount >= carouselItemCount
        }

        return transcriptSlideCount > 1
    }

    // MARK: - Pending Swipe Scanner

    /// Scan for cloud-captured swipes that arrived while offline and process them.
    /// Safe to call multiple times — inFlightUUIDs prevents double-processing.
    func scanForPendingSwipes() {
        Task {
            let pendingUUIDs = await fetchPendingSwipeUUIDs()
            guard !pendingUUIDs.isEmpty else { return }
            print("SwipeProcessingService: Found \(pendingUUIDs.count) pending swipes from cloud sync")
            processBatch(uuids: pendingUUIDs)
        }
    }

    private nonisolated func fetchPendingSwipeUUIDs() async -> [String] {
        do {
            return try await CosmoDatabase.shared.asyncRead { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT uuid FROM atoms
                    WHERE type = 'research'
                    AND is_deleted = 0
                    AND metadata LIKE '%"isSwipeFile":true%'
                    AND metadata NOT LIKE '%"processingStatus":"complete"%'
                    AND metadata NOT LIKE '%"processingStatus":"error"%'
                    LIMIT 50
                    """)
                return rows.compactMap { $0["uuid"] as? String }
            }
        } catch {
            print("SwipeProcessingService: Failed to scan pending swipes: \(error)")
            return []
        }
    }

    /// Check if a swipe is currently being processed
    func isProcessing(uuid: String) -> Bool {
        inFlightUUIDs.contains(uuid)
    }

    // MARK: - Single-Post Entry Point

    /// Fire-and-forget background processing for a single swipe (clipboard capture path)
    func processSwipeInBackground(
        uuid: String,
        skipAutoAdaptation: Bool = false,
        forceExtractionRetry: Bool = false
    ) {
        guard !inFlightUUIDs.contains(uuid) else {
            print("SwipeProcessingService: Already processing \(uuid), skipping")
            return
        }
        inFlightUUIDs.insert(uuid)

        // Protect this atom from remote sync overwrites during long processing
        Task { @MainActor in
            await SyncEngine.shared.setExtendedFence(uuid: uuid)
        }

        Task.detached { [weak self] in
            if let output = await self?.transcribe(uuid: uuid, forceExtractionRetry: forceExtractionRetry) {
                await self?.persistAndAnalyze(output: output)

                // Auto-generate hook adaptations for each client profile
                if !skipAutoAdaptation {
                    if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                        await SwipeAdaptationEngine.shared.generateAdaptationsForSwipe(swipeAtom: atom)
                    }
                }
            }
            await MainActor.run { self?.inFlightUUIDs.remove(uuid) }
        }
    }

    // MARK: - Batch Entry Point

    /// Process multiple swipes concurrently with bounded parallelism (max 3).
    /// Each transcription runs in isolation off MainActor; persistence is serialized on MainActor.
    func processBatch(uuids: [String]) {
        let newUUIDs = uuids.filter { !inFlightUUIDs.contains($0) }
        guard !newUUIDs.isEmpty else { return }
        for uuid in newUUIDs { inFlightUUIDs.insert(uuid) }

        print("SwipeProcessingService: Starting batch of \(newUUIDs.count) transcriptions")

        Task.detached { [weak self] in
            let semaphore = AsyncSemaphore(value: 3)

            await withTaskGroup(of: Void.self) { group in
                for uuid in newUUIDs {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }

                        // Phase 1: Transcribe off MainActor (parallel)
                        if let output = await self?.transcribe(uuid: uuid) {
                            // Phase 2: Persist + analyze on MainActor (interleaved)
                            await self?.persistAndAnalyze(output: output)
                        }

                        await MainActor.run { self?.inFlightUUIDs.remove(uuid) }
                    }
                }
            }

            await MainActor.run {
                print("SwipeProcessingService: Batch complete")
            }
        }
    }

    // MARK: - Phase 1: Transcription (off MainActor)

    /// Runs transcription off MainActor for true parallelism.
    /// Hops to MainActor briefly for DB reads/writes and media cache lookups.
    private nonisolated func transcribe(
        uuid: String,
        forceExtractionRetry: Bool = false
    ) async -> SwipeTranscriptionOutput? {
        print("SwipeProcessingService: Starting transcription for \(uuid)")

        // Step 1: Fetch atom (brief MainActor hop)
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
            print("SwipeProcessingService: Could not fetch atom \(uuid)")
            return nil
        }

        // Step 2a: Bail if extraction has been retried too many times
        let retryCount = atom.swipeAnalysis?.extractionRetryCount ?? 0
        if retryCount >= 3 {
            if forceExtractionRetry {
                print("SwipeProcessingService: Forcing extraction retry for \(uuid) after \(retryCount) failed attempt(s)")
                var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
                sa.extractionRetryCount = 0
                atom = atom.withSwipeAnalysis(sa)
                _ = try? await AtomRepository.shared.update(atom)
            } else {
                print("SwipeProcessingService: Max extraction retries (\(retryCount)) reached for \(uuid)")
                atom.processingStatus = "extraction_failed"
                _ = try? await AtomRepository.shared.update(atom)
                return nil
            }
        }

        // Step 2b: Skip if already transcribed. A single-slide /p/ transcript is
        // suspicious unless metadata confirms the post is actually single-image.
        let sourceURL = atom.url.flatMap(URL.init(string:))
        let transcriptSlideCount = atom.swipeAnalysis?.transcriptSlides?.count ?? 0
        let carouselItemCount = atom.richContent?.instagramData?.carouselItems?.count
        let expectedCarouselItemCount = atom.richContent?.instagramData?.expectedCarouselItemCount
        if Self.shouldSkipExistingTranscript(
            sourceURL: sourceURL,
            transcriptStatus: atom.richContent?.transcriptStatus,
            transcriptSlideCount: transcriptSlideCount,
            carouselItemCount: carouselItemCount,
            expectedCarouselItemCount: expectedCarouselItemCount
        ) {
            print("SwipeProcessingService: Atom \(uuid) already has transcript + \(atom.swipeAnalysis?.transcriptSlides?.count ?? 0) slides, skipping")
            return nil
        }

        // Update status (brief MainActor hop)
        atom.processingStatus = "extracting"
        _ = try? await AtomRepository.shared.update(atom)

        // Step 3: Extract media
        guard let urlString = atom.url, let url = URL(string: urlString) else {
            print("SwipeProcessingService: No URL for atom \(uuid)")
            atom.processingStatus = "error"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        }

        var mediaData: InstagramMediaData
        do {
            mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
        } catch {
            print("SwipeProcessingService: Media extraction failed for \(uuid): \(error)")
            atom.processingStatus = "error"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        }

        // Retry once for likely carousel URLs that got incomplete extraction.
        // A 1-item result is treated as partial — Cobalt/GraphQL can return a
        // truncated picker when a scrape fails mid-response. Invalidate and let
        // the cache's best-carousel resolver (GraphQL sidecar) take a second pass.
        let isLikelyCarousel = Self.isLikelyCarouselPostURL(url)
        let currentItemCount = mediaData.carouselItems?.count ?? 0
        let looksPartial = currentItemCount <= 1 && mediaData.videoURL == nil
        if isLikelyCarousel && looksPartial {
            print("SwipeProcessingService: Likely carousel with \(currentItemCount) item(s), retrying for \(uuid)")
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { InstagramMediaCache.shared.invalidate(for: url) }
            if let retryData = try? await InstagramMediaCache.shared.getMedia(for: url) {
                let retryCount = retryData.carouselItems?.count ?? 0
                if retryCount > currentItemCount {
                    print("SwipeProcessingService: Retry improved — \(currentItemCount) -> \(retryCount) items for \(uuid)")
                    mediaData = retryData
                } else if retryCount >= 1 {
                    // Adopt retry result anyway — fresher CDN URLs are less likely to be expired.
                    mediaData = retryData
                }
            }
        }

        // Update status
        atom.processingStatus = "transcribing"
        _ = try? await AtomRepository.shared.update(atom)

        // Step 4: Branch by content type — transcription runs off MainActor
        var transcriptionResult: TranscriptionResult

        let carouselItems = mediaData.carouselItems
            ?? atom.richContent?.instagramData?.carouselItems

        if InstagramMediaResolution.isIncompletePostMedia(
            mediaData: mediaData,
            sourceURL: url,
            existingCarouselItems: carouselItems
        ) {
            print("SwipeProcessingService: Incomplete carousel extraction for \(uuid), refusing partial carousel/thumbnail fallback")
            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            sa.extractionRetryCount = (sa.extractionRetryCount ?? 0) + 1
            atom = atom.withSwipeAnalysis(sa)
            atom.processingStatus = "extraction_failed"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        } else if let items = carouselItems, !items.isEmpty {
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: items
            ) { progress in
                switch progress {
                case .recognizingText(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService [\(uuid.prefix(8))]: OCR \(Int(pct * 100))%")
                    }
                case .analyzingWithAI(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService [\(uuid.prefix(8))]: AI \(Int(pct * 100))%")
                    }
                default: break
                }
            }
        } else if let videoURL = mediaData.videoURL {
            let shortcode = await InstagramExtractor.shared.extractShortcode(from: url)
            let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL, shortcode: shortcode)
            let duration = mediaData.duration ?? 60

            transcriptionResult = await InstagramAutoTranscriber.shared.transcribe(
                videoURL: playableURL,
                duration: duration
            ) { progress in
                switch progress {
                case .extractingFrames(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService [\(uuid.prefix(8))]: Frames \(Int(pct * 100))%")
                    }
                default: break
                }
            }
        } else if let thumbnailURL = mediaData.thumbnailURL,
                  Self.shouldUseThumbnailFallback(
                    mediaData: mediaData,
                    sourceURL: url,
                    existingCarouselItems: carouselItems
                  ) {
            print("SwipeProcessingService: Image post, transcribing thumbnail for \(uuid)")
            let singleItem = CarouselItem(
                index: 0,
                mediaType: .image,
                mediaURL: thumbnailURL
            )
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: [singleItem]
            ) { progress in
                switch progress {
                case .recognizingText(let pct):
                    if Int(pct * 100) % 50 == 0 {
                        print("SwipeProcessingService [\(uuid.prefix(8))]: OCR \(Int(pct * 100))%")
                    }
                default: break
                }
            }

            let isVideoContent = mediaData.contentType == .reel || mediaData.contentType == .videoPost
            if isVideoContent {
                transcriptionResult.quality = .degraded
                let warning = "Video extraction failed; transcript was generated from a thumbnail only."
                if !transcriptionResult.warnings.contains(warning) {
                    transcriptionResult.warnings.append(warning)
                }
            }

            if isLikelyCarousel {
                transcriptionResult.quality = .degraded
                let warning = "Carousel extraction incomplete; only the first slide was transcribed."
                if !transcriptionResult.warnings.contains(warning) {
                    transcriptionResult.warnings.append(warning)
                }
            }
        } else if isLikelyCarousel {
            print("SwipeProcessingService: Incomplete carousel extraction for \(uuid), refusing thumbnail fallback")
            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            sa.extractionRetryCount = (sa.extractionRetryCount ?? 0) + 1
            atom = atom.withSwipeAnalysis(sa)
            atom.processingStatus = "extraction_failed"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        } else {
            print("SwipeProcessingService: No transcribable content for \(uuid)")
            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            sa.extractionRetryCount = (sa.extractionRetryCount ?? 0) + 1
            atom = atom.withSwipeAnalysis(sa)
            atom.processingStatus = "extraction_failed"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        }

        // Step 5: Skip if transcription returned nothing
        guard transcriptionResult.contentType != .empty,
              !transcriptionResult.slides.isEmpty else {
            print("SwipeProcessingService: Transcription returned empty for \(uuid)")
            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            sa.extractionRetryCount = (sa.extractionRetryCount ?? 0) + 1
            atom = atom.withSwipeAnalysis(sa)
            atom.processingStatus = "extraction_failed"
            _ = try? await AtomRepository.shared.update(atom)
            return nil
        }

        return SwipeTranscriptionOutput(
            uuid: uuid,
            result: transcriptionResult,
            carouselItems: carouselItems,
            mediaData: mediaData,
            sourceURL: url
        )
    }

    // MARK: - Phase 2: Persist + Analyze (on MainActor)

    /// Persists transcription results and runs NLP/classification analysis.
    /// Must run on MainActor for safe access to AtomRepository, SwipeAnalyzer, etc.
    private func persistAndAnalyze(output: SwipeTranscriptionOutput) async {
        let uuid = output.uuid
        let transcriptionResult = output.result
        let carouselItems = output.carouselItems
        let url = output.sourceURL
        let mediaData = output.mediaData

        let finalSlides = transcriptionResult.cleanedSlides
        let rawSlides = transcriptionResult.rawSlides
        let speechSegments = transcriptionResult.speechSegments
        let transcriptionWarnings = transcriptionResult.warnings
        let transcriptionQuality = transcriptionResult.quality

        let combined = finalSlides
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        // Re-fetch atom to avoid overwriting concurrent changes
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
            print("SwipeProcessingService: Could not re-fetch atom \(uuid) for persist")
            return
        }

        // Check if user is actively editing this atom — skip body/title if so
        let userIsEditing = AtomRepository.shared.isBeingEdited(uuid)
        if userIsEditing {
            print("SwipeProcessingService: Atom \(uuid) is being edited, preserving user's body/title")
        }

        // Ensure sourceType + thumbnail are correct if carousel items were used
        if let items = carouselItems, !items.isEmpty {
            var rc = atom.richContent ?? ResearchRichContent()
            var needsUpdate = false

            if rc.sourceType != .instagramCarousel {
                rc.sourceType = .instagramCarousel
                rc.instagramType = "carousel"
                needsUpdate = true
            }

            let hasThumbnail = !(rc.thumbnailUrl ?? "").isEmpty
            if !hasThumbnail, let firstImage = items.first(where: { $0.mediaType == .image }) ?? items.first {
                rc.thumbnailUrl = firstImage.mediaURL.absoluteString
                atom.thumbnailUrl = firstImage.mediaURL.absoluteString
                needsUpdate = true
            }

            if needsUpdate {
                atom.setRichContent(rc)
            }
        }

        // Build in-memory atom with transcript (needed as analyzer input)
        atom.body = combined
        var richContent = atom.richContent ?? ResearchRichContent()
        richContent.transcript = combined
        richContent.transcriptStatus = "available"

        if let expectedCount = mediaData.expectedCarouselItemCount {
            var igData = richContent.instagramData ?? InstagramData(
                originalURL: url,
                contentType: mediaData.contentType
            )
            igData.expectedCarouselItemCount = expectedCount
            richContent.instagramData = igData
        }

        // Persist carousel items + sourceType + thumbnail if this was a carousel
        if let items = carouselItems, !items.isEmpty {
            var igData = richContent.instagramData ?? InstagramData(
                originalURL: url,
                contentType: .carousel
            )
            if igData.expectedCarouselItemCount != mediaData.expectedCarouselItemCount {
                igData.expectedCarouselItemCount = mediaData.expectedCarouselItemCount
            }
            let existingCarouselCount = igData.carouselItems?.count ?? 0
            let existingSignature = (igData.carouselItems ?? []).map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            let incomingSignature = items.map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            if existingCarouselCount < items.count ||
                igData.carouselItems?.isEmpty == true ||
                existingSignature != incomingSignature {
                igData.carouselItems = items
            }
            richContent.instagramData = igData
            richContent.sourceType = .instagramCarousel
            richContent.instagramType = "carousel"

            if (richContent.thumbnailUrl ?? "").isEmpty,
               let firstImage = items.first(where: { $0.mediaType == .image }) ?? items.first {
                richContent.thumbnailUrl = firstImage.mediaURL.absoluteString
                atom.thumbnailUrl = firstImage.mediaURL.absoluteString
            }
        }

        // Set hook/title from first slide (skip if user is editing AND has a real title)
        let hasPlaceholderTitle = ["Instagram Post", "Instagram Reel", "Instagram", "YouTube Video", "X Post", "Threads Post", "Saved Content", "Saved Text"].contains(atom.title ?? "")
        if (!userIsEditing || hasPlaceholderTitle),
           let firstText = finalSlides.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
            let hook = firstText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            atom.hook = String(hook.prefix(500))
            atom.title = String(hook.prefix(120))
            richContent.title = String(hook.prefix(120))
        }

        atom.setRichContent(richContent)

        // Save slides into swipeAnalysis
        var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
        sa.transcriptSlides = finalSlides
        sa.rawTranscriptSlides = rawSlides
        sa.transcriptSpeechSegments = speechSegments
        sa.transcriptionQuality = transcriptionQuality
        sa.transcriptionWarnings = transcriptionWarnings
        atom = atom.withSwipeAnalysis(sa)

        atom.processingStatus = "analyzing"

        // Run NLP analysis (in-memory only — no DB write yet)
        print("SwipeProcessingService: Running analysis for \(uuid)")
        var nlpResult = await SwipeAnalyzer.shared.analyze(atom: atom)
        nlpResult.transcriptSlides = finalSlides
        nlpResult.rawTranscriptSlides = rawSlides
        nlpResult.transcriptSpeechSegments = speechSegments
        nlpResult.transcriptionQuality = transcriptionQuality
        nlpResult.transcriptionWarnings = transcriptionWarnings
        atom = atom.withSwipeAnalysis(nlpResult)

        // Deep analysis via Claude (in-memory only — no DB write yet)
        let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(
            atom: atom,
            model: SwipeClassificationEngine.autoIngestModel
        )
        if classifiedResult.isFullyAnalyzed {
            var enriched = SwipeClassificationEngine.shared.mergeClassification(classifiedResult, into: nlpResult)
            enriched.transcriptSlides = finalSlides
            enriched.rawTranscriptSlides = rawSlides
            enriched.transcriptSpeechSegments = speechSegments
            enriched.transcriptionQuality = transcriptionQuality
            enriched.transcriptionWarnings = transcriptionWarnings
            atom = atom.withSwipeAnalysis(enriched)
        }

        // Re-index embedding with transcript text
        var textToEmbed = ""
        if let hook = atom.hook { textToEmbed += hook + " " }
        textToEmbed += combined
        if !textToEmbed.isEmpty {
            try? await VectorDatabase.shared.index(
                text: String(textToEmbed.prefix(2000)),
                entityType: "research",
                entityId: atom.id ?? 0,
                entityUUID: atom.uuid
            )
        }

        // SINGLE WRITE: Persist all accumulated changes (transcript + NLP + classification + status) at once.
        // On version conflict (common for cloud-captured swipes where sync bumps the version during
        // processing), re-fetch the latest version and re-apply analysis results.
        atom.processingStatus = "complete"
        do {
            _ = try await AtomRepository.shared.update(atom)
        } catch let error as AtomRepositoryError where error.isVersionConflict {
            print("SwipeProcessingService: Version conflict for \(uuid), retrying with latest version")
            if var latest = try? await AtomRepository.shared.fetch(uuid: uuid) {
                // Merge analysis results onto the latest version
                latest.body = atom.body
                latest.title = atom.title
                latest.hook = atom.hook
                latest.processingStatus = "complete"
                latest.setRichContent(atom.richContent ?? ResearchRichContent())
                if let sa = atom.swipeAnalysis {
                    latest = latest.withSwipeAnalysis(sa)
                }
                do {
                    _ = try await AtomRepository.shared.update(latest)
                    print("SwipeProcessingService: Retry succeeded for \(uuid)")
                } catch {
                    print("SwipeProcessingService: Retry also failed for \(uuid): \(error)")
                }
            }
        } catch {
            print("SwipeProcessingService: Failed to persist final analysis: \(error)")
        }

        // Cache carousel thumbnail locally (CDN URLs expire)
        if let items = carouselItems, !items.isEmpty {
            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)
            await SwipeFileEngine.cacheCarouselThumbnail(items: items, shortcode: shortcode)
        }

        // Update canvas block metadata with analysis results (hookType, hookScore)
        // so the block on the canvas reflects the completed analysis
        var blockMetadataUpdate: [String: String] = [:]
        if let hookType = atom.swipeAnalysis?.hookType?.rawValue {
            blockMetadataUpdate["hookType"] = hookType
        }
        if let hookScore = atom.swipeAnalysis?.hookScore {
            blockMetadataUpdate["hookScore"] = String(format: "%.1f", hookScore)
        }
        if let hook = atom.hook {
            blockMetadataUpdate["hook"] = hook
        }
        if !blockMetadataUpdate.isEmpty {
            // Find the canvas block for this atom and update its metadata
            NotificationCenter.default.post(
                name: .updateBlockMetadata,
                object: nil,
                userInfo: [
                    "entityUuid": uuid,
                    "metadata": blockMetadataUpdate
                ]
            )
        }

        // Notify gallery to reload — the atom now has complete analysis data
        // (hookType, framework, emotional arc, etc.) replacing the "Pending" state
        NotificationCenter.default.post(name: .researchCreated, object: nil)

        print("SwipeProcessingService: Processing complete for \(uuid) — \(finalSlides.count) slides")
    }
}
