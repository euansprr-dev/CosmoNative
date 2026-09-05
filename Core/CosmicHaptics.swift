// Native trackpad feedback. Core Haptics capability checks exclude the Mac's
// built-in trackpad; NSHapticFeedbackManager is the platform's tactile API.
import AppKit
import SwiftUI

final class CosmicHaptics: Sendable {
    static let shared = CosmicHaptics()

    enum Pattern: Sendable {
        case selection, cardPickUp, cardDrop, success, error, warning
        case threshold, menuAppear, delete, focusEnter, focusExit, keystroke

        var native: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .selection, .threshold, .keystroke: return .alignment
            case .cardPickUp, .menuAppear, .focusEnter, .focusExit: return .levelChange
            default: return .generic
            }
        }
    }

    private init() {}

    func play(_ pattern: Pattern) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.perform(pattern) }
        } else {
            DispatchQueue.main.async { Self.perform(pattern) }
        }
    }

    @MainActor private static var lastFeedback: TimeInterval = -.infinity

    @MainActor private static func perform(_ pattern: Pattern) {
        guard NSApp.isActive,
              UserDefaults.standard.object(forKey: "haptics.enabled") as? Bool != false else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFeedback >= 0.05 else { return }
        lastFeedback = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern.native, performanceTime: .now)
    }

    /// Preserve the existing call sites using native discrete feedback.
    func playCustom(intensity: Float, sharpness: Float, duration: TimeInterval = 0.1) {
        guard intensity > 0 else { return }
        play(intensity < 0.4 ? .selection : .cardDrop)
    }

    // Native trackpad feedback has no persistent engine to keep awake.
    func stop() {}
    func restart() {}
}

extension View {
    func cosmicHaptic<T: Equatable>(_ pattern: CosmicHaptics.Pattern, trigger: T) -> some View {
        onChange(of: trigger) { _, _ in CosmicHaptics.shared.play(pattern) }
    }

    func cosmicHapticOnTap(_ pattern: CosmicHaptics.Pattern = .selection) -> some View {
        simultaneousGesture(TapGesture().onEnded { CosmicHaptics.shared.play(pattern) })
    }
}
