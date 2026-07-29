// CosmoOS/Settings/GoogleDriveConnectionCard.swift
// The Google Drive connection, in the Connections tab's card grammar.
//
// Unlike every other card in this tab, there is no key to paste here in the
// steady state — the user presses Connect, signs in to Google, and comes back.
// The one-time setup state exists only because an OAuth client must be
// registered somewhere, and a client ID is public config, not a credential.
// Once `GoogleDriveConfiguration.bundledClientID` is filled in, that state
// never appears again on any Mac running the build.
// July 2026

import SwiftUI
import AppKit

struct GoogleDriveConnectionCard: View {
    private let connection = GoogleDriveConnection.shared

    @State private var clientIDInput = ""
    @State private var showSetupSteps = false
    @State private var folders: [DriveFile] = []
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            headerRow
            stateContent
            if let error = connection.lastError {
                errorRow(error)
            }
        }
        .padding(DS.space16)
        .background(cardBackground)
        .task {
            await connection.refreshState()
            if connection.state.isConnected { await loadFolders() }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: DS.space16) {
            driveIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("Google Drive")
                    .font(DS.title3)
                    .foregroundStyle(connection.state.isConnected ? DS.text : DS.textSecondary)
                Text(subtitle)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            headerTrailing
        }
    }

    private var driveIcon: some View {
        Image(systemName: "externaldrive.badge.icloud")
            .font(DS.title2)
            .foregroundStyle(connection.state.isConnected ? DS.entityContent : DS.entityContent.opacity(0.5))
            .frame(width: 36, height: 36)
            .background(DS.entityContent.opacity(connection.state.isConnected ? 0.15 : 0.08))
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .accessibilityLabel("Google Drive")
    }

    private var subtitle: String {
        switch connection.state {
        case .needsSetup: return "Send finished content straight to Drive"
        case .disconnected: return "Send finished content straight to Drive"
        case .connecting: return "Waiting for Google…"
        case .connected(let email, let displayName):
            if let displayName, !displayName.isEmpty { return "\(displayName) · \(email)" }
            return email
        case .needsReconnect: return "Sign-in expired"
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        switch connection.state {
        case .connecting:
            ProgressView().controlSize(.small)
        case .connected:
            HStack(spacing: DS.space8) {
                statusPill(text: "Connected", color: DS.green)
                disconnectButton
            }
        case .needsReconnect:
            statusPill(text: "Reconnect", color: DS.orange)
        case .disconnected:
            connectButton(title: "Connect")
        case .needsSetup:
            statusPill(text: "Setup", color: DS.textMuted)
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch connection.state {
        case .needsSetup:
            setupSection
        case .needsReconnect(let reason):
            reconnectSection(reason: reason)
        case .connected:
            connectedSection
        case .disconnected, .connecting:
            EmptyView()
        }
    }

    // MARK: - Connected

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Text("Folder")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 52, alignment: .leading)
                folderMenu
                newFolderButton
                Spacer()
                openInDriveButton
            }
            if isCreatingFolder { newFolderField }
            Text("Cosmo can only see folders it created — move this one anywhere in Drive and the link still works.")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var folderMenu: some View {
        Menu {
            ForEach(folders) { folder in
                Button(folder.name) { connection.selectFolder(folder) }
            }
            if folders.isEmpty {
                Text("No folders yet").font(DS.caption2)
            }
            Divider()
            Button("Refresh") { Task { await loadFolders() } }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "folder")
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(connection.folderName).font(DS.footnote).lineLimit(1)
            }
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .frame(minHeight: 24)
            .background(fieldBackground)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var newFolderButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isCreatingFolder.toggle() }
        } label: {
            Text(isCreatingFolder ? "Cancel" : "New…")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .frame(minHeight: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var newFolderField: some View {
        HStack(spacing: DS.space8) {
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(DS.footnote)
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(fieldBackground)
                .onSubmit { createFolder() }
            Button("Create") { createFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var openInDriveButton: some View {
        if let folderID = connection.folderID,
           let url = URL(string: "https://drive.google.com/drive/folders/\(folderID)") {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open in Drive", systemImage: "arrow.up.forward.square")
                    .font(DS.footnote)
                    .foregroundStyle(DS.entityContent)
                    .frame(minHeight: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Reconnect

    private func reconnectSection(reason: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(reason)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            connectButton(title: "Reconnect Google Drive")
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Cosmo needs its own Google OAuth client before it can sign you in. This is a one-time setup, and the client ID isn't a secret.")
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.space8) {
                TextField("123456789-abc.apps.googleusercontent.com", text: $clientIDInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DS.text)
                    .padding(DS.space8)
                    .background(fieldBackground)
                    .onSubmit { saveClientID() }
                Button("Save") { saveClientID() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            setupStepsToggle
            if showSetupSteps { setupSteps }
        }
    }

    private var setupStepsToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showSetupSteps.toggle() }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: showSetupSteps ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text("How to get a client ID").font(DS.caption2)
            }
            .foregroundStyle(DS.textMuted)
            .frame(minHeight: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: DS.space6) {
                    Text("\(index + 1).")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                    Text(step)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                NSWorkspace.shared.open(GoogleDriveConfiguration.credentialsConsoleURL)
            } label: {
                Label("Open Google Cloud Console", systemImage: "arrow.up.forward.square")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entityContent)
                    .frame(minHeight: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space10)
        .background(fieldBackground)
    }

    /// Step 5 is the one people skip and then wonder why they're signing in
    /// again every week: a consent screen left in Testing expires refresh
    /// tokens after seven days.
    private static let steps = [
        "In Google Cloud Console, create a project (or pick an existing one).",
        "APIs & Services → Library → enable the Google Drive API.",
        "APIs & Services → Credentials → Create credentials → OAuth client ID → application type iOS, bundle ID com.cosmo.CosmoOS.",
        "Copy the client ID it gives you and paste it above.",
        "On the OAuth consent screen, add the .../auth/drive.file scope, add yourself as a test user, then publish the app to Production — a consent screen left in Testing expires the sign-in every 7 days."
    ]

    // MARK: - Shared pieces

    private func connectButton(title: String) -> some View {
        Button {
            Task { await connection.connect(); await loadFolders() }
        } label: {
            Text(title)
                .font(DS.buttonText)
                .foregroundStyle(DS.entityContent)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space6)
                .frame(minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.entityContent.opacity(0.12))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var disconnectButton: some View {
        Button {
            Task { await connection.disconnect() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.textMuted)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Disconnect Google Drive")
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: DS.space4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(DS.footnote).foregroundStyle(color)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(DS.caption2)
            .foregroundStyle(DS.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .fill(DS.glassInputFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.glassBorder, lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.glassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(
                        connection.state.isConnected ? DS.entityContent.opacity(0.2) : DS.glassBorder,
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Actions

    private func saveClientID() {
        guard connection.saveClientID(clientIDInput) else { return }
        clientIDInput = ""
    }

    private func createFolder() {
        let name = newFolderName
        Task {
            _ = try? await connection.createFolder(named: name)
            newFolderName = ""
            isCreatingFolder = false
            await loadFolders()
        }
    }

    private func loadFolders() async {
        guard connection.state.isConnected else { return }
        folders = (try? await connection.availableFolders()) ?? []
    }
}
