// CosmoOS/UI/Sanctuary/SanctuaryAnimationChoreographer.swift
// Sanctuary Animation Choreographer - Apple-grade coordinated animation sequences
// Phase 1 Foundation: Cinematic entry, transitions, and real-time animation orchestration

import SwiftUI
import Combine

// MARK: - Animation State

/// Represents the current state of the Sanctuary animation system
public enum SanctuaryAnimationPhase: Equatable {
    case idle
    case entering
    case active
    case transitioning(to: LevelDimension)
    case exiting
}

/// Individual element animation states
public struct ElementAnimationState: Equatable {
    public var opacity: Double
    public var scale: CGFloat
    public var offset: CGSize
    public var rotation: Double

    public static let hidden = ElementAnimationState(
        opacity: 0,
        scale: 0.3,
        offset: CGSize(width: 0, height: 20),
        rotation: 0
    )

    public static let visible = ElementAnimationState(
        opacity: 1,
        scale: 1.0,
        offset: .zero,
        rotation: 0
    )

    public static let dimmed = ElementAnimationState(
        opacity: 0.3,
        scale: 0.95,
        offset: .zero,
        rotation: 0
    )
}

// MARK: - Animation Choreographer

/// Orchestrates all Sanctuary animations with Apple-grade timing and coordination
/// This class manages:
/// - Entry sequences (staggered appearance of elements)
/// - Dimension transitions (zoom-in/zoom-out)
/// - Continuous animations (breathing, rotation, glow)
/// - Real-time data-driven animations (XP updates, level ups)
@MainActor
public final class SanctuaryAnimationChoreographer: ObservableObject {

    // MARK: - Published State

    /// Current animation phase
    @Published public private(set) var phase: SanctuaryAnimationPhase = .idle

    /// Background animation state
    @Published public private(set) var backgroundState = ElementAnimationState.hidden

    /// Hero orb animation state
    @Published public private(set) var heroOrbState = ElementAnimationState.hidden

    /// Dimension orbs animation states (indexed by dimension)
    @Published public private(set) var dimensionOrbStates: [LevelDimension: ElementAnimationState] = [:]

    /// Insight carousel animation state
    @Published public private(set) var insightState = ElementAnimationState.hidden

    /// Currently focused dimension (for zoom transitions)
    @Published public private(set) var focusedDimension: LevelDimension?

    // MARK: - Continuous Animation State

    /// Master animation phase (0.0 - continuous, used for breathing/rotation)
    @Published public private(set) var animationPhase: Double = 0

    /// Hero orb breathing scale
    @Published public private(set) var heroBreathingScale: CGFloat = 1.0

    /// Hero orb inner rotation
    @Published public private(set) var heroInnerRotation: Double = 0

    /// Hero orb outer rotation
    @Published public private(set) var heroOuterRotation: Double = 0

    /// Dimension orb breathing scales
    @Published public private(set) var dimensionBreathingScales: [LevelDimension: CGFloat] = [:]

    /// Connection line glow intensity
    @Published public private(set) var connectionGlowIntensity: Double = 0.3

    // MARK: - Special Animation State

    /// Level up celebration active
    @Published public private(set) var isLevelUpActive = false

    /// XP burst animation active
    @Published public private(set) var isXPBurstActive = false

    /// Currently animating XP amount
    @Published public private(set) var animatingXPAmount: Int64 = 0

    // MARK: - Private Properties

    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hasCompletedInitialEntry = false

    // MARK: - Initialization

    public init() {
        // Initialize dimension orb states
        for dimension in LevelDimension.allCases {
            dimensionOrbStates[dimension] = .hidden
            dimensionBreathingScales[dimension] = 1.0
        }
    }

    // MARK: - Computed Properties

    /// Background opacity convenience accessor
    public var backgroundOpacity: Double {
        backgroundState.opacity
    }

    /// Dimensions opacity convenience accessor (average of all dimension orb opacities)
    public var dimensionsOpacity: Double {
        let opacities = dimensionOrbStates.values.map { $0.opacity }
        guard !opacities.isEmpty else { return 0 }
        return opacities.reduce(0, +) / Double(opacities.count)
    }

    /// Alias for heroBreathingScale (view compatibility)
    public var breathingScale: CGFloat { heroBreathingScale }

    /// Hero orb scale from state
    public var heroScale: CGFloat { heroOrbState.scale }

    /// Hero orb opacity from state
    public var heroOpacity: Double { heroOrbState.opacity }

    // MARK: - Async Entry Methods

    /// Play entry sequence (async wrapper)
    @MainActor
    public func playEntrySequence() async {
        startEntrySequence()
    }

