// CosmoOS/Canvas/CosmoAIBlockView.swift
// Premium AI Agent Card - Clean, minimal, powerful
// States: Idle (ready), Thinking (lavender), Research (coral), Complete (emerald)
// Now with 4 intelligent modes: Think, Research, Recall, Act

import SwiftUI
import AppKit

// MARK: - CosmoMode (4 intelligent modes)

enum CosmoMode: String, CaseIterable {
    case think = "Think"
    case research = "Research"
    case recall = "Recall"
    case act = "Act"

    var icon: String {
        switch self {
        case .think: return "brain"
        case .research: return "globe"
        case .recall: return "magnifyingglass"
        case .act: return "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .think: return CosmoColors.lavender
        case .research: return Color(red: 0.91, green: 0.48, blue: 0.36)
        case .recall: return CosmoColors.skyBlue
        case .act: return CosmoColors.emerald
        }
    }

    static func infer(from query: String) -> CosmoMode {
        let q = query.lowercased()
        if q.hasPrefix("research") || q.hasPrefix("search") || q.hasPrefix("find out") || q.contains("latest on") {
            return .research
        }
        if q.hasPrefix("what do i know") || q.hasPrefix("recall") || q.hasPrefix("remember") || q.hasPrefix("find my") || q.contains("related to") {
            return .recall
        }
        if q.hasPrefix("create") || q.hasPrefix("make") || q.hasPrefix("summarize") || q.hasPrefix("analyze") || q.contains("should i work on") {
            return .act
        }
        return .think
    }
}

// MARK: - Supporting Types

struct RecallResult: Identifiable {
    let id = UUID()
    let atom: Atom
    let similarity: Float?
    let source: String // "vector", "keyword", "graph"
}

struct ActionResult: Identifiable {
    let id = UUID()
    let description: String
    let createdAtomId: Int64?
    let createdAtomType: EntityType?
}

struct ContextSource: Identifiable {
    let id: String
    let title: String
    let type: EntityType
    let bodyPreview: String
}

// MARK: - CosmoAIBlockView

