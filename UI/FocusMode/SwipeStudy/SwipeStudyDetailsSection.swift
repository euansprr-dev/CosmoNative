// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyDetailsSection.swift
// The DETAILS rail section: taxonomy classification rows (narrative, format,
// niche, creator link with search) plus the reclassify flow. Extracted
// verbatim from the old SwipeStudyFocusModeView during the July 2026 rebuild.

import SwiftUI

struct CreatorSearchResult: Identifiable, Equatable, Sendable {
    let name: String
    let uuid: String
    let handle: String

    var id: String { uuid }
}

/// Editable taxonomy classification panel for the swipe study right panel
struct TaxonomySection: View {
    @Binding var analysis: SwipeAnalysis?
    @Binding var currentAtom: Atom?
    @Binding var isReclassifying: Bool
    @Binding var reclassifySuggestion: SwipeAnalysis?
    let onReclassify: () -> Void
    let onAcceptReclassification: () -> Void
    let onRejectReclassification: () -> Void
    let onSaveTaxonomyChange: () -> Void
    var onOpenCreatorProfile: ((String) -> Void)? = nil
    var onLinkCreator: ((String, String) -> Void)? = nil

    @State private var creatorSearchText = ""
    @State private var creatorSearchResults: [CreatorSearchResult] = []
    @State private var creatorSearchCache: [CreatorSearchResult] = []
    @State private var creatorSearchTask: Task<Void, Never>?
    @State private var creatorSearchRequestID = UUID()
    @State private var showCreatorSearch = false
    @State private var linkedCreatorName: String?
    @State private var nicheOptions: [String] = []
    @State private var showNicheInput = false
    @State private var nicheInputText = ""

