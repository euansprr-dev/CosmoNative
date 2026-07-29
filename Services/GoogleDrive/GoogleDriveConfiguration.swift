// CosmoOS/Services/GoogleDrive/GoogleDriveConfiguration.swift
// The shape of the Google connection: which OAuth client we are, where the
// redirect lands, what we're allowed to touch, and how a failure is named.
//
// Cosmo authenticates as an *installed app* using the OAuth 2.0 flow for
// native clients: authorization code + PKCE, no client secret. That means the
// OAuth client registered in Google Cloud Console must be of type **iOS**
// (bundle id `com.cosmo.CosmoOS`), which issues a client ID and no secret —
// the only Google client type that is honest about a desktop binary's
// inability to keep a secret. The redirect URI is the reversed client ID,
// which ASWebAuthenticationSession intercepts in-process (no Info.plist
// registration required, and no loopback listener to leave open).
//
// SCOPE LAW: `drive.file` and nothing wider. It grants access only to files
// this app creates, which is exactly what an export feature needs, and it
// keeps Cosmo out of Google's *restricted* scope tier — the tier that demands
// an annual third-party security assessment. The consequence to design around
// is that we cannot enumerate the user's existing Drive: every destination
// folder must be one Cosmo created itself.
// July 2026

import Foundation
import CryptoKit

// MARK: - Configuration

enum GoogleDriveConfiguration {

    /// Compiled-in OAuth client ID. Fill this once with the client ID from
    /// Google Cloud Console (APIs & Services → Credentials → iOS client) and
    /// every Mac running this build gets a one-tap "Connect" with no setup.
    /// Left empty, the Settings card falls back to a one-time setup state.
    ///
    /// This is deliberately not a secret: Google's installed-app flow treats
    /// the client ID as public, and PKCE — not a shipped secret — is what
    /// actually binds the authorization code to this process.
    static let bundledClientID = ""

    /// Keychain first (set in Settings), then environment, then the bundled
    /// constant. Trimmed, because a pasted client ID almost always arrives
    /// with a trailing newline.
    static var clientID: String? {
        let candidates = [APIKeys.googleDriveClientID, bundledClientID]
        for candidate in candidates {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    static var isConfigured: Bool { clientID != nil }

    /// Google issues client IDs as `<digits>-<hash>.apps.googleusercontent.com`.
    /// We validate rather than trust, so a mistyped ID fails in Settings with a
    /// clear message instead of at the authorization screen with a Google 400.
    static func validate(clientID: String) -> Bool {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(clientIDSuffix) else { return false }
        let prefix = String(trimmed.dropLast(clientIDSuffix.count))
        return !prefix.isEmpty && prefix.contains("-")
    }

    private static let clientIDSuffix = ".apps.googleusercontent.com"

    /// The reversed client ID, which is both the custom URL scheme Google
    /// accepts for iOS clients and the `callbackURLScheme` we hand to
    /// ASWebAuthenticationSession.
    ///
    ///   `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    static func redirectScheme(for clientID: String) -> String? {
        guard validate(clientID: clientID) else { return nil }
        let identifier = String(clientID.dropLast(clientIDSuffix.count))
        return "com.googleusercontent.apps.\(identifier)"
    }

    /// Google's convention for reversed-client-ID redirects uses a single
    /// slash after the scheme — `scheme:/path`, not `scheme://path`.
    static func redirectURI(for clientID: String) -> String? {
        guard let scheme = redirectScheme(for: clientID) else { return nil }
        return "\(scheme):/oauth2redirect"
    }

    // MARK: - Scopes

    /// `drive.file` carries the write access. `openid` + `email` are
    /// non-sensitive and let the token response carry an id_token whose
    /// payload names the connected account — saving a separate userinfo call
    /// just to render "connected as …".
    static let scopes = [
        "https://www.googleapis.com/auth/drive.file",
        "openid",
        "email"
    ]

    static var scopeString: String { scopes.joined(separator: " ") }

    /// The scope whose absence means the connection is useless. Google may
    /// grant a subset of what we ask for if the user unticks a permission on
    /// the consent screen, so we verify rather than assume.
    static let requiredScope = "https://www.googleapis.com/auth/drive.file"

    // MARK: - Endpoints

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let driveAPIBase = URL(string: "https://www.googleapis.com/drive/v3")!
    static let driveUploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3")!

    /// Where the user goes to create the OAuth client, linked from the setup card.
    static let credentialsConsoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!

    // MARK: - Behaviour

    /// Refresh this far ahead of the stated expiry. Google's access tokens
    /// last an hour; a two-minute cushion absorbs clock skew and a slow
    /// upload that starts valid and would otherwise expire mid-flight.
    static let refreshMargin: TimeInterval = 120

    /// Uploads at or under this size go out as a single multipart request.
    /// Larger payloads use the resumable protocol so a dropped connection
    /// doesn't cost the whole transfer.
    static let multipartUploadCeiling = 5 * 1024 * 1024

    /// Resumable upload chunk size. Google requires chunks to be a multiple
    /// of 256 KiB (except the final one).
    static let resumableChunkSize = 8 * 1024 * 1024

    /// The folder Cosmo creates and owns in the user's Drive root.
    static let defaultFolderName = "Cosmo Exports"
}

// MARK: - PKCE

/// Proof Key for Code Exchange. The verifier never leaves this process until
/// the token exchange; the challenge is what travels through the browser. An
/// intercepted authorization code is worthless without the verifier, which is
/// what makes a secretless native client safe.
struct PKCEChallenge: Sendable, Equatable {
    let verifier: String
    let challenge: String
    let method = "S256"

