import Foundation

struct CosmoInlineAssistantPreparedAgentRequest {
    var prompt: String
    var conversationID: String
    var tierOverride: AgentModelTier?
    /// Pinned intent — keeps the tool set and cached prompt prefix byte-stable
    /// instead of fragmenting on keyword-classification noise.
    var intentOverride: AgentIntent?
    /// Byte-stable instruction layer (route rules + personality). Lives inside the
    /// prompt-cache prefix; must not contain anything request-specific.
    var systemPromptOverride: String?
    /// Per-request context (surface snapshot, resolved skill facts, working frame).
    /// Rendered after the cache breakpoint so it never invalidates the prefix.
    var volatileContextOverride: String?
    var responseMode: AgentResponseMode
    var profileToolBundles: [AgentToolBundle]
    var forcedToolBundles: Set<AgentToolBundle>
    var contextAtomUUIDs: [String]
    var contextSourceIDs: [String]
    var activeClientUUID: String?
    /// Multi-phase skill pipeline — when non-empty the bridge runs one scoped
    /// agent turn per step instead of a single turn.
    var pipelineSteps: [CosmoInlineSkillStep] = []
}

struct CosmoInlineAssistantAgentBridge {
    var send: @MainActor (
        _ prompt: String,
        _ route: CosmoInlineAssistantRoute,
        _ store: CosmoInlineAssistantStore
    ) async throws -> Void