    private let gold = DS.entitySwipe

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space6) {
                classificationSourceBadge
                Spacer(minLength: DS.space8)
                reclassifyButton
            }

            if let suggestion = reclassifySuggestion {
                reclassifySuggestionBanner(suggestion)
            }

            VStack(spacing: DS.space8) {
                narrativeRow
                secondaryNarrativeRow
                contentFormatRow
                nicheRow
                creatorRow
            }
        }
        .onDisappear {
            creatorSearchTask?.cancel()
        }
    }

    // MARK: - Classification Source Badge

    @ViewBuilder
    private var classificationSourceBadge: some View {
        if let source = analysis?.classificationSource {
            HStack(spacing: 3) {
                Image(systemName: source == .ai ? "checkmark.circle.fill" : "pencil.circle.fill")
                    .font(DS.caption2)
                Text(source == .ai ? "AI" : "Manual")
                    .font(DS.caption2)
            }
            .foregroundStyle(source == .ai ? DS.green : DS.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((source == .ai ? DS.green : DS.orange).opacity(0.11))
            )
        }

        if let confidence = analysis?.classificationConfidence {
            Text("\(Int(confidence * 100))%")
                .font(DS.caption2.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.glassCardFill.opacity(0.45), in: Capsule())
        }
    }

    // MARK: - Reclassify Button

    private var reclassifyButton: some View {
        Button {
            onReclassify()
        } label: {
            HStack(spacing: 4) {
                if isReclassifying {
                    ProgressView()
                        .scaleEffect(0.4)
                        .tint(gold)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(DS.caption2)
                }
                Text("Reclassify")
                    .font(DS.caption2)
            }
            .foregroundStyle(gold.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(gold.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(gold.opacity(0.16), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isReclassifying)
    }

    // MARK: - Reclassification Suggestion Banner

    private func reclassifySuggestionBanner(_ suggestion: SwipeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(DS.caption2)
                    .foregroundStyle(gold)
                Text("AI Suggestion")
                    .font(DS.caption)
                    .foregroundStyle(gold)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let narrative = suggestion.primaryNarrative {
                    suggestionRow("Narrative", value: narrative.displayName, color: narrative.color)
                }
                if let format = suggestion.swipeContentFormat {
                    suggestionRow("Format", value: format.displayName, color: format.color)
                }
                if let niche = suggestion.niche {
                    suggestionRow("Niche", value: niche, color: DS.textSecondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onAcceptReclassification()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(DS.caption2)
                        Text("Accept")
                            .font(DS.caption)
                    }
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onRejectReclassification()
                } label: {
                    Text("Keep Current")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.border, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(gold.opacity(0.045), in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .stroke(gold.opacity(0.14), lineWidth: 0.5)
        )
    }

    private func suggestionRow(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Text(value)
                .font(DS.caption2)
                .foregroundStyle(color)
        }
    }

    // MARK: - Dimension Rows

    private var narrativeRow: some View {
        taxonomyDropdownRow(
            label: "Narrative",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? DS.green : DS.orange
        ) {
            Menu {
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        analysis?.primaryNarrative = style
                        onSaveTaxonomyChange()
                    } label: {
                        narrativePickerLabel(style)
                    }
                }
            } label: {
                narrativeDropdownLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func narrativePickerLabel(_ style: NarrativeStyle) -> some View {
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if analysis?.primaryNarrative == style {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var narrativeDropdownLabel: some View {
        let narrative = analysis?.primaryNarrative
        return taxonomyValuePill(
            title: narrative?.displayName ?? "Select…",
            color: narrative?.color ?? DS.textMuted,
            dotColor: narrative?.color,
            systemImage: narrative?.icon,
            showsChevron: true
        )
    }

    private var secondaryNarrativeRow: some View {
        taxonomyDropdownRow(label: "Secondary", icon: nil, iconColor: .clear) {
            Menu {
                Button("None") {
                    analysis?.secondaryNarrative = nil
                    onSaveTaxonomyChange()
                }
                Divider()
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        analysis?.secondaryNarrative = style
                        onSaveTaxonomyChange()
                    } label: {
                        secondaryPickerLabel(style)
                    }
                }
            } label: {
                secondaryDropdownLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func secondaryPickerLabel(_ style: NarrativeStyle) -> some View {
        HStack {
            Image(systemName: style.icon)
            Text(style.displayName)
            if analysis?.secondaryNarrative == style {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var secondaryDropdownLabel: some View {
        let narrative = analysis?.secondaryNarrative
        return taxonomyValuePill(
            title: narrative?.displayName ?? "None",
            color: narrative?.color ?? DS.textMuted,
            dotColor: narrative?.color,
            systemImage: narrative?.icon,
            showsChevron: true
        )
    }

    private var contentFormatRow: some View {
        taxonomyDropdownRow(
            label: "Format",
            icon: analysis?.classificationSource == .ai ? "checkmark.circle.fill" : "pencil.circle.fill",
            iconColor: analysis?.classificationSource == .ai ? DS.green : DS.orange
        ) {
            Menu {
                ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                    Button {
                        analysis?.swipeContentFormat = format
                        onSaveTaxonomyChange()
                    } label: {
                        formatPickerLabel(format)
                    }
                }
            } label: {
                formatDropdownLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func formatPickerLabel(_ format: ContentFormat) -> some View {
        HStack {
            Image(systemName: format.icon)
            Text(format.displayName)
            if analysis?.swipeContentFormat == format {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var formatDropdownLabel: some View {
        let format = analysis?.swipeContentFormat
        return taxonomyValuePill(
            title: format?.displayName ?? "Select…",
            color: format?.color ?? DS.textMuted,
            dotColor: format?.color,
            systemImage: format?.icon,
            showsChevron: true
        )
    }

    private var nicheRow: some View {
        taxonomyDropdownRow(label: "Niche", icon: nil, iconColor: .clear) {
            if showNicheInput {
                nicheInputField
            } else {
                nicheMenu
            }
        }
        .task { await loadNicheOptions() }
    }

    private var nicheMenu: some View {
        Menu {
            Button("None") {
                analysis?.niche = nil
                onSaveTaxonomyChange()
            }
            if !nicheOptions.isEmpty {
                Divider()
                ForEach(nicheOptions, id: \.self) { option in
                    Button {
                        analysis?.niche = option
                        onSaveTaxonomyChange()
                    } label: {
                        nichePickerLabel(option)
                    }
                }
            }
            Divider()
            Button("New niche…") {
                nicheInputText = ""
                showNicheInput = true
            }
        } label: {
            nicheDropdownLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func nichePickerLabel(_ option: String) -> some View {
        HStack {
            Text(option)
            if analysis?.niche == option {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private var nicheDropdownLabel: some View {
        taxonomyValuePill(
            title: {
                if let niche = analysis?.niche, !niche.isEmpty { return niche }
                return "No niche"
            }(),
            color: analysis?.niche?.isEmpty == false ? gold.opacity(0.85) : DS.textMuted,
            dotColor: nil,
            systemImage: nil,
            showsChevron: true
        )
    }

    /// Free entry routes through NicheRegistry.resolve — a typed label that
    /// matches an existing niche folds into it instead of creating a twin.
    private var nicheInputField: some View {
        HStack(spacing: 6) {
            TextField("Niche name", text: $nicheInputText)
                .textFieldStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .frame(minWidth: 120)
                .onSubmit { commitNicheInput() }

            Button {
                commitNicheInput()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.caption)
                    .foregroundStyle(gold)
                    .accessibilityLabel("Save niche")
            }
            .buttonStyle(.plain)
            .disabled(nicheInputText.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                showNicheInput = false
                nicheInputText = ""
            } label: {
                Image(systemName: "xmark.circle")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityLabel("Cancel niche entry")
            }
            .buttonStyle(.plain)
        }
    }

    private func commitNicheInput() {
        let text = nicheInputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        showNicheInput = false
        nicheInputText = ""
        Task {
            let canonical = await NicheRegistry.shared.resolve(text)
            analysis?.niche = canonical
            onSaveTaxonomyChange()
            await loadNicheOptions()
        }
    }

    private func loadNicheOptions() async {
        let niches = await NicheRegistry.shared.currentNiches()
        nicheOptions = niches
            .sorted { $0.usageCount > $1.usageCount }
            .map(\.value)
    }

    private var creatorRow: some View {
        taxonomyDropdownRow(label: "Creator", icon: nil, iconColor: .clear) {
            if let creatorUUID = analysis?.creatorUUID, !creatorUUID.isEmpty {
                // Linked creator — tappable to open profile, with unlink button
                creatorLinkedView(creatorUUID: creatorUUID)
            } else if showCreatorSearch {
                // Autocomplete search field
                creatorSearchField
            } else {
                // Not linked — tap to search
                creatorUnlinkedView
            }
        }
    }

    @ViewBuilder
    private func creatorLinkedView(creatorUUID: String) -> some View {
        HStack(spacing: 4) {
            Button {
                onOpenCreatorProfile?(creatorUUID)
            } label: {
                creatorLinkedLabel(creatorUUID: creatorUUID)
            }
            .buttonStyle(.plain)

            // Unlink button
            Button {
                analysis?.creatorUUID = nil
                onSaveTaxonomyChange()
                linkedCreatorName = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func creatorLinkedLabel(creatorUUID: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(DS.caption2)
                .foregroundStyle(gold.opacity(0.7))
            Text(linkedCreatorName ?? "Creator")
                .font(DS.caption)
                .foregroundStyle(gold.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(gold.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(gold.opacity(0.18), lineWidth: 0.5)
        )
        .onAppear {
            if linkedCreatorName == nil {
                loadCreatorName(uuid: creatorUUID)
            }
        }
    }

    private var creatorUnlinkedView: some View {
        Button {
            showCreatorSearch = true
            loadAllCreators(refresh: true)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                Text("Link creator")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DS.glassCardFill.opacity(0.45), in: Capsule())
            .overlay(Capsule().stroke(DS.glassBorder.opacity(0.45), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var creatorSearchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                TextField("Search creators…", text: $creatorSearchText)
                    .textFieldStyle(.plain)
                    .font(DS.footnote)
                    .foregroundStyle(DS.text)
                    .onChange(of: creatorSearchText) { _ in filterCreators() }
                Button {
                    showCreatorSearch = false
                    resetCreatorSearchState()
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DS.glassCardFill.opacity(0.5), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(gold.opacity(0.2), lineWidth: 0.5)
            )

            // Results dropdown
            if !creatorSearchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(creatorSearchResults.prefix(5)) { creator in
                        creatorResultRow(creator)
                    }

                    // Create new option
                    if !creatorSearchText.isEmpty {
                        Divider().background(DS.border)
                        creatorCreateNewRow
                    }
                }
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DS.borderActive, lineWidth: 1)
                )
            } else if !creatorSearchText.isEmpty {
                // No matches — show create option
                VStack(spacing: 0) {
                    creatorCreateNewRow
                }
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DS.borderActive, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func creatorResultRow(_ creator: CreatorSearchResult) -> some View {
        Button {
            selectCreator(name: creator.name, uuid: creator.uuid)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(DS.caption2)
                    .foregroundStyle(gold.opacity(0.6))
                Text(creator.name)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var creatorCreateNewRow: some View {
        Button {
            createAndLinkCreator(name: creatorSearchText)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(gold)
                Text("Create \"\(creatorSearchText)\"")
                    .font(DS.caption)
                    .foregroundStyle(gold)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Creator Search Helpers

    private func loadCreatorName(uuid: String) {
        Task {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                await MainActor.run {
                    linkedCreatorName = atom.title ?? "Unknown"
                }
            }
        }
    }

    private func loadAllCreators(refresh: Bool = true) {
        scheduleCreatorSearch(debounce: false, refresh: refresh)
    }

    private func filterCreators() {
        scheduleCreatorSearch(refresh: creatorSearchCache.isEmpty)
    }

    private func scheduleCreatorSearch(debounce: Bool = true, refresh: Bool = false) {
        creatorSearchTask?.cancel()

        let requestID = UUID()
        let query = creatorSearchText
        let cachedItems = creatorSearchCache
        creatorSearchRequestID = requestID

        creatorSearchTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }

            let needsFetch = refresh || cachedItems.isEmpty
            let items: [CreatorSearchResult]
            if needsFetch {
                let creators = try? await AtomRepository.shared.fetchCreators()
                items = (creators ?? []).compactMap(Self.makeCreatorSearchResult)
            } else {
                items = cachedItems
            }

            let results = Self.filterCreatorSearchItems(items, query: query)
            await MainActor.run {
                guard creatorSearchRequestID == requestID, !Task.isCancelled else { return }
                if needsFetch {
                    creatorSearchCache = items
                }
                creatorSearchResults = results
            }
        }
    }

    private static func makeCreatorSearchResult(from atom: Atom) -> CreatorSearchResult? {
        guard let name = atom.title, !name.isEmpty else { return nil }
        let handle = atom.metadataValue(as: CreatorMetadata.self)?.handle ?? ""
        return CreatorSearchResult(name: name, uuid: atom.uuid, handle: handle)
    }

    private static func filterCreatorSearchItems(
        _ items: [CreatorSearchResult],
        query: String
    ) -> [CreatorSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { creator in
            creator.name.lowercased().contains(normalizedQuery)
                || creator.handle.lowercased().contains(normalizedQuery)
        }
    }

    private func selectCreator(name: String, uuid: String) {
        analysis?.creatorUUID = uuid
        linkedCreatorName = name
        showCreatorSearch = false
        resetCreatorSearchState()
        onSaveTaxonomyChange()
        onLinkCreator?(uuid, name)
    }

    private func resetCreatorSearchState() {
        creatorSearchTask?.cancel()
        creatorSearchText = ""
        creatorSearchResults = []
        creatorSearchCache = []
    }

    private func createAndLinkCreator(name: String) {
        // Through the directory: a handle spelled from the name, the post's
        // honest platform, and a twin-aware match — never a handle-less atom
        // that nothing could ever match again.
        let platform = currentAtom.flatMap { CreatorIdentity.platform(for: $0) }
        Task {
            guard let creator = try? await CreatorDirectory.shared.resolve(
                handle: name, name: name, platform: platform, derivedFromName: true
            ) else { return }
            await MainActor.run {
                selectCreator(name: creator.title ?? name, uuid: creator.uuid)
            }
        }
    }

    // MARK: - Taxonomy Row Helper

    private func taxonomyDropdownRow<Content: View>(
        label: String,
        icon: String?,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(DS.caption2)
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(width: 76, alignment: .leading)

            content()

            Spacer()
        }
    }

    private func taxonomyValuePill(
        title: String,
        color: Color,
        dotColor: Color?,
        systemImage: String?,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(DS.caption2)
                    .foregroundStyle(color.opacity(0.75))
            }

            Text(title)
                .font(DS.caption)
                .foregroundStyle(color)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(DS.glassCardFill.opacity(0.48), in: Capsule())
        .overlay(Capsule().stroke(DS.glassBorder.opacity(0.46), lineWidth: 0.5))
    }
}
