// CosmoOS/UI/Sanctuary/Systems/SanctuarySoundscape.swift
// Audio engine for the living Sanctuary experience
// Phase 9: Polish - Sound Design System

import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Soundscape Engine

/// Central audio engine for Sanctuary's immersive sound experience.
/// Manages ambient layers, transitions, feedback sounds, and alerts.
///
/// Sound Categories:
/// - Ambient: Continuous, layered sounds that evolve with Cosmo Index
/// - Transitions: Event-triggered sounds (dimension enter/exit, reveals)
/// - Feedback: Micro-interactions (node taps, XP gains, level-ups)
/// - Alerts: Discovery tones, streak warnings, optimal window reminders
public actor SanctuarySoundscape {

    // MARK: - Singleton

    public static let shared = SanctuarySoundscape()

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cosmo.sanctuary", category: "Soundscape")

    // Procedural audio synthesizer (replaces file-based audio)
    private let synthesizer = SanctuaryAudioSynthesizer()

    // State
    private var isEngineRunning = false
    private var currentDimension: SanctuaryDimension?
    private var currentCosmoIndex: Double = 0.5
    private var masterVolume: Float = 0.7
    private var ambientVolume: Float = 0.4
    private var isMuted: Bool = false

    // Volume fade tasks
    private var volumeFadeTasks: [AmbientLayer: Task<Void, Never>] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Engine Lifecycle

    /// Initialize and start the audio engine
    public func start() async throws {
        guard !isEngineRunning else { return }

        // Start the procedural synthesizer
        try synthesizer.start()
        isEngineRunning = true

        logger.info("Sanctuary Soundscape engine started")
    }

    /// Stop the audio engine
    public func stop() {
        guard isEngineRunning else { return }

        // Cancel all fade tasks
        for task in volumeFadeTasks.values {
            task.cancel()
        }
        volumeFadeTasks.removeAll()

        // Stop synthesizer
        synthesizer.stop()
        isEngineRunning = false

        logger.info("Sanctuary Soundscape engine stopped")
    }

    // MARK: - Preloading (No-op - using procedural synthesis)

    // Sounds are generated procedurally, no files to preload

    // MARK: - Ambient Control (Disabled - Event-Driven Mode)

    /// Start ambient sound - DISABLED (event-driven mode only)
    public func startAmbient() async {
        // Ambient disabled - Sanctuary uses event-driven sounds only
        // No continuous background noise
        logger.info("Ambient disabled (event-driven mode)")
    }

    /// Transition to a dimension's sound
    public func transitionToDimension(_ dimension: SanctuaryDimension, duration: TimeInterval = 2.0) async {
        currentDimension = dimension

        // Play transition sound only (no ambient)
        await playTransition(.dimensionEnter)

        logger.info("Transitioned to \(dimension.rawValue) dimension")
    }

    /// Return to home sanctuary
    public func returnToHome(duration: TimeInterval = 2.0) async {
        // Play exit transition sound
        await playTransition(.dimensionExit)
        currentDimension = nil

        logger.info("Returned to home")
    }

    /// Update based on Cosmo Index - no-op in event-driven mode
    public func updateCosmoIndex(_ index: Double) async {
        currentCosmoIndex = index
        // No ambient modulation in event-driven mode
    }

    private func ambientLayer(for dimension: SanctuaryDimension) -> AmbientLayer {
        switch dimension {
        case .cognitive: return .dimensionCognitive
        case .creative: return .dimensionCreative
        case .physiological: return .dimensionPhysiological
        case .behavioral: return .dimensionBehavioral
        case .knowledge: return .dimensionKnowledge
        case .reflection: return .dimensionReflection
        }
    }

    // MARK: - Transition Sounds

    /// Play a transition sound
    public func playTransition(_ sound: TransitionSound) async {
        guard isEngineRunning, !isMuted else { return }

        synthesizer.playTransition(sound)
        logger.debug("Playing transition: \(sound.rawValue)")
    }

    // MARK: - Feedback Sounds

    /// Play a feedback sound (micro-interaction)
    public func playFeedback(_ sound: FeedbackSound, pitch: Float = 1.0) async {
        guard isEngineRunning, !isMuted else { return }

        synthesizer.playFeedback(sound, pitchMultiplier: pitch)
        logger.debug("Playing feedback: \(sound.rawValue) at pitch \(pitch)")
    }

    /// Play XP tick sound with pitch based on amount
    public func playXPTick(amount: Int) async {
        guard isEngineRunning, !isMuted else { return }

        synthesizer.playXPTick(amount: amount)
    }

    // MARK: - Alert Sounds

    /// Play an alert sound
    public func playAlert(_ sound: AlertSound) async {
        guard isEngineRunning, !isMuted else { return }

        synthesizer.playAlert(sound)
        logger.debug("Playing alert: \(sound.rawValue)")
    }

    // MARK: - Level Up Ceremony

    /// Play the full level-up sound sequence
    public func playLevelUpSequence() async {
        guard isEngineRunning, !isMuted else { return }

        await synthesizer.playLevelUpSequence()
        logger.info("Level-up sound sequence played")
    }

    // MARK: - Volume Control

    /// Set master volume
    public func setMasterVolume(_ volume: Float) {
        masterVolume = max(0, min(1, volume))
    }

    /// Set ambient layer volume (no-op in event-driven mode)
    public func setAmbientVolume(_ volume: Float) {
        ambientVolume = max(0, min(1, volume))
    }

    /// Toggle mute
    public func toggleMute() -> Bool {
        isMuted.toggle()
        return isMuted
    }

    /// Set mute state
    public func setMuted(_ muted: Bool) {
        isMuted = muted
    }
}

