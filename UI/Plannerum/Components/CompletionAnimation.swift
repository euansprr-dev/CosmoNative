//
//  CompletionAnimation.swift
//  CosmoOS
//
//  Celebratory animations for task completion, quest completion,
//  and XP awards. Uses particle effects and satisfying feedback.
//

import SwiftUI

// MARK: - CompletionAnimationType

/// Types of completion animations
public enum CompletionAnimationType {
    case taskComplete
    case questComplete
    case xpBurst
    case levelUp
    case streakMilestone
}

// MARK: - CompletionAnimationView

/// Overlay view that displays completion animations
public struct CompletionAnimationView: View {

    let animationType: CompletionAnimationType
    let xpAmount: Int
    let onComplete: () -> Void

    @State private var isAnimating = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var burstScale: CGFloat = 0.5
    @State private var burstOpacity: Double = 0
    @State private var xpScale: CGFloat = 0.5
    @State private var xpOpacity: Double = 0
    @State private var xpOffset: CGFloat = 0
    @State private var particles: [ParticleState] = []

    public var body: some View {
        ZStack {
            // Background dim
            Color.black.opacity(isAnimating ? 0.3 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.2), value: isAnimating)

            // Animation content
            VStack(spacing: 20) {
                // Main celebration element
                ZStack {
                    // Burst effect
                    Circle()
                        .fill(burstColor.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(burstScale)
                        .opacity(burstOpacity)

                    // Checkmark or icon
                    mainIcon
                }

                // XP display
                if xpAmount > 0 {
                    xpDisplay
                }
            }

            // Particles
            ForEach(particles) { particle in
                ParticleView(state: particle)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Main Icon

    @ViewBuilder
    private var mainIcon: some View {
        switch animationType {
        case .taskComplete:
            ZStack {
                Circle()
                    .fill(NowViewTokens.checkboxChecked)
                    .frame(width: 64, height: 64)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

        case .questComplete:
            ZStack {
                Circle()
                    .fill(DailyQuestsTokens.mainQuestProgress)
                    .frame(width: 72, height: 72)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

        case .xpBurst:
            ZStack {
                Circle()
                    .fill(PlannerumColors.xpGold)
                    .frame(width: 64, height: 64)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

        case .levelUp:
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PlannerumColors.primary, PlannerumColors.primaryLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

        case .streakMilestone:
            ZStack {
                Circle()
                    .fill(DailyQuestsTokens.streakFire)
                    .frame(width: 72, height: 72)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "flame.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }
        }
    }

    // MARK: - XP Display

    private var xpDisplay: some View {
        HStack(spacing: 4) {
            Text("+\(xpAmount)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(OnyxColors.Accent.amber)
        .scaleEffect(xpScale)
        .opacity(xpOpacity)
        .offset(y: xpOffset)
    }

    // MARK: - Colors

    private var burstColor: Color {
        switch animationType {
        case .taskComplete: return NowViewTokens.checkboxChecked
        case .questComplete: return DailyQuestsTokens.mainQuestProgress
        case .xpBurst: return PlannerumColors.xpGold
        case .levelUp: return PlannerumColors.primary
        case .streakMilestone: return DailyQuestsTokens.streakFire
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        isAnimating = true

        // Generate particles
        generateParticles()

        // Phase 1: Checkmark appears (spring)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }

        // Phase 2: Burst expands
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
            burstScale = 2.0
            burstOpacity = 1.0
        }

        // Phase 2.5: Burst fades
        withAnimation(.easeOut(duration: 0.3).delay(0.4)) {
            burstOpacity = 0
        }

        // Phase 3: XP appears (if applicable)
        if xpAmount > 0 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.25)) {
                xpScale = 1.0
                xpOpacity = 1.0
            }

            // XP floats up
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                xpOffset = -20
            }
        }

        // Phase 4: Everything fades out
        withAnimation(.easeOut(duration: 0.3).delay(1.2)) {
            checkmarkScale = 0.8
            checkmarkOpacity = 0
            xpOpacity = 0
            isAnimating = false
        }

        // Callback after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onComplete()
        }
    }

    private func generateParticles() {
        let count = animationType == .levelUp ? 20 : 12
        particles = (0..<count).map { i in
            let angle = (Double(i) / Double(count)) * 2 * .pi
            let distance = CGFloat.random(in: 80...150)
            let delay = Double.random(in: 0...0.2)

            return ParticleState(
                id: UUID(),
                angle: angle,
                distance: distance,
                delay: delay,
                color: burstColor
            )
        }
    }
}

// MARK: - Particle State

struct ParticleState: Identifiable {
    let id: UUID
    let angle: Double
    let distance: CGFloat
    let delay: Double
    let color: Color
}

// MARK: - Particle View

struct ParticleView: View {
    let state: ParticleState

    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(offset)
            .onAppear {
                // Calculate target position
                let targetX = cos(state.angle) * state.distance
                let targetY = sin(state.angle) * state.distance

                // Animate particle
                withAnimation(.easeOut(duration: 0.6).delay(state.delay)) {
                    offset = CGSize(width: targetX, height: targetY)
                    opacity = 1.0
                }

                // Fade out
                withAnimation(.easeOut(duration: 0.3).delay(state.delay + 0.4)) {
                    opacity = 0
                    scale = 0.5
                }
            }
    }
}

// MARK: - Checkmark Animation View (Simpler version for inline use)

/// Animated checkmark for task completion
public struct CheckmarkAnimationView: View {

    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    let size: CGFloat
    let color: Color
    let onComplete: (() -> Void)?

    public init(
        size: CGFloat = 24,
        color: Color = NowViewTokens.checkboxChecked,
        onComplete: (() -> Void)? = nil
    ) {
        self.size = size
        self.color = color
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .opacity(opacity)

            // Checkmark path
            Path { path in
                let checkSize = size * 0.4
                let startX = size * 0.3
                let startY = size * 0.5
                let midX = size * 0.45
                let midY = size * 0.65
                let endX = size * 0.7
                let endY = size * 0.35

                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: midX, y: midY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .opacity(opacity)
        }
        .onAppear {
            // Circle appears
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }

            // Checkmark draws
            withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
                trimEnd = 1.0
            }

            // Callback
            if let onComplete = onComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}

// MARK: - XP Award Floater Animation

/// Floating XP indicator that animates upward (distinct from XPBurstView in XPTracerView)
public struct XPAwardFloater: View {

    let amount: Int
    let onComplete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5

    public init(amount: Int, onComplete: @escaping () -> Void) {
        self.amount = amount
        self.onComplete = onComplete
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .bold))
            Text("+\(amount) XP")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundColor(PlannerumColors.xpGold)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PlannerumColors.xpGold.opacity(0.2))
        .clipShape(Capsule())
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            // Pop in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }

            // Float up
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                offset = -50
            }

            // Fade out
            withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
                opacity = 0
            }

            // Callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CompletionAnimation_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            VStack(spacing: 40) {
                // Checkmark
                CheckmarkAnimationView(size: 48)

                // XP Award Floater
                XPAwardFloater(amount: 25, onComplete: {})

                // Full completion
                Button("Show Completion") {
                    // Would trigger overlay
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}
#endif
