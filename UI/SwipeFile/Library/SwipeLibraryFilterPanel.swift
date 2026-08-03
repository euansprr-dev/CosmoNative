import SwiftUI

/// The library configuration of the one filter popover: every facet the old chip
/// walls exposed, organized into collapsible sections. Platforms + hook types open
/// by default so it never reads as a wall.
struct SwipeLibraryFilterPanel: View {
    @Bindable var viewModel: SwipeLibraryViewModel
    var maxHeight: CGFloat = 580

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // PROGRESSIVE DISCLOSURE: a library of nothing but posts never
                // sees this section — the facet appears the day a second genre
                // exists, and only then. "Kind" is the Finder word; the rows
                // speak GENRE (the collector's axis), which strictly refines
                // the old structural-kind rows.
                if viewModel.availableGenres.count > 1 {
                    SwipeFilterDisclosure(title: "Kind", isInitiallyExpanded: true) {
                        genreRows
                    }
                    divider
                }
                SwipeFilterDisclosure(title: "Platforms", isInitiallyExpanded: true) {
                    platformRows
                }
                divider
                SwipeFilterDisclosure(title: "Hook Type", isInitiallyExpanded: true) {
                    hookTypeChips
                }
                divider
                SwipeFilterDisclosure(title: "Narrative") {
                    narrativeChips
                }
                divider
                SwipeFilterDisclosure(title: "Format") {
                    formatChips
                }
                divider
                scoreSection
                divider
                studiedSection
                divider
                creatorNicheSection
                if viewModel.filterState.hasActiveFilters {
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

    /// Genre rows wear the genre's own glyph in the neutral muted tint — a
    /// genre is a category, not a brand, so it never earns a colour the way a
    /// platform mark does (Law 6: accent is punctuation).
    private var genreRows: some View {
        VStack(spacing: 2) {
            ForEach(viewModel.availableGenres, id: \.rawValue) { genre in
                SwipeFilterCheckRow(
                    title: genre.pluralName,
                    systemImage: genre.iconName,
                    iconTint: DS.textMuted,
                    trailingCount: viewModel.genreCount(genre),
                    isOn: viewModel.filterState.genres.contains(genre)
                ) {
                    withAnimation(ProMotionSprings.snappy) { viewModel.toggleGenre(genre) }
                }
            }
        }
    }

    private var platformRows: some View {
        VStack(spacing: 2) {
            ForEach(viewModel.availablePlatforms, id: \.self) { platform in
                let name = viewModel.platformName(platform)
                let socialPlatform = SocialPlatform.fromLibraryKey(platform)
                SwipeFilterCheckRow(
                    title: name,
                    systemImage: socialPlatform?.iconName,
                    platformKey: platform,
                    iconTint: socialPlatform?.swipeBrandColor ?? DS.textMuted,
                    isOn: viewModel.filterState.platforms.contains(name)
                ) {
                    withAnimation(ProMotionSprings.snappy) { viewModel.togglePlatform(name) }
                }
            }
        }
    }

    private var hookTypeChips: some View {
        CosmoFlowLayout(spacing: 7) {
            ForEach(SwipeHookType.allCases, id: \.rawValue) { hookType in
                SwipeFilterSegmentChip(
                    label: hookType.displayName,
                    isSelected: viewModel.filterState.hookTypes.contains(hookType)
                ) {
                    withAnimation(ProMotionSprings.snappy) { viewModel.toggleHookType(hookType) }
                }
            }
        }
    }

    private var narrativeChips: some View {
        CosmoFlowLayout(spacing: 7) {
            ForEach(NarrativeStyle.allCases, id: \.rawValue) { narrative in
                SwipeFilterSegmentChip(
                    label: narrative.displayName,
                    isSelected: viewModel.filterState.narratives.contains(narrative)
                ) {
                    withAnimation(ProMotionSprings.snappy) { viewModel.toggleNarrative(narrative) }
                }
            }
        }
    }

    private var formatChips: some View {
        CosmoFlowLayout(spacing: 7) {
            ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                SwipeFilterSegmentChip(
                    label: format.displayName,
                    isSelected: viewModel.filterState.formats.contains(format)
                ) {
                    withAnimation(ProMotionSprings.snappy) { viewModel.toggleFormat(format) }
                }
            }
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SwipeFilterSectionHeader(title: "Hook Score")
                .padding(.bottom, 4)
            ForEach([nil, 6.0, 8.0, 9.0] as [Double?], id: \.self) { threshold in
                SwipeFilterRadioRow(
                    title: threshold.map { "\(Int($0))+ only" } ?? "Any score",
                    systemImage: "gauge.with.needle",
                    iconTint: DS.accent,
                    isOn: viewModel.filterState.minimumHookScore == threshold
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.filterState.minimumHookScore = threshold
                    }
                }
            }
        }
    }

    private var studiedSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SwipeFilterSectionHeader(title: "Studied")
                .padding(.bottom, 4)
            SwipeFilterRadioRow(title: "All", isOn: !viewModel.filterState.onlyStudied && !viewModel.filterState.onlyUnstudied) {
                setStudied(studied: false, unstudied: false)
            }
            SwipeFilterRadioRow(title: "Unstudied", isOn: viewModel.filterState.onlyUnstudied) {
                setStudied(studied: false, unstudied: true)
            }
            SwipeFilterRadioRow(title: "Studied", isOn: viewModel.filterState.onlyStudied) {
                setStudied(studied: true, unstudied: false)
            }
        }
    }

    private func setStudied(studied: Bool, unstudied: Bool) {
        withAnimation(ProMotionSprings.snappy) {
            viewModel.setStudiedFilter(onlyStudied: studied, onlyUnstudied: unstudied)
        }
    }

    private var creatorNicheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwipeFilterSectionHeader(title: "Creator & Niche")
            HStack(spacing: 8) {
                facetMenu(
                    title: viewModel.filterState.creator ?? "Creator",
                    isActive: viewModel.filterState.creator != nil,
                    options: viewModel.availableCreators,
                    select: { viewModel.setCreator($0) }
                )
                facetMenu(
                    title: viewModel.filterState.niche ?? "Niche",
                    isActive: viewModel.filterState.niche != nil,
                    options: viewModel.availableNiches,
                    select: { viewModel.setNiche($0) }
                )
            }
        }
    }

    private func facetMenu(
        title: String,
        isActive: Bool,
        options: [String],
        select: @escaping (String?) -> Void
    ) -> some View {
        Menu {
            Button("Any") { select(nil) }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(option) { select(option) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(DS.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
            }
            .foregroundStyle(isActive ? DS.text : DS.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Capsule().fill(isActive ? DS.accentSoft : DS.glassInputFill))
            .overlay(Capsule().strokeBorder(isActive ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { viewModel.resetFilters() }
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

// MARK: - Disclosure section

struct SwipeFilterDisclosure<Content: View>: View {
    let title: String
    var isInitiallyExpanded = false
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool
    @State private var hovering = false

    init(title: String, isInitiallyExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isInitiallyExpanded = isInitiallyExpanded
        self.content = content
        self._isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(ProMotionSprings.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    SwipeFilterSectionHeader(title: title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(hovering ? DS.textSecondary : DS.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
            .accessibilityLabel("\(title) filters")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                content()
            }
        }
    }
}