    init() {
        self.verifier = Self.randomURLSafeString(byteCount: 64)
        self.challenge = Self.s256(self.verifier)
    }

    /// Deterministic initializer for tests.
    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.s256(verifier)
    }

    static func s256(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    /// RFC 7636 allows 43–128 characters from an unreserved alphabet. 64 random
    /// bytes base64url-encode to 86 characters, comfortably inside the range.
    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes failing is close to unthinkable, but silently
            // degrading to a weak verifier would defeat the whole mechanism.
            // AES.GCM's nonce generator draws from the same system entropy and
            // gives us a second, equally strong path.
            bytes = (0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// base64url without padding — the encoding RFC 7636 and JWT both use.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decode base64url (padding optional), for reading id_token payloads.
    static func fromBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - Token Set

/// A live Google session. The refresh token is the durable half — the access
/// token is disposable and re-minted on demand.
struct GoogleTokenSet: Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var grantedScope: String
    var accountEmail: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-GoogleDriveConfiguration.refreshMargin)
    }

    /// Google returns the scopes it actually granted, which can be narrower
    /// than what we asked for if the user unticked a box on the consent screen.
    var hasDriveAccess: Bool {
        grantedScope
            .split(separator: " ")
            .contains { $0 == GoogleDriveConfiguration.requiredScope }
    }
}

// MARK: - Errors

enum GoogleDriveError: LocalizedError, Equatable {
    /// No OAuth client ID compiled in or configured.
    case notConfigured
    /// The configured client ID isn't a well-formed Google client ID.
    case malformedClientID
    /// No stored session — the user has not connected, or has disconnected.
    case notConnected
    /// The refresh token was revoked, expired, or invalidated. This is the
    /// shape a Google Cloud consent screen left in "Testing" mode takes after
    /// seven days, and the shape a password change or a manual revoke takes
    /// immediately. Recovery is always: connect again.
    case reconnectRequired(String)
    /// The user closed the Google sign-in window.
    case authorizationCancelled
    case authorizationFailed(String)
    /// The `state` echoed by Google didn't match what we sent — the response
    /// is not ours and must not be trusted.
    case stateMismatch
    /// The user completed sign-in but withheld Drive permission.
    case driveScopeDeclined
    case tokenExchangeFailed(String)
    /// A Drive API call returned an error envelope.
    case api(status: Int, reason: String?, message: String)
    case driveStorageFull
    case uploadFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Drive isn't set up yet. Add an OAuth client ID in Settings → Connections."
        case .malformedClientID:
            return "That doesn't look like a Google OAuth client ID — it should end in .apps.googleusercontent.com"
        case .notConnected:
            return "Connect a Google account in Settings → Connections first."
        case .reconnectRequired(let detail):
            return "Google sign-in expired — reconnect in Settings → Connections. (\(detail))"
        case .authorizationCancelled:
            return "Google sign-in was cancelled."
        case .authorizationFailed(let detail):
            return "Google sign-in failed: \(detail)"
        case .stateMismatch:
            return "Google sign-in failed a security check and was discarded. Try again."
        case .driveScopeDeclined:
            return "Cosmo needs permission to add files to your Drive. Reconnect and leave that permission ticked."
        case .tokenExchangeFailed(let detail):
            return "Couldn't complete Google sign-in: \(detail)"
        case .api(let status, let reason, let message):
            if let reason { return "Google Drive error (\(status)/\(reason)): \(message)" }
            return "Google Drive error (\(status)): \(message)"
        case .driveStorageFull:
            return "Your Google Drive is out of storage space."
        case .uploadFailed(let detail):
            return "Upload to Google Drive failed: \(detail)"
        case .invalidResponse(let detail):
            return "Unexpected response from Google Drive: \(detail)"
        }
    }

    /// Whether the connection should be torn down and the user asked to sign
    /// in again. Everything else is a transient failure the user can retry.
    var invalidatesConnection: Bool {
        switch self {
        case .reconnectRequired, .driveScopeDeclined: return true
        default: return false
        }
    }
}
