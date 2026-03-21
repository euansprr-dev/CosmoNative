// CosmoOS/Settings/ProfileManagementTab.swift
// Profile management tab for Settings — browse, create, edit, and delete client profiles
// February 2026

import SwiftUI

/// Wrapper to force SwiftUI to recreate the sheet on each presentation
private struct ProfileSheetItem: Identifiable {
    let id = UUID()
    let atom: Atom?
}

struct ProfileManagementTab: View {
    @State private var profiles: [Atom] = []
    @State private var profileSheetItem: ProfileSheetItem?
    @State private var deleteConfirmProfile: Atom?
    @State private var showDetail = false
    @State private var detailProfile: Atom?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text("Content Profiles")
                        .font(DS.title2)
                        .foregroundStyle(DS.text)

                    Text("Brand voice profiles for AI-powered content drafting")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()

                Button(action: {
                    profileSheetItem = ProfileSheetItem(atom: nil)
                }) {
                    HStack(spacing: DS.space4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Profile")
                            .font(DS.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(CosmoColors.lavender)
                    )
                }
                .buttonStyle(.plain)
            }

            // Profile list or empty state
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if profiles.isEmpty {
                emptyState
            } else {
                profileList
            }

            Spacer(minLength: DS.space24)
        }
        .onAppear { loadProfiles() }
        .sheet(item: $profileSheetItem) { item in
            NewProfileFlowView(existingAtom: item.atom) { _ in
                loadProfiles()
            }
        }
        .sheet(isPresented: $showDetail) {
            if let profile = detailProfile {
                ProfileDetailView(atom: profile)
            }
        }
        .alert("Delete Profile", isPresented: Binding(
            get: { deleteConfirmProfile != nil },
            set: { if !$0 { deleteConfirmProfile = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteConfirmProfile = nil }
            Button("Delete", role: .destructive) {
                if let profile = deleteConfirmProfile {
                    deleteProfile(profile)
                }
            }
        } message: {
            if let profile = deleteConfirmProfile {
                Text("Are you sure you want to delete \"\(profile.title ?? "this profile")\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(DS.textMuted)

            Text("No profiles yet")
                .font(DS.title3)
                .foregroundStyle(DS.textSecondary)

            Text("Create one to enable brand-aware AI drafting.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
        )
    }

    // MARK: - Profile List

    private var profileList: some View {
        VStack(spacing: DS.space8) {
            ForEach(profiles, id: \.uuid) { profile in
                profileCard(profile)
            }
        }
    }

    @ViewBuilder
    private func profileCard(_ profile: Atom) -> some View {
        let meta = profile.metadataValue(as: ClientProfileMetadata.self)

        HStack(spacing: DS.space12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(CosmoColors.lavender.opacity(0.15))
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(CosmoColors.lavender)
            }
            .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.space8) {
                    Text(profile.title ?? "Untitled")
                        .font(DS.title3)
                        .foregroundStyle(DS.text)

                    if meta?.activeStatus == true {
                        Text("Active")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DS.green.opacity(0.12))
                            )
                    }
                }

                HStack(spacing: DS.space8) {
                    if let handle = meta?.handle, !handle.isEmpty {
                        Text(handle)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                    if let niche = meta?.niche, !niche.isEmpty {
                        Text(niche)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                }

                // Platform chips
                if let platforms = meta?.platforms, !platforms.isEmpty {
                    platformChipsRow(platforms)
                }
            }

            Spacer()

            // Edit button
            Button(action: {
                profileSheetItem = ProfileSheetItem(atom: profile)
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.surfaceHover)
                    )
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: {
                deleteConfirmProfile = profile
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.red.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.red.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            detailProfile = profile
            showDetail = true
        }
    }

    @ViewBuilder
    private func platformChipsRow(_ platforms: [SocialPlatform]) -> some View {
        HStack(spacing: 4) {
            ForEach(platforms.prefix(4), id: \.self) { platform in
                Text(platform.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.surfaceHover)
                    )
            }
            if platforms.count > 4 {
                Text("+\(platforms.count - 4)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    // MARK: - Actions

    private func loadProfiles() {
        Task {
            isLoading = true
            do {
                profiles = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            } catch {
                profiles = []
            }
            isLoading = false
        }
    }

    private func deleteProfile(_ profile: Atom) {
        Task {
            do {
                try await AtomRepository.shared.delete(uuid: profile.uuid)
                loadProfiles()
            } catch {
                print("ProfileManagementTab: Failed to delete profile: \(error.localizedDescription)")
            }
        }
        deleteConfirmProfile = nil
    }
}

// MARK: - Preview

#Preview("Profile Management") {
    ProfileManagementTab()
        .frame(width: 600, height: 500)
        .padding()
}
