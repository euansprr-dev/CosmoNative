// CosmoOS/UI/Sanctuary/Systems/SanctuaryHaptics.swift
// Haptic feedback patterns for the Sanctuary experience
// Phase 9: Polish - Haptic Feedback System

import Foundation
import CoreHaptics
import AppKit
import os.log

// MARK: - Zoom Direction

public enum ZoomDirection: String, Codable, Sendable {
    case `in`
    case out
}

// MARK: - Haptics Engine

/// Central haptic feedback engine for Sanctuary.
/// Provides tactile feedback for interactions, achievements, and alerts.
///
/// Haptic Patterns:
/// - Selection: Light taps for node/element selection
/// - Panels: Medium feedback for UI panel interactions
/// - Insights: Success pattern for insight reveals
/// - XP: Quick taps for XP gains
/// - Level Up: Celebratory pattern for leveling up
/// - Alerts: Warning patterns for streaks/time-sensitive items
/// - Grail: Special celebratory pattern for grail discoveries
public final class SanctuaryHaptics: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = SanctuaryHaptics()

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cosmo.sanctuary", category: "Haptics")

    // Core Haptics engine (for custom patterns)
    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    // macOS Haptic Feedback Manager
    private let hapticPerformer = NSHapticFeedbackManager.defaultPerformer

    // State
    private var isEnabled: Bool = true
    private var hapticIntensity: Float = 1.0  // 0.0 - 1.0

    // MARK: - Initialization

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        // Check for haptics support
        let hapticCapability = CHHapticEngine.capabilitiesForHardware()
        supportsHaptics = hapticCapability.supportsHaptics

        guard supportsHaptics else {
            logger.info("Device does not support Core Haptics")
            return
        }

        do {
            engine = try CHHapticEngine()

            // Handle engine reset
            engine?.resetHandler = { [weak self] in
                self?.logger.info("Haptic engine reset")
                do {
                    try self?.engine?.start()
                } catch {
                    self?.logger.error("Failed to restart haptic engine: \(error.localizedDescription)")
                }
            }

            // Handle engine stop
            engine?.stoppedHandler = { [weak self] reason in
                self?.logger.info("Haptic engine stopped: \(reason.rawValue)")
            }

            try engine?.start()
            logger.info("Core Haptics engine started")

        } catch {
            logger.error("Failed to create haptic engine: \(error.localizedDescription)")
        }
    }

    // MARK: - macOS Haptic Feedback Helpers

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern, performanceTime: NSHapticFeedbackManager.PerformanceTime = .default) {
        guard isEnabled else { return }
        Task { @MainActor in
            hapticPerformer.perform(pattern, performanceTime: performanceTime)
        }
    }

    // MARK: - Standard Haptics

    /// Play haptic for node/element selection
    public func nodeSelect() {
        performHaptic(.generic)
    }

    /// Play haptic for panel open/close
    public func panelOpen() {
        performHaptic(.levelChange)
    }

    /// Play haptic for panel close
    public func panelClose() {
        performHaptic(.generic)
    }

    /// Play haptic for insight reveal
    public func insightReveal() {
        performHaptic(.levelChange)
    }

    /// Play haptic for dimension transition
    public func dimensionTransition() {
        performHaptic(.levelChange)
    }

    /// Play haptic for scroll/swipe selection
    public func scrollSelection() {
        performHaptic(.generic)
    }

    // MARK: - XP and Progression Haptics

    /// Play haptic pattern for XP gain (3 quick taps)
    public func xpGain(amount: Int) {
        guard isEnabled else { return }

        Task { @MainActor in
            // Quick triple tap pattern
            hapticPerformer.perform(.generic, performanceTime: .now)

            try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
            hapticPerformer.perform(.generic, performanceTime: .now)

            try? await Task.sleep(nanoseconds: 60_000_000)
            hapticPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Play haptic for level up (heavy + success)
    public func levelUp() {
        guard isEnabled else { return }

        Task { @MainActor in
            // Heavy impact first
            hapticPerformer.perform(.levelChange, performanceTime: .now)

            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

            // Success notification
            hapticPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    /// Play full level-up ceremony haptic sequence
    public func levelUpCeremony() async {
        guard isEnabled else { return }

        await MainActor.run {
            _ = Task { @MainActor in
                for _ in 0..<5 {
                    hapticPerformer.perform(.generic, performanceTime: .now)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                // Phase 2: Flash (heavy impact)
                hapticPerformer.perform(.levelChange, performanceTime: .now)

                try? await Task.sleep(nanoseconds: 100_000_000)

                // Phase 3: Celebration
                hapticPerformer.perform(.levelChange, performanceTime: .now)

                try? await Task.sleep(nanoseconds: 200_000_000)
                hapticPerformer.perform(.generic, performanceTime: .now)

                try? await Task.sleep(nanoseconds: 150_000_000)
                hapticPerformer.perform(.generic, performanceTime: .now)

                // Phase 4: Settle
                try? await Task.sleep(nanoseconds: 300_000_000)
                hapticPerformer.perform(.generic, performanceTime: .now)
            }
        }
    }

    // MARK: - Alert Haptics

    /// Play haptic for streak warning
    public func streakAlert() {
        performHaptic(.levelChange)
    }

    /// Play haptic for error/failure
    public func error() {
        performHaptic(.levelChange)
    }

    /// Play haptic for optimal window reminder
    public func optimalWindow() {
        guard isEnabled else { return }
        Task { @MainActor in
            // Gentle double tap
            hapticPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 100_000_000)
            hapticPerformer.perform(.generic, performanceTime: .now)
        }
    }

    // MARK: - Grail Discovery

    /// Play celebratory haptic for Grail discovery
    public func grailDiscovery() async {
        guard isEnabled, supportsHaptics, let engine = engine else {
            // Fallback to standard haptics
            await MainActor.run {
                hapticPerformer.perform(.levelChange, performanceTime: .now)
            }
            return
        }

        // Custom Core Haptics pattern for Grail discovery
        let pattern = try? grailDiscoveryPattern()
        guard let pattern = pattern else { return }

        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Failed to play grail haptic: \(error.localizedDescription)")
        }
    }

    private func grailDiscoveryPattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []

        // Golden shimmer effect (multiple quick transients)
        for i in 0..<8 {
            let time = Double(i) * 0.05
            let intensity = Float(i % 2 == 0 ? 0.8 : 0.5) * hapticIntensity

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: time
            )
            events.append(event)
        }

        // Sustained glow (continuous haptic)
        let glowEvent = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6 * hapticIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0.4,
            duration: 0.5
        )
        events.append(glowEvent)

        // Final burst
        let burstEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0 * hapticIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ],
            relativeTime: 0.9
        )
        events.append(burstEvent)

        return try CHHapticPattern(events: events, parameters: [])
    }

    // MARK: - Knowledge Graph Haptics

    /// Play haptic for knowledge node focus
    public func nodeFocus() {
        performHaptic(.generic)
    }

    /// Play haptic for knowledge graph zoom
    public func graphZoom(direction: ZoomDirection) {
        performHaptic(.generic)
    }

    /// Play haptic for cluster expansion
    public func clusterExpand() {
        guard isEnabled else { return }
        Task { @MainActor in
            // Soft expanding pattern
            hapticPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 80_000_000)
            hapticPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 80_000_000)
            hapticPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    // MARK: - Mood and Reflection Haptics

    /// Play haptic for mood log
    public func moodLog(valence: Double, energy: Double) {
        guard isEnabled else { return }

        Task { @MainActor in
            // Positive moods = generic, negative = level change
            if valence > 0 {
                hapticPerformer.perform(.generic, performanceTime: .now)
            } else {
                hapticPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    /// Play haptic for meditation start
    public func meditationStart() {
        guard isEnabled else { return }
        Task { @MainActor in
            // Very gentle fade-in pattern
            hapticPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 200_000_000)
            hapticPerformer.perform(.generic, performanceTime: .now)
            try? await Task.sleep(nanoseconds: 200_000_000)
            hapticPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Play haptic for journal entry open
    public func journalOpen() {
        performHaptic(.generic)
    }

    // MARK: - Configuration

    /// Enable or disable haptics
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("Haptics \(enabled ? "enabled" : "disabled")")
    }

    /// Set haptic intensity (0.0 - 1.0)
    public func setIntensity(_ intensity: Float) {
        hapticIntensity = max(0, min(1, intensity))
        logger.info("Haptic intensity set to \(self.hapticIntensity)")
    }

    /// Get current enabled state
    public var isHapticsEnabled: Bool { isEnabled }

    /// Get current intensity
    public var currentIntensity: Float { hapticIntensity }

    /// Check if device supports Core Haptics
    public var deviceSupportsHaptics: Bool { supportsHaptics }
}

// MARK: - Haptic Pattern Type

/// Predefined haptic patterns for common Sanctuary interactions
public enum SanctuaryHapticPattern: Sendable {
    case nodeSelect
    case panelOpen
    case panelClose
    case dimensionTransition
    case insightReveal
    case xpGain(amount: Int)
    case levelUp
    case levelUpCeremony
    case streakAlert
    case optimalWindow
    case grailDiscovery
    case nodeFocus
    case graphZoom(ZoomDirection)
    case clusterExpand
    case moodLog(valence: Double, energy: Double)
    case meditationStart
    case journalOpen
    case error

    /// Play this haptic pattern
    public func play() async {
        let haptics = SanctuaryHaptics.shared

        switch self {
        case .nodeSelect:
            haptics.nodeSelect()
        case .panelOpen:
            haptics.panelOpen()
        case .panelClose:
            haptics.panelClose()
        case .dimensionTransition:
            haptics.dimensionTransition()
        case .insightReveal:
            haptics.insightReveal()
        case .xpGain(let amount):
            haptics.xpGain(amount: amount)
        case .levelUp:
            haptics.levelUp()
        case .levelUpCeremony:
            await haptics.levelUpCeremony()
        case .streakAlert:
            haptics.streakAlert()
        case .optimalWindow:
            haptics.optimalWindow()
        case .grailDiscovery:
            await haptics.grailDiscovery()
        case .nodeFocus:
            haptics.nodeFocus()
        case .graphZoom(let direction):
            haptics.graphZoom(direction: direction)
        case .clusterExpand:
            haptics.clusterExpand()
        case .moodLog(let valence, let energy):
            haptics.moodLog(valence: valence, energy: energy)
        case .meditationStart:
            haptics.meditationStart()
        case .journalOpen:
            haptics.journalOpen()
        case .error:
            haptics.error()
        }
    }
}

// MARK: - SwiftUI View Extension

import SwiftUI

public extension View {

    /// Add haptic feedback on tap
    func hapticOnTap(_ pattern: SanctuaryHapticPattern = .nodeSelect) -> some View {
        self.onTapGesture {
            Task {
                await pattern.play()
            }
        }
    }

    /// Add haptic feedback when value changes
    func hapticOnChange<T: Equatable>(of value: T, pattern: SanctuaryHapticPattern = .nodeSelect) -> some View {
        self.onChange(of: value) { _, _ in
            Task {
                await pattern.play()
            }
        }
    }
}
