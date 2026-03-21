// CosmoOS/Settings/CloudSyncSettingsTab.swift
// Cloud Sync settings — Supabase Auth, data migration, sync status

import SwiftUI

struct CloudSyncSettingsTab: View {
    private var authService = SupabaseAuthService.shared
    @ObservedObject private var syncEngine = SyncEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Cloud Sync")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("Sync your data across devices and enable the cloud Telegram agent")
                .font(DS.navTitle)
                .foregroundStyle(DS.textMuted)

            authSection
            syncStatusSection
            migrationSection
            cloudAgentSection

            Spacer()
        }
    }

    // MARK: - Auth Section

    @ViewBuilder
    private var authSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "ACCOUNT", icon: "person.crop.circle.fill", color: DS.accent)

            switch authService.authState {
            case .signedIn(let userId, let email):
                signedInCard(userId: userId, email: email)

            case .signingIn:
                signingInCard

            case .error(let message):
                errorCard(message: message)

            case .signedOut, .unknown:
                signedOutCard
            }
        }
    }

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 44, height: 44)
                    .background(DS.surface)
                    .clipShape(.rect(cornerRadius: DS.radiusSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Connected")
                        .font(DS.title3)
                        .foregroundStyle(DS.text)

                    Text("Sign in to sync your data to the cloud")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()
            }

            Button(action: {
                Task { await authService.signInWithApple() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .medium))
                    Text("Sign in with Apple")
                        .font(DS.buttonText)
                        .fontWeight(.medium)
                }
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.space12)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(Color.black)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private func signedInCard(userId: String, email: String?) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(DS.accent)
                .frame(width: 44, height: 44)
                .background(DS.accentSoft)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                if let email = email {
                    Text(email)
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                } else {
                    Text(String(userId.prefix(8)) + "...")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            connectedBadge

            Button(action: {
                Task { await authService.signOut() }
            }) {
                Text("Sign Out")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.red)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private var signingInCard: some View {
        HStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Signing in...")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                Text("Waiting for Apple authentication")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(DS.red)
                    .frame(width: 44, height: 44)
                    .background(DS.red.opacity(0.12))
                    .clipShape(.rect(cornerRadius: DS.radiusSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign In Failed")
                        .font(DS.title3)
                        .foregroundStyle(DS.text)

                    Text(message)
                        .font(DS.callout)
                        .foregroundStyle(DS.red)
                        .lineLimit(2)
                }

                Spacer()
            }

            Button(action: {
                Task { await authService.signInWithApple() }
            }) {
                Text("Try Again")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.space8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.accentSoft)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space16)
        .background(glassCard)
    }

    // MARK: - Sync Status Section

    @ViewBuilder
    private var syncStatusSection: some View {
        if authService.isSignedIn {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(title: "SYNC STATUS", icon: "arrow.triangle.2.circlepath", color: DS.accent)

                HStack(spacing: 16) {
                    syncStatusIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncStatusLabel)
                            .font(DS.title3)
                            .foregroundStyle(DS.text)

                        if let lastSync = syncEngine.lastSyncTime {
                            Text("Last sync: \(lastSync, style: .relative) ago")
                                .font(DS.callout)
                                .foregroundStyle(DS.textMuted)
                        }
                    }

                    Spacer()

                    if syncEngine.pendingChanges > 0 {
                        Text("\(syncEngine.pendingChanges) pending")
                            .font(DS.footnote)
                            .foregroundStyle(DS.orange)
                            .padding(.horizontal, DS.space8)
                            .padding(.vertical, DS.space4)
                            .background(
                                Capsule()
                                    .fill(DS.orange.opacity(0.12))
                            )
                    }

                    Button(action: {
                        Task { await syncEngine.forceSync() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(DS.callout)
                            .foregroundStyle(DS.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(syncEngine.syncState == .syncing)
                }
                .padding(DS.space16)
                .background(glassCard)
            }
        }
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncEngine.syncState {
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
        case .idle:
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.green)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DS.red)
        }
    }

    private var syncStatusLabel: String {
        switch syncEngine.syncState {
        case .syncing: return "Syncing..."
        case .idle: return "Up to date"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    // MARK: - Migration Section

    @ViewBuilder
    private var migrationSection: some View {
        if authService.isSignedIn {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(title: "DATA SYNC", icon: "square.and.arrow.up.fill", color: DS.accent)

                switch authService.migrationState {
                case .inProgress(let label, let current, let total):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)

                        if total > 0 {
                            ProgressView(value: Double(current), total: Double(total))
                                .tint(DS.accent)

                            Text("\(current) / \(total)")
                                .font(DS.footnote)
                                .foregroundStyle(DS.textMuted)
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(DS.space16)
                    .background(glassCard)

                case .failed(let error):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(DS.callout)
                                .foregroundStyle(DS.red)
                            Text("Sync failed: \(error)")
                                .font(DS.callout)
                                .foregroundStyle(DS.red)
                                .lineLimit(2)
                        }

                        reSyncButton
                    }
                    .padding(DS.space16)
                    .background(glassCard)

                case .notStarted where !DataMigrationService.shared.isMigrationComplete:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your local data hasn't been synced to the cloud yet.")
                            .font(DS.callout)
                            .foregroundStyle(DS.textSecondary)

                        Button(action: {
                            Task { await authService.triggerMigrationIfNeeded() }
                        }) {
                            Text("Start Migration")
                                .font(DS.buttonText)
                                .foregroundStyle(DS.textOnAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.space8)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                                        .fill(DS.accent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DS.space16)
                    .background(glassCard)

                default:
                    // Complete or notStarted+migrationComplete — show status + re-sync option
                    VStack(alignment: .leading, spacing: 8) {
                        migrationStatusRows
                        reSyncButton
                    }
                    .padding(DS.space16)
                    .background(glassCard)
                }
            }
        }
    }

    @ViewBuilder
    private var migrationStatusRows: some View {
        let progress = DataMigrationService.shared.migrationProgress

        HStack(spacing: 8) {
            migrationCheckmark(done: progress.atomsComplete)
            Text("Atoms")
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer()
            migrationCheckmark(done: progress.edgesComplete)
            Text("Graph")
                .font(DS.callout)
                .foregroundStyle(DS.text)
            Spacer()
            migrationCheckmark(done: progress.canvasComplete)
            Text("Canvas")
                .font(DS.callout)
                .foregroundStyle(DS.text)
        }
    }

    @ViewBuilder
    private func migrationCheckmark(done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(DS.callout)
            .foregroundStyle(done ? DS.green : DS.textMuted)
    }

    private var reSyncButton: some View {
        Button(action: {
            DataMigrationService.shared.resetMigration()
            Task { await authService.triggerMigrationIfNeeded() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(DS.callout)
                Text("Re-sync All Data")
                    .font(DS.buttonText)
            }
            .foregroundStyle(DS.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.accentSoft)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cloud Agent Section

    @ViewBuilder
    private var cloudAgentSection: some View {
        if authService.isSignedIn {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(title: "TELEGRAM AGENT", icon: "paperplane.fill", color: Color(red: 0.0, green: 0.54, blue: 0.85))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(DS.textMuted)
                            .frame(width: 36, height: 36)
                            .background(DS.surface)
                            .clipShape(.rect(cornerRadius: DS.radiusSmall))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cloud Agent")
                                .font(DS.title3)
                                .foregroundStyle(DS.text)

                            Text("Works when your Mac is closed")
                                .font(DS.callout)
                                .foregroundStyle(DS.textMuted)
                        }

                        Spacer()

                        Text("Coming Soon")
                            .font(DS.buttonText)
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, DS.space16)
                            .padding(.vertical, DS.space4)
                            .background(
                                RoundedRectangle(cornerRadius: DS.radiusSmall)
                                    .fill(DS.surface)
                            )
                    }

                    Text("Once cloud sync is active, the Telegram agent will work independently of your Mac. Deploy the cloud agent server to enable this.")
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                        .padding(.top, DS.space4)
                }
                .padding(DS.space16)
                .background(glassCard)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(DS.sectionLabel)
                .foregroundStyle(color)

            Text(title)
                .font(DS.sectionLabel)
                .foregroundStyle(DS.textMuted)
                .tracking(1.2)
        }
    }

    private var connectedBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DS.green)
                .frame(width: 6, height: 6)

            Text("Connected")
                .font(DS.footnote)
                .foregroundStyle(DS.green)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(
            Capsule()
                .fill(DS.green.opacity(0.1))
        )
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }
}
