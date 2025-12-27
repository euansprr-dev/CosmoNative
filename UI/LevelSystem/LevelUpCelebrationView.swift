import SwiftUI
import Combine

// MARK: - Level Up Celebration View

/// Epic celebration overlay for level-up moments
/// Based on peak-end rule psychology for memorable experiences
public struct LevelUpCelebrationView: View {
    let levelUp: LevelUpEvent
    let onDismiss: () -> Void

    @State private var showLevel = false
    @State private var showDetails = false
    @State private var showUnlocks = false
    @State private var showContinue = false
    @State private var ringScale: CGFloat = 0.5
    @State private var ringRotation: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var confettiActive = false

    public struct LevelUpEvent {
        let dimension: String
        let previousLevel: Int
        let newLevel: Int
        let totalXP: Int
        let xpToNextLevel: Int
        let unlockedFeatures: [UnlockedFeature]
        let unlockedBadges: [UnlockedBadge]
        let milestone: Milestone?
        let isCosmosIndexLevel: Bool

        public struct UnlockedFeature: Identifiable {
            public let id = UUID()
            let name: String
            let description: String
            let icon: String
        }

        public struct UnlockedBadge: Identifiable {
            public let id = UUID()
            let name: String
            let icon: String
            let tier: String
        }

        public struct Milestone {
            let name: String
            let description: String
        }
    }

    public init(levelUp: LevelUpEvent, onDismiss: @escaping () -> Void) {
        self.levelUp = levelUp
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Background
            backgroundLayer

            // Confetti
            if confettiActive {
                ConfettiView()
                    .ignoresSafeArea()
            }

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Level display
                if showLevel {
                    levelDisplaySection
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // Details and unlocks
                if showDetails {
                    detailsSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 20)
                }

                if showUnlocks && (!levelUp.unlockedFeatures.isEmpty || !levelUp.unlockedBadges.isEmpty) {
                    unlocksSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 20)
                }

