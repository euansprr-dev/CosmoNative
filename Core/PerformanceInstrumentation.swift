// CosmoOS/Core/PerformanceInstrumentation.swift
// App-wide os_signpost probes for the surfaces the July 2026 performance pass
// tuned: launch, destination switches, focus open/close, deep dive load.
// Mirrors CommandKPerformanceInstrumentation so Instruments shows one
// consistent story. Intervals are cheap (no-ops unless a tool is recording).
//
// Usage:
//   let state = AppPerformanceInstrumentation.begin("focus-open")
//   defer { AppPerformanceInstrumentation.end("focus-open", state) }

import Foundation
import OSLog

enum AppPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "AppPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "AppPerformance")

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// One-shot event marker (e.g. "first-frame").
    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