    static let live = CosmoInlineAssistantAgentBridge { prompt, route, store in
        // Hydrating variant of activeEditableSnapshot(): falls back to the
        // persisted atom when the registered surface is missing or serves an
        // empty text for a document that has substance on disk — the model
        // must see what the user sees, not what a stale provider remembers.
        let snapshot = await store.submissionEditableSnapshot()

        // Craft skills (/review, /riff) bypass the agent tool loop entirely:
        // comparables and stats are computed in Swift, then ONE structured
        // engine call delivers the result — evidence-grounded and ~10x cheaper
        // than running these skills through the 95-tool agent loop.
        if route == .answer,
           let craftSkillID = CosmoCraftSkillRunner.resolveCraftSkillID(
               selectedSkillID: store.activeSubmissionSkillID,
               prompt: prompt,
               surfaceKind: snapshot?.kind,
               residentSkillID: snapshot?.residentSkillID
           ) {
            try await CosmoCraftSkillRunner.shared.run(
                prompt: prompt,
                skillID: craftSkillID,
                store: store,
                snapshot: snapshot
            )
            return
        }

        let perfStart = Date()
        let executor = AgentToolExecutor.shared
        executor.resetSessionSourceRefs()
        executor.onWorkspaceEditProposal = { proposal in
            store.receive(proposal: proposal)
        }
        executor.onAssistantPaneAnswer = { title, answer in
            store.receivePaneAnswer(title: title, answer: answer, route: route)
        }
        executor.onInquiryQuestionProposal = { proposal in
            store.receive(inquiryProposal: proposal)
        }
        // Canvas plans (thinkspace copilot) review in the pane now, not the
        // old floating window.
        executor.onCanvasPlan = { plan in
            Task { @MainActor in
                store.receive(canvasPlan: plan)
            }
        }
        // The surface bound at submit is the truth for edit targeting — the
        // executor stamps it over model-authored IDs so proposals always bind
        // to the editor the user was actually in. The text rides along so the
        // executor can validate anchors and expand series instructions
        // (renumberSequence, scoped formatMarks) against real document state.
        executor.workspaceEditBoundSurface = snapshot.map { ($0.surfaceID, $0.targetID) }
        executor.workspaceEditBoundSurfaceText = snapshot?.text
        // Concept turns finish with a reaction + one deepening question in the
        // SAME pass — the staging tool result itself demands it (see
        // proposeWorkspaceEdit). The post-run nudge below stays as the net.
        executor.conceptTurnContractActive =
            store.activeSubmissionSkillID == CosmoInlineAssistantSkillID.concept.rawValue

        let paneAnswerCount = store.paneMessages.filter {
            $0.role == .assistant && $0.proposalID == nil
        }.count
        let proposalCount = store.proposals.count
        defer {
            executor.onWorkspaceEditProposal = nil
            executor.onAssistantPaneAnswer = nil
            executor.onInquiryQuestionProposal = nil
            executor.onCanvasPlan = nil
            executor.workspaceEditBoundSurface = nil
            executor.workspaceEditBoundSurfaceText = nil
            executor.conceptTurnContractActive = false
            executor.contextAtomUUIDs = []
            executor.contextSourceIDs = []
            executor.contextConversationID = nil
            executor.activeClientUUID = nil
            store.sourceRefsProvider = nil
        }

        // The session was already bound by submit(), atomically with the user's
        // message — retargeting it here (after the message was appended) is what
        // used to make sent messages vanish from the pane. The snapshot is for
        // edit targeting and context only.
        // Chips show what was actually read: tool-read refs plus the prefetched
        // ambient pack (which the model is told to use without re-searching).
        let surfaceIDForRefs = snapshot?.surfaceID
        store.sourceRefsProvider = {
            var refs = AgentToolExecutor.shared.sessionSourceRefs
            for ambient in CosmoInlineAmbientContextPack.shared.sourceRefs(forSurfaceID: surfaceIDForRefs)
            where !refs.contains(where: { $0.uuid == ambient.uuid }) {
                refs.append(ambient)
            }
            guard !ContextSourcePolicy.allowsGeneratedCodexCorpus(query: prompt) else { return refs }
            return refs.filter { !ContextSourcePolicy.isGeneratedCodexCorpusTitle($0.title) }
        }
        let contextStatus = snapshot.map { "Reading \($0.title)" } ?? "Reading current context"
        store.receiveToolActivity(.started(
            name: "inline_context",
            displayLabel: contextStatus,
            args: [:]
        ))

        var preparedRequest = await CosmoWindowViewModel.shared.prepareInlineAssistantAgentRequest(
            prompt: prompt,
            route: route,
            snapshot: snapshot,
            inlineContextAtoms: store.selectedContextAtoms,
            selectedSkillID: store.activeSubmissionSkillID,
            sessionLedgerBlock: store.sessionLedgerPromptBlock
        )
        // The agent's memory thread follows the conversation the user can SEE
        // (the store's active session), not whichever surface happens to be
        // registered — otherwise follow-ups lose the chat history behind them.
        preparedRequest.conversationID = store.activeConversationID
        let perfPrepareMs = Int(Date().timeIntervalSince(perfStart) * 1000)
        print("[AGENT-PERF] inline prepare (retrieval+memory+context-pack)=\(perfPrepareMs)ms forcedBundles=\(preparedRequest.forcedToolBundles.map(\.rawValue).sorted())")

        // Show live progress during the first model call (which runs before any tool fires).
        store.receiveToolActivity(.started(name: "inline_thinking", displayLabel: "Cosmo is thinking…", args: [:]))

        executor.contextAtomUUIDs = preparedRequest.contextAtomUUIDs
        executor.contextSourceIDs = preparedRequest.contextSourceIDs
        executor.contextConversationID = preparedRequest.conversationID
        executor.activeClientUUID = preparedRequest.activeClientUUID

        var response: String
        if !preparedRequest.pipelineSteps.isEmpty {
            response = await Self.runPipeline(preparedRequest, route: route, store: store)
        } else {
            // Chatty answer routes (concept development, brainstorms) run the
            // daily driver at medium effort (GPT-5.6's own default; on Sonnet 5
            // it was roughly Sonnet 4.6 at high) because reasoning bills as
            // output. Action/edit routes and the escalation retry below never
            // set the scope: exact-match splicing keeps the provider default.
            let scopedEffort: String? = route == .action ? nil : "medium"
            (response, _) = await LLMEffortScope.$effort.withValue(scopedEffort) {
                await CosmoAgentService.shared.processMessage(
                    preparedRequest.prompt,
                    conversationId: preparedRequest.conversationID,
                    source: .inApp,
                    tierOverride: preparedRequest.tierOverride,
                    intentOverride: preparedRequest.intentOverride,
                    systemPromptOverride: preparedRequest.systemPromptOverride,
                    volatileContextOverride: preparedRequest.volatileContextOverride,
                    responseMode: preparedRequest.responseMode,
                    profileToolBundles: preparedRequest.profileToolBundles,
                    forcedToolBundles: preparedRequest.forcedToolBundles,
                    // Action edits inject their own compact context — skip the heavy Command-A layers.
                    lightweightContext: route == .action,
                    onToolActivity: { event in
                        Task { @MainActor in
                            store.receiveToolActivity(event)
                        }
                    },
                    onPaneAnswerDelta: { delta in
                        Task { @MainActor in
                            store.receivePaneAnswerDelta(delta)
                        }
                    }
                )
            }
        }

        // Escalation ladder: an edit run whose proposals kept failing
        // validation (locator misses, structure corruption, scope/move/
        // duplication rejections) retries ONCE — the Haiku fast lane steps up
        // to the daily driver; stronger tiers get one clean re-run with the
        // rejection feedback already in the conversation. Cheap requests stay
        // cheap; hard ones self-heal instead of dead-ending.
        if preparedRequest.pipelineSteps.isEmpty,
           route == .action,
           store.proposals.count == proposalCount,
           executor.workspaceEditValidationRejections >= 2 {
            let escalationTier: AgentModelTier = preparedRequest.tierOverride == .sensor
                ? CosmoInlineAssistantRequestShape.defaultModelTier
                : (preparedRequest.tierOverride ?? CosmoInlineAssistantRequestShape.defaultModelTier)
            print("[AGENT-PERF] inline validation escalation → \(escalationTier) after \(executor.workspaceEditValidationRejections) validation rejections")
            store.receiveToolActivity(.started(
                name: "inline_thinking",
                displayLabel: "Taking another pass at the edit…",
                args: [:]
            ))
            executor.resetSessionSourceRefs()
            let retry = await CosmoAgentService.shared.processMessage(
                preparedRequest.prompt,
                conversationId: preparedRequest.conversationID,
                source: .inApp,
                tierOverride: escalationTier,
                intentOverride: preparedRequest.intentOverride,
                systemPromptOverride: preparedRequest.systemPromptOverride,
                volatileContextOverride: preparedRequest.volatileContextOverride,
                responseMode: preparedRequest.responseMode,
                profileToolBundles: preparedRequest.profileToolBundles,
                forcedToolBundles: preparedRequest.forcedToolBundles,
                lightweightContext: true,
                onToolActivity: { event in
                    Task { @MainActor in
                        store.receiveToolActivity(event)
                    }
                },
                onPaneAnswerDelta: { delta in
                    Task { @MainActor in
                        store.receivePaneAnswerDelta(delta)
                    }
                }
            )
            response = retry.0
        }
        // Contract backstop: an action-routed run's deliverable is the STAGED
        // EDIT. If the model answered but staged nothing (it asked permission
        // instead — "want me to fill it in?"), give it ONE continuation to
        // stage its recommendation. The review diff is the user's confirmation
        // step; a chat question before staging is double-asking. Runs that
        // genuinely contained no edit instruction answer normally and pass
        // straight through.
        if route == .action,
           preparedRequest.pipelineSteps.isEmpty,
           !Task.isCancelled,
           store.proposals.count == proposalCount,
           store.paneMessages.filter({ $0.role == .assistant && $0.proposalID == nil }).count > paneAnswerCount {
            print("[AGENT-PERF] inline stage-contract nudge: action run answered without staging")
            store.receiveToolActivity(.started(
                name: "inline_thinking",
                displayLabel: "Staging the edit…",
                args: [:]
            ))
            let nudge = await CosmoAgentService.shared.processMessage(
                "Continue: the request included an edit instruction, and you answered without staging anything. Stage your recommended edit NOW with one propose_workspace_edit call (in-place operations, best-supported values; note alternatives briefly in the summary). Only if the original request truly asked for no document change, reply with a one-line answer_in_assistant_pane instead.",
                conversationId: preparedRequest.conversationID,
                source: .inApp,
                tierOverride: preparedRequest.tierOverride,
                intentOverride: preparedRequest.intentOverride,
                systemPromptOverride: preparedRequest.systemPromptOverride,
                volatileContextOverride: preparedRequest.volatileContextOverride,
                responseMode: preparedRequest.responseMode,
                profileToolBundles: preparedRequest.profileToolBundles,
                forcedToolBundles: preparedRequest.forcedToolBundles,
                lightweightContext: true,
                onToolActivity: { event in
                    Task { @MainActor in
                        store.receiveToolActivity(event)
                    }
                },
                onPaneAnswerDelta: { delta in
                    Task { @MainActor in
                        store.receivePaneAnswerDelta(delta)
                    }
                }
            )
            if !nudge.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                response = nudge.0
            }
        }

