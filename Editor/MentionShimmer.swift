// CosmoOS/Editor/MentionShimmer.swift
// Premium shimmer animation for mention insertion
// Creates a delightful "magic" moment when linking entities

import SwiftUI

/// Premium shimmer effect that plays when a mention is inserted
/// Creates a sweeping gradient highlight that draws attention to the new link
struct MentionShimmer: View {
    let entityColor: Color
    let size: CGSize

    @State private var shimmerOffset: CGFloat = -1.0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: entityColor.opacity(0.2), location: 0.3),
                            .init(color: entityColor.opacity(0.5), location: 0.5),
                            .init(color: entityColor.opacity(0.2), location: 0.7),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: shimmerOffset * geo.size.width)
                .blur(radius: 2)
        }
        .frame(width: size.width, height: size.height)
        .mask(RoundedRectangle(cornerRadius: 4))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                shimmerOffset = 1.5
            }
        }
    }
}

/// Shimmer overlay for inline text mentions
/// Attaches to the NSAttributedString range and plays animation
struct MentionShimmerOverlay: View {
    let entityType: EntityType
    let frame: CGRect
    @State private var phase: CGFloat = -1
    @State private var opacity: CGFloat = 1

    private var entityColor: Color {
        CosmoMentionColors.color(for: entityType)
    }

    var body: some View {
        ZStack {
            // Glow pulse behind
            RoundedRectangle(cornerRadius: 4)
                .fill(entityColor.opacity(0.15))
                .blur(radius: 8)
                .scaleEffect(1.2)

            // Shimmer sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            entityColor.opacity(0.4),
                            .white.opacity(0.6),
                            entityColor.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: frame.width * 0.3)
                .offset(x: phase * frame.width)
                .mask(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .opacity(opacity)
        .onAppear {
            // Shimmer sweep animation
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = 1.3
            }

            // Fade out after shimmer completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }
        }
    }
}

/// Container view that triggers shimmer on new mention insertion
struct MentionInsertionAnimator: ViewModifier {
    let mentionId: String
    let entityType: EntityType
    let frame: CGRect

    @State private var showShimmer = false

    func body(content: Self.Content) -> some View {
        content
            .overlay {
                if showShimmer {
                    MentionShimmerOverlay(entityType: entityType, frame: frame)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                showShimmer = true
                // Remove after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showShimmer = false
                }
            }
    }
}

// MARK: - Sparkle Effect (Alternative Premium Animation)
/// Subtle sparkle particles that emanate from the mention
struct MentionSparkle: View {
    let entityColor: Color
    let origin: CGPoint

    @State private var particles: [SparkleParticle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(entityColor.opacity(particle.opacity))
                    .frame(width: particle.size, height: particle.size)
                    .offset(particle.offset)
                    .blur(radius: 0.5)
            }
        }
        .position(origin)
        .onAppear {
            generateParticles()
            animateParticles()
        }
    }

    private func generateParticles() {
        particles = (0..<8).map { _ in
            SparkleParticle(
                offset: .zero,
                size: CGFloat.random(in: 2...5),
                opacity: 1.0,
                velocity: CGSize(
                    width: CGFloat.random(in: -30...30),
                    height: CGFloat.random(in: -30...30)
                )
            )
        }
    }

    private func animateParticles() {
        withAnimation(.easeOut(duration: 0.6)) {
            for i in particles.indices {
                particles[i].offset = CGSize(
                    width: particles[i].velocity.width,
                    height: particles[i].velocity.height
                )
                particles[i].opacity = 0
                particles[i].size = 1
            }
        }
    }
}

struct SparkleParticle: Identifiable {
    let id = UUID()
    var offset: CGSize
    var size: CGFloat
    var opacity: CGFloat
    var velocity: CGSize
}

// MARK: - View Extension
extension View {
    /// Apply shimmer animation when a mention is inserted
    func mentionShimmer(
        mentionId: String,
        entityType: EntityType,
        frame: CGRect
    ) -> some View {
        modifier(MentionInsertionAnimator(
            mentionId: mentionId,
            entityType: entityType,
            frame: frame
        ))
    }
}

// MARK: - Preview
#if DEBUG
struct MentionShimmer_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Idea mention shimmer
            MentionShimmer(
                entityColor: CosmoMentionColors.idea,
                size: CGSize(width: 120, height: 24)
            )
            .frame(width: 120, height: 24)
            .background(CosmoColors.softWhite)

            // Content mention shimmer
            MentionShimmer(
                entityColor: CosmoMentionColors.content,
                size: CGSize(width: 100, height: 24)
            )
            .frame(width: 100, height: 24)
            .background(CosmoColors.softWhite)

            // Sparkle effect
            MentionSparkle(
                entityColor: CosmoColors.lavender,
                origin: CGPoint(x: 100, y: 100)
            )
            .frame(width: 200, height: 200)
        }
        .padding()
        .background(CosmoColors.softWhite)
    }
}
#endif
