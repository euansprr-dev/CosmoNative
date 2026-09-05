import Foundation

// Standalone harness supplies only the unrelated app type required by Sound.
enum Companion { case sample }

@main struct AudioPolicyTests {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ reason: String) {
            precondition(value(), reason)
            count += 1
        }
        check(SoundProfile.minimal.allows(.complete), "Essentials must include completion")
        check(SoundProfile.minimal.allows(.focus), "Essentials must include focus finish")
        check(SoundProfile.minimal.allows(.milestone), "Essentials must include milestones")
        for cue in SoundCue.allCases {
            check(!SoundProfile.off.allows(cue), "Off must reject every cue")
            check(SoundProfile.full.allows(cue), "All actions must allow the palette")
        }
        check(!SoundProfile.minimal.allows(.remove), "Deletion is not a reward")
        check(!SoundProfile.minimal.allows(.open), "Navigation is not a reward")
        var policy = SoundPlaybackPolicy()
        check(policy.allows(.complete, at: 1), "First completion")
        policy.record(.complete, at: 1, duration: 0.272)
        check(!policy.allows(.complete, at: 1.1), "Rapid duplicate suppressed")
        check(!policy.allows(.place, at: 1.15), "Low priority cannot mask completion")
        check(!policy.allows(.milestone, at: 1.02), "No simultaneous stacked cues")
        check(policy.allows(.place, at: 1.3), "Everyday cues resume after tail")
        policy.record(.milestone, at: 2, duration: 0.44)
        check(!policy.allows(.milestone, at: 2.6), "Duplicate milestone surfaces coalesce")
        check(policy.allows(.milestone, at: 3.6), "Later milestone permitted")
        let gate = SoundPlaybackGate()
        gate.update(enabled: true, volume: 0.7)
        let request = gate.snapshot()
        check(gate.accepts(generation: request.generation, requestedAt: 1, now: 1.05), "Fresh request")
        gate.update(enabled: false, volume: 0.7)
        check(!gate.accepts(generation: request.generation, requestedAt: 1, now: 1.06), "Off while decoding revokes request")
        gate.update(enabled: true, volume: 0.7)
        check(!gate.accepts(generation: request.generation, requestedAt: 1, now: 1.07), "Resume must not resurrect old request")
        let resumed = gate.snapshot()
        check(!gate.accepts(generation: resumed.generation, requestedAt: 1, now: 1.3), "Cold request expires instead of sounding late")
        check(gate.accepts(generation: resumed.generation, requestedAt: 2, now: 2.05), "Fresh action after resume works")
        print("PASS: \(count) playback policy and cancellation assertions")
    }
}
