import Foundation
import SwiftUI
import Combine

#if os(iOS) || os(watchOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

// MARK: - Celebration Engine

/// Creates memorable celebration moments for achievements
/// Based on Kahneman's peak-end rule and video game psychology
@MainActor
public final class CelebrationEngine: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var currentCelebration: CelebrationEvent?
    @Published public private(set) var isShowingCelebration: Bool = false
    @Published public private(set) var celebrationQueue: [CelebrationEvent] = []

    // MARK: - Celebration Stream

    private let celebrationSubject = PassthroughSubject<CelebrationEvent, Never>()
    public var celebrations: AnyPublisher<CelebrationEvent, Never> {
        celebrationSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Trigger Celebrations

    /// Trigger a celebration for an achievement
    public func celebrate(_ event: CelebrationEvent) {
        celebrationQueue.append(event)
        celebrationSubject.send(event)

        if !isShowingCelebration {
            showNextCelebration()
        }
    }

    /// Celebrate a level up
    public func celebrateLevelUp(
        previousLevel: Int,
        newLevel: Int,
        dimension: String?,
        xpEarned: Int
    ) {
        let tier = determineLevelUpTier(previousLevel: previousLevel, newLevel: newLevel)

        let event = CelebrationEvent(
            type: .levelUp,
            tier: tier,
            title: dimension != nil ? "\(dimension!.capitalized) Level Up!" : "Level Up!",
            subtitle: "Level \(newLevel)",
            message: "You've reached level \(newLevel)! +\(xpEarned) XP",
            xpAmount: xpEarned,
            duration: tier.defaultDuration,
            hapticPattern: tier.hapticPattern,
            soundEffect: tier.soundEffect,
            particleEffect: tier.particleEffect
        )

        celebrate(event)
    }

    /// Celebrate a badge unlock
    public func celebrateBadge(_ badge: BadgeDefinition) {
        let tier = badgeTierToCelebrationTier(badge.tier)

        let event = CelebrationEvent(
            type: .badgeUnlock,
            tier: tier,
            title: "Badge Unlocked!",
            subtitle: badge.name,
            message: badge.description,
            xpAmount: badge.xpReward,
            iconName: badge.iconName,
            duration: tier.defaultDuration,
            hapticPattern: tier.hapticPattern,
            soundEffect: tier.soundEffect,
            particleEffect: tier.particleEffect
        )

        celebrate(event)
    }

    /// Celebrate a streak milestone
    public func celebrateStreak(days: Int, dimension: String?) {
        let tier = determineStreakTier(days: days)

        let event = CelebrationEvent(
            type: .streakMilestone,
            tier: tier,
            title: "\(days)-Day Streak!",
            subtitle: dimension ?? "Overall",
            message: StreakMultiplierTiers.tierName(for: days),
            duration: tier.defaultDuration,
            hapticPattern: tier.hapticPattern,
            soundEffect: .streak,
            particleEffect: tier.particleEffect
        )

        celebrate(event)
    }

    /// Celebrate quest completion
    public func celebrateQuestComplete(_ quest: Quest, xpEarned: Int, exceededTarget: Bool) {
        let tier: CelebrationTier = exceededTarget ? .medium : .small

        let event = CelebrationEvent(
            type: .questComplete,
            tier: tier,
            title: exceededTarget ? "Quest Exceeded!" : "Quest Complete!",
            subtitle: quest.title,
            message: "+\(xpEarned) XP",
            xpAmount: xpEarned,
            duration: tier.defaultDuration,
            hapticPattern: tier.hapticPattern,
            soundEffect: .questComplete,
            particleEffect: exceededTarget ? .confetti : .sparkle
        )

        celebrate(event)
    }

    /// Celebrate XP bonus (variable ratio reward)
    public func celebrateXPBonus(bonus: XPBonusType, xpAmount: Int) {
        let tier: CelebrationTier
        let title: String

        switch bonus {
        case .luckyBonus:
            tier = .small
            title = "Lucky Bonus!"
        case .superBonus:
            tier = .medium
            title = "Super Bonus!"
        case .megaBonus:
            tier = .large
            title = "MEGA BONUS!"
        case .jackpot:
            tier = .epic
            title = "JACKPOT!"
        case .streakBonus:
            tier = .small
            title = "Streak Bonus!"
        case .firstOfDay:
            tier = .small
            title = "First of the Day!"
        case .perfectDay:
            tier = .large
            title = "Perfect Day!"
        case .dimensionMilestone:
            tier = .medium
            title = "Milestone Reached!"
        }

        let event = CelebrationEvent(
            type: .xpBonus,
            tier: tier,
            title: title,
            subtitle: "+\(xpAmount) XP",
            message: "Random bonus reward!",
            xpAmount: xpAmount,
            duration: tier.defaultDuration,
            hapticPattern: tier.hapticPattern,
            soundEffect: .bonus,
            particleEffect: tier.particleEffect
        )

        celebrate(event)
    }

    /// Celebrate all daily quests complete
    public func celebrateAllQuestsComplete(totalXP: Int) {
        let event = CelebrationEvent(
            type: .allQuestsComplete,
            tier: .large,
            title: "All Quests Complete!",
            subtitle: "Perfect Day",
            message: "You've completed all daily quests! +\(totalXP) XP",
            xpAmount: totalXP,
            duration: 4.0,
            hapticPattern: .success,
            soundEffect: .triumph,
            particleEffect: .confetti
        )

        celebrate(event)
    }

    // MARK: - Celebration Flow

    private func showNextCelebration() {
        guard !celebrationQueue.isEmpty else {
            isShowingCelebration = false
            currentCelebration = nil
            return
        }

        let event = celebrationQueue.removeFirst()
        currentCelebration = event
        isShowingCelebration = true

        // Trigger haptics
        triggerHaptics(event.hapticPattern)

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(event.duration * 1_000_000_000))
            await MainActor.run {
                dismissCurrentCelebration()
            }
        }
    }

    /// Dismiss the current celebration
    public func dismissCurrentCelebration() {
        isShowingCelebration = false
        currentCelebration = nil

        // Show next if queued
        if !celebrationQueue.isEmpty {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 second gap
                await MainActor.run {
                    showNextCelebration()
                }
            }
        }
    }

    // MARK: - Haptics

    private func triggerHaptics(_ pattern: HapticPattern) {
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator

        switch pattern {
        case .light:
            generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

        case .medium:
            generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        case .heavy:
            generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()

        case .success:
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)

        case .sequence:
            // Triple tap pattern
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }

        case .epic:
            // Epic celebration haptic sequence
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        #endif

        #if os(macOS)
        // macOS haptic feedback via trackpad
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #endif
    }

    // MARK: - Tier Determination

    private func determineLevelUpTier(previousLevel: Int, newLevel: Int) -> CelebrationTier {
        // Milestone levels get bigger celebrations
        if newLevel == 100 { return .legendary }
        if newLevel % 25 == 0 { return .epic }
        if newLevel % 10 == 0 { return .large }
        if newLevel % 5 == 0 { return .medium }
        return .small
    }

    private func badgeTierToCelebrationTier(_ badgeTier: BadgeTier) -> CelebrationTier {
        switch badgeTier {
        case .bronze: return .small
        case .silver: return .medium
        case .gold: return .large
        case .platinum: return .epic
        case .diamond: return .epic
        case .cosmic: return .legendary
        }
    }

    private func determineStreakTier(days: Int) -> CelebrationTier {
        switch days {
        case 1000...: return .legendary
        case 365...: return .epic
        case 90...: return .large
        case 30...: return .medium
        default: return .small
        }
    }
}

