//
//  TaskIntentPicker.swift
//  CosmoOS
//
//  4x2 grid intent selector for task/block creation.
//  Shows 8 intent options with conditional link fields.
//

import SwiftUI

// MARK: - IntentGridItem

/// Maps visual grid items to TaskIntent + metadata
struct IntentGridItem: Identifiable {
    let id: String
    let label: String
    let icon: String
    let intent: TaskIntent
    let color: Color
    let tag: String?  // e.g. "plan", "exercise" for .general variants

    init(label: String, icon: String, intent: TaskIntent, color: Color, tag: String? = nil) {
        self.id = label
        self.label = label
        self.icon = icon
        self.intent = intent
        self.color = color
        self.tag = tag
    }

    static let allItems: [IntentGridItem] = [
        // Row 1
        IntentGridItem(label: "Write", icon: "pencil.line", intent: .writeContent, color: TaskIntent.writeContent.color),
        IntentGridItem(label: "Research", icon: "magnifyingglass", intent: .research, color: TaskIntent.research.color),
        IntentGridItem(label: "Swipe", icon: "bolt.fill", intent: .studySwipes, color: TaskIntent.studySwipes.color),
        IntentGridItem(label: "Think", icon: "brain.head.profile", intent: .deepThink, color: TaskIntent.deepThink.color),
        // Row 2
        IntentGridItem(label: "Review", icon: "eye", intent: .review, color: TaskIntent.review.color),
        IntentGridItem(label: "Plan", icon: "list.clipboard", intent: .general, color: Color(red: 148/255, green: 163/255, blue: 184/255), tag: "plan"),
        IntentGridItem(label: "Exercise", icon: "figure.run", intent: .general, color: Color(red: 16/255, green: 185/255, blue: 129/255), tag: "exercise"),
        IntentGridItem(label: "General", icon: "checkmark.circle", intent: .general, color: TaskIntent.general.color),
    ]
}

// MARK: - TaskIntentPicker

/// 4x2 grid of intent buttons for task/block creation.
/// Shows conditional link field below based on selected intent.
public struct TaskIntentPicker: View {

    // MARK: - Properties

    @Binding var selectedIntent: TaskIntent
    @Binding var linkedIdeaUUID: String

    /// Optional bindings for atom/content linking (used when embedded in block creation)
    @Binding var linkedAtomUUID: String
    @Binding var linkedContentUUID: String

    /// Tag for .general variants (plan, exercise)
    @Binding var intentTag: String

    @State private var hoveredItemId: String?
    @State private var selectedItemId: String = "General"

    // Idea search state
    @State private var ideaSearchQuery: String = ""
    @State private var ideaResults: [IdeaPickerItem] = []
    @State private var isSearchingIdeas: Bool = false
    @State private var selectedIdeaTitle: String = ""
    @State private var showIdeaResults: Bool = false

    // Atom search state (research/think linking)
    @State private var atomSearchQuery: String = ""
    @State private var atomSearchResults: [AtomPickerItem] = []
    @State private var isSearchingAtoms: Bool = false
    @State private var selectedAtomTitle: String = ""
    @State private var showAtomResults: Bool = false

    // Content search state (review linking)
    @State private var contentSearchQuery: String = ""
    @State private var contentSearchResults: [AtomPickerItem] = []
    @State private var isSearchingContent: Bool = false
    @State private var selectedContentTitle: String = ""
    @State private var showContentResults: Bool = false

    @FocusState private var ideaFieldFocused: Bool
    @FocusState private var atomFieldFocused: Bool
    @FocusState private var contentFieldFocused: Bool

    // MARK: - Initialization

