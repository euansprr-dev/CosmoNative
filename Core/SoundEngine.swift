// Core/SoundEngine.swift
// The Greenhouse Sound, on the desk: the Mac port of the iOS SoundEngine
// (CosmoiOS/Design/SoundEngine.swift — keep the two in step). The app sounds
// like the place it looks like — wood, seeds, paper, felt, water, air — and
// one strain of tuned warmth reserved for earned moments.
//
// Architecture: AVAudioEngine + a pool of player nodes over a bank of
// preloaded .caf buffers (round-robin variants, jitter baked into the files).
// macOS differences from the iOS engine: there is no AVAudioSession — the
// engine listens for AVAudioEngineConfigurationChange (device/route changes)
// and rebuilds lazily; there is no silent switch, so the Settings profile is
// the only gate. Call sites speak `Sound.*` semantic verbs, never file names.
// July 2026

import AVFoundation
import SwiftUI

// MARK: - Profiles & tiers (mirrors iOS)

/// How much of the soundscape plays. `minimal` keeps only the signature
/// moments — completion, the earned once-a-day cues — so the sounds that
/// remain never wear out.
enum SoundProfile: String, CaseIterable {
    case full, minimal, off

    var label: String {
        switch self {
        case .full: return "Full"
        case .minimal: return "Minimal"
        case .off: return "Off"
        }
    }
}

/// floor     — frequent vocabulary sounds; Full only.
/// standard  — bespoke everyday cues (drags, filing); Full only.
/// signature — completion and the rare earned moments; plays in Minimal too.
enum SoundTier { case floor, standard, signature }

// MARK: - The engine

@MainActor
final class SoundEngine {

    static let shared = SoundEngine()

    static let profileKey = "sound.profile"

    /// Minimal by default: the signature sounds only; Full is the opt-in.
    var profile: SoundProfile {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.profileKey),
               let stored = SoundProfile(rawValue: raw) {
                return stored
            }
            return .minimal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.profileKey)
        }
    }

    private func allows(_ tier: SoundTier) -> Bool {
        switch profile {
        case .full: return true
        case .minimal: return tier == .signature
        case .off: return false
        }
    }

    // MARK: Suppression (unmuted media surfaces)

    private var suppressionCount = 0

    /// While any unmuted media surface plays, UI sound yields entirely.
    func beginSuppression() { suppressionCount += 1 }
    func endSuppression() { suppressionCount = max(0, suppressionCount - 1) }

    /// Bespoke cues muffle the vocabulary floor briefly so a paired generic
    /// cue never doubles the designed one.
    private var floorMutedUntil: TimeInterval = 0

    // MARK: Engine state

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var format: AVAudioFormat?
    private var bank: [String: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [String: Int] = [:]
    private var lastPlayed: [String: TimeInterval] = [:]
    private var lastActivity: TimeInterval = 0
    private var running = false
    private var loaded = false
    private var idleWatch: Task<Void, Never>?

    private static let poolSize = 10
    private static let idleStop: TimeInterval = 30

    private init() {
        // An output-device change invalidates the graph — tear down and let
        // the next sound rebuild lazily against the new route.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in Task { @MainActor in SoundEngine.shared.stopEngine() } }
    }

    // MARK: Boot

    /// Load the bank and warm the graph so the first real sound of the
    /// session is as tight as the tenth.
    func prewarm() {
        guard profile != .off else { return }
        loadBankIfNeeded()
        startIfNeeded()
    }

    // MARK: Bank

    private func loadBankIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // Individually-added resources flatten into the bundle root; a folder
        // reference would keep the Sounds/ subdirectory. Accept either.
        let subdirectoryURLs = Bundle.main.urls(forResourcesWithExtension: "caf", subdirectory: "Sounds") ?? []
        let urls = subdirectoryURLs.isEmpty
            ? (Bundle.main.urls(forResourcesWithExtension: "caf", subdirectory: nil) ?? [])
            : subdirectoryURLs
        for url in urls where url.lastPathComponent.hasPrefix("snd_") {
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let fileFormat = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(file.length)
            ), (try? file.read(into: buffer)) != nil else { continue }
            format = format ?? fileFormat
            // snd_<key>_<n>.caf → key
            let stem = url.deletingPathExtension().lastPathComponent.dropFirst(4)
            guard let underscore = stem.lastIndex(of: "_") else { continue }
            let key = String(stem[..<underscore])
            bank[key, default: []].append(buffer)
        }
    }

    private func startIfNeeded() {
        guard !running, let format else { return }
        if players.isEmpty {
            for _ in 0..<Self.poolSize {
                let node = AVAudioPlayerNode()
                players.append(node)
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
            }
        }
        guard (try? engine.start()) != nil else { return }
        running = true
        // Swallow the first-play latency spike with one silent buffer.
        if let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256) {
            silent.frameLength = 256
            players[0].scheduleBuffer(silent)
            players[0].play()
        }
        watchIdle()
    }

    private func watchIdle() {
        idleWatch?.cancel()
        lastActivity = Date.timeIntervalSinceReferenceDate
        idleWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                if Date.timeIntervalSinceReferenceDate - self.lastActivity > Self.idleStop {
                    self.stopEngine()
                    return
                }
            }
        }
    }

    private func stopEngine() {
        idleWatch?.cancel()
        idleWatch = nil
        guard running else { return }
        for node in players { node.stop() }
        engine.stop()
        running = false
    }

    // MARK: Play

    private func canPlay(_ tier: SoundTier) -> Bool {
        allows(tier) && suppressionCount == 0
    }

    /// Vocabulary-floor sound. Full profile only.
    func floor(_ key: String, gain: Float = 1, minInterval: TimeInterval = 0.05) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now >= floorMutedUntil else { return }
        fire(key, tier: .floor, gain: gain, minInterval: minInterval, now: now)
    }

    /// Bespoke cue — mutes the floor briefly so nothing doubles it.
    func cue(
        _ key: String,
        tier: SoundTier = .standard,
        gain: Float = 1,
        muffleFloor: TimeInterval = 0.3
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        floorMutedUntil = max(floorMutedUntil, now + muffleFloor)
        fire(key, tier: tier, gain: gain, minInterval: 0.08, now: now)
    }

    private func fire(_ key: String, tier: SoundTier, gain: Float, minInterval: TimeInterval, now: TimeInterval) {
        guard canPlay(tier) else { return }
        if let last = lastPlayed[key], now - last < minInterval { return }
        loadBankIfNeeded()
        startIfNeeded()
        guard running, let variantsAvailable = bank[key], !variantsAvailable.isEmpty else { return }

        // Round-robin, never the same variant twice in a row.
        var index = Int.random(in: 0..<variantsAvailable.count)
        if variantsAvailable.count > 1, index == lastVariant[key] {
            index = (index + 1) % variantsAvailable.count
        }
        lastVariant[key] = index
        lastPlayed[key] = now
        lastActivity = now

        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        // Reset the node: scheduleBuffer QUEUES behind a still-ringing tail,
        // which would delay this sound — a stopped node plays immediately.
        node.stop()
        // ±0.8 dB per-play jitter for foley; signatures play IDENTICALLY
        // every time (the Apple Pay rule — sameness is the identity).
        let jitter: Float = tier == .signature
            ? 1
            : Float(pow(10, Double.random(in: -0.8...0.8) / 20))
        node.volume = gain * jitter
        node.scheduleBuffer(variantsAvailable[index])
        node.play()
    }
}

