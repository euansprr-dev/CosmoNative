// CosmoOS/Agent/Core/AgentContextAssembler.swift
// Assembles intent-aware system prompts with live user data for the Cosmo Agent

import Foundation

@MainActor
class AgentContextAssembler {
    static let shared = AgentContextAssembler()

    private let atomRepo = AtomRepository.shared

    /// Maximum approximate tokens for the assembled context (chars / 4).
    /// Increased to 8000 for strategy/query intents that need more context.
    private var tokenBudget = 6000

    /// Skills that were injected into the last assembled prompt (for transparency).
    private(set) var lastInjectedSkills: [(rule: String, category: String, intent: String?)] = []

    /// Message count threshold above which conversation history is summarized.
    private let summarizationThreshold = 15

    // MARK: - Context Cache (conversation-scoped TTL)

    /// Cached dynamic context to avoid re-fetching from GRDB on every message.
    private var cachedDynamicContext: (conversationId: String, intent: AgentIntent?, activeClientUUID: String?, context: String, timestamp: Date)?

    /// Cached linked atom context (separate from main context since linked UUIDs can change mid-conversation).
    private var cachedLinkedContext: (uuids: [String], context: String, timestamp: Date)?

    /// How long cached context stays valid (2 minutes).
    private let contextCacheTTL: TimeInterval = 120

    /// The default identity prompt text, exposed so the Settings UI can show it as a baseline.
    static let defaultIdentityPrompt: String = CosmoDefaultAgentPrompt.text

    private init() {}

    // MARK: - System Prompt Assembly

    /// Assemble the full system prompt from identity, user context, preferences,
    /// and conversation history. Now intent-aware for smarter context selection.
    func assembleSystemPrompt(
        conversation: AgentConversation?,
        preferences: [AgentPreference],
        tools: [LLMToolDefinition],
        intent: AgentIntent? = nil,
        activeItemsContext: String? = nil,
        systemPromptOverride: String? = nil,
        lightweightContext: Bool = false
    ) async -> SystemPrompt {
        // Increase token budget for strategy/query intents that need swipe library + pipeline data
        if let intent = intent, intent == .strategy || intent == .query {
            tokenBudget = 8000
        } else {
            tokenBudget = 6000
        }

        // --- Cached sections: static content that stays the same across requests ---
        var cachedSections: [(priority: Int, content: String)] = []

        // Layer 1: Identity and personality (always included, highest priority)
        // Uses lightweight identity for simple intents (capture/correct/meta) to save ~1.5K tokens
        let source = conversation?.source ?? .inApp
        let identity = identityPrompt(source: source, intent: intent)
        cachedSections.append((priority: 0, content: identity))

        if let systemPromptOverride,
           !systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedSections.append((priority: 1, content: systemPromptOverride))
        }

        // Layer 3.25: Writing methodology for writing intents
        // For draft/brainstorm: condensed methodology + skill module titles (full context lives in
        // UnifiedWritingEngine's own system prompt — the outer agent only coordinates tools)
        // For strategy/analyze: condensed version to save tokens
        let writingIntents: Set<AgentIntent> = [.draft, .brainstorm, .strategy, .analyze]
        if let intent = intent, writingIntents.contains(intent) {
            let methodology = writingMethodologyContext()
            cachedSections.append((priority: 2, content: methodology))
        }

        // Layer 7: Tool usage guidelines (same per intent, cacheable)
        if !tools.isEmpty {
            let toolSection = toolGuidelines(tools)
            cachedSections.append((priority: 6, content: toolSection))
        }

        let cachedPrompt = cachedSections
            .sorted { $0.priority < $1.priority }
            .map { $0.content }
            .joined(separator: "\n\n")

        // --- Dynamic sections: live data that changes every request ---
        // GRDB-heavy layers (2, 3, 3.5, 5.5) are cached with a 2-minute TTL to avoid
        // re-fetching client profiles, swipes, taste profiles, etc. on every message.
        // Per-message layers (3.75 active items, 4 preferences, 4.5 skills, 5 conversation) stay fresh.
        var dynamicSections: [(priority: Int, content: String)] = []
        var usedTokens = estimateTokens(cachedPrompt)

        let convId = conversation?.id ?? ""

        // Inline edits inject their own compact "Resolved Inline Skill Context", so skip the
        // heavy GRDB/retrieval layers (client intelligence, swipes, taste, recent analyses) —
        // they are redundant here and are the bulk of cold-call latency.
        if !lightweightContext {
        // Resolve active client UUID for cache keying (prevents cross-client contamination)
        var activeClientUUID: String? = nil
        if let conv = conversation, !conv.linkedAtomUUIDs.isEmpty {
            for uuid in conv.linkedAtomUUIDs.reversed() {
                if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .content,
                   let clientUUID = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID {
                    activeClientUUID = clientUUID
                    break
                }
                if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .clientProfile {
                    activeClientUUID = uuid
                    break
                }
            }
        }

        // Fallback: extract client name from latest user message (handles first-turn case)
        if activeClientUUID == nil, let conv = conversation,
           let lastUserMsg = conv.messages.last(where: { $0.role == .user }) {
            let lower = lastUserMsg.content.lowercased()
            if let clients = try? await atomRepo.clientProfiles() {
                for client in clients {
                    guard let name = client.title, !name.isEmpty else { continue }
                    let nameLower = name.lowercased()
                    if lower.contains("for \(nameLower)") || lower.contains("about \(nameLower)") {
                        activeClientUUID = client.uuid
                        break
                    }
                }
            }
        }

        let cacheHit = cachedDynamicContext.map { cached in
            cached.conversationId == convId &&
            cached.intent == intent &&
            cached.activeClientUUID == activeClientUUID &&
            Date().timeIntervalSince(cached.timestamp) < contextCacheTTL
        } ?? false

        if cacheHit, let cached = cachedDynamicContext {
            // Use cached GRDB context (layers 2, 3, 3.5, 5.5)
            dynamicSections.append((priority: 1, content: cached.context))
            usedTokens += estimateTokens(cached.context)
        } else {
            // Fetch fresh from GRDB and cache
            var grdbSections: [String] = []

            // Layer 2: Intent-aware live user context from GRDB
            let linkedUUIDs = conversation?.linkedAtomUUIDs ?? []
            let userContext = await buildIntentAwareContext(intent: intent, linkedAtomUUIDs: linkedUUIDs)
            if !userContext.isEmpty {
                grdbSections.append(userContext)
            }

            // Layer 3: Taste profile (high priority for draft/strategy/brainstorm intents)
            let tasteIntents: Set<AgentIntent> = [.draft, .strategy, .brainstorm, .analyze]
            if let intent = intent, tasteIntents.contains(intent) {
                let taste = await tasteProfileContext()
                if !taste.isEmpty {
                    grdbSections.append(taste)
                }
            }

            // Layer 3.5: Standing instructions (so the LLM knows what recurring tasks exist)
            let standingInstructionContext = await standingInstructionsPrompt()
            if !standingInstructionContext.isEmpty {
                grdbSections.append(standingInstructionContext)
            }

            // Layer 5.5: Auto-load saved analyses for creative intents (WP6)
            let analysisIntents: Set<AgentIntent> = [.draft, .strategy, .analyze, .brainstorm]
            if let intent = intent, analysisIntents.contains(intent) {
                // Reuse already-resolved activeClientUUID to scope analyses
                var activeClientName: String? = nil
                if let clientUUID = activeClientUUID,
                   let clientAtom = try? await atomRepo.fetch(uuid: clientUUID) {
                    activeClientName = clientAtom.title
                }
                let analysisContext = await loadRecentAnalyses(filteredToClient: activeClientName)
                if !analysisContext.isEmpty {
                    grdbSections.append(analysisContext)
                }
            }

            let combinedGrdbContext = grdbSections.joined(separator: "\n\n")
            cachedDynamicContext = (conversationId: convId, intent: intent, activeClientUUID: activeClientUUID, context: combinedGrdbContext, timestamp: Date())

            if !combinedGrdbContext.isEmpty {
                dynamicSections.append((priority: 1, content: combinedGrdbContext))
                usedTokens += estimateTokens(combinedGrdbContext)
            }
        }
        } // end if !lightweightContext

