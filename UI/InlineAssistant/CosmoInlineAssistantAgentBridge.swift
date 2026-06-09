import Foundation

struct CosmoInlineAssistantPreparedAgentRequest {
    var prompt: String
    var conversationID: String
    var tierOverride: AgentModelTier?
    var systemPromptOverride: String?
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
        let perfStart = Date()
        let executor = AgentToolExecutor.shared
        executor.onWorkspaceEditProposal = { proposal in
            store.receive(proposal: proposal)
        }
        executor.onAssistantPaneAnswer = { title, answer in
            store.receivePaneAnswer(title: title, answer: answer, route: route)
        }

        let paneAnswerCount = store.paneMessages.filter {
            $0.role == .assistant && $0.proposalID == nil
        }.count
        let proposalCount = store.proposals.count
        defer {
            executor.onWorkspaceEditProposal = nil
            executor.onAssistantPaneAnswer = nil
            executor.contextAtomUUIDs = []
            executor.contextSourceIDs = []
            executor.contextConversationID = nil
            executor.activeClientUUID = nil
        }

        let activeSurface = CosmoEditableSurfaceRegistry.shared.activeSurface
        let snapshot = activeSurface?.editableSnapshot()
        store.activateSession(surfaceID: snapshot?.surfaceID)
        let contextStatus = snapshot.map { "Reading \($0.title)" } ?? "Reading current context"
        store.receiveToolActivity(.started(
            name: "inline_context",
            displayLabel: contextStatus,
            args: [:]
        ))

        let preparedRequest = await CosmoWindowViewModel.shared.prepareInlineAssistantAgentRequest(
            prompt: prompt,
            route: route,
            snapshot: snapshot,
            inlineContextAtoms: store.selectedContextAtoms,
            selectedSkillID: store.activeSubmissionSkillID
        )
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
            systemPromptOverride: preparedRequest.systemPromptOverride,
            responseMode: preparedRequest.responseMode,
            profileToolBundles: preparedRequest.profileToolBundles,
            forcedToolBundles: preparedRequest.forcedToolBundles,
            // Action edits inject their own compact context — skip the heavy Command-A layers.
            lightweightContext: route == .action,
            onToolActivity: { event in
                Task { @MainActor in
                    store.receiveToolActivity(event)
                }
            }
        )
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
