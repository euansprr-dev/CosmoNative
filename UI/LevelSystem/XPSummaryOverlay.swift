import SwiftUI
import Combine

// MARK: - Cross-Platform Screen Size

private struct ScreenSize {
    static var width: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.width
        #else
        return NSScreen.main?.frame.width ?? 1440
        #endif
    }

    static var height: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.height
        #else
        return NSScreen.main?.frame.height ?? 900
        #endif
    }
}

// MARK: - XP Summary Overlay

/// Full-screen overlay shown on first boot after daily cron has run
/// Displays yesterday's progress with animated XP counting and celebrations
public struct XPSummaryOverlay: View {
    @ObservedObject var levelService: LevelSystemService
    @Binding var isPresented: Bool

    @State private var animationPhase: AnimationPhase = .greeting
    @State private var displayedXP: Int = 0
    @State private var showDimensionBreakdown = false
    @State private var showLevelUps = false
    @State private var showBadges = false
    @State private var showStreaks = false
    @State private var showTodayFocus = false
    @State private var particleOpacity: Double = 0

    public enum AnimationPhase {
        case greeting
        case xpCounting
        case breakdown
        case achievements
        case todayFocus
        case complete
    }

    public init(
        levelService: LevelSystemService,
        isPresented: Binding<Bool>
    ) {
        self.levelService = levelService
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Background
            backgroundGradient

            // Particle effects
            ParticleEffectView()
                .opacity(particleOpacity)

            // Content
            VStack(spacing: 32) {
                Spacer()

                // Greeting
                if animationPhase != .complete {
                    greetingSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // XP Counter
                if animationPhase.rawValue >= AnimationPhase.xpCounting.rawValue {
                    xpCounterSection
                        .transition(.scale.combined(with: .opacity))
                }

                // Dimension Breakdown
                if showDimensionBreakdown {
                    dimensionBreakdownSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Level Ups
                if showLevelUps {
                    levelUpsSection
                        .transition(.scale.combined(with: .opacity))
                }

                // Badges
                if showBadges {
                    badgesSection
                        .transition(.scale.combined(with: .opacity))
                }

                // Streaks
                if showStreaks {
                    streaksSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Today's Focus
                if showTodayFocus {
                    todayFocusSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                // Continue Button
                if animationPhase == .complete {
                    continueButton
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(24)
        }
        .onAppear {
            startAnimationSequence()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.1, green: 0.05, blue: 0.2),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        VStack(spacing: 12) {
            Text(greeting)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("Here's your progress from yesterday")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default: return "Welcome Back"
        }
    }

    // MARK: - XP Counter Section

    private var xpCounterSection: some View {
        VStack(spacing: 16) {
            Text("XP EARNED")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("+")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.green)

                Text("\(displayedXP)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text("XP")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Bonus indicator
            if displayedXP > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("1.35x streak bonus applied!")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Dimension Breakdown Section

    private var dimensionBreakdownSection: some View {
        VStack(spacing: 12) {
            Text("BY DIMENSION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)

            HStack(spacing: 16) {
                DimensionXPChip(
                    dimension: "Cognitive",
                    xp: 245,
                    icon: "brain.head.profile",
                    color: .blue
                )

                DimensionXPChip(
                    dimension: "Creative",
                    xp: 180,
                    icon: "lightbulb.fill",
                    color: .orange
                )

                DimensionXPChip(
                    dimension: "Physiological",
                    xp: 85,
                    icon: "heart.fill",
                    color: .red
                )
            }

            HStack(spacing: 16) {
                DimensionXPChip(
                    dimension: "Behavioral",
                    xp: 120,
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                DimensionXPChip(
                    dimension: "Knowledge",
                    xp: 95,
                    icon: "book.fill",
                    color: .purple
                )

                DimensionXPChip(
                    dimension: "Reflection",
                    xp: 50,
                    icon: "person.fill.questionmark",
                    color: .indigo
                )
            }
        }
    }

    // MARK: - Level Ups Section

    private var levelUpsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow)

                Text("LEVEL UP!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
                    .tracking(1)
            }

            HStack(spacing: 24) {
                LevelUpCard(
                    dimension: "Cognitive",
                    previousLevel: 41,
                    newLevel: 42,
                    color: .blue
                )

                LevelUpCard(
                    dimension: "Cosmo Index",
                    previousLevel: 37,
                    newLevel: 38,
                    color: .purple,
                    isMainLevel: true
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.yellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(spacing: 12) {
            Text("BADGES UNLOCKED")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)

            HStack(spacing: 16) {
                BadgeUnlockCard(
                    name: "30-Day Flowwalker",
                    icon: "flame.fill",
                    tier: .silver
                )

                BadgeUnlockCard(
                    name: "Word Warrior",
                    icon: "pencil.line",
                    tier: .bronze
                )
            }
        }
    }

    // MARK: - Streaks Section

    private var streaksSection: some View {
        HStack(spacing: 16) {
            // Current streak
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)

                    Text("47")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Text("Day Streak")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )

            // Streak protected
            VStack(spacing: 6) {
                Image(systemName: "shield.checkmark.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                Text("Streak Protected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.15))
            )
        }
    }

    // MARK: - Today's Focus Section

    private var todayFocusSection: some View {
        VStack(spacing: 12) {
            Text("TODAY'S FOCUS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Primary Quest")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))

                        Text("Complete 60 min deep work")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("+75 XP")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }

                // Readiness note
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)

                    Text("Your readiness is 85% - great day for peak performance!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                isPresented = false
            }
        } label: {
            Text("Let's Go")
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
        .padding(.bottom, 20)
    }

    // MARK: - Animation Sequence

    private func startAnimationSequence() {
        let totalXP = 775 // Sample total XP

        // Phase 1: Greeting (already shown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animationPhase = .xpCounting
            }
            startXPCounting(to: totalXP)
        }

        // Phase 2: Dimension breakdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDimensionBreakdown = true
            }
        }

        // Phase 3: Level ups
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showLevelUps = true
                particleOpacity = 1.0
            }
            triggerHaptic(.success)
        }

        // Phase 4: Badges
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showBadges = true
            }
            triggerHaptic(.medium)
        }

        // Phase 5: Streaks
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStreaks = true
            }
        }

        // Phase 6: Today's focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTodayFocus = true
                animationPhase = .complete
            }
        }
    }

    private func startXPCounting(to target: Int) {
        let duration: Double = 1.5
        let steps = 30
        let stepDuration = duration / Double(steps)
        let increment = target / steps

        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedXP = min(increment * (i + 1), target)
                }
            }
        }
    }

    private func triggerHaptic(_ type: XPHapticType) {
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator
        switch type {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy: generator = UIImpactFeedbackGenerator(style: .heavy)
        case .success:
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)
            return
        }
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Animation Phase Extension

