// CosmoOS/UI/CosmoWindow/CosmoWindowView.swift
// Global floating Cosmo chat panel — accessible from anywhere via Option+A
// Native macOS sidebar chat aesthetic, iMessage/Telegram Desktop feel
// February 2026

import SwiftUI

// MARK: - Cosmo Window View

/// The main floating chat panel for the global Cosmo AI assistant.
/// Rendered as a ZStack overlay in MainView, anchored to left or right edge.
/// Width: 400px, full height minus 32px padding. Glass material background.
struct CosmoWindowView: View {

    // MARK: - State

    @ObservedObject private var viewModel = CosmoWindowViewModel.shared
    @Binding var isVisible: Bool
    @AppStorage("cosmoWindowAnchor") private var anchor: CosmoWindowAnchor = .right
    @FocusState private var isInputFocused: Bool

    @State private var inputText: String = ""
    @State private var isHoveringClose = false
    @State private var isHoveringMinimize = false
    @State private var isHoveringNewChat = false
    @State private var isHoveringHistory = false
    @State private var bottomAnchorID = "bottom"
    @State private var pendingScrollWorkItem: DispatchWorkItem?

    // MARK: - Constants

    private let panelWidth: CGFloat = 400
    private let verticalPadding: CGFloat = 16

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            if anchor == .right { Spacer(minLength: 0) }

