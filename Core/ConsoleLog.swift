// CosmoOS/Core/ConsoleLog.swift
// Centralized logging utility for debugging and monitoring
// macOS 26+ optimized

import Foundation
import os.log

// MARK: - Console Log Subsystems

public enum LogSubsystem: String, Sendable {
    case telepathy = "TELEPATHY"
    case gardener = "GARDENER"
    case autocomplete = "AUTOCOMPLETE"
    case notification = "NOTIFICATION"
    case voice = "VOICE"
    case search = "SEARCH"
    case database = "DATABASE"
    case daemon = "DAEMON"
    case context = "CONTEXT"
    case session = "SESSION"
    case safety = "SAFETY"
    case embedding = "EMBEDDING"
    case llm = "LLM"
    case asr = "ASR"
    case canvas = "CANVAS"
    case spatial = "SPATIAL"
}

// MARK: - Console Log

public struct ConsoleLog {
    private static let osLog = OSLog(subsystem: "com.cosmo.os", category: "CosmoOS")

    /// Enable/disable debug logging (set to false in production)
    public static nonisolated(unsafe) var isDebugEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Enable/disable verbose logging (more detailed than debug)
    public static nonisolated(unsafe) var isVerboseEnabled: Bool = false

    // MARK: - Debug Level

    /// Debug-level logging - only shown in debug builds
    /// Use for detailed diagnostic information during development
    public static func debug(_ message: String, subsystem: LogSubsystem) {
        guard isDebugEnabled else { return }

        let formatted = "[\(subsystem.rawValue)] \(message)"
        os_log(.debug, log: osLog, "%{public}@", formatted)
        #if DEBUG
        print("🔍 \(formatted)")
        #endif
    }

    // MARK: - Verbose Level

    /// Verbose-level logging - for very detailed trace information
    /// Only shown when isVerboseEnabled is true
    public static func verbose(_ message: String, subsystem: LogSubsystem) {
        guard isVerboseEnabled else { return }

        let formatted = "[\(subsystem.rawValue)] \(message)"
        os_log(.debug, log: osLog, "%{public}@", formatted)
        #if DEBUG
        print("🔬 \(formatted)")
        #endif
    }

    // MARK: - Info Level

    /// Info-level logging - important operational information
    /// Shown in both debug and release builds
    public static func info(_ message: String, subsystem: LogSubsystem) {
        let formatted = "[\(subsystem.rawValue)] \(message)"
        os_log(.info, log: osLog, "%{public}@", formatted)
        #if DEBUG
        print("ℹ️ \(formatted)")
        #endif
    }

    // MARK: - Warning Level

    /// Warning-level logging - potential issues that don't prevent operation
    public static func warning(_ message: String, subsystem: LogSubsystem) {
        let formatted = "[\(subsystem.rawValue)] ⚠️ \(message)"
        os_log(.error, log: osLog, "%{public}@", formatted)
        #if DEBUG
        print("⚠️ \(formatted)")
        #endif
    }

    // MARK: - Error Level

    /// Error-level logging - errors that affect operation
    public static func error(_ message: String, subsystem: LogSubsystem, error: Error? = nil) {
        var formatted = "[\(subsystem.rawValue)] ❌ \(message)"
        if let error = error {
            formatted += " - \(error.localizedDescription)"
        }
        os_log(.fault, log: osLog, "%{public}@", formatted)
        #if DEBUG
        print("❌ \(formatted)")
        #endif
    }

    // MARK: - Timing Helpers

    /// Log the start of a timed operation and return the start time
    public static func startTiming(_ operation: String, subsystem: LogSubsystem) -> Date {
        let start = Date()
        debug("⏱ Starting: \(operation)", subsystem: subsystem)
        return start
    }

    /// Log the end of a timed operation
    public static func endTiming(_ operation: String, start: Date, subsystem: LogSubsystem) {
        let duration = Date().timeIntervalSince(start) * 1000 // Convert to ms
        let formatted = String(format: "%.2fms", duration)
        info("⏱ Completed: \(operation) in \(formatted)", subsystem: subsystem)
    }

    /// Execute a block and log its timing
    public static func timed<T>(_ operation: String, subsystem: LogSubsystem, block: () throws -> T) rethrows -> T {
        let start = startTiming(operation, subsystem: subsystem)
        defer { endTiming(operation, start: start, subsystem: subsystem) }
        return try block()
    }

    /// Execute an async block and log its timing
    public static func timed<T>(_ operation: String, subsystem: LogSubsystem, block: () async throws -> T) async rethrows -> T {
        let start = startTiming(operation, subsystem: subsystem)
        defer { endTiming(operation, start: start, subsystem: subsystem) }
        return try await block()
    }

    // MARK: - Memory Logging

    /// Log current memory usage (useful for debugging memory issues)
    public static func logMemoryUsage(context: String, subsystem: LogSubsystem) {
        var memInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &memInfo) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(memInfo.phys_footprint) / 1_048_576
            ConsoleLog.info("📊 Memory [\(context)]: \(String(format: "%.1f", usedMB))MB", subsystem: subsystem)
        }
    }
}

// MARK: - Convenience Extensions

extension ConsoleLog {
    /// Log entry point for a function
    public static func enter(_ function: String = #function, subsystem: LogSubsystem) {
        verbose("→ \(function)", subsystem: subsystem)
    }

    /// Log exit point for a function
    public static func exit(_ function: String = #function, subsystem: LogSubsystem) {
        verbose("← \(function)", subsystem: subsystem)
    }

    /// Log a successful operation
    public static func success(_ message: String, subsystem: LogSubsystem) {
        info("✓ \(message)", subsystem: subsystem)
    }

    /// Log a failure (less severe than error)
    public static func failure(_ message: String, subsystem: LogSubsystem) {
        warning("✗ \(message)", subsystem: subsystem)
    }
}
