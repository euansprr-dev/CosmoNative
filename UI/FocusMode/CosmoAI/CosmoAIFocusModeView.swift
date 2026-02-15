// CosmoOS/UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift
// Full-screen deep AI workspace for Cosmo AI blocks
// Opened via double-tap on a Cosmo AI block on the canvas

import SwiftUI

struct CosmoAIFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    @StateObject private var viewModel: CosmoAIFocusModeViewModel
    @FocusState private var isInputFocused: Bool

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: CosmoAIFocusModeViewModel(atom: atom))
    }

    var body: some View {
        ZStack {
            // Background
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            // Subtle ambient purple glow
            RadialGradient(
                colors: [
                    CosmoColors.thinkspacePurple.opacity(0.05),
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

                    inputBar
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
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.thinkspacePurple)
                Text("Cosmo AI")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            // Connected context count
            if !viewModel.connectedAtomUUIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("\(viewModel.connectedAtomUUIDs.count) connected")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(CosmoColors.thinkspacePurple.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(CosmoColors.thinkspacePurple.opacity(0.1)))
            }

            // Mode pills
            HStack(spacing: 6) {
                ForEach(CosmoMode.allCases, id: \.rawValue) { mode in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.currentMode = mode
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 9))
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(viewModel.currentMode == mode ? .white : mode.color.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(viewModel.currentMode == mode ? mode.color.opacity(0.3) : Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CosmoColors.thinkspaceSecondary.opacity(0.5))
    }

    // MARK: - Context Chips
    private var contextChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.contextSources) { source in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mentionColor(for: source.type))
                            .frame(width: 5, height: 5)
                        Text(source.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 12) {
            // Mode indicator
            Image(systemName: viewModel.currentMode.icon)
                .font(.system(size: 12))
                .foregroundColor(viewModel.currentMode.color)

            // Text input
            ZStack(alignment: .leading) {
                if viewModel.inputText.isEmpty {
                    Text("Ask Cosmo anything...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.25))
                }
                TextField("", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task { await viewModel.sendMessage() }
                    }
            }

            // Send button
            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.inputText.isEmpty ? .white.opacity(0.15) : CosmoColors.thinkspacePurple)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.isEmpty || viewModel.isGenerating)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CosmoColors.thinkspaceSecondary)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Surfaced Atoms Panel
    private var surfacedAtomsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Related")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
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
        .background(CosmoColors.thinkspaceSecondary.opacity(0.3))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 1),
            alignment: .leading
        )
    }

    private func mentionColor(for type: EntityType) -> Color {
        switch type {
        case .idea: return CosmoMentionColors.idea
        case .content: return CosmoMentionColors.content
        case .research: return CosmoMentionColors.research
        case .connection: return CosmoMentionColors.connection
        case .cosmoAI: return CosmoMentionColors.cosmoAI
        case .task: return CosmoMentionColors.task
        case .note: return CosmoMentionColors.note
        default: return .white
        }
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
                    .fill(mentionColor(for: entityType))
                    .frame(width: 6, height: 6)
                Text(entityType.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(mentionColor(for: entityType).opacity(0.7))
                Spacer()
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(atom.title ?? "Untitled")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)

            if let body = atom.body, !body.isEmpty {
                Text(body.prefix(100))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(CosmoColors.thinkspaceTertiary))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 1)
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

    private func mentionColor(for type: EntityType) -> Color {
        switch type {
        case .idea: return CosmoMentionColors.idea
        case .content: return CosmoMentionColors.content
        case .research: return CosmoMentionColors.research
        case .connection: return CosmoMentionColors.connection
        case .cosmoAI: return CosmoMentionColors.cosmoAI
        case .task: return CosmoMentionColors.task
        case .note: return CosmoMentionColors.note
        default: return .white
        }
    }
}
