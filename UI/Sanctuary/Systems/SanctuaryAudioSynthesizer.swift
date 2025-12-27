// CosmoOS/UI/Sanctuary/Systems/SanctuaryAudioSynthesizer.swift
// Procedural audio synthesis for Sanctuary soundscape
// Event-driven only - no continuous ambient

import Foundation
import AVFoundation

// MARK: - Audio Synthesizer

/// Generates pleasant, musical sounds for Sanctuary interactions.
/// Event-driven only - plays sounds on specific triggers, never continuously.
public final class SanctuaryAudioSynthesizer: @unchecked Sendable {

    // MARK: - Types

    /// Sound definition with harmonics support
    struct SoundDef {
        let frequency: Double       // Base frequency in Hz
        let duration: Double        // Total duration in seconds
        let attack: Double          // Attack time (soft start)
        let decay: Double           // Decay rate (higher = faster fade)
        let volume: Float           // Base volume 0-1
        let harmonicMix: Double     // 0 = pure sine, 1 = equal harmonic

        init(
            frequency: Double,
            duration: Double,
            attack: Double = 0.015,
            decay: Double = 8.0,
            volume: Float = 0.2,
            harmonicMix: Double = 0.25
        ) {
            self.frequency = frequency
            self.duration = duration
            self.attack = attack
            self.decay = decay
            self.volume = volume
            self.harmonicMix = harmonicMix
        }
    }

    // MARK: - Properties

    private let engine: AVAudioEngine
    private let mixer: AVAudioMixerNode
    private let format: AVAudioFormat
    private var isRunning = false
    private let lock = NSLock()

    // MARK: - Sound Definitions (Musical Notes)

    // Transition sounds - musical intervals, warm tones
    private let transitionSounds: [TransitionSound: SoundDef] = [
        // Dimension enter: warm rising tone (G4 to B4)
        .dimensionEnter: SoundDef(frequency: 392, duration: 0.3, attack: 0.03, decay: 6.0, volume: 0.22, harmonicMix: 0.3),
        // Dimension exit: gentle falling tone
        .dimensionExit: SoundDef(frequency: 330, duration: 0.25, attack: 0.02, decay: 7.0, volume: 0.18, harmonicMix: 0.25),
        // Insight reveal: bright but not harsh (E5)
        .insightReveal: SoundDef(frequency: 659, duration: 0.35, attack: 0.02, decay: 5.0, volume: 0.25, harmonicMix: 0.35),
        // Grail discovery: special chord feel
        .grailDiscovery: SoundDef(frequency: 523, duration: 0.5, attack: 0.03, decay: 4.0, volume: 0.28, harmonicMix: 0.4),
        // Panel open: soft click (G4)
        .panelOpen: SoundDef(frequency: 392, duration: 0.12, attack: 0.01, decay: 12.0, volume: 0.15, harmonicMix: 0.2),
        // Panel close: slightly lower (E4)
        .panelClose: SoundDef(frequency: 330, duration: 0.1, attack: 0.01, decay: 14.0, volume: 0.12, harmonicMix: 0.2)
    ]

    // Feedback sounds - short, pleasant taps
    private let feedbackSounds: [FeedbackSound: SoundDef] = [
        // Node tap: soft wooden click feel (A4)
        .nodeTap: SoundDef(frequency: 440, duration: 0.1, attack: 0.008, decay: 15.0, volume: 0.15, harmonicMix: 0.3),
        // Node hover: very subtle (C5, quieter)
        .nodeHover: SoundDef(frequency: 523, duration: 0.06, attack: 0.005, decay: 20.0, volume: 0.08, harmonicMix: 0.2),
        // XP tick: pleasant ping (E5)
        .xpTick: SoundDef(frequency: 659, duration: 0.08, attack: 0.005, decay: 18.0, volume: 0.12, harmonicMix: 0.25),
        // Level up build: rising anticipation
        .levelUpBuild: SoundDef(frequency: 392, duration: 0.4, attack: 0.05, decay: 3.0, volume: 0.25, harmonicMix: 0.35),
        // Level up burst: triumphant (C5)
        .levelUpBurst: SoundDef(frequency: 523, duration: 0.45, attack: 0.02, decay: 3.5, volume: 0.3, harmonicMix: 0.4)
    ]

    // Alert sounds - noticeable but pleasant
    private let alertSounds: [AlertSound: SoundDef] = [
        // Correlation found: discovery chime (A4)
        .correlationFound: SoundDef(frequency: 440, duration: 0.3, attack: 0.02, decay: 5.0, volume: 0.22, harmonicMix: 0.35),
        // Streak endangered: gentle warning (G4, minor feel)
        .streakEndangered: SoundDef(frequency: 392, duration: 0.35, attack: 0.03, decay: 4.5, volume: 0.2, harmonicMix: 0.3),
        // Optimal window: opportunity bell (E5)
        .optimalWindow: SoundDef(frequency: 659, duration: 0.25, attack: 0.02, decay: 6.0, volume: 0.2, harmonicMix: 0.3),
        // Grail discovered: special moment (C5)
        .grailDiscovered: SoundDef(frequency: 523, duration: 0.5, attack: 0.03, decay: 3.5, volume: 0.28, harmonicMix: 0.45)
    ]

    // MARK: - Initialization