    /// Pulse the hero orb (for feedback effects)
    public func pulseHeroOrb() {
        // Create a quick pulse effect
        withAnimation(.easeInOut(duration: 0.2)) {
            heroBreathingScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.heroBreathingScale = 1.0
            }
        }
    }

    // MARK: - Entry Sequence

    /// Start the cinematic entry sequence for Sanctuary
    /// This choreographs the appearance of all elements in a staggered, cinematic manner
    public func startEntrySequence() {
        guard phase == .idle else { return }
        phase = .entering

        // Reset all states to hidden
        resetToHidden()

        // Phase 1: Background fades in (0-600ms)
        withAnimation(.easeOut(duration: SanctuaryDurations.backgroundEntry)) {
            backgroundState = .visible
        }

        // Phase 2: Hero orb springs in (200-1000ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            withAnimation(SanctuarySprings.heroEntry) {
                self?.heroOrbState = .visible
            }
        }

        // Phase 3: Dimension orbs appear with stagger (500-1100ms)
        for (index, dimension) in LevelDimension.allCases.enumerated() {
            let delay = 0.5 + (Double(index) * SanctuaryDurations.staggerDelay)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(SanctuarySprings.staggered(index: index)) {
                    self?.dimensionOrbStates[dimension] = .visible
                }
            }
        }

        // Phase 4: Insights slide up (800-1200ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            withAnimation(SanctuarySprings.smooth) {
                self?.insightState = .visible
            }
        }

        // Mark entry complete and start continuous animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.phase = .active
            self?.hasCompletedInitialEntry = true
            self?.startContinuousAnimations()
        }
    }

    /// Exit sequence - reverse of entry
    public func startExitSequence(completion: (() -> Void)? = nil) {
        guard phase == .active else { return }
        phase = .exiting

        // Stop continuous animations
        stopContinuousAnimations()

        // Reverse order: insights first
        withAnimation(SanctuarySprings.smooth) {
            insightState = .hidden
        }

        // Dimension orbs (reverse stagger)
        for (index, dimension) in LevelDimension.allCases.reversed().enumerated() {
            let delay = 0.1 + (Double(index) * 0.03)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(SanctuarySprings.smooth) {
                    self?.dimensionOrbStates[dimension] = .hidden
                }
            }
        }

        // Hero orb
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            withAnimation(SanctuarySprings.smooth) {
                self?.heroOrbState = .hidden
            }
        }

        // Background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) {
                self?.backgroundState = .hidden
            }
        }

        // Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.phase = .idle
            completion?()
        }
    }

    // MARK: - Dimension Transitions

    /// Zoom into a specific dimension for detail view
    public func zoomToDimension(_ dimension: LevelDimension) {
        guard phase == .active else { return }
        phase = .transitioning(to: dimension)
        focusedDimension = dimension

        // Dim other elements
        withAnimation(SanctuarySprings.cinematic) {
            heroOrbState = .dimmed
            insightState = .hidden

            for dim in LevelDimension.allCases {
                if dim == dimension {
                    // Selected dimension grows and moves to center
                    dimensionOrbStates[dim] = ElementAnimationState(
                        opacity: 1.0,
                        scale: 2.0,
                        offset: .zero,
                        rotation: 0
                    )
                } else {
                    // Other dimensions fade out
                    dimensionOrbStates[dim] = .dimmed
                }
            }
        }
    }

    /// Return from dimension detail to overview
    public func returnToOverview() {
        guard case .transitioning = phase else { return }

        withAnimation(SanctuarySprings.cinematic) {
            heroOrbState = .visible
            insightState = .visible
            focusedDimension = nil

            for dimension in LevelDimension.allCases {
                dimensionOrbStates[dimension] = .visible
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.phase = .active
        }
    }

    // MARK: - Continuous Animations

    /// Start the continuous ambient animations (breathing, rotation, glow)
    public func startContinuousAnimations() {
        // Stop any existing timer
        stopContinuousAnimations()

        // PERFORMANCE FIX: Use very low refresh rate for phase updates.
        // The actual animations (breathing, rotation) use SwiftUI's Core Animation system.
        // This timer only updates animationPhase for subtle ambient glow effects.
        // 2fps is sufficient — these are slow, ambient effects not user-interactive.
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateContinuousAnimations()
            }
        }

        // Start breathing animations (uses SwiftUI animation system - no timer needed)
        startBreathingAnimations()

        // Start rotation animations (uses SwiftUI animation system - no timer needed)
        startRotationAnimations()
    }

    /// Stop continuous animations
    public func stopContinuousAnimations() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateContinuousAnimations() {
        // Update master phase (wraps around) - used for any phase-based effects
        animationPhase += 0.5 // 2fps update rate, 0.5 increment per tick

        // Only update glow if value changed significantly to avoid unnecessary publishes
        let newGlow = 0.3 + sin(animationPhase * 0.5) * 0.1
        if abs(newGlow - connectionGlowIntensity) > 0.02 {
            connectionGlowIntensity = newGlow
        }
    }

    private func startBreathingAnimations() {
        // Hero breathing - slow, subtle
        withAnimation(
            .easeInOut(duration: SanctuaryDurations.breathingCycle)
            .repeatForever(autoreverses: true)
        ) {
            heroBreathingScale = 1.03
        }

        // Dimension orbs breathing - slightly offset from each other
        for (index, dimension) in LevelDimension.allCases.enumerated() {
            let delay = Double(index) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(
                    .easeInOut(duration: SanctuaryDurations.breathingCycle + Double(index) * 0.2)
                    .repeatForever(autoreverses: true)
                ) {
                    self?.dimensionBreathingScales[dimension] = 1.02
                }
            }
        }
    }

    private func startRotationAnimations() {
        // Hero inner rotation (slow)
        withAnimation(.linear(duration: SanctuaryDurations.rotationMedium).repeatForever(autoreverses: false)) {
            heroInnerRotation = 360
        }

        // Hero outer rotation (slower, opposite direction)
        withAnimation(.linear(duration: SanctuaryDurations.rotationSlow).repeatForever(autoreverses: false)) {
            heroOuterRotation = -360
        }
    }

    // MARK: - Special Animations

    /// Trigger level up celebration animation
    public func triggerLevelUp(from oldLevel: Int, to newLevel: Int, dimension: LevelDimension? = nil) {
        guard !isLevelUpActive else { return }
        isLevelUpActive = true

        // Phase 1: Build up (0-500ms)
        // Dim background, accelerate rotations
        withAnimation(SanctuarySprings.smooth) {
            backgroundState = ElementAnimationState(
                opacity: 0.7,
                scale: 1.0,
                offset: .zero,
                rotation: 0
            )
        }

        // Phase 2: Flash (500-700ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            withAnimation(SanctuarySprings.elastic) {
                if let dimension = dimension {
                    self?.dimensionOrbStates[dimension] = ElementAnimationState(
                        opacity: 1.0,
                        scale: 1.3,
                        offset: .zero,
                        rotation: 0
                    )
                } else {
                    self?.heroOrbState = ElementAnimationState(
                        opacity: 1.0,
                        scale: 1.3,
                        offset: .zero,
                        rotation: 0
                    )
                }
            }
        }

        // Phase 3: Settle (700-2500ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            withAnimation(SanctuarySprings.bouncy) {
                self?.backgroundState = .visible
                if let dimension = dimension {
                    self?.dimensionOrbStates[dimension] = .visible
                } else {
                    self?.heroOrbState = .visible
                }
            }
        }

        // Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.isLevelUpActive = false
        }
    }

    /// Trigger XP burst animation
    public func triggerXPBurst(amount: Int64, source: LevelDimension? = nil) {
        guard !isXPBurstActive else { return }
        isXPBurstActive = true
        animatingXPAmount = amount

        // Quick pulse on source dimension or hero
        if let dimension = source {
            withAnimation(SanctuarySprings.orbPulse) {
                dimensionBreathingScales[dimension] = 1.1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                withAnimation(SanctuarySprings.smooth) {
                    self?.dimensionBreathingScales[dimension] = 1.02
                }
            }
        } else {
            withAnimation(SanctuarySprings.orbPulse) {
                heroBreathingScale = 1.1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                withAnimation(SanctuarySprings.smooth) {
                    self?.heroBreathingScale = 1.03
                }
            }
        }

        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isXPBurstActive = false
            self?.animatingXPAmount = 0
        }
    }

    /// Pulse a specific dimension orb (for data updates)
    public func pulseDimension(_ dimension: LevelDimension) {
        withAnimation(SanctuarySprings.orbPulse) {
            dimensionBreathingScales[dimension] = 1.08
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            withAnimation(SanctuarySprings.smooth) {
                self?.dimensionBreathingScales[dimension] = 1.02
            }
        }
    }

    // MARK: - Utility

    /// Reset all animation states to hidden
    private func resetToHidden() {
        backgroundState = .hidden
        heroOrbState = .hidden
        insightState = .hidden
        for dimension in LevelDimension.allCases {
            dimensionOrbStates[dimension] = .hidden
        }

        // Reset continuous animation values
        heroBreathingScale = 1.0
        heroInnerRotation = 0
        heroOuterRotation = 0
        for dimension in LevelDimension.allCases {
            dimensionBreathingScales[dimension] = 1.0
        }
    }

    /// Reset choreographer for reuse
    public func reset() {
        stopContinuousAnimations()
        phase = .idle
        focusedDimension = nil
        isLevelUpActive = false
        isXPBurstActive = false
        hasCompletedInitialEntry = false
        resetToHidden()
    }
}

