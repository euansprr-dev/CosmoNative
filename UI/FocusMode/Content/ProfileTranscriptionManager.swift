// CosmoOS/UI/FocusMode/Content/ProfileTranscriptionManager.swift
// Manages Instagram URL auto-transcription for client profile editor
// March 2026

import Foundation

// MARK: - Profile Transcription Manager

/// Manages per-entry transcription state for the ContentProfileEditor.
/// Reuses the same InstagramMediaCache + InstagramAutoTranscriber pipeline as SwipeProcessingService.
@MainActor
final class ProfileTranscriptionManager: ObservableObject {

    // MARK: - Transcription State

    struct TranscriptionState {
        var isTranscribing: Bool = false
        var progressText: String = ""
        var error: String?
    }

    /// Tracks state by ProfileDocument.id
    @Published var states: [UUID: TranscriptionState] = [:]

    /// Returns true if any transcription is in-flight
    var hasActiveTranscriptions: Bool {
        states.values.contains { $0.isTranscribing }
    }

    // MARK: - Transcribe URL

    /// Transcribe an Instagram URL and return a completed ProfileDocument.
    /// Updates `states[documentId]` with progress throughout the process.
    func transcribe(
        url: URL,
        documentId: UUID,
        category: ProfileDocumentCategory
    ) async -> ProfileDocument? {
        states[documentId] = TranscriptionState(isTranscribing: true, progressText: "Extracting media...")

        // Step 1: Extract media via InstagramMediaCache
        let mediaData: InstagramMediaData
        do {
            mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
        } catch {
            states[documentId] = TranscriptionState(error: "Could not extract media")
            return nil
        }

        // Step 2: Resolve carousel items — the initial extraction may have stopped
        // early (e.g. Cobalt returned a single URL instead of picker) so if no
        // carousel items were found, try the GraphQL API directly which reliably
        // parses edge_sidecar_to_children for carousel posts.
        var carouselItems = mediaData.carouselItems
        if (carouselItems ?? []).isEmpty {
            if let fallbackItems = await fetchCarouselItemsViaGraphQL(url: url) {
                carouselItems = fallbackItems
                print("ProfileTranscriptionManager: GraphQL fallback found \(fallbackItems.count) carousel items")
            }
        }

        // Step 3: Transcribe based on content type
        states[documentId]?.progressText = "Transcribing..."

        let transcriptionResult: TranscriptionResult
        var isCarousel = false

        if let items = carouselItems, !items.isEmpty {
            // Carousel path
            isCarousel = true
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: items
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(documentId: documentId, progress: progress)
                }
            }
        } else if let videoURL = mediaData.videoURL {
            // Video/Reel path — download locally first
            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)
            let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(
                from: videoURL, shortcode: shortcode
            )
            let duration = mediaData.duration ?? 60

            transcriptionResult = await InstagramAutoTranscriber.shared.transcribe(
                videoURL: playableURL,
                duration: duration
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(documentId: documentId, progress: progress)
                }
            }
        } else if let thumbnailURL = mediaData.thumbnailURL {
            // Thumbnail-only fallback — warn if this is a reel/video (degraded result)
            let isVideoContent = mediaData.contentType == .reel || mediaData.contentType == .videoPost
            if isVideoContent {
                states[documentId]?.progressText = "Video extraction failed, OCR on thumbnail..."
            }
            let singleItem = CarouselItem(index: 0, mediaType: .image, mediaURL: thumbnailURL)
            transcriptionResult = await InstagramAutoTranscriber.shared.transcribeCarousel(
                items: [singleItem]
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(documentId: documentId, progress: progress)
                }
            }
            // If result seems thin and this was a video, set a warning
            if isVideoContent {
                let totalText = transcriptionResult.slides.map(\.text).joined()
                if totalText.count < 50 {
                    states[documentId] = TranscriptionState(
                        error: "Could not extract video — only thumbnail text captured. Try pasting the transcript manually."
                    )
                    return nil
                }
            }
        } else {
            states[documentId] = TranscriptionState(error: "No transcribable content found")
            return nil
        }

        // Step 4: Check for empty result
        guard transcriptionResult.contentType != .empty,
              !transcriptionResult.slides.isEmpty else {
            states[documentId] = TranscriptionState(error: "Transcription returned empty")
            return nil
        }

        // Step 5: Claude cleanup (skip for Gemini-only results)
        states[documentId]?.progressText = "Cleaning up..."
        var finalSlides = transcriptionResult.slides
        let needsCleanup = transcriptionResult.contentType != .voiceoverOnly
            && !finalSlides.allSatisfy({ $0.source == .geminiVision })
        if needsCleanup {
            if let cleaned = await InstagramAutoTranscriber.shared.cleanupWithClaude(
                slides: finalSlides, isCarousel: isCarousel
            ) {
                finalSlides = cleaned
            }
        }

        // Step 6: Build combined transcript with slide numbering
        let nonEmptySlides = finalSlides.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !nonEmptySlides.isEmpty else {
            states[documentId] = TranscriptionState(error: "Transcription returned empty")
            return nil
        }

        let combined: String
        if nonEmptySlides.count == 1 {
            // Single slide — no numbering needed
            combined = nonEmptySlides[0].text
        } else {
            // Multiple slides — add "Slide N:" prefix for each
            combined = nonEmptySlides.enumerated().map { index, slide in
                "Slide \(index + 1):\n\(slide.text)"
            }.joined(separator: "\n\n")
        }

        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            states[documentId] = TranscriptionState(error: "Transcription returned empty")
            return nil
        }

        // Step 7: Build ProfileDocument — auto-detect reel vs thread
        let resolvedCategory: ProfileDocumentCategory
        if isCarousel {
            resolvedCategory = category.isUnderperformer ? .underperformingThread : .thread
        } else {
            resolvedCategory = category
        }

        let title = String((nonEmptySlides.first?.text ?? "Transcribed post").prefix(60))
        let doc = ProfileDocument(
            id: documentId,
            category: resolvedCategory,
            title: title,
            content: combined,
            platform: "instagram",
            sourceURL: url.absoluteString
        )

        states[documentId] = TranscriptionState(isTranscribing: false)
        return doc
    }

    // MARK: - Carousel Fallback

    /// Direct GraphQL API call to extract carousel items when the primary extraction
    /// pipeline missed them (e.g. Cobalt returned a single URL instead of a picker).
    /// Uses the same endpoint and parsing as InstagramExtractor Strategy 3.
    private func fetchCarouselItemsViaGraphQL(url: URL) async -> [CarouselItem]? {
        guard let shortcode = InstagramExtractor.shared.extractShortcode(from: url) else { return nil }

        let graphqlURL = URL(string: "https://www.instagram.com/api/graphql")!
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 10

        let variables = "{\"shortcode\":\"\(shortcode)\"}"
        let docId = "8845758582119845"
        let bodyString = "variables=\(variables.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? variables)&doc_id=\(docId)"
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let media = dataObj["xdt_shortcode_media"] as? [String: Any] else {
                return nil
            }

            let mediaData = try InstagramExtractor.shared.parseMediaObject(media, originalURL: url, baseType: .image)
            let items = mediaData.carouselItems
            return (items?.isEmpty == false) ? items : nil
        } catch {
            print("ProfileTranscriptionManager: GraphQL carousel fallback failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Progress Updates

    private func updateProgress(documentId: UUID, progress: TranscriptionProgress) {
        guard states[documentId]?.isTranscribing == true else { return }
        switch progress {
        case .extractingFrames(let pct):
            states[documentId]?.progressText = "Extracting frames (\(Int(pct * 100))%)"
        case .recognizingText(let pct):
            states[documentId]?.progressText = "Reading text (\(Int(pct * 100))%)"
        case .recognizingSpeech(let pct):
            states[documentId]?.progressText = "Recognizing speech (\(Int(pct * 100))%)"
        case .analyzingWithAI(let pct):
            states[documentId]?.progressText = "AI analysis (\(Int(pct * 100))%)"
        case .mergingResults:
            states[documentId]?.progressText = "Merging results..."
        case .complete:
            states[documentId]?.progressText = "Complete"
        }
    }
}
