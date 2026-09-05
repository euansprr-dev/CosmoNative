// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift
// ViewModel for Idea Focus Mode brainstorm workspace
// February 2026

import GRDB
import SwiftUI

/// The freshness contract for idea writes, in one place: where a model's
/// content-modified clock STARTS, and whether a given write may land.
///
/// Both halves have to agree or neither works. `allowsWrite` refuses a writer
/// whose content predates the row — but only if that writer's clock was seeded
/// honestly. Seeding it from `Date()` (which is effectively what the old
/// write-time stamping did) makes every writer the freshest and the check can
/// never fire, which is how a duplicate model overwrote live typing on
/// 2026-07-29.
enum IdeaFocusWritePolicy {
    /// Where a newly-built model's `lastModified` starts: whatever the row
    /// already claims, never "now". A model that takes no edits therefore can
    /// never out-rank the row it was built from.
    static func seededModifiedTime(metadata: String?, updatedAt: String?) -> Date {
        if let persisted = persistedModifiedTime(from: metadata) {
            return Date(timeIntervalSince1970: persisted)
        }
        if let updatedAt, let date = ISO8601.date(from: updatedAt) {
            return date
        }
        return .distantPast
    }

    static func allowsWrite(existingMetadata: String?, snapshotLastModified: Date) -> Bool {
        guard let existingModified = persistedModifiedTime(from: existingMetadata) else {
            return true
        }

        return snapshotLastModified.timeIntervalSince1970 + 0.000001 >= existingModified
    }

    private static func persistedModifiedTime(from metadata: String?) -> TimeInterval? {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let unix = dict["lastModifiedUnix"] as? TimeInterval {
            return unix
        }

        return nil
    }
}

private struct IdeaFocusSaveSnapshot: Sendable {
    let uuid: String
    let title: String?
    let body: String?
    let tags: [String]
    let selectedStatus: IdeaStatus
    let selectedFormat: ContentFormat?
    let selectedPlatform: IdeaPlatform?
    let editableHooks: [String]
    let editableDescription: String
    let mentionedAtomUUIDs: [String]
    let editableContext: String
    let selectedArcType: String?
    let editableCreativeDirection: String
    let selectedBlueprintUUID: String?
    let selectedContentType: String?
    let researchResults: [IdeaResearchResult]
    let chatHistory: [IdeaChatMessage]
    let arcRecommendations: [ArcRecommendation]
    let codexOutline: CodexOutlineModel?
    let lastModified: Date

    func metadataJSON(merging existingMetadata: String?) -> String? {
        var meta = decodeExistingMetadata(existingMetadata)
        meta.tags = tags.isEmpty ? nil : tags
        meta.contentFormat = selectedFormat
        meta.platform = selectedPlatform
        meta.ideaStatus = selectedStatus
        meta.hooks = editableHooks.isEmpty ? nil : editableHooks
        meta.ideaDescription = editableDescription.isEmpty ? nil : editableDescription
        meta.mentionedAtomUUIDs = mentionedAtomUUIDs.isEmpty ? nil : mentionedAtomUUIDs
        meta.context = editableContext.isEmpty ? nil : editableContext
        meta.arcType = selectedArcType
        meta.creativeDirection = editableCreativeDirection.isEmpty ? nil : editableCreativeDirection
        meta.blueprintUUID = selectedBlueprintUUID
        meta.ideaContentType = selectedContentType
        meta.researchResults = encodedNonEmpty(researchResults)
        meta.chatHistory = encodedNonEmpty(chatHistory)
        meta.arcRecommendations = encodedNonEmpty(arcRecommendations)
        meta.codexOutline = encoded(codexOutline)
        meta.lastModifiedUnix = lastModified.timeIntervalSince1970
        return encoded(meta)
    }

    private func decodeExistingMetadata(_ metadata: String?) -> IdeaMetadata {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(IdeaMetadata.self, from: data) else {
            return IdeaMetadata()
        }
        return decoded
    }

