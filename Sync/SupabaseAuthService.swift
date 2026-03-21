// CosmoOS/Sync/SupabaseAuthService.swift
// Supabase Auth via native Sign in with Apple (no browser redirect)
// Uses ASAuthorizationAppleIDProvider → identity token → Supabase signInWithIdToken

import Foundation
import AuthenticationServices
import Supabase
import CryptoKit

@MainActor
@Observable
final class SupabaseAuthService: NSObject {
    static let shared = SupabaseAuthService()

    // MARK: - Auth State

    enum AuthState: Equatable {
        case unknown
        case signedOut
        case signedIn(userId: String, email: String?)
        case signingIn
        case error(String)

        static func == (lhs: AuthState, rhs: AuthState) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown): return true
            case (.signedOut, .signedOut): return true
            case (.signedIn(let a, _), .signedIn(let b, _)): return a == b
            case (.signingIn, .signingIn): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    private(set) var authState: AuthState = .unknown
    private(set) var migrationState: MigrationState = .notStarted

    enum MigrationState: Equatable {
        case notStarted
        case inProgress(String, Int, Int)
        case complete
        case failed(String)

        static func == (lhs: MigrationState, rhs: MigrationState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted): return true
            case (.complete, .complete): return true
            case (.inProgress(let a, _, _), .inProgress(let b, _, _)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    var userId: String? {
        if case .signedIn(let id, _) = authState { return id }
        return nil
    }

    var userEmail: String? {
        if case .signedIn(_, let email) = authState { return email }
        return nil
    }

    // MARK: - Supabase Client (Official SDK — used for auth + realtime)

    let supabaseSDKClient: Supabase.SupabaseClient
    private var supabase: Supabase.SupabaseClient { supabaseSDKClient }

    // Nonce for Apple Sign In CSRF protection
    private var currentNonce: String?

    // Continuation for bridging ASAuthorization delegate callback to async/await
    private var signInContinuation: CheckedContinuation<ASAuthorization, Error>?

    private override init() {
        let url = APIKeys.supabaseUrl ?? "https://cskxozkzpzxyefqmgsgg.supabase.co"
        let key = APIKeys.supabaseAnonKey ?? ""

        self.supabaseSDKClient = Supabase.SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key
        )

        super.init()
    }

    // MARK: - Check Existing Session

    func checkExistingSession() async {
        if let savedToken = APIKeys.supabaseAuthToken,
           let savedUserId = APIKeys.supabaseUserId {
            do {
                let session = try await supabase.auth.session
                let uid = session.user.id.uuidString
                let email = session.user.email

                SupabaseClient.shared?.setAuthToken(session.accessToken)
                SupabaseClient.shared?.setUserId(uid)
                APIKeys.saveSupabaseAuth(token: session.accessToken, userId: uid)

                authState = .signedIn(userId: uid, email: email)
                print("✅ Supabase session restored for \(email ?? uid)")
                return
            } catch {
                SupabaseClient.shared?.setAuthToken(savedToken)
                SupabaseClient.shared?.setUserId(savedUserId)
                authState = .signedIn(userId: savedUserId, email: nil)
                print("⚠️ Supabase session restore failed, using saved token: \(error.localizedDescription)")
                return
            }
        }

        authState = .signedOut
    }

    // MARK: - Sign In with Apple (Native — No Browser)

    func signInWithApple() async {
        authState = .signingIn

        do {
            // Step 1: Get Apple credential via native ASAuthorization
            let appleCredential = try await requestAppleCredential()

            guard let appleIDCredential = appleCredential.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.invalidCredential("Not an Apple ID credential")
            }

            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                throw AuthError.invalidCredential("No identity token in Apple credential")
            }

            // Step 2: Exchange Apple identity token for Supabase session
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: currentNonce
                )
            )

            let uid = session.user.id.uuidString
            let email = session.user.email ?? appleIDCredential.email

            // Save to Keychain
            APIKeys.saveSupabaseAuth(token: session.accessToken, userId: uid)

            // Bridge to custom SupabaseClient
            SupabaseClient.shared?.setAuthToken(session.accessToken)
            SupabaseClient.shared?.setUserId(uid)

            authState = .signedIn(userId: uid, email: email)
            print("✅ Signed in with Apple: \(email ?? uid)")

            // Start Realtime sync
            RealtimeSyncService.shared.startListening()

            // Trigger initial data migration
            await triggerMigrationIfNeeded()

        } catch {
            authState = .error(error.localizedDescription)
            print("❌ Sign in with Apple failed: \(error)")
        }
    }

    /// Request Apple credential using ASAuthorizationAppleIDProvider (native sheet, no browser)
    private func requestAppleCredential() async throws -> ASAuthorization {
        let nonce = generateNonce()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            print("⚠️ Supabase sign out error: \(error)")
        }

        APIKeys.clearSupabaseAuth()
        SupabaseClient.shared?.setAuthToken(nil)
        SupabaseClient.shared?.setUserId(nil)
        RealtimeSyncService.shared.stopListening()
        authState = .signedOut
    }

    // MARK: - Data Migration

    func triggerMigrationIfNeeded() async {
        guard !DataMigrationService.shared.isMigrationComplete else {
            migrationState = .complete
            return
        }

        // Pause Realtime during migration to prevent echo loop
        RealtimeSyncService.shared.isPaused = true
        migrationState = .inProgress("Starting migration...", 0, 100)

        do {
            try await DataMigrationService.shared.migrateToSupabase { label, current, total in
                Task { @MainActor in
                    self.migrationState = .inProgress(label, current, total)
                }
            }
            migrationState = .complete
            RealtimeSyncService.shared.isPaused = false
            print("✅ Data migration complete")
        } catch {
            migrationState = .failed(error.localizedDescription)
            RealtimeSyncService.shared.isPaused = false
            print("❌ Data migration failed: \(error)")
        }
    }

    // MARK: - Refresh Token

    func refreshSessionIfNeeded() async {
        guard isSignedIn else { return }

        do {
            let session = try await supabase.auth.session
            APIKeys.saveSupabaseAuth(token: session.accessToken, userId: session.user.id.uuidString)
            SupabaseClient.shared?.setAuthToken(session.accessToken)
        } catch {
            print("⚠️ Token refresh failed: \(error)")
        }
    }

    // MARK: - Nonce Helpers

    private func generateNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess { fatalError("Unable to generate nonce") }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension SupabaseAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            signInContinuation?.resume(returning: authorization)
            signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            signInContinuation?.resume(throwing: error)
            signInContinuation = nil
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredential(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidCredential(let reason): return "Invalid credential: \(reason)"
        case .sessionExpired: return "Session expired — please sign in again"
        }
    }
}
