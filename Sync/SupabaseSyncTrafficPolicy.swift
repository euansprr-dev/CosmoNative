import Foundation
import Realtime

extension ProcessInfo {
    /// True when running inside an XCTest host. Sync must NEVER touch the real
    /// Supabase project from tests: the local database is sandboxed to a temp
    /// path, but the keychain (and therefore the authenticated Supabase session)
    /// is the developer's real one — an unguarded push writes test fixtures into
    /// production cloud data that other devices then pull.
    var isRunningTests: Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        return arguments.contains { argument in
            argument.hasSuffix(".xctest") || argument.contains("/XCTest")
        }
    }
}

enum SupabaseSyncTrafficPolicy {
    static let localSource = "mac"
    static let sourceColumn = "_source"

    /// Master kill-switch for ALL Supabase traffic (push, pull, realtime).
    /// False under tests — see ProcessInfo.isRunningTests.
    static var allowsNetworkSync: Bool {
        !ProcessInfo.processInfo.isRunningTests
    }

    static var remoteOnlyQueryItem: URLQueryItem {
        URLQueryItem(name: sourceColumn, value: "neq.\(localSource)")
    }

    static var remoteOnlyRealtimeFilter: RealtimePostgresFilter {
        .neq(sourceColumn, value: localSource)
    }

    static func shouldApplyRemoteChange(source: String?) -> Bool {
        guard let source else { return false }
        return source != localSource
    }

    static func shouldAttemptPush(isAuthenticated: Bool) -> Bool {
        allowsNetworkSync && isAuthenticated
    }
}

struct SyncFailureResolution: Equatable {
    let status: String
    let retryCount: Int
    let shouldClearLocalPending: Bool
    let shouldPauseFurtherAttempts: Bool
}

enum SyncFailurePolicy {
    static func resolve(
        currentRetryCount: Int,
        maxRetries: Int,
        error: Error
    ) -> SyncFailureResolution {
        if error.isSupabaseQuotaExceeded || error.isSupabaseAuthOrPolicyRejected {
            return SyncFailureResolution(
                status: "pending",
                retryCount: currentRetryCount,
                shouldClearLocalPending: false,
                shouldPauseFurtherAttempts: true
            )
        }

        let retryCount = currentRetryCount + 1
        let status = retryCount >= maxRetries ? "failed" : "pending"
        return SyncFailureResolution(
            status: status,
            retryCount: retryCount,
            shouldClearLocalPending: status == "failed",
            shouldPauseFurtherAttempts: false
        )
    }
}

extension SupabaseError {
    var statusCode: Int? {
        switch self {
        case .insertFailed(let statusCode),
             .updateFailed(let statusCode),
             .upsertFailed(let statusCode, _):
            return statusCode
        case .invalidURL, .fetchFailed, .invalidResponse, .authRequired:
            return nil
        }
    }

    var isQuotaExceeded: Bool {
        statusCode == 402
    }

    var isAuthOrPolicyRejected: Bool {
        switch self {
        case .authRequired:
            return true
        case .insertFailed(let statusCode),
             .updateFailed(let statusCode),
             .upsertFailed(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .invalidURL, .fetchFailed, .invalidResponse:
            return false
        }
    }
}

extension Error {
    var isSupabaseQuotaExceeded: Bool {
        (self as? SupabaseError)?.isQuotaExceeded == true
    }

    var isSupabaseAuthOrPolicyRejected: Bool {
        (self as? SupabaseError)?.isAuthOrPolicyRejected == true
    }
}
