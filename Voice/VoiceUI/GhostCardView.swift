// CosmoOS/Voice/VoiceUI/GhostCardView.swift
// Visual representation of speculative "Ghost Cards"
// Frosted glass design with streaming text and state animations
// macOS 26+ optimized

import SwiftUI

// MARK: - Ghost Card View

public struct GhostCardView: View {
    let card: GhostCard
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false
    @State private var displayedTitle = ""

    public init(
        card: GhostCard,
        onTap: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.card = card
        self.onTap = onTap
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Background
            backgroundView

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                headerView

                Spacer()

                // Title (streaming)
                titleView

                // Subtitle if present
                if let subtitle = card.streamingSubtitle, !subtitle.isEmpty {
                    subtitleView(subtitle)
                }

                // Progress indicator
                if card.progress > 0 && card.progress < 1 {
                    progressView
                }

                Spacer()

                // Footer with metadata
                footerView
            }
            .padding(16)
        }
        .frame(width: card.size.width, height: card.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .scaleEffect(scaleEffect)
        .opacity(opacityValue)
        .offset(y: offsetY)
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            contextMenuItems
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: card.streamingTitle) { _, newValue in
            animateTitle(to: newValue)
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            // Base glass effect
            Rectangle()
                .fill(.ultraThinMaterial)

            // Gradient overlay based on state
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.3)
        }
    }

    private var gradientColors: [Color] {
        switch card.state {
        case .spawning:
            return [.blue.opacity(0.2), .purple.opacity(0.1)]
        case .streaming:
            return [.cyan.opacity(0.2), .blue.opacity(0.1)]
        case .confirming:
            return [.green.opacity(0.2), .cyan.opacity(0.1)]
        case .committed:
            return [.green.opacity(0.3), .mint.opacity(0.1)]
        case .dismissed:
            return [.gray.opacity(0.2), .gray.opacity(0.1)]
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Intent icon
            intentIcon
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            // Intent type label
            Text(card.intent.type.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // State indicator
            stateIndicator

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
    }

    private var intentIcon: some View {
        Group {
            switch card.intent.type {
            case .create:
                Image(systemName: "plus.circle")
            case .search:
                Image(systemName: "magnifyingglass")
            case .navigate:
                Image(systemName: "arrow.right.circle")
            case .modify:
                Image(systemName: "pencil.circle")
            case .delete:
                Image(systemName: "trash.circle")
            case .arrange:
                Image(systemName: "square.grid.2x2")
            case .unknown:
                Image(systemName: "questionmark.circle")
            }
        }
    }

    private var stateIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.5 : 1.0)

            Text(card.state.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var stateColor: Color {
        switch card.state {
        case .spawning: return .blue
        case .streaming: return .cyan
        case .confirming: return .orange
        case .committed: return .green
        case .dismissed: return .gray
        }
    }

    // MARK: - Title

    private var titleView: some View {
        Text(displayedTitle.isEmpty ? "..." : displayedTitle)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .animation(.easeInOut(duration: 0.1), value: displayedTitle)
    }

    private func subtitleView(_ subtitle: String) -> some View {
        Text(subtitle)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Progress

    private var progressView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * card.progress, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: card.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Entity type if known
            if let entityType = card.entityType {
                Text(entityType)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            Spacer()

            // Confidence indicator
            HStack(spacing: 2) {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                Text("\(Int(card.intent.confidence * 100))%")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.tertiary)

            // TTL indicator when low
            if card.timeToLive < 1.0 && card.state != .committed {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(String(format: "%.1fs", card.timeToLive))
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Border

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(borderGradient, lineWidth: borderWidth)
            .opacity(isPulsing && card.state == .spawning ? 0.8 : 1.0)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                borderColor.opacity(0.6),
                borderColor.opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        switch card.state {
        case .spawning: return .blue
        case .streaming: return .cyan
        case .confirming: return .orange
        case .committed: return .green
        case .dismissed: return .gray
        }
    }

    private var borderWidth: CGFloat {
        isHovered ? 2 : 1
    }

    // MARK: - Effects

    private var shadowColor: Color {
        borderColor.opacity(0.3)
    }

    private var shadowRadius: CGFloat {
        isHovered ? 20 : 10
    }

    private var shadowY: CGFloat {
        isHovered ? 8 : 4
    }

    private var scaleEffect: CGFloat {
        switch card.state {
        case .spawning: return isPulsing ? 0.98 : 1.0
        case .streaming: return isHovered ? 1.02 : 1.0
        case .confirming: return 1.02
        case .committed: return 1.0
        case .dismissed: return 0.95
        }
    }

    private var opacityValue: Double {
        switch card.state {
        case .spawning: return 0.9
        case .streaming: return 0.95
        case .confirming: return 1.0
        case .committed: return 1.0
        case .dismissed: return 0.0
        }
    }

    private var offsetY: CGFloat {
        card.state == .dismissed ? 20 : 0
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Commit Now") {
            onTap()
        }

        Divider()

        Button("Dismiss", role: .destructive) {
            onDismiss()
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Start with current title
        displayedTitle = card.streamingTitle

        // Pulsing animation for spawning state
        if card.state == .spawning {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func animateTitle(to newTitle: String) {
        // Typewriter effect for streaming
        guard card.state == .streaming || card.state == .spawning else {
            displayedTitle = newTitle
            return
        }

        // Simple fade transition
        withAnimation(.easeInOut(duration: 0.1)) {
            displayedTitle = newTitle
        }
    }
}

// MARK: - Ghost Cards Overlay

@MainActor
public struct GhostCardsOverlay: View {
    @ObservedObject var controller: FloatingCardsController

    public init(controller: FloatingCardsController) {
        self.controller = controller
    }

    public init() {
        self.controller = FloatingCardsController.shared
    }

    public var body: some View {
        ZStack {
            ForEach(controller.ghostCards) { card in
                GhostCardView(
                    card: card,
                    onTap: {
                        // Would trigger commit flow
                        controller.confirmCard(cardId: card.id)
                    },
                    onDismiss: {
                        controller.dismissGhostCard(card.id)
                    }
                )
                .position(card.position)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.ghostCards.map(\.id))
    }
}

// MARK: - Preview

#if DEBUG
struct GhostCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Spawning state
            GhostCardView(
                card: GhostCard(
                    state: .spawning,
                    position: .zero,
                    intent: DetectedIntent(type: .create, confidence: 0.8, nouns: ["idea"])
                )
            )

            // Streaming state
            GhostCardView(
                card: GhostCard(
                    state: .streaming,
                    position: .zero,
                    intent: DetectedIntent(type: .search, confidence: 0.92, nouns: ["meetings", "project"]),
                    streamingTitle: "Find all meetings about project..."
                )
            )

            // Confirming state
            GhostCardView(
                card: {
                    var card = GhostCard(
                        state: .confirming,
                        position: .zero,
                        intent: DetectedIntent(type: .create, confidence: 0.95, nouns: ["task"]),
                        streamingTitle: "Create new task: Review PR"
                    )
                    card.entityType = "Task"
                    card.progress = 0.7
                    return card
                }()
            )
        }
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 400, height: 800)
    }
}
#endif
