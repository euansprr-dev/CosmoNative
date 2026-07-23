import XCTest
@testable import CosmoOS

final class CosmoWindowRoutingTests: XCTestCase {
    @MainActor
    func testAgentToolRegistryExposesCreateNoteTool() {
        let names = Set(AgentToolRegistry.shared.allTools.map(\.name))

        XCTAssertTrue(names.contains("create_note"))
    }

    func testExpandedAgentModelTiersUseExactOpenRouterIds() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.modelId, "openai/gpt-5.5")
        XCTAssertEqual(AgentModelTier.opus47.modelId, "anthropic/claude-opus-4.7")
        XCTAssertEqual(AgentModelTier.gptChatLatest.modelId, "openai/gpt-chat-latest")
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.modelId, "google/gemini-3-flash-preview")
        XCTAssertEqual(AgentModelTier.gemini35Flash.modelId, "google/gemini-3.5-flash")
    }

    func testExpandedAgentModelTiersExposeReadableLabels() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.displayLabel, "GPT 5.5 Thinking")
        XCTAssertEqual(AgentModelTier.opus47.displayLabel, "Opus 4.7")
        XCTAssertEqual(AgentModelTier.gptChatLatest.displayLabel, "GPT Chat Latest")
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.displayLabel, "Gemini 3 Flash")
        XCTAssertEqual(AgentModelTier.gemini35Flash.displayLabel, "Gemini 3.5 Flash")
    }

    func testExplicitModelFailoverChainsStartWithSelectedModel() {
        XCTAssertEqual(ModelFailoverChain.chain(for: .gpt55Thinking).models.first?.modelId, "openai/gpt-5.5")
        XCTAssertEqual(ModelFailoverChain.chain(for: .opus47).models.first?.modelId, "anthropic/claude-opus-4.7")
        XCTAssertEqual(ModelFailoverChain.chain(for: .gptChatLatest).models.first?.modelId, "openai/gpt-chat-latest")
        XCTAssertEqual(ModelFailoverChain.chain(for: .geminiFlashLatest).models.first?.modelId, "google/gemini-3-flash-preview")
        XCTAssertEqual(ModelFailoverChain.chain(for: .gemini35Flash).models.first?.modelId, "google/gemini-3.5-flash")
    }

    func testGeminiFlashLatestFailoverNeverFallsBackToOpus() {
        let modelIds = ModelFailoverChain.chain(for: .geminiFlashLatest).models.map(\.modelId)

        XCTAssertFalse(modelIds.contains { $0.contains("opus") })
    }

    func testOpenRouterSettingsCatalogIncludesNewModels() {
        let ids = Set(AgentProvider.openRouterModels.map(\.id))

        XCTAssertTrue(ids.contains("openai/gpt-5.5"))
        XCTAssertTrue(ids.contains("anthropic/claude-opus-4.7"))
        XCTAssertTrue(ids.contains("openai/gpt-chat-latest"))
        XCTAssertTrue(ids.contains("google/gemini-3-flash-preview"))
        XCTAssertTrue(ids.contains("google/gemini-3.5-flash"))
        XCTAssertFalse(ids.contains("~google/gemini-flash-latest"))
        XCTAssertFalse(ids.contains("google/gemini-3.1-flash-lite-preview"))
    }

    func testOpenRouterSettingsCatalogDoesNotContainDuplicateModelIds() {
        let ids = AgentProvider.openRouterModels.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAPIKeysSettingsExposeAgentLLMKeyUsedByCraftSkills() throws {
        let settingsSource = try source("Settings/CosmoSettingsView.swift")

        XCTAssertTrue(settingsSource.contains("Anthropic Agent LLM Key"))
        XCTAssertTrue(settingsSource.contains("keyIdentifier: \"agent_llm\""))
        XCTAssertTrue(settingsSource.contains("case \"agent_llm\": return APIKeys.agentLLM"))
    }

    func testAPIKeyInputsCapturePasteInsideSettingsOverlay() throws {
        let settingsSource = try source("Settings/CosmoSettingsView.swift")

        XCTAssertTrue(settingsSource.contains("PasteAwareAPIKeyField("))
        XCTAssertTrue(settingsSource.contains("override func performKeyEquivalent(with event: NSEvent) -> Bool"))
        XCTAssertTrue(settingsSource.contains("pasteStringFromPasteboard()"))
        XCTAssertTrue(settingsSource.contains("NSPasteboard.general.string(forType: .string)"))
        XCTAssertFalse(settingsSource.contains("SecureField(placeholder, text: $apiKey)"))
    }

    func testSettingsOverlayBlocksInlineAssistantPasteTarget() throws {
        let mainViewSource = try source("Navigation/MainView.swift")

        XCTAssertTrue(mainViewSource.contains("isBlockingOverlayPresented: showSettings"))
        XCTAssertTrue(mainViewSource.contains("clearFirstResponder(in: NSApp.keyWindow)"))
    }

    func testMissingAgentLLMErrorNamesAPIKeysRoute() throws {
        let craftSource = try source("AI/Craft/CosmoCraftEngine.swift")

        XCTAssertTrue(craftSource.contains("Settings → API Keys"))
        XCTAssertTrue(craftSource.contains("Anthropic Agent LLM Key"))
    }

    func testGPT55ThinkingUsesOpenRouterReasoningParameter() {
        XCTAssertEqual(OpenAIProvider.reasoningEffort(for: AgentModelTier.gpt55Thinking.modelId), "high")
        XCTAssertNil(OpenAIProvider.reasoningEffort(for: AgentModelTier.gptChatLatest.modelId))
    }

    func testCosmoModelPickerOptionsIncludeRequestedModels() {
        let ids = Set(CosmoModelOption.all.map(\.id))

        XCTAssertTrue(ids.contains("gpt55Thinking"))
        XCTAssertTrue(ids.contains("opus47"))
        XCTAssertTrue(ids.contains("gptChatLatest"))
        XCTAssertTrue(ids.contains("geminiFlashLatest"))
        XCTAssertTrue(ids.contains("gemini35Flash"))
    }

    func testAgentModelTierMaxTokensForNewModels() {
        XCTAssertEqual(AgentModelTier.gpt55Thinking.maxTokens, 16384)
        XCTAssertEqual(AgentModelTier.opus47.maxTokens, 16384)
        XCTAssertEqual(AgentModelTier.gptChatLatest.maxTokens, 8192)
        XCTAssertEqual(AgentModelTier.geminiFlashLatest.maxTokens, 8192)
        XCTAssertEqual(AgentModelTier.gemini35Flash.maxTokens, 8192)
    }

    func testAutoModeUsesOneStableDefaultForEveryIntent() {
        let intents: [AgentIntent] = [
            .capture, .brainstorm, .plan, .query, .execute, .debrief,
            .reflect, .correct, .meta, .strategy, .draft, .research,
            .synthesize, .analyze, .organize
        ]

        // ONE default across all intents — per-intent switching would fragment
        // the prompt cache. The identity of that default is .autoDefault
        // (currently Sonnet 5: near-Opus agentic quality at Sonnet pricing,
        // unified with the inline assistant's default).
        for intent in intents {
            XCTAssertEqual(
                CosmoAgentService.defaultModelTier(for: intent),
                .autoDefault,
                "Auto mode must not switch models for intent \(intent.rawValue)"
            )
        }
        XCTAssertEqual(AgentModelTier.autoDefault, .sonnet5)
    }

    func testGeminiFlashChainDoesNotFailOverToAnotherModelWhenLocked() {
        let chain = ModelFailoverChain.chain(for: .geminiFlashLatest, allowCrossModelFailover: false)

        XCTAssertEqual(chain.models.map(\.modelId), [AgentModelTier.geminiFlashLatest.modelId])
    }

    func testConversationModelLockPersistsManualSelection() {
        var conversation = AgentConversation(id: "conversation-1", source: .inApp)
        conversation.modelLock = .opus47

        XCTAssertEqual(conversation.effectiveModelTier(userOverride: nil), .opus47)
        XCTAssertEqual(conversation.effectiveModelTier(userOverride: .geminiFlashLatest), .geminiFlashLatest)
    }

    func testHistoryBuilderKeepsAllMessagesWhenUnderModelWindow() {
        var messages: [AgentMessage] = []
        for index in 1...40 {
            messages.append(.user("User decision \(index): keep slide \(index) direction."))
            messages.append(.assistant("Acknowledged decision \(index)."))
        }

        let window = CosmoAgentService.buildContextWindowForTests(
            messages,
            modelTier: .geminiFlashLatest,
            reservedOutputTokens: 8_192,
            reservedSystemTokens: 12_000
        )

        XCTAssertEqual(window.count, messages.count)
        XCTAssertTrue(window.first?.content.contains("User decision 1") == true)
    }

    func testFocusModeUsesAutoDefaultWhenNoManualOverrideExists() {
        XCTAssertEqual(CosmoAIFocusModeViewModel.defaultModelTier(userOverride: nil), .autoDefault)
        XCTAssertEqual(CosmoAIFocusModeViewModel.defaultModelTier(userOverride: .opus47), .opus47)
    }

    func testCosmoModelPickerLabelsGeminiFlashAsEverydayDefault() {
        let autoOption = CosmoModelOption.all.first { $0.id == "auto" }
        let sonnetOption = CosmoModelOption.all.first { $0.id == "sonnet" }
        let geminiOption = CosmoModelOption.all.first { $0.id == "geminiFlashLatest" }
        let gemini35Option = CosmoModelOption.all.first { $0.id == "gemini35Flash" }

        XCTAssertEqual(autoOption?.detail, "Sonnet 5 by default")
        XCTAssertEqual(sonnetOption?.title, "Sonnet 5")
        XCTAssertEqual(sonnetOption?.detail, "Daily driver via Claude API")
        XCTAssertEqual(geminiOption?.title, "Gemini 3 Flash")
        XCTAssertEqual(geminiOption?.detail, "Pinned everyday search and brainstorming")
        XCTAssertEqual(gemini35Option?.title, "Gemini 3.5 Flash")
        XCTAssertEqual(gemini35Option?.detail, "Higher-cost agentic and deepening work")
    }

    func testAutoModelRoutingNeverUsesOpusWriterTier() {
        let autoIntents: [AgentIntent] = [
            .capture, .brainstorm, .plan, .query, .execute, .debrief,
            .reflect, .correct, .meta, .strategy, .draft, .analyze
        ]

        XCTAssertFalse(autoIntents.contains { CosmoAgentService.defaultModelTier(for: $0) == .writer })
    }

    func testAutoDefaultFailoverChainsStartWithTheAutoDefaultModel() {
        let autoIntents: [AgentIntent] = [
            .capture, .brainstorm, .plan, .query, .execute, .debrief,
            .reflect, .correct, .meta, .strategy, .draft, .research,
            .synthesize, .analyze, .organize
        ]

        let startingModelIds = autoIntents.compactMap {
            ModelFailoverChain.chain(for: CosmoAgentService.defaultModelTier(for: $0)).models.first?.modelId
        }

        XCTAssertTrue(startingModelIds.allSatisfy { $0 == AgentModelTier.autoDefault.modelId })
    }

    func testExplicitPickerStillAllowsOpus() {
        let opusOption = CosmoModelOption.all.first { $0.id == "opus" }
        let opus47Option = CosmoModelOption.all.first { $0.id == "opus47" }

        XCTAssertEqual(opusOption?.tier, .writer)
        XCTAssertEqual(opus47Option?.tier, .opus47)
    }

    func testBypassesFlashRouterForFollowUpAboutCapturedContent() {
        let recentAssistant = [
            "Captured Instagram swipe.",
            "Saved idea: The hook is worth adapting."
        ]

        XCTAssertTrue(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: recentAssistant
            )
        )
    }

    func testDoesNotBypassFlashRouterWithoutCaptureHistory() {
        XCTAssertFalse(
            CosmoWindowViewModel.shouldBypassFlashRouter(
                text: "turn this into a carousel",
                recentAssistantContents: ["I can help think through that."]
            )
        )
    }

    func testProfileInspectionRequestsBypassFlashRouter() {
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback("check out Josh's content profile"))
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback("show me Josh's best performing posts"))
    }

    func testFlashLiteRouterUsesPinnedCheapClassifierModel() {
        XCTAssertEqual(FlashLiteRouter.modelId, "google/gemini-3.1-flash-lite")
    }

    func testAgentContextAtomMergePreservesPinnedProfilesWhenMentionsArePresent() {
        XCTAssertEqual(
            CosmoAgentService.mergedContextAtomUUIDs(
                existing: ["profile-1", "content-1"],
                mentioned: ["content-1", "swipe-1"]
            ),
            ["profile-1", "content-1", "swipe-1"]
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

@MainActor
final class ClientProfileToolTests: XCTestCase {
    private var createdUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = createdUUIDs.reversed()
        createdUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        try await super.tearDown()
    }

    func testGetClientProfileReturnsCompleteTopPostsAndDocuments() async throws {
        let fullPost = String(repeating: "Josh full performer sentence. ", count: 80)
        let fullDocument = String(repeating: "Josh document transcript sentence. ", count: 90)
        let profile = ClientProfileMetadata(
            clientId: UUID().uuidString,
            clientName: "Josh Profile Tool Test",
            platforms: [.instagram],
            topPerformingTranscripts: [fullPost],
            documents: [
                ProfileDocument(
                    category: .reel,
                    title: "Best reel",
                    content: fullDocument,
                    platform: "instagram",
                    likes: 12,
                    shares: 3,
                    saves: 4,
                    comments: 5,
                    leads: 6,
                    sourceURL: "https://example.com/reel"
                )
            ],
            topPerformingPosts: [
                TopPost(
                    transcript: fullPost,
                    platform: "instagram",
                    likes: 100,
                    shares: 20,
                    leads: 7,
                    views: 12_000,
                    datePosted: "2026-05-01"
                )
            ]
        )

        let created = try await AtomRepository.shared.create(
            Atom.new(type: .clientProfile, title: "Josh Profile Tool Test").withMetadata(profile)
        )
        createdUUIDs.append(created.uuid)

        let result = try await AgentToolExecutor.shared.execute(
            toolName: "get_client_profile",
            arguments: ["client_name": "Josh Profile Tool Test"]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )

        let posts = try XCTUnwrap(payload["topPerformingPosts"] as? [[String: Any]])
        XCTAssertEqual(posts.first?["transcript"] as? String, fullPost)

        let transcripts = payload["topPerformingTranscripts"] as? [String]
        XCTAssertEqual(transcripts?.first, fullPost)

        let documents = try XCTUnwrap(payload["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.first?["content"] as? String, fullDocument)
        XCTAssertEqual(documents.first?["sourceURL"] as? String, "https://example.com/reel")
    }
}

@MainActor
final class AgentNoteCreationToolTests: XCTestCase {
    private var createdUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = createdUUIDs.reversed()
        createdUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        try await super.tearDown()
    }

    func testCreateNoteToolCreatesNoteAtomWithBody() async throws {
        let title = "Agent Note Creation Test \(UUID().uuidString)"
        let body = "This should be saved as a real note atom, not a content atom."

        let result = try await AgentToolExecutor.shared.execute(
            toolName: "create_note",
            arguments: [
                "title": title,
                "body": body
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )
        let uuid = try XCTUnwrap(payload["uuid"] as? String)
        createdUUIDs.append(uuid)

        let fetchedAtom = try await AtomRepository.shared.fetch(uuid: uuid)
        let atom = try XCTUnwrap(fetchedAtom)
        XCTAssertEqual(atom.type, .note)
        XCTAssertEqual(atom.title, title)
        XCTAssertEqual(atom.body, body)
        XCTAssertEqual(payload["message"] as? String, "Note created: \(title)")
    }
}
