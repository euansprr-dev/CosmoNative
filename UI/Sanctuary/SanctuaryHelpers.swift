// CosmoOS/UI/Sanctuary/SanctuaryHelpers.swift
// Sanctuary Helpers - Extensions and utilities for the Sanctuary UI

import SwiftUI
#if os(iOS)
import UIKit
#endif

// Note: Color(hex:) is defined in Core/Theme.swift

// MARK: - View Extensions

extension View {
    /// Apply a glow effect
    func glow(color: Color, radius: CGFloat = 10) -> some View {
        self
            .shadow(color: color.opacity(0.5), radius: radius / 2)
            .shadow(color: color.opacity(0.3), radius: radius)
            .shadow(color: color.opacity(0.1), radius: radius * 2)
    }

    /// Apply a pulsing animation
    func pulse(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 2.0) -> some View {
        modifier(SanctuaryPulseModifier(minScale: minScale, maxScale: maxScale, duration: duration))
    }

    /// Apply floating animation
    func floating(offset: CGFloat = 5, duration: Double = 3.0) -> some View {
        modifier(FloatingModifier(offset: offset, duration: duration))
    }
}

// MARK: - Animation Modifiers

struct SanctuaryPulseModifier: ViewModifier {
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double

    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = scale == minScale ? maxScale : minScale
                }
            }
    }
}

struct FloatingModifier: ViewModifier {
    let offset: CGFloat
    let duration: Double

    @State private var yOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: yOffset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    yOffset = offset
                }
            }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 3)
                    .mask(content)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Haptic Feedback

enum SanctuaryHapticType {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case selection
}

#if os(iOS)
func triggerSanctuaryHaptic(_ type: SanctuaryHapticType) {
    switch type {
    case .light:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .heavy:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .success:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning:
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .error:
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .selection:
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
#else
func triggerSanctuaryHaptic(_ type: SanctuaryHapticType) {
    // Haptics not available on macOS
}
#endif

// MARK: - Gradient Presets

struct GradientPresets {
    static let sanctuary = LinearGradient(
        colors: [
            Color(hex: "#0A0A0F"),
            Color(hex: "#0F0A1A"),
            Color(hex: "#0A0F1A")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cognitive = LinearGradient(
        colors: [Color(hex: "#6366F1"), Color(hex: "#4338CA")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let creative = LinearGradient(
        colors: [Color(hex: "#EC4899"), Color(hex: "#BE185D")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let physiological = LinearGradient(
        colors: [Color(hex: "#EF4444"), Color(hex: "#B91C1C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let behavioral = LinearGradient(
        colors: [Color(hex: "#F97316"), Color(hex: "#C2410C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let knowledge = LinearGradient(
        colors: [Color(hex: "#22C55E"), Color(hex: "#15803D")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let reflection = LinearGradient(
        colors: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func forDimension(_ dimension: LevelDimension) -> LinearGradient {
        switch dimension {
        case .cognitive: return cognitive
        case .creative: return creative
        case .physiological: return physiological
        case .behavioral: return behavioral
        case .knowledge: return knowledge
        case .reflection: return reflection
        }
    }
}

// MARK: - Animation Choreographer

/// Coordinates complex multi-element animations
@MainActor
public final class AnimationChoreographer: ObservableObject {
    @Published public var heroOrbAppeared = false
    @Published public var dimensionOrbsAppeared = false
    @Published public var insightsAppeared = false
    @Published public var backgroundAppeared = false

    public var allAppeared: Bool {
        heroOrbAppeared && dimensionOrbsAppeared && insightsAppeared && backgroundAppeared
    }

    public func startEntrySequence() {
        // Background fades in first
        withAnimation(.easeOut(duration: 0.6)) {
            backgroundAppeared = true
        }

        // Hero orb appears with spring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                self.heroOrbAppeared = true
            }
        }

        // Dimension orbs appear one by one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.dimensionOrbsAppeared = true
            }
        }

        // Insights slide up last
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.insightsAppeared = true
            }
        }
    }

    public func startExitSequence(completion: @escaping () -> Void) {
        // Reverse order
        withAnimation(.easeIn(duration: 0.2)) {
            insightsAppeared = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.2)) {
                self.dimensionOrbsAppeared = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                self.heroOrbAppeared = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.2)) {
                self.backgroundAppeared = false
            }
            completion()
        }
    }

    public func reset() {
        heroOrbAppeared = false
        dimensionOrbsAppeared = false
        insightsAppeared = false
        backgroundAppeared = false
    }
}

// MARK: - Number Formatting

extension Int {
    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Int64 {
    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    var abbreviated: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return formatted
    }
}

extension Double {
    var percentFormatted: String {
        String(format: "%.0f%%", self * 100)
    }

    var signedPercentFormatted: String {
        let prefix = self >= 0 ? "+" : ""
        return prefix + String(format: "%.0f%%", self * 100)
    }
}
