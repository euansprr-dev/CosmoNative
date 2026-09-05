// Append to Core/SoundEngine.swift for a simulator-only regression executable.
import SwiftUI

enum Companion { case sample }
enum CreationRoute { case task }
enum FocusGoalNotifier { static let soundName = "cosmo-goal-v3.caf" }

// Appended to the real engine only in this regression executable, so the
// assertions can inspect its admission gate without adding a production API.
extension SoundEngine {
    func runLifecycleRegression() {
        profile = .minimal
        volume = 0.7
        let center = NotificationCenter.default
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        precondition(!gate.snapshot().enabled, "A live interruption blocks incidental cues")
        // iOS does not promise an ended notification after suspension.
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        print("Foreground recovery: \(gate.snapshot().enabled ? "PASS" : "FAIL")")
        let first = gate.snapshot().enabled
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
                               AVAudioSessionInterruptionReasonKey: AVAudioSession.InterruptionReason.routeDisconnected.rawValue])
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        print("Reconnected output recovery: \(gate.snapshot().enabled ? "PASS" : "FAIL")")
        let second = gate.snapshot().enabled
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        play(.complete, preview: true)
        print("Explicit preview recovery: \(gate.snapshot().enabled ? "PASS" : "FAIL")")
        let third = gate.snapshot().enabled
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        print("Media reset recovery: \(gate.snapshot().enabled ? "PASS" : "FAIL")")
        let passed = first && second && third && gate.snapshot().enabled
        // Recovery must preserve the user's Off preference and media suppression.
        profile = .off
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        precondition(!gate.snapshot().enabled, "Foregrounding must preserve Off")
        profile = .minimal
        beginSuppression()
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        precondition(!gate.snapshot().enabled, "Foregrounding must preserve media suppression")
        endSuppression()
        print(passed ? "ALL PASS" : "REGRESSION REPRODUCED")
        precondition(passed, "iOS audio recovery failed")
    }
}

@main struct LifecycleRegression: App {
    var body: some Scene {
        WindowGroup {
            Text("Audio lifecycle regression").task {
                try? await Task.sleep(for: .milliseconds(500))
                SoundEngine.shared.runLifecycleRegression()
                exit(0)
            }
        }
    }
}
