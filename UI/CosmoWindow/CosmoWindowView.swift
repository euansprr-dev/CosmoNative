// CosmoOS/UI/CosmoWindow/CosmoWindowView.swift
// Premium floating Cosmo agent overlay
// March 2026

import SwiftUI

struct CosmoWindowView: View {
    @ObservedObject private var viewModel = CosmoWindowViewModel.shared
    @Binding var isVisible: Bool
    @AppStorage("cosmoWindowAnchor") private var anchor: CosmoWindowAnchor = .right
    @Environment(\.cosmoWindowIsFloating) private var isFloating
    @State private var isComposerFocused = false

    @State private var inputText = ""
    @State private var bottomAnchorID = "bottom"
    @State private var pendingScrollWorkItem: DispatchWorkItem?

    var body: some View {
        if isFloating {
            panelShell
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .onAppear(perform: handleAppear)
        } else {
            HStack(spacing: 0) {
                if anchor == .right {
                    Spacer(minLength: 0)
                }

                panelShell
                    .dsFloatingShadow()
                    .frame(width: CosmoWindowMetrics.defaultWidth)
                    .padding(.vertical, 18)

                if anchor == .left {
                    Spacer(minLength: 0)
                }
            }
            .onAppear(perform: handleAppear)
        }
    }

    private var panelShell: some View {
        VStack(spacing: 0) {
            headerBar

            if viewModel.activeContext.type != .none {
                contextSummarySection
            }

            ZStack(alignment: .bottom) {
                messageStage

                if viewModel.showMentionOverlay {
                    CosmoMentionOverlay(
                        isVisible: $viewModel.showMentionOverlay,
                        searchText: $viewModel.mentionSearchText,
                        onSelect: { atom in
                            viewModel.addMention(atom)
                            if let atIndex = inputText.lastIndex(of: "@") {
                                let beforeAt = String(inputText[inputText.startIndex..<atIndex])
                                let title = atom.title ?? "Untitled"
                                inputText = beforeAt + "@\(title) "
                            }
                        },
                        onDismiss: {
                            dismissMentionOverlay(trimMentionQuery: true)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
                }
            }

            composerSection
        }
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: CosmoWindowMetrics.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CosmoWindowMetrics.panelCornerRadius, style: .continuous)
                .stroke(DS.border.opacity(0.5), lineWidth: 0.5)
        )
        .compositingGroup()
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cosmo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DS.text)

                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let error = viewModel.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(error)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cosmoWindowChip(activeFill: DS.redSoft, activeBorder: DS.red.opacity(0.18))
            } else if viewModel.isProcessing {
                ProcessingStatusPill(
                    startedAt: viewModel.processingStartedAt,
                    label: viewModel.activeToolLabel ?? "Thinking"
                )
            }

            HStack(spacing: 6) {
                headerControlButton("plus.message") {
                    Task { await viewModel.startNewChat() }
                }
                .help("New Chat")

                headerControlButton("clock.arrow.circlepath") {
                    viewModel.showChatHistory.toggle()
                }
                .help("Chat History")
                .popover(isPresented: $viewModel.showChatHistory) {
                    chatHistoryPopover
                }

                headerControlButton("xmark") {
                    CosmoWindowPanelController.shared.hide()
                }
                .help("Close")
            }
            .padding(4)
            .cosmoWindowGroupChrome(cornerRadius: 14)
        }
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
        .frame(height: CosmoWindowMetrics.headerHeight)
    }

    private var contextSummarySection: some View {
        CosmoContextBar(context: viewModel.activeContext)
            .padding(.horizontal, CosmoWindowMetrics.contentPadding)
            .padding(.bottom, 6)
    }

    private var messageStage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: CosmoWindowMetrics.messageSpacing) {
                    if viewModel.messages.isEmpty {
                        CosmoEmptyStateCard(
                            context: viewModel.activeContext,
                            suggestions: promptSuggestions,
                            onSelectSuggestion: queuePrompt
                        )
                    } else {
                        ForEach(viewModel.messages) { message in
                            CosmoMessageBubble(
                                message: message,
                                onEdit: message.type == .user ? { msg in
                                    viewModel.editAndResend(messageId: msg.id)
                                    inputText = msg.content
                                    focusComposer()
                                } : nil
                            )
                        }
                    }

                    if viewModel.isProcessing {
                        CosmoThinkingCard(
                            activeLabel: viewModel.activeToolLabel ?? "Thinking",
                            startedAt: viewModel.processingStartedAt,
                            groups: viewModel.liveToolActivity,
                            onCancel: viewModel.cancelCurrentOperation
                        )
                        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 20)
            }
            .background(DS.bg)
            .onChange(of: viewModel.messages.count) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isProcessing) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.toolActivityScrollTick) { _ in
                debouncedScrollToBottom(proxy: proxy)
            }
        }
    }

    private var composerSection: some View {
        VStack(spacing: 10) {
            if viewModel.pendingEditIndex != nil {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.accent)

                    Text("Editing earlier message")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Spacer(minLength: 0)

                    Button("Cancel") {
                        viewModel.pendingEditIndex = nil
                        inputText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .cosmoWindowSectionChrome(cornerRadius: 14, shadow: false)
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        if viewModel.showMentionOverlay {
                            dismissMentionOverlay(trimMentionQuery: true)
                        } else {
                            openMentionOverlayFromComposer()
                        }
                    }
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(viewModel.showMentionOverlay ? DS.accent : DS.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(viewModel.showMentionOverlay ? DS.accentSoft : DS.bg)
                        )
                }
                .buttonStyle(.plain)

                MentionComposerTextView(
                    text: $inputText,
                    mentionedAtoms: viewModel.mentionedAtoms,
                    placeholder: "Ask Cosmo anything...",
                    isFocused: $isComposerFocused,
                    onSubmit: sendCurrentMessage,
                    onTextChange: { syncMentionSearch() }
                )
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: inputText) { syncMentionSearch() }

                modelSelector

                Button {
                    if viewModel.isProcessing {
                        viewModel.cancelCurrentOperation()
                    } else {
                        sendCurrentMessage()
                    }
                } label: {
                    Image(systemName: viewModel.isProcessing ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(sendButtonForeground)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(sendButtonBackground)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isProcessing && !canSend)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.composerCornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CosmoWindowMetrics.composerCornerRadius, style: .continuous)
                    .stroke(isComposerFocused ? DS.accent.opacity(0.22) : DS.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
        }
        .padding(CosmoWindowMetrics.contentPadding)
        .background(DS.surface)
    }

    private var modelSelector: some View {
        Menu {
            Button("Auto") { viewModel.modelOverride = nil }
            Divider()
            Button("Flash Lite (Fast)") { viewModel.modelOverride = .router }
            Button("Flash (Balanced)") { viewModel.modelOverride = .agent }
            Button("Sonnet (Best)") { viewModel.modelOverride = .reasoner }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.currentModelLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textSecondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DS.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cosmoWindowChip()
        }
        .menuStyle(.borderlessButton)
    }

    private var chatHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("Recent in-app conversations")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }

                Spacer(minLength: 0)

                Button("New Chat") {
                    Task { await viewModel.startNewChat() }
                    viewModel.showChatHistory = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cosmoWindowChip(isActive: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textMuted)

                TextField("Search chats", text: $viewModel.historySearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )

            if viewModel.filteredChatHistoryEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(DS.textMuted)

                    Text(viewModel.historySearchText.isEmpty ? "No past chats yet" : "No matching chats")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredChatHistoryEntries) { entry in
                            chatHistoryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .onAppear {
            viewModel.historySearchText = ""
            Task { await viewModel.loadChatHistory() }
        }
    }

    private func chatHistoryRow(_ entry: ChatHistoryEntry) -> some View {
        Button {
            Task { await viewModel.switchToChat(id: entry.id) }
            viewModel.showChatHistory = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.preview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if entry.isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip(isActive: true)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(entry.messageCount) messages")
                    Text("·")
                    Text(entry.lastActivity, style: .relative)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(entry.isActive ? DS.accentSoft : DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(entry.isActive ? DS.accent.opacity(0.18) : DS.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var headerSubtitle: String {
        if viewModel.activeContext.type == .none {
            return "Global assistant"
        }
        return viewModel.activeContext.type.displayName
    }

    private var promptSuggestions: [String] {
        let title = viewModel.activeContext.data.currentAtomTitle ?? "what I’m looking at"

        switch viewModel.activeContext.type {
        case .commandCenter:
            return [
                "What deserves attention in Command Center?",
                "Summarize what changed recently",
                "What should I tackle next?"
            ]
        case .contentFocusMode:
            return [
                "Tighten the angle for \(title)",
                "Give me 3 stronger hooks",
                "What should I rewrite first?"
            ]
        case .swipeGallery, .swipeStudy:
            return [
                "What pattern is showing up here?",
                "Find the strongest hook angle",
                "How would I adapt this swipe?"
            ]
        case .researchFocusMode:
            return [
                "Summarize the important takeaways",
                "What contradictions should I examine?",
                "Turn this into actionable notes"
            ]
        case .thinkspaceCanvas:
            return [
                "Summarize what I’m looking at",
                "What should I focus on next?",
                "Turn this into a plan"
            ]
        case .sanctuary:
            return [
                "What deserves attention today?",
                "Summarize my current state",
                "What should I improve first?"
            ]
        case .none:
            return [
                "What should I focus on next?",
                "Help me turn a thought into a plan",
                "Summarize what I’m working on"
            ]
        default:
            return [
                "Help me think through \(title)",
                "What matters most here?",
                "Give me the next best move"
            ]
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isProcessing
    }

    private var sendButtonBackground: Color {
        if viewModel.isProcessing {
            return DS.red
        }
        return canSend ? DS.accent : DS.borderSubtle
    }

    private var sendButtonForeground: Color {
        if viewModel.isProcessing {
            return DS.textOnAccent
        }
        return canSend ? DS.textOnAccent : DS.textMuted
    }

    private func focusComposer() {
        isComposerFocused = true
        NotificationCenter.default.post(name: .focusCosmoComposer, object: nil)
    }

    private func queuePrompt(_ prompt: String) {
        inputText = prompt
        focusComposer()
    }

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        if viewModel.showMentionOverlay {
            viewModel.showMentionOverlay = false
            viewModel.mentionSearchText = ""
        }

        if viewModel.pendingEditIndex != nil {
            Task {
                await viewModel.sendEditedMessage(text)
            }
        } else {
            Task {
                await viewModel.sendMessage(text)
            }
        }
    }

    private func headerControlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)
                .frame(width: CosmoWindowMetrics.controlSize, height: CosmoWindowMetrics.controlSize)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func handleAppear() {
        inputText = viewModel.inputText
        Task { await viewModel.loadConversation() }
        DispatchQueue.main.async { focusComposer() }
    }

    private func openMentionOverlayFromComposer() {
        if inputText.lastIndex(of: "@") == nil {
            if !inputText.isEmpty && !inputText.hasSuffix(" ") {
                inputText += " "
            }
            inputText += "@"
        }
        viewModel.mentionSearchText = ""
        viewModel.showMentionOverlay = true
        focusComposer()
    }

    private func dismissMentionOverlay(trimMentionQuery: Bool) {
        if trimMentionQuery, let atIndex = inputText.lastIndex(of: "@") {
            inputText = String(inputText[..<atIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        viewModel.showMentionOverlay = false
        viewModel.mentionSearchText = ""
    }

    private func syncMentionSearch() {
        if inputText.hasSuffix("@") && !viewModel.showMentionOverlay {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showMentionOverlay = true
                viewModel.mentionSearchText = ""
            }
        }

        guard viewModel.showMentionOverlay else { return }

        guard let atIndex = inputText.lastIndex(of: "@") else {
            dismissMentionOverlay(trimMentionQuery: false)
            return
        }

        let afterAt = String(inputText[inputText.index(after: atIndex)...])
        viewModel.mentionSearchText = afterAt
    }

    private func debouncedScrollToBottom(proxy: ScrollViewProxy) {
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(ProMotionSprings.snappy) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
}

enum CosmoWindowMetrics {
    static let defaultWidth: CGFloat = 440
    static let defaultHeight: CGFloat = 520
    static let minWidth: CGFloat = 380
    static let minHeight: CGFloat = 400
    static let maxWidth: CGFloat = 620
    static let maxHeight: CGFloat = 700

    static let panelCornerRadius: CGFloat = 20
    static let headerHeight: CGFloat = 56
    static let contentPadding: CGFloat = 18
    static let messageSpacing: CGFloat = 12
    static let controlSize: CGFloat = 32
    static let cardCornerRadius: CGFloat = 14
    static let composerCornerRadius: CGFloat = 16
    static let maxMessageWidth: CGFloat = 332
}

struct CosmoWindowSectionChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .modifier(CosmoWindowConditionalShadowModifier(enabled: shadow))
    }
}

struct CosmoWindowConditionalShadowModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dsRestingShadow()
        } else {
            content
        }
    }
}

