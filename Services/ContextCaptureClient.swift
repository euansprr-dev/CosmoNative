// CosmoOS/Services/ContextCaptureClient.swift
// Thin XPC wrapper for AXContextService running in daemon
// Main app uses this to request context capture from the daemon
// macOS 26+ optimized

import Foundation
import Combine
import AppKit

// MARK: - Context Capture Client

@MainActor
public final class ContextCaptureClient: ObservableObject {
    // MARK: - Singleton

    public static let shared = ContextCaptureClient()

    // MARK: - Dependencies

    private let daemonClient: DaemonXPCClient

    // MARK: - Published State

    @Published public private(set) var lastContext: WindowContext?
    @Published public private(set) var lastCaptureTime: Date?
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: Error?

    // MARK: - Cache

    private var contextCache: WindowContext?
    private let cacheValidDuration: TimeInterval = 2.0  // 2 second cache
    private var cacheTimestamp: Date?

    // MARK: - Initialization

    private init() {
        self.daemonClient = DaemonXPCClient.shared
    }

    // MARK: - Context Capture

    /// Capture context from the active window (via daemon)
    public func captureContext(useCache: Bool = true) async throws -> WindowContext {
        // Check cache first
        if useCache, let cached = contextCache, let timestamp = cacheTimestamp {
            if Date().timeIntervalSince(timestamp) < cacheValidDuration {
                return cached
            }
        }

        isCapturing = true
        lastError = nil

        defer {
            isCapturing = false
        }

        do {
            let context = try await daemonClient.captureActiveWindowContext()

            // Update cache
            contextCache = context
            cacheTimestamp = Date()

            // Update published state
            lastContext = context
            lastCaptureTime = context.captureTime

            return context
        } catch {
            lastError = error
            throw error
        }
    }

    /// Capture context with timeout
    public func captureContext(timeout: Duration) async throws -> WindowContext {
        try await withThrowingTaskGroup(of: WindowContext.self) { group in
            group.addTask {
                try await self.captureContext(useCache: false)
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw ContextCaptureError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Clear the context cache
    public func clearCache() {
        contextCache = nil
        cacheTimestamp = nil
    }

    // MARK: - Convenience Methods

    /// Get current app name
    public func getCurrentAppName() async -> String? {
        try? await captureContext().appName
    }

    /// Get current URL (if in browser)
    public func getCurrentURL() async -> String? {
        try? await captureContext().url
    }

    /// Get selected text (if any)
    public func getSelectedText() async -> String? {
        try? await captureContext().selectedText
    }

    /// Get context summary for LLM
    public func getContextSummary() async -> String? {
        try? await captureContext().contextSummary
    }

    /// Check if current app is a browser
    public func isInBrowser() async -> Bool {
        guard let bundleId = try? await captureContext().bundleIdentifier else {
            return false
        }
        return bundleId.contains("Safari") ||
               bundleId.contains("Chrome") ||
               bundleId.contains("Firefox") ||
               bundleId.contains("Arc")
    }

    /// Check if current app is a code editor
    public func isInCodeEditor() async -> Bool {
        guard let bundleId = try? await captureContext().bundleIdentifier else {
            return false
        }
        return bundleId.contains("VSCode") ||
               bundleId.contains("Xcode") ||
               bundleId.contains("Sublime") ||
               bundleId.contains("Nova")
    }
}

// MARK: - Errors

public enum ContextCaptureError: LocalizedError {
    case daemonNotConnected
    case captureFailedTimeout
    case noContextAvailable
    case timeout

    public var errorDescription: String? {
        switch self {
        case .daemonNotConnected:
            return "Daemon not connected for context capture"
        case .captureFailedTimeout:
            return "Context capture timed out"
        case .noContextAvailable:
            return "No context available"
        case .timeout:
            return "Context capture timed out"
        }
    }
}

// MARK: - Voice Context Integration

extension ContextCaptureClient {
    /// Create enriched context snapshot combining VoiceContextStore data with window context
    public func createEnrichedContext(from voiceContext: VoiceContextSnapshot?) async throws -> EnrichedVoiceContext {
        let windowContext = try await captureContext()
        return EnrichedVoiceContext(
            voiceContext: voiceContext,
            windowContext: windowContext
        )
    }
}

// MARK: - Enriched Voice Context

/// Combines VoiceContextSnapshot with WindowContext from daemon
/// Note: VoiceContextSnapshot is defined in Voice/VoiceContextStore.swift
/// Note: EntityReference is defined in Cosmo/CosmoCore.swift
public struct EnrichedVoiceContext: Sendable {
    public let voiceContext: VoiceContextSnapshot?
    public let windowContext: WindowContext?

    public init(voiceContext: VoiceContextSnapshot?, windowContext: WindowContext?) {
        self.voiceContext = voiceContext
        self.windowContext = windowContext
    }

    /// Get combined context summary for LLM
    public var fullContextSummary: String {
        var parts: [String] = []

        if let vc = voiceContext {
            parts.append("Section: \(vc.selectedSection.rawValue)")

            if let blockId = vc.selectedBlockId {
                parts.append("Selected Block: \(blockId)")
            }

            if let editingType = vc.editingEntityType {
                parts.append("Editing: \(editingType.rawValue)")
            }
        }

        if let wc = windowContext {
            parts.append("---")
            parts.append(wc.contextSummary)
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Notification Integration

extension ContextCaptureClient {
    /// Start auto-capture on app switch
    public func startAutoCapture() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                try? await self?.captureContext(useCache: false)
            }
        }
    }

    /// Stop auto-capture
    public func stopAutoCapture() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
}
