// Cosmo sound system. Keep this file identical in the macOS and iOS apps.
// Nine short, mastered gestures; one stable identity on every device.
// Audio I/O is confined to a serial queue. The main actor only sends intent.

import AVFoundation
import Observation
import os
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum SoundProfile: String, CaseIterable, Sendable {
    // Preserve the existing stored values when upgrading.
    case minimal, full, off

    var label: String {
        switch self {
        case .minimal: return "Essentials"
        case .full: return "All actions"
        case .off: return "Off"
        }
    }

    var detail: String {
        switch self {
        case .minimal: return "Completion and milestones."
        case .full: return "Subtle sounds for everyday actions."
        case .off: return "Interface sounds are muted."
        }
    }

    func allows(_ cue: SoundCue) -> Bool {
        self == .full || (self == .minimal && cue.isEssential)
    }
}

enum SoundCue: String, CaseIterable, Sendable {
    case complete, milestone, confirm, open, close, place, remove, undo, focus

    var isEssential: Bool {
        switch self {
        case .complete, .milestone, .focus: return true
        default: return false
        }
    }

    var priority: Int {
        switch self {
        case .complete, .milestone, .focus: return 2
        default: return 1
        }
    }

    var cooldown: TimeInterval {
        switch self {
        case .milestone: return 1.5
        case .complete: return 0.24
        default: return 0.16
        }
    }

    var resourceName: String { "ui_" + rawValue }
}

/// Pure admission policy, also exercised by the standalone sound regression suite.
struct SoundPlaybackPolicy {
    private var lastPlayed: [SoundCue: TimeInterval] = [:]
    private var protectedUntil: TimeInterval = 0
    private var lastAny: TimeInterval = -.infinity

    func allows(_ cue: SoundCue, at now: TimeInterval) -> Bool {
        guard now - lastAny >= 0.055 else { return false }
        if let last = lastPlayed[cue], now - last < cue.cooldown { return false }
        return cue.priority == 2 || now >= protectedUntil
    }

    mutating func record(_ cue: SoundCue, at now: TimeInterval, duration: TimeInterval) {
        lastPlayed[cue] = now
        lastAny = now
        if cue.priority == 2 { protectedUntil = now + duration }
    }
}

/// Revoking a request is synchronous, even while the audio queue is preparing
/// a player. Off, background, media, and route changes invalidate queued work.
final class SoundPlaybackGate: Sendable {
    struct State: Sendable {
        var generation: UInt64 = 0
        var enabled = false
        var volume: Float = 0.7
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func update(enabled: Bool, volume: Float) {
        state.withLock {
            $0.generation &+= 1
            $0.enabled = enabled
            $0.volume = volume
        }
    }

    func snapshot() -> State { state.withLock { $0 } }

    func accepts(generation: UInt64, requestedAt: TimeInterval, now: TimeInterval) -> Bool {
        state.withLock { $0.enabled && $0.generation == generation && now - requestedAt < 0.18 }
    }
}

/// Queue confinement is the Sendable invariant. Players never cross this queue.
private final class SoundPlaybackDriver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cosmo.interface-audio", qos: .userInitiated)
    private let gate: SoundPlaybackGate
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private var policy = SoundPlaybackPolicy()
    private var preparedSession = false
    private let logger = Logger(subsystem: "com.cosmo.audio", category: "playback")

    init(gate: SoundPlaybackGate) { self.gate = gate }

    func prewarm() {
        queue.async { [self] in
            guard gate.snapshot().enabled else { return }
            guard prepareSession() else { return }
            for cue in SoundCue.allCases { _ = player(for: cue) }
        }
    }

    func invalidate() {
        queue.async { [self] in
            players.values.forEach { $0.stop() }
            players.removeAll()
            preparedSession = false
            policy = SoundPlaybackPolicy()
        }
    }

    func updateVolume() {
        queue.async { [self] in
            let state = gate.snapshot()
            for player in players.values {
                if !state.enabled { player.stop() }
                player.volume = state.volume
            }
        }
    }

