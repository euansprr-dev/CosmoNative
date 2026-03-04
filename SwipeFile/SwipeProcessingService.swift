// CosmoOS/SwipeFile/SwipeProcessingService.swift
// Background processing service for auto-transcription + analysis of swipe files on capture
// February 2026

import Foundation

/// Singleton service that processes swipe files in the background after capture.
/// Handles transcription (video or carousel), Claude cleanup, analysis, and re-indexing.
@MainActor
final class SwipeProcessingService {
    static let shared = SwipeProcessingService()

    /// UUIDs currently being processed — prevents duplicate work
    private var inFlightUUIDs: Set<String> = []

    private init() {}

    /// Check if a swipe is currently being processed
    func isProcessing(uuid: String) -> Bool {
        inFlightUUIDs.contains(uuid)
    }

    /// Fire-and-forget background processing for a newly captured swipe
    func processSwipeInBackground(uuid: String) {
        guard !inFlightUUIDs.contains(uuid) else {
            print("SwipeProcessingService: Already processing \(uuid), skipping")
            return
        }
        inFlightUUIDs.insert(uuid)

        Task {
            await processSwipe(uuid: uuid)
            inFlightUUIDs.remove(uuid)
        }
    }

    // MARK: - Main Processing Pipeline

    private func processSwipe(uuid: String) async {
        print("SwipeProcessingService: Starting background processing for \(uuid)")

        // Step 1: Fetch atom
        guard var atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
            print("SwipeProcessingService: Could not fetch atom \(uuid)")
            return
        }

