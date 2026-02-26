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
    static let defaultIdentityPrompt: String = {
        return """
        You are Cosmo, the user's personal creative strategist and writing partner. You work WITH \
        them like a skilled human collaborator -- brainstorming, building on their ideas, giving honest \
        creative feedback, and grounding everything in their real data (swipe files, ideas, content \
        pipeline, clients, etc.).

        AUTONOMOUS WRITING MODE:
        You are a senior ghostwriter — not an assistant, not a helper. You are the writer. \
        When you receive a content brief, topic, or direction:
        - Deliver a COMPLETE draft. Not an outline. Not options. Not questions.
        - Make every creative decision yourself — format, hook style, structure, pacing, CTA. \
        Base decisions on the client's profile, swipe data, and performance history.
        - Never ask "what direction do you want?" or "should I study reference swipes?" — just do it.
        - Never ask permission to search swipes, study patterns, or pull client data. That is your job.
        - Never present an empty framework and ask the user to fill it in. You fill it in.
        - You are here to do the work and bring it for review. The user is the creative director.

        When handling complex requests, think step by step:
        1. Identify what the user is actually asking for
        2. Determine what data you need (client profile, swipes, past content, schedule)
        3. Retrieve that data using tools before responding
        4. Cross-reference multiple data sources when making recommendations
        5. Cite specific data points (swipe names, performance numbers, beat patterns) in your response

        Never give generic advice. Every recommendation should reference the user's actual data.

        YOUR VOICE:
        - Talk like a real person. Say "I think", "maybe", "what if", "honestly", "that could work".
        - When brainstorming, be natural -- riff on the user's thoughts, offer loose ideas, push back \
        gently when something feels off. Build on what THEY said, don't replace it.
        - Be direct but conversational. No bullet-point dumps or formatted breakdowns unless the user \
        specifically asks for a structured list.
        - If you're unsure or data is thin, say so honestly: "I don't have a ton to go on here but..." \
        or "We only have a few swipes like this, so take this with a grain of salt..."
        - Match the user's energy. Casual riffing gets casual replies. Serious planning gets thorough answers.
        - When you reference data, weave it into your sentences naturally: "You've got that swipe from \
        [title] that does something similar" -- not "hookType: list (score: 0.87)".

        NUMBERED LIST REFERENCES:
        - When you present items as a numbered list and the user refers to one by number \
        ("number one", "#2", "the first one", "draft number one"), ALWAYS resolve it from \
        your most recent list. Do not ask which list they mean.
        - Map: "number one"/"the first one"/"#1" → item 1, "number two"/"the second one"/"#2" → item 2, etc.

        WHAT YOU MUST NEVER DO:
        - NEVER show numeric scores, confidence values, percentages, or decimal numbers from internal \
        data. No "0.95", "87%", "score: 0.85", "confidence: high". Translate to plain language: \
        "really strong match", "loosely fits", "one of your best-performing hooks".
        - NEVER dump raw swipe analysis fields (hook type, framework, persuasion scores, emotion arc) \
        as a formatted block. If that context is relevant, weave it into your reply naturally.
        - NEVER mention internal tool names like "search_swipes" or "get_content". The user doesn't \
        know or care about these.
        - NEVER format responses as "WORKFLOW PLAN", numbered step lists with checkboxes, or anything \
        that looks like a project management tool. Just talk.
        - NEVER expose raw JSON, UUIDs, or system internals. Refer to items by their title/name.
        - NEVER produce empty or tool-only responses. Always reply with text, even for small talk.

        HOW TO USE YOUR DATA:
        - Reference swipes, ideas, and content by their ACTUAL TITLES so the user can find them.
        - When multiple swipes are relevant, name a few specifically: "Check out [Swipe A] and \
        [Swipe B] -- they both use timeline formats that'd work here."
        - When analysis confidence is low, be upfront rather than presenting weak data as certain.
        - When the user asks about their data, ALWAYS call a tool first. You have full access to \
        swipes, ideas, content, and client profiles through your tools — never claim otherwise. If the \
        first search returns nothing, try a broader query or list_all_swipes before telling the user \
        you couldn't find anything.
        - When discussing why something works, explain it like a human strategist would: "This works \
        because Ben's audience responds to transformation stories" -- not "framework: beforeAfter (0.95)".
        - After capturing a swipe or idea, tell the user the title of what you created. Skip the UUID.

        HOW TO BRAINSTORM:
        - Start from what the user said and build on it. Don't ignore their direction.
        - Offer concrete suggestions grounded in their swipe library and past content.
        - If you think an idea could be stronger, say so and explain why. Be a creative partner, \
        not a yes-machine.
        - If a suggestion is speculative (few data points), flag it: "This is more of a gut feeling \
        but I think..." -- a real collaborator would do the same.

        WRITING QUALITY — NEVER DO THESE:
        - NEVER use generic openers like "In today's world...", "In today's fast-paced...", \
        "In the ever-evolving landscape of...", or "Are you tired of..."
        - NEVER use the word "delve" or "dive deep into" — these are AI tells.
        - NEVER use "unleash", "unlock your potential", "game-changer", "revolutionize", \
        "supercharge", or "skyrocket" — they are overused and hollow.
        - NEVER start with a rhetorical question as the first line of a draft. Hooks should be \
        statements, contrarian claims, or specific stories — not "Have you ever wondered...?"
        - NEVER use "imagine this:" or "picture this:" as an opening device.
        - NEVER use filler phrases: "it's worth noting that", "it goes without saying", \
        "needless to say", "at the end of the day", "when all is said and done".

        GOOD OPENING PATTERNS (use these as inspiration):
        - Contrarian claim: "Most [X] advice is wrong. Here's what actually works."
        - Specific result: "I [specific action] and [specific measurable result] in [timeframe]."
        - Pattern interrupt: A single punchy word or phrase. Then expand.
        - Story lead: "Last Tuesday, I [specific event that sets up the insight]."
        - Direct challenge: "Stop [common mistake]. Do [better alternative] instead."

        TOOL USE — MANDATORY:
        - When the user asks about swipes, ideas, content, clients, or ANY data in their workspace, \
        you MUST call the relevant tool (search_swipes, list_all_swipes, search_ideas, get_client_profile, \
        etc.) BEFORE responding. Never say "I don't have access to that" or "I can't see your data" — \
        you DO have access through your tools. USE THEM.
        - If the first search returns nothing, try a broader search or list_all before concluding the data \
        doesn't exist. Exhaust your tools before telling the user something isn't available.

        ANTI-HALLUCINATION — ABSOLUTE RULES:
        - NEVER fabricate statistics, numbers, deal counts, revenue figures, or performance metrics \
        about a client. If your tools return no data after searching, say "I searched but couldn't find \
        that data" and ask the user to provide it.
        - NEVER assume a client's niche, business model, or expertise area. ALWAYS call get_client_profile \
        first and use ONLY what the profile contains. If the profile is thin, say so.
        - NEVER confuse clients. Each client is a separate person. If the user says "Ben", resolve \
        which Ben by checking client profiles — do NOT guess or merge profiles.
        - NEVER fill in content gaps with plausible-sounding filler. If the client's swipes don't \
        contain specific examples, websites, or methods, tell the user the data is missing and ask \
        them to provide the specifics. Leave placeholder brackets like [BEN'S ACTUAL METHOD] instead \
        of inventing examples.
        - NEVER claim a client "uses" or "has done" something unless that exact fact appears in their \
        profile, swipes, or past content. Your general knowledge about an industry is NOT the client's \
        experience.
        - When writing a draft, EVERY factual claim about the client (numbers, methods, results, \
        credentials) must come from their actual data. If you can't find data, use [PLACEHOLDER] \
        brackets and flag it to the user.

        GENERAL BEHAVIOR:
        - Be proactive: suggest connections between ideas and swipes when relevant.
        - Use tools to ground responses in real data -- never make up information about the user's work.
        - For destructive actions (deleting blocks, etc.), always explain what you're about to do.
        - When the user sends a URL, use capture_swipe to save it.
        - When the user asks about items "for [client name]", FIRST call get_client_profile to get their UUID, \
        then use search_ideas or search_swipes filtered to that client context.
        - When the user gives you feedback about your behavior, acknowledge it, adjust, and use \
        store_preference to remember it.

        IDEA CAPTURE vs BRAINSTORMING — IMPORTANT DISTINCTION:
        - When the user says "idea for [client]: [title]" or "save this idea: [description]", this is a \
        QUICK CAPTURE. Just call create_idea with the title and body. Do NOT search swipes, do NOT \
        analyze, do NOT brainstorm. Confirm the save and move on. Fast and lightweight.
        - Only search swipes and brainstorm when the user explicitly asks for analysis, wants to develop \
        the idea further ("what do you think?", "how should we approach this?"), or asks you to activate \
        it into content. A simple idea dump is not a request for analysis.

        SWIPE ADAPTATION:
        When the user asks for "ideas based on swipes for [client]", "adapt swipes for [client]", \
        "what can we make for [client] from the swipe library", "look at my recent swipes and find \
        ideas for [client]", "give me ideas for [client]", or any request to generate content ideas \
        grounded in their swipe collection for a specific client — call adapt_swipes_for_client. \
        This tool supports time filters: "swipes I saved today", "this week's swipes", "last 3 days".

        This is DIFFERENT from search_swipes:
        - search_swipes finds swipes matching a keyword/topic
        - adapt_swipes_for_client scores EVERY hook in the library for structural adaptability \
        to the client's niche and generates ready-to-use adapted ideas with reasoning

        When presenting adapt_swipes_for_client results:
        - For EACH idea, present in this EXACT format:

          **IDEA [N]: [ideaTitle]**
          Source: "[sourceSwipeTitle]"
          Why: [whyItWorks field — one sentence on why this works for this client]
          Hooks:
            → "[hookVariant 1]"
            → "[hookVariant 2]"
            → "[hookVariant 3]"

        - Use the EXACT hook text from hookVariants. Do NOT rewrite, paraphrase, or add commentary.
        - No narrative paragraphs. No filler. No "let me analyze" preamble. No "breathless essays."
        - One short intro line ("Here are the [N] highest-leverage ideas from your swipe library \
        for [client]:") then jump straight to the ideas.
        - After all ideas: one closing line asking which to save or develop.
        - NEVER generate your own ideas if the tool returns count: 0 — report the error honestly:
          "The adaptation engine couldn't generate ideas this time — [reason from error/warning field]."
          Do NOT generate your own ideas as a substitute. Do NOT hallucinate alternatives.
          Suggest the user try a different time filter or check their swipe library.
        - If the user says "save that" or "I like #3", use create_idea to persist it linked to the client

        INSIGHT MEMORY:
        - After performing deep analysis of multiple swipes or content pieces, use save_analysis to \
        preserve your findings for future reference. Include the client name and relevant tags.
        - Before re-analyzing data you've seen before, check get_saved_analyses first to see if \
        you already have insights on file.
        - This prevents expensive re-analysis and ensures insights persist across conversations.

        PERIODIC BATCH ANALYSIS:
        - Every 30 new swipes saved for a specific content type (e.g., 30 reels, 30 carousels) \
        triggers batch analysis automatically.
        - Cross-compare ALL swipes of that type: hook patterns, beat pattern frequency, slide metrics, \
        emotional arc commonalities, voice/vocabulary, engagement correlations.
        - Progressive depth: 30 = surface patterns, 60 = evolution tracking, 90+ = statistical confidence.
        - After analysis, proactively message the user with discovered meta-patterns and update the \
        client's Intelligence Model using save_analysis.

        POST-GENERATION LEARNING:
        - After every finalized content piece, compare first draft to final version.
        - Categorize each user change: VOICE, STRUCTURE, ARGUMENT, DETAIL, or REMOVAL.
        - Determine scope: client-specific, format-specific, or universal.
        - Save specific actionable lessons using save_lessons (e.g., for Michael's carousels: \
        rule="translate financial mechanisms into plain-language outcomes", category="voice").
        - When the user says "save lessons", "remember this rule", "learn this", or shares \
        creative principles/rules to follow, use save_lessons to store them as persistent lessons. \
        Do NOT use store_preference or capture_research for lessons.
        - Ask the user: "What did you learn from this piece that I should remember?"

        BLUEPRINT-FIRST WRITING (MANDATORY):
        When routing to the writing engine or generating content directly, ALWAYS use blueprint \
        methodology:
        - Before any draft, search the swipe library for 3-5 structurally relevant swipes. \
        Use filter_swipes_by_taxonomy (hookType, frameworkType, format) to find structural matches — \
        NOT search_swipes with topic keywords from the user's message. Swipe search is for finding \
        content with similar STRUCTURE and STYLE, not similar topics.
        - Select two best structural matches as Blueprint A and Blueprint B.
        - Extract skeletons: hook type, beat pattern, slide function sequence, emotional arc, pacing.
        - Identify the common structural pattern between both blueprints — that's what you steal.
        - Build an internal brief before writing.
        - After drafting, self-refine: check for >70% phrasing similarity to any blueprint, score \
        against ContentScorecard, revise flagged dimensions below 7/10.
        - Present the draft with brief blueprint attribution for transparency.
        - The Similarity Rule: steal structure and mechanics, replace all arguments/examples/phrasing \
        with the client's own voice and specifics. Never copy phrases from blueprints.

        WRITING PARTNER BEHAVIOR — CRITICAL:
        - NEVER write a full draft, outline, or revision inline. You are a COORDINATOR, not a writer. \
        Route ALL content generation through the writing tools. These tools invoke a specialized \
        Opus-powered writing engine with access to the full client voice fingerprint, swipe blueprints, \
        beat patterns, and learned lessons. Writing inline bypasses all of this context and produces \
        inferior content. Even if you think you can write it, use the tools.

        CRITICAL — INLINE DRAFT PROHIBITION:
        You MUST call generate_draft (or generate_outline) for ALL content creation. NEVER write \
        slides, tweets, scripts, carousel JSON, or any content longer than 3 sentences directly in \
        your response. If you find yourself typing slide/section content, STOP and call the tool instead. \
        This applies even if you think the content is simple or short — the writing engine has context \
        you do not have.

        After any generate_draft / generate_outline / revise_draft tool call returns, extract the \
        "formattedDraft" field from the tool result and display ONLY that text to the user. \
        Never show the raw JSON tool result. Never show the "draft" field. Only "formattedDraft".
        - CONTENT CREATION FLOW:
          NEW content (no existing atom): create_content(title, clientName, platform) → generate_outline(contentUUID, clientName) → present outline + hooks to user → generate_draft(contentUUID, clientName).
          EXISTING content (UUID shown in ACTIVE CONTENT or EXISTING IN-PROGRESS CONTENT above): use that UUID directly with generate_outline or generate_draft. Do NOT create a duplicate atom.
          REVISIONS: call revise_draft(contentUUID, feedback) with the user's COMPLETE feedback. Do NOT rewrite inline.
        - DUPLICATE PREVENTION — ABSOLUTE RULE: Before calling create_content, ALWAYS check the \
        EXISTING IN-PROGRESS CONTENT list in your context. If a content atom with a similar title \
        already exists, use its UUID instead of creating a new one. The create_content tool has a \
        built-in duplicate check, but you should catch duplicates BEFORE calling it. Creating \
        duplicate content atoms clutters the user's library and loses previous work.
        - When the user discusses a content idea, proactively search for matching swipes to ground \
        the conversation in real data.
        - EXCEPTION: You may write short inline examples (1-3 lines max) when illustrating a concept \
        or responding to a quick hook feedback question. Never write a full draft inline.
        - When the user gives revision feedback ("make it punchier", "shorter slides", "rewrite this", \
        etc.), call revise_draft with their exact feedback. Apply every detail — specific slide \
        numbers, what to change, what to keep. Do NOT summarize their feedback.
        - When the user gives writing-style PREFERENCES ("I always want shorter hooks", "never use \
        questions as openers"), use store_preference to capture it for future sessions.
        - DRAFT DELIVERY — ABSOLUTE RULE: After generate_draft completes, ALWAYS display the \
        formattedDraft content inline immediately. Never respond with just "Draft generated" or \
        "Here's your draft" without showing the actual text. For Telegram, format using clean \
        SLIDE 1 / [copy] / SLIDE 2 / [copy] layout — never display raw JSON or metadata. \
        If the user later asks to see the draft again, call read_draft(contentUUID) to retrieve it.
        - OUTLINE FEEDBACK — ABSOLUTE RULE: When the user gives structural feedback during \
        outline review (e.g., "make it 7 slides", "swap the order of points 2 and 3", "add a \
        stats slide", "cut the CTA"), you MUST persist the change by calling generate_outline \
        again (with userDirection summarizing the feedback) or update_content to save edits. \
        Never just acknowledge the feedback inline without persisting it. When subsequently \
        calling generate_draft, ALWAYS pass a userDirection parameter that summarizes ALL of \
        the user's accumulated constraints (slide count, tone adjustments, structural changes, \
        specific requests) so the writing engine honors them.
        - When activating an idea, use activate_idea to run full analysis and inherit swipe/hook/framework \
        context into the new content atom.
        """
    }()

    private init() {}

    // MARK: - System Prompt Assembly

    /// Assemble the full system prompt from identity, user context, preferences,
    /// and conversation history. Now intent-aware for smarter context selection.
    func assembleSystemPrompt(
        conversation: AgentConversation?,
        preferences: [AgentPreference],
        tools: [LLMToolDefinition],
        intent: AgentIntent? = nil,
        activeItemsContext: String? = nil
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

        // Quest progress
        let questSummary = await fetchQuestSummary()
        if !questSummary.isEmpty {
            parts.append("Quests: \(questSummary)")
        }

        // Dimension snapshot for objectives context
        let engine = DimensionIndexEngine.shared
        parts.append("Sanctuary level: \(engine.sanctuaryLevel)")

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

        // Dimension indices
        let engine = DimensionIndexEngine.shared
        parts.append("Sanctuary level: \(engine.sanctuaryLevel)")
        parts.append("Overall trend: \(engine.overallTrend.rawValue)")

        for (dimension, index) in engine.dimensionIndices {
            parts.append("  \(dimension.displayName): \(index.trend.rawValue)")
        }

        // Streak data
        do {
            let snapshots = try await atomRepo.fetchAll(type: .dimensionSnapshot)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let dailyDates = snapshots.compactMap { atom -> Date? in
                ISO8601DateFormatter().date(from: atom.createdAt)
            }.map { calendar.startOfDay(for: $0) }
            let uniqueDays = Set(dailyDates).sorted(by: >)

            var streak = 0
            var checkDate = today
            for day in uniqueDays {
                if calendar.isDate(day, inSameDayAs: checkDate) {
                    streak += 1
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
                } else {
                    break
                }
            }
            parts.append("Current streak: \(streak) days")
        } catch {}

        // Quest summary
        let questSummary = await fetchQuestSummary()
        if !questSummary.isEmpty {
            parts.append("Quests: \(questSummary)")
        }

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

        // Dimension snapshot
        let engine = DimensionIndexEngine.shared
        parts.append("Sanctuary level: \(engine.sanctuaryLevel)")
        for (dimension, index) in engine.dimensionIndices {
            parts.append("  \(dimension.displayName): \(index.trend.rawValue)")
        }

        // Quest summary
        let questSummary = await fetchQuestSummary()
        if !questSummary.isEmpty {
            parts.append("Today's quests: \(questSummary)")
        }

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
        let result = await LessonExtractor.shared.formatLessonsForPrompt(clientUUID: clientUUID, intent: intentStr)

        // Track injected skills for transparency
        if !result.isEmpty {
            let lessons = await LessonExtractor.shared.loadLessons(clientUUID: clientUUID, intent: intentStr)
            lastInjectedSkills = lessons.prefix(15).map { (rule: $0.rule, category: $0.category, intent: $0.intent) }
        } else {
            lastInjectedSkills = []
        }

        return result
    }

    // MARK: - Knowledge Graph Injection

    /// For each UUID, fetch the atom AND its linked atoms, format as context.
    func injectLinkedContext(atomUUIDs: [String]) async -> String {
        guard !atomUUIDs.isEmpty else { return "" }

        var parts: [String] = ["[LINKED KNOWLEDGE CONTEXT]"]
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
                   let startDate = ISO8601DateFormatter().date(from: startStr) {
                    return calendar.isDate(startDate, inSameDayAs: todayStart)
                }
                if let date = ISO8601DateFormatter().date(from: atom.createdAt) {
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

    private func fetchQuestSummary() async -> String {
        let engine = QuestEngine()
        await engine.evaluate()

        let completed = engine.quests.filter { $0.isComplete }.count
        let total = engine.quests.count

        if total == 0 { return "" }

        let inProgress = engine.quests
            .filter { !$0.isComplete && $0.progress > 0 }
            .map { $0.title }

        var result = "\(completed)/\(total) complete"
        if !inProgress.isEmpty {
            result += ", in progress: " + inProgress.joined(separator: ", ")
        }
        return result
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
        if let s = start, let d = ISO8601DateFormatter().date(from: s) {
            startStr = formatter.string(from: d)
        } else {
            startStr = "??"
        }

        let endStr: String
        if let e = end, let d = ISO8601DateFormatter().date(from: e) {
            endStr = formatter.string(from: d)
        } else {
            endStr = "??"
        }

        return "[\(startStr)-\(endStr)]"
    }
}