struct CosmoAIBlockView: View {
    let block: CanvasBlock
    @StateObject private var state = CosmoAIBlockState()
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var inputText = ""
    @State private var hasAutoStarted = false
    @FocusState private var isInputFocused: Bool

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: state.chromeAccentColor,
            icon: state.chromeIcon,
            title: "Cosmo",
            isExpanded: $isExpanded,
            onClose: closeBlock
        ) {
            contentView
                .padding(16)
        }
        .onChange(of: state.uiState) { _, newState in
            // Auto-expand when results arrive
            if newState == .responding && !isExpanded {
                withAnimation(BlockAnimations.expand) {
                    isExpanded = true
                    expansionManager.expand(block.id)
                }
            }
        }
        .onAppear {
            // Auto-execute query if provided via voice command
            autoStartIfNeeded()
            // Load connected context from graph edges and atom links
            state.loadConnectedContext(entityUuid: block.entityUuid)
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.updateBlockContent)) { notification in
            if let blockId = notification.userInfo?["blockId"] as? String,
               blockId == block.id,
               let action = notification.userInfo?["action"] as? String,
               action == "refreshContext" {
                state.loadConnectedContext(entityUuid: block.entityUuid)
            }
        }
        .onChange(of: inputText) { _, _ in
            syncCapturingState()
        }
        .onChange(of: isInputFocused) { _, _ in
            syncCapturingState()
        }
    }

    // MARK: - Auto-Start from Voice Command
    private func autoStartIfNeeded() {
        guard !hasAutoStarted else { return }

        // Check if block was created with an initial query (from voice command)
        if let initialQuery = block.metadata["query"], !initialQuery.isEmpty {
            hasAutoStarted = true

            // Check for research mode flag
            let isResearchMode = block.metadata["mode"] == "research"

            // Small delay to ensure view is fully rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputText = initialQuery
                state.query = initialQuery

                if isResearchMode {
                    // Start in research mode immediately
                    startProcessing(query: initialQuery, forcedRoute: .webResearch)
                } else {
                    // Auto-detect mode based on query content
                    startProcessing(query: initialQuery, forcedRoute: nil)
                }
            }
        }
    }

    private func syncCapturingState() {
        // Only show capturing while idle (typing should not override a running request)
        guard state.uiState == .idle || state.uiState == .capturing else { return }
        state.uiState = (isInputFocused || !inputText.isEmpty) ? .capturing : .idle
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status indicator
            AIStatusBar(state: state)

            // Mode selector pills
            modeSelectorView

            // Context chips (connected atoms)
            if !state.contextSources.isEmpty {
                contextChipsView
            }

            // Query Input or Current Query
            if state.uiState == .idle || state.uiState == .capturing {
                PremiumIdleInputView(
                    inputText: $inputText,
                    isInputFocused: _isInputFocused,
                    accentColor: state.mode.color,
                    inkColor: state.route.ink,
                    onSubmit: startProcessing
                )
            } else {
                // Show current query with improved contrast
                if let query = state.query {
                    QueryDisplayView(query: query, accentColor: state.mode.color)
                }
            }

            // Processing State or Results
            if state.isProcessing {
                switch state.mode {
                case .research:
                    PremiumProcessingView(state: state, isExpanded: isExpanded)
                default:
                    // Generic thinking view for Think/Recall/Act
                    if let thought = state.currentThought {
                        PremiumThinkingStreamView(text: thought, color: state.mode.color)
                    }
                }
            } else if state.uiState == .responding {
                // Mode-specific results
                switch state.mode {
                case .recall:
                    if !state.recallResults.isEmpty {
                        recallResultsView
                    } else {
                        PremiumResultsView(
                            state: state,
                            isExpanded: isExpanded,
                            blockId: block.id,
                            blockPosition: block.position,
                            onReset: resetBlock,
                            onCopy: copyResult
                        )
                    }
                case .act:
                    actResultsView
                default:
                    PremiumResultsView(
                        state: state,
                        isExpanded: isExpanded,
                        blockId: block.id,
                        blockPosition: block.position,
                        onReset: resetBlock,
                        onCopy: copyResult
                    )
                }
            } else if state.uiState == .failed {
                AIErrorView(error: state.error, onRetry: resetBlock)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Mode Selector

    private var modeSelectorView: some View {
        HStack(spacing: 8) {
            ForEach(CosmoMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        state.mode = mode
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .fixedSize()
                    .foregroundColor(state.mode == mode ? .white : mode.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(state.mode == mode ? mode.color : mode.color.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Context Chips

    private var contextChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.contextSources) { source in
                    HStack(spacing: 4) {
                        Image(systemName: source.type.icon)
                            .font(.system(size: 9))
                        Text(source.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Recall Results View

    @ViewBuilder
    private var recallResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Knowledge")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.recallResults) { result in
                        RecallResultCard(result: result, onTap: {
                            let atomType = result.atom.type
                            let entityType = EntityType(rawValue: atomType.rawValue) ?? .idea
                            NotificationCenter.default.post(
                                name: .enterFocusMode,
                                object: nil,
                                userInfo: ["type": entityType, "id": result.atom.id ?? 0]
                            )
                        })
                    }
                }
            }
            .frame(maxHeight: isExpanded ? 300 : 180)

            // Summary text
            if let resultText = state.result {
                Text(resultText)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }

            // Action pills
            HStack(spacing: 10) {
                PremiumAgentActionButton(
                    label: "Copy",
                    icon: "doc.on.doc",
                    color: CosmoColors.textSecondary,
                    action: copyResult
                )
                Spacer()
                PremiumAgentActionButton(
                    label: "New Query",
                    icon: "arrow.counterclockwise",
                    color: CosmoColors.textTertiary,
                    action: resetBlock
                )
            }
        }
    }

    // MARK: - Act Results View

    @ViewBuilder
    private var actResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Action results cards
            if !state.actionResults.isEmpty {
                ForEach(state.actionResults) { actionResult in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CosmoColors.emerald.opacity(0.16))
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(CosmoColors.emerald)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(actionResult.description)
                                .font(CosmoTypography.bodySmall)
                                .foregroundColor(CosmoColors.textPrimary)
                            if let type = actionResult.createdAtomType {
                                Text(type.rawValue.uppercased())
                                    .font(CosmoTypography.labelSmall)
                                    .foregroundColor(CosmoColors.emerald.opacity(0.8))
                            }
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(CosmoColors.emerald.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CosmoColors.emerald.opacity(0.16), lineWidth: 1))
                }
            }

            // Fallback to text result
            if let resultText = state.result, state.actionResults.isEmpty {
                ResultSummaryCard(
                    text: resultText,
                    accentColor: CosmoColors.emerald,
                    isExpanded: isExpanded
                )
            }

            // Action pills
            HStack(spacing: 10) {
                PremiumAgentActionButton(
                    label: "Copy",
                    icon: "doc.on.doc",
                    color: CosmoColors.textSecondary,
                    action: copyResult
                )
                Spacer()
                PremiumAgentActionButton(
                    label: "New Query",
                    icon: "arrow.counterclockwise",
                    color: CosmoColors.textTertiary,
                    action: resetBlock
                )
            }
        }
    }

    // MARK: - Actions
    private func closeBlock() {
        NotificationCenter.default.post(
            name: .removeBlock,
            object: nil,
            userInfo: ["blockId": block.id]
        )
    }

    private func startProcessing() {
        startProcessing(query: nil, forcedRoute: nil)
    }

    private func startProcessing(query: String?, forcedRoute: AgentRoute?) {
        let q = (query ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // Infer mode from query
        let inferredMode = CosmoMode.infer(from: q)
        state.mode = inferredMode
        state.query = q

        // Map mode to existing route for backward compatibility
        let route: AgentRoute
        switch inferredMode {
        case .research: route = .webResearch
        default: route = .localAI
        }
        state.beginRequest(query: q, route: forcedRoute ?? route)

        inputText = ""
        isInputFocused = false

        switch inferredMode {
        case .think: performThink(query: q)
        case .research: performResearch(query: q)
        case .recall: performRecall(query: q)
        case .act: performAct(query: q)
        }
    }

    // MARK: - Think Mode

    private func performThink(query: String) {
        state.setThought("Thinking about this...")

        Task {
            do {
                // Build context prefix from connected atoms
                var contextText = ""
                for source in state.contextSources {
                    contextText += "[\(source.type.rawValue.uppercased()): \(source.title)]\n\(source.bodyPreview)\n\n"
                }

                let fullQuery: String
                if contextText.isEmpty {
                    fullQuery = "Think step by step about: \(query). Provide a clear, thoughtful analysis."
                } else {
                    fullQuery = "Think step by step about: \(query). Provide a clear, thoughtful analysis.\n\nContext from connected knowledge:\n\(contextText)"
                }

                let result = try await ResearchService.shared.performResearch(
                    query: fullQuery,
                    searchType: .web,
                    maxResults: 3
                )

                await MainActor.run {
                    state.result = result.summary
                    state.sources = result.findings
                    state.finishSuccess()
                }
            } catch {
                await MainActor.run {
                    state.finishFailure(error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Research Mode

    private func performResearch(query: String) {
        // Stage 1: Searching
        state.researchStage = .searching
        state.setThought("Finding real statistics and sources")

        Task {
            do {
                // Searching phase
                try await Task.sleep(for: .milliseconds(800))

                // Stage 2: Analyzing
                await MainActor.run {
                    state.researchStage = .analyzing
                    state.setThought("Extracting relevant findings")
                }

                let result = try await ResearchService.shared.performResearch(
                    query: query,
                    searchType: .web,
                    maxResults: 5
                )

                // Stage 3: Organizing
                await MainActor.run {
                    state.researchStage = .organizing
                    state.setThought("Structuring by narrative angle")
                    state.sources = result.findings
                }

                try await Task.sleep(for: .milliseconds(500))

                // Complete
                await MainActor.run {
                    state.researchStage = .complete
                    state.result = result.summary
                    state.finishSuccess()
                }
            } catch {
                await MainActor.run {
                    state.finishFailure(error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Recall Mode

    private func performRecall(query: String) {
        state.setThought("Searching knowledge base...")

        Task {
            do {
                // Vector search
                let vectorResults = try await VectorDatabase.shared.search(
                    query: query, limit: 10, minSimilarity: 0.3
                )

                // Keyword search
                let keywordResults = try await AtomRepository.shared.search(query: query, limit: 10)

                // Merge and deduplicate
                var seen = Set<String>()
                var results: [RecallResult] = []

                for vr in vectorResults {
                    let uuid = vr.entityUUID ?? "\(vr.entityId)"
                    if !seen.contains(uuid) {
                        seen.insert(uuid)
                        if let entityUUID = vr.entityUUID,
                           let atom = try await AtomRepository.shared.fetch(uuid: entityUUID) {
                            results.append(RecallResult(atom: atom, similarity: vr.similarity, source: "vector"))
                        } else if let atom = try await AtomRepository.shared.fetch(id: vr.entityId) {
                            results.append(RecallResult(atom: atom, similarity: vr.similarity, source: "vector"))
                        }
                    }
                }

                for atom in keywordResults {
                    if !seen.contains(atom.uuid) {
                        seen.insert(atom.uuid)
                        results.append(RecallResult(atom: atom, similarity: nil, source: "keyword"))
                    }
                }

                await MainActor.run {
                    state.recallResults = results
                    state.result = "Found \(results.count) related items"
                    state.finishSuccess()
                }
            } catch {
                await MainActor.run {
                    state.finishFailure(error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Act Mode

    private func performAct(query: String) {
        state.setThought("Processing action...")
        let q = query.lowercased()

        Task {
            do {
                if q.contains("create a note") || q.contains("make a note") {
                    let content = extractContent(from: query, removing: ["create a note about", "make a note about"])
                    let atom = try await AtomRepository.shared.create(type: .idea, title: content, body: content)

                    // Spawn block on canvas
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: CosmoNotification.Canvas.createEntityAtPosition,
                            object: nil,
                            userInfo: [
                                "type": EntityType.note,
                                "position": CGPoint(x: block.position.x + 360, y: block.position.y),
                                "entityId": atom.id ?? 0
                            ]
                        )
                        state.actionResults = [ActionResult(description: "Created note: \(content)", createdAtomId: atom.id, createdAtomType: .note)]
                        state.result = "Created note: \(content)"
                        state.finishSuccess()
                    }
                } else if q.contains("should i work on") || q.contains("what should i") {
                    let (primary, alternatives) = try await TaskRecommendationEngine.shared.getRecommendations(
                        currentEnergy: 50,
                        currentFocus: 50,
                        limit: 5
                    )

                    var recommendationText = ""
                    if let primary = primary {
                        recommendationText = "Top recommendation: \(primary.task.title)\n"
                        recommendationText += "Reason: \(primary.reason.displayMessage)\n"
                    }

                    if !alternatives.isEmpty {
                        recommendationText += "\nAlternatives:\n"
                        for alt in alternatives {
                            recommendationText += "- \(alt.task.title)\n"
                        }
                    }

                    if recommendationText.isEmpty {
                        recommendationText = "No tasks found. Create some tasks first to get recommendations."
                    }

                    await MainActor.run {
                        state.result = recommendationText
                        state.finishSuccess()
                    }
                } else if q.contains("analyze") || q.contains("writing") {
                    await MainActor.run {
                        state.result = "Action completed: Analyzed your request. Use specific commands like 'create a note about X' or 'what should I work on?' for targeted actions."
                        state.finishSuccess()
                    }
                } else {
                    await MainActor.run {
                        state.result = "Available actions:\n- Create a note about [topic]\n- What should I work on?\n- Summarize my research on [topic]\n- Analyze my writing in [content]"
                        state.finishSuccess()
                    }
                }
            } catch {
                await MainActor.run {
                    state.finishFailure(error: error.localizedDescription)
                }
            }
        }
    }

    private func extractContent(from query: String, removing prefixes: [String]) -> String {
        var result = query
        for prefix in prefixes {
            if result.lowercased().hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result.isEmpty ? query : result
    }

    private func copyResult() {
        if let result = state.result {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
        }
    }

    private func resetBlock() {
        withAnimation(.spring(response: 0.3)) {
            state.reset()
            state.query = nil
            state.result = nil
            state.sources = []
            state.currentThought = nil
            state.error = nil
            state.researchStage = .searching
            state.recallResults = []
            state.actionResults = []
        }
    }
}

// MARK: - Recall Result Card

private struct RecallResultCard: View {
    let result: RecallResult
    let onTap: () -> Void

    @State private var isHovered = false

    private var typeColor: Color {
        switch result.atom.type {
        case .idea: return CosmoMentionColors.idea
        case .research: return CosmoMentionColors.research
        case .task: return CosmoMentionColors.task
        case .content: return CosmoMentionColors.content
        case .connection: return CosmoColors.lavender
        case .project: return CosmoColors.emerald
        default: return CosmoColors.textSecondary
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Type indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(typeColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconForType(result.atom.type))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(typeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.atom.title ?? result.atom.body?.prefix(60).description ?? "Untitled")
                        .font(CosmoTypography.bodySmall.weight(.medium))
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(result.atom.type.rawValue.capitalized)
                            .font(CosmoTypography.labelSmall)
                            .foregroundColor(typeColor)

                        if let similarity = result.similarity {
                            Text("\(Int(similarity * 100))% match")
                                .font(CosmoTypography.labelSmall)
                                .foregroundColor(CosmoColors.textTertiary)
                        }

                        Text(result.source)
                            .font(CosmoTypography.labelSmall)
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CosmoColors.textTertiary.opacity(0.6))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(typeColor.opacity(isHovered ? 0.26 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .research: return "magnifyingglass"
        case .task: return "checkmark.circle.fill"
        case .content: return "doc.text.fill"
        case .connection: return "person.2.fill"
        case .project: return "folder.fill"
        case .note: return "note.text"
        default: return "doc.fill"
        }
    }
}

// MARK: - AI Status Bar

struct AIStatusBar: View {
    @ObservedObject var state: CosmoAIBlockState

    var body: some View {
        HStack(spacing: 8) {
            // Animated status indicator
            ZStack {
                Circle()
                    .fill(state.mode.color.opacity(0.18))
                    .frame(width: 8, height: 8)

                if state.isProcessing {
                    Circle()
                        .fill(state.mode.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(state.isProcessing ? 1.5 : 1.0)
                        .opacity(state.isProcessing ? 0 : 1)
                        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: state.isProcessing)
                }

                Circle()
                    .fill(state.mode.color)
                    .frame(width: 6, height: 6)
            }

            Text(state.statusText)
                .font(CosmoTypography.caption)
                .foregroundColor(state.statusInkColor) // High-contrast ink color

            Spacer()

            // Mode pill with improved visibility
            PremiumModeIndicatorPill(route: state.route, uiState: state.uiState)
        }
    }
}

// MARK: - Query Display View

struct QueryDisplayView: View {
    let query: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10))
                .foregroundColor(accentColor.opacity(0.8))

            Text(query)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textPrimary) // Improved from textSecondary
                .lineLimit(2)

            Spacer()
        }
        .padding(10)
        .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Premium Idle Input View

struct PremiumIdleInputView: View {
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    let accentColor: Color
    let inkColor: Color
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header: Brain icon + COSMO AI title
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CosmoColors.lavender.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(CosmoColors.lavender)
                }

                Text("COSMO AI")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(CosmoColors.textPrimary)

                Spacer()
            }

            // Input field - always visible
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    if inputText.isEmpty {
                        Text("Ask anything...")
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textTertiary)
                    }

                    TextField("", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textPrimary)
                        .focused($isInputFocused)
                        .onSubmit(onSubmit)
                }
                if !inputText.isEmpty {
                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(CosmoColors.lavender)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(CosmoColors.thinkspaceSecondary))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isInputFocused ? CosmoColors.lavender.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))

            Spacer(minLength: 0)

            // Voice / Keyboard buttons
            HStack(spacing: 16) {
                Spacer()

                // Voice button
                Button(action: { }) {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "mic.fill").font(.system(size: 18)).foregroundColor(CosmoColors.textSecondary))
                }
                .buttonStyle(.plain)

                // Keyboard button - focuses input
                Button(action: {
                    isInputFocused = true
                }) {
                    ZStack {
                        Circle().fill(CosmoColors.lavender.opacity(0.15)).frame(width: 48, height: 48)
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 1).frame(width: 48, height: 48)
                        Image(systemName: "keyboard").font(.system(size: 16)).foregroundColor(CosmoColors.lavender)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}


private struct AgentCoreOrb: View {
    let accentColor: Color
    let inkColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(accentColor.opacity(0.18))
                .blur(radius: 10)
                .scaleEffect(1.3)

            // Orb body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            accentColor.opacity(0.22),
                            Color.white.opacity(0.15)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 26
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.16), radius: 10, y: 3)
                .scaleEffect(pulse)

            // Orbiting arcs
            Circle()
                .trim(from: 0.10, to: 0.32)
                .stroke(accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .padding(2)

            Circle()
                .trim(from: 0.62, to: 0.78)
                .stroke(CosmoColors.skyBlue.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-rotation * 0.75))
                .padding(6)

            // Center mark
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(inkColor.opacity(0.9))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = 1.05 }
        }
    }
}

private struct AgentSuggestionChip: View {
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CosmoTypography.caption)
                    .foregroundColor(color.opacity(0.95))
                Text(subtitle)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(isHovered ? 0.14 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isHovered ? 0.35 : 0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Research Pipeline View

struct PremiumProcessingView: View {
    @ObservedObject var state: CosmoAIBlockState
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pipeline header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(state.mode.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: state.mode.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(state.mode.color)
                }
                Text("Researching...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(CosmoColors.textPrimary)
                Spacer()
                Text(state.researchStage.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(state.mode.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(state.mode.color.opacity(0.12), in: Capsule())
            }

            // Pipeline stages
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ResearchStage.allCases.filter { $0 != .complete }, id: \.rawValue) { stage in
                    ResearchPipelineStep(
                        icon: stage.icon,
                        title: stage.rawValue,
                        subtitle: stage.subtitle,
                        isActive: state.researchStage == stage,
                        isCompleted: isStageCompleted(stage),
                        accentColor: state.mode.color
                    )
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(CosmoColors.thinkspaceSecondary))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Source info
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundColor(state.mode.color)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(state.mode.color)
                Text("Real-time web search via Perplexity")
                    .font(.system(size: 11))
                    .foregroundColor(CosmoColors.textTertiary)
            }

            // Query display
            if let query = state.query {
                Text(query)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(state.mode.color.opacity(0.08)))
            }

            // Waveform animation
            WaveformAnimation(color: state.mode.color)
                .frame(height: 40)

            // Status text
            Text("RESEARCHING...")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(state.mode.color)
                .tracking(1.5)
                .frame(maxWidth: .infinity)
        }
    }

    private func isStageCompleted(_ stage: ResearchStage) -> Bool {
        let stages: [ResearchStage] = [.searching, .analyzing, .organizing, .complete]
        guard let currentIndex = stages.firstIndex(of: state.researchStage),
              let stageIndex = stages.firstIndex(of: stage) else { return false }
        return stageIndex < currentIndex
    }
}

