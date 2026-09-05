// CosmoOS/Sync/SupabaseAuthService.swift
// Supabase Auth via native Sign in with Apple (no browser redirect)
// Uses ASAuthorizationAppleIDProvider → identity token → Supabase signInWithIdToken

import Foundation
import AuthenticationServices
import Supabase
import CryptoKit
import Security

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

    // MARK: - Workspace mode (the gate contract — paired with iOS)
    //
    // The Welcome gate blocks ONLY when this Mac holds no workspace: neither
    // a signed-in account nor a chosen local-only workspace. Token expiry
    // keeps `.cloud` (workspace stays visible, re-auth notice shows); an
    // explicit sign-out keeps local data on Mac, so the workspace remains.
    enum WorkspaceMode: String {
        case local
        case cloud
    }

    private static let workspaceModeKey = "cosmo.workspace.mode"

    private(set) var workspaceMode: WorkspaceMode? =
        UserDefaults.standard.string(forKey: workspaceModeKey).flatMap(WorkspaceMode.init)

    private func setWorkspaceMode(_ mode: WorkspaceMode?) {
        workspaceMode = mode
        if let mode {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.workspaceModeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.workspaceModeKey)
        }
    }

    /// "Continue offline — sync later." Every write still queues in
    /// sync_queue; a later sign-in migrates + uploads the full backlog.
    func establishLocalWorkspace() {
        guard workspaceMode == nil else { return }
        setWorkspaceMode(.local)
    }

    /// The Welcome threshold shows only over an empty Mac — never as a wall
    /// in front of real work. Existing pre-auth workspaces are adopted as
    /// `.local` at launch (CosmoApp.initializeApp) before this can go true.
    var showsWelcomeGate: Bool {
        if case .signedOut = authState { return workspaceMode == nil }
        return false
    }

    /// Local-first restore: saved keychain credentials flip the UI to
    /// signed-in IMMEDIATELY — no network wait, no Welcome flash. The async
    /// checkExistingSession still validates and refreshes right after.
    func restoreFromKeychainInstantly() {
        guard case .unknown = authState else { return }
        guard let savedToken = APIKeys.supabaseAuthToken,
              let savedUserId = APIKeys.supabaseUserId else { return }
        SupabaseClient.shared?.setAuthToken(savedToken)
        SupabaseClient.shared?.setUserId(savedUserId)
        authState = .signedIn(userId: savedUserId, email: nil)
        setWorkspaceMode(.cloud)
    }

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
        // Ensure Keychain has the correct credentials BEFORE reading them
        APIKeys.seedSupabaseIfNeeded()

        let url = APIKeys.supabaseUrl ?? "https://cskxozkzpzxyefqmgsgg.supabase.co"
        let key = APIKeys.supabaseAnonKey ?? ""

        self.supabaseSDKClient = Supabase.SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key,
            options: .init(auth: .init(storage: SupabaseSessionKeychainStorage()))
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
                setWorkspaceMode(.cloud)
                print("✅ Supabase session restored for \(email ?? uid)")
                return
            } catch {
                SupabaseClient.shared?.setAuthToken(savedToken)
                SupabaseClient.shared?.setUserId(savedUserId)
                authState = .signedIn(userId: savedUserId, email: nil)
                setWorkspaceMode(.cloud)
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
            // A local-only workspace signing in becomes a cloud workspace —
            // migration + the queued backlog upload through the flows below.
            setWorkspaceMode(.cloud)
            print("✅ Signed in with Apple: \(email ?? uid)")

            // Start Realtime sync
            RealtimeSyncService.shared.startListening()

            // Trigger initial data migration
            await triggerMigrationIfNeeded()

            // Flush anything queued while signed out — a re-sign-in after a
            // session loss must drain the backlog now, not in ≤5 minutes.
            Task { await SyncEngine.shared.forceSync() }

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
        // Mac sign-out keeps local data, so the workspace continues as
        // local-only — the Welcome gate never walls off existing work.
        setWorkspaceMode(.local)
        authState = .signedOut
    }

    // MARK: - Data Migration

    func triggerMigrationIfNeeded() async {
        guard !DataMigrationService.shared.isMigrationComplete else {
            migrationState = .complete
            return
        }

        // Refresh auth token before migration (prevents JWT expired errors)
        await refreshSessionIfNeeded()

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
            // Try to refresh the session (SDK handles refresh token exchange)
            let session = try await supabase.auth.session
            let token = session.accessToken
            let uid = session.user.id.uuidString

            APIKeys.saveSupabaseAuth(token: token, userId: uid)
            SupabaseClient.shared?.setAuthToken(token)
            SupabaseClient.shared?.setUserId(uid)
            print("🔄 Auth token refreshed")
        } catch {
            // Tear the session down ONLY when the auth server itself rejected it.
            // A transient failure (offline wake, DNS, 5xx) must keep the session:
            // clearing it here silently killed ALL sync — pushes bailed at the
            // auth guard with no error recorded, the queue accumulated for hours,
            // and other devices drifted — until a manual re-sign-in.
            guard SupabaseSessionRefreshPolicy.isTerminalAuthError(error) else {
                print("⚠️ Token refresh failed (transient, keeping session): \(error)")
                PersistenceHealth.note(
                    .syncFailure,
                    context: "SupabaseAuth.refreshSession",
                    detail: "transient refresh failure, will retry next sync pass: \(error.localizedDescription)"
                )
                return
            }

            print("⛔️ Supabase session rejected by server: \(error) — signing out")
            PersistenceHealth.note(
                .syncFailure,
                context: "SupabaseAuth.sessionExpired",
                detail: "Session expired — sync is paused until you sign in again (Settings → Account). Local changes are safe and queued."
            )
            APIKeys.clearSupabaseAuth()
            SupabaseClient.shared?.setAuthToken(nil)
            SupabaseClient.shared?.setUserId(nil)
            RealtimeSyncService.shared.stopListening()
            authState = .signedOut
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

// MARK: - Non-interactive SDK session storage

/// The SDK default uses the file-based login keychain, whose per-build ACL can
/// prompt repeatedly during SDK migrations and refresh. Keep sessions in the
/// Data Protection Keychain, matching APIKeys, and never prompt from background
/// auth work. Never inspect the legacy keychain: its ACL dialogs can ignore
/// kSecUseAuthenticationUIFail. Accounts stored only there must sign in again.
struct SupabaseSessionKeychainStorage: AuthLocalStorage {
    var read: @Sendable ([String: Any]) -> (OSStatus, Data?) = { query in
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    var add: @Sendable ([String: Any]) -> OSStatus = {
        SecItemAdd($0 as CFDictionary, nil)
    }
    var update: @Sendable ([String: Any], [String: Any]) -> OSStatus = {
        SecItemUpdate($0 as CFDictionary, $1 as CFDictionary)
    }

    private func query(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "supabase.gotrue.swift",
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
            // This flag is effective for the Data Protection Keychain only.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
    }

    func store(key: String, value: Data) throws {
        let match = query(key: key)
        let attributes = [kSecValueData as String: value]
        // Update first: never delete a valid refresh token before a write succeeds.
        let status = update(match, attributes)
        if status == errSecItemNotFound {
            var item = match
            item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = add(item)
            if added == errSecDuplicateItem {
                try check(update(match, attributes))
            } else {
                try check(added)
            }
        } else {
            try check(status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var match = query(key: key)
        match[kSecReturnData as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = read(match)
        if status == errSecItemNotFound { return nil }
        try check(status)
        // Honor sign-out tombstones written by previous builds.
        return data.flatMap { $0.isEmpty ? nil : $0 }
    }

    func remove(key: String) throws {
        // Keep the tombstone for compatibility with older installed builds that
        // still attempt legacy migration. No secret remains in this item.
        try store(key: key, value: Data())
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Secure session storage is unavailable (\(status)). Sign in again in Settings if needed."
            ])
        }
    }
}