    public init() {
        engine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Engine Control

    public func start() throws {
        guard !isRunning else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default)
        try session.setActive(true)
        #endif

        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    // MARK: - Ambient (Disabled)

    public func startAmbient(layer: AmbientLayer, volume: Float = 0.15) {
        // No-op: Ambient disabled in event-driven mode
    }

    public func stopAmbient() {
        // No-op
    }

    public func setAmbientVolume(_ volume: Float) {
        // No-op
    }

    public func transitionAmbient(to layer: AmbientLayer, duration: TimeInterval = 1.0) {
        // No-op
    }

    // MARK: - Sound Playback

    public func playTransition(_ sound: TransitionSound, pitchMultiplier: Float = 1.0) {
        guard let def = transitionSounds[sound] else { return }
        playMusicalTone(def, pitchMultiplier: pitchMultiplier)

        // For dimension enter, play a second rising tone
        if sound == .dimensionEnter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                let secondTone = SoundDef(frequency: 494, duration: 0.25, attack: 0.02, decay: 6.0, volume: 0.2, harmonicMix: 0.3) // B4
                self?.playMusicalTone(secondTone, pitchMultiplier: pitchMultiplier)
            }
        }

        // For grail discovery, play a chord
        if sound == .grailDiscovery {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                let e5 = SoundDef(frequency: 659, duration: 0.45, attack: 0.025, decay: 4.0, volume: 0.22, harmonicMix: 0.35)
                self?.playMusicalTone(e5, pitchMultiplier: pitchMultiplier)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                let g5 = SoundDef(frequency: 784, duration: 0.4, attack: 0.03, decay: 4.0, volume: 0.18, harmonicMix: 0.3)
                self?.playMusicalTone(g5, pitchMultiplier: pitchMultiplier)
            }
        }
    }

    public func playFeedback(_ sound: FeedbackSound, pitchMultiplier: Float = 1.0) {
        guard let def = feedbackSounds[sound] else { return }
        playMusicalTone(def, pitchMultiplier: pitchMultiplier)
    }

    public func playAlert(_ sound: AlertSound) {
        guard let def = alertSounds[sound] else { return }
        playMusicalTone(def, pitchMultiplier: 1.0)

        // For grail discovered, play rising arpeggio
        if sound == .grailDiscovered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                let e5 = SoundDef(frequency: 659, duration: 0.4, attack: 0.02, decay: 4.0, volume: 0.24, harmonicMix: 0.4)
                self?.playMusicalTone(e5, pitchMultiplier: 1.0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                let g5 = SoundDef(frequency: 784, duration: 0.35, attack: 0.025, decay: 4.5, volume: 0.2, harmonicMix: 0.35)
                self?.playMusicalTone(g5, pitchMultiplier: 1.0)
            }
        }
    }

    public func playXPTick(amount: Int) {
        // Pitch rises slightly with amount (max +20%)
        let pitch: Float = 1.0 + Float(min(amount, 50)) / 250.0
        playFeedback(.xpTick, pitchMultiplier: pitch)
    }

    public func playLevelUpSequence() async {
        // Build-up
        playFeedback(.levelUpBuild)
        try? await Task.sleep(nanoseconds: 350_000_000)

        // Burst with chord
        playFeedback(.levelUpBurst)

        // Add E5 for major chord
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let e5 = SoundDef(frequency: 659, duration: 0.4, attack: 0.02, decay: 4.0, volume: 0.25, harmonicMix: 0.35)
            self?.playMusicalTone(e5, pitchMultiplier: 1.0)
        }

        // Add G5 to complete the chord
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let g5 = SoundDef(frequency: 784, duration: 0.35, attack: 0.025, decay: 4.5, volume: 0.2, harmonicMix: 0.3)
            self?.playMusicalTone(g5, pitchMultiplier: 1.0)
        }
    }

    // MARK: - Core Tone Generation

    private func playMusicalTone(_ def: SoundDef, pitchMultiplier: Float) {
        guard isRunning else { return }

        let frequency = def.frequency * Double(pitchMultiplier)
        let duration = def.duration
        let attackTime = def.attack
        let decayRate = def.decay
        let volume = def.volume
        let harmonicMix = def.harmonicMix
        let sampleRate = 44100.0
        let totalSamples = Int(duration * sampleRate)

        var phase: Double = 0
        var currentSample = 0

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                guard currentSample < totalSamples else {
                    for buffer in ablPointer {
                        let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                        buf?[frame] = 0
                    }
                    continue
                }

                let time = Double(currentSample) / sampleRate

                // Soft attack (fade in)
                let attackEnv = min(1.0, time / attackTime)

                // Exponential decay (natural fade out)
                let decayEnv = exp(-time * decayRate)

                // Combined envelope
                let envelope = attackEnv * decayEnv

                // Generate fundamental + octave harmonic for richer tone
                let fundamental = sin(phase * 2.0 * .pi)
                let harmonic = sin(phase * 4.0 * .pi) // Octave above

                // Mix fundamental and harmonic
                let mixed = fundamental * (1.0 - harmonicMix) + harmonic * harmonicMix

                // Apply envelope and volume
                let sample = mixed * envelope * Double(volume)

                // Advance phase
                phase += frequency / sampleRate
                if phase > 1.0 { phase -= 1.0 }

                // Write to buffer
                let floatSample = Float(sample)
                for buffer in ablPointer {
                    let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                    buf?[frame] = floatSample
                }

                currentSample += 1
            }

            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mixer, format: format)

        // Clean up after sound completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self, weak sourceNode] in
            if let node = sourceNode {
                self?.engine.detach(node)
            }
        }
    }
}