        // Layer 3.75: Active items context (numbered list resolution) — always fresh
        if let itemsCtx = activeItemsContext, !itemsCtx.isEmpty {
            dynamicSections.append((priority: 2, content: itemsCtx))
            usedTokens += estimateTokens(itemsCtx)
        }

        // Layer 4: Learned preferences — always fresh
        if !preferences.isEmpty {
            let prefSection = preferencesPrompt(preferences)
            dynamicSections.append((priority: 3, content: prefSection))
            usedTokens += estimateTokens(prefSection)
        }

        // Layer 4.5: Learned skills (intent-filtered) — always fresh
        let skillsSection = await learnedSkillsContext(intent: intent, conversation: conversation)
        if !skillsSection.isEmpty {
            dynamicSections.append((priority: 3, content: skillsSection))
            usedTokens += estimateTokens(skillsSection)
        }

        // Layer 5: Conversation history (summarized if long) — always fresh
        if let conv = conversation, !conv.messages.isEmpty {
            let convContext = await conversationContext(conv)
            dynamicSections.append((priority: 4, content: convContext))
            usedTokens += estimateTokens(convContext)
        }

        // Layer 6: Linked atom context — cached separately since linked UUIDs can change
        if let conv = conversation, !conv.linkedAtomUUIDs.isEmpty {
            let linkedUUIDs = conv.linkedAtomUUIDs
            let linkedCacheHit = cachedLinkedContext.map { cached in
                cached.uuids == linkedUUIDs &&
                Date().timeIntervalSince(cached.timestamp) < contextCacheTTL
            } ?? false

            if linkedCacheHit, let cached = cachedLinkedContext {
                dynamicSections.append((priority: 5, content: cached.context))
                usedTokens += estimateTokens(cached.context)
            } else {
                let linkedContext = await injectLinkedContext(atomUUIDs: linkedUUIDs)
                if !linkedContext.isEmpty {
                    cachedLinkedContext = (uuids: linkedUUIDs, context: linkedContext, timestamp: Date())
                    dynamicSections.append((priority: 5, content: linkedContext))
                    usedTokens += estimateTokens(linkedContext)
                }
            }
        }

        // Apply token budget to dynamic sections
        let dynamicPrompt = applyTokenBudget(sections: dynamicSections, budget: max(0, tokenBudget - estimateTokens(cachedPrompt)))