// MARK: - Research Pipeline Step

private struct ResearchPipelineStep: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    var isCompleted: Bool = false
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                } else if isCompleted {
                    Circle()
                        .fill(CosmoColors.emerald.opacity(0.15))
                        .frame(width: 32, height: 32)
                }
                Image(systemName: isCompleted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: isActive ? 15 : 14, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isCompleted ? CosmoColors.emerald : (isActive ? accentColor : CosmoColors.textTertiary))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isCompleted ? CosmoColors.emerald : (isActive ? accentColor : CosmoColors.textSecondary))
                if !isCompleted {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? accentColor.opacity(0.8) : CosmoColors.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .background(isActive ? accentColor.opacity(0.06) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Waveform Animation

private struct WaveformAnimation: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: animating ? CGFloat.random(in: 8...28) : 8)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Premium Thinking Stream View

struct PremiumThinkingStreamView: View {
    let text: String
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedText = ""
    @State private var dotCount = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            // Animated thinking dots with better visibility
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color.opacity(i < dotCount ? 1.0 : 0.4))
                        .frame(width: 5, height: 5)
                }
            }

            Text(displayedText)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textPrimary) // Improved contrast
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if reduceMotion {
                displayedText = text
                dotCount = 3
            } else {
                animateText()
                animateDots()
            }
        }
        .onChange(of: text) { _, _ in
            if reduceMotion {
                displayedText = text
            } else {
                animateText()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func animateText() {
        displayedText = ""
        for (index, char) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) {
                displayedText += String(char)
            }
        }
    }

    private func animateDots() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