// MARK: - View Modifiers

/// Apply choreographed animation state to a view
public struct ChoreographedAnimationModifier: ViewModifier {
    let state: ElementAnimationState

    public func body(content: Content) -> some View {
        content
            .opacity(state.opacity)
            .scaleEffect(state.scale)
            .offset(state.offset)
            .rotationEffect(.degrees(state.rotation))
    }
}

extension View {
    /// Apply animation state from choreographer
    public func choreographedAnimation(_ state: ElementAnimationState) -> some View {
        modifier(ChoreographedAnimationModifier(state: state))
    }

    /// Apply dimension orb animation from choreographer
    public func dimensionOrbAnimation(
        choreographer: SanctuaryAnimationChoreographer,
        dimension: LevelDimension
    ) -> some View {
        let state = choreographer.dimensionOrbStates[dimension] ?? .hidden
        let breathingScale = choreographer.dimensionBreathingScales[dimension] ?? 1.0

        return self
            .opacity(state.opacity)
            .scaleEffect(state.scale * breathingScale)
            .offset(state.offset)
    }

    /// Apply hero orb animation from choreographer
    public func heroOrbAnimation(choreographer: SanctuaryAnimationChoreographer) -> some View {
        self
            .opacity(choreographer.heroOrbState.opacity)
            .scaleEffect(choreographer.heroOrbState.scale * choreographer.heroBreathingScale)
            .offset(choreographer.heroOrbState.offset)
    }
}

