// CosmoOS/Core/CosmicHaptics.swift
// Apple-grade haptic feedback system using CoreHaptics
// Choreographed patterns for premium tactile experience

import CoreHaptics
import AppKit
import SwiftUI

// MARK: - CosmicHaptics Engine
/// Centralized haptic feedback system for CosmoOS.
/// Provides choreographed haptic patterns that match the visual motion design.
///
/// Usage:
/// ```swift
/// CosmicHaptics.shared.play(.cardPickUp)
/// CosmicHaptics.shared.play(.success)
/// ```
final class CosmicHaptics: @unchecked Sendable {
    // ═══════════════════════════════════════════════════════════════
    // SINGLETON
    // ═══════════════════════════════════════════════════════════════

    static let shared = CosmicHaptics()

    // ═══════════════════════════════════════════════════════════════
    // PROPERTIES
    // ═══════════════════════════════════════════════════════════════

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    // ═══════════════════════════════════════════════════════════════
    // HAPTIC PATTERNS - Pre-defined patterns
    // ═══════════════════════════════════════════════════════════════

    enum Pattern {
        /// Light tap for selections, toggles
        case selection

        /// Card/block picked up - gentle lift feel
        case cardPickUp

        /// Card/block dropped - satisfying landing
        case cardDrop

        /// Successful action - ascending double tap
        case success

        /// Error occurred - sharp buzz
        case error

        /// Warning/attention needed - medium pulse
        case warning

        /// Drag threshold crossed - subtle notch
        case threshold

        /// Menu appeared - soft pop
        case menuAppear

        /// Delete action - descending fade
        case delete

        /// Focus mode entered - breathing pulse
        case focusEnter

        /// Focus mode exited - quick release
        case focusExit

        /// Typing impact (use sparingly)
        case keystroke
    }

    // ═══════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════

    private init() {
        checkHapticSupport()
        prepareEngine()
    }

    private func checkHapticSupport() {
        let capabilities = CHHapticEngine.capabilitiesForHardware()
        supportsHaptics = capabilities.supportsHaptics
    }

    private func prepareEngine() {
        guard supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()

            // Handle engine reset
            engine?.resetHandler = { [weak self] in
                do {
                    try self?.engine?.start()
                } catch {
                    print("CosmicHaptics: Failed to restart engine: \(error)")
                }
            }

            // Handle engine stopped
            engine?.stoppedHandler = { reason in
                print("CosmicHaptics: Engine stopped - \(reason)")
            }

            try engine?.start()
        } catch {
            print("CosmicHaptics: Failed to initialize engine: \(error)")
            supportsHaptics = false
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═══════════════════════════════════════════════════════════════

    /// Play a pre-defined haptic pattern
    func play(_ pattern: Pattern) {
        guard supportsHaptics, let engine = engine else { return }

        do {
            let events = createEvents(for: pattern)
            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("CosmicHaptics: Failed to play pattern: \(error)")
        }
    }

    /// Play a custom haptic with specific intensity and sharpness
    func playCustom(intensity: Float, sharpness: Float, duration: TimeInterval = 0.1) {
        guard supportsHaptics, let engine = engine else { return }

        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0,
                duration: duration
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("CosmicHaptics: Failed to play custom haptic: \(error)")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // PATTERN DEFINITIONS
    // ═══════════════════════════════════════════════════════════════

    private func createEvents(for pattern: Pattern) -> [CHHapticEvent] {
        switch pattern {
        case .selection:
            // Single light tap
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                )
            ]

        case .cardPickUp:
            // Gentle lift - soft transient followed by subtle continuous
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0.02,
                    duration: 0.08
                )
            ]

        case .cardDrop:
            // Satisfying landing - initial impact + bounce
            return [
                // Main impact
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                ),
                // Bounce
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    ],
                    relativeTime: 0.08
                )
            ]

        case .success:
            // Ascending double tap - celebratory
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0.1
                )
            ]

        case .error:
            // Sharp buzz - attention-getting but not harsh
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    ],
                    relativeTime: 0.05,
                    duration: 0.1
                )
            ]

        case .warning:
            // Medium pulse - noticeable but not alarming
            return [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0,
                    duration: 0.15
                )
            ]

        case .threshold:
            // Subtle notch - feedback for crossing drag thresholds
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0
                )
            ]

        case .menuAppear:
            // Soft pop - gentle menu appearance
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: 0
                )
            ]

        case .delete:
            // Descending fade - item being removed
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: 0.08
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0.15
                )
            ]

        case .focusEnter:
            // Breathing pulse - immersive entry
            return [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0,
                    duration: 0.2
                ),
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    ],
                    relativeTime: 0.15,
                    duration: 0.15
                )
            ]

        case .focusExit:
            // Quick release - snapping back to reality
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                )
            ]

        case .keystroke:
            // Very light tap - use sparingly for typewriter feel
            return [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                    ],
                    relativeTime: 0
                )
            ]
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════════

    /// Stop the haptic engine (call when app enters background)
    func stop() {
        engine?.stop()
    }

    /// Restart the haptic engine (call when app enters foreground)
    func restart() {
        do {
            try engine?.start()
        } catch {
            print("CosmicHaptics: Failed to restart engine: \(error)")
        }
    }
}

// MARK: - SwiftUI View Extension
extension View {
    /// Trigger haptic feedback when a value changes
    func cosmicHaptic<T: Equatable>(_ pattern: CosmicHaptics.Pattern, trigger: T) -> some View {
        self.onChange(of: trigger) { _, _ in
            CosmicHaptics.shared.play(pattern)
        }
    }

    /// Trigger haptic feedback on tap
    func cosmicHapticOnTap(_ pattern: CosmicHaptics.Pattern = .selection) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                CosmicHaptics.shared.play(pattern)
            }
        )
    }
}