// MARK: - Sound Types

/// Ambient sound layers
public enum AmbientLayer: String, CaseIterable, Sendable {
    case sanctuaryBase = "sanctuary_ambient"
    case dimensionCognitive = "dimension_cognitive"
    case dimensionCreative = "dimension_creative"
    case dimensionPhysiological = "dimension_physiological"
    case dimensionBehavioral = "dimension_behavioral"
    case dimensionKnowledge = "dimension_knowledge"
    case dimensionReflection = "dimension_reflection"
}

/// Transition sounds (event-triggered)
public enum TransitionSound: String, CaseIterable, Sendable {
    case dimensionEnter = "dimension_enter"
    case dimensionExit = "dimension_exit"
    case insightReveal = "insight_reveal"
    case grailDiscovery = "grail_discovery"
    case panelOpen = "panel_open"
    case panelClose = "panel_close"
}

/// Feedback sounds (micro-interactions)
public enum FeedbackSound: String, CaseIterable, Sendable {
    case nodeTap = "node_tap"
    case nodeHover = "node_hover"
    case xpTick = "xp_tick"
    case levelUpBuild = "level_up_build"
    case levelUpBurst = "level_up_burst"
}

/// Alert sounds
public enum AlertSound: String, CaseIterable, Sendable {
    case correlationFound = "correlation_found"
    case streakEndangered = "streak_endangered"
    case optimalWindow = "optimal_window"
    case grailDiscovered = "grail_discovered"
}

// MARK: - Errors

public enum SoundscapeError: Error, LocalizedError, Sendable {
    case engineInitFailed
    case audioSessionFailed
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .engineInitFailed:
            return "Failed to initialize audio engine"
        case .audioSessionFailed:
            return "Failed to configure audio session"
        case .fileNotFound(let name):
            return "Sound file not found: \(name)"
        }
    }
}

// MARK: - Convenience Extensions

public extension SanctuarySoundscape {

    /// Play appropriate sound for a mood log
    func playMoodLogSound(valence: Double, energy: Double) async {
        // Positive moods = brighter tone
        let pitch: Float = 1.0 + Float(valence) * 0.2
        await playFeedback(.nodeTap, pitch: pitch)
    }

    /// Play sound for knowledge node focus
    func playNodeFocusSound() async {
        await playFeedback(.nodeTap)
    }

    /// Play sound for insight discovery
    func playInsightSound(isGrail: Bool) async {
        if isGrail {
            await playTransition(.grailDiscovery)
        } else {
            await playTransition(.insightReveal)
        }
    }

    /// Play correlation discovery sound
    func playCorrelationSound() async {
        await playAlert(.correlationFound)
    }

    /// Play streak warning
    func playStreakWarning() async {
        await playAlert(.streakEndangered)
    }
}
