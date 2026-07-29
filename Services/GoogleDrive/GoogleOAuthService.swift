// CosmoOS/Services/GoogleDrive/GoogleOAuthService.swift
// The token lifecycle: sign in, mint, refresh, revoke.
//
// Every other "connection" in Cosmo is a pasted static key that never expires
// and never rotates. A real OAuth session is different in three ways this file
// exists to handle:
//
//   1. The access token dies hourly and must be re-minted from a refresh token.
//   2. Concurrent callers must never each start their own refresh — hence the
//      SINGLE-FLIGHT LAW below.
//   3. The refresh token itself can be revoked out from under us at any time,
//      by the user, by a password change, or by Google's own seven-day expiry
//      on consent screens still in "Testing". That failure has exactly one
//      remedy — sign in again — so it is modelled as its own error case and
//      tears the session down rather than retrying forever.
//
// SINGLE-FLIGHT LAW: all refreshes funnel through `refreshTask`. Two uploads
// racing on an expired token must await one shared refresh, not two. Google
// rotates nothing on a plain refresh, but a doubled refresh is a wasted round
// trip at best and a rate-limit at worst — and the second writer would clobber
// the first's Keychain write.
// July 2026

import Foundation
import AuthenticationServices
import AppKit

// MARK: - Authorization Presenter

/// Owns the ASWebAuthenticationSession for the duration of one sign-in. Lives
/// on the main actor because the session needs a window to hang itself off.
@MainActor
final class GoogleAuthorizationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// ASWebAuthenticationSession cancels itself the moment nothing holds it,
    /// so the session has to outlive the closure that made it. It can't live on
    /// `self` — the continuation body runs outside this class's isolation — so
    /// it lives in a box the async function keeps alive across the await.
    /// `hasResumed` rides along because the completion handler and the
    /// `start()` failure path are two mouths on one continuation, and resuming
    /// a continuation twice is a crash, not a warning.
    private final class SessionBox: @unchecked Sendable {
        var session: ASWebAuthenticationSession?
        var hasResumed = false
    }

    /// Presents Google's consent screen and resolves with the redirect URL.
    /// Not ephemeral: reusing the user's existing Safari Google session is what
    /// makes this feel like "Continue as Euan" rather than a fresh login.
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let box = SessionBox()
        defer { box.session = nil }

        return try await withCheckedThrowingContinuation { continuation in
            func finish(_ result: Result<URL, Error>) {
                guard !box.hasResumed else { return }
                box.hasResumed = true
                continuation.resume(with: result)
            }

            let authSession = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        finish(.failure(GoogleDriveError.authorizationCancelled))
                    } else {
                        finish(.failure(GoogleDriveError.authorizationFailed(error.localizedDescription)))
                    }
                    return
                }
                guard let callbackURL else {
                    finish(.failure(GoogleDriveError.authorizationFailed("No response from Google")))
                    return
                }
                finish(.success(callbackURL))
            }

            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            box.session = authSession

            if !authSession.start() {
                finish(.failure(GoogleDriveError.authorizationFailed(
                    "Couldn't open the Google sign-in window"
                )))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
    }
}

// MARK: - OAuth Service