// MARK: - Particle System State

/// State for XP particle burst animations in Sanctuary
public struct SanctuaryXPParticle: Identifiable {
    public let id = UUID()
    public var position: CGPoint
    public var velocity: CGVector
    public var opacity: Double
    public var scale: CGFloat
    public var rotation: Double

    public init(origin: CGPoint) {
        let angle = Double.random(in: 0...(2 * .pi))
        let speed = Double.random(in: 50...150)

        self.position = origin
        self.velocity = CGVector(
            dx: cos(angle) * speed,
            dy: sin(angle) * speed - 80 // Bias upward
        )
        self.opacity = 1.0
        self.scale = CGFloat.random(in: 0.3...1.0)
        self.rotation = Double.random(in: 0...360)
    }

    public mutating func update(deltaTime: TimeInterval) {
        position.x += velocity.dx * deltaTime
        position.y += velocity.dy * deltaTime

        // Gravity
        velocity.dy += 200 * deltaTime

        // Fade out
        opacity -= deltaTime * 1.5
        opacity = max(0, opacity)

        // Shrink
        scale -= CGFloat(deltaTime * 0.5)
        scale = max(0, scale)

        // Spin
        rotation += 180 * deltaTime
    }
}

/// Particle system manager for XP bursts and celebrations
@MainActor
public final class SanctuaryParticleSystem: ObservableObject {
    @Published public private(set) var particles: [SanctuaryXPParticle] = []

    private var updateTimer: Timer?

    public init() {}

    /// Spawn particles at a position
    public func spawnBurst(at position: CGPoint, count: Int = 20) {
        let newParticles = (0..<count).map { _ in SanctuaryXPParticle(origin: position) }
        particles.append(contentsOf: newParticles)

        // Start update loop if not running
        if updateTimer == nil {
            startUpdateLoop()
        }
    }

    private func startUpdateLoop() {
        // PERFORMANCE FIX: Run particle updates at 30fps instead of 60fps
        // Particles are small enough that 30fps looks smooth
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.update(deltaTime: 1.0 / 30.0)
            }
        }
    }

    private func update(deltaTime: TimeInterval) {
        // Update all particles
        for index in particles.indices {
            particles[index].update(deltaTime: deltaTime)
        }

        // Remove dead particles
        particles.removeAll { $0.opacity <= 0 || $0.scale <= 0 }

        // Stop update loop if no particles
        if particles.isEmpty {
            updateTimer?.invalidate()
            updateTimer = nil
        }
    }

    public func reset() {
        particles.removeAll()
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryAnimationChoreographer_Previews: PreviewProvider {
    static var previews: some View {
        SanctuaryAnimationPreview()
            .preferredColorScheme(.dark)
    }

    struct SanctuaryAnimationPreview: View {
        @StateObject private var choreographer = SanctuaryAnimationChoreographer()

        var body: some View {
            ZStack {
                SanctuaryColors.voidPrimary.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Demo orb
                    Circle()
                        .fill(SanctuaryColors.heroPrimary)
                        .frame(width: 100, height: 100)
                        .heroOrbAnimation(choreographer: choreographer)

                    // Controls
                    VStack(spacing: 16) {
                        Button("Start Entry") {
                            choreographer.startEntrySequence()
                        }

                        Button("Level Up") {
                            choreographer.triggerLevelUp(from: 5, to: 6)
                        }

                        Button("XP Burst") {
                            choreographer.triggerXPBurst(amount: 150)
                        }

                        Button("Reset") {
                            choreographer.reset()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
    }
}
#endif
