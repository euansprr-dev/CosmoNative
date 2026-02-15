// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift
// ViewModel for Idea Focus Mode brainstorm workspace
// February 2026

import SwiftUI
import Combine

// MARK: - Idea Focus Mode ViewModel

/// Drives the Idea Focus Mode workspace -- manages editable fields, analysis pipeline,
/// framework selection, blueprint generation, and content promotion.
@MainActor
class IdeaFocusModeViewModel: ObservableObject {
    // MARK: - Published State (Editable Fields)

    @Published var idea: Atom
    @Published var editableTitle: String
    @Published var editableBody: String
    @Published var selectedStatus: IdeaStatus
    @Published var selectedFormat: ContentFormat?
    @Published var selectedPlatform: IdeaPlatform?
    @Published var tags: [String]
    @Published var selectedHookIndex: Int?

    // MARK: - Published State (Intelligence)

    @Published var insight: IdeaInsight?
    @Published var isAnalyzing: Bool = false
    @Published var analysisStage: String = ""
    @Published var blueprint: ContentBlueprint?
    @Published var linkedClient: Atom?
    @Published var clientProfiles: [Atom] = []

    // MARK: - Session State

    @Published var sessionState: IdeaFocusModeState

    // MARK: - Private

    private var autoSaveTask: Task<Void, Never>?
    private var autoEnrichTask: Task<Void, Never>?
    private let autoSaveDelay: TimeInterval = 1.5
    private let autoEnrichDelay: TimeInterval = 1.5

    // MARK: - Initialization

    init(atom: Atom) {
        self.idea = atom

        let meta = atom.ideaMetadata

        self.editableTitle = atom.title ?? ""
        self.editableBody = atom.body ?? ""
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

        // Load client profiles in background
        Task { await loadClientProfiles() }

        // If a client is assigned, load it
        if let clientUUID = meta?.clientUUID {
            Task { await loadLinkedClient(uuid: clientUUID) }
        }
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
                meta.lastAnalyzedAt = ISO8601DateFormatter().string(from: Date())
                meta.insightScore = calculateInsightScore(result)
                meta.matchingSwipeCount = result.matchingSwipes?.count
                if let topFramework = result.frameworkRecommendations?.first {
                    meta.suggestedFramework = topFramework.framework.rawValue
                }
                if let topHook = result.hookSuggestions?.first {
                    meta.suggestedHookType = topHook.hookType?.rawValue
                }
            }
            updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
            updatedAtom.localVersion += 1

            idea = try await AtomRepository.shared.update(updatedAtom)

