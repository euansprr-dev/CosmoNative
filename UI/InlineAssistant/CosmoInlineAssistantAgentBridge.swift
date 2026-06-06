import Foundation

struct CosmoInlineAssistantAgentBridge {
    var send: @MainActor (
        _ prompt: String,
        _ route: CosmoInlineAssistantRoute,
        _ store: CosmoInlineAssistantStore
    ) async throws -> Void

    static let live = CosmoInlineAssistantAgentBridge { prompt, route, store in
        let executor = AgentToolExecutor.shared
        executor.onWorkspaceEditProposal = { proposal in
            Task { @MainActor in
                store.receive(proposal: proposal)
            }
        }
        executor.onAssistantPaneAnswer = { title, answer in
            Task { @MainActor in
                store.receivePaneAnswer(title: title, answer: answer, route: route)
            }
        }

        let assistantMessageCount = store.paneMessages.filter { $0.role == .assistant }.count
        let proposalCount = store.proposals.count
        defer {
            executor.onWorkspaceEditProposal = nil
            executor.onAssistantPaneAnswer = nil
        }

        let activeSurface = CosmoEditableSurfaceRegistry.shared.activeSurface
        let snapshot = activeSurface?.editableSnapshot()
        let contextStatus = snapshot.map { "Reading \($0.title)" } ?? "Reading current context"
        store.receiveToolActivity(.started(
            name: "inline_context",
            displayLabel: contextStatus,
            args: [:]
        ))

        let surfaceContext = snapshot.map { snapshot in
            """
            Active editable surface:
            surfaceID: \(snapshot.surfaceID)
            targetID: \(snapshot.targetID)
            title: \(snapshot.title)
            kind: \(snapshot.kind.rawValue)
            sourceHash: \(snapshot.sourceHash)
            anchors: \(snapshot.anchors.map { "\($0.id):\($0.label)" }.joined(separator: ", "))
            text:
            \(snapshot.text)
            """
        } ?? "No editable surface is currently registered."

        let routeInstruction: String
        switch route {
        case .action:
            routeInstruction = "If the user is asking for edits, call propose_workspace_edit with exact source hashes and reviewed operations."
        case .answer:
            routeInstruction = "If answering a question, call answer_in_assistant_pane with the response."
        }

        let systemPrompt = [
            "You are Cosmo's inline workspace assistant.",
            routeInstruction,
            "Never mutate app state directly. All edits must be proposal operations.",
            "For edit requests, prefer proposal tools over prose replies.",
            surfaceContext
        ].joined(separator: "\n\n")

        let forcedBundles = CosmoInlineAssistantToolBundlePolicy.bundles(
            for: prompt,
            route: route,
            surfaceKind: snapshot?.kind
        )

        let (response, _) = await CosmoAgentService.shared.processMessage(
            prompt,
            conversationId: "cosmo-inline-assistant",
            source: .inApp,
            tierOverride: CosmoWindowViewModel.shared.modelOverride,
            systemPromptOverride: systemPrompt,
            responseMode: .automatic,
            profileToolBundles: [],
            forcedToolBundles: forcedBundles,
            onToolActivity: { event in
                Task { @MainActor in
                    store.receiveToolActivity(event)
                }
            }
        )

        let didReceiveAssistant = store.paneMessages.filter({ $0.role == .assistant }).count > assistantMessageCount
        let didReceiveProposal = store.proposals.count > proposalCount
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAnswer = trimmedResponse.isEmpty ? "I couldn't generate a response. Try asking again with a narrower request." : trimmedResponse

        if route == .answer, !didReceiveAssistant {
            store.receivePaneAnswer(title: nil, answer: fallbackAnswer, route: .answer)
        } else if route == .action, !didReceiveProposal, !didReceiveAssistant {
            store.receivePaneAnswer(
                title: "No reviewable edit yet",
                answer: fallbackAnswer,
                route: .answer
            )
        }
    }

    static let mock = CosmoInlineAssistantAgentBridge { _, _, _ in }
}
