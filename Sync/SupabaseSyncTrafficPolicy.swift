import Foundation
import Realtime
import Auth

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
        shouldAttemptPush(isAuthenticated: isAuthenticated, allowsNetworkSync: allowsNetworkSync)
    }

    /// Testable core: the production overload injects the live kill-switch
    /// (which is always false inside a test host).
    static func shouldAttemptPush(isAuthenticated: Bool, allowsNetworkSync: Bool) -> Bool {
        allowsNetworkSync && isAuthenticated
    }
}

/// Decides whether a failed session refresh means the session is truly dead.
///
/// Destroying a live session is the catastrophic direction: sync dies silently
/// (every push guard returns early, the queue accumulates, Realtime drops) until
/// the user manually re-signs in. So only errors where the auth server itself
/// rejected the session tear it down — anything else (offline wake, DNS, 5xx,
/// rate limit) keeps the session and retries on the next sync pass.
enum SupabaseSessionRefreshPolicy {
    /// Error codes where the server said this session can never work again.
    private static let terminalCodes: Set<Auth.ErrorCode> = [
        .sessionNotFound,
        .sessionExpired,
        .refreshTokenNotFound,
        .refreshTokenAlreadyUsed,
        .invalidCredentials,
        .userNotFound,
        .userBanned,
    ]

    static func isTerminalAuthError(_ error: Error) -> Bool {
        // Auth.AuthError explicitly: the app declares its own `AuthError` enum
        // (SupabaseAuthService.swift) which would otherwise win the lookup and
        // make this cast never match the SDK's error.
        guard let authError = error as? Auth.AuthError else { return false }
        switch authError {
        case .sessionMissing:
            return true
        case .api(_, let errorCode, _, _):
            return terminalCodes.contains(errorCode)
        default:
            return false
        }
    }
}

struct SyncFailureResolution: Equatable {
    let status: String
    let retryCount: Int
    let shouldClearLocalPending: Bool
    let shouldPauseFurtherAttempts: Bool
}

enum SyncFailurePolicy {
    /// Going offline is not a bad record. Pause the pass without spending
    /// its retry budget or eventually dead-lettering an otherwise valid edit.
    static func isTransientFailure(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .dataNotAllowed, .internationalRoamingOff, .cancelled].contains(error.code)
        }
        if let status = (error as? SupabaseError)?.statusCode {
            return status == 429 || (500...599).contains(status)
        }
        return false
    }

    static func resolve(
        currentRetryCount: Int,
        maxRetries: Int,
        error: Error
    ) -> SyncFailureResolution {
        if error.isSupabaseQuotaExceeded || error.isSupabaseAuthOrPolicyRejected || isTransientFailure(error) {
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
             .updateFailed(let statusCode, _),
             .upsertFailed(let statusCode, _):
            return statusCode
        case .invalidURL, .fetchFailed, .invalidResponse, .authRequired, .missingRow:
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
             .updateFailed(let statusCode, _),
             .upsertFailed(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .invalidURL, .fetchFailed, .invalidResponse, .missingRow:
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
