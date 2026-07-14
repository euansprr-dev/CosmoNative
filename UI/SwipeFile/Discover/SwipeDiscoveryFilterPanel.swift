import SwiftUI

/// The Discover configuration of the one filter popover — the control the whole
/// redesign is modeled on. Sections unchanged: Platforms · Format · Followers ·
/// Min outlier · Posted · Reset.
struct SwipeDiscoveryFilterPanel: View {
    @Bindable var model: SwipeDiscoverModel
    var maxHeight: CGFloat = 580

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                platformsSection
                divider
                formatSection
                divider
                followersSection
                divider
                outlierSection
                divider
                postedSection
                if hasActiveFilters {
                    resetButton
                }
            }
            .padding(18)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: maxHeight)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.glassBorder)
            .frame(height: 0.5)
            .opacity(0.7)
    }

    // MARK: Platforms (empty set = all)

    private var resolvedPlatforms: Set<SocialPlatform> {
        model.query.platforms.isEmpty
            ? Set(SwipeDiscoveryFilterPresentation.primaryPlatforms)
            : model.query.platforms
    }

    private var platformsSection: some View {
        let platforms = SwipeDiscoveryFilterPresentation.primaryPlatforms
        let selectedCount = resolvedPlatforms.intersection(Set(platforms)).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SwipeFilterSectionHeader(title: "Platforms")
                Spacer()
                Button("Select all") { model.query.platforms = [] }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(selectedCount == platforms.count ? DS.textMuted : DS.accent)
                    .disabled(selectedCount == platforms.count)
            }
            Text("\(selectedCount) of \(platforms.count) selected")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .padding(.bottom, 2)
            ForEach(platforms, id: \.rawValue) { platform in
                SwipeFilterCheckRow(
                    title: SwipeDiscoveryFilterPresentation.platformLabel(platform),
                    platformKey: platform.rawValue,
                    iconTint: platform.swipeBrandColor,
                    isOn: resolvedPlatforms.contains(platform)
                ) {
                    togglePlatform(platform)
                }
            }
        }
    }

    private func togglePlatform(_ platform: SocialPlatform) {
        let all = Set(SwipeDiscoveryFilterPresentation.primaryPlatforms)
        var set = resolvedPlatforms
        if set.contains(platform) {
            set.remove(platform)
        } else {
            set.insert(platform)
        }
        withAnimation(ProMotionSprings.snappy) {
            model.query.platforms = (set.isEmpty || set == all) ? [] : set
        }
    }

    // MARK: Format lenses

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwipeFilterSectionHeader(title: "Format")
            formatRow(.youtube, selection: $model.query.youtubeFormat) { $0.label }
            formatRow(.substack, selection: $model.query.substackFormat) { $0.label }
            formatRow(.instagram, selection: $model.query.instagramFormat) { $0.label }
            Text("Format lenses apply only to their own platform's posts.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatRow<Filter: CaseIterable & Hashable>(
        _ platform: SocialPlatform,
        selection: Binding<Filter>,
        label: @escaping (Filter) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                SwipePlatformGlyph(source: platform.rawValue)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(platform.swipeBrandColor)
                Text(SwipeDiscoveryFilterPresentation.platformLabel(platform))
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            CosmoFlowLayout(spacing: 7) {
                ForEach(Array(Filter.allCases), id: \.self) { option in
                    SwipeFilterSegmentChip(label: label(option), isSelected: option == selection.wrappedValue) {
                        withAnimation(ProMotionSprings.snappy) { selection.wrappedValue = option }
                    }
                }
            }
        }
    }

    // MARK: Followers

    private var followersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwipeFilterSectionHeader(title: "Followers")
            CosmoFlowLayout(spacing: 7) {
                ForEach(SwipeDiscoveryFilterPresentation.followerPresets) { preset in
                    SwipeFilterSegmentChip(label: preset.label, isSelected: model.query.followerRange == preset.range) {
                        withAnimation(ProMotionSprings.snappy) { model.query.followerRange = preset.range }
                    }
                }
            }
            HStack(spacing: 10) {
                SwipeFollowerBoundField(title: "Min", value: model.query.followerRange.minValue) { newMin in
                    model.query.followerRange = .bounded(min: newMin, max: model.query.followerRange.maxValue)
                }
                SwipeFollowerBoundField(title: "Max", value: model.query.followerRange.maxValue) { newMax in
                    model.query.followerRange = .bounded(min: model.query.followerRange.minValue, max: newMax)
                }
            }
            Text("Tip: type values like 20k or 1.5m.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: Outlier + posted

    private var outlierSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SwipeFilterSectionHeader(title: "Min Outlier Score")
                .padding(.bottom, 4)
            ForEach(Array(SwipeDiscoveryFilterPresentation.minimumOutlierOptions.enumerated()), id: \.offset) { _, option in
                SwipeFilterRadioRow(
                    title: option.map { "\(Int($0))× or more" } ?? "Any score",
                    systemImage: "bolt.fill",
                    iconTint: DS.orange,
                    isOn: model.query.minimumOutlierMultiplier == option
                ) {
                    withAnimation(ProMotionSprings.snappy) { model.query.minimumOutlierMultiplier = option }
                }
            }
        }
    }

    private var postedSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SwipeFilterSectionHeader(title: "Posted Within")
                .padding(.bottom, 4)
            ForEach(SocialPostedWindow.allCases, id: \.rawValue) { window in
                SwipeFilterRadioRow(
                    title: window.displayName,
                    systemImage: "calendar",
                    iconTint: DS.info,
                    isOn: model.query.postedWindow == window
                ) {
                    withAnimation(ProMotionSprings.snappy) { model.query.postedWindow = window }
                }
            }
        }
    }

    // MARK: Reset

    private var hasActiveFilters: Bool {
        !model.query.platforms.isEmpty ||
        !model.query.usesDefaultFormats ||
        model.query.followerRange != .any ||
        model.query.minimumOutlierMultiplier != nil ||
        model.query.postedWindow != .lastThreeMonths
    }

    private var resetButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                model.query.platforms = []
                model.query.youtubeFormat = .all
                model.query.substackFormat = .all
                model.query.instagramFormat = .all
                model.query.followerRange = .any
                model.query.minimumOutlierMultiplier = nil
                model.query.postedWindow = .lastThreeMonths
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset filters")
            }
            .font(DS.subheadline.weight(.semibold))
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.glassInputFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.glassBorder, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Follower bound field

struct SwipeFollowerBoundField: View {
    let title: String
    let value: Int?
    let onCommit: (Int?) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            TextField("Any", text: $text)
                .textFieldStyle(.plain)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .focused($isFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .dsGlassInput(isFocused: isFocused, cornerRadius: 9)
        }
        .onAppear(perform: syncFromValue)
        .onChange(of: value) { _, _ in
            if !isFocused { syncFromValue() }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func syncFromValue() {
        text = value.map(String.init) ?? ""
    }

    private func commit() {
        onCommit(SocialFollowerRange.parseFollowerInput(text))
    }
}