        // Go-deeper backstop (concept collaborator): the whole point of the
        // concept partner is to keep pulling the idea further, so every turn —
        // including one that staged a capture — must end with ONE deepening
        // question. The prompt says so, but prompts alone let a "let me seed
        // that" turn end flat; this forces the question when the turn produced
        // work but no "?". Mirrors the action route's stage-contract nudge.
        // Not gated on route: a concept run must end with its question no
        // matter how the classifier routed the user's message.
        if store.activeSubmissionSkillID == CosmoInlineAssistantSkillID.concept.rawValue,
           preparedRequest.pipelineSteps.isEmpty,
           !Task.isCancelled {
            // Only answers produced by THIS run count. The previous turn's
            // question always contains a "?", so reading the session's last
            // answer let a capture-only turn (stage receipt, no prose) slip
            // through with the backstop silently satisfied — the exact flat
            // ending this nudge exists to prevent.
            let turnAnswers = store.paneMessages
                .filter { $0.role == .assistant && $0.proposalID == nil }
                .dropFirst(paneAnswerCount)
            let askedQuestion = turnAnswers.contains { $0.content.contains("?") }
            let didWork = store.proposals.count > proposalCount || !turnAnswers.isEmpty
            if didWork, !askedQuestion {
                print("[AGENT-PERF] inline concept go-deeper nudge: turn ended without a question")
                let nudge = await CosmoAgentService.shared.processMessage(
                    "Continue: you ended the turn without a deepening question. Reply now with a single answer_in_assistant_pane containing exactly ONE short follow-up question that pulls this concept one step further, phrased in the user's own vocabulary, warm and human, with zero process narration (no 'before I go further', no 'let me'). Do not stage any more edits and do not restate what you already said — only the one question. (Skip only if the concept is genuinely complete, in which case say so in one clause.)",
                    conversationId: preparedRequest.conversationID,
                    source: .inApp,
                    tierOverride: preparedRequest.tierOverride,
                    intentOverride: preparedRequest.intentOverride,
                    systemPromptOverride: preparedRequest.systemPromptOverride,
                    volatileContextOverride: preparedRequest.volatileContextOverride,
                    responseMode: preparedRequest.responseMode,
                    profileToolBundles: preparedRequest.profileToolBundles,
                    forcedToolBundles: preparedRequest.forcedToolBundles,
                    lightweightContext: true,
                    onToolActivity: { event in
                        Task { @MainActor in
                            store.receiveToolActivity(event)
                        }
                    },
                    onPaneAnswerDelta: { delta in
                        Task { @MainActor in
                            store.receivePaneAnswerDelta(delta)
                        }
                    }
                )
                if !nudge.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    response = nudge.0
                }
            }
        }

        CosmoAgentService.shared.noteInlinePrefixWritten()
        let perfTotalMs = Int(Date().timeIntervalSince(perfStart) * 1000)
        print("[AGENT-PERF] inline TOTAL=\(perfTotalMs)ms (prepare=\(perfPrepareMs)ms, agentLoop=\(perfTotalMs - perfPrepareMs)ms)")
        CosmoWindowViewModel.shared.finishInlineAssistantAgentRequest(
            contextAtomUUIDs: executor.contextAtomUUIDs,
            contextSourceIDs: executor.contextSourceIDs
        )

        let didReceivePaneAnswer = store.paneMessages.filter({
            $0.role == .assistant && $0.proposalID == nil
        }).count > paneAnswerCount
        let didReceiveProposal = store.proposals.count > proposalCount
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAnswer = trimmedResponse.isEmpty ? "I couldn't generate a response. Try asking again with a narrower request." : trimmedResponse

        if route == .answer, !didReceivePaneAnswer {
            store.receivePaneAnswer(title: nil, answer: fallbackAnswer, route: .answer)
        } else if route == .action,
                  store.shouldOpenPaneForCurrentActionExplanation,
                  didReceiveProposal,
                  !didReceivePaneAnswer {
            let proposal = store.proposals.last
            store.receivePaneAnswer(
                title: proposal?.title ?? "What I changed",
                answer: proposal?.summary ?? fallbackAnswer,
                route: .action
            )
        } else if route == .action, !didReceiveProposal, !didReceivePaneAnswer {
            store.receivePaneAnswer(
                title: "No reviewable edit yet",
                answer: fallbackAnswer,
                route: .answer
            )
        }
    }

    static let mock = CosmoInlineAssistantAgentBridge { _, _, _ in }

    /// Runs a multi-step skill pipeline: one scoped agent turn per step in the
    /// SAME conversation, so each step sees the previous steps' receipts. Steps
    /// can carry their own tool bundles and model tier (gather-on-Haiku →
    /// write-on-Sonnet → stage-edits).
    @MainActor
    private static func runPipeline(
        _ preparedRequest: CosmoInlineAssistantPreparedAgentRequest,
        route: CosmoInlineAssistantRoute,
        store: CosmoInlineAssistantStore
    ) async -> String {
        let steps = preparedRequest.pipelineSteps
        var lastResponse = ""

        for (index, step) in steps.enumerated() {
            if Task.isCancelled { break }
            store.receiveToolActivity(.started(
                name: "inline_pipeline_step",
                displayLabel: "Step \(index + 1) of \(steps.count): \(step.name)",
                args: [:]
            ))

            let volatile = [
                preparedRequest.volatileContextOverride,
                step.promptBlock(index: index, total: steps.count)
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")

            let stepBundles = step.toolBundles.map { preparedRequest.forcedToolBundles.union($0) }
                ?? preparedRequest.forcedToolBundles

            let (text, _) = await CosmoAgentService.shared.processMessage(
                index == 0
                    ? preparedRequest.prompt
                    : "Continue with pipeline step \(index + 1): \(step.name).",
                conversationId: preparedRequest.conversationID,
                source: .inApp,
                tierOverride: step.preferredModelTier ?? preparedRequest.tierOverride,
                intentOverride: preparedRequest.intentOverride,
                systemPromptOverride: preparedRequest.systemPromptOverride,
                volatileContextOverride: volatile,
                responseMode: preparedRequest.responseMode,
                profileToolBundles: preparedRequest.profileToolBundles,
                forcedToolBundles: stepBundles,
                lightweightContext: route == .action,
                onToolActivity: { event in
                    Task { @MainActor in
                        store.receiveToolActivity(event)
                    }
                },
                onPaneAnswerDelta: { delta in
                    Task { @MainActor in
                        store.receivePaneAnswerDelta(delta)
                    }
                }
            )
            lastResponse = text
        }

        return lastResponse
    }
}