            // Update session state
            sessionState.lastAnalyzedAt = ISO8601DateFormatter().string(from: Date())
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
        }
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
            updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
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
                    meta.lastAnalyzedAt = ISO8601DateFormatter().string(from: Date())
                }
                analysisAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
                analysisAtom.localVersion += 1
                idea = try await AtomRepository.shared.update(analysisAtom)
            }

            // Create content atom with empty body — the idea text goes into coreIdea,
            // not into draftContent (which maps to atom.body).
            let contentAtom = try await AtomRepository.shared.createContent(
                title: editableTitle,
                body: nil,
                contentType: selectedFormat?.rawValue ?? "post"
            )

            // Determine inherited metadata from insight
            let inheritedSwipeUUIDs = insight?.matchingSwipes?.map(\.swipeAtomUUID) ?? []
            let inheritedFramework: String? = {
                if let selected = sessionState.selectedFramework {
                    return selected
                }
                return insight?.frameworkRecommendations?.first?.framework.rawValue
            }()
            let inheritedHooks = insight?.hookSuggestions?.map(\.hookText) ?? []
            let nowISO = ISO8601DateFormatter().string(from: Date())

            // Build ContentFocusModeState with coreIdea = the original idea text
            var focusState = ContentFocusModeState(atomUUID: contentAtom.uuid)
            focusState.coreIdea = editableBody

            // Generate AI-suggested outline using ResearchService
            let aiOutline = await generateOutline(
                ideaTitle: editableTitle,
                ideaBody: editableBody,
                framework: inheritedFramework,
                format: selectedFormat,
                swipes: insight?.matchingSwipes
            )

            if !aiOutline.isEmpty {
                focusState.outline = aiOutline
                focusState.isAISuggestedOutline = true
            } else if let bp = blueprint {
                // Fallback: seed outline from blueprint sections if AI call fails
                var sortOrder = 0
                if let hook = bp.suggestedHook, !hook.isEmpty {
                    focusState.outline.append(OutlineItem(title: "Hook & Setup", reasoning: hook, sortOrder: sortOrder))
                    sortOrder += 1
                }
                for section in bp.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    let detail = section.suggestedContent ?? section.purpose
                    focusState.outline.append(OutlineItem(title: section.label, reasoning: detail, sortOrder: sortOrder))
                    sortOrder += 1
                }
                if let cta = bp.suggestedCTA, !cta.isEmpty {
                    focusState.outline.append(OutlineItem(title: "CTA", reasoning: cta, sortOrder: sortOrder))
                }
                focusState.isAISuggestedOutline = true
            }

            // Set ContentAtomMetadata on the content atom
            var contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
                ?? ContentAtomMetadata(phase: .ideation, wordCount: 0)
            contentMeta.sourceIdeaUUID = idea.uuid
            contentMeta.inheritedSwipeUUIDs = inheritedSwipeUUIDs.isEmpty ? nil : inheritedSwipeUUIDs
            contentMeta.inheritedFramework = inheritedFramework
            contentMeta.inheritedHooks = inheritedHooks.isEmpty ? nil : inheritedHooks
            contentMeta.activatedAt = nowISO
            contentMeta.phaseEnteredAt = nowISO

            // Merge focus state fields into the content atom's metadata
            let focusFields = focusState.toAtomFields(existingMetadata: contentMeta.toJSON())

            var updatedContent = contentAtom.addingLink(.contentToIdea(idea.uuid))
            updatedContent.metadata = focusFields.metadata
            updatedContent.body = focusFields.body  // nil — draftContent starts empty
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

            // Award 10 XP to creative dimension for idea activation
            await awardActivationXP(contentUUID: contentAtom.uuid)

            // Post notification to open the new content in focus mode
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": contentAtom.uuid]
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

    /// Award 10 XP for idea activation (promote to content).
    private func awardActivationXP(contentUUID: String) async {
        let pipelineService = ContentPipelineService()
        await pipelineService.awardContentXP(
            xp: 10,
            reason: "Idea activated to content",
            contentUUID: contentUUID
        )
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
            updatedClient.updatedAt = ISO8601DateFormatter().string(from: Date())
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

        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
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

        var updatedAtom = idea.withUpdatedIdeaMetadata { meta in
            meta.ideaStatus = status
            meta.statusChangedAt = ISO8601DateFormatter().string(from: Date())
        }
        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
        updatedAtom.localVersion += 1

        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
        } catch {
            print("IdeaFocusMode: failed to update status: \(error)")
        }
    }

    // MARK: - Save

    /// Persist current editable fields (title, body, tags, format, platform) to the atom.
    func save() async {
        var updatedAtom = idea
        updatedAtom.title = editableTitle.isEmpty ? nil : editableTitle
        updatedAtom.body = editableBody.isEmpty ? nil : editableBody

        updatedAtom = updatedAtom.withUpdatedIdeaMetadata { meta in
            meta.tags = tags.isEmpty ? nil : tags
            meta.contentFormat = selectedFormat
            meta.platform = selectedPlatform
            meta.ideaStatus = selectedStatus
        }

        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
        updatedAtom.localVersion += 1

        do {
            idea = try await AtomRepository.shared.update(updatedAtom)
        } catch {
            print("IdeaFocusMode: save failed: \(error)")
        }
    }

    /// Schedule a debounced auto-save (call after each keystroke in text fields).
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// Force immediate save -- called when the view disappears.
    func saveOnClose() {
        autoSaveTask?.cancel()
        sessionState.selectedHookIndex = selectedHookIndex
        sessionState.save()
        Task { await save() }
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