            panelContent
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .padding(.vertical, verticalPadding)
                .background(panelBackground)
                .clipShape(innerEdgeShape)
                .overlay(
                    innerEdgeShape.stroke(DS.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 24, x: anchor == .right ? -8 : 8, y: 0)
                .transition(
                    .move(edge: anchor == .right ? .trailing : .leading)
                    .combined(with: .opacity)
                )

            if anchor == .left { Spacer(minLength: 0) }
        }
        .onAppear {
            isInputFocused = true
            Task { await viewModel.loadConversation() }
        }
    }

    // MARK: - Panel Content

    private var panelContent: some View {
        VStack(spacing: 0) {
            headerBar
            contextChips
            divider
            messageList
            inputBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Cosmo label
            Text("Cosmo")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.text)

            // Context indicator pill
            if viewModel.activeContext.type != .none {
                contextPill
            }

            Spacer()

            // Error indicator
            if viewModel.error != nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.orange)
            }

            // Processing indicator
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            // New Chat button
            Button {
                Task { await viewModel.startNewChat() }
            } label: {
                Image(systemName: "plus.message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHoveringNewChat ? DS.text : DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        isHoveringNewChat ? DS.borderActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringNewChat = hovering
            }
            .help("New Chat")

            // Chat History button
            Button {
                viewModel.showChatHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHoveringHistory ? DS.text : DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        isHoveringHistory ? DS.borderActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringHistory = hovering
            }
            .help("Chat History")
            .popover(isPresented: $viewModel.showChatHistory) {
                chatHistoryPopover
            }

            // Close button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isHoveringClose ? DS.text : DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        isHoveringClose ? DS.borderActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringClose = hovering
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    // MARK: - Context Indicator Pill

    private var contextPill: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.activeContext.type.icon)
                .font(.system(size: 9, weight: .medium))

            Text(viewModel.activeContext.type.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(DS.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.accent.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Context Chips

    @ViewBuilder
    private var contextChips: some View {
        if viewModel.activeContext.type != .none {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    contextChipItems
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 32)

            divider
        }
    }

    @ViewBuilder
    private var contextChipItems: some View {
        let data = viewModel.activeContext.data

        // Current item chip
        if let title = data.currentAtomTitle {
            contextChip(title)
        }

        // Visible items chip
        if let count = data.visibleItemCount {
            contextChip("\(count) items")
        }

        // Active filters
        if let filters = data.activeFilters {
            ForEach(filters, id: \.self) { filter in
                contextChip(filter)
            }
        }

        // View-specific data chips (show first 3)
        let specificData = Array(data.viewSpecificData.prefix(3))
        ForEach(specificData, id: \.key) { key, value in
            contextChip("\(key): \(value)")
        }

        // Selected text indicator
        if data.selectedText != nil {
            contextChip("Selection active")
        }
    }

    private func contextChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Empty state
                    if viewModel.messages.isEmpty {
                        emptyState
                    }

                    // Messages
                    ForEach(viewModel.messages) { message in
                        CosmoMessageBubble(
                            message: message,
                            onEdit: message.type == .user ? { msg in
                                viewModel.editAndResend(messageId: msg.id)
                            } : nil
                        )
                    }

                    // Live tool activity (shown during processing)
                    if viewModel.isProcessing && (!viewModel.liveToolActivity.isEmpty || viewModel.activeToolLabel != nil) {
                        ToolActivityStreamView(
                            groups: viewModel.liveToolActivity,
                            activeLabel: viewModel.activeToolLabel
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Bottom anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.vertical, 8)
            }
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

    // MARK: - Auto-Scroll

    /// Debounced scroll-to-bottom — coalesces rapid successive calls (tool activity,
    /// message count, processing state) into a single scroll to prevent layout thrashing.
    private func debouncedScrollToBottom(proxy: ScrollViewProxy) {
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("Ask Cosmo anything")
                .font(DS.cardTitle)
                .foregroundColor(DS.textSecondary)

            Text("Context-aware AI assistant.\nKnows what you're working on.")
                .font(DS.cardMeta)
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            divider

            // Error banner
            if let error = viewModel.error {
                errorBanner(error)
            }

            // Edit indicator (above input)
            if viewModel.pendingEditIndex != nil {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.accent)

                    Text("Editing message")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)

                    Spacer()

                    Button {
                        viewModel.pendingEditIndex = nil
                        inputText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(DS.accent.opacity(0.06))
            }

            // Mention overlay (above input)
            if viewModel.showMentionOverlay {
                CosmoMentionOverlay(
                    isVisible: $viewModel.showMentionOverlay,
                    searchText: $viewModel.mentionSearchText,
                    onSelect: { atom in
                        viewModel.addMention(atom)
                        // Remove the @query text — the chip is the visual indicator
                        if let atIndex = inputText.lastIndex(of: "@") {
                            inputText = String(inputText[inputText.startIndex..<atIndex])
                            if !inputText.isEmpty && !inputText.hasSuffix(" ") { inputText += " " }
                        }
                    },
                    onDismiss: {
                        viewModel.showMentionOverlay = false
                        viewModel.mentionSearchText = ""
                    }
                )
                .frame(maxHeight: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Mention context chips (above input)
            if !viewModel.mentionedAtoms.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.mentionedAtoms, id: \.uuid) { atom in
                            mentionChip(atom)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // @ mention button
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.showMentionOverlay.toggle()
                    }
                } label: {
                    Text("@")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.showMentionOverlay ? DS.accent : DS.textMuted)
                        .frame(width: 28, height: 28)
                        .background(viewModel.showMentionOverlay ? DS.accent.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Expanding text field (grows up to 5 lines, then scrolls)
                TextField("Ask Cosmo anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.body)
                    .foregroundColor(DS.text)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(
                                isInputFocused ? DS.accent.opacity(0.4) : DS.border,
                                lineWidth: 1
                            )
                    )
                    .onSubmit {
                        sendCurrentMessage()
                    }
                    .onChange(of: inputText) { newValue in
                        // Detect @ trigger
                        if newValue.hasSuffix("@") && !viewModel.showMentionOverlay {
                            withAnimation(ProMotionSprings.snappy) {
                                viewModel.showMentionOverlay = true
                                viewModel.mentionSearchText = ""
                            }
                        }
                        // Update mention search text while overlay is open
                        if viewModel.showMentionOverlay {
                            if let atIndex = newValue.lastIndex(of: "@") {
                                let afterAt = String(newValue[newValue.index(after: atIndex)...])
                                viewModel.mentionSearchText = afterAt
                            }
                        }
                    }

                // Model selector
                modelSelector

                // Send / Stop button
                if viewModel.isProcessing {
                    Button {
                        viewModel.cancelCurrentOperation()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(DS.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        sendCurrentMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(
                                canSend ? DS.accent : DS.textMuted
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Mention Chip

    @ViewBuilder
    private func mentionChip(_ atom: Atom) -> some View {
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .note
        HStack(spacing: 4) {
            Circle()
                .fill(CosmoMentionColors.color(for: entityType))
                .frame(width: 6, height: 6)
            Text(atom.title ?? "Untitled")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CosmoMentionColors.color(for: entityType))
                .lineLimit(1)
            Button {
                viewModel.removeMention(atom)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(CosmoMentionColors.color(for: entityType).opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(CosmoMentionColors.pillBackground(for: entityType))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(CosmoMentionColors.color(for: entityType).opacity(0.3), lineWidth: 1))
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        Menu {
            Button("Auto") { viewModel.modelOverride = nil }
            Divider()
            Button("Haiku (Fast)") { viewModel.modelOverride = .sensor }
            Button("Sonnet (Balanced)") { viewModel.modelOverride = .strategist }
            Button("Opus (Best)") { viewModel.modelOverride = .writer }
        } label: {
            Text(modelLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 50)
    }

    private var modelLabel: String {
        switch viewModel.modelOverride {
        case nil: return "Auto"
        case .sensor: return "Haiku"
        case .strategist: return "Sonnet"
        case .writer: return "Opus"
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.red)

            Text(message)
                .font(DS.cardMeta)
                .foregroundColor(DS.red)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(DS.red.opacity(0.08))
    }

    // MARK: - Chat History Popover

    private var chatHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat History")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            if viewModel.chatHistoryEntries.isEmpty {
                VStack(spacing: 8) {
                    Text("No past chats")
                        .font(DS.cardMeta)
                        .foregroundColor(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.chatHistoryEntries) { entry in
                            chatHistoryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            Task { await viewModel.loadChatHistory() }
        }
    }

    private func chatHistoryRow(_ entry: ChatHistoryEntry) -> some View {
        Button {
            Task { await viewModel.switchToChat(id: entry.id) }
            viewModel.showChatHistory = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(entry.messageCount) messages")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)

                    Text("·")
                        .foregroundColor(DS.textMuted)

                    Text(entry.lastActivity, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(entry.isActive ? DS.accent.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Panel Background

    private var panelBackground: some View {
        ZStack {
            // Ultra-thin material for blur-through
            Rectangle()
                .fill(.ultraThinMaterial)

            // Semi-transparent surface overlay
            DS.surface.opacity(0.85)
        }
    }

    // MARK: - Panel Shape

    /// Rounds only the inner edge — left corners when right-anchored, right corners when left-anchored.
    private var innerEdgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: anchor == .right ? DS.radiusLarge : 0,
            bottomLeadingRadius: anchor == .right ? DS.radiusLarge : 0,
            bottomTrailingRadius: anchor == .left ? DS.radiusLarge : 0,
            topTrailingRadius: anchor == .left ? DS.radiusLarge : 0
        )
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isProcessing
    }

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        // Dismiss mention overlay if open
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
}

// MARK: - Preview

#if DEBUG
struct CosmoWindowView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isVisible = true

        var body: some View {
            ZStack {
                DS.bg.ignoresSafeArea()

                // Simulated background content
                VStack {
                    Text("Main App Content")
                        .font(DS.pageTitle)
                        .foregroundColor(DS.textMuted)
                }

                if isVisible {
                    CosmoWindowView(isVisible: $isVisible)
                        .transition(
                            .move(edge: .trailing)
                            .combined(with: .opacity)
                        )
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .frame(width: 1200, height: 800)
    }
}
#endif
