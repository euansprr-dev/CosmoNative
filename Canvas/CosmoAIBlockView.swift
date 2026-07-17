// CosmoOS/Canvas/CosmoAIBlockView.swift
// Modern chat preview block — routes through CosmoAgentService
// Compact message preview with inline input bar
// February 2026

import SwiftUI
import AppKit

// MARK: - Supporting Types (kept for cross-file usage)

struct CosmoAIContextSource: Identifiable {
    let id: String
    let title: String
    let type: EntityType
    let bodyPreview: String
}

// MARK: - CosmoAIBlockView

struct CosmoAIBlockView: View {
    let block: CanvasBlock

    @StateObject private var state = CosmoAIBlockChatState()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: DS.accent,
            icon: "brain",
            title: block.title.isEmpty ? "Cosmo AI" : block.title,
            onClose: closeBlock
        ) {
            chatContent
                .padding(12)
        }
        .onAppear {
            state.loadConversation(entityUuid: block.entityUuid)
            state.loadConnectedContext(entityUuid: block.entityUuid)
            autoStartIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.updateBlockContent)) { notification in
            if let blockId = notification.userInfo?["blockId"] as? String,
               blockId == block.id,
               let action = notification.userInfo?["action"] as? String,
               action == "refreshContext" {
                state.loadConnectedContext(entityUuid: block.entityUuid)
            }
        }
        .onTapGesture(count: 2) {
            openFocusMode()
        }
    }

    // MARK: - Auto-Start from Voice Command

    private func autoStartIfNeeded() {
        if let initialQuery = block.metadata["query"], !initialQuery.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                sendMessage(initialQuery)
            }
        }
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Connected context count chip
            if !state.contextSources.isEmpty {
                contextCountChip
            }

            // Message preview area
            if state.messages.isEmpty && !state.isProcessing {
                emptyStateView
            } else {
                messagePreviewList
            }

            // Typing indicator
            if state.isProcessing {
                typingIndicator
            }

            Spacer(minLength: 0)

            // Compact tool activity summary
            if let activitySummary = state.lastToolActivitySummary {
                toolActivityRow(activitySummary)
            }

            // Input bar
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Context Count Chip

    private var contextCountChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.system(size: 9))
            Text("\(state.contextSources.count) connected")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(DS.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DS.border, in: Capsule())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DS.accent.opacity(0.5))

            Text("Ask Cosmo anything")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Message Preview List

    private var messagePreviewList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Show last 4 messages
            ForEach(state.messages.suffix(4)) { message in
                messagePreviewRow(message)
            }
        }
    }

    @ViewBuilder
    private func messagePreviewRow(_ message: CosmoWindowMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            let isUser = isUserMessage(message)
            Text(isUser ? "You:" : "Cosmo:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isUser ? DS.textSecondary : DS.accent)
                .frame(width: 42, alignment: .leading)

            Text(message.content.prefix(100).description)
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isUserMessage(_ message: CosmoWindowMessage) -> Bool {
        switch message.type {
        case .user: return true
        default: return false
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.accent)
                    .frame(width: 5, height: 5)
                    .opacity(state.typingDotIndex == i ? 1.0 : 0.3)
            }

            if let toolLabel = state.activeToolLabel {
                Text(toolLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            } else {
                Text("Thinking…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DS.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Tool Activity Row

    private func toolActivityRow(_ summary: String) -> some View {
        HStack(spacing: 6) {
            Text("\u{250A}")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)

            Text(summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
                .lineLimit(1)

            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(CosmoColors.emerald)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    Text("Ask Cosmo anything…")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                }

                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.text)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage(inputText)
                    }
            }

            if !inputText.isEmpty {
                Button(action: { sendMessage(inputText) }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(DS.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isInputFocused ? DS.accent.opacity(0.4) : DS.border, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        inputText = ""
        isInputFocused = false

        state.sendMessage(query, entityUuid: block.entityUuid)
    }

    private func closeBlock() {
        NotificationCenter.default.post(
            name: .removeBlock,
            object: nil,
            userInfo: ["blockId": block.id]
        )
    }

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.cosmoAI,
                "id": block.entityId,
                "entityUuid": block.entityUuid
            ]
        )
    }
}

// MARK: - CosmoAIBlockChatState

@MainActor
final class CosmoAIBlockChatState: ObservableObject {
    @Published var messages: [CosmoWindowMessage] = []
    @Published var isProcessing = false
    @Published var contextSources: [CosmoAIContextSource] = []
    @Published var activeToolLabel: String? = nil
    @Published var lastToolActivitySummary: String? = nil
    @Published var typingDotIndex: Int = 0

    private var typingTimer: Timer?
    private var liveToolActivity: [ToolActivityGroup] = []
    private let agentService = CosmoAgentService.shared

    // MARK: - Load Conversation from Atom structured JSON

    func loadConversation(entityUuid: String) {
        Task {
            // Warm store first — the thinkspace switch batch-fetched every
            // entity atom; the repository round-trip is the fallback.
            var loadedAtom: Atom? = CanvasAtomWarmStore.shared.atom(uuid: entityUuid)
            if loadedAtom == nil {
                loadedAtom = try? await AtomRepository.shared.fetch(uuid: entityUuid)
            }
            guard let atom = loadedAtom,
                  let structured = atom.structured,
                  let data = structured.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messagesArray = json["messages"] as? [[String: Any]] else { return }

            let loaded: [CosmoWindowMessage] = messagesArray.compactMap { dict in
                guard let typeStr = dict["type"] as? String,
                      let content = dict["content"] as? String else { return nil }
                let timestamp = (dict["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()

                switch typeStr {
                case "user":
                    return CosmoWindowMessage(type: .user, content: content, timestamp: timestamp, isStreaming: false)
                case "assistant":
                    return CosmoWindowMessage(type: .assistant, content: content, timestamp: timestamp, isStreaming: false)
                case "system":
                    return CosmoWindowMessage(type: .system, content: content, timestamp: timestamp, isStreaming: false)
                default:
                    return nil
                }
            }

            self.messages = loaded
        }
    }

    // MARK: - Send Message

    func sendMessage(_ query: String, entityUuid: String) {
        let userMsg = CosmoWindowMessage.user(query)
        messages.append(userMsg)

        isProcessing = true
        lastToolActivitySummary = nil
        liveToolActivity = []
        activeToolLabel = nil
        startTypingAnimation()

        // Build enriched text with connected context
        let enrichedText = buildEnrichedText(query: query)

        Task {
            let conversationId = "cosmo-ai-block-\(entityUuid)"

            let (response, trace) = await agentService.processMessage(
                enrichedText,
                conversationId: conversationId,
                source: .inApp,
                onToolActivity: { [weak self] event in
                    Task { @MainActor in
                        self?.handleToolActivity(event)
                    }
                }
            )

            // Build tool activity summary
            let totalItems = liveToolActivity.reduce(0) { $0 + $1.items.count }
            if totalItems > 0 {
                let categories = liveToolActivity.map { "\($0.category) \($0.items.count) \($0.items.count == 1 ? "file" : "files")" }
                lastToolActivitySummary = categories.joined(separator: " \u{00B7} ")
            }

            // Append context trace if tools were used
            if trace.hasContent {
                messages.append(.contextTrace(from: trace))
            }

            // Append assistant response
            let frozenGroups = liveToolActivity.isEmpty ? nil : liveToolActivity
            messages.append(CosmoWindowMessage(
                type: .assistant,
                content: response,
                toolActivityGroups: frozenGroups
            ))

            isProcessing = false
            activeToolLabel = nil
            stopTypingAnimation()

            saveConversation(entityUuid: entityUuid)
        }
    }

    // MARK: - Build Enriched Text

    private func buildEnrichedText(query: String) -> String {
        var parts: [String] = []

        if !contextSources.isEmpty {
            var contextBlock = "## Connected Context (auto-loaded from canvas connections)"
            for source in contextSources {
                contextBlock += "\n[\(source.type.rawValue.uppercased()): \(source.title)] \(source.bodyPreview)"
            }
            parts.append(contextBlock)
        }

        parts.append(query)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Tool Activity Handling

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

    // MARK: - Typing Animation

    private func startTypingAnimation() {
        typingDotIndex = 0
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.typingDotIndex = (self.typingDotIndex + 1) % 3
            }
        }
    }

    private func stopTypingAnimation() {
        typingTimer?.invalidate()
        typingTimer = nil
    }

    // MARK: - Persistence

    private func saveConversation(entityUuid: String) {
        let messagesArray: [[String: Any]] = messages.suffix(50).compactMap { msg in
            let typeStr: String
            switch msg.type {
            case .user: typeStr = "user"
            case .assistant: typeStr = "assistant"
            case .system: typeStr = "system"
            default: return nil
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
                if var atom = try? await AtomRepository.shared.fetch(uuid: entityUuid) {
                    atom.structured = jsonString
                    _ = try? await AtomRepository.shared.update(atom)
                }
            }
        }
    }

    // MARK: - Connected Context Loading

    func loadConnectedContext(entityUuid: String) {
        Task {
            do {
                var sources: [CosmoAIContextSource] = []
                var uuids: [String] = []

                // Check atom's direct links
                if let atom = try await AtomRepository.shared.fetch(uuid: entityUuid) {
                    for link in atom.linksList {
                        if let linkedAtom = try await AtomRepository.shared.fetch(uuid: link.uuid) {
                            let entityType = EntityType(rawValue: linkedAtom.type.rawValue) ?? .idea
                            if !uuids.contains(linkedAtom.uuid) {
                                sources.append(CosmoAIContextSource(
                                    id: linkedAtom.uuid,
                                    title: linkedAtom.title ?? "Untitled",
                                    type: entityType,
                                    bodyPreview: String((linkedAtom.body ?? "").prefix(300))
                                ))
                                uuids.append(linkedAtom.uuid)
                            }
                        }
                    }
                }

                // Also from graph edges
                let edges = try await GraphQueryEngine().getEdges(for: entityUuid)
                for edge in edges.prefix(10) {
                    let connectedUUID = edge.sourceUUID == entityUuid ? edge.targetUUID : edge.sourceUUID
                    if !uuids.contains(connectedUUID) {
                        if let connectedAtom = try await AtomRepository.shared.fetch(uuid: connectedUUID) {
                            let entityType = EntityType(rawValue: connectedAtom.type.rawValue) ?? .idea
                            sources.append(CosmoAIContextSource(
                                id: connectedAtom.uuid,
                                title: connectedAtom.title ?? "Untitled",
                                type: entityType,
                                bodyPreview: String((connectedAtom.body ?? "").prefix(300))
                            ))
                            uuids.append(connectedUUID)
                        }
                    }
                }

                self.contextSources = sources
            } catch {
                print("Failed to load connected context: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview("Cosmo AI Block") {
    ZStack {
        CosmoColors.thinkspaceVoid
            .ignoresSafeArea()

        CosmoAIBlockView(
            block: CanvasBlock.cosmoAIBlock(position: CGPoint(x: 200, y: 200))
        )
    }
    .frame(width: 420, height: 380)
}
