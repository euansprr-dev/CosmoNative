// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift
// ViewModel for Idea Focus Mode brainstorm workspace
// February 2026

import GRDB
import SwiftUI
import Combine

enum IdeaFocusWritePolicy {
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
    var generatedHooks: [HookSuggestion] = []
    var isGeneratingHooks: Bool = false

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

    // MARK: - Overlay State

    var showLinkSwipesOverlay: Bool = false
    var showLinkConnectionsOverlay: Bool = false

    // MARK: - Mention State

    var mentionedAtoms: [Atom] = []
    var showMentionOverlay: Bool = false
    var mentionSearchText: String = ""

    // MARK: - Session State

    var sessionState: IdeaFocusModeState

    // MARK: - Private

    @ObservationIgnored private var autoSaveTask: Task<Void, Never>?
    @ObservationIgnored private var autoEnrichTask: Task<Void, Never>?
    @ObservationIgnored private var hookGenerationTask: Task<Void, Never>?
    @ObservationIgnored private var terminationCancellable: AnyCancellable?
    private let autoSaveDelay: TimeInterval = 1.5
    private let autoEnrichDelay: TimeInterval = 1.5
    @ObservationIgnored private var saveSequence: UInt64 = 0
    @ObservationIgnored private var lastModified: Date = Date()

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

        // Restore insight from atom's structured JSON
        self.insight = atom.ideaInsight
        self.blueprint = atom.ideaInsight?.blueprint

        // Restore session-level selections
        if let hookIdx = sessionState.selectedHookIndex {
            self.selectedHookIndex = hookIdx
        }

        // Flush pending saves synchronously when the app is about to terminate
        terminationCancellable = NotificationCenter.default
            .publisher(for: .cosmoAppWillTerminate)
            .sink { [weak self] _ in
                self?.flushForTermination()
            }

        // Load client profiles in background
        Task { await loadClientProfiles() }

        // If a client is assigned, load it
        if let clientUUID = meta?.clientUUID {
            Task { await loadLinkedClient(uuid: clientUUID) }
        }

        // Restore codex-era fields from metadata
        self.editableContext = meta?.context ?? ""
        self.selectedBlueprintUUID = meta?.blueprintUUID
        self.selectedContentType = meta?.ideaContentType
        self.selectedArcType = meta?.arcType
        self.editableCreativeDirection = meta?.creativeDirection ?? ""

        // Decode JSON-backed fields
        if let outlineJSON = meta?.codexOutline,
           let data = outlineJSON.data(using: .utf8) {
            self.codexOutline = try? JSONDecoder().decode(CodexOutlineModel.self, from: data)
        }
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

        // Load blueprint atom if UUID exists
        if let bpUUID = meta?.blueprintUUID {
            Task { selectedBlueprint = try? await AtomRepository.shared.fetch(uuid: bpUUID) }
        }

        // Load supporting swipes
        if let swipeUUIDs = meta?.supportingSwipeUUIDs, !swipeUUIDs.isEmpty {
            Task { supportingSwipes = (try? await AtomRepository.shared.fetchBatch(uuids: swipeUUIDs)) ?? [] }
        }