// MARK: - Celebration Event

public struct CelebrationEvent: Identifiable, Sendable {
    public let id: UUID
    public let type: CelebrationType
    public let tier: CelebrationTier
    public let title: String
    public let subtitle: String
    public let message: String
    public let xpAmount: Int?
    public let iconName: String?
    public let duration: TimeInterval
    public let hapticPattern: HapticPattern
    public let soundEffect: SoundEffect
    public let particleEffect: ParticleEffect

    public init(
        id: UUID = UUID(),
        type: CelebrationType,
        tier: CelebrationTier,
        title: String,
        subtitle: String,
        message: String,
        xpAmount: Int? = nil,
        iconName: String? = nil,
        duration: TimeInterval,
        hapticPattern: HapticPattern,
        soundEffect: SoundEffect,
        particleEffect: ParticleEffect
    ) {
        self.id = id
        self.type = type
        self.tier = tier
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.xpAmount = xpAmount
        self.iconName = iconName
        self.duration = duration
        self.hapticPattern = hapticPattern
        self.soundEffect = soundEffect
        self.particleEffect = particleEffect
    }
}

// MARK: - Celebration Type

public enum CelebrationType: String, Sendable {
    case levelUp
    case badgeUnlock
    case streakMilestone
    case questComplete
    case allQuestsComplete
    case xpBonus
    case neloMilestone
    case perfectDay
    case secretUnlock
}

// MARK: - Celebration Tier

public enum CelebrationTier: Int, Sendable, CaseIterable {
    case small = 1       // Subtle acknowledgment
    case medium = 2      // Moderate celebration
    case large = 3       // Full celebration
    case epic = 4        // Major milestone
    case legendary = 5   // Rare, memorable moment

    public var defaultDuration: TimeInterval {
        switch self {
        case .small: return 1.5
        case .medium: return 2.5
        case .large: return 3.5
        case .epic: return 5.0
        case .legendary: return 7.0
        }
    }

    public var hapticPattern: HapticPattern {
        switch self {
        case .small: return .light
        case .medium: return .medium
        case .large: return .success
        case .epic: return .sequence
        case .legendary: return .epic
        }
    }