// MARK: - Premium Agent Processing Animation

struct PremiumAgentProcessingAnimation: View {
    let route: AgentRoute
    let uiState: AgentUIState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var innerRotation: Double = 0

    var body: some View {
        let color = route.color
        let icon = route.icon

        ZStack {
            // Outer glow ring
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 8)
                .frame(width: 60, height: 60)
                .blur(radius: 4)

            // Outer ring
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2)
                .frame(width: 56, height: 56)

            // Primary animated arc
            Circle()
                .trim(from: 0, to: 0.35)
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(rotation))

            // Secondary arc (opposite direction)
            Circle()
                .trim(from: 0, to: 0.2)
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-innerRotation))

            // Inner pulse
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.2), color.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 40, height: 40)
                .scaleEffect(scale)

            // Center icon
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(color)
                .symbolEffect(.pulse.byLayer, isActive: true)
        }
        .onAppear {
            guard !reduceMotion else { return }
            // Keep it calm; "still thinking" slows slightly.
            let speedMultiplier: Double = (uiState == .stillThinking) ? 1.35 : 1.0
            withAnimation(.linear(duration: 1.5 * speedMultiplier).repeatForever(autoreverses: false)) { rotation = 360 }
            withAnimation(.linear(duration: 2.0 * speedMultiplier).repeatForever(autoreverses: false)) { innerRotation = 360 }
            withAnimation(.easeInOut(duration: 1.0 * speedMultiplier).repeatForever(autoreverses: true)) { scale = 1.2 }
        }
    }
}