        // Step 2: Skip if already transcribed
        let hasTranscript = atom.richContent?.transcriptStatus == "available"
        let hasBody = !(atom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTranscript && hasBody {
            print("SwipeProcessingService: Atom \(uuid) already has transcript, skipping")
            return
        }

        // Update status
        atom.processingStatus = "extracting"
        try? await AtomRepository.shared.update(atom)

        // Step 3: Determine content type and extract media
        guard let urlString = atom.url, let url = URL(string: urlString) else {
            print("SwipeProcessingService: No URL for atom \(uuid)")
            atom.processingStatus = "error"
            try? await AtomRepository.shared.update(atom)
            return
        }

        let mediaData: InstagramMediaData
        do {
            mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
        } catch {
            print("SwipeProcessingService: Media extraction failed for \(uuid): \(error)")
            atom.processingStatus = "error"
            try? await AtomRepository.shared.update(atom)
            return
        }

        // Update status
        atom.processingStatus = "transcribing"
        try? await AtomRepository.shared.update(atom)

        // Step 4: Branch by content type
        var transcriptionResult: TranscriptionResult

        // Primary: use freshly extracted carousel items
        // Fallback: use stored carousel items from initial capture
        let carouselItems = mediaData.carouselItems
            ?? atom.richContent?.instagramData?.carouselItems

        if let items = carouselItems, !items.isEmpty {
            // Carousel path (check items regardless of content type label)
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: items
            ) { progress in
                switch progress {
                case .recognizingText(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService: OCR \(Int(pct * 100))%")
                    }
                case .analyzingWithAI(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService: AI \(Int(pct * 100))%")
                    }
                default: break
                }
            }
        } else if let videoURL = mediaData.videoURL {
            // Video/Reel path — download locally first
            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)
            let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL, shortcode: shortcode)
            let duration = mediaData.duration ?? 60

            transcriptionResult = await InstagramAutoTranscriber.shared.transcribe(
                videoURL: playableURL,
                duration: duration
            ) { progress in
                switch progress {
                case .extractingFrames(let pct):
                    if Int(pct * 100) % 25 == 0 {
                        print("SwipeProcessingService: Frames \(Int(pct * 100))%")
                    }
                default: break
                }
            }
        } else if let thumbnailURL = mediaData.thumbnailURL {
            // Image post with thumbnail — OCR the thumbnail image
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
                        print("SwipeProcessingService: OCR \(Int(pct * 100))%")
                    }
                default: break
                }
            }
        } else {
            // No video, no carousel items, no thumbnail — nothing to transcribe
            print("SwipeProcessingService: No transcribable content for \(uuid)")
            atom.processingStatus = "complete"
            try? await AtomRepository.shared.update(atom)
            return
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

            // Set thumbnail from first carousel image if missing
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

        // Step 5: Skip if transcription returned nothing
        guard transcriptionResult.contentType != .empty,
              !transcriptionResult.slides.isEmpty else {
            print("SwipeProcessingService: Transcription returned empty for \(uuid)")
            atom.processingStatus = "complete"
            try? await AtomRepository.shared.update(atom)
            return
        }

        // Step 6: Claude cleanup (skip for Gemini-only results)
        var finalSlides = transcriptionResult.slides
        let needsCleanup = transcriptionResult.contentType != .voiceoverOnly
            && !finalSlides.allSatisfy({ $0.source == .geminiVision })
        if needsCleanup {
            let isCarousel = carouselItems != nil && !carouselItems!.isEmpty
            if let cleaned = await InstagramAutoTranscriber.shared.cleanupWithClaude(slides: finalSlides, isCarousel: isCarousel) {
                finalSlides = cleaned
            }
        }

        // Step 7: Save transcript to atom
        let combined = finalSlides
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        // Re-fetch atom to avoid overwriting concurrent changes
        if let fresh = try? await AtomRepository.shared.fetch(uuid: uuid) {
            atom = fresh
        }

        atom.body = combined
        var richContent = atom.richContent ?? ResearchRichContent()
        richContent.transcript = combined
        richContent.transcriptStatus = "available"

        // Persist carousel items + sourceType + thumbnail if this was a carousel
        if let items = carouselItems, !items.isEmpty {
            var igData = richContent.instagramData ?? InstagramData(
                originalURL: url,
                contentType: .carousel
            )
            if igData.carouselItems == nil || igData.carouselItems?.isEmpty == true {
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

        // Set hook/title from first slide.
        // Hook = the ENTIRETY of slide 1, nothing more, nothing less.
        // The 500-char limit covers TranscriptSlide.characterLimit (450) with buffer.
        if let firstText = finalSlides.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
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
        atom = atom.withSwipeAnalysis(sa)

        atom.processingStatus = "analyzing"
        do {
            atom = try await AtomRepository.shared.update(atom)
        } catch {
            print("SwipeProcessingService: Failed to save transcript: \(error)")
        }

        // Step 8: Run analysis
        print("SwipeProcessingService: Running analysis for \(uuid)")
        var nlpResult = await SwipeAnalyzer.shared.analyze(atom: atom)
        nlpResult.transcriptSlides = finalSlides
        atom = atom.withSwipeAnalysis(nlpResult)
        do {
            atom = try await AtomRepository.shared.update(atom)
        } catch {
            print("SwipeProcessingService: Failed to save NLP analysis: \(error)")
        }

        // Deep analysis via Claude
        let classifiedResult = await SwipeClassificationEngine.shared.classifyAndAnalyze(atom: atom)
        if classifiedResult.isFullyAnalyzed {
            var enriched = SwipeClassificationEngine.shared.mergeClassification(classifiedResult, into: nlpResult)
            enriched.transcriptSlides = finalSlides
            atom = atom.withSwipeAnalysis(enriched)
            do {
                atom = try await AtomRepository.shared.update(atom)
            } catch {
                print("SwipeProcessingService: Failed to save deep analysis: \(error)")
            }
        }

        // Step 9: Re-index embedding with transcript text
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

        // Step 10: Mark complete
        atom.processingStatus = "complete"
        do {
            try await AtomRepository.shared.update(atom)
        } catch {
            print("SwipeProcessingService: Failed to mark complete: \(error)")
        }

        // Step 11: Cache carousel thumbnail locally (CDN URLs expire)
        if let items = carouselItems, !items.isEmpty {
            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)
            await SwipeFileEngine.cacheCarouselThumbnail(items: items, shortcode: shortcode)
        }

        print("SwipeProcessingService: Background processing complete for \(uuid) — \(finalSlides.count) slides")
    }
}
