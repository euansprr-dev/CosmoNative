// CosmoOS/UI/FocusMode/SwipeStudy/CreatorImportSheet.swift
// Import an Instagram creator's full catalog with engagement data
// Sort by performance, selectively save as swipes

import SwiftUI

struct CreatorImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engine = CreatorImportEngine()
    @State private var handleInput = ""
    @State private var maxPostsSlider: Double = 100
    @State private var showingAlert = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    handleInputSection
                    profileSection
                    costSection
                    progressSection
                    if !engine.importedPosts.isEmpty {
                        sortAndFilterBar
                        postGrid
                        selectionToolbar
                    }
                    completionSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 680, idealWidth: 800, maxWidth: 1000)
        .frame(minHeight: 500, idealHeight: 700, maxHeight: 900)
        .background(DS.bg)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.entitySwipe)
            Text("Import Creator")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)
            Spacer()
            if !engine.importedPosts.isEmpty {
                Text("\(engine.importedPosts.count) posts loaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DS.bg, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Handle Input

    @ViewBuilder
    private var handleInputSection: some View {
        if engine.creatorProfile == nil && !engine.importedPosts.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("Instagram Handle or URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)

                HStack(spacing: 8) {
                    Image(systemName: "at")
                        .foregroundStyle(DS.textSecondary)
                    TextField("username or instagram.com/username", text: $handleInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit { startImport() }

                    Button("Paste") {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            handleInput = clipboard
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.accent)

                    Button(action: startImport) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("Lookup")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(handleInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DS.border, lineWidth: 1)
                )

                if !ApifyInstagramProvider.shared.isConfigured {
                    apiKeyWarning
                }
            }
        }
    }

    @ViewBuilder
    private var apiKeyWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Apify API key not configured. Add it in Settings → API Keys.")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Profile Preview

    @ViewBuilder
    private var profileSection: some View {
        if let profile = engine.creatorProfile {
            profileCard(profile)
        }
    }

    @ViewBuilder
    private func profileCard(_ profile: ImportedCreatorProfile) -> some View {
        HStack(spacing: 16) {
            profileAvatar(profile)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.fullName ?? profile.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.text)
                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                }
                Text("@\(profile.username)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                if let bio = profile.biography, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            profileStats(profile)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func profileAvatar(_ profile: ImportedCreatorProfile) -> some View {
        if let urlStr = profile.profilePicUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    @ViewBuilder
    private var avatarPlaceholder: some View {
        Circle()
            .fill(DS.entitySwipe.opacity(0.15))
            .frame(width: 52, height: 52)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(DS.entitySwipe)
            }
    }

    @ViewBuilder
    private func profileStats(_ profile: ImportedCreatorProfile) -> some View {
        HStack(spacing: 16) {
            statColumn(value: formatLargeCount(profile.followerCount), label: "Followers")
            statColumn(value: formatLargeCount(profile.followingCount), label: "Following")
            statColumn(value: formatLargeCount(profile.postsCount), label: "Posts")
        }
    }

    @ViewBuilder
    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.text)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Cost Estimate

    @ViewBuilder
    private var costSection: some View {
        if case .awaitingConfirmation(let estimate) = engine.importState {
            costConfirmation(estimate)
        }
    }

    @ViewBuilder
    private func costConfirmation(_ estimate: ImportCostEstimate) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Posts to import")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text("\(Int(maxPostsSlider))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.entitySwipe)
            }
            Slider(value: $maxPostsSlider, in: 25...min(1000, Double(engine.creatorProfile?.postsCount ?? 100)), step: 25)
                .tint(DS.entitySwipe)

            HStack(spacing: 16) {
                costPill(icon: "dollarsign.circle", value: String(format: "$%.2f", provider.estimateCost(postCount: Int(maxPostsSlider)).estimatedCostUSD), label: "Est. cost")
                costPill(icon: "clock", value: "\(provider.estimateCost(postCount: Int(maxPostsSlider)).estimatedDurationSeconds)s", label: "Duration")
                Spacer()
                Button(action: { Task { await engine.fetchPosts(maxPosts: Int(maxPostsSlider)) } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Import Posts")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.entitySwipe, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let warning = estimate.warning {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(warning)
                }
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func costPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(DS.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var provider: InstagramDataProvider { ApifyInstagramProvider.shared }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        switch engine.importState {
        case .fetchingProfile:
            progressRow(label: "Fetching profile...", progress: nil)
        case .fetchingPosts(let fetched, let total):
            progressRow(label: "Fetching posts... \(fetched)/\(total)", progress: Double(fetched) / max(Double(total), 1))
        case .saving(let saved, let total):
            progressRow(label: "Saving... \(saved)/\(total)", progress: Double(saved) / max(Double(total), 1))
        case .error(let message):
            errorRow(message)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func progressRow(label: String, progress: Double?) -> some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(DS.entitySwipe)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DS.text)
            Spacer()
            Button("Try Again") {
                engine.reset()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.accent)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sort & Filter

    @ViewBuilder
    private var sortAndFilterBar: some View {
        HStack(spacing: 12) {
            ForEach(ImportSortOption.allCases, id: \.self) { option in
                sortChip(option)
            }
            Spacer()
            Toggle("Auto-transcribe videos", isOn: $engine.autoTranscribe)
                .toggleStyle(.switch)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .controlSize(.mini)
        }
    }

    @ViewBuilder
    private func sortChip(_ option: ImportSortOption) -> some View {
        let isActive = engine.sortOption == option
        Button {
            withAnimation(ProMotionSprings.snappy) {
                engine.sortOption = option
            }
        } label: {
            Text(option.rawValue)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isActive ? DS.entitySwipe : Color.white,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(isActive ? Color.clear : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post Grid

    @ViewBuilder
    private var postGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(engine.sortedPosts) { post in
                ImportedPostCard(
                    post: post,
                    isSelected: engine.selectedPostIds.contains(post.id),
                    isDuplicate: engine.existingShortcodes.contains(post.shortcode),
                    onToggle: { engine.toggleSelection(post.id) }
                )
            }
        }
    }

    // MARK: - Selection Toolbar

    @ViewBuilder
    private var selectionToolbar: some View {
        if !engine.importedPosts.isEmpty {
            HStack(spacing: 10) {
                quickSelectButton("Top 10", action: { engine.selectTopN(10) })
                quickSelectButton("Top 25", action: { engine.selectTopN(25) })
                quickSelectButton("All Reels", action: { engine.selectAllReels() })

                if !engine.selectedPostIds.isEmpty {
                    quickSelectButton("Clear", action: { engine.deselectAll() })
                }

                Spacer()

                if !engine.selectedPostIds.isEmpty {
                    saveButton
                }
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DS.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func quickSelectButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.bg, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var saveButton: some View {
        Button {
            Task { await engine.saveSelectedPosts() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down.fill")
                Text("Save \(engine.selectedPostIds.count) Selected")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DS.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Completion

    @ViewBuilder
    private var completionSection: some View {
        if case .complete(let saved, let enriched) = engine.importState {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(DS.accent)
                Text("Import Complete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text("\(saved) posts saved as swipes")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
                if enriched > 0 {
                    Text("\(enriched) existing swipes enriched with engagement data")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.entitySwipe)
                }
                Button("Done") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DS.accent.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func startImport() {
        guard let handle = engine.resolveHandle(from: handleInput) else { return }
        Task { await engine.fetchProfile(handle: handle) }
    }

    // MARK: - Helpers

    private func formatLargeCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