    func play(_ cue: SoundCue) {
        let request = gate.snapshot()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard gate.accepts(generation: request.generation, requestedAt: requestedAt,
                               now: ProcessInfo.processInfo.systemUptime) else { return }
            guard prepareSession() else { return }
            guard let player = player(for: cue) else { return }
            let now = ProcessInfo.processInfo.systemUptime
            // Revalidate AFTER blocking audio I/O, not only at tap time.
            guard gate.accepts(generation: request.generation, requestedAt: requestedAt, now: now),
                  policy.allows(cue, at: now), !player.isPlaying,
                  players.values.filter(\.isPlaying).count < 3 else { return }
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            guard !session.isOtherAudioPlaying, !session.secondaryAudioShouldBeSilencedHint,
                  session.category == .ambient else { return }
            #endif
            player.currentTime = 0
            player.volume = gate.snapshot().volume
            if player.play() { policy.record(cue, at: now, duration: player.duration) }
        }
    }

    @discardableResult
    private func prepareSession() -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if preparedSession && session.category == .ambient { return true }
        do {
            // Avoid generating a category-change notification on every recovery.
            if session.category != .ambient || session.mode != .default {
                try session.setCategory(.ambient, mode: .default)
            }
            // An interruption may have no matching ended notification. Let iOS
            // decide whether a fresh activation is allowed, and handle failure.
            try session.setActive(true)
        } catch {
            preparedSession = false
            logger.error("Could not activate interface audio: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #endif
        preparedSession = true
        return true
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }
        guard let url = Bundle.main.url(forResource: cue.resourceName, withExtension: "caf", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: cue.resourceName, withExtension: "caf") else {
            logger.error("Missing interface cue: \(cue.rawValue, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[cue] = player
            return player
        } catch {
            logger.error("Could not load interface cue: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

@Observable @MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    static let profileKey = "sound.profile"
    static let volumeKey = "sound.volume"
    static let hapticsKey = "haptics.enabled"

    var profile: SoundProfile {
        didSet {
            UserDefaults.standard.set(profile.rawValue, forKey: Self.profileKey)
            refreshGate()
            if profile == .off { driver.invalidate() } else { prewarm() }
        }
    }

    var volume: Double {
        didSet {
            let clamped = volume.isFinite ? min(1, max(0, volume)) : 0.7
            if volume != clamped { volume = clamped }
            UserDefaults.standard.set(clamped, forKey: Self.volumeKey)
            refreshGate()
            driver.updateVolume()
        }
    }

    @ObservationIgnored private let gate: SoundPlaybackGate
    @ObservationIgnored private let driver: SoundPlaybackDriver
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var suppressionCount = 0
    private var isActive = true
    private var interrupted = false
    private var isRecording = false

    private init() {
        let defaults = UserDefaults.standard
        profile = defaults.string(forKey: Self.profileKey).flatMap(SoundProfile.init(rawValue:))
            ?? (defaults.object(forKey: "sound.enabled") as? Bool == false ? .off : .minimal)
        let savedVolume = defaults.object(forKey: Self.volumeKey) as? Double ?? 0.7
        volume = savedVolume.isFinite ? min(1, max(0, savedVolume)) : 0.7
        let gate = SoundPlaybackGate()
        self.gate = gate
        driver = SoundPlaybackDriver(gate: gate)
        #if os(iOS)
        isActive = UIApplication.shared.applicationState == .active
        #else
        isActive = NSApp?.isActive ?? false
        #endif
        refreshGate()
        observeLifecycle()
    }

    func prewarm() {
        refreshGate()
        driver.prewarm()
    }

    func play(_ cue: SoundCue, preview: Bool = false) {
        #if os(iOS)
        // Preview is a new playback request, not an automatic resume. An old
        // interruption must not permanently disable the user's Play button.
        if preview && isActive && interrupted {
            interrupted = false
            refreshGate()
            driver.invalidate()
        }
        #endif
        guard profile != .off, preview || profile.allows(cue),
              suppressionCount == 0, isActive, !interrupted, !isRecording, volume > 0 else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        guard !session.isOtherAudioPlaying, !session.secondaryAudioShouldBeSilencedHint else { return }
        #endif
        driver.play(cue)
    }

    func beginSuppression() {
        suppressionCount += 1
        refreshGate()
        driver.invalidate()
    }

    func endSuppression() {
        suppressionCount = max(0, suppressionCount - 1)
        prewarm()
    }

    func appDidEnterBackground() {
        isActive = false
        refreshGate()
        driver.invalidate()
    }

    func appDidBecomeActive() {
        isActive = true
        #if os(iOS)
        // iOS does not guarantee an interruption-ended notification after the
        // app leaves the foreground. Rebuild the session for future actions.
        interrupted = false
        driver.invalidate()
        #endif
        prewarm()
    }

    private func refreshGate() {
        gate.update(enabled: profile != .off && volume > 0 && suppressionCount == 0 && isActive && !interrupted && !isRecording,
                    volume: Float(volume))
    }

    private func observe(_ name: Notification.Name, detailKey: String? = nil, action: @escaping @MainActor @Sendable (UInt?) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            // Only a Sendable scalar crosses isolation; Notification.userInfo
            // may hold non-Sendable objects owned by the audio framework.
            #if os(iOS)
            let interruption = note.userInfo?[detailKey ?? AVAudioSessionInterruptionTypeKey] as? UInt
            #else
            let interruption: UInt? = nil
            #endif
            MainActor.assumeIsolated { action(interruption) }
        })
    }

    private func observeLifecycle() {
        #if os(iOS)
        observe(UIApplication.willResignActiveNotification) { [weak self] _ in self?.appDidEnterBackground() }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            self?.appDidBecomeActive()
        }
        observe(AVAudioSession.interruptionNotification) { [weak self] raw in
            guard let self, let raw,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self.interrupted = type == .began
            self.refreshGate()
            self.driver.invalidate()
            // End of an interruption permits FUTURE taps; old cues never replay.
            if !self.interrupted { self.driver.prewarm() }
        }
        observe(AVAudioSession.routeChangeNotification, detailKey: AVAudioSessionRouteChangeReasonKey) { [weak self] raw in
            guard let self else { return }
            // Reconnecting an output can end a route-disconnection interruption
            // without an interruption-ended notification.
            if raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                self.interrupted = false
            }
            self.refreshGate()
            self.driver.invalidate()
            self.driver.prewarm()
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self else { return }
            self.interrupted = false
            self.refreshGate()
            self.driver.invalidate()
            self.driver.prewarm()
        }
        #else
        observe(NSApplication.didResignActiveNotification) { [weak self] _ in self?.appDidEnterBackground() }
        observe(NSApplication.didBecomeActiveNotification) { [weak self] _ in
            self?.appDidBecomeActive()
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("com.cosmo.voice.recordingStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            let recording = note.userInfo?["isRecording"] as? Bool ?? false
            MainActor.assumeIsolated {
                self?.isRecording = recording
                self?.refreshGate()
                if recording { self?.driver.invalidate() }
                else { self?.prewarm() }
            }
        })
        #endif
    }

    #if os(iOS)
    nonisolated static let notificationSoundName = FocusGoalNotifier.soundName

    nonisolated static func installNotificationSound() {
        guard let source = Bundle.main.url(forResource: "ui_milestone", withExtension: "caf", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: "ui_milestone", withExtension: "caf"),
              let data = try? Data(contentsOf: source),
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        let destination = directory.appendingPathComponent(notificationSoundName)
        // Atomic replacement also upgrades an existing installation's old bell.
        guard (try? Data(contentsOf: destination)) != data else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch {
            Logger(subsystem: "com.cosmo.audio", category: "notification")
                .error("Could not install goal sound: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

/// Semantic call sites stay stable while both apps share the same small palette.
@MainActor enum Sound {
    private static var engine: SoundEngine { .shared }

    // The caller fires this ON the checkmark beat. One audio file owns both
    // transients, so the signature never depends on independently sleeping Tasks.
    static func taskComplete() { engine.play(.complete) }
    static func dayClear() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard defaults.double(forKey: "sound.lastDayClear") != today else { return }
        defaults.set(today, forKey: "sound.lastDayClear")
        engine.play(.milestone)
    }
    static func habitComplete() { engine.play(.complete) }
    static func focusStart() { engine.play(.open) }
    static func focusPause() { engine.play(.close) }
    static func focusResume() { engine.play(.open) }
    static func focusEnd() { engine.play(.focus) }
    static func goalBell() { engine.play(.milestone) }
    static func dragPickup() { engine.play(.open) }
    static func dragDrop() { engine.play(.place) }
    /// An image landed in Downloads / on disk — the same "placed" knock as a drop.
    static func imageSaved() { engine.play(.place) }
    static func deleteTuck() { engine.play(.remove) }
    static func undo() { engine.play(.undo) }
    static func companionFlourish(_ companion: Companion) { engine.play(.confirm) }

    #if os(iOS)
    enum Entity: String { case task, note, idea, connection, swipe }
    static func inboxZero() { engine.play(.milestone) }
    static func giltShimmer() {} // Decorative changes do not need an announcement.
    static func orbTap() { engine.play(.open) }
    static func bloomOpen() { engine.play(.open) }
    static func bloomClose() { engine.play(.close) }
    static func fanStep(_ rowIndex: Int) {} // Selection haptics carry navigation.
    static func entityCommit(_ route: CreationRoute) { engine.play(.confirm) }
    static func captureSaved() { engine.play(.confirm) }
    static func filing(_ entity: Entity?) { engine.play(.place) }
    static func connectTie() { engine.play(.confirm) }
    static func dismissTuck() { engine.play(.close) }
    static func reschedule() { engine.play(.place) }
    static func snapTick(degree: Int) {} // No pitched scale while dragging.
    static func workspaceReady() {} // Loading a page is silent.
    static func hello() { engine.play(.focus) }
    #endif
}