actor GoogleOAuthService {
    static let shared = GoogleOAuthService()

    private var cached: GoogleTokenSet?
    private var didLoadFromKeychain = false
    private var refreshTask: Task<GoogleTokenSet, Error>?

    private init() {}

    // MARK: - Session State

    /// Rehydrate from the Keychain once per launch. The access token is kept
    /// across quits purely as an optimisation — if it's stale we refresh, and
    /// if it's missing entirely the refresh token still rebuilds the session.
    private func loadIfNeeded() {
        guard !didLoadFromKeychain else { return }
        didLoadFromKeychain = true

        guard let refreshToken = APIKeys.googleDriveRefreshToken, !refreshToken.isEmpty else {
            return
        }
        let expiry = APIKeys.googleDriveTokenExpiry
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))

        cached = GoogleTokenSet(
            accessToken: APIKeys.googleDriveAccessToken ?? "",
            refreshToken: refreshToken,
            // No stored expiry means "assume stale" — a needless refresh is
            // cheap, a request with a dead token costs a round trip and a 401.
            expiresAt: expiry ?? .distantPast,
            grantedScope: APIKeys.googleDriveScope ?? GoogleDriveConfiguration.requiredScope,
            accountEmail: APIKeys.googleDriveAccount
        )
    }

    func hasSession() -> Bool {
        loadIfNeeded()
        return cached != nil
    }

    func accountEmail() -> String? {
        loadIfNeeded()
        return cached?.accountEmail
    }

    // MARK: - Connect

    /// The full interactive flow: consent screen → authorization code → tokens.
    @discardableResult
    func connect() async throws -> GoogleTokenSet {
        guard let clientID = GoogleDriveConfiguration.clientID else {
            throw GoogleDriveError.notConfigured
        }
        guard
            let redirectURI = GoogleDriveConfiguration.redirectURI(for: clientID),
            let callbackScheme = GoogleDriveConfiguration.redirectScheme(for: clientID)
        else {
            throw GoogleDriveError.malformedClientID
        }

        let pkce = PKCEChallenge()
        let state = PKCEChallenge.randomURLSafeString(byteCount: 24)
        let authURL = try buildAuthorizationURL(
            clientID: clientID,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state
        )

        let presenter = await GoogleAuthorizationPresenter()
        let callbackURL = try await presenter.authorize(url: authURL, callbackScheme: callbackScheme)
        let code = try authorizationCode(from: callbackURL, expectedState: state)

        let tokens = try await exchange(
            code: code,
            verifier: pkce.verifier,
            clientID: clientID,
            redirectURI: redirectURI
        )

        // A user who unticks the Drive permission completes sign-in and hands
        // us a token that can't do the one thing we need. Fail loudly here
        // rather than at the first upload.
        guard tokens.hasDriveAccess else {
            throw GoogleDriveError.driveScopeDeclined
        }

        persist(tokens)
        return tokens
    }

    private func buildAuthorizationURL(
        clientID: String,
        redirectURI: String,
        pkce: PKCEChallenge,
        state: String
    ) throws -> URL {
        var components = URLComponents(
            url: GoogleDriveConfiguration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfiguration.scopeString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            // Installed apps get refresh tokens by default, but saying so
            // explicitly costs nothing and documents the intent.
            URLQueryItem(name: "access_type", value: "offline"),
            // Force the consent screen every time. Without it Google withholds
            // the refresh token on any re-authorization, which would leave a
            // reconnect with no durable half and a session that dies in an hour.
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components?.url else {
            throw GoogleDriveError.authorizationFailed("Couldn't build the sign-in URL")
        }
        return url
    }

    /// Pull the code out of the redirect, rejecting anything whose `state`
    /// doesn't match the one we generated for this attempt.
    private func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            if error == "access_denied" { throw GoogleDriveError.authorizationCancelled }
            throw GoogleDriveError.authorizationFailed(value("error_description") ?? error)
        }
        guard let returnedState = value("state"), returnedState == expectedState else {
            throw GoogleDriveError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GoogleDriveError.authorizationFailed("Google didn't return an authorization code")
        }
        return code
    }

    // MARK: - Token Exchange

    private func exchange(
        code: String,
        verifier: String,
        clientID: String,
        redirectURI: String
    ) async throws -> GoogleTokenSet {
        let response = try await postToTokenEndpoint([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])

        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw GoogleDriveError.tokenExchangeFailed(
                "Google didn't return a refresh token — try disconnecting the app at myaccount.google.com/permissions and connecting again"
            )
        }

        return GoogleTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            grantedScope: response.scope ?? GoogleDriveConfiguration.scopeString,
            accountEmail: response.idToken.flatMap(Self.email(fromIDToken:))
        )
    }

    // MARK: - Access

    /// The one entry point every Drive call funnels through.
    func validAccessToken() async throws -> String {
        loadIfNeeded()
        guard let current = cached else { throw GoogleDriveError.notConnected }
        guard current.isExpired || current.accessToken.isEmpty else {
            return current.accessToken
        }
        return try await refresh().accessToken
    }

    /// Refresh regardless of what our clock thinks. Called exactly once by the
    /// Drive client when a request comes back 401 — the server's opinion of
    /// token validity outranks ours.
    @discardableResult
    func forceRefresh() async throws -> GoogleTokenSet {
        loadIfNeeded()
        guard cached != nil else { throw GoogleDriveError.notConnected }
        return try await refresh()
    }

    /// SINGLE-FLIGHT LAW — see the file header.
    private func refresh() async throws -> GoogleTokenSet {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> GoogleTokenSet {
        guard let current = cached else { throw GoogleDriveError.notConnected }
        guard let clientID = GoogleDriveConfiguration.clientID else {
            throw GoogleDriveError.notConfigured
        }

        do {
            let response = try await postToTokenEndpoint([
                "client_id": clientID,
                "refresh_token": current.refreshToken,
                "grant_type": "refresh_token"
            ])

            let refreshed = GoogleTokenSet(
                accessToken: response.accessToken,
                // A refresh response usually omits the refresh token, meaning
                // "the one you have still stands". Only replace it when Google
                // actually rotates it.
                refreshToken: response.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? current.refreshToken,
                expiresAt: Date().addingTimeInterval(response.expiresIn),
                grantedScope: response.scope ?? current.grantedScope,
                accountEmail: response.idToken.flatMap(Self.email(fromIDToken:)) ?? current.accountEmail
            )
            persist(refreshed)
            return refreshed
        } catch let error as GoogleDriveError {
            // A dead refresh token is terminal. Clear the session so the UI
            // stops claiming a connection that no longer exists.
            if error.invalidatesConnection {
                clearSession()
            }
            throw error
        }
    }

    // MARK: - Disconnect

    /// Revoke at Google, then forget locally. Revocation is best-effort: if the
    /// network is down, the local session still goes away — a disconnect that
    /// silently fails is worse than one that leaves a stale grant behind, and
    /// the user can always finish the job at myaccount.google.com/permissions.
    func disconnect() async {
        loadIfNeeded()
        let token = cached?.refreshToken
        clearSession()

        guard let token, !token.isEmpty else { return }
        var request = URLRequest(url: GoogleDriveConfiguration.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(["token": token]).data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Persistence

    private func persist(_ tokens: GoogleTokenSet) {
        cached = tokens
        didLoadFromKeychain = true
        APIKeys.saveGoogleDriveSession(
            refreshToken: tokens.refreshToken,
            accessToken: tokens.accessToken,
            expiresAt: tokens.expiresAt,
            scope: tokens.grantedScope,
            accountEmail: tokens.accountEmail
        )
    }

    private func clearSession() {
        cached = nil
        didLoadFromKeychain = true
        APIKeys.clearGoogleDriveSession()
    }

    // MARK: - Token Endpoint

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
        let scope: String?
        let idToken: String?
    }

    private func postToTokenEndpoint(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleDriveConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(parameters).data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await withNetworkRetry(label: "GoogleOAuth") {
            try await URLSession.shared.data(for: request)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleDriveError.invalidResponse("Token endpoint returned unreadable data")
        }

        if response.statusCode >= 400 {
            let code = json["error"] as? String ?? "unknown_error"
            let detail = json["error_description"] as? String ?? code
            // `invalid_grant` is Google's single word for "that refresh token
            // is dead" — revoked, expired, or issued by a consent screen still
            // in Testing mode more than seven days ago.
            if code == "invalid_grant" {
                throw GoogleDriveError.reconnectRequired(detail)
            }
            throw GoogleDriveError.tokenExchangeFailed(detail)
        }

        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw GoogleDriveError.invalidResponse("Token endpoint returned no access token")
        }

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: (json["expires_in"] as? Double) ?? 3600,
            scope: json["scope"] as? String,
            idToken: json["id_token"] as? String
        )
    }

    static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    /// Read the email out of an id_token's payload.
    ///
    /// Deliberately unverified: this JWT arrived in the body of a TLS response
    /// from Google's own token endpoint, in reply to a request we made. It is
    /// used only to render "connected as …" — never to authorize anything —
    /// so signature verification would buy nothing over the transport
    /// guarantee we already have.
    static func email(fromIDToken idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2,
              let payload = Data.fromBase64URL(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}
