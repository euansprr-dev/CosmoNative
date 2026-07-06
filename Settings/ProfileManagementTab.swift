// CosmoOS/Settings/ProfileManagementTab.swift
// Profiles tab in Settings — the voices Cosmo drafts in. Rows follow the
// SettingsSurfaceKit grammar; tapping one morphs the settings shell into
// the Profile Studio (no stacked sheets).

import SwiftUI

struct ProfileManagementTab: View {
    @State private var profiles: [Atom] = []
    @State private var deleteConfirmProfile: Atom?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(
                label: "PROFILES",
                detail: isLoading ? nil : "\(profiles.count)"
            )

            if isLoading {
                loadingBox
            } else if profiles.isEmpty {
                emptyTeachingBox
            } else {
                profilesBox
            }

            newProfileButton
        }
        .task { await loadProfiles() }
        .onReceive(NotificationCenter.default.publisher(for: .clientProfilesChanged)) { _ in
            Task { await loadProfiles() }
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
                Text("Delete \"\(profile.title ?? "this profile")\"? Its documents and voice model go with it. This cannot be undone.")
            }
        }
    }

    // MARK: - Boxes

    private var loadingBox: some View {
        SettingsGroupedBox {
            ForEach(0..<2, id: \.self) { index in
                skeletonRow
                if index == 0 { SettingsRowDivider() }
            }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: DS.space12) {
            Circle()
                .fill(DS.glassSectionFill)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: DS.space4) {
                Capsule().fill(DS.glassSectionFill).frame(width: 140, height: 10)
                Capsule().fill(DS.glassSectionFill).frame(width: 90, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .frame(minHeight: 44)
        .accessibilityHidden(true)
    }

    private var emptyTeachingBox: some View {
        SettingsGroupedBox {
            VStack(spacing: DS.space6) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 20))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text("Give Cosmo a voice to write in")
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                Text("Create a profile with your brand story and 3 posts you're proud of — every draft starts sounding like you.")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space24)
            .padding(.horizontal, DS.space16)
        }
    }

    private var profilesBox: some View {
        SettingsGroupedBox {
            ForEach(profiles, id: \.uuid) { profile in
                ProfileListRow(
                    profile: profile,
                    onOpen: { openStudio(profile) },
                    onDelete: { deleteConfirmProfile = profile }
                )
                if profile.uuid != profiles.last?.uuid {
                    SettingsRowDivider(inset: 64)
                }
            }
        }
    }

    private var newProfileButton: some View {
        Button {
            NotificationCenter.default.post(name: .openProfileStudio, object: nil)
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("New Profile")
                    .font(DS.caption.weight(.semibold))
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(DS.accent, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .help("Create a profile (⇧⌘N)")
    }

    // MARK: - Actions

    private func openStudio(_ profile: Atom) {
        NotificationCenter.default.post(
            name: .openProfileStudio,
            object: nil,
            userInfo: ["atomUUID": profile.uuid]
        )
    }

    private func loadProfiles() async {
        do {
            profiles = try await AtomRepository.shared.fetchAll(type: .clientProfile)
        } catch {
            profiles = []
        }
        isLoading = false
    }

    private func deleteProfile(_ profile: Atom) {
        Task {
            do {
                try await AtomRepository.shared.delete(uuid: profile.uuid)
                await loadProfiles()
            } catch {
                print("ProfileManagementTab: Failed to delete profile: \(error.localizedDescription)")
            }
        }
        deleteConfirmProfile = nil
    }
}

// MARK: - Row

private struct ProfileListRow: View {
    let profile: Atom
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var meta: ClientProfileMetadata? {
        profile.metadataValue(as: ClientProfileMetadata.self)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.space12) {
                ProfileAvatarMark(name: profile.title ?? "", size: 36)
                rowText
                Spacer(minLength: DS.space8)
                trailing
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? DS.surfaceHover : Color.clear)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Delete…", role: .destructive) { onDelete() }
        }
        .help("Open in Profile Studio")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.title ?? "Untitled")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
            HStack(spacing: DS.space6) {
                if let handle = meta?.handle, !handle.isEmpty {
                    Text(handle)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
                if let niche = meta?.niche, !niche.isEmpty {
                    Text(niche)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
                if let count = meta?.documents?.count, count > 0 {
                    Text("\(count) documents")
                        .font(DS.footnote.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if meta?.intelligenceModel != nil {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .help("Voice model generated")
                .accessibilityHidden(true)
        }
        if let platform = meta?.primaryPlatform ?? meta?.platforms.first {
            Text(platform.displayName)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space6)
                .padding(.vertical, 2)
                .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        }
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DS.textMuted)
            .opacity(isHovered ? 1 : 0.5)
            .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts = [profile.title ?? "Untitled"]
        if let handle = meta?.handle, !handle.isEmpty { parts.append(handle) }
        if let count = meta?.documents?.count { parts.append("\(count) documents") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Profile Management") {
    ProfileManagementTab()
        .frame(width: 600, height: 500)
        .padding()
}