struct CosmoWindowChipModifier: ViewModifier {
    let isActive: Bool
    let activeFill: Color
    let activeBorder: Color

    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(isActive ? activeFill : DS.surfaceElevated)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? activeBorder : DS.borderSubtle, lineWidth: 1)
            )
    }
}

struct CosmoWindowGroupChromeModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func cosmoWindowSectionChrome(
        cornerRadius: CGFloat = CosmoWindowMetrics.cardCornerRadius,
        shadow: Bool = true
    ) -> some View {
        modifier(CosmoWindowSectionChromeModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func cosmoWindowChip(
        isActive: Bool = false,
        activeFill: Color = DS.accentSoft,
        activeBorder: Color = DS.accent.opacity(0.18)
    ) -> some View {
        modifier(
            CosmoWindowChipModifier(
                isActive: isActive,
                activeFill: activeFill,
                activeBorder: activeBorder
            )
        )
    }

    func cosmoWindowGroupChrome(cornerRadius: CGFloat = 14) -> some View {
        modifier(CosmoWindowGroupChromeModifier(cornerRadius: cornerRadius))
    }
}

private struct ProcessingStatusPill: View {
    let startedAt: Date?
    let label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.accent)
                    .frame(width: 8, height: 8)

                Text(label)
                    .lineLimit(1)

                if let elapsedText = elapsedText {
                    Text(elapsedText)
                        .foregroundColor(DS.textMuted)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DS.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .cosmoWindowChip(isActive: true)
        }
    }

    private var elapsedText: String? {
        guard let startedAt else { return nil }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }
}

