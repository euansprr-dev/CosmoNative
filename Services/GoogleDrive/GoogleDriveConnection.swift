// CosmoOS/Services/GoogleDrive/GoogleDriveConnection.swift
// The connection as the UI sees it: one state machine, one export entry point.
//
// Settings and the ship sheet both talk to this object and nothing below it.
// That matters because a connection can die between the moment Settings last
// rendered "Connected" and the moment an export runs — so the *export path*,
// not the settings screen, is what discovers a revoked grant. Routing both
// through here means the card updates itself the instant an upload finds out.
//
// FOLDER LAW: the destination is always a folder Cosmo created. `drive.file`
// gives us no view of the user's existing Drive, so "pick any folder" is not a
// thing we can offer honestly. What we can do — and do — is create a real
// folder, remember it by ID, and let the user move or rename it in Drive
// afterwards without breaking anything.
// July 2026

import Foundation
import Observation

@MainActor
@Observable
final class GoogleDriveConnection {
    static let shared = GoogleDriveConnection()

    enum State: Equatable {
        /// No OAuth client ID — the app itself isn't registered yet.
        case needsSetup
        case disconnected
        case connecting
        case connected(email: String, displayName: String?)
        /// The grant was revoked or expired. Recoverable only by signing in again.
        case needsReconnect(reason: String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private(set) var state: State = .disconnected
    private(set) var lastError: String?
    private(set) var isVerifying = false

    /// The destination folder. Name is cached for display so the card can
    /// render without a network round trip.
    private(set) var folderID: String?
    private(set) var folderName: String

    private let auth: GoogleOAuthService
    private let client: GoogleDriveClient

    private let folderIDKey = "googleDriveFolderID"
    private let folderNameKey = "googleDriveFolderName"

    private init(auth: GoogleOAuthService = .shared, client: GoogleDriveClient = .shared) {
        self.auth = auth
        self.client = client
        self.folderID = UserDefaults.standard.string(forKey: folderIDKey)
        self.folderName = UserDefaults.standard.string(forKey: folderNameKey)
            ?? GoogleDriveConfiguration.defaultFolderName
    }

    // MARK: - State

    /// Local-only state read: does a client ID exist, and is there a stored
    /// refresh token? No network, safe to call on every appearance.
    func refreshState() async {
        guard GoogleDriveConfiguration.isConfigured else {
            state = .needsSetup
            return
        }
        // A live reconnect prompt outranks the stored session — the token is
        // still in the Keychain, it's just dead, and re-reading it would make
        // the card claim a connection the next upload will refuse. A sign-in
        // already in flight owns the state until it finishes.
        if case .needsReconnect = state { return }
        if case .connecting = state { return }
        await resolveFromStorage()
    }

    /// The same read without the guards, for the paths that own the transition
    /// themselves. `connect()` must use this on its way out of `.connecting` —
    /// going through `refreshState()` there would hit the in-flight guard and
    /// strand the card on "Waiting for Google…" after a cancelled sign-in.
    private func resolveFromStorage() async {
        if await auth.hasSession() {
            let email = await auth.accountEmail()
            state = .connected(email: email ?? "Google account", displayName: nil)
        } else {
            state = .disconnected
        }
    }

    /// Ask Drive who we are. Confirms the grant is genuinely live and fills in
    /// the display name.
    func verify() async {
        guard state.isConnected else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let account = try await client.accountInfo()
            state = .connected(email: account.email, displayName: account.displayName)
            lastError = nil
        } catch {
            handle(error)
        }
    }

    // MARK: - Connect / Disconnect

