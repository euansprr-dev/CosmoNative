// CosmoOS/Core/Components/CosmicShimmer.swift
// Apple-grade shimmer loading effect
// GPU-accelerated, entity-color aware

import SwiftUI

// MARK: - CosmicShimmer
/// Premium shimmer loading effect that replaces boring ProgressViews.
/// Matches entity colors and creates a polished loading experience.
///
/// Usage:
/// ```swift
/// CosmicShimmer(entityColor: CosmoMentionColors.idea)
///     .frame(height: 100)
///     .clipShape(RoundedRectangle(cornerRadius: 12))
/// ```
struct CosmicShimmer: View {
    // ═══════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════

    /// The entity color to tint the shimmer
    var entityColor: Color

    /// Base opacity of the shimmer (default: 0.08)
    var baseOpacity: CGFloat

    /// Peak opacity during shimmer (default: 0.18)
    var peakOpacity: CGFloat

    /// Animation duration (default: 1.2s)
    var duration: TimeInterval

    /// Corner radius for the shimmer shape (default: 8)
    var cornerRadius: CGFloat

    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════

    @State private var phase: CGFloat = -0.5

    // ═══════════════════════════════════════════════════════════════
    // INITIALIZER
    // ═══════════════════════════════════════════════════════════════

    init(
        entityColor: Color = CosmoColors.glassGrey,
        baseOpacity: CGFloat = 0.08,
        peakOpacity: CGFloat = 0.18,
        duration: TimeInterval = 1.2,
        cornerRadius: CGFloat = 8
    ) {
        self.entityColor = entityColor
        self.baseOpacity = baseOpacity
        self.peakOpacity = peakOpacity
        self.duration = duration
        self.cornerRadius = cornerRadius
    }

    // ═══════════════════════════════════════════════════════════════
    // BODY
    // ═══════════════════════════════════════════════════════════════

    var body: some View {
        GeometryReader { geometry in
            // Compute gradient stops with guaranteed ascending order
            let clampedPhase = max(0.0, min(1.0, phase))
            let leadingEdge = max(0.0, min(clampedPhase - 0.2, clampedPhase - 0.01))
            let trailingEdge = min(1.0, max(clampedPhase + 0.2, clampedPhase + 0.01))

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: entityColor.opacity(baseOpacity), location: 0),
                            .init(color: entityColor.opacity(baseOpacity), location: leadingEdge),
                            .init(color: entityColor.opacity(peakOpacity), location: clampedPhase),
                            .init(color: entityColor.opacity(baseOpacity), location: trailingEdge),
                            .init(color: entityColor.opacity(baseOpacity), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onAppear {
                    withAnimation(
                        .linear(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1.5
                    }
                }
        }
    }
}

// MARK: - CosmicShimmerText
/// Shimmer placeholder for text content
struct CosmicShimmerText: View {
    var lines: Int
    var entityColor: Color
    var lineHeight: CGFloat
    var lineSpacing: CGFloat

    init(
        lines: Int = 3,
        entityColor: Color = CosmoColors.glassGrey,
        lineHeight: CGFloat = 14,
        lineSpacing: CGFloat = 8
    ) {
        self.lines = lines
        self.entityColor = entityColor
        self.lineHeight = lineHeight
        self.lineSpacing = lineSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(0..<lines, id: \.self) { index in
                CosmicShimmer(entityColor: entityColor, cornerRadius: 4)
                    .frame(height: lineHeight)
                    // Vary line widths for natural look
                    .frame(maxWidth: lineWidth(for: index), alignment: .leading)
            }
        }
    }

    private func lineWidth(for index: Int) -> CGFloat {
        // Last line is shorter, middle lines vary
        if index == lines - 1 {
            return .infinity * 0.6
        }
        return .infinity
    }
}

// MARK: - CosmicShimmerCard
/// Full card shimmer placeholder matching EntityPreviewCard layout
struct CosmicShimmerCard: View {
    var entityColor: Color
    var showThumbnail: Bool
    var cornerRadius: CGFloat

    init(
        entityColor: Color = CosmoColors.glassGrey,
        showThumbnail: Bool = true,
        cornerRadius: CGFloat = 16
    ) {
        self.entityColor = entityColor
        self.showThumbnail = showThumbnail
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail area
            if showThumbnail {
                CosmicShimmer(entityColor: entityColor, cornerRadius: 8)
                    .frame(height: 120)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Title
                CosmicShimmer(entityColor: entityColor, cornerRadius: 4)
                    .frame(height: 18)
                    .frame(maxWidth: 180)

                // Subtitle/preview
                CosmicShimmer(entityColor: entityColor, cornerRadius: 4)
                    .frame(height: 14)

                // Meta row
                HStack(spacing: 8) {
                    CosmicShimmer(entityColor: entityColor, cornerRadius: 4)
                        .frame(width: 60, height: 12)

                    CosmicShimmer(entityColor: entityColor, cornerRadius: 4)
                        .frame(width: 40, height: 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(CosmoColors.softWhite)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(entityColor.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - CosmicPulse
/// Subtle pulsing effect for loading states (alternative to shimmer)
struct CosmicPulse: View {
    var entityColor: Color
    var minOpacity: CGFloat
    var maxOpacity: CGFloat

    @State private var isPulsing = false

    init(
        entityColor: Color = CosmoColors.glassGrey,
        minOpacity: CGFloat = 0.3,
        maxOpacity: CGFloat = 0.7
    ) {
        self.entityColor = entityColor
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
    }

    var body: some View {
        Rectangle()
            .fill(entityColor.opacity(isPulsing ? maxOpacity : minOpacity))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - AsyncImage with Shimmer
/// Drop-in replacement for AsyncImage that uses CosmicShimmer for loading
struct CosmicAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let entityColor: Color
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        url: URL?,
        entityColor: Color = CosmoColors.glassGrey,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.entityColor = entityColor
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder()
            case .success(let image):
                content(image)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .failure:
                // Fallback icon on failure
                ZStack {
                    CosmicShimmer(entityColor: entityColor, baseOpacity: 0.05, peakOpacity: 0.05)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(entityColor.opacity(0.4))
                }
            @unknown default:
                placeholder()
            }
        }
    }
}

// Convenience initializer with default shimmer placeholder
extension CosmicAsyncImage where Placeholder == CosmicShimmer {
    init(
        url: URL?,
        entityColor: Color = CosmoColors.glassGrey,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.url = url
        self.entityColor = entityColor
        self.content = content
        self.placeholder = { CosmicShimmer(entityColor: entityColor) }
    }
}

// MARK: - View Extension for Shimmer Overlay
extension View {
    /// Apply shimmer overlay when loading (useful for skeleton screens)
    @ViewBuilder
    func shimmerOverlay(isLoading: Bool, entityColor: Color = CosmoColors.glassGrey) -> some View {
        self
            .overlay {
                if isLoading {
                    CosmicShimmer(entityColor: entityColor)
                        .allowsHitTesting(false)
                }
            }
            .animation(ProMotionSprings.gentle, value: isLoading)
    }
}

// MARK: - Preview
#if DEBUG
struct CosmicShimmer_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            // Basic shimmer
            CosmicShimmer(entityColor: CosmoMentionColors.idea)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text shimmer
            CosmicShimmerText(lines: 4, entityColor: CosmoMentionColors.research)

            // Card shimmer
            CosmicShimmerCard(entityColor: CosmoMentionColors.connection)
                .frame(width: 280)
        }
        .padding(24)
        .background(CosmoColors.softWhite)
    }
}
#endif