    private func encoded<T: Encodable>(_ value: T?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func encodedNonEmpty<T: Encodable>(_ value: [T]) -> String? {
        guard !value.isEmpty,
              let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Idea Focus Mode ViewModel

/// Drives the Idea Focus Mode workspace -- manages editable fields, analysis pipeline,
/// framework selection, blueprint generation, and content promotion.
@MainActor
@Observable
final class IdeaFocusModeViewModel {
    // MARK: - Published State (Editable Fields)

    var idea: Atom
    var editableTitle: String
    var editableBody: String
    var editableHooks: [String]
    var editableDescription: String
    var selectedStatus: IdeaStatus
    var selectedFormat: ContentFormat?
    var selectedPlatform: IdeaPlatform?
    var tags: [String]
    var selectedHookIndex: Int?

    // MARK: - Published State (Intelligence)

    var insight: IdeaInsight?
    var isAnalyzing: Bool = false
    var analysisStage: String = ""
    var blueprint: ContentBlueprint?
    var linkedClient: Atom?
    var clientProfiles: [Atom] = []

    // MARK: - Published State (Linked Context)

    var linkedSwipes: [Atom] = []
    var linkedConnections: [Atom] = []
    var suggestedConnections: [Atom] = []
    /// The library's best performers in the idea's format — the "steal from
    /// the winners" shelf. Loaded per format change, ranked by real
    /// performance (views, then engagement), never AI quality guesses.
    var recommendedSwipes: [Atom] = []

    // MARK: - Published State (Codex Integration)

    var editableContext: String = ""
    var selectedBlueprintUUID: String? = nil
    var selectedBlueprint: Atom? = nil
    var supportingSwipes: [Atom] = []
    var selectedContentType: String? = nil
    var codexOutline: CodexOutlineModel? = nil
    var selectedArcType: String? = nil
    var editableCreativeDirection: String = ""
    var researchResults: [IdeaResearchResult] = []
    var chatHistory: [IdeaChatMessage] = []
    var arcRecommendations: [ArcRecommendation] = []

    // MARK: - Published State (Scheduled development tasks)

    /// Tasks whose linkedAtoms point back at this idea — its scheduled
    /// development sessions. The link lives on the task (IdeaTaskLinkService);
    /// the idea atom is never written by scheduling.
    var scheduledTasks: [Atom] = []

    // MARK: - Overlay State

    var showLinkSwipesOverlay: Bool = false
    var showLinkConnectionsOverlay: Bool = false
    /// The toolbar's schedule popover (⌘⇧T) — schedule this idea into a task.
    var showSchedulePopover: Bool = false

    // MARK: - Mention State

    var mentionedAtoms: [Atom] = []
    var showMentionOverlay: Bool = false
    var mentionSearchText: String = ""

    // MARK: - Session State

    var sessionState: IdeaFocusModeState

    // MARK: - Private

    @ObservationIgnored private var autoSaveTask: Task<Void, Never>?
    @ObservationIgnored private var autoEnrichTask: Task<Void, Never>?
    private let autoSaveDelay: TimeInterval = 1.5
    private let autoEnrichDelay: TimeInterval = 1.5
    @ObservationIgnored private var saveSequence: UInt64 = 0

    /// When this model's CONTENT last changed — never when a write was attempted.
    ///
    /// LAW: only `markEdited()` may move this. `IdeaFocusWritePolicy.allowsWrite`
    /// compares it against the row's persisted `lastModifiedUnix` to refuse a
    /// writer whose content predates what is already saved, so stamping it at
    /// write time makes every writer look like the freshest one and defeats the
    /// guard entirely. That is exactly what happened on 2026-07-29: a duplicate
    /// model holding pre-edit text flushed at quit, stamped itself `now`, passed
    /// the freshness check, and overwrote three minutes of typing. Seeded from
    /// the persisted stamp so a model that never takes an edit is never "newer".
    @ObservationIgnored private var lastModified: Date

    /// Whether this model has ever taken a content edit of its own.
    ///
    /// GUARD-TWIN of `lastModified` (change together). Close and termination
    /// flushes persist what the model already knows is dirty; they must never
    /// claim freshness on behalf of a model that never edited anything. Latches
    /// true and never resets — a save must not be able to clear it and leave a
    /// later untracked mutation unwritten.
    @ObservationIgnored private var hasRecordedEdit = false

    /// Latches on the first `start()` so the loader ladder runs once per model.
    @ObservationIgnored private var hasStarted = false

    // MARK: - Initialization

    init(atom: Atom) {
        self.idea = atom

        let meta = atom.ideaMetadata

        self.editableTitle = atom.title ?? ""
        self.editableBody = atom.body ?? ""
        self.editableHooks = meta?.hooks ?? []
        self.editableDescription = meta?.ideaDescription ?? ""
        self.selectedStatus = meta?.ideaStatus ?? .spark
        self.selectedFormat = meta?.contentFormat
        self.selectedPlatform = meta?.platform
        self.tags = meta?.tags ?? []
        self.selectedHookIndex = nil

        self.sessionState = IdeaFocusModeState(atomUUID: atom.uuid)

        // Seeded from what is already on the row, never `Date()`: an unedited
        // model must never out-rank the row it was built from.
        self.lastModified = IdeaFocusWritePolicy.seededModifiedTime(
            metadata: atom.metadata,
            updatedAt: atom.updatedAt
        )

        // Restore insight from atom's structured JSON (decoded once)
        let restoredInsight = atom.ideaInsight
        self.insight = restoredInsight
        self.blueprint = restoredInsight?.blueprint

        // Restore session-level selections
        if let hookIdx = sessionState.selectedHookIndex {
            self.selectedHookIndex = hookIdx
        }

        // The termination flush is NOT subscribed here — it lives on the view
        // (`IdeaFocusModeView`, the Content/Notes idiom). `State(initialValue:)`
        // is not lazy, so this initializer runs on every re-render of the host
        // view and SwiftUI discards all but the first model. When each of those
        // discarded models subscribed to `.cosmoAppWillTerminate`, quitting made
        // every one of them flush its own pre-edit copy. See `lastModified`.

        // Restore codex-era fields from metadata
        self.editableContext = meta?.context ?? ""
        self.selectedBlueprintUUID = meta?.blueprintUUID
        self.selectedContentType = meta?.ideaContentType
        self.selectedArcType = meta?.arcType
        self.editableCreativeDirection = meta?.creativeDirection ?? ""

        // Decode JSON-backed fields.
        // codexOutline decodes HERE: the bench body renders the outline
        // section on its first pass, before onAppear runs `start()`.
        if let outlineJSON = meta?.codexOutline,
           let data = outlineJSON.data(using: .utf8) {
            self.codexOutline = try? JSONDecoder().decode(CodexOutlineModel.self, from: data)
        }
        // researchResults / chatHistory / arcRecommendations decode in
        // `start()`: no view body reads them before appear (verified — the
        // only readers are save snapshots and Begin Writing, both gated
        // behind user action), so only the mounted model pays the parse —
        // this init runs on every host re-render.
    }

    /// Begin loading everything this idea hangs off the network and the DB.
    ///
    /// Deliberately NOT done in `init`: the initializer runs on every re-render
    /// of the host view (`State(initialValue:)` is not lazy) and SwiftUI throws
    /// all but the first model away. Loading here meant every throwaway ran the
    /// whole ladder — including `loadRecommendedSwipes`, a full `fetchAll` over
    /// the research table — and, worse, the in-flight tasks kept those dead
    /// models alive long enough to still be listening at quit. Idempotent: the
    /// view calls it on appear, and calling it twice is harmless.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let meta = idea.ideaMetadata

        // JSON-backed fields whose decode moved out of init (init runs per
        // host re-render; only the mounted model should pay the parse).
        // Synchronous and ahead of the loader ladder so every downstream
        // reader (save snapshots, Begin Writing) sees them seeded.
        if let researchJSON = meta?.researchResults,
           let data = researchJSON.data(using: .utf8) {
            self.researchResults = (try? JSONDecoder().decode([IdeaResearchResult].self, from: data)) ?? []
        }
        if let chatJSON = meta?.chatHistory,
           let data = chatJSON.data(using: .utf8) {
            self.chatHistory = (try? JSONDecoder().decode([IdeaChatMessage].self, from: data)) ?? []
        }
        if let arcJSON = meta?.arcRecommendations,
           let data = arcJSON.data(using: .utf8) {
            self.arcRecommendations = (try? JSONDecoder().decode([ArcRecommendation].self, from: data)) ?? []
        }

        Task { await loadClientProfiles() }
        if let clientUUID = meta?.clientUUID {
            Task { await loadLinkedClient(uuid: clientUUID) }
        }
        if let bpUUID = meta?.blueprintUUID {
            Task { selectedBlueprint = try? await AtomRepository.shared.fetch(uuid: bpUUID) }
        }
        if let swipeUUIDs = meta?.supportingSwipeUUIDs, !swipeUUIDs.isEmpty {
            Task { supportingSwipes = (try? await AtomRepository.shared.fetchBatch(uuids: swipeUUIDs)) ?? [] }
        }
        Task { await loadLinkedSwipes() }
        Task { await loadRecommendedSwipes() }
        Task { await loadLinkedConnections() }
        Task { await loadMentionedAtoms() }
        Task { await loadSuggestedConnections() }
        Task { await loadScheduledTasks() }
    }

    deinit {
        autoSaveTask?.cancel()
        autoEnrichTask?.cancel()
    }

    // MARK: - Analysis Pipeline

    /// Run the full IdeaInsightEngine analysis pipeline.
    /// Sets `isAnalyzing` while in-flight, populates `insight` on completion.
    func analyzeIdea() async {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        analysisStage = "Preparing analysis…"

        // Ensure latest edits are saved before analysis
        await save()

        do {
            // Refresh the atom from the database to get the latest version
            analysisStage = "Loading latest data…"
            if let freshAtom = try await AtomRepository.shared.fetch(uuid: idea.uuid) {
                idea = freshAtom
            }

            analysisStage = "Finding matching swipes…"
            let result = await IdeaInsightEngine.shared.fullAnalysis(atom: idea)

            analysisStage = "Processing results…"
            insight = result

            // Persist insight to atom's structured JSON
            var updatedAtom = idea.withIdeaInsight(result)
            updatedAtom = updatedAtom.withUpdatedIdeaMetadata { meta in
                meta.lastAnalyzedAt = ISO8601.string(from: Date())
                meta.insightScore = calculateInsightScore(result)
                meta.matchingSwipeCount = result.matchingSwipes?.count
                if let topFramework = result.frameworkRecommendations?.first {
                    meta.suggestedFramework = topFramework.framework.rawValue
                }
                if let topHook = result.hookSuggestions?.first {
                    meta.suggestedHookType = topHook.hookType?.rawValue
                }
            }
            updatedAtom.updatedAt = ISO8601.string(from: Date())
            updatedAtom.localVersion += 1

            idea = try await AtomRepository.shared.update(updatedAtom)

            // Update session state
            sessionState.lastAnalyzedAt = ISO8601.string(from: Date())
            sessionState.save()

        } catch {
            print("IdeaFocusMode: analysis failed: \(error)")
        }

        analysisStage = ""
        isAnalyzing = false
    }

    // MARK: - Auto Enrich

    /// Debounced lightweight analysis triggered on body text changes.
    /// Runs `IdeaInsightEngine.quickInsight()` after 1.5s of idle typing.
    /// The background arc-recommendation call was removed with the framework
    /// surface (July 2026) — no silent LLM calls ride the typing path.
    func autoEnrich() {
        autoEnrichTask?.cancel()
        autoEnrichTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoEnrichDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let ideaText = "\(editableTitle)\n\(editableBody)"
            let _ = IdeaInsightEngine.shared.quickInsight(ideaText: ideaText)
        }
    }

    // MARK: - Blueprint Selection

    /// Set a swipe as the primary blueprint (structural skeleton for writing).
    /// This is separate from supporting swipes — the blueprint is the core emulation target.
    func selectBlueprint(_ atom: Atom) {
        selectedBlueprintUUID = atom.uuid
        selectedBlueprint = atom
        scheduleAutoSave()
    }

    /// Remove the current blueprint selection.
    func clearBlueprint() {
        selectedBlueprintUUID = nil
        selectedBlueprint = nil
        scheduleAutoSave()
    }

    // MARK: - Promote to Content

    /// Begin Writing. The promotion itself lives in `IdeaPromotionService`
    /// (shared with the Pipeline board and the calendar so the three paths
    /// can never drift); the bench flushes its session first, hands over the
    /// session-only choices, then follows the piece into the writing surface.
    func promoteToContent() async {
        await save()
        do {
            let options = IdeaPromotionService.PromotionOptions(
                refreshInsightIfStale: true,
                scheduleOn: nil,
                initialPhase: .ideation,
                carryAssistantSession: true,
                openFocusMode: true,
                selectedFramework: sessionState.selectedFramework,
                selectedHookIndex: selectedHookIndex,
                titleOverride: editableTitle,
                bodyOverride: editableBody,
                mentionedAtoms: mentionedAtoms
            )
            let result = try await IdeaPromotionService.promote(ideaUUID: idea.uuid, options: options)
            idea = result.idea
            insight = result.idea.ideaInsight ?? insight
            selectedStatus = .inProduction
            await loadScheduledTasks()
        } catch {
            print("IdeaFocusMode: promoteToContent failed: \(error)")
        }
    }

    /// Check if the cached insight is stale (older than 1 hour).
    private func isInsightStale() -> Bool {
        guard let lastAnalyzed = idea.ideaMetadata?.lastAnalyzedAt else { return true }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: lastAnalyzed) else { return true }
        return Date().timeIntervalSince(date) > 3600
    }