    public init(
        selectedIntent: Binding<TaskIntent>,
        linkedIdeaUUID: Binding<String>,
        linkedAtomUUID: Binding<String> = .constant(""),
        linkedContentUUID: Binding<String> = .constant(""),
        intentTag: Binding<String> = .constant("")
    ) {
        self._selectedIntent = selectedIntent
        self._linkedIdeaUUID = linkedIdeaUUID
        self._linkedAtomUUID = linkedAtomUUID
        self._linkedContentUUID = linkedContentUUID
        self._intentTag = intentTag
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Section label
            Text("Intent")
                .font(OnyxTypography.label)
                .foregroundColor(OnyxColors.Text.tertiary)
                .tracking(OnyxTypography.labelTracking)

            // 4x2 intent grid
            intentGrid

            // Conditional link field based on selected intent
            linkFieldForIntent
        }
        .animation(PlannerumSprings.select, value: selectedIntent)
        .animation(PlannerumSprings.select, value: selectedItemId)
    }

    // MARK: - Intent Grid (4x2)

    private var intentGrid: some View {
        let items = IntentGridItem.allItems
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(items) { item in
                intentGridButton(item)
            }
        }
    }

    private func intentGridButton(_ item: IntentGridItem) -> some View {
        Button(action: {
            selectedItemId = item.id
            selectedIntent = item.intent
            intentTag = item.tag ?? ""
            // Clear previous linking state when switching intents
            clearLinkingState()
        }) {
            intentGridButtonLabel(item)
        }
        .buttonStyle(.plain)
        .onHover { hoveredItemId = $0 ? item.id : nil }
    }

    @ViewBuilder
    private func intentGridButtonLabel(_ item: IntentGridItem) -> some View {
        let isSelected = selectedItemId == item.id
        let isHovered = hoveredItemId == item.id

        VStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))

            Text(item.label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundColor(isSelected ? item.color : PlannerumColors.textTertiary)
        .background(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .fill(
                    isSelected
                        ? item.color.opacity(0.15)
                        : isHovered
                            ? Color.white.opacity(0.06)
                            : Color.white.opacity(0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(
                    isSelected ? item.color.opacity(0.4) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Conditional Link Field

    @ViewBuilder
    private var linkFieldForIntent: some View {
        switch selectedItemId {
        case "Write":
            linkedIdeaSection
                .transition(.opacity.combined(with: .move(edge: .top)))
        case "Research":
            linkedAtomSection(label: "Link Research", atomType: .research, icon: "magnifyingglass")
                .transition(.opacity.combined(with: .move(edge: .top)))
        case "Think":
            linkedAtomSection(label: "Link Connection", atomType: .connection, icon: "link")
                .transition(.opacity.combined(with: .move(edge: .top)))
        case "Review":
            linkedContentSection
                .transition(.opacity.combined(with: .move(edge: .top)))
        default:
            EmptyView()
        }
    }

    // MARK: - Linked Idea Section (Write)

    private var linkedIdeaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ideaSearchField

            if !linkedIdeaUUID.isEmpty, !selectedIdeaTitle.isEmpty {
                selectedIdeaBadge
            }

            if showIdeaResults && !ideaResults.isEmpty {
                ideaResultsList
            }
        }
    }

    @ViewBuilder
    private var ideaSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundColor(PlannerumColors.ideasInbox.opacity(0.7))

            TextField("Link idea...", text: $ideaSearchQuery)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textSecondary)
                .textFieldStyle(.plain)
                .focused($ideaFieldFocused)
                .onChange(of: ideaSearchQuery) {
                    searchIdeas(query: ideaSearchQuery)
                }
                .onChange(of: ideaFieldFocused) {
                    if ideaFieldFocused {
                        // Load all ideas immediately on focus
                        searchIdeas(query: "")
                        showIdeaResults = true
                    } else {
                        // Delay hiding to allow click on results
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showIdeaResults = false
                        }
                    }
                }

            if isSearchingIdeas {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedIdeaBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
            Text(selectedIdeaTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button(action: {
                linkedIdeaUUID = ""
                selectedIdeaTitle = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(PlannerumColors.ideasInbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PlannerumColors.ideasInbox.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
    }

    @ViewBuilder
    private var ideaResultsList: some View {
        VStack(spacing: 2) {
            ForEach(ideaResults.prefix(5)) { idea in
                ideaResultRow(idea)
            }
        }
        .padding(4)
        .background(Color(red: 20/255, green: 20/255, blue: 32/255).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func ideaResultRow(_ idea: IdeaPickerItem) -> some View {
        Button(action: {
            linkedIdeaUUID = idea.uuid
            selectedIdeaTitle = idea.title
            ideaSearchQuery = ""
            showIdeaResults = false
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(idea.statusColor)
                    .frame(width: 6, height: 6)
                Text(idea.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let format = idea.format {
                    Text(format)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Linked Atom Section (Research / Think)

    private func linkedAtomSection(label: String, atomType: AtomType, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            atomSearchField(label: label, icon: icon, atomType: atomType)

            if !linkedAtomUUID.isEmpty, !selectedAtomTitle.isEmpty {
                selectedAtomBadge
            }

            if showAtomResults && !atomSearchResults.isEmpty {
                atomResultsList
            }
        }
    }

    @ViewBuilder
    private func atomSearchField(label: String, icon: String, atomType: AtomType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(selectedIntent.color.opacity(0.7))

            TextField("\(label.lowercased())...", text: $atomSearchQuery)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textSecondary)
                .textFieldStyle(.plain)
                .focused($atomFieldFocused)
                .onChange(of: atomSearchQuery) {
                    searchAtoms(query: atomSearchQuery, filterType: atomType)
                }
                .onChange(of: atomFieldFocused) {
                    if atomFieldFocused {
                        searchAtoms(query: "", filterType: atomType)
                        showAtomResults = true
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showAtomResults = false
                        }
                    }
                }

            if isSearchingAtoms {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedAtomBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
            Text(selectedAtomTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button(action: {
                linkedAtomUUID = ""
                selectedAtomTitle = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(selectedIntent.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selectedIntent.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
    }

    @ViewBuilder
    private var atomResultsList: some View {
        VStack(spacing: 2) {
            ForEach(atomSearchResults.prefix(5)) { item in
                atomResultRow(item)
            }
        }
        .padding(4)
        .background(Color(red: 20/255, green: 20/255, blue: 32/255).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func atomResultRow(_ item: AtomPickerItem) -> some View {
        Button(action: {
            linkedAtomUUID = item.uuid
            selectedAtomTitle = item.title
            atomSearchQuery = ""
            showAtomResults = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 10))
                    .foregroundColor(item.accentColor)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(item.typeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Linked Content Section (Review)

    private var linkedContentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            contentSearchField

            if !linkedContentUUID.isEmpty, !selectedContentTitle.isEmpty {
                selectedContentBadge
            }

            if showContentResults && !contentSearchResults.isEmpty {
                contentResultsList
            }
        }
    }

    @ViewBuilder
    private var contentSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 11))
                .foregroundColor(TaskIntent.review.color.opacity(0.7))

            TextField("Link content...", text: $contentSearchQuery)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textSecondary)
                .textFieldStyle(.plain)
                .focused($contentFieldFocused)
                .onChange(of: contentSearchQuery) {
                    searchContent(query: contentSearchQuery)
                }
                .onChange(of: contentFieldFocused) {
                    if contentFieldFocused {
                        searchContent(query: "")
                        showContentResults = true
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showContentResults = false
                        }
                    }
                }

            if isSearchingContent {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var selectedContentBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
            Text(selectedContentTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button(action: {
                linkedContentUUID = ""
                selectedContentTitle = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(TaskIntent.review.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TaskIntent.review.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
    }

    @ViewBuilder
    private var contentResultsList: some View {
        VStack(spacing: 2) {
            ForEach(contentSearchResults.prefix(5)) { item in
                contentResultRow(item)
            }
        }
        .padding(4)
        .background(Color(red: 20/255, green: 20/255, blue: 32/255).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func contentResultRow(_ item: AtomPickerItem) -> some View {
        Button(action: {
            linkedContentUUID = item.uuid
            selectedContentTitle = item.title
            contentSearchQuery = ""
            showContentResults = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundColor(TaskIntent.review.color)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(item.typeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clear State

    private func clearLinkingState() {
        ideaSearchQuery = ""
        ideaResults = []
        selectedIdeaTitle = ""
        showIdeaResults = false

        atomSearchQuery = ""
        atomSearchResults = []
        selectedAtomTitle = ""
        showAtomResults = false

        contentSearchQuery = ""
        contentSearchResults = []
        selectedContentTitle = ""
        showContentResults = false

        // Don't clear the bound UUIDs here — let the parent decide
    }

    // MARK: - Search Logic

    private func searchIdeas(query: String) {
        isSearchingIdeas = true

        Task {
            do {
                let atoms = try await AtomRepository.shared.fetchAll(type: .idea)
                let lowered = query.lowercased()

                let matches = atoms.compactMap { atom -> IdeaPickerItem? in
                    guard let title = atom.title else { return nil }
                    // If query is empty, show all; otherwise filter
                    if !lowered.isEmpty && !title.lowercased().contains(lowered) { return nil }

                    let ideaMeta = atom.metadataValue(as: IdeaMetadata.self)
                    let status = ideaMeta?.ideaStatus ?? .spark

                    return IdeaPickerItem(
                        uuid: atom.uuid,
                        title: title,
                        statusColor: status.color,
                        format: ideaMeta?.contentFormat?.rawValue
                    )
                }

                await MainActor.run {
                    ideaResults = matches
                    isSearchingIdeas = false
                }
            } catch {
                await MainActor.run {
                    ideaResults = []
                    isSearchingIdeas = false
                }
            }
        }
    }

    private func searchAtoms(query: String, filterType: AtomType) {
        isSearchingAtoms = true

        Task {
            do {
                let atoms = try await AtomRepository.shared.fetchAll(type: filterType)
                let lowered = query.lowercased()

                let matches = atoms.compactMap { atom -> AtomPickerItem? in
                    guard let title = atom.title else { return nil }
                    if !lowered.isEmpty && !title.lowercased().contains(lowered) { return nil }

                    return AtomPickerItem(
                        uuid: atom.uuid,
                        title: title,
                        typeLabel: filterType.rawValue.capitalized,
                        icon: filterType == .research ? "magnifyingglass" :
                              filterType == .connection ? "link" : "note.text",
                        accentColor: selectedIntent.color
                    )
                }

                await MainActor.run {
                    atomSearchResults = Array(matches.prefix(8))
                    isSearchingAtoms = false
                }
            } catch {
                await MainActor.run {
                    atomSearchResults = []
                    isSearchingAtoms = false
                }
            }
        }
    }

    private func searchContent(query: String) {
        isSearchingContent = true

        Task {
            do {
                let atoms = try await AtomRepository.shared.fetchAll(type: .content)
                let lowered = query.lowercased()

                let matches = atoms.compactMap { atom -> AtomPickerItem? in
                    guard let title = atom.title else { return nil }
                    if !lowered.isEmpty && !title.lowercased().contains(lowered) { return nil }

                    let phaseMeta = atom.metadataValue(as: ContentAtomMetadata.self)
                    let phaseLabel = phaseMeta?.phase.rawValue ?? "draft"

                    return AtomPickerItem(
                        uuid: atom.uuid,
                        title: title,
                        typeLabel: phaseLabel,
                        icon: "doc.text.fill",
                        accentColor: TaskIntent.review.color
                    )
                }

                await MainActor.run {
                    contentSearchResults = Array(matches.prefix(8))
                    isSearchingContent = false
                }
            } catch {
                await MainActor.run {
                    contentSearchResults = []
                    isSearchingContent = false
                }
            }
        }
    }

    // MARK: - Dynamic Button Label

    /// Returns the selected intent grid item's label for dynamic button text
    public var selectedIntentLabel: String {
        IntentGridItem.allItems.first { $0.id == selectedItemId }?.label ?? "General"
    }

    /// Returns the selected intent grid item's color for dynamic button styling
    public var selectedIntentColor: Color {
        IntentGridItem.allItems.first { $0.id == selectedItemId }?.color ?? TaskIntent.general.color
    }
}

// MARK: - IdeaPickerItem

/// Lightweight model for idea search results in the picker
struct IdeaPickerItem: Identifiable {
    let uuid: String
    let title: String
    let statusColor: Color
    let format: String?

    var id: String { uuid }
}

// MARK: - Preview

#if DEBUG
struct TaskIntentPicker_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            TaskIntentPicker(
                selectedIntent: .constant(.writeContent),
                linkedIdeaUUID: .constant("")
            )
            .padding(24)
        }
        .frame(width: 600, height: 400)
    }
}
#endif
