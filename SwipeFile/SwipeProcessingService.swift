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
    /// Whether the cloud worker had ALREADY completed this swipe when the local
    /// pass started. If it hadn't, but has by persist time, the worker won the
    /// race — the local (poorer) result is discarded instead of overwriting it.
    let cloudCompleteAtStart: Bool
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

    /// Last time we force-retried a stale "partial"/"extraction_failed" swipe, keyed by
    /// UUID. Throttles re-attempts so a permanently-unresolvable post (e.g. deleted upstream,
    /// or a private account) can't be hammered on every launch / foreground / sync tick.
    /// In-memory only: a fresh launch is allowed exactly one retry per stale swipe, which is
    /// precisely the behavior we want — it self-heals the common "worked the next day" case.
    private var recentExtractionAttempts: [String: Date] = [:]

    /// Minimum gap between forced extraction retries of the same swipe (30 minutes).
    private static let extractionRetryThrottle: TimeInterval = 1800

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
            if expectedCarouselItemCount == 1, carouselItemCount != nil {
                return false
            }
            return transcriptSlideCount >= expectedCarouselItemCount
        }

        if let carouselItemCount, carouselItemCount > 1 {
            return transcriptSlideCount >= carouselItemCount
        }

        return transcriptSlideCount > 1
    }

    // MARK: - Pending Swipe Scanner

    /// A swipe awaiting processing, tagged with whether it represents a stale prior
    /// failure (`partial` / `extraction_failed`) that warrants a forced extraction retry,
    /// versus a fresh item that just needs its first normal pass.
    private struct PendingSwipeCandidate: Sendable {
        let uuid: String
        let needsForcedRetry: Bool
    }

    /// Scan for swipes that still need processing and route them appropriately.
    /// Safe to call multiple times — `inFlightUUIDs` prevents double-processing and the
    /// `recentExtractionAttempts` throttle prevents hammering unresolvable posts.
    ///
    /// Fresh items go through the bounded-parallelism batch path. Stale prior failures
    /// (`partial`/`extraction_failed`) get a throttled `forceExtractionRetry` so a swipe
    /// that failed once — e.g. a Telegram save that hit a transient Instagram rate limit —
    /// is automatically re-attempted later instead of staying permanently stuck.
    func scanForPendingSwipes() {
        Task {
            let candidates = await fetchPendingSwipeCandidates()
            guard !candidates.isEmpty else { return }

            let now = Date()
            // Drop throttle entries that have aged out so the map can't grow unbounded.
            recentExtractionAttempts = recentExtractionAttempts.filter {
                now.timeIntervalSince($0.value) < Self.extractionRetryThrottle
            }

            var freshUUIDs: [String] = []
            var retryUUIDs: [String] = []
            for candidate in candidates {
                guard candidate.needsForcedRetry else {
                    freshUUIDs.append(candidate.uuid)
                    continue
                }
                if let last = recentExtractionAttempts[candidate.uuid],
                   now.timeIntervalSince(last) < Self.extractionRetryThrottle {
                    continue  // attempted within the throttle window — skip this pass
                }
                recentExtractionAttempts[candidate.uuid] = now
                retryUUIDs.append(candidate.uuid)
            }

            if !freshUUIDs.isEmpty {
                print("SwipeProcessingService: Found \(freshUUIDs.count) pending swipes from cloud sync")
                processBatch(uuids: freshUUIDs)
            }
            for uuid in retryUUIDs {
                print("SwipeProcessingService: Re-attempting stale swipe \(uuid) with forced extraction retry")
                processSwipeInBackground(uuid: uuid, forceExtractionRetry: true)
            }
        }
    }

    private nonisolated func fetchPendingSwipeCandidates() async -> [PendingSwipeCandidate] {
        do {
            return try await CosmoDatabase.shared.asyncRead { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT uuid, metadata, updated_at FROM atoms
                    WHERE type = 'research'
                    AND is_deleted = 0
                    AND metadata LIKE '%"isSwipeFile":true%'
                    AND metadata NOT LIKE '%"processingStatus":"complete"%'
                    AND metadata NOT LIKE '%"processingStatus":"error"%'
                    LIMIT 50
                    """)
                return rows.compactMap { row in
                    guard let uuid = row["uuid"] as? String else { return nil }
                    let metadata = (row["metadata"] as? String) ?? ""
                    // Railway-first: the cloud worker owns instagram/youtube/
                    // twitter swipes. The Mac is strictly the fallback tier —
                    // it steps in only when the worker's claim went stale, its
                    // retry budget ran out, or it never showed up at all.
                    let updatedAt = (row["updated_at"] as? String).flatMap(ISO8601.date(from:))
                    if !Self.macMayProcess(metadataJSON: metadata, updatedAt: updatedAt) { return nil }
                    let needsForcedRetry =
                        metadata.contains("\"processingStatus\":\"partial\"") ||
                        metadata.contains("\"processingStatus\":\"extraction_failed\"")
                    return PendingSwipeCandidate(uuid: uuid, needsForcedRetry: needsForcedRetry)
                }
            }
        } catch {
            print("SwipeProcessingService: Failed to scan pending swipes: \(error)")
            return []
        }
    }

    /// A cloud claim is live when the worker stamped it within the last 15
    /// minutes and the swipe is mid-pipeline. Anything older is fair game.
    nonisolated static func hasLiveCloudClaim(metadataJSON: String) -> Bool {
        guard let data = metadataJSON.data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return hasLiveCloudClaim(meta: meta, now: Date())
    }

    private nonisolated static func hasLiveCloudClaim(meta: [String: Any], now: Date) -> Bool {
        guard meta["processingWorker"] as? String == "cloud" else { return false }
        let status = meta["processingStatus"] as? String ?? ""
        guard ["pending", "extracting", "transcribing", "analyzing"].contains(status) else { return false }
        guard let claimedStr = meta["processingClaimedAt"] as? String,
              let claimedAt = ISO8601.date(from: claimedStr) else {
            // Claimed but unparseable timestamp: treat pending as unclaimed,
            // in-flight statuses as live (conservative against double work).
            return status != "pending"
        }
        return now.timeIntervalSince(claimedAt) < 15 * 60
    }

    // MARK: - Railway-First Policy

    /// Grace the Railway worker gets to claim a fresh pending swipe before the
    /// Mac steps in. The worker ticks every 15 seconds and finishes a swipe in
    /// one to two minutes — minutes of silence means it is down or unreachable.
    nonisolated static let cloudPendingGrace: TimeInterval = 10 * 60
    /// Slack past the worker's own scheduled retry (`processingRetryAfter`)
    /// before the Mac concludes the worker missed its window and takes over.
    nonisolated static let cloudRetryGrace: TimeInterval = 5 * 60
    /// Mirror of the worker's MAX_CLOUD_RETRIES — at this count it has given up.
    nonisolated static let cloudMaxRetries = 5

    /// The Railway worker owns instagram / youtube / twitter swipes — the same
    /// scope check as `inWorkerScope` in cosmo-cloud-agent/src/swipes/types.ts.
    /// Everything else (websites, tiktok, …) is Mac-only. A matching
    /// contentSource alone qualifies — some swipes carry their URL only in
    /// structured.sourceUrl, which the worker reads but metadata doesn't have.
    nonisolated static func isCloudWorkerScoped(url: String?, contentSource: String?) -> Bool {
        let url = url ?? ""
        let source = (contentSource ?? "").lowercased()
        func urlMatches(_ pattern: String) -> Bool {
            url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if source.contains("instagram") || urlMatches(#"instagram\.com"#) { return true }
        if source.contains("youtube") || urlMatches(#"youtube\.com|youtu\.be"#) { return true }
        if source == "twitter" || urlMatches(#"twitter\.com|(^|/|\.)x\.com"#) { return true }
        return false
    }

    /// Railway-first: may the Mac process this swipe right now, or does the
    /// cloud worker still own it? The worker is the primary pipeline for its
    /// scope; the Mac is strictly the fallback tier and only steps in when the
    /// worker has demonstrably failed or gone quiet:
    ///   • in-flight claim gone stale (worker died mid-swipe)
    ///   • pending with no worker activity past the grace window (worker down)
    ///   • failed/partial with the worker's retry budget exhausted, or its
    ///     scheduled retry missed by more than the grace window
    nonisolated static func macMayProcess(
        metadataJSON: String?,
        updatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        guard isCloudWorkerScoped(
            url: meta["url"] as? String,
            contentSource: meta["contentSource"] as? String
        ) else {
            return true
        }

        let status = meta["processingStatus"] as? String ?? "pending"
        switch status {
        case "extracting", "transcribing", "analyzing":
            return !hasLiveCloudClaim(meta: meta, now: now)
        case "pending":
            guard let updatedAt else { return false }
            return now.timeIntervalSince(updatedAt) > cloudPendingGrace
        case "partial", "extraction_failed":
            let attempts = (meta["cloudRetryCount"] as? NSNumber)?.intValue ?? 0
            if attempts >= cloudMaxRetries { return true }
            if let retryStr = meta["processingRetryAfter"] as? String,
               let retryAt = ISO8601.date(from: retryStr) {
                return now.timeIntervalSince(retryAt) > cloudRetryGrace
            }
            // No cloud bookkeeping at all — the worker has never touched it.
            guard let updatedAt else { return false }
            return now.timeIntervalSince(updatedAt) > cloudPendingGrace
        default:
            // complete / error — nothing contended; existing skip logic decides.
            return true
        }
    }

    /// True when the cloud worker marked this swipe complete.
    nonisolated static func isCloudComplete(metadataJSON: String?) -> Bool {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return meta["processingWorker"] as? String == "cloud"
            && meta["processingStatus"] as? String == "complete"
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

        Task.detached { [weak self] in
            if let output = await self?.transcribe(uuid: uuid, forceExtractionRetry: forceExtractionRetry) {
                await self?.persistAndAnalyze(output: output)

                // Auto-generate hook adaptations for each client profile
                if !skipAutoAdaptation {
                    if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
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

        // Step 1a: Railway-first. Every entry point funnels through here
        // (scanner, realtime push, UI actions) — if the cloud worker still owns
        // this swipe, the Mac stays out of its way entirely: no status writes,
        // no racing transcription that would overwrite the worker's result.
        if !Self.macMayProcess(metadataJSON: atom.metadata, updatedAt: ISO8601.date(from: atom.updatedAt)) {
            print("SwipeProcessingService: \(uuid.prefix(8)) belongs to the cloud worker — deferring (Railway-first)")
            return nil
        }
        let cloudCompleteAtStart = Self.isCloudComplete(metadataJSON: atom.metadata)

        // Step 1b: A transcript the user edited by hand is terminal — background
        // transcription must never re-run over deliberate edits (including
        // carousels whose slide count the user reduced on purpose).
        if atom.swipeAnalysis?.transcriptEditedByUser == true {
            print("SwipeProcessingService: Transcript for \(uuid) was edited by the user — auto-transcription is terminal")
            if atom.processingStatus != "complete" {
                atom.processingStatus = "complete"
                _ = try? await AtomRepository.shared.update(atom)
            }
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

        // The local pass is definitely running from here — protect this atom
        // from remote sync overwrites during long processing. (Set only AFTER
        // the Railway-first gate: a fence on a deferred swipe would block the
        // cloud worker's own result from syncing down.)
        await SyncEngine.shared.setExtendedFence(uuid: uuid)

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

        let isIncompleteCarousel = InstagramMediaResolution.isIncompletePostMedia(
            mediaData: mediaData,
            sourceURL: url,
            existingCarouselItems: carouselItems
        )

        if let items = carouselItems, !items.isEmpty {
            // Transcribe whatever slides we have — even a partial carousel. Bricking a
            // partial (the old behavior) meant a rate-limited Telegram save could never
            // finish; instead we store a best-effort, degraded transcript now and keep
            // upgrading toward the full slide set in the background (see the "partial"
            // status set in persistAndAnalyze + the throttled re-scan in
            // scanForPendingSwipes). Never re-run a downgrade, though:
            let storedSlideCount = atom.swipeAnalysis?.transcriptSlides?
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count ?? 0
            if items.count < storedSlideCount {
                print("SwipeProcessingService: Live carousel (\(items.count)) is poorer than stored (\(storedSlideCount)) for \(uuid) — keeping stored transcript")
                let expected = mediaData.expectedCarouselItemCount
                    ?? atom.richContent?.instagramData?.expectedCarouselItemCount
                let stillIncomplete = expected.map { storedSlideCount < $0 } ?? false
                atom.processingStatus = stillIncomplete ? "partial" : "complete"
                _ = try? await AtomRepository.shared.update(atom)
                return nil
            }

            let shortcode = await InstagramExtractor.shared.extractShortcode(from: url)
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: items,
                shortcode: shortcode
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

            if isIncompleteCarousel {
                transcriptionResult.quality = .degraded
                let expectedDesc = mediaData.expectedCarouselItemCount.map(String.init) ?? "more"
                let warning = "Carousel extraction incomplete — transcribed \(items.count) of \(expectedDesc) slides. Will keep upgrading in the background."
                if !transcriptionResult.warnings.contains(warning) {
                    transcriptionResult.warnings.append(warning)
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
            let shortcode = await InstagramExtractor.shared.extractShortcode(from: url)
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: [singleItem],
                shortcode: shortcode
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
            sourceURL: url,
            cloudCompleteAtStart: cloudCompleteAtStart
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

        // Railway-first: the cloud worker completed this swipe while the local
        // pass was running — its result wins, ours is discarded. (Without this,
        // the Mac's slower pipeline landed last and overwrote the worker's full
        // carousel transcript with a poorer one.)
        if Self.isCloudComplete(metadataJSON: atom.metadata), !output.cloudCompleteAtStart {
            print("SwipeProcessingService: Cloud worker completed \(uuid.prefix(8)) mid-pass — discarding local result (Railway-first)")
            return
        }

        // Check if user is actively editing this atom — skip body/title if so
        let userIsEditing = AtomRepository.shared.isBeingEdited(uuid)
        if userIsEditing {
            print("SwipeProcessingService: Atom \(uuid) is being edited, preserving user's body/title")
        }

        // The editing lock covers body + slides too, not just title/hook: while
        // the user has this swipe open, a background transcription result must
        // not clobber their transcript. Only write transcript fields when there
        // is nothing user-visible to lose.
        let existingAnalysis = atom.swipeAnalysis
        let hasStoredTranscript = (existingAnalysis?.transcriptSlides?.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false) || !(atom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let skipTranscriptWrite = userIsEditing && hasStoredTranscript
        if skipTranscriptWrite {
            print("SwipeProcessingService: Atom \(uuid) is being edited with an existing transcript — preserving user's body/slides")
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

        // Build in-memory atom with transcript (needed as analyzer input).
        // When the user's transcript is protected, the analyzer runs on the
        // user's existing body instead of the fresh auto-transcript.
        var richContent = atom.richContent ?? ResearchRichContent()
        if !skipTranscriptWrite {
            atom.body = combined
            richContent.transcript = combined
            richContent.transcriptStatus = "available"
        }

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
        var didSetHookTitle = false
        if (!userIsEditing || hasPlaceholderTitle),
           let firstText = finalSlides.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
            let hook = firstText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            atom.hook = String(hook.prefix(500))
            atom.title = String(hook.prefix(120))
            richContent.title = String(hook.prefix(120))
            didSetHookTitle = true
        }

        atom.setRichContent(richContent)

        // Save slides into swipeAnalysis (unless the user's transcript is protected)
        if !skipTranscriptWrite {
            var sa = atom.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            sa.transcriptSlides = finalSlides
            sa.rawTranscriptSlides = rawSlides
            sa.transcriptSpeechSegments = speechSegments
            sa.transcriptionQuality = transcriptionQuality
            sa.transcriptionWarnings = transcriptionWarnings
            atom = atom.withSwipeAnalysis(sa)
        }

        atom.processingStatus = "analyzing"

        // Single insight pass (Sonnet 5) — in-memory only, no DB write yet.
        // Replaces the old two-step NLP-heuristics + classification pipeline.
        print("SwipeProcessingService: Running insight analysis for \(uuid)")
        var insight = await SwipeInsightEngine.shared.analyze(atom: atom)
        if !skipTranscriptWrite {
            insight.transcriptSlides = finalSlides
            insight.rawTranscriptSlides = rawSlides
            insight.transcriptSpeechSegments = speechSegments
            insight.transcriptionQuality = transcriptionQuality
            insight.transcriptionWarnings = transcriptionWarnings
        }
        // A fresh analysis knows nothing about engagement metrics, study state,
        // comments, or manual taxonomy overrides — carry them over before persisting.
        insight = insight.preservingCuratedFields(from: existingAnalysis)
        atom = atom.withSwipeAnalysis(insight)

        // Library headline: short hooks stay verbatim, long hooks arrive
        // compressed from the insight pass. Same guard as the hook block above;
        // atom.hook keeps the full first slide either way.
        if (!userIsEditing || hasPlaceholderTitle),
           let displayTitle = insight.displayTitle, !displayTitle.isEmpty {
            atom.title = displayTitle
            if var rc = atom.richContent {
                rc.title = displayTitle
                atom.setRichContent(rc)
            }
            didSetHookTitle = true
        }

        // Re-index the recall embedding now that the transcript landed.
        await RecallIndexer.shared.noteAtomChanged(uuid: atom.uuid)

        // SINGLE WRITE: Persist all accumulated changes (transcript + NLP + classification + status) at once.
        // On version conflict (common for cloud-captured swipes where sync bumps the version during
        // processing), re-fetch the latest version and re-apply analysis results.
        //
        // A /p/ carousel that did not resolve its full slide set is persisted as "partial",
        // never bricked: it stays displayable (≥1 slide) AND remains eligible for a later
        // background upgrade pass. Only fully-resolved media is marked "complete".
        let stillIncomplete = InstagramMediaResolution.isIncompletePostMedia(
            mediaData: mediaData,
            sourceURL: url,
            existingCarouselItems: carouselItems
        )
        atom.processingStatus = stillIncomplete ? "partial" : "complete"
        do {
            _ = try await AtomRepository.shared.update(atom)
        } catch let error as AtomRepositoryError where error.isVersionConflict {
            print("SwipeProcessingService: Version conflict for \(uuid), retrying with latest version")
            if var latest = try? await AtomRepository.shared.fetch(uuid: uuid) {
                // Railway-first: the conflicting writer may BE the cloud worker
                // finishing this exact swipe — never re-apply on top of that.
                if Self.isCloudComplete(metadataJSON: latest.metadata), !output.cloudCompleteAtStart {
                    print("SwipeProcessingService: Conflict was the cloud worker completing \(uuid.prefix(8)) — discarding local result (Railway-first)")
                    return
                }
                // Merge analysis results onto the latest version — only the
                // fields this pass actually produced, preserving anything the
                // concurrent writer (or the user) changed in the meantime.
                if !skipTranscriptWrite {
                    latest.body = atom.body
                }
                if didSetHookTitle {
                    latest.title = atom.title
                    latest.hook = atom.hook
                }
                latest.processingStatus = stillIncomplete ? "partial" : "complete"
                latest.setRichContent(atom.richContent ?? ResearchRichContent())
                if let sa = atom.swipeAnalysis {
                    latest = latest.withSwipeAnalysis(sa.preservingCuratedFields(from: latest.swipeAnalysis))
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

        // Queue for the cross-swipe pattern weaver (batched — no call here).
        if atom.swipeAnalysis?.isFullyAnalyzed == true {
            SwipePatternStore.shared.markPendingWeave(uuid)
        }

        // Cache carousel media locally (CDN URLs expire)
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

// MARK: - iOS Companion Ext 3a: Swipe Thumbnail Cloud Mirror
// The Mac's ThumbnailCache is the only durable copy of swipe thumbnails
// (Instagram CDN URLs expire). Mirror the cached JPEGs to Supabase Storage
// (`atom-images/<user>/swipe-thumbs/<atomUUID>.jpg`) and record
// `metadata.thumbnailStorageURL` so the iPhone renders real cards.
// Throttled backfill; purely additive — existing behavior untouched.

@MainActor
enum SwipeThumbnailCloudMirror {

    static let perPassLimit = 40
    /// Swipes whose mirror failed this launch (no local cache AND dead CDN URL).
    /// Skipped for the rest of the launch so they never block the batch;
    /// retried automatically on the next launch.
    private static var failedThisLaunch: Set<String> = []

    /// Runs every sync pass, mirroring up to `perPassLimit` swipes per pass
    /// until the backlog is drained. Fresh swipes are covered too: their CDN
    /// URL is still live, so the direct-fetch fallback mirrors them within a
    /// sync cycle of capture.
    static func runBackfillPassIfNeeded() async {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        guard let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId else { return }

        let atoms = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        let eligible = atoms.filter { $0.isSwipeFileAtom }
        let pending = eligible.filter { mirrorableStorageURL(from: $0.metadata) == nil }
        // Attempts bound the pass, not successes — when uploads fail
        // systemically (e.g. a storage policy rejects everything), a
        // success-only cap walks the ENTIRE backlog in one burst.
        let workable = pending.filter { !failedThisLaunch.contains($0.uuid) }

        SwipeMediaMirrorProgress.shared.setThumbnails(
            done: eligible.count - pending.count,
            total: eligible.count,
            deferred: failedThisLaunch.count
        )

        guard !workable.isEmpty else { return }

        var mirrored = 0
        for atom in workable.prefix(perPassLimit) {
            if await mirror(atom: atom, client: client, userId: userId) {
                mirrored += 1
            } else {
                failedThisLaunch.insert(atom.uuid)
            }
        }

        let done = eligible.count - pending.count + mirrored
        SwipeMediaMirrorProgress.shared.setThumbnails(done: done, total: eligible.count, deferred: failedThisLaunch.count)
        let remaining = max(0, eligible.count - done - failedThisLaunch.count)
        print("SwipeThumbnailCloudMirror: \(done)/\(eligible.count) thumbnails in cloud — \(SwipeCloudMirrorSupport.etaDescription(remaining: remaining, perPass: perPassLimit))\(failedThisLaunch.isEmpty ? "" : " (\(failedThisLaunch.count) deferred to next launch)")")
    }

    private static func mirrorableStorageURL(from metadata: String?) -> String? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict["thumbnailStorageURL"] as? String
    }

    /// Locate the JPEG for this swipe — local cache first (carousel stable key,
    /// then the thumbnail URL's cache key), then a direct CDN fetch for URLs
    /// that are still live — and upload it.
    private static func mirror(atom: Atom, client: SupabaseClient, userId: String) async -> Bool {
        var keys: [String] = []
        if let instagramId = atom.richContent?.instagramId {
            keys.append("ig-carousel-\(instagramId)-0")
        }
        let thumbnailURLString = atom.researchMetadata?.thumbnailUrl ?? atom.richContent?.thumbnailUrl
        if let thumbnailURLString, let url = URL(string: thumbnailURLString) {
            keys.append(ThumbnailCacheService.shared.cacheKey(for: url, stableKey: nil))
        }

        let cacheDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)

        var jpegData: Data?
        for key in keys {
            let path = cacheDir.appendingPathComponent("thumb-\(key).jpg")
            if let data = try? Data(contentsOf: path), !data.isEmpty {
                jpegData = data
                break
            }
        }

        // No local cache — the CDN URL may still be live (always true for
        // freshly captured swipes). Fetch and drop a copy into the local cache
        // so the Mac's own cards benefit too.
        if jpegData == nil,
           let thumbnailURLString,
           let url = URL(string: thumbnailURLString),
           url.scheme?.hasPrefix("http") == true {
            if let (data, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               !data.isEmpty {
                jpegData = data
                if let cacheKey = keys.last {
                    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                    try? data.write(to: cacheDir.appendingPathComponent("thumb-\(cacheKey).jpg"))
                }
            }
        }

        guard let jpegData else { return false }

        do {
            let storageURL = try await client.uploadStorageObject(
                bucket: "atom-images",
                path: "\(userId.lowercased())/swipe-thumbs/\(atom.uuid).jpg",
                data: jpegData
            )
            return await SwipeCloudMirrorSupport.mergeMetadata(
                atom: atom,
                entries: ["thumbnailStorageURL": storageURL],
                context: "SwipeThumbnailCloudMirror"
            )
        } catch {
            print("SwipeThumbnailCloudMirror: upload failed for \(atom.uuid): \(error)")
            return false
        }
    }
}

// MARK: - Mirror progress (Settings → Cloud Sync shows this)

/// Live backlog counters for the three swipe media mirrors, updated every
/// backfill pass so the user can see how far along the cloud upload is and
/// when it will finish — instead of being in the dark behind console logs.
@MainActor
@Observable
final class SwipeMediaMirrorProgress {
    static let shared = SwipeMediaMirrorProgress()

    struct Lane: Equatable {
        var done = 0
        var total = 0
        var deferred = 0   // failed this launch; retried next launch

        var remaining: Int { max(0, total - done - deferred) }
        var isComplete: Bool { total > 0 && done >= total }
    }

    private(set) var thumbnails = Lane()
    private(set) var carousels = Lane()
    private(set) var videos = Lane()
    private(set) var lastPassAt: Date?

    var hasAnyWork: Bool {
        thumbnails.total + carousels.total + videos.total > 0
    }

    func setThumbnails(done: Int, total: Int, deferred: Int) {
        thumbnails = Lane(done: done, total: total, deferred: deferred)
        lastPassAt = Date()
    }

    func setCarousels(done: Int, total: Int, deferred: Int) {
        carousels = Lane(done: done, total: total, deferred: deferred)
        lastPassAt = Date()
    }

    func setVideos(done: Int, total: Int, deferred: Int) {
        videos = Lane(done: done, total: total, deferred: deferred)
        lastPassAt = Date()
    }
}

// MARK: - Shared mirror support

@MainActor
enum SwipeCloudMirrorSupport {
    /// Backlogs drain continuously (SwipeMediaMirrorCoordinator), so status is
    /// a plain remaining count — time claims would be connection-speed guesses.
    static func etaDescription(remaining: Int, perPass: Int) -> String {
        remaining > 0 ? "\(remaining) to go" : "done"
    }

    /// Key-level metadata merge — every key this build doesn't model survives.
    static func mergeMetadata(atom: Atom, entries: [String: Any], context: String) async -> Bool {
        guard var dict = atom.metadata
            .flatMap({ $0.data(using: .utf8) })
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return false }
        for (key, value) in entries {
            dict[key] = value
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: dict),
              let mergedString = String(data: merged, encoding: .utf8) else { return false }

        var updated = atom
        updated.metadata = mergedString
        do {
            _ = try await AtomRepository.shared.update(updated)
            return true
        } catch {
            print("\(context): metadata merge failed for \(atom.uuid): \(error)")
            return false
        }
    }
}

// MARK: - Continuous drain coordinator

/// Runs mirror passes BACK-TO-BACK until the backlog is empty, instead of one
/// pass per 5-minute sync cycle — the backlog uploads at connection speed.
/// The loop stops when a full round makes no progress (everything mirrored,
/// or only deferred failures remain); the next sync cycle re-kicks it, which
/// is a cheap no-op when there's nothing to do.
@MainActor
enum SwipeMediaMirrorCoordinator {
    private static var drainTask: Task<Void, Never>?

    static func kick() {
        guard drainTask == nil else { return }
        drainTask = Task {
            defer { drainTask = nil }
            // Once per launch: rewrite legacy hook-length titles into short
            // display headlines (self-guards, cheap no-op when clean).
            await SwipeTitleBackfill.runBackfillPassIfNeeded()
            // Once per launch: consolidate pre-canonical free-text niches into
            // the NicheRegistry vocabulary (data-derived gate — cheap no-op
            // once the library is canonical).
            await SwipeNicheBackfill.runBackfillPassIfNeeded()
            // Once per launch: weave pending swipes into the pattern library
            // (batched — runs only when enough swipes accumulated or weekly).
            await SwipePatternWeaver.runIfNeeded()
            while !Task.isCancelled {
                let before = attemptCounts()
                await SwipeThumbnailCloudMirror.runBackfillPassIfNeeded()
                await SwipeCarouselCloudMirror.runBackfillPassIfNeeded()
                await SwipeVideoCloudMirror.runBackfillPassIfNeeded()
                let after = attemptCounts()
                if after == before { break }   // nothing left to try → idle until next kick
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Progress = work consumed, successful OR deferred. Counting successes
    /// alone stopped the loop after one all-failure round, stranding the rest
    /// of the backlog untried.
    private static func attemptCounts() -> [Int] {
        let progress = SwipeMediaMirrorProgress.shared
        return [
            progress.thumbnails.done + progress.thumbnails.deferred,
            progress.carousels.done + progress.carousels.deferred,
            progress.videos.done + progress.videos.deferred,
        ]
    }
}

// MARK: - Swipe Video Cloud Mirror
// Reels/video swipes are watchable on the iPhone only if the MP4 leaves the
// Mac's local cache (Instagram CDN URLs expire in days). Mirrors cached videos
// to Supabase Storage (`swipe-videos/<user>/<atomUUID>.mp4`, ~9 MB avg) and
// records `metadata.videoStorageURL`. Same backlog-drain grammar as the
// thumbnail mirror: attempts bound each pass, failures memoized per launch.

@MainActor
enum SwipeVideoCloudMirror {

    static let perPassLimit = 10   // ~90 MB per 5-min pass
    private static var failedThisLaunch: Set<String> = []

    static func runBackfillPassIfNeeded() async {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        guard let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId else { return }

        let atoms = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        let eligible = atoms.filter { $0.isSwipeFileAtom && isVideoSwipe($0) }
        let pending = eligible.filter { storageURL(from: $0.metadata) == nil }
        let workable = pending.filter { !failedThisLaunch.contains($0.uuid) }

        SwipeMediaMirrorProgress.shared.setVideos(
            done: eligible.count - pending.count,
            total: eligible.count,
            deferred: failedThisLaunch.count
        )

        guard !workable.isEmpty else { return }

        var mirrored = 0
        for atom in workable.prefix(perPassLimit) {
            if await mirror(atom: atom, client: client, userId: userId) {
                mirrored += 1
            } else {
                failedThisLaunch.insert(atom.uuid)
            }
        }

        let done = eligible.count - pending.count + mirrored
        SwipeMediaMirrorProgress.shared.setVideos(done: done, total: eligible.count, deferred: failedThisLaunch.count)
        let remaining = max(0, eligible.count - done - failedThisLaunch.count)
        print("SwipeVideoCloudMirror: \(done)/\(eligible.count) videos in cloud — \(SwipeCloudMirrorSupport.etaDescription(remaining: remaining, perPass: perPassLimit))\(failedThisLaunch.isEmpty ? "" : " (\(failedThisLaunch.count) deferred to next launch)")")
    }

    static func storageURL(from metadata: String?) -> String? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict["videoStorageURL"] as? String
    }

    /// Instagram reels / video posts only — the local MP4 cache is Instagram-
    /// specific (YouTube swipes play via embed and are not cached).
    private static func isVideoSwipe(_ atom: Atom) -> Bool {
        guard let igData = atom.richContent?.instagramData else { return false }
        switch igData.contentType {
        case .reel, .videoPost:
            return true
        default:
            // Older atoms may be mislabeled — a stored extracted video URL or a
            // cached MP4 still marks them as video content.
            if igData.extractedMediaURL != nil { return true }
            if let shortcode = shortcode(for: atom),
               InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) != nil {
                return true
            }
            return false
        }
    }

    private static func shortcode(for atom: Atom) -> String? {
        guard let urlString = atom.url, let url = URL(string: urlString) else { return nil }
        return InstagramExtractor.shared.extractShortcode(from: url)
    }

    private static func mirror(atom: Atom, client: SupabaseClient, userId: String) async -> Bool {
        guard let shortcode = shortcode(for: atom) else { return false }

        // 1) Local cache fast path; 2) re-extract via the resolver (downloads
        // into the same cache) when the stored CDN URL is still live.
        var fileURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode)
        if fileURL == nil, let remote = atom.richContent?.instagramData?.extractedMediaURL {
            let resolved = await InstagramVideoLocalCache.resolvePlayableURL(from: remote, shortcode: shortcode)
            if resolved.isFileURL {
                fileURL = resolved
            }
        }
        guard let fileURL, let videoData = try? Data(contentsOf: fileURL), videoData.count > 10_000 else {
            return false
        }

        do {
            let storageURL = try await client.uploadStorageObject(
                bucket: "swipe-videos",
                path: "\(userId.lowercased())/\(atom.uuid).mp4",
                data: videoData,
                contentType: "video/mp4"
            )
            return await SwipeCloudMirrorSupport.mergeMetadata(
                atom: atom,
                entries: ["videoStorageURL": storageURL],
                context: "SwipeVideoCloudMirror"
            )
        } catch {
            print("SwipeVideoCloudMirror: upload failed for \(atom.uuid): \(error)")
            return false
        }
    }
}

// MARK: - Swipe Carousel Cloud Mirror
// Carousels need EVERY page on the phone, not just the cover. Mirrors each
// carousel image (local ThumbnailCache first, live CDN fetch fallback with
// Instagram-friendly headers) to `atom-images/<user>/swipe-carousel/` and
// records the ordered `metadata.carouselImageStorageURLs`. Written only when
// every page uploads, so the array is always complete and index-aligned.

@MainActor
enum SwipeCarouselCloudMirror {

    static let perPassLimit = 6   // atoms per pass (~5-10 images each)
    private static var failedThisLaunch: Set<String> = []

    static func runBackfillPassIfNeeded() async {
        guard SupabaseSyncTrafficPolicy.allowsNetworkSync else { return }
        guard let client = SupabaseClient.shared, client.isAuthenticated,
              let userId = client.currentUserId else { return }

        let atoms = (try? await AtomRepository.shared.fetchAll(type: .research)) ?? []
        let eligible = atoms.filter { atom in
            atom.isSwipeFileAtom && (atom.richContent?.instagramData?.carouselItems?.count ?? 0) > 1
        }
        let pending = eligible.filter { atom in
            let itemCount = atom.richContent?.instagramData?.carouselItems?.count ?? 0
            return mirroredURLs(from: atom.metadata)?.count != itemCount
        }
        let workable = pending.filter { !failedThisLaunch.contains($0.uuid) }

        SwipeMediaMirrorProgress.shared.setCarousels(
            done: eligible.count - pending.count,
            total: eligible.count,
            deferred: failedThisLaunch.count
        )

        guard !workable.isEmpty else { return }

        var mirrored = 0
        for atom in workable.prefix(perPassLimit) {
            guard let items = atom.richContent?.instagramData?.carouselItems else { continue }
            if await mirror(atom: atom, items: items, client: client, userId: userId) {
                mirrored += 1
            } else {
                failedThisLaunch.insert(atom.uuid)
            }
        }

        let done = eligible.count - pending.count + mirrored
        SwipeMediaMirrorProgress.shared.setCarousels(done: done, total: eligible.count, deferred: failedThisLaunch.count)
        let remaining = max(0, eligible.count - done - failedThisLaunch.count)
        print("SwipeCarouselCloudMirror: \(done)/\(eligible.count) carousels in cloud — \(SwipeCloudMirrorSupport.etaDescription(remaining: remaining, perPass: perPassLimit))\(failedThisLaunch.isEmpty ? "" : " (\(failedThisLaunch.count) deferred to next launch)")")
    }

    static func mirroredURLs(from metadata: String?) -> [String]? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict["carouselImageStorageURLs"] as? [String]
    }

    /// Rebuilds a displayable slide list from the durable Supabase copies —
    /// the exact media iOS renders instantly. The mirror is only ever written
    /// complete (every page or nothing), so a non-nil result is the full set.
    /// Upload order is page order; videos inside carousels are poster frames.
    static func mirroredCarouselItems(from metadata: String?) -> [CarouselItem]? {
        guard let urls = mirroredURLs(from: metadata), !urls.isEmpty else { return nil }
        let items = urls.enumerated().compactMap { index, raw -> CarouselItem? in
            guard let url = URL(string: raw) else { return nil }
            return CarouselItem(index: index, mediaType: .image, mediaURL: url)
        }
        return items.count == urls.count ? items : nil
    }

    private static func mirror(atom: Atom, items: [CarouselItem], client: SupabaseClient, userId: String) async -> Bool {
        let shortcode = atom.richContent?.instagramId
        let cacheDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cosmo/ThumbnailCache", isDirectory: true)

        var uploaded: [String] = []
        for item in items.sorted(by: { $0.index < $1.index }) {
            // Videos inside carousels: mirror the poster frame.
            let sourceURL = item.mediaType == .video ? (item.thumbnailURL ?? item.mediaURL) : item.mediaURL
            let cacheKey = InstagramCarouselImageCache.cacheKey(shortcode: shortcode, index: item.index, url: sourceURL)

            var imageData: Data?
            let cachePath = cacheDir.appendingPathComponent("thumb-\(cacheKey).jpg")
            if let data = try? Data(contentsOf: cachePath), !data.isEmpty {
                imageData = data
            } else if let (data, response) = try? await URLSession.shared.data(for: InstagramCarouselImageCache.request(for: sourceURL)),
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      !data.isEmpty {
                imageData = data
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try? data.write(to: cachePath)
            }
            guard let imageData else { return false }

            do {
                let storageURL = try await client.uploadStorageObject(
                    bucket: "atom-images",
                    path: "\(userId.lowercased())/swipe-carousel/\(atom.uuid)-\(item.index).jpg",
                    data: imageData
                )
                uploaded.append(storageURL)
            } catch {
                print("SwipeCarouselCloudMirror: upload failed for \(atom.uuid) page \(item.index): \(error)")
                return false
            }
        }

        guard uploaded.count == items.count else { return false }
        return await SwipeCloudMirrorSupport.mergeMetadata(
            atom: atom,
            entries: ["carouselImageStorageURLs": uploaded],
            context: "SwipeCarouselCloudMirror"
        )
    }
}