        // Load linked swipes and connections
        Task { await loadLinkedSwipes() }
        Task { await loadLinkedConnections() }
        Task { await loadMentionedAtoms() }
        Task { await loadSuggestedConnections() }
    }

    deinit {
        autoSaveTask?.cancel()
        autoEnrichTask?.cancel()
        hookGenerationTask?.cancel()
        terminationCancellable?.cancel()
    }

    // MARK: - Analysis Pipeline

    /// Run the full IdeaInsightEngine analysis pipeline.
    /// Sets `isAnalyzing` while in-flight, populates `insight` on completion.
    func analyzeIdea() async {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        analysisStage = "Preparing analysis..."

        // Ensure latest edits are saved before analysis
        await save()

        do {
            // Refresh the atom from the database to get the latest version
            analysisStage = "Loading latest data..."
            if let freshAtom = try await AtomRepository.shared.fetch(uuid: idea.uuid) {
                idea = freshAtom
            }

            analysisStage = "Finding matching swipes..."
            let result = await IdeaInsightEngine.shared.fullAnalysis(atom: idea)

            analysisStage = "Processing results..."
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
    func autoEnrich() {
        autoEnrichTask?.cancel()
        autoEnrichTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoEnrichDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let ideaText = "\(editableTitle)\n\(editableBody)"
            let _ = IdeaInsightEngine.shared.quickInsight(ideaText: ideaText)

            // Auto-trigger arc recommendations when context has 20+ words and none exist
            let wordCount = editableBody.split(separator: " ").count
            if wordCount >= 20 && arcRecommendations.isEmpty {
                await generateArcRecommendations()
            }
        }
    }

    /// Generate arc type recommendations from the idea context using Gemini Flash.
    /// Recommendations are grounded in the idea text and the swipe library —
    /// the retired Codex element catalog no longer feeds this.
    func generateArcRecommendations() async {
        do {
            let swipes = try await AtomRepository.shared.fetchAll(type: .research)
            let bpTitles = swipes
                .filter { $0.isSwipeFileAtom }
                .prefix(30)
                .map { ($0.title ?? "", $0.bestPhysicsProfile?.arcQuarks?.shape ?? "") }

            let result = try await ArcRecommendationAgent.shared.recommend(
                ideaText: editableBody,
                clientNiche: linkedClient?.title,
                blueprintTitles: bpTitles
            )
            self.arcRecommendations = result.arcRecommendations
            scheduleAutoSave()
        } catch {
            print("Arc recommendation failed: \(error)")
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

    // MARK: - Framework Selection

    /// Select a framework and generate a content blueprint.
    func selectFramework(_ framework: SwipeFrameworkType) async {
        sessionState.selectedFramework = framework.rawValue
        sessionState.save()

        let format = selectedFormat ?? .post
        let ideaText = "\(editableTitle)\n\(editableBody)"
        let referenceSwipes = insight?.matchingSwipes ?? []
        let blueprintResult = await IdeaInsightEngine.shared.generateBlueprint(
            ideaText: ideaText,
            framework: framework,
            format: format,
            referenceSwipes: referenceSwipes
        )

        blueprint = blueprintResult

        // Store blueprint in insight
        if var currentInsight = insight {
            currentInsight.blueprint = blueprintResult
            insight = currentInsight

            var updatedAtom = idea.withIdeaInsight(currentInsight)
            updatedAtom.updatedAt = ISO8601.string(from: Date())
            updatedAtom.localVersion += 1

            do {
                idea = try await AtomRepository.shared.update(updatedAtom)
            } catch {
                print("IdeaFocusMode: failed to save blueprint: \(error)")
            }
        }
    }

    // MARK: - Promote to Content

    /// Create a new content atom from this idea, link them bidirectionally,
    /// and update the idea status to `.inProduction`.
    func promoteToContent() async {
        do {
            // Ensure insight is fresh — run full analysis if nil or stale (>1hr)
            if insight == nil || isInsightStale() {
                await save()
                if let freshAtom = try? await AtomRepository.shared.fetch(uuid: idea.uuid) {
                    idea = freshAtom
                }
                let result = await IdeaInsightEngine.shared.fullAnalysis(atom: idea)
                insight = result
                var analysisAtom = idea.withIdeaInsight(result)
                analysisAtom = analysisAtom.withUpdatedIdeaMetadata { meta in
                    meta.lastAnalyzedAt = ISO8601.string(from: Date())
                }
                analysisAtom.updatedAt = ISO8601.string(from: Date())
                analysisAtom.localVersion += 1
                idea = try await AtomRepository.shared.update(analysisAtom)
            }

            // Create content atom. The idea text goes into contentDescription; draftContent
            // starts as a slide workspace only when the user composed a multi-slide outline.
            let contentAtom = try await AtomRepository.shared.createContent(
                title: editableTitle,
                body: nil,
                contentType: selectedFormat?.rawValue ?? "post"
            )

            // Determine inherited metadata — blueprint FIRST (becomes isPrimary in cloud engine),
            // then supporting swipes, then insight matches
            var allSwipeUUIDs: [String] = []
            if let bpUUID = selectedBlueprintUUID {
                allSwipeUUIDs.append(bpUUID)  // Blueprint must be FIRST for cloud engine isPrimary
            }
            let linkedSwipeUUIDs = idea.ideaMetadata?.linkedSwipeIds ?? []
            let insightSwipeUUIDs = insight?.matchingSwipes?.map(\.swipeAtomUUID) ?? []
            for uuid in linkedSwipeUUIDs + insightSwipeUUIDs {
                if !allSwipeUUIDs.contains(uuid) { allSwipeUUIDs.append(uuid) }
            }
            let inheritedSwipeUUIDs = allSwipeUUIDs

            let linkedConnectionUUIDs = idea.ideaMetadata?.linkedConnectionIds ?? []

            let inheritedFramework: String? = {
                if let selected = sessionState.selectedFramework {
                    return selected
                }
                return insight?.frameworkRecommendations?.first?.framework.rawValue
            }()
            let inheritedHooks: [String] = {
                if !editableHooks.isEmpty {
                    return editableHooks  // User's manual hooks take priority
                }
                if !generatedHooks.isEmpty {
                    return generatedHooks.map(\.hookText)
                }
                return insight?.hookSuggestions?.map(\.hookText) ?? []
            }()
            let nowISO = ISO8601.string(from: Date())

            let inheritedClientUUID = linkedClient?.uuid ?? idea.ideaMetadata?.clientUUID

            // Build ContentFocusModeState with description = the original idea text
            var focusState = ContentFocusModeState(atomUUID: contentAtom.uuid)
            // Expand mentioned atoms into the core idea text for writing context
            let mentionedUUIDs = idea.ideaMetadata?.mentionedAtomUUIDs ?? []
            var enrichedBody = editableBody
            if !mentionedAtoms.isEmpty {
                enrichedBody = MentionContextHelper.expandMentionsForWritingEngine(
                    text: editableBody, atoms: mentionedAtoms
                )
            }
            focusState.contentDescription = enrichedBody
            focusState.coreIdea = enrichedBody
            focusState.hooks = inheritedHooks
            focusState.clientProfileUUID = inheritedClientUUID

            if let codexOutline,
               let draftTemplate = CodexOutlineDraftTemplate.make(from: codexOutline) {
                focusState.draftContent = draftTemplate
                focusState.richDraftDocument = RichDocument.migrateLegacy(draftTemplate)
            }

            // Convert user's codex outline notes to focusState.outline for display
            // Cloud engine handles full physics plan during writing — no local AI generation
            if let codexOutline = codexOutline, !codexOutline.slides.isEmpty {
                focusState.outline = codexOutline.slides.compactMap { slide in
                    guard let note = slide.note, !note.isEmpty else { return nil }
                    return OutlineItem(
                        title: note,
                        reasoning: "",
                        sortOrder: slide.position - 1
                    )
                }
                if focusState.outline.isEmpty {
                    // All slides had empty notes — create generic placeholders
                    focusState.outline = codexOutline.slides.map { slide in
                        OutlineItem(title: "Slide \(slide.position)", reasoning: "", sortOrder: slide.position - 1)
                    }
                }
                focusState.isAISuggestedOutline = false
            }

            // Set ContentAtomMetadata on the content atom
            var contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
                ?? ContentAtomMetadata(phase: .ideation, wordCount: 0)
            contentMeta.sourceIdeaUUID = idea.uuid
            contentMeta.inheritedSwipeUUIDs = inheritedSwipeUUIDs.isEmpty ? nil : inheritedSwipeUUIDs
            contentMeta.inheritedConnectionIds = linkedConnectionUUIDs.isEmpty ? nil : linkedConnectionUUIDs
            contentMeta.inheritedMentionedAtomUUIDs = mentionedUUIDs.isEmpty ? nil : mentionedUUIDs
            contentMeta.inheritedFramework = inheritedFramework
            contentMeta.inheritedHooks = inheritedHooks.isEmpty ? nil : inheritedHooks
            contentMeta.clientProfileUUID = inheritedClientUUID
            contentMeta.blueprintSwipeUUID = selectedBlueprintUUID
            contentMeta.activatedAt = nowISO
            contentMeta.phaseEnteredAt = nowISO

            // Codex-era field transfers
            contentMeta.inheritedArcType = selectedArcType
            if let outline = codexOutline, let data = try? JSONEncoder().encode(outline) {
                contentMeta.inheritedCodexOutline = String(data: data, encoding: .utf8)
            }
            contentMeta.inheritedCreativeDirection = editableCreativeDirection.isEmpty ? nil : editableCreativeDirection
            contentMeta.inheritedContext = editableContext.isEmpty ? nil : editableContext
            let includedResearch = researchResults.filter { $0.isIncluded }
            if !includedResearch.isEmpty, let data = try? JSONEncoder().encode(includedResearch) {
                contentMeta.inheritedResearchResults = String(data: data, encoding: .utf8)
            }
            focusState.inheritedResearchResults = includedResearch.isEmpty ? nil : includedResearch
            if let history = chatHistory.isEmpty ? nil : chatHistory,
               let data = try? JSONEncoder().encode(history) {
                contentMeta.inheritedChatHistory = String(data: data, encoding: .utf8)
            }
            // Collect all canonical names for the writing engine
            var allNames: Set<String> = []
            if let outline = codexOutline {
                for slide in outline.slides {
                    if let sa = slide.speechAct { allNames.insert(sa) }
                    allNames.formUnion(slide.readerDeltas)
                    if let f = slide.frame { allNames.insert(f) }
                    if let d = slide.distance { allNames.insert(d) }
                    allNames.formUnion(slide.techniques)
                    if let t = slide.transition { allNames.insert(t) }
                }
            }
            contentMeta.codexElementNames = allNames.isEmpty ? nil : Array(allNames)

            // Merge focus state fields into the content atom's metadata
            let focusFields = focusState.toAtomFields(existingMetadata: contentMeta.toJSON())

            var updatedContent = contentAtom.addingLink(.contentToIdea(idea.uuid))
            if let inheritedClientUUID {
                updatedContent = updatedContent.addingLink(.contentToClient(inheritedClientUUID))
            }
            updatedContent.metadata = focusFields.metadata
            updatedContent.body = focusFields.body
            updatedContent.updatedAt = nowISO
            updatedContent.localVersion += 1
            _ = try await AtomRepository.shared.update(updatedContent)

            // Add bidirectional links and update idea metadata
            var updatedIdea = idea
                .addingLink(.ideaToContent(contentAtom.uuid))
            updatedIdea = updatedIdea.withUpdatedIdeaMetadata { meta in
                meta.ideaStatus = .inProduction
                meta.statusChangedAt = nowISO
                var uuids = meta.contentUUIDs ?? []
                uuids.append(contentAtom.uuid)
                meta.contentUUIDs = uuids
            }
            updatedIdea.updatedAt = nowISO
            updatedIdea.localVersion += 1
            idea = try await AtomRepository.shared.update(updatedIdea)
            selectedStatus = .inProduction

            // Notify the Ideas Library to remove this idea (it's now a content piece)
            NotificationCenter.default.post(
                name: Notification.Name("ideaActivated"),
                object: nil,
                userInfo: ["uuid": idea.uuid]
            )

            // Leave a breadcrumb so Content Focus Mode recognizes this mount as a
            // continuation of the Atelier and uses a cross-fade instead of a stagger.
            FocusTransitionCoordinator.shared.markPromotion(contentAtomUUID: contentAtom.uuid)

            // Post notification to open the new content in focus mode with auto-draft trigger
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: [
                    "atomUUID": contentAtom.uuid,
                    "autoGenerate": true,
                    "restoreCommandKOnFocusClose": false
                ]
            )

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
            scheduleHookGeneration()
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
            scheduleHookGeneration()
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

    // MARK: - AI Hook Generation

    /// Schedule debounced hook generation (5s delay).
    func scheduleHookGeneration() {
        hookGenerationTask?.cancel()
        hookGenerationTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await generateHooksFromLinkedSwipes()
        }
    }

    /// Generate hooks from linked swipes using ResearchService.
    func generateHooksFromLinkedSwipes() async {
        guard !linkedSwipes.isEmpty else {
            generatedHooks = []
            return
        }
        guard !isGeneratingHooks else { return }

        isGeneratingHooks = true
        defer { isGeneratingHooks = false }

        // Build swipe context
        var swipeContext = ""
        for swipe in linkedSwipes.prefix(5) {
            let analysis = swipe.swipeAnalysis
            let hookText = swipe.researchMetadata?.hook ?? analysis?.hookText ?? ""
            let hookType = analysis?.hookType?.displayName ?? "unknown"
            let score = analysis?.hookScore.map { String(format: "%.1f", $0) } ?? "?"
            let title = swipe.title ?? "Untitled"
            swipeContext += "- \"\(hookText)\" (type: \(hookType), score: \(score)/10, source: \(title))\n"
        }

        // Build client voice context
        var voiceContext = ""
        if let client = linkedClient {
            let clientMeta = client.clientMetadata
            if let voice = clientMeta?.brandVoice, !voice.isEmpty {
                voiceContext = "\nClient voice: \(voice)"
            }
        }

        let prompt = """
        Generate 3-5 hook suggestions for this idea, inspired by the structural patterns in the linked swipe files.

        Idea title: \(editableTitle)
        Core idea: \(editableBody)\(voiceContext)

        Linked swipe hooks:
        \(swipeContext)

        For each hook, provide:
        - "hookText": The full hook text (1-2 sentences)
        - "hookType": One of: question, statistic, story, contrarian, authority, vulnerability, curiosity, challenge, comparison, metaphor, prediction, confession, secret, directAddress
        - "sourceSwipeTitle": Which swipe file inspired this hook pattern
        - "estimatedScore": Predicted hook score 1-10

        Return ONLY this JSON:
        {"hooks":[{"hookText":"...","hookType":"...","sourceSwipeTitle":"...","estimatedScore":7.5}]}
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let startIdx = cleaned.firstIndex(of: "{"),
                  let endIdx = cleaned.lastIndex(of: "}") else { return }

            let jsonString = String(cleaned[startIdx...endIdx])
            guard let data = jsonString.data(using: .utf8) else { return }

            struct HookResponse: Decodable {
                struct Item: Decodable {
                    let hookText: String
                    let hookType: String?
                    let sourceSwipeTitle: String?
                    let estimatedScore: Double?
                }
                let hooks: [Item]
            }

            if let parsed = try? JSONDecoder().decode(HookResponse.self, from: data) {
                generatedHooks = parsed.hooks.map { item in
                    HookSuggestion(
                        hookText: item.hookText,
                        hookType: item.hookType.flatMap { SwipeHookType(rawValue: $0) },
                        sourceSwipeTitle: item.sourceSwipeTitle,
                        estimatedScore: item.estimatedScore
                    )
                }
            }
        } catch {
            print("IdeaFocusMode: generateHooksFromLinkedSwipes failed: \(error)")
        }
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
        let sequence = nextSaveSequence(markModified: true)
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
        let sequence = nextSaveSequence(markModified: true)
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
        let sequence = nextSaveSequence(markModified: true)
        let snapshot = makeSaveSnapshot()
        sessionState.selectedHookIndex = selectedHookIndex
        sessionState.save()

        // Async close save: the focus-exit animation must never block on the
        // DB write lock (cross-process busy timeout is 5s). The registry
        // escort preserves the quit guarantee — terminating mid-write flushes
        // the captured snapshot synchronously; the commit unregisters it.
        let escortID = "idea-close-\(idea.uuid)"
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
        let sequence = nextSaveSequence(markModified: true)
        let snapshot = makeSaveSnapshot()
        sessionState.selectedHookIndex = selectedHookIndex
        sessionState.save()

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

    private func nextSaveSequence(markModified: Bool) -> UInt64 {
        if markModified {
            lastModified = Date()
        }
        saveSequence += 1
        return saveSequence
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