    /// Generate an AI-suggested outline for the content using ResearchService.
    /// Returns OutlineItem array with title/reasoning/estimatedSeconds, or empty array on failure.
    private func generateOutline(
        ideaTitle: String,
        ideaBody: String,
        framework: String?,
        format: ContentFormat?,
        swipes: [SwipeMatch]?
    ) async -> [OutlineItem] {
        let frameworkLabel = framework ?? "flexible"
        let formatLabel = format?.rawValue ?? "post"

        var swipeContext = ""
        if let swipes = swipes, !swipes.isEmpty {
            let examples = swipes.prefix(3).map { swipe in
                "- \(swipe.title): hook=\(swipe.hookType?.rawValue ?? "unknown")"
            }.joined(separator: "\n")
            swipeContext = "\n\nReference swipe files:\n\(examples)"
        }

        let prompt = """
        Generate a content outline for the following idea.

        Title: \(ideaTitle)
        Core Idea: \(ideaBody)
        Framework: \(frameworkLabel)
        Format: \(formatLabel)\(swipeContext)

        Return 4-8 outline sections that follow the \(frameworkLabel) framework structure.

        Each item needs:
        - "title": Short, scannable label (2-5 words, e.g. "Hook & Setup", "Core Argument", "CTA")
        - "reasoning": Full detail — what to say, why it works, shooting notes, examples (2-4 sentences)
        - "estimatedSeconds": Approximate duration in seconds (for video/reel formats, null for text)

        Format your response as ONLY this JSON, nothing else:
        {"items":[{"title":"...","reasoning":"...","estimatedSeconds":7},{"title":"...","reasoning":"...","estimatedSeconds":null}]}
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

            // Find the JSON object in the response
            guard let startIdx = cleaned.firstIndex(of: "{"),
                  let endIdx = cleaned.lastIndex(of: "}") else {
                return []
            }

            let jsonString = String(cleaned[startIdx...endIdx])
            guard let data = jsonString.data(using: .utf8) else { return [] }

            struct OutlineResponse: Decodable {
                struct Item: Decodable {
                    let title: String
                    let reasoning: String
                    let estimatedSeconds: Int?
                }
                let items: [Item]
            }

            if let parsed = try? JSONDecoder().decode(OutlineResponse.self, from: data) {
                return parsed.items.enumerated().map { index, item in
                    OutlineItem(
                        title: item.title,
                        reasoning: item.reasoning,
                        estimatedSeconds: item.estimatedSeconds,
                        sortOrder: index
                    )
                }
            }

            // Fallback: try parsing as a flat array of strings (legacy format)
            if let arrayStart = cleaned.firstIndex(of: "["),
               let arrayEnd = cleaned.lastIndex(of: "]") {
                let arrayJson = String(cleaned[arrayStart...arrayEnd])
                if let arrayData = arrayJson.data(using: .utf8),
                   let items = try? JSONDecoder().decode([String].self, from: arrayData) {
                    return items.enumerated().map { index, text in
                        OutlineItem(title: text, sortOrder: index)
                    }
                }
            }

            return []
        } catch {
            print("IdeaFocusMode: generateOutline failed: \(error)")
            return []
        }
    }

    // MARK: - Linked Swipes

    /// Load swipe atoms from the idea's linkedSwipeIds metadata.
    func loadLinkedSwipes() async {
        let swipeIds = idea.ideaMetadata?.linkedSwipeIds ?? []
        var swipes: [Atom] = []
        for uuid in swipeIds {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                swipes.append(atom)
            }
        }
        linkedSwipes = swipes
    }

    /// Link a swipe to this idea by appending its UUID to linkedSwipeIds.
    func linkSwipe(_ swipeUUID: String) async {
        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            var ids = meta.linkedSwipeIds ?? []
            guard !ids.contains(swipeUUID) else { return }
            ids.append(swipeUUID)
            meta.linkedSwipeIds = ids
        }
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1
        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
            await loadLinkedSwipes()
            await loadRecommendedSwipes()
        } catch {
            print("IdeaFocusMode: linkSwipe failed: \(error)")
        }
    }

    /// Unlink a swipe from this idea by removing its UUID from linkedSwipeIds.
    func unlinkSwipe(_ swipeUUID: String) async {
        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            meta.linkedSwipeIds = meta.linkedSwipeIds?.filter { $0 != swipeUUID }
            if meta.linkedSwipeIds?.isEmpty == true { meta.linkedSwipeIds = nil }
        }
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1
        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
            await loadLinkedSwipes()
            await loadRecommendedSwipes()
        } catch {
            print("IdeaFocusMode: unlinkSwipe failed: \(error)")
        }
    }

    // MARK: - Linked Connections

    /// Load connection atoms from the idea's linkedConnectionIds metadata.
    func loadLinkedConnections() async {
        let connectionIds = idea.ideaMetadata?.linkedConnectionIds ?? []
        var connections: [Atom] = []
        for uuid in connectionIds {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                connections.append(atom)
            }
        }
        linkedConnections = connections
    }

    /// Link a connection to this idea.
    func linkConnection(_ connectionUUID: String) async {
        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            var ids = meta.linkedConnectionIds ?? []
            guard !ids.contains(connectionUUID) else { return }
            ids.append(connectionUUID)
            meta.linkedConnectionIds = ids
        }
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1
        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
            await loadLinkedConnections()
        } catch {
            print("IdeaFocusMode: linkConnection failed: \(error)")
        }
    }

    /// Unlink a connection from this idea.
    func unlinkConnection(_ connectionUUID: String) async {
        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            meta.linkedConnectionIds = meta.linkedConnectionIds?.filter { $0 != connectionUUID }
            if meta.linkedConnectionIds?.isEmpty == true { meta.linkedConnectionIds = nil }
        }
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1
        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
            await loadLinkedConnections()
        } catch {
            print("IdeaFocusMode: unlinkConnection failed: \(error)")
        }
    }

    // MARK: - Scheduled Development Tasks

    func loadScheduledTasks() async {
        scheduledTasks = (try? await IdeaTaskLinkService.scheduledTasks(for: idea.uuid)) ?? []
    }

    /// Schedule this idea into a development task on `day`. The task carries
    /// the link (title mention pill + primary linked atom); the idea itself
    /// is never written.
    func scheduleTask(on day: Date) async {
        // The task snapshots whatever title is on screen, not the last save.
        var snapshot = idea
        let liveTitle = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !liveTitle.isEmpty { snapshot.title = liveTitle }
        do {
            _ = try await IdeaTaskLinkService.createScheduledTask(for: snapshot, on: day)
            await loadScheduledTasks()
        } catch {
            print("IdeaFocusMode: scheduleTask failed: \(error)")
        }
    }

    func rescheduleTask(uuid: String, to day: Date) async {
        do {
            try await IdeaTaskLinkService.reschedule(taskUUID: uuid, to: day)
            await loadScheduledTasks()
        } catch {
            print("IdeaFocusMode: rescheduleTask failed: \(error)")
        }
    }

    func removeScheduledTask(uuid: String) async {
        do {
            try await IdeaTaskLinkService.removeScheduledTask(taskUUID: uuid)
            await loadScheduledTasks()
        } catch {
            print("IdeaFocusMode: removeScheduledTask failed: \(error)")
        }
    }

    // MARK: - Mentioned Atoms (@)

    /// Load mentioned atoms from persisted UUIDs.
    func loadMentionedAtoms() async {
        let uuids = idea.ideaMetadata?.mentionedAtomUUIDs ?? []
        var atoms: [Atom] = []
        for uuid in uuids {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                atoms.append(atom)
            }
        }
        mentionedAtoms = atoms
    }

    /// Add an atom as @-mentioned context.
    func addMention(_ atom: Atom) {
        guard !mentionedAtoms.contains(where: { $0.uuid == atom.uuid }) else { return }
        mentionedAtoms.append(atom)
        showMentionOverlay = false
        mentionSearchText = ""
        scheduleAutoSave()
    }

    /// Remove an atom from @-mentioned context.
    func removeMention(_ atom: Atom) {
        mentionedAtoms.removeAll { $0.uuid == atom.uuid }
        scheduleAutoSave()
    }

    /// Load suggested connections — connections assigned to the idea's client, or semantically related.
    func loadSuggestedConnections() async {
        let linkedIds = Set(idea.ideaMetadata?.linkedConnectionIds ?? [])
        do {
            let allConnections = try await AtomRepository.shared.fetchAll(type: .connection)
            let clientUUID = idea.ideaMetadata?.clientUUID

            // Suggest connections assigned to the same client, or with matching titles
            let suggestions = allConnections.filter { conn in
                guard !linkedIds.contains(conn.uuid) else { return false }
                // If idea has a client, prefer connections linked to the same client
                if let clientUUID = clientUUID {
                    if conn.linksList.contains(where: { $0.uuid == clientUUID }) {
                        return true
                    }
                }
                return false
            }
            suggestedConnections = Array(suggestions.prefix(2))
        } catch {
            print("IdeaFocusMode: loadSuggestedConnections failed: \(error)")
        }
    }

    // MARK: - Recommended Swipes

    /// The best performers in the idea's format, drawn from the whole swipe
    /// library: an idea shaped as a voiceover reel sees the top voiceover
    /// reels, a carousel sees the top carousels. Exact format matches lead;
    /// legacy `.reel` classifications back-fill reel-family formats. Ranked
    /// by real performance — views, then engagement rate — and never by
    /// hookScore (all swipes are curated; scores are not quality gates).
    ///
    /// The shelf shows 4 drawn from the top 12, seeded by (idea, day): a
    /// plain global top-4 rendered the identical shelf on every idea forever,
    /// which reads as "recommendations stopped running". Seeding keeps it
    /// deterministic — stable while you work an idea today, different on the
    /// next idea and again tomorrow — while everything offered is still a
    /// proven performer.
    func loadRecommendedSwipes() async {
        guard let format = selectedFormat else {
            recommendedSwipes = []
            return
        }

        var excluded = Set(idea.ideaMetadata?.linkedSwipeIds ?? [])
        if let blueprintUUID = selectedBlueprintUUID {
            excluded.insert(blueprintUUID)
        }

        guard let research = try? await AtomRepository.shared.fetchAll(type: .research) else {
            recommendedSwipes = []
            return
        }

        let reelFamily: Set<ContentFormat> = [.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA]
        let ranked = research.compactMap { atom -> (atom: Atom, tier: Int, views: Int, engagement: Double)? in
            guard atom.isSwipeFileAtom,
                  !excluded.contains(atom.uuid),
                  let analysis = atom.swipeAnalysis,
                  let swipeFormat = analysis.swipeContentFormat else { return nil }
            let tier: Int
            if swipeFormat == format {
                tier = 0
            } else if swipeFormat == .reel, reelFamily.contains(format) {
                tier = 1
            } else {
                return nil
            }
            return (atom, tier, analysis.viewsCount ?? 0, analysis.engagementRate ?? 0)
        }

        let pool = ranked
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.views != rhs.views { return lhs.views > rhs.views }
                return lhs.engagement > rhs.engagement
            }
            .prefix(12)

        guard pool.count > 4 else {
            recommendedSwipes = pool.map(\.atom)
            return
        }

        let dayOrdinal = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var rng = SeededShelfGenerator(seed: Self.shelfSeed(ideaUUID: idea.uuid, dayOrdinal: dayOrdinal))
        let picked = Set(pool.shuffled(using: &rng).prefix(4).map(\.atom.uuid))
        // Present the pick in performance order — the shelf still reads
        // best-first even though membership rotates.
        recommendedSwipes = pool.filter { picked.contains($0.atom.uuid) }.map(\.atom)
    }

    /// Deterministic within a day for one idea, different across ideas and
    /// days (FNV-1a — `Hasher` is salted per launch and would reshuffle the
    /// shelf on every app restart).
    static func shelfSeed(ideaUUID: String, dayOrdinal: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(ideaUUID)#\(dayOrdinal)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Format edits route through here so the recommendation shelf follows
    /// the format the idea is shaped as.
    func updateFormat(_ format: ContentFormat?) {
        selectedFormat = format
        scheduleAutoSave()
        Task { await loadRecommendedSwipes() }
    }

    // MARK: - Client Assignment

    /// Assign or unassign a client profile to this idea.
    func assignClient(_ client: Atom?) async {
        linkedClient = client

        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            meta.clientUUID = client?.uuid
        }

        if let client = client {
            // Add bidirectional links
            updatedAtom = updatedAtom.addingLink(.ideaToClient(client.uuid))

            var updatedClient = client.addingLink(.clientToIdea(idea.uuid))
            updatedClient.updatedAt = ISO8601.string(from: Date())
            updatedClient.localVersion += 1
            do {
                _ = try await AtomRepository.shared.update(updatedClient)
            } catch {
                print("IdeaFocusMode: failed to update client link: \(error)")
            }
        } else {
            // Remove client links
            updatedAtom = updatedAtom.removingLinks(ofType: .ideaToClient)
        }

        updatedAtom.updatedAt = ISO8601.string(from: Date())
        updatedAtom.localVersion += 1

        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
        } catch {
            print("IdeaFocusMode: failed to assign client: \(error)")
        }
    }

    // MARK: - Status Update

    /// Update the idea's status in the pipeline.
    func updateStatus(_ status: IdeaStatus) async {
        selectedStatus = status

        let updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            meta.ideaStatus = status
            meta.statusChangedAt = ISO8601.string(from: Date())
        }
        // Note: AtomRepository.update() handles updatedAt and localVersion internally

        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
        } catch {
            print("IdeaFocusMode: failed to update status: \(error)")
        }
    }

    // MARK: - Save

    /// Persist current editable fields to the atom.
    func save() async {
        // Every caller reaches here straight after mutating an editable field
        // (the inline-assistant applies, the view's explicit saves), so this
        // IS an edit commit point.
        markEdited()
        let sequence = nextSaveSequence()
        let snapshot = makeSaveSnapshot()
        do {
            if let savedAtom = try await writeSnapshot(snapshot, sequence: sequence) {
                idea = savedAtom
            }
        } catch {
            print("IdeaFocusMode: save failed: \(error)")
        }
    }

    // MARK: - Inline Assistant Edits

    /// Apply a reviewed inline-assistant operation to this idea. Body edits locate
    /// through the shared diff resolver (same locate-or-conflict guarantees as
    /// notes/content); hook edits route by `hook-N` anchor or by matching text.
    func applyInlineAssistantEdit(
        _ operation: CosmoAssistantProposalOperation
    ) async throws -> CosmoEditableOperationResult {
        guard operation.kind != .canvasPlan else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Canvas edits need a canvas provider"
            )
        }

        if Self.isHookOperation(operation) {
            return await applyInlineHookEdit(operation)
        }

        guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: editableBody) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Original text not found"
            )
        }
        editableBody.replaceSubrange(placement.range, with: placement.replacementText)
        await save()
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    private static func isHookOperation(_ operation: CosmoAssistantProposalOperation) -> Bool {
        operation.anchorID?.hasPrefix("hook") == true
    }

    private func applyInlineHookEdit(
        _ operation: CosmoAssistantProposalOperation
    ) async -> CosmoEditableOperationResult {
        guard let proposed = operation.proposedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !proposed.isEmpty else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Hook edit has no proposed text"
            )
        }

        let original = operation.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // New hook: insertion, or an anchor with no original text to replace.
        if operation.kind == .textInsertion || original.isEmpty {
            editableHooks.append(proposed)
            await save()
            return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Hook added")
        }

        // Replacement: prefer the indexed anchor when it still matches; otherwise
        // fall back to locating the hook by its text. Mismatch on both = conflict.
        let anchorIndex = operation.anchorID
            .flatMap { $0.split(separator: "-").last }
            .flatMap { Int($0) }

        if let anchorIndex,
           editableHooks.indices.contains(anchorIndex),
           editableHooks[anchorIndex].trimmingCharacters(in: .whitespacesAndNewlines) == original {
            editableHooks[anchorIndex] = proposed
        } else if let matchIndex = editableHooks.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == original
        }) {
            editableHooks[matchIndex] = proposed
        } else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "That hook changed since this was drafted"
            )
        }

        await save()
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Hook updated")
    }

    /// Schedule a debounced auto-save (call after each keystroke in text fields).
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        markEdited()
        let sequence = nextSaveSequence()
        let snapshot = makeSaveSnapshot()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await saveScheduledSnapshot(snapshot, sequence: sequence)
        }
    }

    func updateOutlineSlideNote(slideId: UUID, note: String) {
        guard let idx = codexOutline?.slides.firstIndex(where: { $0.id == slideId }) else { return }
        codexOutline?.slides[idx].note = note.isEmpty ? nil : note
        scheduleAutoSave()
    }

    func replaceCodexOutline(_ outline: CodexOutlineModel?) {
        codexOutline = outline
        scheduleAutoSave()
    }

    /// Force immediate synchronous save — blocks until the DB write completes.
    /// Guarantees data is persisted before the view/app exits.
    func saveOnClose() {
        autoSaveTask?.cancel()
        sessionState.selectedHookIndex = selectedHookIndex
        sessionState.save()

        // A model that never took an edit has nothing of its own to persist,
        // and writing anyway means overwriting the row with the copy this model
        // was BUILT from — the 2026-07-29 clobber. Session state above is UI
        // selection, not content, so it still persists.
        guard hasRecordedEdit else { return }

        let sequence = nextSaveSequence()
        let snapshot = makeSaveSnapshot()

        // Async close save: the focus-exit animation must never block on the
        // DB write lock (cross-process busy timeout is 5s). The registry
        // escort preserves the quit guarantee — terminating mid-write flushes
        // the captured snapshot synchronously; the commit unregisters it.
        let escortID = "idea-close-\(idea.uuid)-\(UUID().uuidString.prefix(8))"
        DirtyEditorRegistry.shared.register(id: escortID) { [weak self] in
            guard let self else { return }
            _ = try? self.writeSnapshotSync(snapshot, sequence: sequence)
        }
        Task { @MainActor in
            defer { DirtyEditorRegistry.shared.unregister(id: escortID) }
            do {
                if let savedAtom = try await self.writeSnapshot(snapshot, sequence: sequence) {
                    self.idea = savedAtom
                }
            } catch {
                print("IdeaFocusMode: close save failed: \(error)")
            }
        }
    }

    /// Termination flush — must stay synchronous: the process is about to
    /// exit, so an async write would never commit.
    func flushForTermination() {
        autoSaveTask?.cancel()
        sessionState.selectedHookIndex = selectedHookIndex
        sessionState.save()

        // GUARD-TWIN of the gate in `saveOnClose` (change together).
        guard hasRecordedEdit else { return }

        let sequence = nextSaveSequence()
        let snapshot = makeSaveSnapshot()

        do {
            if let savedAtom = try writeSnapshotSync(snapshot, sequence: sequence) {
                idea = savedAtom
            }
        } catch {
            print("IdeaFocusMode: sync save failed: \(error)")
        }
    }

    private func saveScheduledSnapshot(_ snapshot: IdeaFocusSaveSnapshot, sequence: UInt64) async {
        do {
            if let savedAtom = try await writeSnapshot(snapshot, sequence: sequence) {
                idea = savedAtom
            }
        } catch {
            print("IdeaFocusMode: autosave failed: \(error)")
        }
    }

    /// Bumps the per-model write sequence so a slower in-flight write can tell
    /// it has been superseded. Deliberately has NO effect on `lastModified` —
    /// see that property. It used to stamp it, which is what let a stale writer
    /// win the freshness comparison it was supposed to lose.
    private func nextSaveSequence() -> UInt64 {
        saveSequence += 1
        return saveSequence
    }

    /// The single funnel for "the user changed something". Every content
    /// mutation must pass through here (via `scheduleAutoSave` or `save`)
    /// before it is persisted.
    private func markEdited() {
        lastModified = Date()
        hasRecordedEdit = true
    }

    private func makeSaveSnapshot() -> IdeaFocusSaveSnapshot {
        IdeaFocusSaveSnapshot(
            uuid: idea.uuid,
            title: editableTitle.isEmpty ? nil : editableTitle,
            body: editableBody.isEmpty ? nil : editableBody,
            tags: tags,
            selectedStatus: selectedStatus,
            selectedFormat: selectedFormat,
            selectedPlatform: selectedPlatform,
            editableHooks: editableHooks,
            editableDescription: editableDescription,
            mentionedAtomUUIDs: mentionedAtoms.map(\.uuid),
            editableContext: editableContext,
            selectedArcType: selectedArcType,
            editableCreativeDirection: editableCreativeDirection,
            selectedBlueprintUUID: selectedBlueprintUUID,
            selectedContentType: selectedContentType,
            researchResults: researchResults,
            chatHistory: chatHistory,
            arcRecommendations: arcRecommendations,
            codexOutline: codexOutline,
            lastModified: lastModified
        )
    }

    private func writeSnapshot(_ snapshot: IdeaFocusSaveSnapshot, sequence: UInt64) async throws -> Atom? {
        guard sequence == saveSequence else {
            print("IdeaFocusMode: skipped stale autosave seq=\(sequence) latest=\(saveSequence)")
            return nil
        }

        let didWrite = try await CosmoDatabase.shared.asyncWrite { db -> Bool in
            let existingMetadata = try Self.existingMetadata(for: snapshot.uuid, db: db)
            guard IdeaFocusWritePolicy.allowsWrite(
                existingMetadata: existingMetadata,
                snapshotLastModified: snapshot.lastModified
            ) else {
                print("IdeaFocusMode: skipped stale metadata write seq=\(sequence)")
                return false
            }

            try Self.write(snapshot: snapshot, existingMetadata: existingMetadata, db: db)
            return db.changesCount > 0
        }

        guard didWrite,
              let savedAtom = try await CosmoDatabase.shared.asyncRead({ db in
                  try Atom.filter(Column("uuid") == snapshot.uuid).fetchOne(db)
              }) else {
            return nil
        }

        await ChangeTracker.shared.trackUpdate(table: Atom.databaseTableName, entity: savedAtom, skipVersionIncrement: true)
        AtomRepository.shared.refreshEditingLock(uuid: snapshot.uuid)
        return savedAtom
    }

    private func writeSnapshotSync(_ snapshot: IdeaFocusSaveSnapshot, sequence: UInt64) throws -> Atom? {
        guard sequence == saveSequence else {
            print("IdeaFocusMode: skipped stale sync save seq=\(sequence) latest=\(saveSequence)")
            return nil
        }

        let didWrite = try CosmoDatabase.shared.write { db -> Bool in
            let existingMetadata = try Self.existingMetadata(for: snapshot.uuid, db: db)
            guard IdeaFocusWritePolicy.allowsWrite(
                existingMetadata: existingMetadata,
                snapshotLastModified: snapshot.lastModified
            ) else {
                print("IdeaFocusMode: skipped stale sync metadata write seq=\(sequence)")
                return false
            }

            try Self.write(snapshot: snapshot, existingMetadata: existingMetadata, db: db)
            return db.changesCount > 0
        }

        guard didWrite,
              let savedAtom = try CosmoDatabase.shared.read({ db in
                  try Atom.filter(Column("uuid") == snapshot.uuid).fetchOne(db)
              }) else {
            return nil
        }

        Task {
            await ChangeTracker.shared.trackUpdate(table: Atom.databaseTableName, entity: savedAtom, skipVersionIncrement: true)
        }
        AtomRepository.shared.refreshEditingLock(uuid: snapshot.uuid)
        return savedAtom
    }

    nonisolated private static func existingMetadata(for uuid: String, db: Database) throws -> String? {
        guard let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) else {
            return nil
        }
        return row["metadata"]
    }

    nonisolated private static func write(snapshot: IdeaFocusSaveSnapshot, existingMetadata: String?, db: Database) throws {
        // Snapshot the pre-image inside this transaction before overwriting it.
        // This path issues raw SQL instead of going through AtomRepository, so
        // without this it accumulated NO history — the same gap that made the
        // note loss unrecoverable, and the reason the 2026-07-29 idea clobber
        // had to be recovered from the sync queue instead of `atom_revisions`.
        // Never throws upward: losing a snapshot must not block a save.
        AtomRevisionWriter.snapshotBeforeRawWrite(
            db,
            uuid: snapshot.uuid,
            incomingTitle: snapshot.title,
            incomingBody: snapshot.body
        )

        try db.execute(
            sql: """
            UPDATE atoms
            SET title = ?,
                body = ?,
                metadata = ?,
                updated_at = ?,
                _local_version = _local_version + 1,
                _local_pending = 1
            WHERE uuid = ?
            """,
            arguments: [
                snapshot.title,
                snapshot.body,
                snapshot.metadataJSON(merging: existingMetadata),
                ISO8601.string(from: Date()),
                snapshot.uuid
            ]
        )
    }

    // MARK: - Client Profiles

    /// Load all client profile atoms for the client picker.
    func loadClientProfiles() async {
        do {
            let profiles = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            clientProfiles = profiles.filter { $0.clientMetadata?.isActive != false }
        } catch {
            print("IdeaFocusMode: failed to load client profiles: \(error)")
        }
    }

    // MARK: - Tags

    /// Add a tag to the idea.
    func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        scheduleAutoSave()
    }

    /// Remove a tag from the idea.
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        scheduleAutoSave()
    }

    // MARK: - Private Helpers

    /// Load a linked client atom by UUID.
    private func loadLinkedClient(uuid: String) async {
        do {
            linkedClient = try await AtomRepository.shared.fetch(uuid: uuid)
        } catch {
            print("IdeaFocusMode: failed to load linked client: \(error)")
        }
    }

    /// Calculate a composite insight score from the analysis results.
    private func calculateInsightScore(_ insight: IdeaInsight) -> Double {
        var score = 0.0
        var factors = 0

        // Matching swipes contribute
        if let swipes = insight.matchingSwipes, !swipes.isEmpty {
            let avgSimilarity = swipes.map(\.similarityScore).reduce(0, +) / Double(swipes.count)
            score += avgSimilarity
            factors += 1
        }

        // Framework recommendations contribute
        if let frameworks = insight.frameworkRecommendations, !frameworks.isEmpty {
            let topConfidence = frameworks.map(\.confidence).max() ?? 0
            score += topConfidence
            factors += 1
        }

        // Hook suggestions contribute
        if let hooks = insight.hookSuggestions, !hooks.isEmpty {
            score += 0.7 // Having hooks is a positive signal
            factors += 1
        }

        // Blueprint existence is a strong signal
        if insight.blueprint != nil {
            score += 0.9
            factors += 1
        }

        return factors > 0 ? score / Double(factors) : 0
    }
}

// MARK: - Seeded shelf shuffle

/// SplitMix64 — the recommended-shelf pick must be reproducible from its
/// seed, which `SystemRandomNumberGenerator` can never be.
private struct SeededShelfGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