                // Continue button
                if showContinue {
                    continueButton
                        .transition(.opacity)
                        .padding(.bottom, 40)
                }
            }
            .padding(24)
        }
        .onAppear {
            startCelebrationSequence()
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: dimensionColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Radial glow
            RadialGradient(
                colors: [
                    Color.white.opacity(glowOpacity * 0.4),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
            .ignoresSafeArea()

            // Animated rings
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 300 + CGFloat(index * 100), height: 300 + CGFloat(index * 100))
                    .scaleEffect(ringScale + CGFloat(index) * 0.1)
                    .rotationEffect(.degrees(ringRotation + Double(index * 30)))
            }
        }
    }

    private var dimensionColors: [Color] {
        if levelUp.isCosmosIndexLevel {
            return [
                Color(red: 0.2, green: 0.1, blue: 0.4),
                Color(red: 0.4, green: 0.1, blue: 0.5),
                Color(red: 0.3, green: 0.0, blue: 0.3)
            ]
        }

        switch levelUp.dimension.lowercased() {
        case "cognitive": return [.blue.opacity(0.8), .indigo.opacity(0.8)]
        case "creative": return [.orange.opacity(0.8), .red.opacity(0.8)]
        case "physiological": return [.red.opacity(0.8), .pink.opacity(0.8)]
        case "behavioral": return [.green.opacity(0.8), .teal.opacity(0.8)]
        case "knowledge": return [.purple.opacity(0.8), .blue.opacity(0.8)]
        case "reflection": return [.indigo.opacity(0.8), .purple.opacity(0.8)]
        default: return [.gray.opacity(0.8), .black]
        }
    }

    // MARK: - Level Display Section

    private var levelDisplaySection: some View {
        VStack(spacing: 24) {
            // Level label
            Text(levelUp.isCosmosIndexLevel ? "COSMO INDEX" : levelUp.dimension.uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .tracking(3)

            // Level number with rings
            ZStack {
                // Outer decorative ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(ringScale)
                    .rotationEffect(.degrees(ringRotation))

                // Inner ring
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(ringScale)

                // Level number
                VStack(spacing: 4) {
                    Text("Level")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Text("\(levelUp.newLevel)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5), radius: 20)
                }
            }

            // Level up indicator
            HStack(spacing: 12) {
                Text("\(levelUp.previousLevel)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)

                Text("\(levelUp.newLevel)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )

            // Milestone badge (if any)
            if let milestone = levelUp.milestone {
                VStack(spacing: 4) {
                    Text(milestone.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.yellow)

                    Text(milestone.description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        HStack(spacing: 24) {
            // Total XP
            VStack(spacing: 4) {
                Text("TOTAL XP")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)

                Text("\(formatNumber(levelUp.totalXP))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )

            // XP to next
            VStack(spacing: 4) {
                Text("NEXT LEVEL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)

                Text("\(formatNumber(levelUp.xpToNextLevel)) XP")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }

    // MARK: - Unlocks Section

    private var unlocksSection: some View {
        VStack(spacing: 16) {
            Text("UNLOCKED")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)

            // Features
            if !levelUp.unlockedFeatures.isEmpty {
                VStack(spacing: 8) {
                    ForEach(levelUp.unlockedFeatures) { feature in
                        FeatureUnlockRow(feature: feature)
                    }
                }
            }

            // Badges
            if !levelUp.unlockedBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(levelUp.unlockedBadges) { badge in
                            BadgeUnlockItem(badge: badge)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                )
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Animation Sequence

    private func startCelebrationSequence() {
        // Trigger haptic
        triggerHaptics()

        // Ring animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            ringScale = 1.0
            glowOpacity = 1.0
        }

        // Continuous ring rotation
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Show level
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showLevel = true
        }

        // Start confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            confettiActive = true
        }

        // Show details
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showDetails = true
            }
        }

        // Show unlocks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showUnlocks = true
            }
        }

        // Show continue
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showContinue = true
            }
        }
    }

    private func triggerHaptics() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
        #endif
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }
}

// MARK: - Feature Unlock Row

struct FeatureUnlockRow: View {
    let feature: LevelUpCelebrationView.LevelUpEvent.UnlockedFeature

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 18))
                .foregroundColor(.yellow)
                .frame(width: 36, height: 36)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(feature.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "lock.open.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Badge Unlock Item

struct BadgeUnlockItem: View {
    let badge: LevelUpCelebrationView.LevelUpEvent.UnlockedBadge

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tierColor.opacity(0.3))
                    .frame(width: 56, height: 56)

                Image(systemName: badge.icon)
                    .font(.system(size: 24))
                    .foregroundColor(tierColor)
            }

            Text(badge.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(badge.tier)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(tierColor)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var tierColor: Color {
        switch badge.tier.lowercased() {
        case "bronze": return .brown
        case "silver": return .gray
        case "gold": return .yellow
        case "platinum": return .cyan
        case "diamond": return .blue
        case "cosmic": return .purple
        default: return .gray
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var confetti: [ConfettiPiece] = []

    struct ConfettiPiece: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var size: CGFloat
        var color: Color
        var speed: CGFloat
        var swayOffset: CGFloat
    }

    private let colors: [Color] = [
        .yellow, .orange, .red, .pink, .purple, .blue, .green, .cyan, .white
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confetti) { piece in
                    ConfettiPieceView(piece: piece)
                }
            }
            .onAppear {
                generateConfetti(in: geometry.size)
                animateConfetti()
            }
        }
    }

    private func generateConfetti(in size: CGSize) {
        for _ in 0..<100 {
            let piece = ConfettiPiece(
                x: CGFloat.random(in: 0...size.width),
                y: -CGFloat.random(in: 50...200),
                rotation: Double.random(in: 0...360),
                size: CGFloat.random(in: 4...10),
                color: colors.randomElement() ?? .yellow,
                speed: CGFloat.random(in: 2...6),
                swayOffset: CGFloat.random(in: -2...2)
            )
            confetti.append(piece)
        }
    }

    private func animateConfetti() {
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            withAnimation(.linear(duration: 0.03)) {
                let screenSize = ConfettiScreenSize.main
                for i in confetti.indices {
                    confetti[i].y += confetti[i].speed
                    confetti[i].x += confetti[i].swayOffset
                    confetti[i].rotation += Double.random(in: 2...5)

                    if confetti[i].y > screenSize.height + 50 {
                        confetti[i].y = -50
                        confetti[i].x = CGFloat.random(in: 0...screenSize.width)
                    }
                }
            }
        }
    }
}

// MARK: - Cross-platform screen size helper
private struct ConfettiScreenSize {
    let width: CGFloat
    let height: CGFloat

    static var main: ConfettiScreenSize {
        #if os(iOS)
        let bounds = UIScreen.main.bounds
        return ConfettiScreenSize(width: bounds.width, height: bounds.height)
        #else
        if let screen = NSScreen.main {
            return ConfettiScreenSize(width: screen.frame.width, height: screen.frame.height)
        }
        return ConfettiScreenSize(width: 1920, height: 1080)
        #endif
    }
}

struct ConfettiPieceView: View {
    let piece: ConfettiView.ConfettiPiece

    var body: some View {
        Rectangle()
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 1.5)
            .rotationEffect(.degrees(piece.rotation))
            .position(x: piece.x, y: piece.y)
    }
}

// MARK: - Preview

#Preview {
    LevelUpCelebrationView(
        levelUp: LevelUpCelebrationView.LevelUpEvent(
            dimension: "Cognitive",
            previousLevel: 41,
            newLevel: 42,
            totalXP: 125847,
            xpToNextLevel: 6300,
            unlockedFeatures: [
                .init(
                    name: "Advanced Analytics",
                    description: "Unlock detailed performance breakdowns",
                    icon: "chart.bar.fill"
                )
            ],
            unlockedBadges: [
                .init(name: "Mind Master", icon: "brain.head.profile", tier: "Gold")
            ],
            milestone: nil,
            isCosmosIndexLevel: false
        ),
        onDismiss: {}
    )
}
