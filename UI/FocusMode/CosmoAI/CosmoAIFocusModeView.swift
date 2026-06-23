// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift
// Full-screen deep AI workspace for Cosmo AI blocks
// Unified with CosmoAgentService — full tool access, @ mentions, live tool activity
// February 2026

import SwiftUI

struct CosmoAIFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @StateObject private var viewModel: CosmoAIFocusModeViewModel
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    @State private var sidebarVisible = false

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.isPaneActive) private var isPaneActive

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: CosmoAIFocusModeViewModel(atom: atom))
    }

    var body: some View {
        ZStack {
            // Background
            DS.focusImmersiveBackground
                .ignoresSafeArea()

            // Subtle ambient purple glow
            RadialGradient(
                colors: [
                    DS.accent.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()

            // Main content
            HStack(spacing: 0) {
                // Left: Conversation panel
                VStack(spacing: 0) {
                    header

                    if !viewModel.contextSources.isEmpty {
                        contextChips
                    }

                    CosmoAIConversationPanel(viewModel: viewModel)

                    inputArea
                }
                .frame(maxWidth: .infinity)

                // Right: Surfaced atoms panel
                if !viewModel.surfacedAtoms.isEmpty {
                    surfacedAtomsPanel
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .focusImmersiveEntryTransition()
        .overlay(alignment: .topLeading) {
            FocusSidebarTrigger(isVisible: $sidebarVisible)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            UniversalFocusSidebar(
                title: "Context",
                icon: "brain",
                accentColor: DS.accent,
                isVisible: $sidebarVisible,
                isLocked: .constant(false)
            ) {
                cosmoAISidebarContent
            }
            .padding(.leading, 8)
            .padding(.top, 56)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            // Main sidebar toggle
            if let atomChrome {
                AtomWindowChromeLeadingControls(context: atomChrome)
            } else if !isPaneContext {
                Button {
                    withAnimation(ProMotionSprings.sidebar) {
                        isSidebarHidden.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSidebarHidden ? DS.textMuted : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isSidebarHidden ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            }

            if atomChrome == nil {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(DS.border))
                }
                .buttonStyle(.plain)
                .opacity(isPeekContext ? 0 : 1)
                .allowsHitTesting(!isPeekContext)
            }

            if atomChrome == nil {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.accent)
                    Text("Cosmo AI")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.text)
                }
            }

            Spacer()

            // Focus mode sidebar toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(sidebarVisible ? DS.accent : DS.textSecondary)
                    .padding(8)
                    .background(
                        sidebarVisible ? DS.accent.opacity(0.15) : DS.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)

            // Connected context count
            if !viewModel.connectedAtomUUIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("\(viewModel.connectedAtomUUIDs.count) connected")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.accent.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DS.accent.opacity(0.1)))
            }

            // Token usage estimate
            if !viewModel.messages.isEmpty {
                let tokenCount = viewModel.messages.reduce(0) { $0 + ($1.content.count / 4) }
                Text("\(tokenCount) tokens")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }

            if let atomChrome {
                AtomWindowChromeTrailingControls(context: atomChrome)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.surface.opacity(0.5))
    }

    // MARK: - Context Chips
    private var contextChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.contextSources) { source in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(CosmoMentionColors.color(for: source.type))
                            .frame(width: 5, height: 5)
                        Text(source.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DS.borderSubtle))
                    .overlay(Capsule().stroke(DS.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Sidebar Content

    private var cosmoAISidebarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.contextSources.isEmpty {
                Text("No context sources")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            } else {
                Text("Context Sources")
                    .dsSmallCapsLabel()

                ForEach(viewModel.contextSources) { source in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CosmoMentionColors.color(for: source.type))
                            .frame(width: 6, height: 6)

                        Text(source.title)
                            .font(.system(size: 12))
                            .foregroundColor(DS.text)
                            .lineLimit(2)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)

            VStack(spacing: 0) {
                // Mention overlay
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

                // Input bar
                HStack(spacing: 8) {
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

                    // Text input
                    ZStack(alignment: .leading) {
                        if inputText.isEmpty {
                            Text("Ask Cosmo anything...")
                                .font(.system(size: 14))
                                .foregroundColor(DS.textMuted)
                        }
                        TextField("", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(DS.text)
                            .focused($isInputFocused)
                            .onSubmit {
                                sendCurrentMessage()
                            }
                            .onChange(of: inputText) { newValue in
                                if newValue.hasSuffix("@") && !viewModel.showMentionOverlay {
                                    withAnimation(ProMotionSprings.snappy) {
                                        viewModel.showMentionOverlay = true
                                        viewModel.mentionSearchText = ""
                                    }
                                }
                                if viewModel.showMentionOverlay {
                                    if let atIndex = newValue.lastIndex(of: "@") {
                                        let afterAt = String(newValue[newValue.index(after: atIndex)...])
                                        viewModel.mentionSearchText = afterAt
                                    }
                                }
                            }
                    }

                    // Model selector
                    modelSelector

                    // Send button
                    Button {
                        sendCurrentMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(inputText.isEmpty || viewModel.isProcessing ? DS.textMuted : DS.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || viewModel.isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(DS.surface)
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
            Button("Haiku") { viewModel.modelOverride = .sensor }
            Button("Sonnet") { viewModel.modelOverride = .strategist }
            Button("Opus") { viewModel.modelOverride = .writer }
        } label: {
            Text(modelLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DS.borderSubtle))
        }
    }

    private var modelLabel: String {
        switch viewModel.modelOverride {
        case .sensor: return "Haiku"
        case .strategist: return "Sonnet"
        case .writer: return "Opus"
        case nil: return "Auto"
        default: return "Auto"
        }
    }

    // MARK: - Send
    private func sendCurrentMessage() {
        viewModel.inputText = inputText
        inputText = ""
        viewModel.showMentionOverlay = false
        Task { await viewModel.sendMessage() }
    }

    // MARK: - Surfaced Atoms Panel
    private var surfacedAtomsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Related")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.surfacedAtoms) { atom in
                        SurfacedAtomCard(atom: atom) {
                            viewModel.unpinAtom(atom)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .background(DS.surface.opacity(0.3))
        .overlay(
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(width: 1),
            alignment: .leading
        )
    }
}


// MARK: - Surfaced Atom Card

private struct SurfacedAtomCard: View {
    let atom: Atom
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .idea

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(CosmoMentionColors.color(for: entityType))
                    .frame(width: 6, height: 6)
                Text(entityType.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CosmoMentionColors.color(for: entityType).opacity(0.7))
                Spacer()
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(atom.title ?? "Untitled")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)
                .lineLimit(2)

            if let body = atom.body, !body.isEmpty {
                Text(body.prefix(100))
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(DS.surfaceElevated))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? DS.border : DS.borderSubtle, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": entityType, "id": atom.id ?? Int64(0)]
            )
        }
    }
}
