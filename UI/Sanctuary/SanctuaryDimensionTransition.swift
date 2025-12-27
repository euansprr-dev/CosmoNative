// CosmoOS/UI/Sanctuary/SanctuaryDimensionTransition.swift
// Dimension Zoom Transition - Cinematic transitions between home and dimension views
// Phase 2: Following SANCTUARY_UI_SPEC_V2.md section 2.6

import SwiftUI

// MARK: - Transition State

/// State machine for dimension transitions
public enum SanctuaryTransitionState: Equatable {
    case home                           // Default home view
    case transitioning(LevelDimension)  // Animating to dimension
    case dimension(LevelDimension)      // Showing dimension view
    case returning                      // Animating back to home
}

// MARK: - Transition Manager

/// Manages cinematic dimension zoom transitions
@MainActor
public final class SanctuaryTransitionManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: SanctuaryTransitionState = .home
    @Published public private(set) var transitionProgress: Double = 0

    // MARK: - Animation State

    // Forward transition (800ms total)
    @Published public var heroOpacity: Double = 1.0
    @Published public var heroScale: CGFloat = 1.0
    @Published public var otherOrbsOpacity: Double = 1.0
    @Published public var otherOrbsScale: CGFloat = 1.0
    @Published public var connectionLinesOpacity: Double = 1.0
    @Published public var insightStreamOffset: CGFloat = 0
    @Published public var backgroundTint: Color = .clear
    @Published public var headerText: String = "SANCTUARY"

    // Selected orb animation
    @Published public var selectedOrbScale: CGFloat = 1.0
    @Published public var selectedOrbPosition: CGPoint = .zero
    @Published public var selectedOrbTargetPosition: CGPoint = .zero

    // Dimension content
    @Published public var dimensionContentOpacity: Double = 0
    @Published public var dimensionContentOffset: CGFloat = 20

    // MARK: - Timing Constants

    private enum Timing {
        static let forwardDuration: Double = 0.8  // 800ms
        static let reverseDuration: Double = 0.6  // 600ms

        // Forward sequence timing (relative to start)
        static let hapticDelay: Double = 0
        static let orbScaleDelay: Double = 0
        static let otherOrbsFadeDelay: Double = 0.05
        static let expansionDelay: Double = 0.1
        static let backgroundShiftDelay: Double = 0.2
        static let connectionsFadeDelay: Double = 0.35
        static let insightSlideDelay: Double = 0.35
        static let hudRenderDelay: Double = 0.5
        static let headerTransitionDelay: Double = 0.7
    }

    // MARK: - Transition Forward

    /// Begin transition to a dimension (800ms sequence)
    public func transitionToDimension(
        _ dimension: LevelDimension,
        fromPosition: CGPoint,
        toPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)  // Center of screen
    ) async {
        guard case .home = state else { return }

        state = .transitioning(dimension)
        selectedOrbPosition = fromPosition
        selectedOrbTargetPosition = toPosition

        // T=0ms: Haptic + initial scale
        // (Haptic would be triggered by the caller)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            selectedOrbScale = 1.15
        }

        // T=50ms: Other orbs begin fading
        try? await Task.sleep(nanoseconds: 50_000_000)
        withAnimation(.easeOut(duration: 0.3)) {
            otherOrbsOpacity = 0
            otherOrbsScale = 0.9
        }

        // T=100ms: Selected orb begins expansion
        try? await Task.sleep(nanoseconds: 50_000_000)
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedOrbScale = 8.0  // Fills viewport
            heroOpacity = 0
        }

        // T=200ms: Background shift
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeInOut(duration: 0.4)) {
            backgroundTint = SanctuaryColors.Dimensions.color(for: dimension).opacity(0.1)
        }

        // T=350ms: Connection lines fade, insight stream slides
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            connectionLinesOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.3)) {
            insightStreamOffset = 200
        }

        // T=500ms: Dimension HUD begins rendering
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.easeOut(duration: 0.25)) {
            dimensionContentOpacity = 1
            dimensionContentOffset = 0
        }

        // T=700ms: Header transitions
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeInOut(duration: 0.15)) {
            headerText = dimension.displayName.uppercased()
        }

        // T=800ms: Transition complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        state = .dimension(dimension)
        transitionProgress = 1.0
    }

    // MARK: - Transition Back

    /// Return to home view (600ms sequence)
    public func transitionToHome() async {
        guard case .dimension = state else { return }

        state = .returning

        // T=0ms: Dimension content begins fading
        withAnimation(.easeIn(duration: 0.15)) {
            dimensionContentOpacity = 0
            dimensionContentOffset = 20
        }

        // T=100ms: Hero core begins appearing
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            heroOpacity = 1
        }

        // T=200ms: Selected orb contracts
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedOrbScale = 1.0
        }

        // T=300ms: Other orbs fade in, connections appear
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            otherOrbsOpacity = 1
            otherOrbsScale = 1.0
            connectionLinesOpacity = 1
            backgroundTint = .clear
        }

        // T=500ms: Insight stream slides up, header reverts
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.15)) {
            insightStreamOffset = 0
            headerText = "SANCTUARY"
        }

        // T=600ms: Transition complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        state = .home
        transitionProgress = 0
    }

    // MARK: - Reset

    /// Reset all state to defaults
    public func reset() {
        state = .home
        transitionProgress = 0
        heroOpacity = 1.0
        heroScale = 1.0
        otherOrbsOpacity = 1.0
        otherOrbsScale = 1.0
        connectionLinesOpacity = 1.0
        insightStreamOffset = 0
        backgroundTint = .clear
        headerText = "SANCTUARY"
        selectedOrbScale = 1.0
        dimensionContentOpacity = 0
        dimensionContentOffset = 20
    }
}