    func connect() async {
        guard GoogleDriveConfiguration.isConfigured else {
            state = .needsSetup
            return
        }
        lastError = nil
        state = .connecting
        do {
            try await auth.connect()
            let account = try await client.accountInfo()
            state = .connected(email: account.email, displayName: account.displayName)
            // Materialize the folder now so the first export isn't the thing
            // that discovers a permissions problem.
            _ = try? await ensureDestinationFolder()
        } catch GoogleDriveError.authorizationCancelled {
            // Backing out of the Google window isn't an error worth shouting about.
            await resolveFromStorage()
        } catch {
            state = .disconnected
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        await auth.disconnect()
        // Every remembered file ID belonged to the account that just left.
        DriveExportLedger.shared.clear()
        folderID = nil
        UserDefaults.standard.removeObject(forKey: folderIDKey)
        lastError = nil
        state = .disconnected
    }

    // MARK: - Client ID (one-time app registration)

    func saveClientID(_ clientID: String) -> Bool {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GoogleDriveConfiguration.validate(clientID: trimmed) else {
            lastError = GoogleDriveError.malformedClientID.localizedDescription
            return false
        }
        APIKeys.save(trimmed, identifier: "google_drive_client_id")
        lastError = nil
        state = .disconnected
        return true
    }

    /// Changing the OAuth client invalidates any session issued by the old
    /// one, so this tears the connection down with it.
    func clearClientID() async {
        await disconnect()
        APIKeys.delete(identifier: "google_drive_client_id")
        state = .needsSetup
    }

    // MARK: - Destination Folder

    /// Resolve the folder to export into, re-creating it if the user deleted
    /// it in Drive. Always validated against the live file — a remembered ID
    /// is a hint, never a guarantee.
    @discardableResult
    func ensureDestinationFolder() async throws -> DriveFile {
        if let folderID, let existing = try await client.file(id: folderID), existing.isFolder {
            applyFolder(existing)
            return existing
        }
        let folder = try await client.ensureFolder(named: folderName)
        applyFolder(folder)
        return folder
    }

    /// Folders Cosmo has created — the complete set we're allowed to see.
    func availableFolders() async throws -> [DriveFile] {
        try await client.listAppFolders()
    }

    func selectFolder(_ folder: DriveFile) {
        applyFolder(folder)
    }

    @discardableResult
    func createFolder(named name: String) async throws -> DriveFile {
        let trimmed = DriveExportBuilder.sanitize(name)
        let folder = try await client.createFolder(
            named: trimmed.isEmpty ? GoogleDriveConfiguration.defaultFolderName : trimmed
        )
        applyFolder(folder)
        return folder
    }

    private func applyFolder(_ folder: DriveFile) {
        folderID = folder.id
        folderName = folder.name
        UserDefaults.standard.set(folder.id, forKey: folderIDKey)
        UserDefaults.standard.set(folder.name, forKey: folderNameKey)
    }

    // MARK: - Export

    /// The one path content takes to Drive.
    ///
    /// Re-exporting the same draft in the same format updates the document
    /// that's already there, so the link the user shared stays the link that
    /// shows the newest version — and Drive keeps the previous one in its own
    /// revision history.
    @discardableResult
    func export(
        atomUUID: String,
        title: String,
        platform: ExportPlatform,
        sections: [ExportSection],
        format: DriveExportFormat,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DriveFile {
        guard !sections.isEmpty else {
            throw GoogleDriveError.uploadFailed("There's nothing to export yet.")
        }
        guard GoogleDriveConfiguration.isConfigured else { throw GoogleDriveError.notConfigured }
        guard await auth.hasSession() else { throw GoogleDriveError.notConnected }

        do {
            let folder = try await ensureDestinationFolder()
            let document = DriveExportBuilder.document(
                title: title,
                platform: platform,
                sections: sections,
                format: format
            )
            let previous = DriveExportLedger.shared.record(
                atomUUID: atomUUID, platform: platform, format: format
            )

            let file = try await client.upload(
                document,
                toFolderID: folder.id,
                replacingFileID: previous?.fileID,
                onProgress: onProgress
            )

            DriveExportLedger.shared.store(
                DriveExportRecord(
                    fileID: file.id,
                    fileName: file.name,
                    webViewLink: file.webViewLink,
                    exportedAt: Date()
                ),
                atomUUID: atomUUID,
                platform: platform,
                format: format
            )
            lastError = nil
            return file
        } catch {
            handle(error)
            throw error
        }
    }

    // MARK: - Errors

    /// One place decides whether a failure kills the connection, so a revoked
    /// grant discovered mid-export immediately repaints the Settings card.
    private func handle(_ error: Error) {
        lastError = error.localizedDescription
        guard let driveError = error as? GoogleDriveError else { return }
        if driveError.invalidatesConnection {
            state = .needsReconnect(reason: driveError.localizedDescription)
        }
    }
}
