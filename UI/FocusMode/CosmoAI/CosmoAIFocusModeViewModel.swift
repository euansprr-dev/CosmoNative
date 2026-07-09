// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift
// Unified conversation state for Cosmo AI Focus Mode
// Routes through CosmoAgentService for full tool access
// February 2026

import SwiftUI
import Combine

@MainActor
final class CosmoAIFocusModeViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [CosmoWindowMessage] = []
    @Published var surfacedAtoms: [Atom] = []
    @Published var isProcessing = false
    @Published var connectedAtomUUIDs: [String] = []
    @Published var contextSources: [CosmoAIContextSource] = []
    @Published var inputText = ""

    // MARK: - Live Tool Activity (WP5)
    @Published var liveToolActivity: [ToolActivityGroup] = []
    @Published var activeToolLabel: String? = nil

    // MARK: - Mention State (WP2)
    @Published var mentionedAtoms: [Atom] = []
    @Published var showMentionOverlay = false
    @Published var mentionSearchText = ""
    @Published var modelOverride: AgentModelTier? = nil

    // MARK: - Properties
    let atom: Atom
    private let agentService = CosmoAgentService.shared
    private var conversationId: String
    private var pinnedContextSourceIDs: [String] = []

    // MARK: - Init
    init(atom: Atom) {
        self.atom = atom
        self.conversationId = "cosmo-ai-focus-\(atom.uuid)"
        loadConversationHistory()
        loadConnectedContext()
    }

    nonisolated static func defaultModelTier(userOverride: AgentModelTier?) -> AgentModelTier {
        userOverride ?? .autoDefault
    }

    // MARK: - Send Message
    func sendMessage() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        inputText = ""

        // Capture mention info before clearing
        let mentionInfo: [MentionedAtomInfo]? = mentionedAtoms.isEmpty ? nil : mentionedAtoms.map { atom in
            MentionedAtomInfo(uuid: atom.uuid, type: atom.type.rawValue, title: atom.title ?? "Untitled")
        }

        let userMsg = CosmoWindowMessage.user(query, mentionedAtoms: mentionInfo)
        messages.append(userMsg)

        isProcessing = true
        liveToolActivity = []
        activeToolLabel = nil

        await ensureSharedContextForCurrentTurn()
        let sharedContextBlock = await focusContextPackBlock(query: query)
        let enrichedText = [
            sharedContextBlock,
            buildEnrichedText(query: query)
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        // Clear mentions after capturing
        clearMentions()

        // Route through CosmoAgentService
        let (response, trace) = await agentService.processMessage(
            enrichedText,
            conversationId: conversationId,
            source: .inApp,
            tierOverride: Self.defaultModelTier(userOverride: modelOverride),
            onToolActivity: { [weak self] event in
                Task { @MainActor in
                    self?.handleToolActivity(event)
                }
            }
        )

        // Insert context trace if tools were used
        if trace.hasContent {
            messages.append(.contextTrace(from: trace))
        }

        // Freeze tool activity into the assistant message
        let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
        messages.append(CosmoWindowMessage(
            type: .assistant,
            content: response,
            toolActivityGroups: frozenGroups
        ))

        isProcessing = false
        liveToolActivity = []
        activeToolLabel = nil

        saveConversationHistory()
        await autoSurfaceRelated(query: query)
    }

    // MARK: - Mention Management

    func addMention(_ atom: Atom) {
        guard !mentionedAtoms.contains(where: { $0.uuid == atom.uuid }) else { return }
        mentionedAtoms.append(atom)
        showMentionOverlay = false
        mentionSearchText = ""
    }

    func removeMention(_ atom: Atom) {
        mentionedAtoms.removeAll { $0.uuid == atom.uuid }
    }

    func clearMentions() {
        mentionedAtoms = []
        showMentionOverlay = false
        mentionSearchText = ""
    }

    // MARK: - Build Enriched Text

    private func buildEnrichedText(query: String) -> String {
        var parts: [String] = []

        // Auto-inject connected context
        if !contextSources.isEmpty {
            var contextBlock = "## Connected Context (auto-loaded from canvas connections)"
            for source in contextSources {
                contextBlock += "\n[\(source.type.rawValue.uppercased()): \(source.title)] \(source.bodyPreview)"
            }
            parts.append(contextBlock)
        }

        // Inject mentioned atoms as referenced context
        if !mentionedAtoms.isEmpty {
            let mentionBlock = MentionContextHelper.buildMentionBlock(atoms: mentionedAtoms)
            parts.append(mentionBlock)
        }

        parts.append(query)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Shared Context

    private func ensureSharedContextForCurrentTurn() async {
        var sourceIDs = pinnedContextSourceIDs
        await pin(atom, into: &sourceIDs, pinState: .active)

        for uuid in connectedAtomUUIDs {
            guard let connectedAtom = try? await AtomRepository.shared.fetch(uuid: uuid) else { continue }
            await pin(connectedAtom, into: &sourceIDs, pinState: .pinned)
        }

        for mentionedAtom in mentionedAtoms {
            await pin(mentionedAtom, into: &sourceIDs, pinState: .pinned)
        }

        pinnedContextSourceIDs = sourceIDs
    }

    private func pin(_ atom: Atom, into sourceIDs: inout [String], pinState: ContextPinState) async {
        guard let sourceID = try? await ContextIndexStore.shared.upsert(atom: atom, pinState: pinState) else { return }
        if !sourceIDs.contains(sourceID) {
            sourceIDs.append(sourceID)
        }
    }

    private func focusContextPackBlock(query: String) async -> String? {
        guard !pinnedContextSourceIDs.isEmpty else { return nil }
        let request = ContextRetrievalRequest(
            query: query,
            conversationID: conversationId,
            surface: .focusPanel,
            purpose: .general,
            pinnedSourceIDs: pinnedContextSourceIDs,
            activeAtomUUID: atom.uuid,
            activeClientUUID: atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
            maxChunks: 8,
            tokenBudget: 4_500
        )
        let retrievalResults = (try? await CosmoRetrievalService.shared.retrieve(request)) ?? []
        let coreMemory = (try? await CosmoMemoryService.shared.coreMemory()) ?? []
        let workingMemory = (try? await CosmoMemoryService.shared.workingMemory(conversationID: conversationId)) ?? []
        guard !retrievalResults.isEmpty || !coreMemory.isEmpty || !workingMemory.isEmpty else {
            return nil
        }

        let pack = ContextPackAssembler.assemble(
            request: request,
            retrievalResults: retrievalResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: []
        )
        return pack.promptBlock
    }

    // MARK: - Live Tool Activity Handling

    private func handleToolActivity(_ event: ToolActivityEvent) {
        switch event {
        case .started(let name, let displayLabel, _):
            activeToolLabel = displayLabel
            let category = toolActivityCategory(for: name)
            let icon = toolActivityIcon(for: name)
            let item = ToolActivityItem(icon: icon, label: displayLabel, status: .active)

            if let idx = liveToolActivity.firstIndex(where: { $0.category == category }) {
                liveToolActivity[idx].items.append(item)
            } else {
                liveToolActivity.append(ToolActivityGroup(category: category, items: [item]))
            }

        case .completed(let name, _, let preview):
            let category = toolActivityCategory(for: name)
            if let gIdx = liveToolActivity.firstIndex(where: { $0.category == category }),
               let iIdx = liveToolActivity[gIdx].items.lastIndex(where: { $0.status == .active }) {
                liveToolActivity[gIdx].items[iIdx] = ToolActivityItem(
                    icon: liveToolActivity[gIdx].items[iIdx].icon,
                    label: liveToolActivity[gIdx].items[iIdx].label,
                    detail: preview,
                    status: .done
                )
            }

        case .allDone:
            activeToolLabel = nil
            for i in liveToolActivity.indices {
                liveToolActivity[i].isComplete = true
            }
        }
    }

    private func toolActivityCategory(for toolName: String) -> String {
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "Viewed" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "Generated" }
        if toolName == "web_search" { return "Searched" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "Analyzed" }
        return "Processed"
    }

    private func toolActivityIcon(for toolName: String) -> String {
        if toolName.hasPrefix("search_") || toolName.hasPrefix("find_") || toolName.hasPrefix("get_") || toolName.hasPrefix("list_") { return "doc.text" }
        if toolName.hasPrefix("generate_") || toolName.hasPrefix("create_") || toolName.hasPrefix("write_") { return "sparkles" }
        if toolName == "web_search" { return "globe" }
        if toolName.hasPrefix("score_") || toolName.hasPrefix("evaluate_") { return "chart.bar" }
        return "gearshape"
    }

    // MARK: - Auto-Surface Related
    private func autoSurfaceRelated(query: String) async {
        do {
            let results = try await VectorDatabase.shared.search(query: query, limit: 3, minSimilarity: 0.4)
            for result in results {
                if let uuid = result.entityUUID,
                   !surfacedAtoms.contains(where: { $0.uuid == uuid }) {
                    if let atom = try await AtomRepository.shared.fetch(uuid: uuid) {
                        surfacedAtoms.append(atom)
                    }
                }
            }
        } catch {
            // Silent failure for suggestions
        }
    }

    // MARK: - Context Loading
    func loadConnectedContext() {
        Task {
            do {
                let edges = try await GraphQueryEngine().getEdges(for: atom.uuid)
                var sources: [CosmoAIContextSource] = []
                var uuids: [String] = []
                var sourceIDs = pinnedContextSourceIDs

                for edge in edges.prefix(10) {
                    let connectedUUID = edge.sourceUUID == atom.uuid ? edge.targetUUID : edge.sourceUUID
                    if let connectedAtom = try await AtomRepository.shared.fetch(uuid: connectedUUID) {
                        let entityType = EntityType(rawValue: connectedAtom.type.rawValue) ?? .idea
                        sources.append(CosmoAIContextSource(
                            id: connectedAtom.uuid,
                            title: connectedAtom.title ?? "Untitled",
                            type: entityType,
                            bodyPreview: String((connectedAtom.body ?? "").prefix(200))
                        ))
                        uuids.append(connectedUUID)
                        if let sourceID = try? await ContextIndexStore.shared.upsert(atom: connectedAtom, pinState: .pinned),
                           !sourceIDs.contains(sourceID) {
                            sourceIDs.append(sourceID)
                        }
                    }
                }

                self.contextSources = sources
                self.connectedAtomUUIDs = uuids
                self.pinnedContextSourceIDs = sourceIDs
            } catch {
                print("Failed to load connected context: \(error)")
            }
        }
    }

    // MARK: - Persistence
    private func loadConversationHistory() {
        guard let structured = atom.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messagesArray = json["messages"] as? [[String: Any]] else { return }

        messages = messagesArray.compactMap { dict in
            guard let typeStr = dict["type"] as? String,
                  let content = dict["content"] as? String else { return nil }
            let timestamp = (dict["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let isStreaming = false

            switch typeStr {
            case "user":
                return CosmoWindowMessage(type: .user, content: content, timestamp: timestamp, isStreaming: isStreaming)
            case "assistant":
                return CosmoWindowMessage(type: .assistant, content: content, timestamp: timestamp, isStreaming: isStreaming)
            case "system":
                return CosmoWindowMessage(type: .system, content: content, timestamp: timestamp, isStreaming: isStreaming)
            default:
                return nil
            }
        }
    }

    private func saveConversationHistory() {
        let messagesArray: [[String: Any]] = messages.suffix(50).compactMap { msg in
            let typeStr: String
            switch msg.type {
            case .user: typeStr = "user"
            case .assistant: typeStr = "assistant"
            case .system: typeStr = "system"
            default: return nil  // Don't persist trace/change messages
            }
            return [
                "type": typeStr,
                "content": msg.content,
                "timestamp": msg.timestamp.timeIntervalSince1970
            ]
        }

        let json: [String: Any] = ["messages": messagesArray]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let jsonString = String(data: data, encoding: .utf8) {
            Task {
                var updatedAtom = atom
                updatedAtom.structured = jsonString
                _ = try? await AtomRepository.shared.update(updatedAtom)
            }
        }
    }

    // MARK: - Pin / Unpin Atom
    func pinAtom(_ atom: Atom) {
        if !surfacedAtoms.contains(where: { $0.uuid == atom.uuid }) {
            surfacedAtoms.append(atom)
        }
    }

    func unpinAtom(_ atom: Atom) {
        surfacedAtoms.removeAll { $0.uuid == atom.uuid }
    }
}
