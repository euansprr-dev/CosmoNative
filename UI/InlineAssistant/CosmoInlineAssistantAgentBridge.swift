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
}

struct CosmoInlineAssistantAgentBridge {
    var send: @MainActor (
        _ prompt: String,
        _ route: CosmoInlineAssistantRoute,
        _ store: CosmoInlineAssistantStore
    ) async throws -> Void

    static let live = CosmoInlineAssistantAgentBridge { prompt, route, store in
        let snapshot = store.activeEditableSnapshot()

        // Craft skills (/review, /riff) bypass the agent tool loop entirely:
        // comparables and stats are computed in Swift, then ONE structured
        // engine call delivers the result — evidence-grounded and ~10x cheaper
        // than running these skills through the 95-tool agent loop.
        if route == .answer,
           let craftSkillID = CosmoCraftSkillRunner.resolveCraftSkillID(
               selectedSkillID: store.activeSubmissionSkillID,
               prompt: prompt,
               surfaceKind: snapshot?.kind
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
        // to the editor the user was actually in.
        executor.workspaceEditBoundSurface = snapshot.map { ($0.surfaceID, $0.targetID) }

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
            selectedSkillID: store.activeSubmissionSkillID
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

        let (response, _) = await CosmoAgentService.shared.processMessage(
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
}

/// Opportunistically writes the inline assistant's cached prompt prefix (tools +
/// identity + static route instructions) into the provider's prompt cache before
/// the user submits anything — fired on orb hover and surface activation, so the
/// first real keystroke-to-token skips the cold cache write.
@MainActor
enum CosmoInlineAssistantCacheWarmer {
    private static var inFlight = false

    static func warmIfNeeded(route: CosmoInlineAssistantRoute = .action) {
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
                tier: .sensor
            )
            inFlight = false
        }
    }
}