    public var soundEffect: SoundEffect {
        switch self {
        case .small: return .subtle
        case .medium: return .achievement
        case .large: return .levelUp
        case .epic: return .triumph
        case .legendary: return .legendary
        }
    }

    public var particleEffect: ParticleEffect {
        switch self {
        case .small: return .sparkle
        case .medium: return .stars
        case .large: return .confetti
        case .epic: return .fireworks
        case .legendary: return .cosmic
        }
    }
}

// MARK: - Haptic Pattern

public enum HapticPattern: String, Sendable {
    case light
    case medium
    case heavy
    case success
    case sequence
    case epic
}

// MARK: - Sound Effect

public enum SoundEffect: String, Sendable {
    case subtle
    case achievement
    case levelUp
    case triumph
    case legendary
    case bonus
    case questComplete
    case streak
}

// MARK: - Particle Effect

public enum ParticleEffect: String, Sendable {
    case none
    case sparkle
    case stars
    case confetti
    case fireworks
    case cosmic
}

// MARK: - Variable Ratio Reward System

/// Implements variable ratio reinforcement (most addictive reward schedule)
public struct VariableRewardSystem: Sendable {

    /// Apply random bonus multiplier to base XP
    public static func applyVariableMultiplier(baseXP: Int) -> (xp: Int, bonus: XPBonusType?) {
        let roll = Double.random(in: 0...1)

        switch roll {
        case 0..<0.70:    // 70% - Normal
            return (baseXP, nil)
        case 0.70..<0.85: // 15% - Lucky bonus
            return (Int(Double(baseXP) * 1.25), .luckyBonus)
        case 0.85..<0.95: // 10% - Super bonus
            return (Int(Double(baseXP) * 1.5), .superBonus)
        case 0.95..<0.99: // 4% - Mega bonus
            return (Int(Double(baseXP) * 2.0), .megaBonus)
        default:          // 1% - Jackpot
            return (baseXP * 3, .jackpot)
        }
    }
}

// MARK: - Celebration View

/// SwiftUI view for displaying celebrations
public struct CelebrationOverlayView: View {
    @ObservedObject var engine: CelebrationEngine
    @State private var showContent = false
    @State private var xpCounterValue: Int = 0

    public init(engine: CelebrationEngine) {
        self.engine = engine
    }

    public var body: some View {
        ZStack {
            if let event = engine.currentCelebration, engine.isShowingCelebration {
                // Background dim
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        engine.dismissCurrentCelebration()
                    }

                // Celebration card
                VStack(spacing: 16) {
                    // Icon or particle effect area
                    ZStack {
                        Circle()
                            .fill(tierGradient(event.tier))
                            .frame(width: 100, height: 100)

                        if let iconName = event.iconName {
                            Image(systemName: iconName)
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: iconForType(event.type))
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(showContent ? 1.0 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showContent)

                    // Title
                    Text(event.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    // Subtitle
                    Text(event.subtitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))

                    // Message
                    Text(event.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // XP counter animation
                    if let xp = event.xpAmount {
                        HStack {
                            Text("+")
                            Text("\(xpCounterValue)")
                                .contentTransition(.numericText())
                            Text("XP")
                        }
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(tierColor(event.tier))
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.0)) {
                                xpCounterValue = xp
                            }
                        }
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(tierGradient(event.tier), lineWidth: 2)
                )
                .padding(24)
                .opacity(showContent ? 1.0 : 0)
                .scaleEffect(showContent ? 1.0 : 0.8)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showContent)
                .onAppear {
                    xpCounterValue = 0
                    showContent = true
                }
                .onDisappear {
                    showContent = false
                }
            }
        }
    }

    private func tierGradient(_ tier: CelebrationTier) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .small:
            colors = [.blue, .cyan]
        case .medium:
            colors = [.green, .teal]
        case .large:
            colors = [.orange, .yellow]
        case .epic:
            colors = [.purple, .pink]
        case .legendary:
            colors = [.yellow, .orange, .red]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func tierColor(_ tier: CelebrationTier) -> Color {
        switch tier {
        case .small: return .blue
        case .medium: return .green
        case .large: return .orange
        case .epic: return .purple
        case .legendary: return .yellow
        }
    }

    private func iconForType(_ type: CelebrationType) -> String {
        switch type {
        case .levelUp: return "arrow.up.circle.fill"
        case .badgeUnlock: return "star.fill"
        case .streakMilestone: return "flame.fill"
        case .questComplete: return "checkmark.circle.fill"
        case .allQuestsComplete: return "trophy.fill"
        case .xpBonus: return "sparkles"
        case .neloMilestone: return "chart.line.uptrend.xyaxis"
        case .perfectDay: return "sun.max.fill"
        case .secretUnlock: return "lock.open.fill"
        }
    }
}