extension XPSummaryOverlay.AnimationPhase: Comparable {
    public static func < (lhs: XPSummaryOverlay.AnimationPhase, rhs: XPSummaryOverlay.AnimationPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var rawValue: Int {
        switch self {
        case .greeting: return 0
        case .xpCounting: return 1
        case .breakdown: return 2
        case .achievements: return 3
        case .todayFocus: return 4
        case .complete: return 5
        }
    }
}

// MARK: - Haptic Type

private enum XPHapticType {
    case light
    case medium
    case heavy
    case success
}

// MARK: - Dimension XP Chip

struct DimensionXPChip: View {
    let dimension: String
    let xp: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text("+\(xp)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(dimension)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.2))
        )
    }
}

// MARK: - Level Up Card

struct LevelUpCard: View {
    let dimension: String
    let previousLevel: Int
    let newLevel: Int
    let color: Color
    var isMainLevel: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Text(dimension)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 8) {
                Text("\(previousLevel)")
                    .font(.system(size: isMainLevel ? 28 : 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.yellow)

                Text("\(newLevel)")
                    .font(.system(size: isMainLevel ? 28 : 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.2))
        )
    }
}

// MARK: - Badge Unlock Card

struct BadgeUnlockCard: View {
    let name: String
    let icon: String
    let tier: SummaryBadgeTier

    enum SummaryBadgeTier {
        case bronze, silver, gold, platinum, diamond, cosmic

        var color: Color {
            switch self {
            case .bronze: return .brown
            case .silver: return .gray
            case .gold: return .yellow
            case .platinum: return .cyan
            case .diamond: return .blue
            case .cosmic: return .purple
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tier.color.opacity(0.3))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(tier.color)
            }

            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Particle Effect View

struct ParticleEffectView: View {
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: Double
    }

    var body: some View {
        GeometryReader { geometry in
            ForEach(particles) { particle in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: particle.size, height: particle.size)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }
        }
        .onAppear {
            generateParticles()
        }
    }

    private func generateParticles() {
        let screenWidth = ScreenSize.width
        let screenHeight = ScreenSize.height

        for _ in 0..<50 {
            let particle = Particle(
                x: CGFloat.random(in: 0...screenWidth),
                y: CGFloat.random(in: -50...screenHeight),
                size: CGFloat.random(in: 2...8),
                opacity: Double.random(in: 0.3...1.0),
                speed: Double.random(in: 1...3)
            )
            particles.append(particle)
        }

        // Animate particles
        animateParticles()
    }

    private func animateParticles() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            withAnimation(.linear(duration: 0.05)) {
                for i in particles.indices {
                    particles[i].y -= CGFloat(particles[i].speed)
                    particles[i].opacity -= 0.01

                    // Reset particle if it goes off screen
                    if particles[i].y < -50 || particles[i].opacity <= 0 {
                        particles[i].y = ScreenSize.height + 50
                        particles[i].x = CGFloat.random(in: 0...ScreenSize.width)
                        particles[i].opacity = Double.random(in: 0.3...1.0)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    XPSummaryOverlay(
        levelService: LevelSystemService(database: CosmoDatabase.shared.dbQueue!),
        isPresented: .constant(true)
    )
}
