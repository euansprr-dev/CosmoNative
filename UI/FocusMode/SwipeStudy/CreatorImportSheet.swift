// CosmoOS/UI/FocusMode/SwipeStudy/CreatorImportSheet.swift
// Import an Instagram creator's full catalog with engagement data
// Sort by performance, selectively save as swipes

import SwiftUI

struct CreatorImportSheet: View {
    var onClose: (() -> Void)? = nil
    /// Pass a creator UUID to load a previously cached catalog instead of fresh import
    var creatorUUID: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var engine = CreatorImportEngine()
    @State private var handleInput = ""
    @State private var maxPostsSlider: Double = 100
    @State private var showingAlert = false
    @State private var isInputFocused = false
    @State private var completionAppeared = false
    @State private var didLoadCatalog = false

    var body: some View {
        VStack(spacing: 0) {
            premiumHeaderBar
            DS.borderSubtle.frame(height: 1)
            scrollContent
        }
        .contentShape(Rectangle())
        .background(DS.surfaceElevated)
        .task {
            if let creatorUUID, !didLoadCatalog {
                didLoadCatalog = true
                await engine.loadCachedCatalog(creatorUUID: creatorUUID)
            }
        }
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                handleInputSection
                profileSection
                costSection
                progressSection
                postGridSection
                completionSection
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            selectionToolbar
        }
    }

    // MARK: - Computed Phase Index

    private var currentPhaseIndex: Int {
        switch engine.importState {
        case .idle: return 0
        case .fetchingProfile: return 0
        case .awaitingConfirmation: return 1
        case .fetchingPosts: return 2
        case .saving: return 3
        case .complete: return 3
        case .error: return currentPhaseForError
        }
    }

    private var currentPhaseForError: Int {
        if engine.creatorProfile != nil {
            return engine.importedPosts.isEmpty ? 1 : 2
        }
        return 0
    }

    // MARK: - Premium Header

    @ViewBuilder
    private var premiumHeaderBar: some View {
        HStack(spacing: 12) {
            headerLeading
            Spacer()
            FloatingOverlayPhaseIndicator(
                phases: ["Lookup", "Preview", "Select", "Save"],
                currentPhase: currentPhaseIndex
            )
            Spacer()
            headerTrailing
        }
        .frame(height: 56)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var headerLeading: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.isCachedCatalog ? "tray.full.fill" : "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.entitySwipe)
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.isCachedCatalog ? "Browse Catalog" : "Import Creator")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)
                if let age = engine.catalogAge {
                    Text(age)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        HStack(spacing: 10) {
            if engine.isCachedCatalog {
                refreshCatalogButton
            }
            if !engine.importedPosts.isEmpty {
                postCountChip
            }
            FloatingOverlayCloseButton { performClose() }
        }
    }

    @ViewBuilder
    private var refreshCatalogButton: some View {
        Button {
            guard let profile = engine.creatorProfile else { return }
            Task {
                engine.isCachedCatalog = false
                engine.catalogAge = nil
                await engine.fetchPosts(maxPosts: engine.importedPosts.count)
                engine.isCachedCatalog = true
                engine.catalogAge = "Fetched just now"
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                Text("Refresh")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.entitySwipe)
            .commandKToolbarChip(
                isActive: false,
                activeFill: DS.entitySwipe.opacity(0.1),
                activeBorder: DS.entitySwipe.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var postCountChip: some View {
        Text("\(engine.importedPosts.count) posts")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.entitySwipe)
            .commandKToolbarChip(
                isActive: true,
                activeFill: DS.entitySwipe.opacity(0.1),
                activeBorder: DS.entitySwipe.opacity(0.2)
            )
    }

    // MARK: - Handle Input

    @ViewBuilder
    private var handleInputSection: some View {
        if engine.creatorProfile == nil && engine.importedPosts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                inputField
                if !ApifyInstagramProvider.shared.isConfigured {
                    apiKeyWarning
                }
            }
            .commandKSectionChrome()
        }
    }

    @ViewBuilder
    private var inputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instagram Handle or URL")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            HStack(spacing: 10) {
                inputFieldContent
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(DS.surface, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isInputFocused ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var inputFieldContent: some View {
        Image(systemName: "at")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(DS.textMuted)

        TextField("username or instagram.com/username", text: $handleInput, onEditingChanged: { focused in
            isInputFocused = focused
        })
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .onSubmit { startImport() }

        pasteButton
        lookupButton
    }

    @ViewBuilder
    private var pasteButton: some View {
        Button {
            if let clipboard = NSPasteboard.general.string(forType: .string) {
                handleInput = clipboard
            }
        } label: {
            Text("Paste")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.surfaceElevated, in: Capsule())
                .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var lookupButton: some View {
        Button(action: startImport) {
            HStack(spacing: 4) {
                Text("Lookup")
                Image(systemName: "magnifyingglass")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DS.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(handleInput.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private var apiKeyWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Apify API key not configured. Add it in Settings \u{2192} API Keys.")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
        VStack(spacing: 0) {
            profileGradientBar
            profileCardContent(profile)
        }
        .clipShape(.rect(cornerRadius: CommandKMetrics.sectionCornerRadius, style: .continuous))
        .commandKSectionChrome()
    }

    @ViewBuilder
    private var profileGradientBar: some View {
        LinearGradient(
            colors: [DS.entitySwipe.opacity(0.25), DS.entitySwipe.opacity(0.05)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 3)
    }

    @ViewBuilder
    private func profileCardContent(_ profile: ImportedCreatorProfile) -> some View {
        HStack(spacing: 16) {
            profileAvatar(profile)
            profileInfo(profile)
            Spacer()
        }
        .padding(16)

        DS.borderSubtle.frame(height: 1)
            .padding(.horizontal, 16)

        profileStatsRow(profile)
            .padding(16)
    }

    @ViewBuilder
    private func profileAvatar(_ profile: ImportedCreatorProfile) -> some View {
        if let urlStr = profile.profilePicUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.entitySwipe, lineWidth: 2))
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
            .fill(DS.entitySwipe.opacity(0.12))
            .frame(width: 64, height: 64)
            .overlay(Circle().stroke(DS.entitySwipe.opacity(0.3), lineWidth: 2))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.entitySwipe)
            }
    }

    @ViewBuilder
    private func profileInfo(_ profile: ImportedCreatorProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(profile.fullName ?? profile.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                }
            }
            Text("@\(profile.username)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
            if let bio = profile.biography, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func profileStatsRow(_ profile: ImportedCreatorProfile) -> some View {
        HStack(spacing: 0) {
            statColumn(value: formatLargeCount(profile.followerCount), label: "Followers")
            Spacer()
            DS.borderSubtle.frame(width: 1, height: 32)
            Spacer()
            statColumn(value: formatLargeCount(profile.followingCount), label: "Following")
            Spacer()
            DS.borderSubtle.frame(width: 1, height: 32)
            Spacer()
            statColumn(value: formatLargeCount(profile.postsCount), label: "Posts")
        }
    }

    @ViewBuilder
    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.text)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 16) {
            costSliderSection
            costInfoRow
            importPostsCTA
            costWarning(estimate)
        }
        .padding(16)
        .commandKSectionChrome()
    }

    @ViewBuilder
    private var costSliderSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Posts to import")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text("\(Int(maxPostsSlider))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.entitySwipe)
            }
            Slider(value: $maxPostsSlider, in: 25...min(1000, Double(engine.creatorProfile?.postsCount ?? 100)), step: 25)
                .tint(DS.entitySwipe)
        }
    }

    @ViewBuilder
    private var costInfoRow: some View {
        HStack(spacing: 10) {
            costChip(
                icon: "dollarsign.circle",
                value: String(format: "$%.2f", provider.estimateCost(postCount: Int(maxPostsSlider)).estimatedCostUSD)
            )
            costChip(
                icon: "clock",
                value: "\(provider.estimateCost(postCount: Int(maxPostsSlider)).estimatedDurationSeconds)s"
            )
            Spacer()
        }
    }

    @ViewBuilder
    private func costChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(DS.text)
        .commandKToolbarChip()
    }

    @ViewBuilder
    private var importPostsCTA: some View {
        Button {
            Task { await engine.fetchPosts(maxPosts: Int(maxPostsSlider)) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Import Posts")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(DS.entitySwipe, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func costWarning(_ estimate: ImportCostEstimate) -> some View {
        if let warning = estimate.warning {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text(warning)
            }
            .font(.system(size: 11))
            .foregroundStyle(.orange)
        }
    }

    private var provider: InstagramDataProvider { ApifyInstagramProvider.shared }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        switch engine.importState {
        case .fetchingProfile:
            progressRow(label: "Fetching profile...", progress: nil, fraction: nil)
        case .fetchingPosts(let fetched, let total):
            if fetched > 0 {
                progressRow(label: "Fetching posts...", progress: Double(fetched) / max(Double(total), 1), fraction: "\(fetched) / \(total) posts")
            } else {
                progressRow(label: "Scraping posts — this may take a few minutes for large accounts...", progress: nil, fraction: nil)
            }
        case .saving(let saved, let total):
            progressRow(label: "Saving...", progress: Double(saved) / max(Double(total), 1), fraction: "\(saved) / \(total) posts")
        case .error(let message):
            errorRow(message)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func progressRow(label: String, progress: Double?, fraction: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                if let fraction {
                    Text(fraction)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textMuted)
                }
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(DS.entitySwipe)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(16)
        .commandKSectionChrome()
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
        .padding(14)
        .background(Color.red.opacity(0.04), in: .rect(cornerRadius: CommandKMetrics.sectionCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CommandKMetrics.sectionCornerRadius, style: .continuous)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Sort & Filter

    @ViewBuilder
    private var postGridSection: some View {
        if !engine.importedPosts.isEmpty {
            sortAndFilterBar
            postGrid
        }
    }

    @ViewBuilder
    private var sortAndFilterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                sortChips
                Spacer()
                autoTranscribeChip
            }

            HStack(spacing: 8) {
                typeFilterChips
                Divider().frame(height: 16)
                savedFilterChips
                Spacer()
                if engine.typeFilter != nil || engine.savedFilter != .all {
                    filteredCountLabel
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .commandKToolbarGroup()
    }

    @ViewBuilder
    private var typeFilterChips: some View {
        typeFilterChip(nil, label: "All")
        typeFilterChip(.reel, label: "Reels")
        typeFilterChip(.carousel, label: "Carousels")
        typeFilterChip(.image, label: "Images")
    }

    @ViewBuilder
    private func typeFilterChip(_ type: InstagramContentType?, label: String) -> some View {
        let isActive = engine.typeFilter == type
        Button {
            withAnimation(ProMotionSprings.snappy) {
                engine.typeFilter = type
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: DS.accent,
                    activeBorder: DS.accent
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var savedFilterChips: some View {
        ForEach(SavedFilter.allCases, id: \.self) { filter in
            savedFilterChip(filter)
        }
    }

    @ViewBuilder
    private func savedFilterChip(_ filter: SavedFilter) -> some View {
        let isActive = engine.savedFilter == filter
        Button {
            withAnimation(ProMotionSprings.snappy) {
                engine.savedFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.textOnAccent : DS.textSecondary)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: DS.accent,
                    activeBorder: DS.accent
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var filteredCountLabel: some View {
        Text("\(engine.sortedPosts.count) shown")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(DS.textMuted)
    }

    @ViewBuilder
    private var sortChips: some View {
        ForEach(ImportSortOption.allCases, id: \.self) { option in
            sortChip(option)
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
                .foregroundStyle(isActive ? DS.textOnAccent : DS.text)
                .commandKToolbarChip(
                    isActive: isActive,
                    activeFill: DS.entitySwipe,
                    activeBorder: DS.entitySwipe
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var autoTranscribeChip: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                engine.autoTranscribe.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: engine.autoTranscribe ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 11))
                Text("Auto-transcribe")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(engine.autoTranscribe ? DS.entitySwipe : DS.textMuted)
            .commandKToolbarChip(
                isActive: engine.autoTranscribe,
                activeFill: DS.entitySwipe.opacity(0.1),
                activeBorder: DS.entitySwipe.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post Grid

    @ViewBuilder
    private var postGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 12)],
            spacing: 12
        ) {
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

    // MARK: - Selection Toolbar (Sticky Bottom)

    @ViewBuilder
    private var selectionToolbar: some View {
        if !engine.importedPosts.isEmpty {
            VStack(spacing: 0) {
                DS.borderSubtle.frame(height: 1)
                selectionToolbarContent
            }
            .background(DS.surfaceElevated)
        }
    }

    @ViewBuilder
    private var selectionToolbarContent: some View {
        HStack(spacing: 8) {
            selectionQuickActions
            Spacer()
            selectionCTA
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var selectionQuickActions: some View {
        Group {
            quickSelectChip("Select All", action: { engine.selectAll() })
            quickSelectChip("Top 10", action: { engine.selectTopN(10) })
            quickSelectChip("Top 25", action: { engine.selectTopN(25) })
            quickSelectChip("All Reels", action: { engine.selectAllReels() })

            if !engine.selectedPostIds.isEmpty {
                quickSelectChip("Clear", action: { engine.deselectAll() })
            }
        }
    }

    @ViewBuilder
    private func quickSelectChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.text)
                .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionCTA: some View {
        if !engine.selectedPostIds.isEmpty {
            Button {
                Task { await engine.saveSelectedPosts() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save \(engine.selectedPostIds.count) Selected")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Completion

    @ViewBuilder
    private var completionSection: some View {
        if case .complete(let saved, let enriched) = engine.importState {
            completionCard(saved: saved, enriched: enriched)
                .onAppear { triggerCompletionAnimation() }
        }
    }

    @ViewBuilder
    private func completionCard(saved: Int, enriched: Int) -> some View {
        VStack(spacing: 12) {
            completionCheckmark
            completionInfo(saved: saved, enriched: enriched)
            completionActions
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(DS.accent.opacity(0.08), in: .rect(cornerRadius: CommandKMetrics.sectionCornerRadius))
        .commandKSectionChrome()
    }

    @ViewBuilder
    private var completionCheckmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 36))
            .foregroundStyle(DS.accent)
            .scaleEffect(completionAppeared ? 1.0 : 0.5)
            .opacity(completionAppeared ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: completionAppeared)
    }

    @ViewBuilder
    private func completionInfo(saved: Int, enriched: Int) -> some View {
        VStack(spacing: 6) {
            Text("Import Complete")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)

            HStack(spacing: 8) {
                completionStatPill(value: "\(saved)", label: "saved")
                if enriched > 0 {
                    completionStatPill(value: "\(enriched)", label: "enriched")
                }
            }
        }
    }

    @ViewBuilder
    private func completionStatPill(value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
        }
        .commandKToolbarChip()
    }

    @ViewBuilder
    private var completionActions: some View {
        VStack(spacing: 8) {
            Button { performClose() } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(DS.accent, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button { performClose() } label: {
                Text("View in Swipe Gallery")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func triggerCompletionAnimation() {
        withAnimation {
            completionAppeared = true
        }
    }

    // MARK: - Actions

    private func performClose() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

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