private struct CosmoThinkingCard: View {
    let activeLabel: String
    let startedAt: Date?
    let groups: [ToolActivityGroup]
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cosmo is working")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("Live context and tool activity")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }

                Spacer(minLength: 0)

                ProcessingStatusPill(startedAt: startedAt, label: activeLabel)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .cosmoWindowChip(activeFill: DS.redSoft, activeBorder: DS.red.opacity(0.18))
            }

            ToolActivityStreamView(groups: groups, activeLabel: activeLabel)
        }
        .padding(14)
        .cosmoWindowSectionChrome(cornerRadius: 16)
    }
}

/// Compact inline context bar — shows the active focus mode context
/// without eating vertical space. No nested card chrome.
private struct CosmoContextBar: View {
    let context: CosmoActiveContext

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: context.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 26, height: 26)
                .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(context.type.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                if let title = context.data.currentAtomTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let count = context.data.visibleItemCount {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .cosmoWindowChip()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }
}

private struct CosmoEmptyStateCard: View {
    let context: CosmoActiveContext
    let suggestions: [String]
    let onSelectSuggestion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.type == .none ? "Ask Cosmo anything" : "Ready with your current context")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text(descriptionText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.accentSoft)
                        .frame(width: 52, height: 52)

                    Image(systemName: context.type == .none ? "sparkles" : context.type.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DS.accent)
                }
            }

            FlowSuggestionsView(items: suggestions, onSelect: onSelectSuggestion)

            HStack(spacing: 10) {
                Text("Option+A")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .cosmoWindowChip(isActive: true)

                Text("Opens Cosmo from anywhere")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .padding(18)
        .padding(.horizontal, CosmoWindowMetrics.contentPadding)
        .cosmoWindowSectionChrome(cornerRadius: 18)
    }

    private var descriptionText: String {
        if context.type == .none {
            return "Cosmo can help you think, summarize, plan, and write. Add @ references or just start typing."
        }

        if let current = context.data.currentAtomTitle, !current.isEmpty {
            return "Cosmo already sees \(current) and the surrounding workspace, so you can jump straight into the work."
        }

        return "Cosmo is reading your active workspace and can use that context immediately."
    }
}

private struct FlowSuggestionsView: View {
    let items: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.textMuted)
                .textCase(.uppercase)
                .tracking(0.7)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) {
                        onSelect(item)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }
}

struct FlexibleFactRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .cosmoWindowChip()
            }
        }
    }
}

#if DEBUG
struct CosmoWindowView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isVisible = true

        var body: some View {
            ZStack {
                DS.bg.ignoresSafeArea()

                if isVisible {
                    CosmoWindowView(isVisible: $isVisible)
                        .frame(width: CosmoWindowMetrics.defaultWidth, height: CosmoWindowMetrics.defaultHeight)
                        .padding(30)
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .frame(width: 1200, height: 900)
    }
}
#endif