        return SystemPrompt(cached: cachedPrompt, dynamic: dynamicPrompt)
    }

    // MARK: - Token Budget

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Assemble sections respecting the token budget. Higher-priority sections
    /// (lower priority number) are kept first; lower-priority sections are truncated.
    private func applyTokenBudget(sections: [(priority: Int, content: String)], budget: Int? = nil) -> String {
        let sorted = sections.sorted { $0.priority < $1.priority }
        var result: [String] = []
        var remaining = budget ?? tokenBudget

        for section in sorted {
            let sectionTokens = estimateTokens(section.content)
            if sectionTokens <= remaining {
                result.append(section.content)
                remaining -= sectionTokens
            } else if remaining > 200 {
                // Truncate to fit remaining budget (approximate chars)
                let maxChars = remaining * 4
                let truncated = String(section.content.prefix(maxChars))
                    + "\n... [truncated for context budget]"
                result.append(truncated)
                remaining = 0
            }
            // Skip section entirely if no room
        }

        return result.joined(separator: "\n\n")
    }

    // MARK: - Intent-Aware Context

    /// Build context sections relevant to the current intent.
    private func buildIntentAwareContext(intent: AgentIntent?, linkedAtomUUIDs: [String] = []) async -> String {
        guard let intent = intent else {
            // Default context: schedule + tasks + ideas (original behavior)
            return await buildDefaultContext()
        }

        switch intent {
        case .strategy, .query:
            // For strategy/query, pull pipeline + recent drafts + swipe stats
            return await buildStrategyContext()

        case .plan:
            // Calendar + objectives + quest progress
            return await buildPlanContext()

        case .draft:
            // Current draft content + source idea + matched swipes
            return await buildDraftContext(linkedAtomUUIDs: linkedAtomUUIDs)

        case .analyze, .debrief:
            // Full analytics: dimensions, streaks, content performance
            return await buildAnalyticsContext()

        case .capture:
            // Lightweight: just client profiles
            return await buildCaptureContext()

        case .brainstorm:
            // Ideas + swipe stats + client profiles (scoped to active client)
            return await buildBrainstormContext(linkedAtomUUIDs: linkedAtomUUIDs)

        case .reflect:
            // Dimensions + quest summary + recent activity
            return await buildReflectContext()

        case .execute, .correct, .meta:
            return await buildDefaultContext()
        }
    }

    // MARK: - Context Builders

    private func buildDefaultContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Live Data]"]

        let todayBlocks = await fetchTodayBlocks()
        if !todayBlocks.isEmpty {
            let blockSummaries = todayBlocks.prefix(5).map { block -> String in
                let title = block.title ?? "Untitled"
                let meta = block.metadataValue(as: ScheduleBlockMetadata.self)
                let status = (meta?.isCompleted ?? false) ? "done" : "pending"
                let time = formatTimeRange(start: meta?.startTime, end: meta?.endTime)
                return "  - \(time) \(title) [\(status)]"
            }
            parts.append("Today's schedule (\(todayBlocks.count) blocks):")
            parts.append(contentsOf: blockSummaries)
        } else {
            parts.append("Today's schedule: No blocks scheduled")
        }

        let activeTasks = await fetchActiveTasks()
        let unscheduledCount = activeTasks.filter { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return meta?.isUnscheduled == true || meta?.startTime == nil
        }.count
        parts.append("Active tasks: \(activeTasks.count) total, \(unscheduledCount) unscheduled")

        let recentIdeas = await fetchRecentIdeas()
        if !recentIdeas.isEmpty {
            let ideaSummaries = recentIdeas.prefix(5).map { "  - \($0.title ?? "Untitled")" }
            parts.append("Recent ideas:")
            parts.append(contentsOf: ideaSummaries)
        }

        let clientNames = await fetchClientProfileNames()
        if !clientNames.isEmpty {
            parts.append("Client profiles: \(clientNames.joined(separator: ", "))")
        }

        // Surface in-progress content so the agent doesn't create duplicates
        let activeContent = await fetchActiveContentSummary()
        if !activeContent.isEmpty {
            parts.append(activeContent)
        }

        return parts.joined(separator: "\n")
    }

    private func buildStrategyContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Content Strategy]"]

        // Pipeline status
        let pipelineCounts = await fetchPipelinePhaseCounts()
        if !pipelineCounts.isEmpty {
            let pipelineStr = pipelineCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            parts.append("Content pipeline: \(pipelineStr)")
        }

        // Recent drafts (last 5 content atoms)
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            let recentDrafts = content.prefix(5)
            if !recentDrafts.isEmpty {
                parts.append("Recent content:")
                for draft in recentDrafts {
                    let meta = draft.metadataValue(as: ContentAtomMetadata.self)
                    let phase = meta?.phase.displayName ?? "Ideation"
                    let platform = meta?.platform?.rawValue ?? "unset"
                    parts.append("  - \(draft.title ?? "Untitled") [\(phase)] (\(platform))")
                }
            }
        } catch {}

        // Swipe library stats
        do {
            let research = try await atomRepo.fetchAll(type: .research)
            let swipes = research.filter { $0.isSwipeFileAtom }
            parts.append("Swipe library: \(swipes.count) total")

            // Hook distribution (top 5) — read from swipeAnalysis, not metadata
            var hookCounts: [String: Int] = [:]
            var fwCounts: [String: Int] = [:]
            for atom in swipes {
                if let analysis = atom.swipeAnalysis {
                    if let hookType = analysis.hookType {
                        hookCounts[hookType.rawValue, default: 0] += 1
                    }
                    if let framework = analysis.frameworkType {
                        fwCounts[framework.rawValue, default: 0] += 1
                    }
                } else if let meta = atom.metadataDict {
                    // Fallback to metadata
                    if let hook = meta["hookType"] as? String {
                        hookCounts[hook, default: 0] += 1
                    }
                    if let fw = meta["framework"] as? String {
                        fwCounts[fw, default: 0] += 1
                    }
                }
            }
            let topHooks = hookCounts.sorted { $0.value > $1.value }.prefix(5)
            if !topHooks.isEmpty {
                parts.append("Top hooks: \(topHooks.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
            }

            let topFW = fwCounts.sorted { $0.value > $1.value }.prefix(5)
            if !topFW.isEmpty {
                parts.append("Top frameworks: \(topFW.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
            }

            // Recent 5 swipe titles (helps LLM reason about "what swipes do I have")
            let recentSwipes = swipes.prefix(5)
            if !recentSwipes.isEmpty {
                parts.append("Recent swipes:")
                for swipe in recentSwipes {
                    let hookLabel = swipe.swipeAnalysis?.hookType?.rawValue ?? ""
                    let hookSuffix = hookLabel.isEmpty ? "" : " [\(hookLabel)]"
                    parts.append("  - \(swipe.title ?? "Untitled")\(hookSuffix)")
                }
            }
        } catch {}

        let clientNames = await fetchClientProfileNames()
        if !clientNames.isEmpty {
            parts.append("Client profiles: \(clientNames.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }

    private func buildPlanContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Planning & Schedule]"]

        // Today's schedule
        let todayBlocks = await fetchTodayBlocks()
        if !todayBlocks.isEmpty {
            let blockSummaries = todayBlocks.map { block -> String in
                let title = block.title ?? "Untitled"
                let meta = block.metadataValue(as: ScheduleBlockMetadata.self)
                let status = (meta?.isCompleted ?? false) ? "done" : "pending"
                let time = formatTimeRange(start: meta?.startTime, end: meta?.endTime)
                return "  - \(time) \(title) [\(status)]"
            }
            parts.append("Today's schedule (\(todayBlocks.count) blocks):")
            parts.append(contentsOf: blockSummaries)
        } else {
            parts.append("Today's schedule: No blocks scheduled")
        }

        // Unscheduled tasks
        let activeTasks = await fetchActiveTasks()
        let unscheduled = activeTasks.filter { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return meta?.isUnscheduled == true || meta?.startTime == nil
        }
        if !unscheduled.isEmpty {
            parts.append("Unscheduled tasks (\(unscheduled.count)):")
            for task in unscheduled.prefix(8) {
                let meta = task.metadataValue(as: TaskMetadata.self)
                let priority = meta?.priority ?? "medium"
                parts.append("  - \(task.title ?? "Untitled") [\(priority)]")
            }
        }

        return parts.joined(separator: "\n")
    }

    private func buildDraftContext(linkedAtomUUIDs: [String] = []) async -> String {
        var parts: [String] = ["[USER CONTEXT - Drafting]"]

        // Prioritize the content atom being worked on in this conversation
        var activeContentAtom: Atom?
        var activeContentUUID: String?

        // Check linked atoms first — the most recently linked content atom is the active one
        for uuid in linkedAtomUUIDs.reversed() {
            if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .content {
                activeContentAtom = atom
                activeContentUUID = uuid
                break
            }
        }

        // Surface the active content atom prominently with full context
        if let active = activeContentAtom, let uuid = activeContentUUID {
            let meta = active.metadataValue(as: ContentAtomMetadata.self)
            let title = active.title ?? "Untitled"
            let phase = meta?.phase.displayName ?? "Ideation"
            let words = meta?.wordCount ?? 0
            let draftPreview = String((active.body ?? "").prefix(500))

            parts.append("ACTIVE CONTENT (use this UUID for writing tools):")
            parts.append("  Title: \(title)")
            parts.append("  UUID: \(uuid)")
            parts.append("  Phase: \(phase) | \(words) words")
            if !draftPreview.isEmpty {
                parts.append("  Draft preview: \(draftPreview)")
            }

            // Include source idea if linked
            let links = active.linksList
            let ideaLink = links.first { $0.type == "ideaToContent" || $0.type == "contentToIdea" }
            if let ideaUUID = ideaLink?.uuid,
               let ideaAtom = try? await atomRepo.fetch(uuid: ideaUUID) {
                parts.append("  Source idea: \(ideaAtom.title ?? "Untitled")")
                if let body = ideaAtom.body, !body.isEmpty {
                    parts.append("  Core idea: \(String(body.prefix(200)))")
                }
            }

            // Include matched swipes for active content
            let swipeLinks = links.filter { $0.type == "ideaToSwipe" || $0.type == "swipeToIdea" }
            if !swipeLinks.isEmpty {
                parts.append("  Matched swipes:")
                for link in swipeLinks.prefix(5) {
                    if let swipeAtom = try? await atomRepo.fetch(uuid: link.uuid) {
                        let hook = swipeAtom.metadataDict?["hookType"] as? String ?? "unknown"
                        parts.append("    - \(swipeAtom.title ?? "Untitled") [hook: \(hook)]")
                    }
                }
            }

            // Client profile for this content
            if let clientUUID = meta?.clientProfileUUID,
               let clientAtom = try? await atomRepo.fetch(uuid: clientUUID) {
                parts.append("  Client: \(clientAtom.title ?? "Unknown")")
            }
        }

        // Also show other active drafts (excluding the active one)
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            let otherDrafts = content.filter { atom in
                let meta = atom.metadataValue(as: ContentAtomMetadata.self)
                let phase = meta?.phase.rawValue ?? ""
                return ["ideation", "brainstorm", "outline", "draft"].contains(phase) && atom.uuid != activeContentUUID
            }.prefix(3)

            if !otherDrafts.isEmpty {
                parts.append("")
                parts.append("Other active drafts:")
                for draft in otherDrafts {
                    let meta = draft.metadataValue(as: ContentAtomMetadata.self)
                    let title = draft.title ?? "Untitled"
                    let phase = meta?.phase.displayName ?? "Ideation"
                    parts.append("  - \(title) [\(phase)] (UUID: \(draft.uuid))")
                }
            }
        } catch {}

        let clientNames = await fetchClientProfileNames()
        if !clientNames.isEmpty {
            parts.append("Client profiles: \(clientNames.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }

    private func buildAnalyticsContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Analytics & Performance]"]

        // Content pipeline performance
        let pipelineCounts = await fetchPipelinePhaseCounts()
        if !pipelineCounts.isEmpty {
            let pipelineStr = pipelineCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            parts.append("Pipeline distribution: \(pipelineStr)")
        }

        return parts.joined(separator: "\n")
    }

    private func buildCaptureContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Capture]"]

        // Include full client profiles so the agent can tag captures correctly
        let clientDetails = await fetchClientProfileDetails()
        if !clientDetails.isEmpty {
            parts.append(contentsOf: clientDetails)
        } else {
            parts.append("No client profiles configured")
        }

        // Surface in-progress content so the agent doesn't create duplicates
        let activeContent = await fetchActiveContentSummary()
        if !activeContent.isEmpty {
            parts.append(activeContent)
        }

        return parts.joined(separator: "\n")
    }

    private func buildBrainstormContext(linkedAtomUUIDs: [String] = []) async -> String {
        var parts: [String] = ["[USER CONTEXT - Brainstorm]"]

        // Surface in-progress content so the agent doesn't create duplicates
        let activeContent = await fetchActiveContentSummary()
        if !activeContent.isEmpty {
            parts.append(activeContent)
        }

        // Recent ideas
        let recentIdeas = await fetchRecentIdeas()
        if !recentIdeas.isEmpty {
            parts.append("Recent ideas:")
            for idea in recentIdeas.prefix(8) {
                let preview = String((idea.body ?? "").prefix(100))
                parts.append("  - \(idea.title ?? "Untitled")\(preview.isEmpty ? "" : ": \(preview)")")
            }
        }

        // Swipe stats for inspiration
        do {
            let research = try await atomRepo.fetchAll(type: .research)
            let swipes = research.filter { $0.isSwipeFileAtom }
            parts.append("Swipe library: \(swipes.count) files")

            var hookCounts: [String: Int] = [:]
            for atom in swipes {
                if let hook = atom.metadataDict?["hookType"] as? String {
                    hookCounts[hook, default: 0] += 1
                }
            }
            let topHooks = hookCounts.sorted { $0.value > $1.value }.prefix(3)
            if !topHooks.isEmpty {
                parts.append("Popular hooks: \(topHooks.map { "\($0.key)(\($0.value))" }.joined(separator: ", "))")
            }
        } catch {}

        // Resolve active client from linked atoms (scoped brainstorming)
        var activeClient: Atom? = nil
        for uuid in linkedAtomUUIDs.reversed() {
            if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .content,
               let clientUUID = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
               let clientAtom = try? await atomRepo.fetch(uuid: clientUUID) {
                activeClient = clientAtom
                break
            }
            if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .clientProfile {
                activeClient = atom
                break
            }
        }

        if let client = activeClient {
            // Active client found: inject ONLY this client's full profile
            let profile = formatSingleClientProfile(client)
            if !profile.isEmpty {
                parts.append("Active client profile:")
                parts.append(contentsOf: profile)
            }
            // List other client names (no details) for awareness
            let allNames = await fetchClientProfileNames()
            let otherNames = allNames.filter { $0.lowercased() != (client.title ?? "").lowercased() }
            if !otherNames.isEmpty {
                parts.append("Other clients (names only): \(otherNames.joined(separator: ", "))")
            }
        } else {
            // No active client: inject names only, instruct LLM to ask
            let names = await fetchClientProfileNames()
            if !names.isEmpty {
                parts.append("Available clients: \(names.joined(separator: ", "))")
                parts.append("NOTE: No specific client is active. If brainstorming for a client, ask the user which client before proceeding. Do NOT mix data from different clients.")
            }
        }

        return parts.joined(separator: "\n")
    }

    private func buildReflectContext() async -> String {
        var parts: [String] = ["[USER CONTEXT - Reflection]"]

        // Today's completed blocks
        let todayBlocks = await fetchTodayBlocks()
        let completed = todayBlocks.filter { atom in
            let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
            return meta?.isCompleted == true
        }
        if !completed.isEmpty {
            parts.append("Completed today:")
            for block in completed {
                parts.append("  - \(block.title ?? "Untitled")")
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Saved Analyses Injection (WP6)

    /// Load recent saved analyses for creative context. Shows titles and summaries
    /// so the LLM knows what insights are already on file without re-analyzing.
    private func loadRecentAnalyses(filteredToClient: String? = nil) async -> String {
        do {
            let allLearnings = try await atomRepo.fetchAll(type: .agentLearning)
            let analyses = allLearnings.filter { atom in
                guard let meta = atom.metadata,
                      let data = meta.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let subtype = dict["subtype"] as? String else { return false }
                guard subtype == "agent_analysis" else { return false }
                // Strict client scoping: with client filter, only show that client's analyses;
                // without client filter, only show client-agnostic analyses (no cross-client leakage)
                let analysisClientName = dict["clientName"] as? String ?? ""
                if let clientFilter = filteredToClient {
                    return !analysisClientName.isEmpty &&
                           analysisClientName.lowercased() == clientFilter.lowercased()
                } else {
                    return analysisClientName.isEmpty
                }
            }

            guard !analyses.isEmpty else { return "" }

            var lines = ["[SAVED ANALYSES — use get_saved_analyses to load full content]"]
            for atom in analyses.prefix(5) {
                let title = atom.title ?? "Untitled"
                let meta = atom.metadataDict ?? [:]
                let client = meta["clientName"] as? String ?? ""
                let tags = (meta["tags"] as? [String] ?? []).joined(separator: ", ")
                let preview = String((atom.body ?? "").prefix(100))
                let clientSuffix = client.isEmpty ? "" : " [client: \(client)]"
                let tagSuffix = tags.isEmpty ? "" : " (tags: \(tags))"
                lines.append("  - \(title)\(clientSuffix)\(tagSuffix): \(preview)...")
            }
            if analyses.count > 5 {
                lines.append("  ... and \(analyses.count - 5) more saved analyses")
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    // MARK: - Learned Skills Injection

    /// Load intent-filtered learned skills and format for prompt injection.
    /// Tracks which skills were injected for transparency (WP5).
    private func learnedSkillsContext(intent: AgentIntent?, conversation: AgentConversation?) async -> String {
        // Resolve client UUID from conversation's linked atoms
        var clientUUID: UUID?
        if let conv = conversation, !conv.linkedAtomUUIDs.isEmpty {
            for uuid in conv.linkedAtomUUIDs.reversed() {
                if let atom = try? await atomRepo.fetch(uuid: uuid), atom.type == .content,
                   let clientStr = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
                   let parsed = UUID(uuidString: clientStr) {
                    clientUUID = parsed
                    break
                }
            }
        }

        let intentStr = intent?.rawValue
        let (result, trackedLessons) = await LessonPolicyResolver.resolveForAgent(
            clientUUID: clientUUID,
            intent: intentStr
        )

        // Track injected skills for transparency
        lastInjectedSkills = trackedLessons

        return result
    }

    // MARK: - Knowledge Graph Injection

    /// For each UUID, fetch the atom AND its linked atoms, format as context.
    func injectLinkedContext(atomUUIDs: [String]) async -> String {
        guard !atomUUIDs.isEmpty else { return "" }

        var parts: [String] = [
            "[LINKED KNOWLEDGE CONTEXT]",
            "NOTE: Full pinned-source retrieval is provided in [COSMO CONTEXT PACK]. This linked summary is compatibility context only."
        ]
        var seen = Set<String>()

        for uuid in atomUUIDs.prefix(5) {
            guard !seen.contains(uuid) else { continue }
            seen.insert(uuid)

            do {
                guard let atom = try await atomRepo.fetch(uuid: uuid) else { continue }

                let title = atom.title ?? "Untitled"
                let typeLabel = atom.type.rawValue

                if atom.isSwipeFileAtom {
                    // Swipe files are REFERENCE MATERIAL — show analysis summary, not body text
                    parts.append("[SWIPE REFERENCE] \(title) (UUID: \(uuid))")
                    if let analysis = atom.swipeAnalysis {
                        let summary = MentionContextHelper.swipeAnalysisSummary(analysis)
                        if !summary.isEmpty {
                            parts.append("  Swipe Analysis: \(summary)")
                        }
                    }
                    parts.append("  NOTE: This is a structural reference swipe, not the content being drafted.")
                } else {
                    let body = String((atom.body ?? "").prefix(1500))
                    parts.append("[\(typeLabel)] \(title) (UUID: \(uuid))")
                    if !body.isEmpty {
                        parts.append("  Content: \(body)")
                    }
                }

                // Fetch linked atoms
                let links = atom.linksList
                for link in links.prefix(3) {
                    guard !seen.contains(link.uuid) else { continue }
                    seen.insert(link.uuid)

                    if let linkedAtom = try? await atomRepo.fetch(uuid: link.uuid) {
                        let linkedTitle = linkedAtom.title ?? "Untitled"
                        let linkedType = linkedAtom.type.rawValue
                        let linkType = link.type
                        let linkedBody = String((linkedAtom.body ?? "").prefix(500))
                        parts.append("  -> [\(linkType)] \(linkedType): \(linkedTitle)")
                        if !linkedBody.isEmpty {
                            parts.append("     \(linkedBody)")
                        }

                        // Include swipe analysis for linked swipe files too
                        if linkedAtom.isSwipeFileAtom, let analysis = linkedAtom.swipeAnalysis {
                            let summary = MentionContextHelper.swipeAnalysisSummary(analysis)
                            if !summary.isEmpty {
                                parts.append("     Swipe Analysis: \(summary)")
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }

        return parts.count > 1 ? parts.joined(separator: "\n") : ""
    }

    // MARK: - Taste Profile Injection

    /// Load the creator taste profile via TasteProfileBuilder (reads from .userPreference atoms).
    func tasteProfileContext() async -> String {
        let summary = await TasteProfileBuilder.shared.getProfileSummary()
        guard !summary.isEmpty else { return "" }
        return "[CREATOR TASTE PROFILE]\n" + summary
    }

    // MARK: - Conversation Context (with Summarization)

    private func conversationContext(_ conv: AgentConversation) async -> String {
        var lines = ["[CONVERSATION CONTEXT]"]

        lines.append("Source: \(conv.source.rawValue)")
        lines.append("Messages in conversation: \(conv.messages.count)")

        if let summary = conv.summary {
            lines.append("Previous summary: \(summary)")
        }

        // If the conversation is long, summarize instead of passing all messages
        if conv.messages.count > summarizationThreshold {
            let summary = summarizeConversation(conv)
            lines.append("Conversation summary:")
            lines.append(summary)
        }

        if !conv.linkedAtomUUIDs.isEmpty {
            lines.append("Referenced atoms: \(conv.linkedAtomUUIDs.prefix(10).joined(separator: ", "))")
            if conv.linkedAtomUUIDs.count > 10 {
                lines.append("  ... and \(conv.linkedAtomUUIDs.count - 10) more")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a running summary of a long conversation.
    /// Uses a compact extraction approach without an LLM call (synchronous).
    private func summarizeConversation(_ conv: AgentConversation) -> String {
        var topics: [String] = []
        var actions: [String] = []
        var lastUserMessages: [String] = []
        var recentAssistantTexts: [String] = []

        for msg in conv.messages {
            if msg.role == .user {
                lastUserMessages.append(String(msg.content.prefix(80)))

                // Extract topic keywords
                let words = msg.content.lowercased().split(separator: " ")
                for keyword in ["idea", "swipe", "draft", "content", "schedule", "task", "quest",
                                "brainstorm", "plan", "analyze", "client"] {
                    if words.contains(where: { $0.contains(keyword) }) && !topics.contains(keyword) {
                        topics.append(keyword)
                    }
                }
            }

            if msg.role == .assistant {
                if let toolCalls = msg.toolCalls {
                    for call in toolCalls {
                        let action = call.name.replacingOccurrences(of: "_", with: " ")
                        if !actions.contains(action) {
                            actions.append(action)
                        }
                    }
                }

                // Track text-only assistant responses (not tool calls) that contain numbered lists
                let content = msg.content
                if !content.isEmpty && msg.toolCalls == nil {
                    let hasNumberedList = content.contains("1.") || content.contains("1)") ||
                                          content.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil
                    if hasNumberedList {
                        recentAssistantTexts.append(String(content.prefix(300)))
                        if recentAssistantTexts.count > 2 {
                            recentAssistantTexts.removeFirst()
                        }
                    }
                }
            }
        }

        var summary: [String] = []

        if !topics.isEmpty {
            summary.append("Topics discussed: \(topics.joined(separator: ", "))")
        }

        if !actions.isEmpty {
            summary.append("Tools used: \(actions.prefix(8).joined(separator: ", "))")
        }

        // Include the last 3 user messages for recency
        let recentMessages = lastUserMessages.suffix(3)
        if !recentMessages.isEmpty {
            summary.append("Recent user messages:")
            for msg in recentMessages {
                summary.append("  - \(msg)")
            }
        }

        // Include recent assistant responses with numbered lists for reference resolution
        if !recentAssistantTexts.isEmpty {
            summary.append("Recent assistant responses (for numbered reference resolution):")
            for text in recentAssistantTexts {
                summary.append("  - \(text)")
            }
        }

        return summary.joined(separator: "\n")
    }

    // MARK: - Writing Methodology Context

    /// Condensed writing methodology injected for writing-related intents.
    /// Gives Sonnet enough context to brainstorm competently without burning Opus tokens.
    private func writingMethodologyContext() -> String {
        return """
        [WRITING METHODOLOGY — Condensed]

        7 VIRALITY DRIVERS: Relatability, Novelty, Emotional Intensity, Practical Value, Identity Signaling, Controversy/Tension, Shareability.

        HOOK CHECKLIST: Specific (not vague), Pattern Interrupt, Curiosity Gap, Emotional Trigger, Benefit-Forward, Under 2 Sentences, Platform-Native.

        COPY CHECKLIST: One Idea Per Section, Conversational Tone, Sensory/Concrete Language, Transitions Between Beats, Proof Points (data/stories/examples), Reads Aloud Naturally, No Filler Sentences, Progressive Disclosure (reveal value in layers).

        CTA CHECKLIST: Single Clear Action, Low Friction, Benefit-Restated, Urgency or Scarcity.

        EMOTIONAL SEQUENCE: Tension > Relatability > Insight > CTA. Open with tension or curiosity, build relatability, deliver the insight, close with action.

        FUNNEL RATIO: 40-50% TOF (awareness/entertainment), 30-40% MOF (education/trust), 10-20% BOF (conversion/sales).

        Write drafts DIRECTLY in your reply — you have the client profile, swipe data, and methodology in your context. Do not defer to external tools for writing.
        """
    }

    // MARK: - Lightweight Identity (WP7)

    /// Minimal identity prompt (~500 tokens) for simple intents: capture, correct, meta.
    /// Strips writing quality rules, brainstorming guide, and methodology to save ~1.5K tokens.
    private static let lightweightIdentityPrompt: String = """
        You are Cosmo, the user's personal creative strategist. You help them capture ideas, \
        swipe files, and manage their creative workflow.

        CRITICAL — URL HANDLING:
        - When the user sends ANY URL (Instagram, YouTube, X/Twitter, Threads, TikTok, or any website), \
        ALWAYS call capture_swipe with the URL. This is your #1 priority.
        - Do NOT say you "can't access" URLs. You don't need to access them — capture_swipe handles \
        downloading, metadata extraction, and transcript fetching internally.
        - Do NOT explain what the tool does. Just call it.
        - If the user also mentions a client name or idea alongside the URL, use capture_swipe_with_idea instead.

        CORE RULES:
        - Use tools to ground responses in real data — never make up information.
        - NEVER fabricate stats, numbers, or facts about a client. If you don't have the data, say so.
        - NEVER confuse clients — each name is a separate person. Verify with get_client_profile.
        - Reference items by their ACTUAL TITLES so the user can find them.
        - For destructive actions (delete, remove), explain what you're about to do.
        - When the user asks about items "for [client name]", use search_by_client first.
        - When the user gives feedback about behavior, use store_preference to remember it.
        - When the user gives an explicit writing rule, lesson, or creative principle to remember, use save_lessons.
        - Use store_preference only for runtime behavior and operational preferences, not writing craft lessons.
        - NEVER expose raw JSON, UUIDs, or system internals. Refer to items by title/name.
        - NEVER mention internal tool names. The user doesn't know or care about these.
        - Be direct and concise. Match the user's energy.
        """

    // MARK: - Identity

    private func identityPrompt(source: MessageSource, intent: AgentIntent? = nil) -> String {
        // Use lightweight identity for simple intents to reduce token usage
        let lightweightIntents: Set<AgentIntent> = [.capture, .correct, .meta]
        if let intent = intent, lightweightIntents.contains(intent) {
            var prompt = Self.lightweightIdentityPrompt
            // Still apply source-specific formatting
            switch source {
            case .telegram:
                prompt += "\n\nFORMATTING: Use plain text only. No Markdown. Keep responses short."
            case .whatsapp:
                prompt += "\n\nFORMATTING: Minimal formatting. Keep responses concise for mobile."
            case .inApp:
                break
            }
            return prompt
        }

        // Use custom system prompt from UserDefaults if set, otherwise use the default
        var prompt = UserDefaults.standard.string(forKey: "agent_custom_system_prompt")
            ?? Self.defaultIdentityPrompt

        switch source {
        case .telegram:
            prompt += """

            FORMATTING (Telegram) — STRICT:
            - Do NOT use Markdown formatting. No asterisks (*), no underscores (_), no backticks (`).
            - Use plain text only. For emphasis, use CAPS or dashes instead of bold/italic.
            - Use line breaks and short paragraphs for readability.

            TELEGRAM RESPONSE LENGTH — MANDATORY:
            - Your ENTIRE response must fit in 2 Telegram messages max (~6000 chars total). This is a hard limit.
            - You are texting a colleague, not writing a report. Be a human, not a dissertation.

            TELEGRAM RESPONSE STRUCTURE FOR DRAFTS/REWRITES:
            When delivering a draft, rewrite, or revised content, use EXACTLY this structure:
            1. A 2-3 sentence human summary of what you did and why ("Got it. Compared against X and Y. \
            Main issues were Z — here's the revised version.")
            2. The draft itself (slides, copy, outline — whatever was requested)
            3. That's it. STOP.
            - Do NOT give a slide-by-slide diagnosis or breakdown unless the user explicitly asks for one.
            - Do NOT explain every change you made. The draft speaks for itself.
            - Do NOT list what tools you used — the context card handles that separately.
            - Do NOT write section headers like "COMPARISON ANALYSIS" or "SLIDE-BY-SLIDE DIAGNOSIS".
            - If the user asks WHY you changed something, THEN explain — but only that specific thing, briefly.

            TELEGRAM RESPONSE STRUCTURE FOR NON-DRAFT MESSAGES:
            - Answer the question directly in 1-3 short paragraphs.
            - If you referenced data, weave it naturally into your response. Don't dump a formatted list.
            - Match the user's energy. Short question = short answer.
            """
        case .whatsapp:
            prompt += """

            FORMATTING (WhatsApp):
            - Use minimal formatting. WhatsApp supports *bold* and _italic_ but avoid backticks and complex formatting.
            - Keep responses concise for mobile reading.
            """
        case .inApp:
            break
        }

        return prompt
    }

    // MARK: - Standing Instructions Prompt

    private func standingInstructionsPrompt() async -> String {
        do {
            let instructions = try await StandingInstructionEngine.shared.listInstructions()
            guard !instructions.isEmpty else { return "" }

            var lines = ["[STANDING INSTRUCTIONS]"]
            lines.append("The user has \(instructions.count) recurring instruction(s):")
            for inst in instructions {
                let body = inst["body"] as? String ?? ""
                let schedule = inst["schedule"] as? String ?? "daily"
                let hour = inst["hour"] as? Int ?? 9
                let minute = inst["minute"] as? Int ?? 0
                let enabled = inst["enabled"] as? Bool ?? true
                let status = enabled ? "active" : "paused"
                lines.append("  - \(body.prefix(80)) (\(schedule) at \(String(format: "%02d:%02d", hour, minute)), \(status))")
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    // MARK: - Preferences Prompt

    private func preferencesPrompt(_ prefs: [AgentPreference]) -> String {
        var lines = ["[USER PREFERENCES]"]
        lines.append("The user has the following preferences (respect these in all interactions):")

        for pref in prefs.sorted(by: { $0.confidence > $1.confidence }) {
            let scopeLabel: String
            switch pref.scope {
            case .global: scopeLabel = ""
            case .client:
                scopeLabel = pref.scopeQualifier != nil ? " [client: \(pref.scopeQualifier!)]" : " [client-specific]"
            case .taskType:
                scopeLabel = pref.scopeQualifier != nil ? " [task: \(pref.scopeQualifier!)]" : " [task-specific]"
            }

            let confidence = pref.isExplicit ? "stated" : "inferred"
            lines.append("  - \(pref.key): \(pref.value)\(scopeLabel) (\(confidence))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Tool Guidelines

    private func toolGuidelines(_ tools: [LLMToolDefinition]) -> String {
        var lines = ["[TOOL GUIDELINES]"]
        lines.append("You have \(tools.count) tools available. Key rules:")
        lines.append("- Always use search tools before answering questions about the user's data")
        lines.append("- For destructive actions (delete_block), a confirmation will be requested automatically")
        lines.append("- When creating items, always return the UUID in your response for reference")
        lines.append("- If a tool returns an error, explain the issue to the user and suggest alternatives")
        lines.append("- Prefer specific tools over general queries (e.g. search_ideas over get_idea when exploring)")
        lines.append("")
        lines.append("Search retry strategy:")
        lines.append("- If search_swipes returns 0 results, try list_all_swipes to browse the full library")
        lines.append("- If searching for a specific type (hook type, framework), use filter_swipes_by_taxonomy")
        lines.append("- Always try at least 2 search strategies before telling the user you couldn't find something")
        lines.append("- For standing instructions queries, use list_standing_instructions")
        return lines.joined(separator: "\n")
    }

    // MARK: - Data Fetching Helpers

    private func fetchTodayBlocks() async -> [Atom] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        do {
            let blocks = try await atomRepo.fetchAll(type: .scheduleBlock)
            return blocks.filter { atom in
                let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
                if let startStr = meta?.startTime,
                   let startDate = ISO8601.date(from: startStr) {
                    return calendar.isDate(startDate, inSameDayAs: todayStart)
                }
                if let date = ISO8601.date(from: atom.createdAt) {
                    return calendar.isDate(date, inSameDayAs: todayStart)
                }
                return false
            }.sorted { a, b in
                let aMeta = a.metadataValue(as: ScheduleBlockMetadata.self)
                let bMeta = b.metadataValue(as: ScheduleBlockMetadata.self)
                return (aMeta?.startTime ?? "") < (bMeta?.startTime ?? "")
            }
        } catch {
            return []
        }
    }

    private func fetchActiveTasks() async -> [Atom] {
        do {
            let tasks = try await atomRepo.fetchAll(type: .task)
            return tasks.filter { atom in
                let meta = atom.metadataValue(as: TaskMetadata.self)
                return meta?.isCompleted != true
            }
        } catch {
            return []
        }
    }

    /// Fetch all in-progress content atoms and format as a summary block.
    /// Injected into brainstorm/capture/default contexts so the agent never creates duplicates.
    private func fetchActiveContentSummary() async -> String {
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            let activePhases: Set<String> = ["ideation", "brainstorm", "outline", "draft", "polish", "review"]
            let active = content.filter { atom in
                let meta = atom.metadataValue(as: ContentAtomMetadata.self)
                let phase = meta?.phase.rawValue ?? "ideation"
                return activePhases.contains(phase)
            }
            guard !active.isEmpty else { return "" }

            var lines: [String] = ["EXISTING IN-PROGRESS CONTENT (do NOT create duplicates — use these UUIDs):"]
            for atom in active.prefix(10) {
                let meta = atom.metadataValue(as: ContentAtomMetadata.self)
                let title = atom.title ?? "Untitled"
                let phase = meta?.phase.displayName ?? "Ideation"
                let clientUUID = meta?.clientProfileUUID
                let clientNote = clientUUID != nil ? " (has client)" : ""
                lines.append("  - \"\(title)\" [\(phase)] UUID: \(atom.uuid)\(clientNote)")
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    private func fetchRecentIdeas() async -> [Atom] {
        do {
            let ideas = try await atomRepo.fetchAll(type: .idea)
            return Array(ideas.prefix(5))
        } catch {
            return []
        }
    }

    private func fetchPipelinePhaseCounts() async -> [String: Int] {
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            var counts: [String: Int] = [:]
            for atom in content {
                let meta = atom.metadataValue(as: ContentAtomMetadata.self)
                let phase = meta?.phase.displayName ?? "Ideation"
                counts[phase, default: 0] += 1
            }
            return counts
        } catch {
            return [:]
        }
    }

    private func fetchClientProfileNames() async -> [String] {
        do {
            let clients = try await atomRepo.clientProfiles()
            return clients.compactMap { $0.title }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    /// Format a single client's full profile (niche, voice, handles) for scoped injection.
    private func formatSingleClientProfile(_ client: Atom) -> [String] {
        var parts: [String] = []
        let name = client.title ?? "Untitled"
        parts.append("  \(name):")
        if let meta = client.metadata,
           let data = meta.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let niche = dict["niche"] as? String, !niche.isEmpty {
                parts.append("    Niche: \(niche)")
            }
            if let brandVoice = dict["brandVoice"] as? String, !brandVoice.isEmpty {
                parts.append("    Voice: \(String(brandVoice.prefix(200)))")
            }
            if let handles = dict["handles"] as? [String: String], !handles.isEmpty {
                let handleStr = handles.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                parts.append("    Handles: \(handleStr)")
            }
        }
        return parts
    }

    /// Fetch full client profile details including voice, niche, and brand context.
    private func fetchClientProfileDetails() async -> [String] {
        do {
            let clients = try await atomRepo.clientProfiles()
            guard !clients.isEmpty else { return [] }

            var parts: [String] = ["Client profiles (\(clients.count)):"]
            for client in clients.prefix(5) {
                let name = client.title ?? "Untitled"
                parts.append("  \(name):")
                if let meta = client.metadata,
                   let data = meta.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let niche = dict["niche"] as? String, !niche.isEmpty {
                        parts.append("    Niche: \(niche)")
                    }
                    if let brandVoice = dict["brandVoice"] as? String, !brandVoice.isEmpty {
                        parts.append("    Voice: \(String(brandVoice.prefix(200)))")
                    }
                    if let handles = dict["handles"] as? [String: String], !handles.isEmpty {
                        let handleStr = handles.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                        parts.append("    Handles: \(handleStr)")
                    }
                }
            }
            return parts
        } catch {
            return []
        }
    }

    // MARK: - Formatting Helpers

    private func formatTimeRange(start: String?, end: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let startStr: String
        if let s = start, let d = ISO8601.date(from: s) {
            startStr = formatter.string(from: d)
        } else {
            startStr = "??"
        }

        let endStr: String
        if let e = end, let d = ISO8601.date(from: e) {
            endStr = formatter.string(from: d)
        } else {
            endStr = "??"
        }

        return "[\(startStr)-\(endStr)]"
    }
}