// MARK: - Transition Modifier

/// View modifier that applies transition animations
@MainActor
struct SanctuaryTransitionModifier: ViewModifier {
    @ObservedObject var manager: SanctuaryTransitionManager
    let role: TransitionRole

    enum TransitionRole {
        case hero
        case otherOrb
        case selectedOrb(LevelDimension)
        case connectionLines
        case insightStream
        case dimensionContent
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .hero:
            content
                .opacity(manager.heroOpacity)
                .scaleEffect(manager.heroScale)

        case .otherOrb:
            content
                .opacity(manager.otherOrbsOpacity)
                .scaleEffect(manager.otherOrbsScale)

        case .selectedOrb(let dimension):
            if case .transitioning(dimension) = manager.state,
               manager.selectedOrbScale > 1.5 {
                // During expansion, orb fills viewport
                content
                    .scaleEffect(manager.selectedOrbScale)
            } else if case .dimension(dimension) = manager.state {
                // Hidden when dimension view is shown
                content.opacity(0)
            } else {
                content
                    .scaleEffect(manager.selectedOrbScale)
            }

        case .connectionLines:
            content.opacity(manager.connectionLinesOpacity)

        case .insightStream:
            content.offset(y: manager.insightStreamOffset)

        case .dimensionContent:
            content
                .opacity(manager.dimensionContentOpacity)
                .offset(y: manager.dimensionContentOffset)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply transition animation for hero orb
    public func sanctuaryTransitionHero(
        manager: SanctuaryTransitionManager
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .hero))
    }

    /// Apply transition animation for other (non-selected) orbs
    public func sanctuaryTransitionOther(
        manager: SanctuaryTransitionManager
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .otherOrb))
    }

    /// Apply transition animation for the selected dimension orb
    public func sanctuaryTransitionSelected(
        manager: SanctuaryTransitionManager,
        dimension: LevelDimension
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .selectedOrb(dimension)))
    }

    /// Apply transition animation for connection lines
    public func sanctuaryTransitionConnections(
        manager: SanctuaryTransitionManager
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .connectionLines))
    }

    /// Apply transition animation for insight stream
    public func sanctuaryTransitionInsights(
        manager: SanctuaryTransitionManager
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .insightStream))
    }

    /// Apply transition animation for dimension content
    public func sanctuaryTransitionContent(
        manager: SanctuaryTransitionManager
    ) -> some View {
        modifier(SanctuaryTransitionModifier(manager: manager, role: .dimensionContent))
    }
}

// MARK: - Transition Background

/// Animated background that tints during dimension transitions
public struct SanctuaryTransitionBackground: View {
    @ObservedObject var manager: SanctuaryTransitionManager

    public init(manager: SanctuaryTransitionManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            // Base void
            SanctuaryColors.Background.void
                .ignoresSafeArea()

            // Dimension tint overlay
            manager.backgroundTint
                .ignoresSafeArea()
                .blendMode(.overlay)

            // Edge vignette that intensifies during transition
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(manager.transitionProgress * 0.3)
                ],
                center: .center,
                startRadius: 200,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SanctuaryDimensionTransition_Previews: PreviewProvider {
    static var previews: some View {
        SanctuaryTransitionPreview()
    }

    struct SanctuaryTransitionPreview: View {
        @StateObject private var manager = SanctuaryTransitionManager()

        var body: some View {
            ZStack {
                SanctuaryTransitionBackground(manager: manager)

                VStack(spacing: 40) {
                    Text(manager.headerText)
                        .font(SanctuaryTypography.displayMedium)
                        .foregroundColor(.white)

                    // Simulated orbs
                    HStack(spacing: 60) {
                        ForEach(LevelDimension.allCases, id: \.self) { dimension in
                            Circle()
                                .fill(SanctuaryColors.Dimensions.color(for: dimension))
                                .frame(width: 60, height: 60)
                                .sanctuaryTransitionSelected(manager: manager, dimension: dimension)
                                .onTapGesture {
                                    Task {
                                        await manager.transitionToDimension(
                                            dimension,
                                            fromPosition: .zero
                                        )
                                    }
                                }
                        }
                    }
                    .sanctuaryTransitionOther(manager: manager)

                    if case .dimension(let dim) = manager.state {
                        VStack {
                            Text("\(dim.displayName) View")
                                .font(SanctuaryTypography.title)
                                .foregroundColor(.white)

                            Button("Back") {
                                Task {
                                    await manager.transitionToHome()
                                }
                            }
                            .foregroundColor(.white)
                        }
                        .sanctuaryTransitionContent(manager: manager)
                    }
                }
            }
        }
    }
}
#endif