// MARK: - Premium Source Pills View

struct PremiumSourcePillsView: View {
    let sources: [ResearchFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sources.prefix(5).enumerated()), id: \.offset) { index, source in
                        PremiumSourcePill(source: source, delay: Double(index) * 0.1)
                    }
                }
            }
        }
    }
}

// MARK: - Premium Source Pill

struct PremiumSourcePill: View {
    let source: ResearchFinding
    let delay: Double

    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 10))
            Text(source.source)
                .font(CosmoTypography.caption)
                .lineLimit(1)
        }
        .foregroundColor(CosmoMentionColors.research)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(CosmoMentionColors.research.opacity(isHovered ? 0.18 : 0.12))
        )
        .overlay(
            Capsule()
                .stroke(CosmoMentionColors.research.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Premium Results View

struct PremiumResultsView: View {
    @ObservedObject var state: CosmoAIBlockState
    let isExpanded: Bool
    let blockId: String
    let blockPosition: CGPoint
    let onReset: () -> Void
    let onCopy: () -> Void

    var body: some View {
        let artifact = AgentArtifact.from(state: state)

        VStack(alignment: .leading, spacing: 12) {
            if let artifact {
                ArtifactStackView(
                    artifact: artifact,
                    accentColor: state.routeColor,
                    isExpanded: isExpanded,
                    blockId: blockId,
                    blockPosition: blockPosition
                )
            } else {
                ResultSummaryCard(
                    text: state.result ?? "",
                    accentColor: state.routeColor,
                    isExpanded: isExpanded
                )
            }

            if !state.sources.isEmpty {
                SourcesSection(
                    sources: state.sources,
                    accentColor: state.routeColor,
                    isExpanded: isExpanded
                )
            }

            // Action pills
            HStack(spacing: 10) {
                PremiumAgentActionButton(
                    label: "Copy",
                    icon: "doc.on.doc",
                    color: CosmoColors.textSecondary,
                    action: onCopy
                )
                Spacer()
                PremiumAgentActionButton(
                    label: "New Query",
                    icon: "arrow.counterclockwise",
                    color: CosmoColors.textTertiary,
                    action: onReset
                )
            }
        }
    }
}

// MARK: - Artifact Stack View (First-Class OS Object)

private struct ArtifactStackView: View {
    let artifact: AgentArtifact
    let accentColor: Color
    let isExpanded: Bool
    let blockId: String
    let blockPosition: CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFullBody = false

    private var kindColor: Color {
        switch artifact.kind {
        case .idea: return CosmoMentionColors.idea
        case .research: return CosmoMentionColors.research
        case .task: return CosmoMentionColors.task
        case .content: return CosmoMentionColors.content
        }
    }

    private var kindIcon: String {
        switch artifact.kind {
        case .idea: return "lightbulb.fill"
        case .research: return "magnifyingglass"
        case .task: return "checkmark.circle.fill"
        case .content: return "doc.text.fill"
        }
    }

    private var kindLabel: String {
        artifact.kind.rawValue.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with kind badge and title
            HStack(alignment: .top, spacing: 10) {
                // Kind badge orb
                ZStack {
                    Circle()
                        .fill(kindColor.opacity(0.18))
                        .frame(width: 32, height: 32)

                    Image(systemName: kindIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(kindColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Kind pill
                    HStack(spacing: 6) {
                        Text(kindLabel)
                            .font(CosmoTypography.labelSmall)
                            .foregroundColor(kindColor.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(kindColor.opacity(0.12), in: Capsule())

                        Spacer()

                        ConfidencePill(label: "READY", color: CosmoColors.emerald)
                    }

                    // Title
                    Text(artifact.title)
                        .font(CosmoTypography.titleSmall)
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(2)
                }
            }

            // Summary bullets (key takeaways)
            if !artifact.summaryBullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(artifact.summaryBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(kindColor.opacity(0.6))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            Text(bullet)
                                .font(CosmoTypography.bodySmall)
                                .foregroundColor(CosmoColors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Expandable body
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    if reduceMotion {
                        showFullBody.toggle()
                    } else {
                        withAnimation(.spring(response: 0.25)) { showFullBody.toggle() }
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(showFullBody ? "Hide details" : "Show full response")
                            .font(CosmoTypography.caption)
                            .foregroundColor(accentColor.opacity(0.85))

                        Image(systemName: showFullBody ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(accentColor.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)

                if showFullBody {
                    ScrollView {
                        Text(artifact.body)
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineSpacing(CosmoTypography.bodyLineSpacing)
                    }
                    .frame(maxHeight: isExpanded ? 200 : 120)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }

            // Place on Canvas action
            ArtifactPlaceButton(
                artifact: artifact,
                kindColor: kindColor,
                blockId: blockId,
                blockPosition: blockPosition
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(kindColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: kindColor.opacity(0.12), radius: 16, y: 6)
    }
}

// MARK: - Artifact Place Button

private struct ArtifactPlaceButton: View {
    let artifact: AgentArtifact
    let kindColor: Color
    let blockId: String
    let blockPosition: CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var entityType: EntityType {
        switch artifact.kind {
        case .idea: return .idea
        case .research: return .research
        case .task: return .task
        case .content: return .content
        }
    }

    private var buttonLabel: String {
        switch artifact.kind {
        case .idea: return "Save as Idea"
        case .research: return "Save as Research"
        case .task: return "Create Task"
        case .content: return "Save as Content"
        }
    }

    var body: some View {
        Button(action: placeOnCanvas) {
            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 12, weight: .semibold))

                Text(buttonLabel)
                    .font(CosmoTypography.label)

                Spacer()

                // Keyboard shortcut hint
                Text("\u{2318}\u{21A9}")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [kindColor, kindColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: kindColor.opacity(isHovered ? 0.35 : 0.25), radius: isHovered ? 12 : 8, y: 4)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1.0 : (isHovered ? 1.02 : 1.0))
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func placeOnCanvas() {
        // Post notification to create entity to the right of this block
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createEntityAtPosition,
            object: nil,
            userInfo: [
                "type": entityType,
                "position": CGPoint(x: blockPosition.x + 360, y: blockPosition.y),
                "content": artifact.body,
                "title": artifact.title,
                "anchorBlockId": blockId,
                "placement": "right",
                "spacing": CGFloat(360)
            ]
        )
    }
}

private struct ResultSummaryCard: View {
    let text: String
    let accentColor: Color
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(CosmoColors.emerald.opacity(0.16))
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(CosmoColors.emerald)
                }

                Text("Response")
                    .font(CosmoTypography.label)
                    .foregroundColor(CosmoColors.textPrimary)

                Spacer()

                ConfidencePill(label: "COMPOSED", color: accentColor)
            }

            ScrollView {
                Text(text)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(CosmoTypography.bodyLineSpacing)
                    .padding(.bottom, 2)
            }
            .frame(maxHeight: isExpanded ? 220 : 120)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.10), radius: 16, y: 6)
    }
}

private struct SourcesSection: View {
    let sources: [ResearchFinding]
    let accentColor: Color
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CosmoColors.textSecondary)
                Text("Sources")
                    .font(CosmoTypography.label)
                    .foregroundColor(CosmoColors.textPrimary)
                Spacer()
                Text("\(min(sources.count, 5))")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }

            VStack(spacing: 8) {
                ForEach(Array(sources.prefix(isExpanded ? 5 : 3).enumerated()), id: \.offset) { index, source in
                    SourceCard(finding: source, accentColor: accentColor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(BlockAnimations.staggered(index: index), value: isExpanded)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct SourceCard: View {
    let finding: ResearchFinding
    let accentColor: Color

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                FaviconView(urlString: finding.url, fallbackColor: accentColor)
                    .frame(width: 22, height: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(finding.source)
                            .font(CosmoTypography.caption)
                            .foregroundColor(CosmoColors.textTertiary)
                            .lineLimit(1)

                        Spacer()

                        ConfidencePill(label: finding.confidence.uppercased(), color: confidenceColor)
                    }

                    Text(finding.title)
                        .font(CosmoTypography.bodySmall.weight(.semibold))
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let snippet = finding.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(CosmoTypography.bodySmall)
                            .foregroundColor(CosmoColors.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CosmoColors.textTertiary.opacity(isHovered ? 0.9 : 0.55))
                    .padding(.top, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor.opacity(isHovered ? 0.26 : 0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovered)
        .onHover { isHovered = $0 }
        .disabled(finding.url == nil)
    }

    private var confidenceColor: Color {
        switch finding.confidence.lowercased() {
        case "high": return CosmoColors.emerald
        case "low": return CosmoColors.softRed
        default: return accentColor
        }
    }

    private func open() {
        guard let urlString = finding.url, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ConfidencePill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(CosmoTypography.labelSmall)
            .foregroundColor(color.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.20), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
            .fixedSize()
    }
}

private struct FaviconView: View {
    let urlString: String?
    let fallbackColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(fallbackColor.opacity(0.22))

            if let faviconURL = faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(3)
                    default:
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(fallbackColor.opacity(0.75))
                    }
                }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(fallbackColor.opacity(0.75))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var faviconURL: URL? {
        guard let urlString, let url = URL(string: urlString), let host = url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}

// MARK: - AI Error View

struct AIErrorView: View {
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(CosmoColors.softRed)

            Text(error ?? "Something went wrong")
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textPrimary) // Improved contrast
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Try Again")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(CosmoColors.softRed, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Premium Agent Action Button

struct PremiumAgentActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(isHovered ? color : color.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(isHovered ? 0.18 : 0.1), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Premium Mode Indicator Pill

struct PremiumModeIndicatorPill: View {
    let route: AgentRoute
    let uiState: AgentUIState

    private var label: String {
        switch uiState {
        case .idle: return route.label
        case .capturing: return "CAPTURING"
        case .thinking: return route == .webResearch ? "SEARCHING" : "THINKING"
        case .stillThinking: return "STILL THINKING"
        case .responding: return "DONE"
        case .failed: return "FAILED"
        }
    }

    private var color: Color {
        switch uiState {
        case .responding: return CosmoColors.emerald
        case .failed: return CosmoColors.softRed
        default: return route.color
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(CosmoTypography.labelSmall)
                .foregroundColor(color.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct StillThinkingCallout: View {
    let route: AgentRoute

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            Text("Still thinking\u{2026} this is taking longer than usual.")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(route.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(route.color.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Agent State Model (explicit enum, reliability-aware)

enum AgentRoute: Equatable {
    case localAI
    case webResearch

    static func infer(from query: String) -> AgentRoute {
        let lowered = query.lowercased()
        if lowered.contains("research") || lowered.contains("find") ||
            lowered.contains("search") || lowered.contains("look up") ||
            lowered.contains("sources") || lowered.contains("citations") {
            return .webResearch
        }
        return .localAI
    }

    var label: String {
        switch self {
        case .localAI: return "AI"
        case .webResearch: return "WEB"
        }
    }

    var icon: String {
        switch self {
        case .localAI: return "brain"
        case .webResearch: return "globe"
        }
    }

    /// Pastel accent for surfaces and glows (NOT for primary text).
    var color: Color {
        switch self {
        case .localAI: return CosmoColors.lavender
        case .webResearch: return CosmoColors.skyBlue
        }
    }

    /// High-contrast ink color for labels/icons on light surfaces.
    var ink: Color {
        switch self {
        case .localAI: return CosmoMentionColors.cosmoAI
        case .webResearch: return CosmoMentionColors.content
        }
    }
}

enum AgentUIState: Equatable {
    case idle
    case capturing
    case thinking
    case stillThinking
    case responding
    case failed
}

// MARK: - Research Stage

enum ResearchStage: String, CaseIterable {
    case searching = "Searching web"
    case analyzing = "Analyzing sources"
    case organizing = "Organizing findings"
    case complete = "Complete"

    var subtitle: String {
        switch self {
        case .searching: return "Finding real statistics and sources"
        case .analyzing: return "Extracting relevant findings"
        case .organizing: return "Structuring by narrative angle"
        case .complete: return "Ready to review"
        }
    }

    var icon: String {
        switch self {
        case .searching: return "globe"
        case .analyzing: return "magnifyingglass"
        case .organizing: return "sparkles"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

@MainActor
final class CosmoAIBlockState: ObservableObject {
    @Published var uiState: AgentUIState = .idle
    @Published var route: AgentRoute = .localAI
    @Published var query: String?
    @Published var result: String?
    @Published var sources: [ResearchFinding] = []
    @Published var currentThought: String?
    @Published var error: String?
    @Published var researchStage: ResearchStage = .searching
    @Published var mode: CosmoMode = .think
    @Published var recallResults: [RecallResult] = []
    @Published var actionResults: [ActionResult] = []
    @Published var connectedAtomUUIDs: [String] = []
    @Published var contextSources: [ContextSource] = []

    private var stillThinkingTask: Task<Void, Never>?

    var isProcessing: Bool {
        uiState == .thinking || uiState == .stillThinking
    }

    // MARK: - Visuals

    /// Accent used by the outer chrome (border/glow).
    var chromeAccentColor: Color {
        switch uiState {
        case .responding: return CosmoColors.emerald
        case .failed: return CosmoColors.softRed
        default: return mode.color
        }
    }

    /// Icon used by the block chrome.
    var chromeIcon: String {
        switch uiState {
        case .responding: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return mode.icon
        }
    }

    /// Pastel accent for inner surfaces.
    var routeColor: Color { mode.color }

    /// High-contrast ink color for status labels.
    var statusInkColor: Color {
        switch uiState {
        case .responding: return CosmoMentionColors.research
        case .failed: return CosmoColors.softRed
        default: return route.ink
        }
    }

    var statusText: String {
        switch uiState {
        case .idle: return "Ready"
        case .capturing: return "Capturing\u{2026}"
        case .thinking:
            switch mode {
            case .think: return "Thinking\u{2026}"
            case .research: return "Searching\u{2026}"
            case .recall: return "Recalling\u{2026}"
            case .act: return "Acting\u{2026}"
            }
        case .stillThinking: return "Still thinking\u{2026}"
        case .responding: return "Done"
        case .failed: return "Failed"
        }
    }

    // MARK: - Lifecycle

    func beginRequest(query: String, route: AgentRoute) {
        stillThinkingTask?.cancel()

        self.route = route
        self.query = query
        self.result = nil
        self.sources = []
        self.error = nil
        self.currentThought = nil
        self.recallResults = []
        self.actionResults = []
        self.uiState = .thinking

        scheduleStillThinkingFlip()
    }

    func setThought(_ text: String?) {
        currentThought = text
    }

    func finishSuccess() {
        stillThinkingTask?.cancel()
        uiState = .responding
        currentThought = nil
        error = nil
    }

    func finishFailure(error: String) {
        stillThinkingTask?.cancel()
        self.error = error
        uiState = .failed
        currentThought = nil
    }

    func reset() {
        stillThinkingTask?.cancel()
        uiState = .idle
        route = .localAI
        mode = .think
    }

    private func scheduleStillThinkingFlip() {
        stillThinkingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.uiState == .thinking {
                    self.uiState = .stillThinking
                }
            }
        }
    }

    // MARK: - Connected Context Loading

    /// Load connected atoms from graph edges and direct atom links
    func loadConnectedContext(entityUuid: String) {
        Task {
            do {
                var sources: [ContextSource] = []
                var uuids: [String] = []

                // Check atom's direct links
                if let atom = try await AtomRepository.shared.fetch(uuid: entityUuid) {
                    for link in atom.linksList {
                        if let linkedAtom = try await AtomRepository.shared.fetch(uuid: link.uuid) {
                            let entityType = EntityType(rawValue: linkedAtom.type.rawValue) ?? .idea
                            if !uuids.contains(linkedAtom.uuid) {
                                sources.append(ContextSource(
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
                            sources.append(ContextSource(
                                id: connectedAtom.uuid,
                                title: connectedAtom.title ?? "Untitled",
                                type: entityType,
                                bodyPreview: String((connectedAtom.body ?? "").prefix(300))
                            ))
                            uuids.append(connectedUUID)
                        }
                    }
                }

                await MainActor.run {
                    self.contextSources = sources
                    self.connectedAtomUUIDs = uuids
                }
            } catch {
                print("Failed to load connected context: \(error)")
            }
        }
    }
}

// MARK: - Artifact Model (UI-only for now)
/// A structured "OS object" representation of a Cosmo output.
/// This is intentionally UI-only initially; persistence + canvas placement is handled later.
struct AgentArtifact: Equatable {
    enum Kind: String {
        case idea
        case research
        case task
        case content
    }

    let kind: Kind
    let title: String
    let summaryBullets: [String]
    let body: String
    let sources: [ResearchFinding]

    @MainActor
    static func from(state: CosmoAIBlockState) -> AgentArtifact? {
        guard let raw = state.result?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let kind = inferKind(route: state.route, query: state.query, body: raw)
        let title = inferTitle(kind: kind, query: state.query, body: raw)
        let bullets = inferBullets(body: raw, max: 3)
        let sources = state.sources

        return AgentArtifact(
            kind: kind,
            title: title,
            summaryBullets: bullets,
            body: raw,
            sources: sources
        )
    }

    private static func inferKind(route: AgentRoute, query: String?, body: String) -> Kind {
        // Route dominates: web research produces a Research artifact by default.
        if route == .webResearch { return .research }

        let q = (query ?? "").lowercased()
        let b = body.lowercased()

        // Task-ish
        if b.contains("- [ ]") || b.contains("todo") || b.contains("checklist") ||
            q.contains("task") || q.contains("checklist") || q.contains("todo") || q.contains("plan my day") {
            return .task
        }

        // Content-ish
        if q.contains("write") || q.contains("draft") || q.contains("blog") || q.contains("article") ||
            q.contains("script") || q.contains("newsletter") || b.contains("## ") && b.contains("introduction") {
            return .content
        }

        // Default: idea
        return .idea
    }

    private static func inferTitle(kind: Kind, query: String?, body: String) -> String {
        // Prefer first heading / first strong line.
        if let heading = body.firstNonEmptyLineStrippingMarkdownHeading(), !heading.isEmpty {
            return heading.truncated(64)
        }

        // Fallback: derive from query.
        let q = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            switch kind {
            case .research: return "Research: \(q)".truncated(64)
            case .task: return "Tasks: \(q)".truncated(64)
            case .content: return "Draft: \(q)".truncated(64)
            case .idea: return q.truncated(64)
            }
        }

        return kind.rawValue.capitalized
    }

    private static func inferBullets(body: String, max: Int) -> [String] {
        // Try to extract explicit bullets first.
        let bullets = body.extractMarkdownBullets(max: max)
        if !bullets.isEmpty { return bullets }

        // Otherwise: first sentences.
        let sentences = body.extractSentences(max: max)
        return sentences
    }
}

// MARK: - String parsing helpers
private extension String {
    func truncated(_ max: Int) -> String {
        guard count > max else { return self }
        return String(prefix(max - 1)) + "\u{2026}"
    }

    func firstNonEmptyLineStrippingMarkdownHeading() -> String? {
        for rawLine in split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            // Strip markdown heading markers (#, ##, ###)
            while line.hasPrefix("#") {
                line.removeFirst()
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip leading list markers like "-", "*", "1."
            line = line.replacingOccurrences(of: #"^(\-|\*|\d+\.)\s+"#, with: "", options: .regularExpression)

            // Ignore very short / decorative lines
            if line.count < 3 { continue }
            return line
        }
        return nil
    }

    func extractMarkdownBullets(max: Int) -> [String] {
        var out: [String] = []
        for rawLine in split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("- ") || line.hasPrefix("\u{2022} ") || line.hasPrefix("* ") {
                let cleaned = line.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    out.append(String(cleaned).truncated(120))
                }
            }
            if out.count >= max { break }
        }
        return out
    }

    func extractSentences(max: Int) -> [String] {
        // Lightweight: split on period / newline boundaries.
        let normalized = replacingOccurrences(of: "\n", with: " ")
        let parts = normalized
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(parts.prefix(max)).map { $0.truncated(140) }
    }
}
