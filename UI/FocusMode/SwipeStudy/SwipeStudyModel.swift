// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyModel.swift
// All Swipe Study state + persistence logic, extracted from the old 5,900-line
// view during the July 2026 rebuild. The invariants transplanted verbatim:
//  - editing lock acquired per open atom, released only after a synchronous
//    flush of pending debounced edits (swipe switch, close, app quit)
//  - DirtyEditorRegistry flush choke point for every debounced save path
//  - transcriptEditedByUser is terminal: manual edits mark it, and
//    auto-transcription never runs again for that swipe
//  - every persist after analysis carries curated fields forward
//    (preservingCuratedFields) and stamps LIVE editor state after long awaits
// July 2026

import SwiftUI
import Combine
import AVKit
import Observation

@MainActor
@Observable
final class SwipeStudyModel {

    // MARK: - Injected

    let initialAtom: Atom
    var onClose: () -> Void

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.initialAtom = atom
        self.onClose = onClose
    }

    // MARK: - Core state

    var currentAtom: Atom?
    var analysis: SwipeAnalysis?
    var isAnalyzing = false
    var hasAppeared = false

    // YouTube player
    var isPlayerActive = false
    var currentTimestamp: TimeInterval = 0
    var videoDuration: TimeInterval = 0

    // Plain transcript (YouTube / default sources)
    var transcriptText: String = ""
    var isFetchingTranscript = false
    var transcriptFetchFailed = false

    // Instagram native player
    var igPlayer: AVPlayer?
    var igIsExtractingVideo = false
    var igVideoFailed = false
    var igMediaData: InstagramMediaData?

    // Carousel
    var carouselCurrentIndex: Int = 0
    var isCarouselContent: Bool = false
    /// True while a partial carousel (≥1 slide) is being upgraded toward the
    /// full slide set in the background. Drives the quiet "Loading more
    /// slides…" hint — never blocks display.
    var isUpgradingCarousel: Bool = false

    // Instagram transcript
    var instagramTranscript: String = ""
    private var transcriptSaveTask: Task<Void, Never>?
    /// Latest transcript text awaiting a debounced save — flushed synchronously
    /// on swipe switch / close / app quit so the edit can't be lost.
    private var pendingTranscriptText: String?

    // Slide-based transcript
    /// False during the entrance: slide cards render pixel-matched plain-Text
    /// stand-ins instead of NSTextViews. Mounting one AppKit text stack per
    /// slide (plus its sizeThatFits layout passes) in the entrance frame WAS
    /// the open hitch — the editors arrive one beat after the spring settles,
    /// or instantly when a stand-in is clicked.
    var slideEditorsActive = false
    private var slideEditorActivationTask: Task<Void, Never>?
    var transcriptSlides: [TranscriptSlide] = [TranscriptSlide(text: "", slideNumber: 1)]
    var rawTranscriptSlides: [TranscriptSlide] = []
    var transcriptSpeechSegments: [TranscriptSegment] = []
    /// Voiceover-only reels carry timestamped speech and NO slide text (the
    /// worker clears slides on the voiceoverOnly verdict; the default slide
    /// list is one blank placeholder). The manuscript renders the speech tier
    /// then — same resolution order as the preview rail and iOS.
    var showsSpeechTranscript: Bool {
        !transcriptSpeechSegments.isEmpty
            && !SwipePreviewTranscript.slidesCarryText(transcriptSlides)
    }
    var transcriptionQuality: TranscriptionQuality?
    var transcriptionWarnings: [String] = []
    var showRawTranscript = false
    private var slidesSaveTask: Task<Void, Never>?
    var slideFocusRequestID: UUID?
    /// Debounce-dirty tracking: the generation increments on every edit and the
    /// async save clears the pending flag only when no newer edit superseded it.
    private var slideEditGeneration = 0
    private var hasPendingSlideEdits = false
    private var commentEditGeneration = 0
    private var hasPendingCommentEdits = false

    // Auto-transcription
    var isAutoTranscribing = false
    var autoTranscriptionProgress: String = ""
    var autoTranscriptionContentType: TranscriptionContentType?

    // Inline comments
    var transcriptComments: [TranscriptComment] = []
    private var commentsSaveTask: Task<Void, Never>?
    var newCommentText: String = ""
    var activeCommentSlideIndex: Int?
    private var personalNotes: String = ""

    // Edit Transcript sheet (YouTube / plain sources)
    var showEditTranscript = false
    var editTranscriptText: String = ""

    // Reclassification
    var isReclassifying = false
    var reclassifySuggestion: SwipeAnalysis?

    // Overlays / feedback
    var showTaxonomyManagement = false
    var showDeleteConfirmation = false
    var copiedTranscript = false

    /// The uuid whose editing lock this model currently holds.
    private var lockedUUID: String?

    // MARK: - Lifecycle

    /// Called from the view's onAppear. First paint is synchronous from the
    /// injected atom — FocusNavigationCoordinator preloaded it, so the bench
    /// has real content on frame 1 of the entrance and the zoom-through hero
    /// never sits over a loading state. The injected snapshot can still be
    /// stale (pane/window contexts), so a background fetch reloads only when
    /// the row actually moved.
    func start() {
        acquireLock(for: initialAtom.uuid)
        loadAtom(using: initialAtom)
        Task {
            if let id = initialAtom.id,
               let fresh = try? await AtomRepository.shared.fetch(id: id),
               fresh.updatedAt != initialAtom.updatedAt,
               isViewingAtom(uuid: fresh.uuid) {
                loadAtom(using: fresh)
            }
        }
    }

    /// Called from the view's onDisappear: flush debounced edits and release
    /// the editing lock.
    func stop() {
        flushPendingDebouncedSavesSync()
        releaseLock()
        igPlayer?.pause()
        // Window context follows presence: leaving the study releases it.
        if let published = publishedContextProvider {
            CosmoWindowViewModel.shared.releaseContext(provider: published)
            publishedContextProvider = nil
        }
    }

    private func acquireLock(for uuid: String) {
        guard lockedUUID != uuid else { return }
        releaseLock()
        AtomRepository.shared.acquireEditingLock(uuid: uuid)
        lockedUUID = uuid
    }

    private func releaseLock() {
        if let lockedUUID {
            AtomRepository.shared.releaseEditingLock(uuid: lockedUUID)
        }
        lockedUUID = nil
    }

    var displayAtom: Atom { currentAtom ?? initialAtom }

    // MARK: - Deferred slide editors

    /// The entrance beat: long enough for the focus spring + hero teardown to
    /// finish, short enough that the swap lands before the user reaches for a
    /// slide. The stand-ins are pixel-matched, so the swap itself is invisible.
    private func scheduleSlideEditorActivation() {
        slideEditorActivationTask?.cancel()
        slideEditorActivationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.slideEditorsActive = true
        }
    }

    /// A stand-in was clicked before the scheduled swap — mount the editors
    /// now and forward focus to the clicked slide.
    func activateSlideEditors(focusing slideID: UUID?) {
        slideEditorActivationTask?.cancel()
        slideEditorsActive = true
        if let slideID {
            slideFocusRequestID = slideID
        }
    }

    private func isViewingAtom(uuid: String) -> Bool {
        currentAtom?.uuid == uuid
    }

    // MARK: - Hero presentation

    /// The manuscript headline: the short display title from the insight pass,
    /// falling back to the atom title / hook for legacy swipes.
    var heroTitle: String {
        if let title = analysis?.displayTitle, !title.isEmpty { return title }
        let candidates = [
            displayAtom.title,
            analysis?.hookText,
            displayAtom.hook,
            displayAtom.body?.components(separatedBy: .newlines).first
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? "Untitled swipe"
    }

    // MARK: - Source detection

    func detectSourceType(for atom: Atom) -> ResearchRichContent.SourceType? {
        if let st = atom.richContent?.sourceType { return st }
        if let rt = atom.researchType, let st = ResearchRichContent.SourceType(rawValue: rt) {
            return st
        }
        if let vid = atom.richContent?.videoId, !vid.isEmpty { return .youtube }
        if let igId = atom.richContent?.instagramId, !igId.isEmpty { return .instagram }
        if let url = atom.url?.lowercased() {
            if url.contains("youtube.com") || url.contains("youtu.be") {
                return url.contains("/shorts/") ? .youtubeShort : .youtube
            }
            if url.contains("instagram.com") {
                if url.contains("/reel") { return .instagramReel }
                if url.contains("/p/") { return .instagramPost }
                return .instagram
            }
        }
        return nil
    }

    func isInstagramSwipe(_ atom: Atom) -> Bool {
        let sourceType = detectSourceType(for: atom)
        return sourceType == .instagram || sourceType == .instagramReel
            || sourceType == .instagramPost || sourceType == .instagramCarousel
    }

    func extractVideoId(from atom: Atom) -> String? {
        if let vid = atom.richContent?.videoId, !vid.isEmpty { return vid }
        guard let url = atom.url else { return nil }
        if let match = url.range(of: #"(?:v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})"#, options: .regularExpression) {
            return String(String(url[match]).suffix(11))
        }
        return nil
    }

    func extractThumbnailUrl(from atom: Atom?) -> String? {
        guard let atom else { return nil }
        if let metadataStr = atom.metadata,
           let data = metadataStr.data(using: .utf8),
           let meta = try? JSONDecoder().decode(ResearchMetadata.self, from: data),
           let url = meta.thumbnailUrl, !url.isEmpty {
            return url
        }
        if let url = atom.richContent?.thumbnailUrl, !url.isEmpty { return url }
        if let videoId = extractVideoId(from: atom) {
            return "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
        }
        return nil
    }

    func sourceDescriptor(for atom: Atom) -> String {
        switch detectSourceType(for: atom) {
        case .youtube: return "YouTube"
        case .youtubeShort: return "YouTube Short"
        case .instagramReel: return "Instagram Reel"
        case .instagramPost: return "Instagram Post"
        case .instagramCarousel: return "Instagram Carousel"
        case .instagram: return "Instagram"
        default: return "Captured source"
        }
    }

    func openInstagramURLInPane(_ url: URL) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            userInfo: ["url": url, "title": "Instagram"]
        )
    }

    func openLinkedCreator() {
        guard let creatorUUID = analysis?.creatorUUID, !creatorUUID.isEmpty else { return }
        NotificationCenter.default.post(
            name: Notification.Name("openCreatorProfile"),
            object: nil,
            userInfo: ["creatorUUID": creatorUUID]
        )
    }

    // MARK: - Load

    func loadAtom(using sourceAtom: Atom) {
        resetLoadedAtomState()
        acquireLock(for: sourceAtom.uuid)
        currentAtom = sourceAtom
        scheduleSlideEditorActivation()
        personalNotes = extractPersonalNotes(from: sourceAtom)
        loadCommentsFromAtom(sourceAtom)
        SwipeStudySession.shared.syncPointer(to: sourceAtom.id ?? -1)

        // Load existing transcript — richContent.transcript first, then body
        // (which may be a JSON TranscriptSegment array from the Research flow).
        if let transcript = sourceAtom.richContent?.transcript, !transcript.isEmpty {
            transcriptText = transcript
        } else if let body = sourceAtom.body, !body.isEmpty {
            if let data = body.data(using: .utf8),
               let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
                transcriptText = segments.map(\.text).joined(separator: " ")
            } else {
                transcriptText = body
            }
        } else {
            transcriptText = ""
        }

        // Slide transcript: swipeAnalysis is the source of truth (it survives
        // analysis rewrites); the prose is only a fallback. One decode for the
        // whole load — this runs on the main actor during the entrance
        // animation.
        let savedAnalysis = sourceAtom.swipeAnalysis
        hydrateTranscriptState(from: savedAnalysis, fallbackTranscript: transcriptText)
        instagramTranscript = transcriptText

        if let savedComments = savedAnalysis?.transcriptComments, !savedComments.isEmpty {
            transcriptComments = savedComments
        }

        // Register the Cosmo window context provider for this swipe.
        publishContextProvider()

        // Analysis: a fully-analyzed swipe shows its cached analysis instantly —
        // never a surprise model call on open. Anything else runs one insight
        // pass once a transcript exists.
        let cached = savedAnalysis
        if let cached, cached.isFullyAnalyzed {
            analysis = cached
            withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
            markStudiedIfNeeded()
            Task { await fetchYouTubeTranscriptIfMissing() }
            return
        }

        withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
        Task {
            await fetchYouTubeTranscriptIfMissing()
            // Railway-first on the OPEN path too: while the cloud worker is
            // ACTIVELY on this swipe (fresh claim, pending inside the grace
            // window, or a scheduled retry), the Mac must not fire a duplicate
            // model call — it waits for the worker's result to sync down.
            // A swipe the cloud ABANDONED (needs_manual_retry, exhausted
            // partial) must not be polled — nothing is coming. If it banked a
            // transcript, a cheap local insight pass finishes the job here;
            // vision is never re-bought on this path.
            if cloudActivelyProcessing(displayAtom) {
                pollForBackgroundCompletion()
            } else {
                let hasText = !slidesTranscriptText.isEmpty || !transcriptText.isEmpty
                if hasText {
                    await runInsightPass(context: "loadAtom")
                }
            }
            markStudiedIfNeeded()
        }
    }

    /// True while the Railway worker still owns this swipe's processing —
    /// the same gate `SwipeProcessingService.transcribe` applies, applied
    /// here so the Study view's own auto-transcribe/analyze paths defer too.
    private func cloudOwnsProcessing(_ atom: Atom) -> Bool {
        !SwipeProcessingService.macMayProcess(
            metadataJSON: atom.metadata,
            updatedAt: ISO8601.date(from: atom.updatedAt)
        )
    }

    /// "Owns" vs "is actively working": macMayProcess returns false BOTH for
    /// swipes the cloud is actively processing AND for swipes it retired
    /// (needs_manual_retry / exhausted retries). Conflating the two made the
    /// Study open path poll a dead swipe for 8 minutes while the local
    /// self-heal never fired. Active = owned AND a result is still coming.
    private func cloudActivelyProcessing(_ atom: Atom) -> Bool {
        cloudOwnsProcessing(atom) && !Self.awaitsManualRetry(atom)
    }

    private func markStudiedIfNeeded() {
        // Capture the target NOW — the persist runs later on a Task, by which
        // time navigation may have re-pointed displayAtom at another swipe.
        let targetUUID = displayAtom.uuid
        guard let current = analysis ?? currentAtom?.swipeAnalysis else {
            // No analysis yet — studying still counts.
            var fresh = SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
            fresh = fresh.markingStudied()
            analysis = fresh
            Task { await persistAnalysis(fresh, toAtomWithUUID: targetUUID, context: "markStudied") }
            recordStudyTasteSignal(analysis: nil)
            return
        }
        guard current.studiedAt == nil else { return }
        let studied = current.markingStudied()
        analysis = studied
        Task { await persistAnalysis(studied, toAtomWithUUID: targetUUID, context: "markStudied") }
        recordStudyTasteSignal(analysis: studied)
    }

    /// What the user chooses to study is a taste signal: it tells the
    /// distiller which formats and hooks they gravitate toward.
    private func recordStudyTasteSignal(analysis: SwipeAnalysis?) {
        let title = displayAtom.title ?? "Untitled swipe"
        var parts = ["Studied swipe: \(title)"]
        if let format = analysis?.swipeContentFormat?.rawValue {
            parts.append("format: \(format)")
        }
        if let hook = analysis?.hookText, !hook.isEmpty {
            parts.append("hook: \(String(hook.prefix(120)))")
        }
        let content = parts.joined(separator: " — ")
        Task { await TasteStore.record(kind: .swipeStudy, clientUuid: nil, content: content) }
    }

    private func fetchYouTubeTranscriptIfMissing() async {
        let atom = displayAtom
        let sourceType = detectSourceType(for: atom)
        guard sourceType == .youtube || sourceType == .youtubeShort,
              transcriptText.isEmpty,
              let videoId = extractVideoId(from: atom) else { return }
        await fetchTranscript(videoId: videoId)
    }

    private func resetLoadedAtomState() {
        // Flush debounced edits BEFORE tearing the state down — cancelling the
        // save tasks without flushing dropped up to 2s of edits on swipe switch.
        flushPendingDebouncedSavesSync()
        hasPendingSlideEdits = false
        hasPendingCommentEdits = false
        pendingTranscriptText = nil

        slideEditorActivationTask?.cancel()
        slideEditorsActive = false
        analysis = nil
        isAnalyzing = false
        personalNotes = ""
        transcriptComments = []
        newCommentText = ""
        activeCommentSlideIndex = nil
        isPlayerActive = false
        currentTimestamp = 0
        videoDuration = 0
        instagramTranscript = ""
        transcriptText = ""
        isFetchingTranscript = false
        transcriptFetchFailed = false
        transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
        rawTranscriptSlides = []
        transcriptSpeechSegments = []
        transcriptionQuality = nil
        transcriptionWarnings = []
        showRawTranscript = false
        slideFocusRequestID = nil
        isAutoTranscribing = false
        autoTranscriptionProgress = ""
        autoTranscriptionContentType = nil
        copiedTranscript = false
        carouselCurrentIndex = 0
        isCarouselContent = false
        reclassifySuggestion = nil
        isReclassifying = false

        igPlayer?.pause()
        igPlayer = nil
        igIsExtractingVideo = false
        igVideoFailed = false
        igMediaData = nil
    }

    // MARK: - Navigation (study queue + sibling jumps)

    func goPrevious() {
        guard let id = SwipeStudySession.shared.stepPrevious() else { return }
        reloadWithEntity(id)
    }

    func goNext() {
        guard let id = SwipeStudySession.shared.stepNext() else { return }
        reloadWithEntity(id)
    }

    func reloadWithEntity(_ newEntityId: Int64) {
        hasAppeared = false
        resetLoadedAtomState()
        currentAtom = nil

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            if let fetched = try? await AtomRepository.shared.fetch(id: newEntityId) {
                loadAtom(using: fetched)
            }
        }
    }

    // MARK: - Cosmo context provider

    /// Pane-context gate: an inactive pane must not stomp the Cosmo window's
    /// context. The view keeps this in sync with its environment.
    var contextPublishingEnabled = true
    private var publishedContextProvider: SwipeStudyContextProvider?

    func publishContextProvider() {
        guard contextPublishingEnabled else { return }
        let provider = SwipeStudyContextProvider(
            atom: displayAtom,
            analysisRef: { [weak self] in self?.analysis },
            transcriptRef: { [weak self] in
                guard let self else { return "" }
                return self.transcriptText.isEmpty ? self.instagramTranscript : self.transcriptText
            }
        )
        publishedContextProvider = provider
        CosmoWindowViewModel.shared.updateContext(provider: provider)
    }

    // MARK: - Insight pass (single-call analysis)

    /// Run the insight engine on the current atom and persist the result with
    /// live editor state + curated fields intact.
    ///
    /// LEAKAGE INVARIANT: the result is persisted onto `atomForAnalysis.uuid`
    /// and NOTHING else. The old code persisted onto `displayAtom`, which
    /// follows navigation (and falls back to `initialAtom` during the reload
    /// window) — a stale pass finishing mid-navigation durably wrote one
    /// swipe's analysis onto a completely different swipe's row.
    func runInsightPass(context: String) async {
        guard !isAnalyzing else { return }
        let atomForAnalysis = displayAtom
        let existingAnalysis = atomForAnalysis.swipeAnalysis
        isAnalyzing = true
        defer { isAnalyzing = false }

        let result = await SwipeInsightEngine.shared.analyze(atom: atomForAnalysis)
        guard result.isFullyAnalyzed else { return }

        guard isViewingAtom(uuid: atomForAnalysis.uuid) else {
            // Navigated away mid-pass: the (expensive) analysis still belongs
            // to the atom it was computed FOR — persist it there from its
            // live row, and leave every piece of view state alone.
            await persistAnalysisToBackgroundAtom(
                result, uuid: atomForAnalysis.uuid, context: context
            )
            return
        }

        // Stamp LIVE editor state (not a pre-await capture) and carry curated
        // fields forward — the model call takes seconds and the user may have
        // edited slides/comments while it ran.
        var enriched = applyingLiveTranscriptState(to: result)
            .preservingCuratedFields(from: existingAnalysis)
        if analysis?.studiedAt != nil || existingAnalysis?.studiedAt != nil {
            enriched.studiedAt = enriched.studiedAt ?? analysis?.studiedAt ?? existingAnalysis?.studiedAt
        }
        withAnimation(ProMotionSprings.snappy) {
            analysis = enriched
        }
        await persistAnalysis(enriched, toAtomWithUUID: atomForAnalysis.uuid, context: context)
        SwipePatternStore.shared.markPendingWeave(atomForAnalysis.uuid)

        // Fresh displayTitle → keep the library headline in sync.
        if var current = currentAtom, current.uuid == atomForAnalysis.uuid,
           let title = enriched.displayTitle, !title.isEmpty, current.title != title {
            current.title = title
            var rc = current.richContent ?? ResearchRichContent()
            rc.title = title
            current.setRichContent(rc)
            do {
                let saved = try await AtomRepository.shared.update(current)
                if isViewingAtom(uuid: atomForAnalysis.uuid) {
                    currentAtom = saved
                }
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.updateDisplayTitle(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        }

        NotificationCenter.default.post(
            name: .researchCreated, object: nil,
            userInfo: ["uuid": atomForAnalysis.uuid]
        )
    }

    /// Persist an insight result for an atom the user has navigated away
    /// from. Fetches the live row so curated fields, transcript artifacts,
    /// study state, and the headline all land on the RIGHT atom.
    private func persistAnalysisToBackgroundAtom(
        _ result: SwipeAnalysis, uuid: String, context: String
    ) async {
        guard let fresh = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        let merged = result.preservingCuratedFields(from: fresh.swipeAnalysis)
        var updated = fresh.withSwipeAnalysis(merged)
        // Same complete-stamp as persistAnalysis — a healed swipe must not
        // keep advertising a terminal failure status.
        if merged.isFullyAnalyzed,
           Self.hasTranscriptContent(merged),
           updated.processingStatus != "complete" {
            updated.processingStatus = "complete"
        }
        if let title = merged.displayTitle, !title.isEmpty, updated.title != title,
           !AtomRepository.shared.isBeingEdited(uuid) {
            updated.title = title
            var rc = updated.richContent ?? ResearchRichContent()
            rc.title = title
            updated.setRichContent(rc)
        }
        do {
            _ = try await AtomRepository.shared.update(updated)
            SwipePatternStore.shared.markPendingWeave(uuid)
            NotificationCenter.default.post(
                name: .researchCreated, object: nil, userInfo: ["uuid": uuid]
            )
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeStudy.\(context).background(\(uuid.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    /// Explicit user action: save the live transcript onto the atom, then run
    /// the insight pass. Replaces the old two-phase NLP + classification flow.
    func reanalyze() {
        let text: String = {
            let slides = slidesTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !slides.isEmpty { return slides }
            let transcript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty { return transcript }
            return instagramTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !text.isEmpty else { return }

        transcriptText = text
        instagramTranscript = text

        Task {
            var atomForAnalysis = displayAtom
            atomForAnalysis.body = text
            atomForAnalysis.processingStatus = "complete"

            var richContent = atomForAnalysis.richContent ?? ResearchRichContent()
            richContent.transcript = text
            richContent.transcriptStatus = "available"
            if let hook = canonicalHookFromSlides() {
                atomForAnalysis.hook = String(hook.prefix(200))
            }
            atomForAnalysis.setRichContent(richContent)
            do {
                currentAtom = try await AtomRepository.shared.update(atomForAnalysis)
            } catch {
                currentAtom = atomForAnalysis
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.reanalyze(\(atomForAnalysis.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }

            await runInsightPass(context: "reanalyze")
        }
    }

    /// Stamp the CURRENT MainActor transcript editor state onto an analysis
    /// just before persisting.
    private func applyingLiveTranscriptState(to analysis: SwipeAnalysis) -> SwipeAnalysis {
        var copy = analysis
        // Speech tier: the live slide lists are blank placeholders, not content.
        // Stamping them would write a phantom slide over the worker's
        // deliberately-empty list and make the swipe read as slide-transcribed.
        if !showsSpeechTranscript {
            copy.transcriptSlides = transcriptSlides
            copy.rawTranscriptSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
        }
        copy.transcriptSpeechSegments = transcriptSpeechSegments
        copy.transcriptionQuality = transcriptionQuality
        copy.transcriptionWarnings = transcriptionWarnings
        copy.transcriptComments = transcriptComments
        return copy
    }

    /// Persist an analysis onto the atom it belongs to — keyed by uuid
    /// captured at schedule time, NEVER by whatever `displayAtom` resolves to
    /// when the async write finally lands (navigation may have moved it, and
    /// during a reload it falls back to `initialAtom` — a different swipe).
    func persistAnalysis(_ analysisToSave: SwipeAnalysis, toAtomWithUUID uuid: String, context: String) async {
        let base: Atom
        if let current = currentAtom, current.uuid == uuid {
            base = current
        } else if let fetched = try? await AtomRepository.shared.fetch(uuid: uuid) {
            base = fetched
        } else {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeStudy.\(context)(\(uuid.prefix(8)))",
                detail: "atom not found for analysis persist"
            )
            return
        }
        var updated = base.withSwipeAnalysis(analysisToSave)
        // A fully-analyzed swipe with real transcript content IS complete —
        // clear any leftover terminal status (partial / extraction_failed /
        // needs_manual_retry) or "Couldn't fetch this post" keeps rendering
        // over a healthy, fully-processed swipe forever.
        if analysisToSave.isFullyAnalyzed,
           Self.hasTranscriptContent(analysisToSave),
           updated.processingStatus != "complete" {
            updated.processingStatus = "complete"
        }
        do {
            let saved = try await AtomRepository.shared.update(updated)
            if isViewingAtom(uuid: uuid) {
                currentAtom = saved
            }
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeStudy.\(context)(\(uuid.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    /// Real transcript content: at least one slide with text, or a speech
    /// segment. (Empty arrays mean a prior pass produced nothing.)
    static func hasTranscriptContent(_ analysis: SwipeAnalysis) -> Bool {
        if let slides = analysis.transcriptSlides,
           slides.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if let segments = analysis.transcriptSpeechSegments, !segments.isEmpty {
            return true
        }
        return false
    }

    // MARK: - YouTube transcript

    func fetchTranscript(videoId: String) async {
        isFetchingTranscript = true
        transcriptFetchFailed = false
        defer { isFetchingTranscript = false }

        if let segments = await YouTubeProcessor.shared.fetchCaptions(videoId: videoId) {
            let fullText = segments.map(\.text).joined(separator: " ")
            transcriptText = fullText

            let metadata = try? await YouTubeProcessor.shared.fetchMetadata(videoId: videoId)

            guard var current = currentAtom else { return }
            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = fullText
            richContent.transcriptStatus = "available"
            if let author = metadata?.channelName {
                richContent.author = author
            }
            if let title = metadata?.title, (current.title == nil || current.title == "YouTube Video") {
                current.title = title
            }
            current.setRichContent(richContent)
            current.body = segments.jsonString
            current.processingStatus = "complete"

            do {
                currentAtom = try await AtomRepository.shared.update(current)
            } catch {
                currentAtom = current
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.fetchTranscript(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        } else {
            transcriptFetchFailed = true
        }
    }

    func retryTranscriptFetch() {
        transcriptFetchFailed = false
        Task {
            await fetchYouTubeTranscriptIfMissing()
            if !transcriptText.isEmpty {
                await runInsightPass(context: "retryFetch")
            }
        }
    }

    func saveEditedTranscript() {
        let newTranscript = editTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTranscript.isEmpty else { return }

        showEditTranscript = false
        transcriptText = newTranscript

        Task {
            guard var current = currentAtom else { return }
            current.body = newTranscript
            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = newTranscript
            richContent.transcriptStatus = "available"
            current.setRichContent(richContent)
            do {
                currentAtom = try await AtomRepository.shared.update(current)
            } catch {
                currentAtom = current
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.saveEditedTranscript(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
            await runInsightPass(context: "editedTranscript")
        }
    }

    // MARK: - Delete

    func deleteSwipe() {
        let uuid = displayAtom.uuid
        Task {
            try? await SwipeFileEngine.shared.deleteSwipe(atomUUID: uuid)
            onClose()
        }
    }

    // MARK: - Reclassification (DETAILS section)

    func reclassifySwipe() {
        guard let atom = currentAtom else { return }
        isReclassifying = true
        reclassifySuggestion = nil

        Task {
            let result = await SwipeInsightEngine.shared.analyze(atom: atom)
            // A suggestion for swipe A must never surface on swipe B.
            guard isViewingAtom(uuid: atom.uuid) else { return }
            if result.isFullyAnalyzed {
                reclassifySuggestion = result
            }
            isReclassifying = false
        }
    }

    func acceptReclassification() {
        guard let suggestion = reclassifySuggestion,
              let current = analysis else { return }
        let targetUUID = displayAtom.uuid
        let merged = SwipeClassificationEngine.shared.mergeClassification(suggestion, into: current)
        analysis = merged
        Task { await persistAnalysis(merged, toAtomWithUUID: targetUUID, context: "acceptReclassification") }
        reclassifySuggestion = nil
    }

    func rejectReclassification() {
        reclassifySuggestion = nil
    }

    func saveTaxonomyOverride() {
        guard var current = analysis else { return }
        let targetUUID = displayAtom.uuid
        current.classificationSource = .aiOverridden
        current.classifiedAt = Date()
        analysis = current
        Task { await persistAnalysis(current, toAtomWithUUID: targetUUID, context: "taxonomyOverride") }
        // A hand-corrected classification is a strong taxonomy belief.
        let title = displayAtom.title ?? "Untitled swipe"
        let format = current.swipeContentFormat?.rawValue ?? "unclassified"
        Task {
            await TasteStore.record(
                kind: .swipeStudy,
                clientUuid: nil,
                content: "Corrected swipe classification: \(title) is a \(format)"
            )
        }
    }

    // MARK: - Slide helpers

    var slidesTranscriptText: String {
        transcriptSlides.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var displayedTranscriptSlides: [TranscriptSlide] {
        if showRawTranscript {
            let raw = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
            return raw.isEmpty ? [TranscriptSlide(text: "", slideNumber: 1)] : raw
        }
        return transcriptSlides
    }

    var shouldShowTranscriptionWarning: Bool {
        transcriptionQuality == .degraded || !transcriptionWarnings.isEmpty
    }

    var transcriptionWarningText: String {
        transcriptionWarnings.isEmpty
            ? "Transcript quality was degraded. Review the raw capture before editing."
            : transcriptionWarnings.joined(separator: " ")
    }

    /// The ONE place persisted transcript state becomes editor state — every
    /// load path (open, Instagram stage, cloud poll) goes through here so they
    /// can't drift into three different answers for the same swipe.
    ///
    /// The tier decision lives in `SwipeStudyTranscriptTier` (next to the
    /// preview rail's `resolve`, its GUARD-TWIN); this only applies it.
    /// The trap it closes: a talking-head reel banks its words as speech
    /// segments with a deliberately EMPTY slide list, and parsing its prose
    /// fallback into slide cards both fills `transcriptSlides` (so
    /// `slidesCarryText` flips true) and clears `transcriptSpeechSegments` —
    /// knocking the manuscript out of the speech tier the preview rail is
    /// happily showing. The prose is a fallback for swipes with NO analysis
    /// transcript, never a substitute for one.
    func hydrateTranscriptState(from analysis: SwipeAnalysis?, fallbackTranscript: String) {
        switch SwipeStudyTranscriptTier.resolve(analysis: analysis) {
        case .slides(let slides, let raw, let speech):
            transcriptSlides = slides
            rawTranscriptSlides = raw
            transcriptSpeechSegments = speech
        case .speech(let speech):
            // The slide lists stay the blank placeholder so
            // `showsSpeechTranscript` reads true and the manuscript renders
            // timestamped rows instead of empty slide editors.
            transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
            rawTranscriptSlides = transcriptSlides
            transcriptSpeechSegments = speech
        case .proseFallback:
            loadSlides(from: fallbackTranscript)
            return
        }
        transcriptionQuality = analysis?.transcriptionQuality
        transcriptionWarnings = analysis?.transcriptionWarnings ?? []
    }

    func loadSlides(from transcript: String) {
        guard !transcript.isEmpty else {
            transcriptSlides = [TranscriptSlide(text: "", slideNumber: 1)]
            rawTranscriptSlides = transcriptSlides
            transcriptSpeechSegments = []
            transcriptionQuality = nil
            transcriptionWarnings = []
            return
        }
        if let data = transcript.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TranscriptSlide].self, from: data) {
            transcriptSlides = decoded
            rawTranscriptSlides = decoded
            transcriptSpeechSegments = []
            transcriptionQuality = nil
            transcriptionWarnings = []
            cleanAllSlideLineBreaks()
            return
        }
        let parts = transcript.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if parts.count > 1 {
            transcriptSlides = parts.enumerated().map { i, text in
                TranscriptSlide(text: text, slideNumber: i + 1)
            }
        } else {
            transcriptSlides = [TranscriptSlide(text: transcript, slideNumber: 1)]
        }
        rawTranscriptSlides = transcriptSlides
        transcriptSpeechSegments = []
        transcriptionQuality = nil
        transcriptionWarnings = []
        cleanAllSlideLineBreaks()
    }

    func applyTranscriptionResult(_ result: TranscriptionResult) {
        transcriptSlides = result.cleanedSlides.isEmpty
            ? [TranscriptSlide(text: "", slideNumber: 1)] : result.cleanedSlides
        rawTranscriptSlides = result.rawSlides.isEmpty ? transcriptSlides : result.rawSlides
        transcriptSpeechSegments = result.speechSegments
        transcriptionQuality = result.quality
        transcriptionWarnings = result.warnings
        showRawTranscript = false
        cleanAllSlideLineBreaks()
    }

    /// Clean up mid-sentence line breaks in slide text while preserving list
    /// items, bullets, and lines after colons.
    func cleanSlideLineBreaks(_ text: String) -> String {
        var working = text
        working = working.replacingOccurrences(
            of: #"(%\s+)(?=[A-Z][a-z])"#, with: "%\n", options: .regularExpression
        )
        working = working.replacingOccurrences(
            of: #"(?<=\S)\s+- (?=[A-Z])"#, with: "\n- ", options: .regularExpression
        )

        let lines = working.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return working.trimmingCharacters(in: .whitespacesAndNewlines) }

        let bulletPattern = #"^[→▸►•·\-\*\+]\s"#
        let numberedPattern = #"^\d+[\.\)\-]\s"#

        var merged: [String] = [lines[0]]
        for i in 1..<lines.count {
            let prev = merged.last ?? ""
            let next = lines[i]
            let nextIsBullet = next.range(of: bulletPattern, options: .regularExpression) != nil
            let nextIsNumbered = next.range(of: numberedPattern, options: .regularExpression) != nil
            if nextIsBullet || nextIsNumbered {
                merged.append(next)
                continue
            }
            let lastChar = prev.last
            let endsWithPunctuation = lastChar == "." || lastChar == "!" || lastChar == "?" || prev.hasSuffix("…") || lastChar == ":"
            if prev.isEmpty || endsWithPunctuation {
                merged.append(next)
            } else {
                merged[merged.count - 1] = prev + " " + next
            }
        }
        return merged.joined(separator: "\n")
    }

    func cleanAllSlideLineBreaks() {
        for i in transcriptSlides.indices {
            transcriptSlides[i].text = cleanSlideLineBreaks(transcriptSlides[i].text)
        }
    }

    private func renumberSlides() {
        for i in transcriptSlides.indices {
            transcriptSlides[i].slideNumber = i + 1
        }
    }

    func indexForSlide(withID slideID: UUID) -> Int? {
        transcriptSlides.firstIndex { $0.id == slideID }
    }

    func bindingForSlideText(_ slideID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.transcriptSlides.first(where: { $0.id == slideID })?.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self, let index = self.indexForSlide(withID: slideID) else { return }
                self.transcriptSlides[index].text = String(newValue.prefix(TranscriptSlide.characterLimit))
                self.debounceSaveSlides()
            }
        )
    }

    func appendSlide() {
        // Creating a slide is an edit — promote the stand-ins so the focus
        // request has a real editor to land in.
        activateSlideEditors(focusing: nil)
        withAnimation(ProMotionSprings.snappy) {
            let newSlide = TranscriptSlide(text: "", slideNumber: transcriptSlides.count + 1)
            transcriptSlides.append(newSlide)
            slideFocusRequestID = newSlide.id
        }
        debounceSaveSlides()
    }

    func insertSlide(after slideID: UUID) {
        let insertionIndex = (indexForSlide(withID: slideID) ?? transcriptSlides.count - 1) + 1
        let newSlide = TranscriptSlide(text: "", slideNumber: insertionIndex + 1)
        withAnimation(ProMotionSprings.snappy) {
            transcriptSlides.insert(newSlide, at: min(insertionIndex, transcriptSlides.count))
            renumberSlides()
            slideFocusRequestID = newSlide.id
        }
        for i in transcriptComments.indices {
            if transcriptComments[i].startIndex >= insertionIndex {
                transcriptComments[i].startIndex += 1
                transcriptComments[i].endIndex += 1
            }
        }
        if let activeCommentSlideIndex, activeCommentSlideIndex >= insertionIndex {
            self.activeCommentSlideIndex = activeCommentSlideIndex + 1
        }
        debounceSaveSlides()
        debounceSaveComments()
    }

    func removeSlide(withID slideID: UUID) {
        guard let index = indexForSlide(withID: slideID) else { return }
        transcriptSlides.remove(at: index)
        renumberSlides()
        transcriptComments.removeAll { $0.startIndex == index }
        for i in transcriptComments.indices {
            if transcriptComments[i].startIndex > index {
                transcriptComments[i].startIndex -= 1
                transcriptComments[i].endIndex -= 1
            }
        }
        if slideFocusRequestID == slideID {
            slideFocusRequestID = nil
        }
        if let activeCommentSlideIndex {
            if activeCommentSlideIndex == index {
                self.activeCommentSlideIndex = nil
            } else if activeCommentSlideIndex > index {
                self.activeCommentSlideIndex = activeCommentSlideIndex - 1
            } else if activeCommentSlideIndex >= transcriptSlides.count {
                self.activeCommentSlideIndex = max(0, transcriptSlides.count - 1)
            }
        }
        debounceSaveSlides()
        debounceSaveComments()
    }

    func canonicalHookFromSlides() -> String? {
        for slide in transcriptSlides {
            let normalized = slide.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }

    func copyTranscript() {
        let formatted = displayedTranscriptSlides.map { slide in
            "Slide \(slide.slideNumber)\n\(slide.text)"
        }.joined(separator: "\n\n")
        let payload = formatted.isEmpty ? transcriptText : formatted
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copiedTranscript = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedTranscript = false
        }
    }

    // MARK: - Comments

    func commentsForSlide(_ slideIndex: Int) -> [TranscriptComment] {
        transcriptComments.filter { $0.startIndex == slideIndex }
    }

    func addComment(toSlide slideIndex: Int) {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let comment = TranscriptComment(startIndex: slideIndex, endIndex: slideIndex, text: text)
        withAnimation(ProMotionSprings.snappy) {
            transcriptComments.append(comment)
            newCommentText = ""
            activeCommentSlideIndex = nil
        }
        debounceSaveComments()
    }

    func deleteComment(_ comment: TranscriptComment) {
        transcriptComments.removeAll { $0.id == comment.id }
        debounceSaveComments()
    }

    func toggleCommentComposer(forSlide index: Int) {
        withAnimation(ProMotionSprings.snappy) {
            if activeCommentSlideIndex == index {
                activeCommentSlideIndex = nil
            } else {
                activeCommentSlideIndex = index
                newCommentText = ""
            }
        }
    }

    private func debounceSaveComments() {
        commentsSaveTask?.cancel()
        commentEditGeneration += 1
        hasPendingCommentEdits = true
        registerDirtyFlush()
        commentsSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, var current = self.currentAtom else { return }
            let generation = self.commentEditGeneration

            self.applyCommentEdits(to: &current)

            do {
                let saved = try await AtomRepository.shared.update(current)
                self.currentAtom = saved
                if self.commentEditGeneration == generation {
                    self.hasPendingCommentEdits = false
                    self.unregisterDirtyFlushIfIdle()
                }
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.saveComments(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        }
    }

    /// Apply pending inline-comment edits onto `current` (top-level structured
    /// key, read by loadCommentsFromAtom). Refuses — keeping the column — when
    /// existing structured is non-empty but unparseable: proceeding from an
    /// empty dict wiped autoMetadata/swipeAnalysis.
    private func applyCommentEdits(to current: inout Atom) {
        guard let data = try? JSONEncoder().encode(transcriptComments),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        var structuredDict: [String: Any] = [:]
        if let existingStr = current.structured, !existingStr.isEmpty {
            guard let existingData = existingStr.data(using: .utf8),
                  let existing = (try? JSONSerialization.jsonObject(with: existingData)) as? [String: Any] else {
                PersistenceHealth.note(
                    .decodeFailure,
                    context: "SwipeStudy.saveComments(\(current.uuid.prefix(8)))",
                    detail: "existing structured unparseable; refusing comment write that would drop its data"
                )
                return
            }
            structuredDict = existing
        }
        structuredDict["transcriptComments"] = jsonStr
        if let merged = try? JSONSerialization.data(withJSONObject: structuredDict),
           let mergedStr = String(data: merged, encoding: .utf8) {
            current.structured = mergedStr
        }
    }

    private func loadCommentsFromAtom(_ atom: Atom) {
        guard let structuredStr = atom.structured,
              let data = structuredStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commentsJsonStr = dict["transcriptComments"] as? String,
              let commentsData = commentsJsonStr.data(using: .utf8),
              let loaded = try? JSONDecoder().decode([TranscriptComment].self, from: commentsData)
        else {
            if !personalNotes.isEmpty {
                transcriptComments = [
                    TranscriptComment(startIndex: 0, endIndex: 0, text: personalNotes)
                ]
            }
            return
        }
        transcriptComments = loaded
    }

    func formatCommentDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func extractPersonalNotes(from atom: Atom) -> String {
        guard let metadataStr = atom.metadata,
              let data = metadataStr.data(using: .utf8),
              let meta = try? JSONDecoder().decode(ResearchMetadata.self, from: data) else { return "" }
        return meta.personalNotes ?? ""
    }

    // MARK: - Debounced saves + flush (DirtyEditorRegistry invariant)

    private var dirtyEditorID: String { "swipestudy-\(displayAtom.uuid)" }

    private var hasPendingDebouncedSaves: Bool {
        hasPendingSlideEdits || hasPendingCommentEdits || pendingTranscriptText != nil
    }

    private func registerDirtyFlush() {
        DirtyEditorRegistry.shared.register(id: dirtyEditorID) { [weak self] in
            self?.flushPendingDebouncedSavesSync()
        }
    }

    private func unregisterDirtyFlushIfIdle() {
        guard !hasPendingDebouncedSaves else { return }
        DirtyEditorRegistry.shared.unregister(id: dirtyEditorID)
    }

    /// Cancel pending debounce tasks and write their content NOW, synchronously
    /// (DB-only via updateSync). Runs on swipe switch, view close, and app quit —
    /// cancelling without flushing silently dropped up to 2s of edits.
    func flushPendingDebouncedSavesSync() {
        transcriptSaveTask?.cancel()
        slidesSaveTask?.cancel()
        commentsSaveTask?.cancel()
        transcriptSaveTask = nil
        slidesSaveTask = nil
        commentsSaveTask = nil
        defer { DirtyEditorRegistry.shared.unregister(id: dirtyEditorID) }
        guard hasPendingDebouncedSaves, var current = currentAtom else { return }

        if hasPendingSlideEdits {
            applySlideTranscriptEdits(to: &current, markUserEdited: true)
            mirrorSlideTextIntoTranscriptFields()
        }
        if let pending = pendingTranscriptText {
            var richContent = current.richContent ?? ResearchRichContent()
            richContent.transcript = pending
            current.setRichContent(richContent)
            if !pending.isEmpty {
                current.body = pending
            }
        }
        if hasPendingCommentEdits, !hasPendingSlideEdits {
            applyCommentEdits(to: &current)
        }

        do {
            currentAtom = try AtomRepository.shared.updateSync(current)
            hasPendingSlideEdits = false
            hasPendingCommentEdits = false
            pendingTranscriptText = nil
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeStudy.flushPendingSaves(\(current.uuid.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    func debounceSaveSlides() {
        slidesSaveTask?.cancel()
        slideEditGeneration += 1
        hasPendingSlideEdits = true
        registerDirtyFlush()
        slidesSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveSlideTranscript()
        }
    }

    /// Apply the current slide/transcript/comment editor state onto `current`.
    /// Shared by the async saves and the synchronous flush so they can't drift.
    /// `markUserEdited` is set ONLY by the manual-edit path: the flag is
    /// terminal and tells auto-transcription to never re-run for this swipe.
    private func applySlideTranscriptEdits(to current: inout Atom, markUserEdited: Bool) {
        let combined = slidesTranscriptText
        var richContent = current.richContent ?? ResearchRichContent()
        // The slide list is the transcript of record ONLY when it carries text.
        // On the speech tier (talking-head reel) the slides are a blank
        // placeholder, and joining them would erase the spoken transcript from
        // body/richContent — the words the speech rows are rendered from.
        if !showsSpeechTranscript {
            current.body = combined
            richContent.transcript = combined
            richContent.transcriptStatus = "available"
        }
        if let hook = canonicalHookFromSlides() {
            current.hook = String(hook.prefix(200))
            // The library headline stays the short displayTitle when one
            // exists; only hook-derived titles track the edited first slide.
            if current.swipeAnalysis?.displayTitle == nil {
                current.title = String(hook.prefix(120))
                richContent.title = String(hook.prefix(120))
            }
        }
        current.setRichContent(richContent)

        var sa = current.swipeAnalysis ?? SwipeAnalysis(analysisVersion: 0, isFullyAnalyzed: false)
        if let hook = canonicalHookFromSlides() {
            sa.hookText = String(hook.prefix(500))
        }
        if !showsSpeechTranscript {
            sa.transcriptSlides = transcriptSlides
            sa.rawTranscriptSlides = rawTranscriptSlides.isEmpty ? transcriptSlides : rawTranscriptSlides
        }
        sa.transcriptSpeechSegments = transcriptSpeechSegments
        sa.transcriptionQuality = transcriptionQuality
        sa.transcriptionWarnings = transcriptionWarnings
        sa.transcriptComments = transcriptComments
        if markUserEdited {
            sa.transcriptEditedByUser = true
        }
        current = current.withSwipeAnalysis(sa)
    }

    /// Mirror the just-saved slide text into the in-memory transcript fields.
    /// A no-op on the speech tier, where the slides are placeholders and the
    /// prose the speech rows were built from has to survive the save.
    private func mirrorSlideTextIntoTranscriptFields() {
        guard !showsSpeechTranscript else { return }
        transcriptText = slidesTranscriptText
        instagramTranscript = slidesTranscriptText
    }

    /// Fire-and-forget save — used from debounced manual edits.
    /// Marks the transcript user-edited (terminal for auto-transcription).
    func saveSlideTranscript() {
        guard var current = currentAtom else { return }
        applySlideTranscriptEdits(to: &current, markUserEdited: true)
        let generation = slideEditGeneration

        mirrorSlideTextIntoTranscriptFields()
        currentAtom = current
        Task { [weak self] in
            do {
                let saved = try await AtomRepository.shared.update(current)
                guard let self else { return }
                self.currentAtom = saved
                if self.slideEditGeneration == generation {
                    self.hasPendingSlideEdits = false
                    self.unregisterDirtyFlushIfIdle()
                }
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.saveSlideTranscript(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        }
    }

    /// Awaitable save — used from autoTranscribe to guarantee the write
    /// completes before analysis starts. Machine path: never marks user-edited.
    func saveSlideTranscriptAsync() async {
        guard var current = currentAtom else { return }
        applySlideTranscriptEdits(to: &current, markUserEdited: false)

        mirrorSlideTextIntoTranscriptFields()
        currentAtom = current

        do {
            currentAtom = try await AtomRepository.shared.update(current)
        } catch {
            PersistenceHealth.note(
                .writeFailure,
                context: "SwipeStudy.saveSlideTranscriptAsync(\(current.uuid.prefix(8)))",
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Instagram media pipeline

    func isPostURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains("/p/") && !lower.contains("/reel/")
    }

    func contentTypeLabel(atom: Atom) -> String {
        if isCarouselContent { return "Carousel" }
        if let url = atom.url?.lowercased(), url.contains("/p/") { return "Post" }
        return "Reel"
    }

    func currentInstagramShortcode() -> String? {
        guard let urlString = displayAtom.url, let url = URL(string: urlString) else { return nil }
        return InstagramExtractor.shared.extractShortcode(from: url)
    }

    /// Called by the stage pane when an Instagram swipe appears. Loads stored
    /// slides, pre-detects carousel content, and kicks extraction once.
    func prepareInstagramStage() {
        let atom = displayAtom
        instagramTranscript = atom.richContent?.transcript ?? ""
        hydrateTranscriptState(
            from: atom.swipeAnalysis,
            fallbackTranscript: atom.richContent?.transcript ?? ""
        )
        // Pre-detect carousel/post from URL pattern (avoids "loading video"
        // flash). Only the URL — sourceType can be stale.
        if let url = atom.url?.lowercased(), url.contains("/p/") && !url.contains("/reel/") {
            isCarouselContent = true
        }
        if igPlayer == nil {
            extractInstagramVideo(atom: atom)
        }
    }

    func extractInstagramVideo(atom: Atom) {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true
        isUpgradingCarousel = false

        Task {
            let expectedUUID = atom.uuid
            guard let urlString = atom.url, let url = URL(string: urlString) else {
                if isViewingAtom(uuid: expectedUUID) {
                    igVideoFailed = true
                    igIsExtractingVideo = false
                }
                return
            }

            guard isViewingAtom(uuid: expectedUUID) else { return }

            let shortcode = InstagramExtractor.shared.extractShortcode(from: url)

            // Durable-mirror fast path: the cloud worker mirrors every carousel
            // page into Supabase storage (`carouselImageStorageURLs`) — the same
            // copies iOS renders instantly. When the local slide list is missing
            // or shorter (worker-processed swipe that never stored rich-content
            // items on this Mac), rebuild it from the mirror instead of running
            // a live Instagram extraction against a rotting CDN link.
            let storedItemCount = atom.richContent?.instagramData?.carouselItems?.count ?? 0
            if isPostURL(urlString),
               let mirrorItems = SwipeCarouselCloudMirror.mirroredCarouselItems(from: atom.metadata),
               mirrorItems.count > storedItemCount {
                isCarouselContent = true
                let mirrorMedia = InstagramMediaData(
                    originalURL: url,
                    contentType: mirrorItems.count == 1 ? .image : .carousel,
                    videoURL: nil,
                    thumbnailURL: atom.thumbnailUrl.flatMap(URL.init(string:))
                        ?? atom.richContent?.thumbnailUrl.flatMap(URL.init(string:))
                        ?? mirrorItems.first?.mediaURL,
                    duration: nil,
                    authorUsername: atom.richContent?.instagramData?.authorUsername,
                    caption: atom.richContent?.instagramData?.caption,
                    carouselItems: mirrorItems,
                    expectedCarouselItemCount: mirrorItems.count,
                    extractedAt: Date()
                )
                igMediaData = mirrorMedia
                carouselCurrentIndex = min(carouselCurrentIndex, mirrorItems.count - 1)
                igIsExtractingVideo = false
                await persistInstagramMediaToAtom(mirrorMedia, expectedAtomUUID: expectedUUID)
                await handleCarouselTranscription(items: mirrorItems, expectedUUID: expectedUUID)
                return
            }

            // Fast path: stored carousel items (regardless of content-type label).
            if let storedIGData = atom.richContent?.instagramData,
               let items = storedIGData.carouselItems, !items.isEmpty {
                isCarouselContent = true
                let storedMediaData = InstagramMediaData(
                    originalURL: url,
                    contentType: storedIGData.contentType,
                    videoURL: storedIGData.extractedMediaURL,
                    thumbnailURL: atom.thumbnailUrl.flatMap(URL.init(string:))
                        ?? atom.richContent?.thumbnailUrl.flatMap(URL.init(string:)),
                    duration: nil,
                    authorUsername: storedIGData.authorUsername,
                    caption: storedIGData.caption,
                    carouselItems: items,
                    expectedCarouselItemCount: storedIGData.expectedCarouselItemCount,
                    extractedAt: storedIGData.extractedAt ?? Date()
                )
                igMediaData = storedMediaData
                carouselCurrentIndex = min(carouselCurrentIndex, items.count - 1)

                if !InstagramMediaResolution.isIncompletePostMedia(
                    mediaData: storedMediaData,
                    sourceURL: url
                ) {
                    igIsExtractingVideo = false
                    await handleCarouselTranscription(items: items, expectedUUID: expectedUUID)
                    return
                }
                isUpgradingCarousel = true
            }

            // Fast path: cached local video — skip extraction entirely.
            if let shortcode, let localURL = InstagramVideoLocalCache.localVideoURL(forShortcode: shortcode) {
                guard isViewingAtom(uuid: expectedUUID) else { return }
                isCarouselContent = false
                setupIGPlayer(videoURL: localURL)

                if shouldAutoTranscribe() {
                    await autoTranscribe(videoURL: localURL, duration: videoDuration > 0 ? videoDuration : 60)
                } else if SwipeProcessingService.shared.isProcessing(uuid: displayAtom.uuid) || cloudOwnsProcessing(displayAtom) {
                    pollForBackgroundCompletion()
                }

                igIsExtractingVideo = false
                return
            }

            // Slow path: live extraction.
            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }

                if let caption = mediaData.caption, !caption.isEmpty,
                   displayAtom.richContent?.instagramData?.caption == nil {
                    persistCaptionToAtom(caption, expectedAtomUUID: expectedUUID)
                }

                if InstagramMediaResolution.isIncompletePostMedia(
                    mediaData: mediaData,
                    sourceURL: url
                ) {
                    isCarouselContent = true
                    igIsExtractingVideo = false
                    await showPartialAndUpgrade(liveMedia: mediaData)
                    return
                }

                isUpgradingCarousel = false
                igMediaData = mediaData
                if let items = mediaData.carouselItems, !items.isEmpty {
                    carouselCurrentIndex = min(carouselCurrentIndex, items.count - 1)
                }
                await persistInstagramMediaToAtom(mediaData, expectedAtomUUID: expectedUUID)

                if let items = mediaData.carouselItems, !items.isEmpty {
                    isCarouselContent = true
                    igIsExtractingVideo = false
                    await handleCarouselTranscription(items: items, expectedUUID: expectedUUID)
                    return
                }

                if let videoURL = mediaData.videoURL {
                    isCarouselContent = false
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL, shortcode: shortcode)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    setupIGPlayer(videoURL: playableURL)
                    if let dur = mediaData.duration {
                        videoDuration = dur
                    }

                    if shouldAutoTranscribe() {
                        guard isViewingAtom(uuid: expectedUUID) else { return }
                        await autoTranscribe(videoURL: playableURL, duration: mediaData.duration ?? 60)
                    } else if SwipeProcessingService.shared.isProcessing(uuid: displayAtom.uuid) || cloudOwnsProcessing(displayAtom) {
                        pollForBackgroundCompletion()
                    }
                } else if let thumbnailURL = mediaData.thumbnailURL,
                          InstagramMediaResolution.shouldUseThumbnailFallback(
                            mediaData: mediaData,
                            sourceURL: url
                          ) {
                    // Image post — show as single-image carousel.
                    let singleItem = CarouselItem(index: 0, mediaType: .image, mediaURL: thumbnailURL)
                    igMediaData = InstagramMediaData(
                        originalURL: mediaData.originalURL,
                        contentType: .carousel,
                        videoURL: nil,
                        thumbnailURL: thumbnailURL,
                        duration: nil,
                        authorUsername: mediaData.authorUsername,
                        caption: mediaData.caption,
                        carouselItems: [singleItem],
                        expectedCarouselItemCount: mediaData.expectedCarouselItemCount,
                        extractedAt: mediaData.extractedAt
                    )
                    isCarouselContent = true

                    if shouldAutoTranscribe() {
                        guard isViewingAtom(uuid: expectedUUID) else { return }
                        await autoTranscribeCarousel(items: [singleItem])
                    }
                } else if isPostURL(urlString) {
                    isCarouselContent = true
                } else {
                    igVideoFailed = true
                }
            } catch {
                guard isViewingAtom(uuid: expectedUUID) else { return }
                print("SwipeStudy: Instagram video extraction failed: \(error)")
                if isPostURL(urlString) {
                    isCarouselContent = true
                } else {
                    igVideoFailed = true
                }
            }

            igIsExtractingVideo = false
        }
    }

    /// The auto-transcribe gate: only when nothing user-visible exists yet and
    /// the background processor isn't already on it.
    private func shouldAutoTranscribe() -> Bool {
        let hasSlideContent = transcriptSlides.contains { !$0.text.isEmpty }
        let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSavedBody = !(displayAtom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTranscriptStatus = displayAtom.richContent?.transcriptStatus == "available"
        let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: displayAtom.uuid)
        let cloudOwns = cloudOwnsProcessing(displayAtom)
        return !hasSlideContent && !hasTranscript && !hasSavedBody && !hasTranscriptStatus
            && !isBackgroundProcessing && !cloudOwns
    }

    /// Decide whether a displayed carousel still needs (re-)transcription.
    /// A user-edited transcript is terminal — never auto re-transcribe over it.
    private func handleCarouselTranscription(items: [CarouselItem], expectedUUID: String) async {
        let existingSlideCount = transcriptSlides.filter { !$0.text.isEmpty }.count
        let isBackgroundProcessing = SwipeProcessingService.shared.isProcessing(uuid: displayAtom.uuid)
        let cloudOwns = cloudOwnsProcessing(displayAtom)

        let needsInitialTranscription = shouldAutoTranscribe()

        let userEditedTranscript = displayAtom.swipeAnalysis?.transcriptEditedByUser == true
        let hasMoreSlides = items.count > existingSlideCount && existingSlideCount > 0
        let isDegraded = displayAtom.swipeAnalysis?.transcriptionQuality == .degraded
        let needsReTranscription = (hasMoreSlides || isDegraded)
            && !isBackgroundProcessing && !cloudOwns && !userEditedTranscript

        if needsInitialTranscription || needsReTranscription {
            guard isViewingAtom(uuid: expectedUUID) else { return }
            await autoTranscribeCarousel(items: items)
        } else if isBackgroundProcessing || cloudOwns {
            pollForBackgroundCompletion()
        }
    }

    /// Show the best media we currently have and upgrade toward the full
    /// carousel in the background. Never downgrades; never dead-ends when ≥1
    /// slide exists.
    /// - Parameter userInitiated: true when this came from an explicit Retry.
    ///   A retired swipe (`needs_manual_retry`) is deliberately inert on the
    ///   automatic path, so the Retry control must say so or it is a no-op.
    private func showPartialAndUpgrade(liveMedia: InstagramMediaData, userInitiated: Bool = false) async {
        let liveItems = liveMedia.carouselItems ?? []
        let shownItems = igMediaData?.carouselItems ?? []
        let shownIsDisplayable = igMediaData.map { InstagramMediaResolution.isDisplayablePostMedia(mediaData: $0) } ?? false
        let liveIsDisplayable = InstagramMediaResolution.isDisplayablePostMedia(mediaData: liveMedia)

        if liveIsDisplayable && (liveItems.count >= shownItems.count || !shownIsDisplayable) {
            igMediaData = liveMedia
            if !liveItems.isEmpty {
                carouselCurrentIndex = min(carouselCurrentIndex, liveItems.count - 1)
            }
        }

        let hasDisplayable = igMediaData.map { InstagramMediaResolution.isDisplayablePostMedia(mediaData: $0) } ?? false
        isUpgradingCarousel = hasDisplayable
        if !hasDisplayable {
            igMediaData = nil
        }

        let currentUUID = displayAtom.uuid
        // Merely LOOKING at a half-loaded carousel must not buy a full extraction
        // pass. Once a swipe has been retired to needs_manual_retry, the upgrade
        // is the Retry control's job — otherwise browsing the swipe file
        // re-triggers the exact spend the capture-window bound was added to stop.
        if !SwipeProcessingService.shared.isProcessing(uuid: currentUUID),
           userInitiated || !Self.awaitsManualRetry(displayAtom) {
            SwipeProcessingService.shared.processSwipeInBackground(
                uuid: currentUUID,
                forceExtractionRetry: true
            )
        }
        pollForBackgroundCompletion()
    }

    func carouselUpgradeHintText(loadedCount: Int) -> String {
        if let expected = igMediaData?.expectedCarouselItemCount, expected > loadedCount {
            return "Loading more slides… (\(loadedCount) of \(expected))"
        }
        return "Loading more slides…"
    }

    private func pollForBackgroundCompletion() {
        guard !isAutoTranscribing else { return }
        autoTranscriptionProgress = "Processing in background…"
        isAutoTranscribing = true

        Task { [weak self] in
            guard let self else { return }
            let uuid = self.displayAtom.uuid
            // Wait for BOTH tiers: the Mac's own background pass AND the
            // Railway worker (whose result arrives via sync). Bounded — a
            // worker that dies mid-swipe releases ownership via the stale-
            // claim window, at which point the loop exits and the local
            // fallback below can step in.
            let deadline = Date().addingTimeInterval(8 * 60)
            while Date() < deadline {
                if SwipeProcessingService.shared.isProcessing(uuid: uuid) {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                guard let row = try? await AtomRepository.shared.fetch(uuid: uuid) else { break }
                // Keep the status line honest while the cloud works.
                if self.isViewingAtom(uuid: uuid),
                   self.currentAtom?.processingStatus != row.processingStatus {
                    self.currentAtom = row
                }
                // Exit as soon as the cloud stops ACTIVELY working — including
                // when it retires the swipe mid-poll (needs_manual_retry).
                // Polling a retired swipe burned the full 8 minutes for nothing.
                guard self.cloudActivelyProcessing(row),
                      row.processingStatus != "complete" else { break }
                try? await Task.sleep(for: .seconds(3))
            }

            guard self.isViewingAtom(uuid: uuid) else { return }

            if let fresh = try? await AtomRepository.shared.fetch(uuid: uuid) {
                self.currentAtom = fresh
                if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                    self.transcriptText = transcript
                    self.instagramTranscript = transcript
                }
                if let urlString = fresh.url,
                   let url = URL(string: urlString),
                   let instagramData = fresh.richContent?.instagramData,
                   let items = instagramData.carouselItems,
                   !items.isEmpty {
                    self.igMediaData = InstagramMediaData(
                        originalURL: instagramData.originalURL,
                        contentType: .carousel,
                        videoURL: instagramData.extractedMediaURL,
                        thumbnailURL: URL(string: fresh.thumbnailUrl ?? "") ?? self.igMediaData?.thumbnailURL,
                        duration: self.igMediaData?.duration,
                        authorUsername: instagramData.authorUsername,
                        caption: instagramData.caption,
                        carouselItems: items,
                        expectedCarouselItemCount: instagramData.expectedCarouselItemCount,
                        extractedAt: instagramData.extractedAt ?? Date()
                    )
                    self.carouselCurrentIndex = min(self.carouselCurrentIndex, items.count - 1)
                    if url.path.lowercased().contains("/p/") {
                        self.isCarouselContent = true
                    }
                }
                if let sa = fresh.swipeAnalysis {
                    self.analysis = sa
                    // Only adopt an analysis that actually banked words — an
                    // empty one arriving mid-poll must not wipe what's on screen.
                    if Self.hasTranscriptContent(sa) {
                        self.hydrateTranscriptState(
                            from: sa,
                            fallbackTranscript: fresh.richContent?.transcript ?? ""
                        )
                        self.cleanAllSlideLineBreaks()
                    } else if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                        self.loadSlides(from: transcript)
                    }
                } else if let transcript = fresh.richContent?.transcript, !transcript.isEmpty {
                    self.loadSlides(from: transcript)
                }
                if fresh.richContent?.sourceType == .instagramCarousel {
                    self.isCarouselContent = true
                }
            }

            self.isUpgradingCarousel = false
            self.isAutoTranscribing = false
            self.autoTranscriptionProgress = ""

            // Self-heal: a transcript arrived but the analysis didn't (cloud
            // insight call failed, or the worker went quiet past its grace
            // window). Once the Mac is allowed to process, run the pass
            // locally instead of leaving the rail empty.
            let hasText = !self.slidesTranscriptText.isEmpty || !self.transcriptText.isEmpty
            if hasText,
               self.analysis?.isFullyAnalyzed != true,
               self.isViewingAtom(uuid: uuid),
               !self.cloudActivelyProcessing(self.displayAtom) {
                await self.runInsightPass(context: "cloudFallback")
            }
        }
    }

    // MARK: - Auto-transcription

    private func publishAutoTranscriptionProgress(_ message: String, expectedUUID: String) {
        guard isViewingAtom(uuid: expectedUUID) else { return }
        guard autoTranscriptionProgress != message else { return }
        autoTranscriptionProgress = message
    }

    func autoTranscribe(videoURL: URL, duration: TimeInterval) async {
        let expectedUUID = displayAtom.uuid
        isAutoTranscribing = true
        autoTranscriptionProgress = "Starting transcription…"

        let result = await InstagramAutoTranscriber.shared.transcribe(
            videoURL: videoURL,
            duration: duration
        ) { [weak self] progress in
            let message: String
            switch progress {
            case .extractingFrames(let pct):
                message = "Extracting frames... \(Int(pct * 100))%"
            case .recognizingText(let pct):
                message = "Reading text... \(Int(pct * 100))%"
            case .recognizingSpeech(let pct):
                message = "Recognizing speech... \(Int(pct * 100))%"
            case .analyzingWithAI(let pct):
                message = "AI analyzing frames... \(Int(pct * 100))%"
            case .mergingResults:
                message = "Merging results…"
            case .complete:
                message = "Complete"
            }
            Task { @MainActor in
                self?.publishAutoTranscriptionProgress(message, expectedUUID: expectedUUID)
            }
        }

        guard isViewingAtom(uuid: expectedUUID) else { return }
        autoTranscriptionContentType = result.contentType

        if result.contentType != .empty {
            applyTranscriptionResult(result)
            await saveSlideTranscriptAsync()
            if shouldAutoAnalyzeAfterTranscription() {
                await runInsightPass(context: "autoTranscribe")
            }
        }

        isAutoTranscribing = false
    }

    func autoTranscribeCarousel(items: [CarouselItem]) async {
        let expectedUUID = displayAtom.uuid
        let shortcode = currentInstagramShortcode()
        isAutoTranscribing = true
        autoTranscriptionProgress = "Starting carousel transcription…"

        let result = await InstagramAutoTranscriber.shared.transcribeCarousel(
            items: items,
            shortcode: shortcode
        ) { [weak self] progress in
            let message: String?
            switch progress {
            case .recognizingText(let pct):
                message = "Reading slide text... \(Int(pct * 100))%"
            case .analyzingWithAI(let pct):
                message = "AI analyzing slides... \(Int(pct * 100))%"
            case .complete:
                message = "Complete"
            default:
                message = nil
            }
            if let message {
                Task { @MainActor in
                    self?.publishAutoTranscriptionProgress(message, expectedUUID: expectedUUID)
                }
            }
        }

        guard isViewingAtom(uuid: expectedUUID) else { return }
        autoTranscriptionContentType = result.contentType

        if !result.cleanedSlides.isEmpty || !result.rawSlides.isEmpty {
            applyTranscriptionResult(result)
            let hasText = result.cleanedSlides.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasText {
                await saveSlideTranscriptAsync()
            }
            if hasText && shouldAutoAnalyzeAfterTranscription() {
                await runInsightPass(context: "autoTranscribeCarousel")
            }
        }

        isAutoTranscribing = false
    }

    private func shouldAutoAnalyzeAfterTranscription() -> Bool {
        guard transcriptSlides.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }
        // Always re-analyze after auto-transcription completes — the previous
        // analysis may have used the caption instead of the first slide.
        return !isAnalyzing
    }

    /// Force re-run auto-transcription (user action from the overflow menu).
    func retranscribeInstagram() {
        guard !isAutoTranscribing else { return }
        let atom = displayAtom

        // Railway-first Retry (iOS parity): the worker holds every key, does
        // fresh Apify extraction, and priorTranscript banking makes a re-kick
        // cheap (analysis-only when a transcript is already stored). The local
        // paths below remain the offline / worker-down fallback — they need a
        // live media URL the CDN has usually expired.
        Task {
            let expectedUUID = atom.uuid
            if await kickCloudRetranscribe(for: atom) { return }
            guard isViewingAtom(uuid: expectedUUID) else { return }
            retranscribeLocally(atom)
        }
    }

    /// Cloud leg of the Retry control. True when the worker accepted the kick
    /// (processing + polling now underway); false → caller falls back local.
    private func kickCloudRetranscribe(for atom: Atom) async -> Bool {
        guard let urlString = atom.url,
              SwipeProcessingService.isCloudWorkerScoped(url: urlString, contentSource: nil) else {
            return false
        }
        guard await CloudSwipeAPI.kickProcessingAwaiting(swipeUUID: atom.uuid) else {
            print("SwipeStudy: cloud retry kick failed for \(atom.uuid.prefix(8)) — falling back to local pipeline")
            return false
        }
        guard isViewingAtom(uuid: atom.uuid) else { return true }
        // Pull the worker's fresh 'extracting' stamp down so the poll sees an
        // ACTIVE cloud claim instead of the stale retired status.
        await SyncEngine.shared.forceSync()
        pollForBackgroundCompletion()
        return true
    }

    private func retranscribeLocally(_ atom: Atom) {
        if isCarouselContent {
            Task {
                let expectedUUID = atom.uuid
                var items = igMediaData?.carouselItems
                    ?? atom.richContent?.instagramData?.carouselItems ?? []

                if let urlString = atom.url,
                   let url = URL(string: urlString),
                   let mediaData = try? await InstagramMediaCache.shared.getMedia(for: url) {
                    guard isViewingAtom(uuid: expectedUUID) else { return }

                    if InstagramMediaResolution.isIncompletePostMedia(
                        mediaData: mediaData,
                        sourceURL: url
                    ) {
                        // Reached only from retranscribeInstagram — the user asked.
                        await showPartialAndUpgrade(liveMedia: mediaData, userInitiated: true)
                        return
                    }

                    isUpgradingCarousel = false
                    igMediaData = mediaData
                    await persistInstagramMediaToAtom(mediaData, expectedAtomUUID: expectedUUID)

                    if let refreshedItems = mediaData.carouselItems, !refreshedItems.isEmpty {
                        carouselCurrentIndex = min(carouselCurrentIndex, refreshedItems.count - 1)
                        items = refreshedItems
                    }
                }

                guard isViewingAtom(uuid: expectedUUID) else { return }
                guard !items.isEmpty else { return }
                await autoTranscribeCarousel(items: items)
            }
            return
        }

        if let player = igPlayer, let currentItem = player.currentItem,
           let asset = currentItem.asset as? AVURLAsset {
            let duration = igMediaData?.duration ?? videoDuration
            Task {
                await autoTranscribe(videoURL: asset.url, duration: duration > 0 ? duration : 60)
            }
            return
        }

        guard let urlString = atom.url, let url = URL(string: urlString) else { return }
        Task {
            let expectedUUID = atom.uuid
            do {
                let mediaData = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }
                igMediaData = mediaData
                if let videoURL = mediaData.videoURL {
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    await autoTranscribe(videoURL: playableURL, duration: mediaData.duration ?? 60)
                }
            } catch {
                print("SwipeStudy: Re-transcribe failed: \(error)")
            }
        }
    }

    /// Refresh engagement stats via the Railway worker.
    func refreshEngagementStats() {
        let uuid = displayAtom.uuid
        Task {
            await CloudSwipeAPI.refreshStats(swipeUUID: uuid)
            await SyncEngine.shared.forceSync()
            if let fresh = try? await AtomRepository.shared.fetch(uuid: uuid), isViewingAtom(uuid: uuid) {
                currentAtom = fresh
                if let sa = fresh.swipeAnalysis { analysis = sa }
            }
        }
    }

    // MARK: - IG player plumbing

    func setupIGPlayer(videoURL: URL) {
        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)

        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTimestamp = time.seconds
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIGVideo()
            }
        }

        igPlayer = player

        Task { [weak self] in
            let asset = AVURLAsset(url: videoURL)
            if let dur = try? await asset.load(.duration), dur.seconds > 0.5 {
                self?.videoDuration = dur.seconds
            }
        }
    }

    func refreshIGVideo() {
        guard !igIsExtractingVideo else { return }
        igIsExtractingVideo = true

        Task {
            let expectedUUID = displayAtom.uuid
            guard let urlString = displayAtom.url, let url = URL(string: urlString) else {
                igIsExtractingVideo = false
                return
            }

            InstagramMediaCache.shared.invalidate(for: url)

            do {
                let fresh = try await InstagramMediaCache.shared.getMedia(for: url)
                guard isViewingAtom(uuid: expectedUUID) else { return }
                igMediaData = fresh
                if let videoURL = fresh.videoURL {
                    let playableURL = await InstagramVideoLocalCache.resolvePlayableURL(from: videoURL)
                    guard isViewingAtom(uuid: expectedUUID) else { return }
                    let item = AVPlayerItem(url: playableURL)
                    igPlayer?.replaceCurrentItem(with: item)
                    if currentTimestamp > 0 {
                        await igPlayer?.seek(to: CMTime(seconds: currentTimestamp, preferredTimescale: 600))
                    }
                }
            } catch {
                print("SwipeStudy: Instagram video refresh failed: \(error)")
            }

            igIsExtractingVideo = false
        }
    }

    // MARK: - Persist IG metadata

    private func persistCaptionToAtom(_ caption: String, expectedAtomUUID: String) {
        guard var current = currentAtom, current.uuid == expectedAtomUUID else { return }
        var richContent = current.richContent ?? ResearchRichContent()
        if var igData = richContent.instagramData {
            igData.caption = caption
            richContent.instagramData = igData
        } else if let urlString = current.url, let url = URL(string: urlString) {
            var igData = InstagramData(originalURL: url, contentType: .reel)
            igData.caption = caption
            richContent.instagramData = igData
        }
        current.setRichContent(richContent)
        currentAtom = current
        Task { [weak self] in
            guard let self, self.currentAtom?.uuid == expectedAtomUUID else { return }
            do {
                let saved = try await AtomRepository.shared.update(current)
                if self.currentAtom?.uuid == expectedAtomUUID {
                    self.currentAtom = saved
                }
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "SwipeStudy.persistCaption(\(current.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func persistInstagramMediaToAtom(_ mediaData: InstagramMediaData, expectedAtomUUID: String) async {
        guard var current = currentAtom, current.uuid == expectedAtomUUID else { return }

        // Skip media refresh while processing is in progress — avoids a
        // version-conflict race with the background pipeline.
        guard current.metadataDict?["processingStatus"] as? String == "complete" else { return }
        if InstagramMediaResolution.isIncompletePostMedia(
            mediaData: mediaData,
            sourceURL: mediaData.originalURL
        ) {
            return
        }

        var richContent = current.richContent ?? ResearchRichContent()
        var igData = richContent.instagramData ?? InstagramData(
            originalURL: mediaData.originalURL,
            contentType: mediaData.contentType
        )
        var didChange = false

        if igData.authorUsername != mediaData.authorUsername, let author = mediaData.authorUsername {
            igData.authorUsername = author
            richContent.author = author
            didChange = true
        }

        if igData.caption != mediaData.caption, let caption = mediaData.caption {
            igData.caption = caption
            didChange = true
        }

        if igData.extractedMediaURL != mediaData.videoURL {
            igData.extractedMediaURL = mediaData.videoURL
            didChange = true
        }

        if igData.extractedAt != mediaData.extractedAt {
            igData.extractedAt = mediaData.extractedAt
            didChange = true
        }

        if igData.expectedCarouselItemCount != mediaData.expectedCarouselItemCount {
            igData.expectedCarouselItemCount = mediaData.expectedCarouselItemCount
            didChange = true
        }

        if let items = mediaData.carouselItems, !items.isEmpty {
            let shortcode = InstagramExtractor.shared.extractShortcode(from: mediaData.originalURL)
            _ = await InstagramCarouselImageCache.cacheCarouselImages(
                items: items,
                shortcode: shortcode
            )

            let existingCount = igData.carouselItems?.count ?? 0
            let existingSignature = (igData.carouselItems ?? []).map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            let incomingSignature = items.map {
                "\($0.index)|\($0.mediaType.rawValue)|\($0.mediaURL.absoluteString)"
            }
            if existingCount < items.count ||
                igData.carouselItems?.isEmpty == true ||
                existingSignature != incomingSignature {
                igData.carouselItems = items
                didChange = true
            }
            if richContent.sourceType != .instagramCarousel {
                richContent.sourceType = .instagramCarousel
                richContent.instagramType = "carousel"
                didChange = true
            }
        }

        let resolvedThumbnail = mediaData.thumbnailURL?.absoluteString
            ?? mediaData.carouselItems?.first(where: { $0.mediaType == .image })?.mediaURL.absoluteString
            ?? mediaData.carouselItems?.first?.mediaURL.absoluteString

        if let resolvedThumbnail,
           resolvedThumbnail != current.thumbnailUrl || resolvedThumbnail != richContent.thumbnailUrl {
            current.thumbnailUrl = resolvedThumbnail
            richContent.thumbnailUrl = resolvedThumbnail
            didChange = true
        }

        guard didChange else { return }

        richContent.instagramData = igData
        current.setRichContent(richContent)
        currentAtom = current

        do {
            currentAtom = try await AtomRepository.shared.update(current)
        } catch {
            print("SwipeStudy: Failed to persist refreshed Instagram media: \(error)")
        }
    }

    // MARK: - Processing status copy

    static func processingCopy(for status: String?) -> String? {
        switch status {
        case "pending", "extracting": return "Getting this post…"
        case "transcribing": return "This post is transcribing…"
        case "analyzing": return "Analyzing…"
        case "extraction_failed", "partial", SwipeProcessingService.statusNeedsManualRetry:
            return "Couldn't fetch this post"
        default: return nil
        }
    }

    /// True when a swipe has stopped trying and is waiting on the user.
    ///
    /// Derived from whether a retry is actually still scheduled, not from the
    /// status string alone. Retries live inside a short capture window now, so
    /// a `partial` / `extraction_failed` row whose `processingRetryAfter` has
    /// passed is finished even though its status still reads mid-flight — which
    /// is exactly the state every swipe that failed under the old backoff-ladder
    /// policy is sitting in. Claiming "retrying" there would be a lie, and the
    /// surface would show no Retry control, stranding the swipe.
    ///
    /// Any surface showing this MUST offer a Retry control.
    static func awaitsManualRetry(_ atom: Atom) -> Bool {
        let status = atom.processingStatus
        if status == SwipeProcessingService.statusNeedsManualRetry { return true }
        guard status == "extraction_failed" || status == "partial" else { return false }
        let meta = atom.metadataDict
        // A scheduled retry the budget can no longer honour is not a retry. This
        // is the state swipes land in the moment they spend their last attempt.
        let attempts = (meta?["cloudRetryCount"] as? NSNumber)?.intValue ?? 0
        if attempts >= SwipeProcessingService.cloudMaxRetries { return true }
        guard let retryAfter = meta?["processingRetryAfter"] as? String,
              let retryAt = ISO8601.date(from: retryAfter) else {
            return true  // no retry scheduled at all — nothing is coming
        }
        return retryAt <= Date()
    }

    static func isProcessingStale(_ atom: Atom) -> Bool {
        guard processingCopy(for: atom.processingStatus) != nil else { return false }
        guard let updated = ISO8601.date(from: atom.updatedAt) else { return false }
        return Date().timeIntervalSince(updated) > 30 * 60
    }

    static func compactCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: value < 10_000_000 ? "%.1fM" : "%.0fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: value < 10_000 ? "%.1fK" : "%.0fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

// MARK: - Cosmo Context Provider

@MainActor
final class SwipeStudyContextProvider: CosmoContextProvider {
    private let atom: Atom
    private let analysisRef: () -> SwipeAnalysis?
    private let transcriptRef: () -> String

    init(atom: Atom, analysisRef: @escaping () -> SwipeAnalysis?, transcriptRef: @escaping () -> String) {
        self.atom = atom
        self.analysisRef = analysisRef
        self.transcriptRef = transcriptRef
    }

    var contextType: CosmoContextType { .swipeStudy }

    var contextSummary: String {
        let analysis = analysisRef()
        let hookLabel = analysis?.hookType?.rawValue ?? "unanalyzed"
        return "Studying: \(atom.title ?? "Untitled") — \(hookLabel)"
    }

    var contextData: CosmoContextData {
        let analysis = analysisRef()
        let transcript = transcriptRef()
        var viewData: [String: String] = [:]

        if let hookType = analysis?.hookType {
            viewData["hookType"] = hookType.rawValue
        }
        if let hookScore = analysis?.hookScore {
            viewData["hookScore"] = String(format: "%.1f", hookScore)
        }
        if let framework = analysis?.frameworkType {
            viewData["framework"] = framework.rawValue
        }
        if !transcript.isEmpty {
            viewData["transcript"] = String(transcript.prefix(1000))
        }
        if let creatorUUID = analysis?.creatorUUID {
            viewData["creatorUUID"] = creatorUUID
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "swipeFile",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
