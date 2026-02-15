// CosmoOS/UI/FocusMode/Content/ContentBrainstormView.swift
// Step 1 of Content Focus Mode - Core idea + outline + AI Collaborator
// February 2026 — Enhanced with Brainstorm AI Collaborator replacing Related panel

import SwiftUI

struct ContentBrainstormView: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    let onNext: () -> Void

    @State private var newOutlineText = ""
    @State private var isSearching = false
    @State private var searchResults: [HybridSearchEngine.SearchResult] = []
    @State private var contentAppeared = false
    @FocusState private var coreIdeaFocused: Bool

    @StateObject private var aiEngine = BrainstormAIEngine()
    @State private var chatInput = ""
    @FocusState private var chatInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main 2-column layout
            HStack(spacing: 0) {
                // MARK: - Left Column (60%) - Core Idea + Outline
                leftColumn
                    .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // MARK: - Right Column (40%) - AI Collaborator
                aiCollaboratorPanel
                    .frame(width: relatedColumnWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .background(CosmoColors.thinkspaceVoid)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                contentAppeared = true
            }
            loadRelatedAtoms()
            syncAIContext()
        }
        .onChange(of: state.coreIdea) { _, _ in
            syncAIContext()
        }
        .onChange(of: state.outline) { _, _ in
            syncAIContext()
        }
    }

    private var relatedColumnWidth: CGFloat { 380 }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section: Core Idea
                coreIdeaSection

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                // Section: Outline
                outlineSection
            }
            .padding(32)
        }
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 12)
    }

    // MARK: - Core Idea Section

    private var coreIdeaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.blockContent)
                Text("Core Idea")
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(.white)
            }

            Text("What is the central message or thesis?")
                .font(CosmoTypography.bodySmall)
                .foregroundColor(.white.opacity(0.5))

            TextEditor(text: $state.coreIdea)
                .font(CosmoTypography.bodyLarge)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .focused($coreIdeaFocused)
                .frame(minHeight: 100, maxHeight: 160)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CosmoColors.thinkspaceTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    coreIdeaFocused
                                        ? CosmoColors.blockContent.opacity(0.4)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )
                .onChange(of: state.coreIdea) { _, _ in
                    state.lastModified = Date()
                    state.save()
                }
        }
    }

    // MARK: - Outline Section

    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.blockContent)
                Text("Outline")
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(.white)
                Spacer()
                if !state.outline.isEmpty {
                    outlineCountLabel
                }
            }

            Text("Build out the structure of your content")
                .font(CosmoTypography.bodySmall)
                .foregroundColor(.white.opacity(0.5))

            // AI-suggested label
            if state.isAISuggestedOutline && !state.outline.isEmpty {
                aiSuggestedBadge
            }

            // Outline items list
            VStack(spacing: 4) {
                ForEach(state.sortedOutline) { item in
                    ExpandableOutlineItemRow(
                        item: item,
                        onUpdateTitle: { title in
                            state.updateOutlineItem(id: item.id, title: title)
                            state.save()
                        },
                        onUpdateReasoning: { reasoning in
                            state.updateOutlineItemReasoning(id: item.id, reasoning: reasoning)
                            state.save()
                        },
                        onDelete: {
                            withAnimation(ProMotionSprings.snappy) {
                                state.removeOutlineItem(id: item.id)
                                state.save()
                            }
                        }
                    )
                }
                .onMove { source, destination in
                    state.moveOutlineItem(from: source, to: destination)
                    state.save()
                }
            }

            // Add new outline item
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(CosmoColors.blockContent.opacity(0.6))

                TextField("Add outline point...", text: $newOutlineText)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .foregroundColor(.white)
                    .onSubmit {
                        addOutlineItem()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.thinkspaceTertiary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var outlineCountLabel: some View {
        HStack(spacing: 4) {
            Text("\(state.outline.count) items")
                .font(CosmoTypography.caption)
                .foregroundColor(.white.opacity(0.3))
            if totalEstimatedSeconds > 0 {
                Text("~\(formattedDuration(totalEstimatedSeconds))")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.blockContent.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var aiSuggestedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
            Text("AI-suggested outline")
                .font(.system(size: 11, weight: .medium))
            Text("Click to expand details")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .foregroundColor(CosmoColors.blockContent.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(CosmoColors.blockContent.opacity(0.1), in: Capsule())
    }

    private var totalEstimatedSeconds: Int {
        state.outline.compactMap(\.estimatedSeconds).reduce(0, +)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
        return "\(seconds)s"
    }

    // MARK: - AI Collaborator Panel

    private var aiCollaboratorPanel: some View {
        VStack(spacing: 0) {
            // Header
            aiPanelHeader

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Quick-action pills
            quickActionPills

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Messages
            aiMessageList

            // Input
            aiInputBar
        }
        .background(CosmoColors.thinkspaceSecondary.opacity(0.5))
        .opacity(contentAppeared ? 1 : 0)
        .offset(x: contentAppeared ? 0 : 20)
        .animation(ProMotionSprings.cardEntrance.delay(0.1), value: contentAppeared)
    }

    // MARK: - AI Panel Header

    @ViewBuilder
    private var aiPanelHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(CosmoColors.lavender.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: "brain")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.lavender)
            }

            Text("AI Collaborator")
                .font(CosmoTypography.label)
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            if aiEngine.isGenerating {
                ProgressView()
                    .controlSize(.mini)
                    .tint(CosmoColors.lavender)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quick Action Pills

    @ViewBuilder
    private var quickActionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickPill(label: "Suggest an outline", icon: "list.bullet.rectangle") {
                    Task { await aiEngine.suggestOutline() }
                }
                quickPill(label: "Improve my hook", icon: "bolt.fill") {
                    Task { await aiEngine.improveHook() }
                }
                quickPill(label: "Framework breakdown", icon: "rectangle.3.group") {
                    Task { await aiEngine.frameworkBreakdown() }
                }
                quickPill(label: "Hook variants", icon: "sparkles") {
                    Task { await aiEngine.generateHookVariants() }
                }
                quickPill(label: "Top creator structure", icon: "star.fill") {
                    Task { await aiEngine.topCreatorStructure() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func quickPill(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickPillLabel(label: label, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(aiEngine.isGenerating)
    }

    @ViewBuilder
    private func quickPillLabel(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(CosmoColors.lavender.opacity(aiEngine.isGenerating ? 0.4 : 0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(CosmoColors.lavender.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(CosmoColors.lavender.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - AI Message List

    @ViewBuilder
    private var aiMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if aiEngine.messages.isEmpty {
                        aiEmptyState
                    }

                    ForEach(aiEngine.messages) { message in
                        brainstormMessageBubble(message)
                            .id(message.id)
                    }

                    if aiEngine.isGenerating {
                        brainstormTypingIndicator
                    }
                }
                .padding(12)
            }
            .onChange(of: aiEngine.messages.count) { _, _ in
                if let lastId = aiEngine.messages.last?.id {
                    withAnimation(.spring(response: 0.3)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aiEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundColor(CosmoColors.lavender.opacity(0.3))

            Text("Your AI brainstorm partner")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text("Ask me to help structure your outline, refine your core idea, or suggest hooks. Use the pills above for quick actions.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func brainstormMessageBubble(_ message: BrainstormMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            // Role label
            if message.role == .assistant {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 9))
                        .foregroundColor(CosmoColors.lavender)
                    Text("AI")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(CosmoColors.lavender)
                    Text(message.timestamp, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.2))
                }
            }

            // Content bubble
            Text(message.content)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(message.role == .user
                            ? CosmoColors.blockContent.opacity(0.15)
                            : CosmoColors.thinkspaceTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            // Action cards
            if !message.actions.isEmpty {
                actionCardsSection(message)
            }
        }
    }

    // MARK: - Action Cards

    @ViewBuilder
    private func actionCardsSection(_ message: BrainstormMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.actions) { action in
                actionCard(action, messageId: message.id, isApplied: message.isApplied)
            }
        }
    }

    @ViewBuilder
    private func actionCard(_ action: BrainstormAction, messageId: UUID, isApplied: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: actionIcon(action.type))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(actionColor(action.type))

            VStack(alignment: .leading, spacing: 2) {
                Text(action.type.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(actionColor(action.type))

                Text(action.payload)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(3)
            }

            Spacer()

            if isApplied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.emerald)
            } else {
                HStack(spacing: 4) {
                    Button(action: { applyAction(action, messageId: messageId) }) {
                        applyButtonLabel
                    }
                    .buttonStyle(.plain)

                    Button(action: { /* Ignore — no-op */ }) {
                        ignoreButtonLabel
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(actionColor(action.type).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(actionColor(action.type).opacity(0.15), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var applyButtonLabel: some View {
        Text("Apply")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(CosmoColors.lavender)
            )
    }

    @ViewBuilder
    private var ignoreButtonLabel: some View {
        Text("Ignore")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    // MARK: - Typing Indicator

    @ViewBuilder
    private var brainstormTypingIndicator: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(CosmoColors.lavender.opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: "brain")
                    .font(.system(size: 10))
                    .foregroundColor(CosmoColors.lavender)
            }

            BrainstormDotsView()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CosmoColors.thinkspaceTertiary)
                )

            Spacer()
        }
    }

    // MARK: - AI Input Bar

    @ViewBuilder
    private var aiInputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 8) {
                TextField("Ask your AI collaborator...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .focused($chatInputFocused)
                    .onSubmit {
                        sendChatMessage()
                    }

                Button(action: sendChatMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(
                            chatInput.trimmingCharacters(in: .whitespaces).isEmpty || aiEngine.isGenerating
                                ? CosmoColors.lavender.opacity(0.3)
                                : CosmoColors.lavender
                        )
                }
                .buttonStyle(.plain)
                .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || aiEngine.isGenerating)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

    private func addOutlineItem() {
        let trimmed = newOutlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            state.addOutlineItem(trimmed)
            newOutlineText = ""
            state.save()
        }
    }

    private func loadRelatedAtoms() {
        let query = state.coreIdea.isEmpty ? (atom.title ?? "") : state.coreIdea
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSearching = true
        Task {
            do {
                let results = try await HybridSearchEngine.shared.search(
                    query: query,
                    limit: 8,
                    entityTypes: [.idea, .research, .connection, .content]
                )
                await MainActor.run {
                    let filtered = results.filter { $0.entityUUID != atom.uuid }
                    for result in filtered {
                        let ref = RelatedAtomRef(
                            atomUUID: result.entityUUID ?? "",
                            title: result.title,
                            type: AtomType(rawValue: result.entityType.rawValue) ?? .idea,
                            relevanceScore: result.combinedScore,
                            preview: result.preview
                        )
                        state.addRelatedAtom(ref)
                    }
                    state.save()
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }

    private func syncAIContext() {
        let metadata = atom.metadata
        var metaDict: [String: Any] = [:]
        if let metaStr = metadata,
           let data = metaStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metaDict = dict
        }

        let format = metaDict["contentFormat"] as? String ?? atom.contentType ?? ""
        let platform = metaDict["platform"] as? String ?? ""
        let framework = metaDict["recommendedFramework"] as? String ?? ""

        let swipePreviews = state.relatedAtoms
            .filter { $0.type == .research }
            .prefix(3)
            .map { $0.preview }

        aiEngine.updateContext(
            coreIdea: state.coreIdea,
            outline: state.outline,
            title: atom.title ?? "",
            contentFormat: format,
            platform: platform,
            framework: framework,
            swipePreviews: Array(swipePreviews)
        )
    }

    private func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatInput = ""

        Task {
            await aiEngine.sendMessage(text)
        }
    }

    private func applyAction(_ action: BrainstormAction, messageId: UUID) {
        withAnimation(ProMotionSprings.snappy) {
            switch action.type {
            case .addOutlineItem:
                state.addOutlineItem(action.payload)

            case .editOutlineItem:
                if let targetIndex = action.targetIndex,
                   targetIndex >= 0 && targetIndex < state.sortedOutline.count {
                    let item = state.sortedOutline[targetIndex]
                    state.updateOutlineItem(id: item.id, title: action.payload)
                }

            case .reorderOutline:
                let indices = action.payload
                    .components(separatedBy: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .map { $0 - 1 }

                let sorted = state.sortedOutline
                var reordered: [OutlineItem] = []
                for idx in indices {
                    if idx >= 0 && idx < sorted.count {
                        reordered.append(sorted[idx])
                    }
                }
                for item in sorted {
                    if !reordered.contains(where: { $0.id == item.id }) {
                        reordered.append(item)
                    }
                }
                for (i, _) in reordered.enumerated() {
                    if let idx = state.outline.firstIndex(where: { $0.id == reordered[i].id }) {
                        state.outline[idx].sortOrder = i
                    }
                }

            case .replaceOutline:
                let items = action.payload
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                state.outline.removeAll()
                for (i, title) in items.enumerated() {
                    let item = OutlineItem(title: title, sortOrder: i)
                    state.outline.append(item)
                }

            case .refineCoreIdea:
                state.coreIdea = action.payload
            }

            state.lastModified = Date()
            state.save()
            aiEngine.markMessageApplied(messageId)
            syncAIContext()
        }
    }

    // MARK: - Action Helpers

    private func actionIcon(_ type: BrainstormAction.ActionType) -> String {
        switch type {
        case .addOutlineItem: return "plus.circle"
        case .editOutlineItem: return "pencil.circle"
        case .reorderOutline: return "arrow.up.arrow.down"
        case .replaceOutline: return "arrow.triangle.2.circlepath"
        case .refineCoreIdea: return "sparkle"
        }
    }

    private func actionColor(_ type: BrainstormAction.ActionType) -> Color {
        switch type {
        case .addOutlineItem: return CosmoColors.emerald
        case .editOutlineItem: return CosmoColors.blockContent
        case .reorderOutline: return CosmoColors.lavender
        case .replaceOutline: return .orange
        case .refineCoreIdea: return CosmoColors.lavender
        }
    }
}

// MARK: - Expandable Outline Item Row

private struct ExpandableOutlineItemRow: View {
    let item: OutlineItem
    let onUpdateTitle: (String) -> Void
    let onUpdateReasoning: (String) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isEditingTitle = false
    @State private var isEditingReasoning = false
    @State private var editTitle: String = ""
    @State private var editReasoning: String = ""
    @State private var isHovered = false
    @FocusState private var titleFocused: Bool
    @FocusState private var reasoningFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed row — always visible
            collapsedRow

            // Expanded reasoning section
            if isExpanded {
                expandedSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.thinkspaceTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isExpanded ? CosmoColors.blockContent.opacity(0.15) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Collapsed Row

    @ViewBuilder
    private var collapsedRow: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))

            // Number
            Text("\(item.sortOrder + 1).")
                .font(CosmoTypography.label)
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20, alignment: .trailing)

            // Title (editable on double-click)
            titleView

            Spacer(minLength: 4)

            // Duration badge
            if let seconds = item.estimatedSeconds, seconds > 0 {
                durationBadge(seconds)
            }

            // Expand chevron
            expandChevron

            // Controls (visible on hover)
            if isHovered {
                controlButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingTitle {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .focused($titleFocused)
                .onSubmit { commitTitleEdit() }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitTitleEdit() }
                }
        } else {
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    editTitle = item.title
                    isEditingTitle = true
                    titleFocused = true
                }
        }
    }

    @ViewBuilder
    private func durationBadge(_ seconds: Int) -> some View {
        Text("~\(formattedDuration(seconds))")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(CosmoColors.blockContent.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(CosmoColors.blockContent.opacity(0.1))
            )
    }

    @ViewBuilder
    private var expandChevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.25))
            .frame(width: 16)
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 2) {
            Button(action: {
                editTitle = item.title
                isEditingTitle = true
                titleFocused = true
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }

    // MARK: - Expanded Section

    @ViewBuilder
    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if isEditingReasoning {
                reasoningEditor
            } else {
                reasoningDisplay
            }
        }
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var reasoningDisplay: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.reasoning.isEmpty {
                emptyReasoningPlaceholder
            } else {
                Text(item.reasoning)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) {
                        editReasoning = item.reasoning
                        isEditingReasoning = true
                        reasoningFocused = true
                    }
            }
        }
        .padding(.horizontal, 44) // aligned with title (drag handle + number width)
    }

    @ViewBuilder
    private var emptyReasoningPlaceholder: some View {
        Button(action: {
            editReasoning = ""
            isEditingReasoning = true
            reasoningFocused = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9))
                Text("Add notes, reasoning, or shooting details...")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white.opacity(0.25))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var reasoningEditor: some View {
        TextEditor(text: $editReasoning)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.7))
            .scrollContentBackground(.hidden)
            .focused($reasoningFocused)
            .frame(minHeight: 60, maxHeight: 120)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CosmoColors.blockContent.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 44)
            .onChange(of: reasoningFocused) { _, focused in
                if !focused { commitReasoningEdit() }
            }
    }

    // MARK: - Helpers

    private func commitTitleEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onUpdateTitle(trimmed)
        }
        isEditingTitle = false
    }

    private func commitReasoningEdit() {
        onUpdateReasoning(editReasoning)
        isEditingReasoning = false
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
        return "\(seconds)s"
    }
}

// MARK: - Related Atom Card (kept for potential sidebar usage)

private struct RelatedAtomCard: View {
    let ref: RelatedAtomRef
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: ref.type.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(typeColor)

                Text(ref.title)
                    .font(CosmoTypography.label)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            Text(ref.preview)
                .font(CosmoTypography.caption)
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(ref.type.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(typeColor.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15), in: Capsule())

                Spacer()

                Text("\(Int(ref.relevanceScore * 100))% match")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.thinkspaceTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    private var typeColor: Color {
        switch ref.type {
        case .idea: return CosmoColors.blockNote
        case .research: return CosmoColors.blockResearch
        case .connection: return CosmoColors.blockConnection
        case .content: return CosmoColors.blockContent
        default: return .white.opacity(0.5)
        }
    }
}

// MARK: - Brainstorm Dots View (Typing Indicator)

private struct BrainstormDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(CosmoColors.lavender)
                    .frame(width: 5, height: 5)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