// MARK: - The vocabulary (semantic API — call sites never see file names)

/// Sound cues for the Mac's moments. Every method is safe to call
/// unconditionally — the engine handles the Settings profile, media
/// suppression, and rate limits. Only verbs with wired call sites live here;
/// grow it alongside the iOS vocabulary as surfaces adopt sound.
@MainActor
enum Sound {

    private static var engine: SoundEngine { .shared }

    // MARK: Completion choreography — layers on the animation keyframes

    /// Swish with the ring, pen stroke with the check, the rising du-DUM with
    /// the strike — riding the exact completion timings. Signature: this is
    /// the sound of the app.
    static func taskCompletion(timings: CommandCenterCompletionTimings) {
        engine.cue("swish", tier: .signature, muffleFloor: timings.fadeDelay)
        Task {
            try? await Task.sleep(for: .seconds(timings.checkDelay))
            engine.cue("stroke", tier: .signature, muffleFloor: 0.1)
            try? await Task.sleep(for: .seconds(timings.strikeDelay - timings.checkDelay))
            engine.cue("landing", tier: .signature, muffleFloor: 0.1)
        }
    }

    // (Un-completing is silent — removing a checkmark is not a moment.)

    // MARK: Earned moments

    /// The last open task of the day falls: once a day, never anywhere else.
    static func dayClear() { engine.cue("dayclear", tier: .signature, muffleFloor: 0.6) }
    static func habitComplete() { engine.cue("minibloom", muffleFloor: 0.4) }

    // MARK: Focus arc

    static func focusStart() { engine.cue("focusstart") }
    static func focusPause() { engine.cue("pause") }
    static func focusResume() { engine.cue("resume") }
    /// The exhale + droplet: time banked in the greenhouse.
    static func focusEnd() { engine.cue("exhale", muffleFloor: 0.5) }
    /// The felt bell — the daily goal lands mid-session.
    static func goalBell() { engine.cue("bell", tier: .signature, muffleFloor: 0.6) }

    // MARK: Drag & place

    static func dragPickup() { engine.cue("pickup", muffleFloor: 0.08) }
    static func dragDrop() { engine.cue("drop", muffleFloor: 0.15) }

    // MARK: Forgiveness

    /// The falling whoosh into the bin (the macOS trash grammar). Signature:
    /// deleting deserves its sound even in Minimal.
    static func deleteTuck() { engine.cue("delete", tier: .signature) }
    static func undo() { engine.cue("undo") }
}