/// Opportunistically writes the inline assistant's cached prompt prefix (tools +
/// identity + static route instructions) into the provider's prompt cache before
/// the user submits anything — fired on orb hover and surface activation, so the
/// first real keystroke-to-token skips the cold cache write.
@MainActor
enum CosmoInlineAssistantCacheWarmer {
    private static var inFlight = false

    /// The tier a real request would run on right now — the same resolution
    /// chain as `prepareInlineAssistantAgentRequest`. Prompt caches are
    /// model-scoped: warming any other model is pure waste and the first real
    /// request still pays the cold write.
    static var effectiveTier: AgentModelTier {
        CosmoWindowViewModel.shared.modelOverride
            ?? CosmoWindowViewModel.shared.selectedAgentProfile?.preferredModelTier
            ?? CosmoInlineAssistantRequestShape.defaultModelTier
    }

    static func warmIfNeeded(route: CosmoInlineAssistantRoute = .action) {
        warm(route: route, tier: effectiveTier)
    }

    /// Fire when the user switches models mid-session so the first request on
    /// the new model reads a warm prefix instead of paying a cold write.
    static func warmForModelChange() {
        warm(route: .action, tier: effectiveTier)
    }

    private static func warm(route: CosmoInlineAssistantRoute, tier: AgentModelTier) {
        guard !inFlight else { return }
        inFlight = true
        Task(priority: .utility) {
            await CosmoAgentService.shared.prewarmCachedPrefix(
                intent: CosmoInlineAssistantRequestShape.pinnedIntent(for: route),
                staticPromptOverride: CosmoInlineAssistantInstructionPrompt.staticInstructions(
                    for: route,
                    requiresPaneExplanation: false
                ),
                responseMode: CosmoInlineAssistantRequestShape.responseMode(for: route),
                profileToolBundles: [],
                forcedToolBundles: CosmoInlineAssistantRequestShape.baselineToolBundles(for: route),
                tier: tier
            )
            inFlight = false
        }
    }
}
