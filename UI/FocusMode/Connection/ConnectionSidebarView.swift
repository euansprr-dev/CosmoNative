// CosmoOS/UI/FocusMode/Connection/ConnectionSidebarView.swift
// Collapsible right sidebar for Connection Focus Mode
// 5 sections: Source Material, Ghost Suggestions, Content Usage, Profile Assignments, Maturity
// February 2026

import SwiftUI

// MARK: - Connection Sidebar View

struct ConnectionSidebarView: View {
    let atom: Atom
    @ObservedObject var viewModel: ConnectionFocusModeViewModel
    let isVisible: Bool
    let onDropSource: (Atom) -> Void

    @StateObject private var engine = ConnectionCoDevEngine()
    @State private var sourceMaterials: [Atom] = []
    @State private var contentUsages: [(atom: Atom, sectionsUsed: [String])] = []
    @State private var linkedProfiles: [Atom] = []
    @State private var maturityLevel: ConnectionMaturityLevel = .seed
    @State private var isLoadingSources = false
    @State private var isLoadingUsage = false
    @State private var showProfilePicker = false
    @State private var allProfiles: [Atom] = []

    private let accentColor = CosmoColors.blockConnection

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                panelHeader

                Divider().background(DS.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        sourceSection
                        ghostSuggestionsSection
                        contentUsageSection
                        profileSection
                        maturitySection
                    }
                    .padding(16)
                }
            }
            .background(DS.surface)
            .onAppear {
                Task { await loadAllData() }
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundColor(accentColor)

            Text("Co-Dev")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            // Maturity badge
            maturityBadge(maturityLevel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Section 1: Source Material

    @ViewBuilder
    private var sourceSection: some View {
        sectionHeader(title: "SOURCE MATERIAL", icon: "doc.text.magnifyingglass")

        if isLoadingSources {
            loadingRow("Finding sources...")
        } else if sourceMaterials.isEmpty {
            emptyStateCard(
                icon: "square.and.arrow.down",
                text: "Drag research onto the canvas to get AI suggestions based on your own data."
            )
        } else {
            VStack(spacing: 6) {
                ForEach(sourceMaterials, id: \.uuid) { source in
                    sourceRow(source)
                }
            }
        }
    }

    private func sourceRow(_ source: Atom) -> some View {
        Button {
            onDropSource(source)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconForType(source.type))
                    .font(.system(size: 11))
                    .foregroundColor(colorForType(source.type))

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(2)

                    typeBadge(source.type)
                }

                Spacer()
            }
            .padding(12)
            .dsGlassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 2: Ghost Suggestions

    @ViewBuilder
    private var ghostSuggestionsSection: some View {
        sectionHeader(title: "GHOST SUGGESTIONS", icon: "sparkles")

        if viewModel.state.isGeneratingGhosts {
            loadingRow("Generating suggestions...")
        } else if viewModel.state.totalGhostCount == 0 {
            if sourceMaterials.isEmpty {
                emptyStateCard(
                    icon: "sparkles",
                    text: "Drag research onto the canvas to get AI suggestions based on your own data."
                )
            } else {
                emptyStateCard(
                    icon: "checkmark.circle",
                    text: "All sections have content. Refresh suggestions to find more."
                )
            }
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.state.sections.filter { !$0.ghostSuggestions.isEmpty }) { section in
                    ghostSectionGroup(section)
                }
            }
        }
    }

    @ViewBuilder
    private func ghostSectionGroup(_ section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: section.type.icon)
                    .font(.system(size: 10))
                    .foregroundColor(section.type.accentColor)
                Text(section.type.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(section.type.accentColor)
            }

            ForEach(section.ghostSuggestions) { ghost in
                sidebarGhostCard(ghost, sectionType: section.type)
            }
        }
    }

    private func sidebarGhostCard(_ ghost: GhostSuggestion, sectionType: ConnectionSectionType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ghost.content)
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
                .italic()
                .lineLimit(3)

            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                Text(ghost.sourceAtomTitle)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundColor(sectionType.accentColor.opacity(0.6))

            HStack(spacing: 8) {
                ghostActionButton(label: "Accept", icon: "checkmark.circle.fill", color: sectionType.accentColor) {
                    viewModel.acceptGhost(ghost, inSection: sectionType)
                }

                ghostActionButton(label: "Dismiss", icon: "xmark.circle", color: DS.textMuted) {
                    viewModel.dismissGhost(ghost.id, inSection: sectionType)
                }

                Spacer()

                Text("\(ghost.confidencePercent)%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(sectionType.accentColor.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .foregroundColor(sectionType.accentColor.opacity(0.2))
                )
        )
    }

    private func ghostActionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 3: Content Usage

    @ViewBuilder
    private var contentUsageSection: some View {
        sectionHeader(title: "CONTENT USAGE", icon: "doc.text.fill")

        if isLoadingUsage {
            loadingRow("Finding usage...")
        } else if contentUsages.isEmpty {
            emptyStateCard(
                icon: "doc.text",
                text: "No content has used this connection yet."
            )
        } else {
            VStack(spacing: 6) {
                ForEach(contentUsages, id: \.atom.uuid) { usage in
                    contentUsageRow(usage)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.system(size: 11))
                Text("Used \(contentUsages.count) time\(contentUsages.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DS.textMuted)
            .padding(.top, 4)
        }
    }

    private func contentUsageRow(_ usage: (atom: Atom, sectionsUsed: [String])) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": usage.atom.uuid]
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundColor(CosmoColors.blockContent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(usage.atom.title ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    if !usage.sectionsUsed.isEmpty {
                        Text(usage.sectionsUsed.joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(12)
            .dsGlassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 4: Profile Assignments

    @ViewBuilder
    private var profileSection: some View {
        sectionHeader(title: "PROFILE ASSIGNMENTS", icon: "person.crop.circle")

        if linkedProfiles.isEmpty {
            emptyStateCard(
                icon: "person.crop.circle.badge.plus",
                text: "Assign to a profile so the AI Collaborator can use this framework in drafts."
            )
        } else {
            VStack(spacing: 6) {
                ForEach(linkedProfiles, id: \.uuid) { profile in
                    profileRow(profile)
                }
            }
        }

        profileAssignButton
    }

    private func profileRow(_ profile: Atom) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(DS.entityConnection)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title ?? "Profile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)

                if let meta = profile.metadataValue(as: ClientProfileMetadata.self),
                   let niche = meta.niche {
                    Text(niche)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                }
            }

            Spacer()

            Button {
                removeProfile(profile)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(DS.red.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .dsGlassCard()
    }

    private var profileAssignButton: some View {
        Button {
            showProfilePicker = true
            Task { await loadAllProfiles() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                Text("Assign Profiles")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showProfilePicker) {
            profilePickerPopover
        }
    }

    private var profilePickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign to Profiles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)
                .padding(.bottom, 4)

            if allProfiles.isEmpty {
                Text("No profiles created yet")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
            } else {
                ForEach(allProfiles, id: \.uuid) { profile in
                    profileToggleRow(profile)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(DS.surfaceCard)
    }

    private func profileToggleRow(_ profile: Atom) -> some View {
        let isLinked = linkedProfiles.contains(where: { $0.uuid == profile.uuid })
        return Button {
            if isLinked {
                removeProfile(profile)
            } else {
                addProfile(profile)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isLinked ? DS.entityConnection : DS.textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title ?? "Profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)

                    if let meta = profile.metadataValue(as: ClientProfileMetadata.self),
                       let niche = meta.niche {
                        Text(niche)
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isLinked ? DS.entityConnection.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 5: Maturity Indicator

    @ViewBuilder
    private var maturitySection: some View {
        sectionHeader(title: "MATURITY", icon: "chart.bar.fill")

        VStack(alignment: .leading, spacing: 14) {
            // Level display
            HStack(spacing: 8) {
                maturityBadge(maturityLevel)
                Spacer()
            }

            // Progress metrics
            maturityMetricRow(
                label: "Sections filled",
                value: "\(viewModel.state.completedSectionCount)/8",
                progress: Double(viewModel.state.completedSectionCount) / 8.0
            )

            maturityMetricRow(
                label: "Source materials",
                value: "\(sourceMaterials.count)",
                progress: min(Double(sourceMaterials.count) / 3.0, 1.0)
            )

            maturityMetricRow(
                label: "Content usage",
                value: "\(contentUsages.count)",
                progress: min(Double(contentUsages.count) / 2.0, 1.0)
            )

            maturityMetricRow(
                label: "Profiles assigned",
                value: "\(linkedProfiles.count)",
                progress: min(Double(linkedProfiles.count) / 1.0, 1.0)
            )

            // AI collaborator weight note
            maturityWeightNote
        }
        .padding(14)
        .dsGlassSection()
    }

    private func maturityMetricRow(label: String, value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.border)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(maturityColor(maturityLevel))
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    private var maturityWeightNote: some View {
        let note: String = {
            switch maturityLevel {
            case .seed:
                return "Develop this connection before using in AI drafts."
            case .developing:
                return "Add more sources and sections to strengthen."
            case .mature:
                return "Strong framework. Use in content for proven status."
            case .proven:
                return "Top-tier framework. Prioritized in AI collaborator."
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text(note)
                .font(.system(size: 10))
        }
        .foregroundColor(DS.textMuted)
        .padding(.top, 4)
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(DS.textMuted)
        }
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
        }
        .padding(12)
    }

    private func emptyStateCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(DS.textMuted)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlassCard(cornerRadius: 10)
    }

    private func maturityBadge(_ level: ConnectionMaturityLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(maturityColor(level))
                .frame(width: 6, height: 6)
            Text(level.displayName)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundColor(maturityColor(level))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(maturityColor(level).opacity(0.12), in: Capsule())
    }

    private func maturityColor(_ level: ConnectionMaturityLevel) -> Color {
        switch level {
        case .seed: return Color(hex: "#9CA3AF")      // Gray
        case .developing: return Color(hex: "#FBBF24") // Amber
        case .mature: return Color(hex: "#22C55E")     // Green
        case .proven: return Color(hex: "#6366F1")     // Indigo
        }
    }

    private func typeBadge(_ type: AtomType) -> some View {
        let label: String
        switch type {
        case .research: label = "Research"
        case .idea: label = "Insight"
        case .connection: label = "Connection"
        default: label = type.rawValue.capitalized
        }

        return Text(label)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundColor(colorForType(type))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colorForType(type).opacity(0.12), in: Capsule())
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .research: return "magnifyingglass"
        case .idea: return "lightbulb.fill"
        case .connection: return "link.circle.fill"
        default: return "doc.fill"
        }
    }

    private func colorForType(_ type: AtomType) -> Color {
        switch type {
        case .research: return CosmoColors.blockResearch
        case .idea: return CosmoColors.lavender
        case .connection: return CosmoColors.blockConnection
        default: return CosmoColors.slate
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        isLoadingSources = true
        isLoadingUsage = true

        // Load source materials
        sourceMaterials = await engine.findSourceMaterials(for: atom, limit: 10)
        isLoadingSources = false

        // Load content usage
        contentUsages = await engine.findContentUsage(connectionUUID: atom.uuid)
        isLoadingUsage = false

        // Load linked profiles
        await loadLinkedProfiles()

        // Compute maturity
        recomputeMaturity()
    }

    private func loadLinkedProfiles() async {
        let profileIds = atom.connectionLinkedProfileIds
        var profiles: [Atom] = []
        for id in profileIds {
            if let profile = try? await AtomRepository.shared.fetch(uuid: id) {
                profiles.append(profile)
            }
        }
        linkedProfiles = profiles
    }

    private func recomputeMaturity() {
        maturityLevel = engine.computeMaturity(
            connection: atom,
            sourceCount: sourceMaterials.count,
            contentUsageCount: contentUsages.count,
            profileCount: linkedProfiles.count
        )
    }

    // MARK: - Profile Management

    private func loadAllProfiles() async {
        do {
            allProfiles = try await AtomRepository.shared.fetchByTypes([.clientProfile])
        } catch {
            allProfiles = []
        }
    }

    private func addProfile(_ profile: Atom) {
        linkedProfiles.append(profile)
        saveLinkedProfileIds()
        recomputeMaturity()
    }

    private func removeProfile(_ profile: Atom) {
        linkedProfiles.removeAll { $0.uuid == profile.uuid }
        saveLinkedProfileIds()
        recomputeMaturity()
    }

    private func saveLinkedProfileIds() {
        let ids = linkedProfiles.map { $0.uuid }
        var updatedAtom = atom
        updatedAtom.setConnectionLinkedProfileIds(ids)
        Task {
            _ = try? await AtomRepository.shared.update(updatedAtom)
        }
    }
}
