// CosmoOS/UI/Sanctuary/DimensionDetailView.swift
// Shared greenhouse-light dimension workspace shell
// March 2026 — sidebar-first workspace routing

import SwiftUI
import AppKit

// MARK: - Legacy Entry Point

public struct DimensionDetailView: View {
    let dimension: LevelDimension
    let state: SanctuaryDimensionState?
    let insights: [CorrelationInsight]
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var environmentDismiss

    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: dimension,
            preferredPresentation: .modal,
            onBack: dismiss
        )
    }
}

// MARK: - Workspace Shell

enum DimensionWorkspacePresentation {
    case primary
    case pane
    case modal
}

private struct DimensionWorkspaceMode: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
}

struct DimensionWorkspaceView: View {
    let dimension: LevelDimension
    let preferredPresentation: DimensionWorkspacePresentation
    let onBack: (() -> Void)?

    @ObservedObject private var coordinator = DimensionWorkspaceCoordinator.shared
    @ObservedObject private var sessionEngine = DeepWorkSessionEngine.shared
    @Environment(\.isPaneContext) private var isPaneContext

    @State private var searchText = ""
    @State private var selectedModeId: String
    @State private var isPinned: Bool
    @State private var copiedDeepLink = false
    @State private var showMoodCheckIn = false
    @State private var showJournalSheet = false

    init(
        dimension: LevelDimension,
        preferredPresentation: DimensionWorkspacePresentation = .primary,
        onBack: (() -> Void)? = nil
    ) {
        self.dimension = dimension
        self.preferredPresentation = preferredPresentation
        self.onBack = onBack

        let defaultModeId = Self.modes(for: dimension).first?.id ?? "today"
        _selectedModeId = State(
            initialValue: DimensionWorkspacePreferences.selectedMode(
                for: dimension,
                fallback: defaultModeId
            )
        )
        _isPinned = State(initialValue: DimensionWorkspacePreferences.isPinned(dimension))
    }

    private var accentColor: Color {
        OnyxColors.DimensionVivid.color(for: dimension)
    }

    private var currentIndex: DimensionIndex {
        coordinator.index(for: dimension)
    }

    private var modes: [DimensionWorkspaceMode] {
        Self.modes(for: dimension)
    }

    private var selectedMode: DimensionWorkspaceMode {
        modes.first(where: { $0.id == selectedModeId }) ?? modes[0]
    }

    var body: some View {
        GeometryReader { geometry in
            let compactLayout = geometry.size.width < compactBreakpoint

            ZStack {
                DS.bg
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        workspaceHeader(compactLayout: compactLayout)
                        workspaceControls(compactLayout: compactLayout)
                        heroMetricGrid(compactLayout: compactLayout)

                        if compactLayout {
                            VStack(spacing: 18) {
                                mainColumn
                                contextRail
                            }
                        } else {
                            HStack(alignment: .top, spacing: 24) {
                                mainColumn
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                contextRail
                                    .frame(width: 312, alignment: .top)
                            }
                        }
                    }
                    .padding(pagePadding)
                    .frame(maxWidth: preferredPresentation == .modal ? 1100 : 1360)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                reflectionOverlay
            }
        }
        .task(id: dimension.rawValue) {
            await coordinator.loadIfNeeded(dimension)
            if dimension == .creative {
                await coordinator.creativeProvider.loadClientProfiles()
            }
        }
    }

    private var compactBreakpoint: CGFloat {
        switch preferredPresentation {
        case .primary: return 1180
        case .modal: return 860
        case .pane: return 760
        }
    }

    private var pagePadding: CGFloat {
        switch preferredPresentation {
        case .primary: return DS.pageMargin
        case .modal: return 24
        case .pane: return 20
        }
    }

    private var headerSubtitle: String {
        switch dimension {
        case .cognitive:
            return "Deep work, interruption recovery, and timing intelligence."
        case .creative:
            return "Publishing momentum, creator systems, and writing leverage."
        case .physiological:
            return "Recovery translated into planning and execution guidance."
        case .behavioral:
            return "Routines, discipline, and execution posture."
        case .knowledge:
            return "Knowledge graph health, capture flow, and active constellations."
        case .reflection:
            return "Journaling, themes, insights, and synthesis."
        }
    }

    @ViewBuilder
    private func workspaceHeader(compactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    if let onBack, preferredPresentation != .pane {
                        Button(action: onBack) {
                            HStack(spacing: 6) {
                                Image(systemName: preferredPresentation == .modal ? "xmark" : "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(preferredPresentation == .modal ? "Close" : "Back")
                                    .font(DS.buttonText)
                            }
                            .foregroundColor(DS.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Dimensions")
                        .dsSectionLabel()

                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accentColor.opacity(0.12))
                                .frame(width: 46, height: 46)

                            Image(systemName: dimension.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(dimension.displayName)
                                .font(DS.pageTitle)
                                .foregroundColor(DS.text)

                            Text(headerSubtitle)
                                .font(DS.sectionDesc)
                                .foregroundColor(DS.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 12)

                if compactLayout {
                    headerBadges
                } else {
                    HStack(spacing: 10) {
                        headerBadges
                    }
                }
            }
        }
    }

    private var headerBadges: some View {
        Group {
            WorkspaceBadge(
                icon: currentIndex.trend.icon,
                label: "Index \(Int(currentIndex.score.rounded()))",
                tint: accentColor
            )
            WorkspaceBadge(
                icon: "checkmark.shield",
                label: "Confidence \(Int(currentIndex.confidence * 100))%",
                tint: DS.accent
            )
            WorkspaceBadge(
                icon: "clock.arrow.circlepath",
                label: coordinator.freshnessLabel(for: dimension),
                tint: DS.textSecondary
            )
        }
    }

    @ViewBuilder
    private func workspaceControls(compactLayout: Bool) -> some View {
        if compactLayout {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                actionButtonRow(scrolls: true)
                modePicker
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    searchField
                    actionButtonRow(scrolls: false)
                }
                modePicker
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textMuted)

            TextField("Search this workspace", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundColor(DS.text)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsRestingShadow()
    }

    @ViewBuilder
    private func actionButtonRow(scrolls: Bool) -> some View {
        let content = Group {
            HStack(spacing: 8) {
                WorkspaceActionButton(
                    title: isPinned ? "Pinned" : "Pin",
                    icon: isPinned ? "pin.fill" : "pin",
                    tint: accentColor
                ) {
                    isPinned.toggle()
                    DimensionWorkspacePreferences.setPinned(isPinned, for: dimension)
                }

                WorkspaceActionButton(
                    title: "Refresh",
                    icon: "arrow.clockwise",
                    tint: DS.accent
                ) {
                    Task {
                        await coordinator.refresh(dimension)
                    }
                }

                if preferredPresentation != .pane && !isPaneContext {
                    WorkspaceActionButton(
                        title: "Open as Pane",
                        icon: "rectangle.split.2x1",
                        tint: DS.info
                    ) {
                        coordinator.openDimensionAsPane(dimension)
                    }
                }

                WorkspaceActionButton(
                    title: "Command Center",
                    icon: "hexagon",
                    tint: DS.accent
                ) {
                    coordinator.navigateToCommandCenter()
                }

                WorkspaceActionButton(
                    title: "Thinkspace",
                    icon: "square.on.square.dashed",
                    tint: DS.entityIdea
                ) {
                    coordinator.navigateToThinkspace()
                }

                WorkspaceActionButton(
                    title: copiedDeepLink ? "Copied" : "Copy link",
                    icon: copiedDeepLink ? "checkmark" : "link",
                    tint: copiedDeepLink ? DS.green : DS.textSecondary
                ) {
                    copyDeepLink()
                }
            }
        }

        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) {
                content
                    .padding(.vertical, 2)
            }
        } else {
            content
        }
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(modes) { mode in
                    Button {
                        selectedModeId = mode.id
                        DimensionWorkspacePreferences.setSelectedMode(mode.id, for: dimension)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(mode.title)
                                .font(DS.buttonText)
                        }
                        .foregroundColor(selectedMode.id == mode.id ? accentColor : DS.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(selectedMode.id == mode.id ? accentColor.opacity(0.12) : DS.surface)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedMode.id == mode.id ? accentColor.opacity(0.22) : DS.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func heroMetricGrid(compactLayout: Bool) -> some View {
        let columns = compactLayout
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(heroMetrics) { metric in
                WorkspaceMetricTile(metric: metric, accentColor: accentColor)
            }
        }
    }

    private var heroMetrics: [WorkspaceHeroMetric] {
        switch dimension {
        case .cognitive:
            let data = coordinator.cognitiveProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Deep work",
                    value: data.formattedDeepWork,
                    detail: data.activeSession != nil ? "Session live now" : "Logged today"
                ),
                WorkspaceHeroMetric(
                    title: "NELO",
                    value: String(format: "%.0f", data.neloScore),
                    detail: data.neloStatus.displayName
                ),
                WorkspaceHeroMetric(
                    title: "Best window",
                    value: data.primaryWindow?.formattedTimeRange ?? "None",
                    detail: data.primaryWindow.map { "\($0.recommendedTaskTypes.first?.displayName ?? "Focus") next" } ?? "Need more sessions"
                )
            ]
        case .creative:
            let data = coordinator.creativeProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Reach",
                    value: data.formattedReach,
                    detail: data.totalReach > 0 ? "Across recent output" : "No connected data"
                ),
                WorkspaceHeroMetric(
                    title: "Engagement",
                    value: String(format: "%.1f%%", data.engagementRate),
                    detail: data.recentPosts.isEmpty ? "Add content atoms" : "\(data.recentPosts.count) recent posts"
                ),
                WorkspaceHeroMetric(
                    title: "Followers",
                    value: data.formattedFollowers,
                    detail: data.growthStatus.displayName
                )
            ]
        case .physiological:
            let data = coordinator.physiologicalProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Readiness",
                    value: "\(Int(data.readinessScore.rounded()))",
                    detail: data.readinessStatus
                ),
                WorkspaceHeroMetric(
                    title: "Recovery",
                    value: "\(Int(data.recoveryScore.rounded()))",
                    detail: data.recoveryStatus
                ),
                WorkspaceHeroMetric(
                    title: "Sleep",
                    value: "\(data.lastNightSleep.score)",
                    detail: data.formattedSleepDebt == "0m" ? "Debt clear" : "Debt \(data.formattedSleepDebt)"
                )
            ]
        case .behavioral:
            let data = coordinator.behavioralProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Discipline",
                    value: "\(Int(data.disciplineIndex.rounded()))",
                    detail: data.disciplineChange == 0 ? "Flat vs last week" : String(format: "%+.1f vs last week", data.disciplineChange)
                ),
                WorkspaceHeroMetric(
                    title: "Tasks",
                    value: "\(data.tasksCompleted)/\(max(data.tasksTotal, 1))",
                    detail: "Completed today"
                ),
                WorkspaceHeroMetric(
                    title: "Streaks",
                    value: "\(data.activeStreaks.count)",
                    detail: data.endangeredStreaks.isEmpty ? "All stable" : "\(data.endangeredStreaks.count) at risk"
                )
            ]
        case .knowledge:
            let data = coordinator.knowledgeProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Captures",
                    value: "\(data.capturesToday)",
                    detail: data.capturesChange == 0 ? "Flat vs yesterday" : String(format: "%+d vs yesterday", data.capturesChange)
                ),
                WorkspaceHeroMetric(
                    title: "Research",
                    value: data.formattedResearchToday,
                    detail: "\(data.totalNodeCount) active nodes"
                ),
                WorkspaceHeroMetric(
                    title: "Density",
                    value: "\(Int((data.semanticDensity * 100).rounded()))%",
                    detail: data.densityLabel.capitalized
                )
            ]
        case .reflection:
            let data = coordinator.reflectionProvider.data
            return [
                WorkspaceHeroMetric(
                    title: "Journal streak",
                    value: "\(data.journalStreak)",
                    detail: "Best \(data.journalPersonalBest)"
                ),
                WorkspaceHeroMetric(
                    title: "Words today",
                    value: "\(data.wordsToday)",
                    detail: data.wordsAverage > 0 ? "Avg \(data.wordsAverage)" : "Start a note"
                ),
                WorkspaceHeroMetric(
                    title: "Insights",
                    value: "\(data.totalGrails)",
                    detail: "\(data.grailsThisMonth) this month"
                )
            ]
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if coordinator.isLoading(dimension) && isCurrentWorkspaceEmpty {
                loadingState
            } else {
                dimensionContent
            }
        }
    }

    private var contextRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            quickActionsCard
            connectedSurfacesCard
            qualityCard
        }
    }

    private var isCurrentWorkspaceEmpty: Bool {
        switch dimension {
        case .cognitive:
            return coordinator.cognitiveProvider.data.isEmpty
        case .creative:
            return coordinator.creativeProvider.data.isEmpty
        case .physiological:
            return coordinator.physiologicalProvider.data.isEmpty
        case .behavioral:
            return coordinator.behavioralProvider.data.isEmpty
        case .knowledge:
            return coordinator.knowledgeProvider.data.isEmpty
        case .reflection:
            return coordinator.reflectionProvider.data.isEmpty
        }
    }

    private var loadingState: some View {
        WorkspaceSurface {
            VStack(alignment: .leading, spacing: 14) {
                Text("Loading workspace")
                    .font(DS.cardTitle)
                    .foregroundColor(DS.text)

                ProgressView()
                    .tint(accentColor)

                Text("Pulling the latest signals for this dimension.")
                    .font(DS.sectionDesc)
                    .foregroundColor(DS.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var dimensionContent: some View {
        switch dimension {
        case .cognitive:
            cognitiveContent
        case .creative:
            creativeContent
        case .physiological:
            physiologicalContent
        case .behavioral:
            behavioralContent
        case .knowledge:
            knowledgeContent
        case .reflection:
            reflectionContent
        }
    }

    // MARK: - Cognitive

    private var cognitiveContent: some View {
        let data = coordinator.cognitiveProvider.data
        let sessions = data.deepWorkSessions.filter { matchesSearch([$0.taskType.displayName, $0.notes ?? ""]) }
        let interruptions = data.interruptions.filter { matchesSearch([$0.source.displayName, $0.app ?? ""]) }
        let correlations = data.topCorrelations.filter { matchesSearch([$0.sourceMetric, $0.targetMetric, $0.actionInsight]) }

        return Group {
            if data.isEmpty {
                emptyState(
                    title: "No focus history yet",
                    message: "Start or resume a deep work session and this workspace will turn into a real operating surface.",
                    buttonTitle: sessionEngine.activeSession == nil ? "Start 45-minute session" : "Resume active session"
                ) {
                    coordinator.startQuickDeepWorkSession()
                    coordinator.navigateToCommandCenter()
                }
            } else {
                switch selectedMode.id {
                case "trends":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Focus stability", subtitle: "Hourly stability across the current day.")
                        VStack(spacing: 10) {
                            ForEach(data.focusStabilityByHour.keys.sorted(), id: \.self) { hour in
                                let stability = data.focusStabilityByHour[hour] ?? 0
                                WorkspaceBarRow(
                                    label: String(format: "%02d:00", hour),
                                    valueLabel: "\(Int(stability.rounded()))",
                                    progress: stability / 100,
                                    tint: accentColor
                                )
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Interruptions", subtitle: "Where cognitive overhead is leaking.")
                        if interruptions.isEmpty {
                            mutedLine("No interruptions logged today.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(interruptions.prefix(8)) { interruption in
                                    WorkspaceListRow(
                                        title: interruption.source.displayName,
                                        subtitle: "\(interruption.formattedTime) • \(Int(interruption.recoveryMinutes))m recovery",
                                        accentColor: Color(hex: interruption.severityColor)
                                    ) {
                                        if let app = interruption.app, !app.isEmpty {
                                            Text(app)
                                                .font(DS.cardMeta)
                                                .foregroundColor(DS.textMuted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                case "insights":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Correlations", subtitle: "Signals that are currently shaping output quality.")
                        if correlations.isEmpty {
                            mutedLine("Not enough data for a stable correlation model yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(correlations.prefix(6)) { correlation in
                                    WorkspaceListRow(
                                        title: correlation.title,
                                        subtitle: correlation.actionInsight,
                                        accentColor: accentColor
                                    ) {
                                        Text(correlation.formattedCoefficient)
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Reflection signal", subtitle: "How self-observation is feeding execution quality.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "Reflection depth",
                                valueLabel: String(format: "%.1f", data.reflectionDepthScore),
                                progress: min(1, data.reflectionDepthScore / 10),
                                tint: accentColor
                            )
                            WorkspaceBarRow(
                                label: "Insight markers",
                                valueLabel: "\(data.journalInsightMarkersToday)",
                                progress: min(1, Double(data.journalInsightMarkersToday) / 8),
                                tint: DS.accent
                            )
                            if !data.detectedThemes.isEmpty {
                                tagCloud(data.detectedThemes)
                            }
                            if let excerpt = data.journalExcerpt, !excerpt.isEmpty {
                                Text(excerpt)
                                    .font(DS.body)
                                    .foregroundColor(DS.textSecondary)
                                    .lineLimit(4)
                            }
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Deep work runway", subtitle: "What to do with your remaining cognitive capacity today.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "Quality",
                                valueLabel: "\(Int(data.averageQualityToday.rounded()))",
                                progress: data.averageQualityToday / 100,
                                tint: accentColor
                            )
                            WorkspaceBarRow(
                                label: "Capacity left",
                                valueLabel: data.formattedCapacityRemaining,
                                progress: max(0, 1 - (data.predictedCapacityRemaining / (4 * 3600))),
                                tint: DS.accent
                            )
                            if let activeSession = data.activeSession {
                                WorkspaceActionStrip(
                                    primaryTitle: "Resume current session",
                                    primaryIcon: "play.fill",
                                    primaryTint: accentColor
                                ) {
                                    coordinator.navigateToCommandCenter()
                                }
                                secondaryLine("Active: \(activeSession.taskType.displayName) • \(activeSession.durationMinutes)m so far")
                            } else {
                                WorkspaceActionStrip(
                                    primaryTitle: "Start a 45-minute session",
                                    primaryIcon: "timer",
                                    primaryTint: accentColor
                                ) {
                                    coordinator.startQuickDeepWorkSession()
                                    coordinator.navigateToCommandCenter()
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Today's sessions", subtitle: "Recent focus blocks with enough context to act on.")
                        VStack(spacing: 12) {
                            ForEach(sessions.prefix(6)) { session in
                                WorkspaceListRow(
                                    title: session.taskType.displayName,
                                    subtitle: "\(session.durationMinutes)m • \(Int(session.qualityScore.rounded())) quality • \(session.interruptionCount) interruptions",
                                    accentColor: accentColor
                                ) {
                                    Text(session.notes?.isEmpty == false ? "Notes" : "Session")
                                        .font(DS.cardMeta)
                                        .foregroundColor(DS.textMuted)
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Optimal windows", subtitle: "Where the model thinks high-value work will land best.")
                        if data.predictedOptimalWindows.isEmpty {
                            mutedLine("Need more focus sessions before timing guidance becomes reliable.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictedOptimalWindows.prefix(4)) { window in
                                    WorkspaceListRow(
                                        title: window.formattedTimeRange,
                                        subtitle: window.recommendedTaskTypes.map(\.displayName).joined(separator: " • "),
                                        accentColor: window.isPrimary ? accentColor : DS.accent
                                    ) {
                                        Text("\(Int(window.confidence.rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Creative

    private var creativeContent: some View {
        let provider = coordinator.creativeProvider
        let data = provider.data
        let filteredPosts = data.recentPosts.filter { post in
            matchesSearch([post.platform.displayName, post.caption, post.type.displayName])
        }

        return Group {
            if data.isEmpty {
                emptyState(
                    title: "Creative systems are not connected yet",
                    message: "Connect social signals or keep publishing from content atoms so this view can become your creator operating room.",
                    buttonTitle: "Open creator database"
                ) {
                    coordinator.openCreatorDatabase()
                }
            } else {
                if !provider.clientProfiles.isEmpty {
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Profiles", subtitle: "Scope the workspace to a client or creator profile.")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                profileChip(title: "All", isSelected: provider.selectedProfileUUID == nil) {
                                    provider.selectedProfileUUID = nil
                                    Task {
                                        await coordinator.refresh(.creative)
                                    }
                                }

                                ForEach(provider.clientProfiles, id: \.uuid) { profile in
                                    profileChip(
                                        title: profile.name,
                                        isSelected: provider.selectedProfileUUID == profile.uuid
                                    ) {
                                        provider.selectedProfileUUID = profile.uuid
                                        Task {
                                            await coordinator.refresh(.creative)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                switch selectedMode.id {
                case "pipeline":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Pipeline health", subtitle: "Publishing flow from active phases.")
                        if provider.funnelData.isEmpty {
                            mutedLine("No active pipeline counts yet.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(provider.funnelData.enumerated()), id: \.offset) { _, item in
                                    WorkspaceBarRow(
                                        label: item.phase.displayName,
                                        valueLabel: "\(item.count)",
                                        progress: min(1, Double(item.count) / Double(maxPipelineCount)),
                                        tint: accentColor
                                    )
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Suggested schedule", subtitle: "Where upcoming output has the best publishing odds.")
                        if data.suggestedSchedule.isEmpty {
                            mutedLine("No schedule suggestions yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.suggestedSchedule.prefix(6)) { post in
                                    WorkspaceListRow(
                                        title: post.title,
                                        subtitle: "\(post.windowType) • \(post.formattedScheduledTime)",
                                        accentColor: post.platform.color
                                    ) {
                                        Text("\(Int((post.confidence * 100).rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                case "insights":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Platform mix", subtitle: "Where attention is clustering right now.")
                        if data.platformMetrics.isEmpty {
                            mutedLine("No platform metrics yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.platformMetrics.prefix(6)) { platform in
                                    WorkspaceListRow(
                                        title: platform.platform.displayName,
                                        subtitle: "\(platform.formattedFollowers) followers • \(String(format: "%.1f%%", platform.engagementRate)) engagement",
                                        accentColor: platform.platform.color
                                    ) {
                                        Text("\(Int(platform.reachPercentage.rounded()))% reach share")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Trending topics", subtitle: "Themes currently worth turning into briefs or drafts.")
                        if data.trendingTopics.isEmpty {
                            mutedLine("No topic signals yet.")
                        } else {
                            tagCloud(Array(data.trendingTopics.prefix(12)))
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Recent output", subtitle: "Posts and drafts with fast actions into focus mode or panes.")
                        VStack(spacing: 12) {
                            ForEach(filteredPosts.prefix(8)) { post in
                                WorkspaceListRow(
                                    title: post.caption.isEmpty ? "\(post.platform.displayName) post" : post.caption,
                                    subtitle: "\(post.platform.displayName) • \(post.type.displayName) • \(post.formattedReach)",
                                    accentColor: post.platform.color
                                ) {
                                    HStack(spacing: 8) {
                                        Button("Focus") {
                                            coordinator.openAtomInFocusMode(uuid: post.id)
                                        }
                                        .buttonStyle(.plain)
                                        .font(DS.cardMeta)
                                        .foregroundColor(accentColor)

                                        Button("Pane") {
                                            Task {
                                                await coordinator.openAtomAsPane(uuid: post.id)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .font(DS.cardMeta)
                                        .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Posting windows", subtitle: "Slots with the strongest modeled reach and engagement lift.")
                        if data.predictedWindows.isEmpty {
                            mutedLine("Need more publishing history before windows stabilize.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictedWindows.prefix(4)) { window in
                                    WorkspaceListRow(
                                        title: window.formattedTimeRange,
                                        subtitle: "\(window.platform.displayName) • \(window.reason)",
                                        accentColor: window.platform.color
                                    ) {
                                        Text("+\(Int(window.predictedBoost.rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var maxPipelineCount: Int {
        max(coordinator.creativeProvider.funnelData.map(\.count).max() ?? 1, 1)
    }

    // MARK: - Knowledge

    private var knowledgeContent: some View {
        let data = coordinator.knowledgeProvider.data
        let captures = data.recentCaptures.filter {
            matchesSearch([$0.title, $0.preview, $0.tags.joined(separator: " ")])
        }
        let growingClusters = data.growingClusters.filter {
            matchesSearch([$0.name, $0.status.displayName])
        }

        return Group {
            if data.isEmpty {
                emptyState(
                    title: "Your graph has not been exercised yet",
                    message: "Capture ideas, research, and notes, then revisit them from Thinkspaces to grow this routing view.",
                    buttonTitle: "Jump to Thinkspace"
                ) {
                    coordinator.navigateToThinkspace()
                }
            } else {
                switch selectedMode.id {
                case "map":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Cluster health", subtitle: "Where semantic gravity is currently strongest.")
                        if data.clusters.isEmpty {
                            mutedLine("No active clusters yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.clusters.prefix(6)) { cluster in
                                    WorkspaceListRow(
                                        title: cluster.name,
                                        subtitle: "\(cluster.nodeCount) nodes • \(cluster.daysSinceActivity)d since last activity",
                                        accentColor: Color(hex: cluster.colorHex)
                                    ) {
                                        Text(cluster.status.displayName)
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Research rhythm", subtitle: "Time invested in knowledge work this week.")
                        VStack(spacing: 10) {
                            ForEach(data.weeklyResearchData) { day in
                                WorkspaceBarRow(
                                    label: day.dayOfWeek,
                                    valueLabel: "\(day.totalMinutes)m",
                                    progress: min(1, Double(day.totalMinutes) / Double(maxResearchMinutes)),
                                    tint: accentColor
                                )
                            }
                        }
                    }
                case "insights":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Emerging links", subtitle: "Cross-cluster bridges worth exploring now.")
                        if data.emergingLinks.isEmpty {
                            mutedLine("No emerging links yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.emergingLinks.prefix(5)) { link in
                                    WorkspaceListRow(
                                        title: "\(link.sourceCluster) → \(link.targetCluster)",
                                        subtitle: link.description,
                                        accentColor: accentColor
                                    ) {
                                        Text("\(Int((link.strength * 100).rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Predictions", subtitle: "Where the graph expects leverage to come from next.")
                        if data.predictions.isEmpty {
                            mutedLine("No predictions yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictions.prefix(4)) { prediction in
                                    WorkspaceListRow(
                                        title: prediction.condition,
                                        subtitle: prediction.prediction,
                                        accentColor: accentColor
                                    ) {
                                        Text("\(Int((prediction.confidence * 100).rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Recent captures", subtitle: "Fast routes from fresh inputs back into focused work.")
                        VStack(spacing: 12) {
                            ForEach(captures.prefix(8)) { capture in
                                WorkspaceListRow(
                                    title: capture.title,
                                    subtitle: "\(capture.type.displayName) • \(capture.connectionCount) links • \(capture.timeAgo)",
                                    accentColor: accentColor
                                ) {
                                    HStack(spacing: 8) {
                                        Button("Focus") {
                                            coordinator.openAtomInFocusMode(uuid: capture.id.uuidString)
                                        }
                                        .buttonStyle(.plain)
                                        .font(DS.cardMeta)
                                        .foregroundColor(accentColor)

                                        Button("Pane") {
                                            Task {
                                                await coordinator.openAtomAsPane(uuid: capture.id.uuidString)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .font(DS.cardMeta)
                                        .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Growing clusters", subtitle: "Collections with the strongest recent momentum.")
                        if growingClusters.isEmpty {
                            mutedLine("No growing clusters detected yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(growingClusters.prefix(5)) { cluster in
                                    WorkspaceListRow(
                                        title: cluster.name,
                                        subtitle: "\(cluster.nodeCount) nodes • growth \(Int((cluster.growthRate * 100).rounded()))%",
                                        accentColor: Color(hex: cluster.colorHex)
                                    ) {
                                        Text(cluster.status.displayName)
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var maxResearchMinutes: Int {
        max(coordinator.knowledgeProvider.data.weeklyResearchData.map(\.totalMinutes).max() ?? 1, 1)
    }

    // MARK: - Behavioral

    private var behavioralContent: some View {
        let data = coordinator.behavioralProvider.data
        let streaks = (data.activeStreaks + data.endangeredStreaks).filter {
            matchesSearch([$0.name, $0.category.displayName])
        }

        return Group {
            if data.isEmpty {
                emptyState(
                    title: "Behavioral guidance needs more signal",
                    message: "Tasks, deep work blocks, routines, and workouts will turn this into a true execution bridge.",
                    buttonTitle: "Open Command Center"
                ) {
                    coordinator.navigateToCommandCenter()
                }
            } else {
                switch selectedMode.id {
                case "routines":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Routine trackers", subtitle: "How predictable the day is becoming.")
                        VStack(spacing: 12) {
                            routineCard(data.morningRoutine, tint: accentColor)
                            routineCard(data.sleepSchedule, tint: DS.accent)
                            routineCard(data.wakeSchedule, tint: DS.info)
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Streaks", subtitle: "Active streaks and anything close to breaking.")
                        if streaks.isEmpty {
                            mutedLine("No streaks yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(streaks.prefix(6)) { streak in
                                    WorkspaceListRow(
                                        title: streak.name,
                                        subtitle: "\(streak.currentDays)d current • \(streak.statusText)",
                                        accentColor: streak.isEndangered ? DS.orange : accentColor
                                    ) {
                                        Text("+\(streak.xpPerDay) XP/day")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                case "forecast":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Level-up path", subtitle: "Which actions accelerate the next discipline milestone.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "XP progress",
                                valueLabel: "\(data.levelUpPath.xpProgress)/\(max(data.levelUpPath.xpNeeded, 1))",
                                progress: data.levelUpPath.progress,
                                tint: accentColor
                            )
                            Text("\(data.levelUpPath.xpRemaining) XP remaining • est. \(data.levelUpPath.estimatedDays)d")
                                .font(DS.sectionDesc)
                                .foregroundColor(DS.textSecondary)
                            ForEach(data.levelUpPath.fastestActions.prefix(4)) { action in
                                WorkspaceListRow(
                                    title: action.action,
                                    subtitle: "\(action.daysRequired)d effort",
                                    accentColor: accentColor
                                ) {
                                    Text("+\(action.xpReward) XP")
                                        .font(DS.cardMeta)
                                        .foregroundColor(DS.textSecondary)
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Predictions", subtitle: "Likely behavioral outcomes if today continues as-is.")
                        if data.predictions.isEmpty {
                            mutedLine("No forecasts yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictions.prefix(4)) { prediction in
                                    WorkspaceListRow(
                                        title: prediction.condition,
                                        subtitle: prediction.prediction,
                                        accentColor: accentColor
                                    ) {
                                        Text("\(Int((prediction.confidence * 100).rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Component scores", subtitle: "The operational surfaces currently dragging or lifting execution.")
                        let columns = [GridItem(.flexible()), GridItem(.flexible())]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(data.allComponentScores) { component in
                                WorkspaceSurface(innerPadding: 14, shadowed: false) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(component.name)
                                            .font(DS.cardTitle)
                                            .foregroundColor(DS.text)

                                        Text("\(Int(component.currentScore.rounded()))")
                                            .font(.system(size: 28, weight: .light))
                                            .foregroundColor(DS.text)

                                        Text(component.status.displayName)
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Today timeline", subtitle: "Execution events already shaping the day.")
                        if data.todayEvents.isEmpty {
                            mutedLine("No events logged yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.todayEvents.prefix(8)) { event in
                                    WorkspaceListRow(
                                        title: event.eventType.displayName,
                                        subtitle: "\(event.formattedTime) • \(event.details ?? "Logged event")",
                                        accentColor: event.status.color
                                    ) {
                                        Text(event.status == .violation ? "Violation" : "On track")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Physiological

    private var physiologicalContent: some View {
        let provider = coordinator.physiologicalProvider
        let data = provider.data

        return Group {
            if !provider.isConnected && data.isEmpty {
                emptyState(
                    title: "Health signals are not connected",
                    message: "Grant HealthKit access to translate recovery, sleep, and activity into planning guidance.",
                    buttonTitle: "Connect Apple Health"
                ) {
                    Task {
                        await provider.connect()
                        await coordinator.refresh(.physiological)
                    }
                }
            } else {
                switch selectedMode.id {
                case "recovery":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Body zones", subtitle: "Areas currently asking for more recovery margin.")
                        if data.bodyZoneStatus.isEmpty {
                            mutedLine("No body zone data available.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.bodyZoneStatus.prefix(6)) { zone in
                                    WorkspaceListRow(
                                        title: zone.zone.displayName,
                                        subtitle: zone.issues.isEmpty ? "Stable" : zone.issues.joined(separator: " • "),
                                        accentColor: accentColor
                                    ) {
                                        Text("\(Int(zone.healthPercent.rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Workouts", subtitle: "Recent output that should influence planning intensity.")
                        if data.workouts.isEmpty {
                            mutedLine("No recent workouts logged.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.workouts.prefix(6)) { workout in
                                    WorkspaceListRow(
                                        title: workout.type.displayName,
                                        subtitle: "\(workout.formattedDuration) • \(workout.formattedDate)",
                                        accentColor: accentColor
                                    ) {
                                        Text("\(workout.calories) kcal")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                case "insights":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Correlations", subtitle: "Physiology signals with the strongest observed impact.")
                        if data.correlations.isEmpty {
                            mutedLine("No correlations available yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.correlations.prefix(5)) { correlation in
                                    WorkspaceListRow(
                                        title: "\(correlation.sourceMetric) → \(correlation.targetMetric)",
                                        subtitle: "\(correlation.strengthLabel) • \(correlation.timeframe)",
                                        accentColor: correlation.isPositive ? accentColor : DS.orange
                                    ) {
                                        Text(String(format: "%.2f", correlation.correlationCoefficient))
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Predictions", subtitle: "Likely downstream effects if your current recovery state holds.")
                        if data.predictions.isEmpty {
                            mutedLine("No health predictions available yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictions.prefix(4)) { prediction in
                                    WorkspaceListRow(
                                        title: prediction.condition,
                                        subtitle: prediction.prediction,
                                        accentColor: accentColor
                                    ) {
                                        Text("\(Int((prediction.confidence * 100).rounded()))%")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Readiness for work", subtitle: "The translation layer between recovery and execution planning.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "Readiness",
                                valueLabel: "\(Int(data.readinessScore.rounded()))",
                                progress: data.readinessScore / 100,
                                tint: accentColor
                            )
                            WorkspaceBarRow(
                                label: "Recovery",
                                valueLabel: "\(Int(data.recoveryScore.rounded()))",
                                progress: data.recoveryScore / 100,
                                tint: DS.accent
                            )
                            Text("Peak window \(data.formattedPeakWindow)")
                                .font(DS.sectionDesc)
                                .foregroundColor(DS.textSecondary)
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Sleep + activity", subtitle: "Yesterday's recovery and today's locomotion in one glance.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "Sleep score",
                                valueLabel: "\(data.lastNightSleep.score)",
                                progress: Double(data.lastNightSleep.score) / 100,
                                tint: accentColor
                            )
                            WorkspaceBarRow(
                                label: "Move ring",
                                valueLabel: "\(data.dailyRings.moveCalories)/\(max(data.dailyRings.moveGoal, 1))",
                                progress: min(1, Double(data.dailyRings.moveCalories) / Double(max(data.dailyRings.moveGoal, 1))),
                                tint: DS.info
                            )
                            WorkspaceBarRow(
                                label: "Steps",
                                valueLabel: "\(data.stepCount)",
                                progress: min(1, Double(data.stepCount) / 10_000),
                                tint: DS.accent
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reflection

    private var reflectionContent: some View {
        let data = coordinator.reflectionProvider.data
        let insights = data.grailInsights.filter {
            matchesSearch([$0.content, $0.sourceEntryTitle, $0.tags.joined(separator: " ")])
        }

        return Group {
            if data.isEmpty {
                emptyState(
                    title: "Reflection has not been captured yet",
                    message: "Journal entries, mood check-ins, and meditation sessions will turn this into a genuine synthesis layer.",
                    buttonTitle: "New journal entry"
                ) {
                    showJournalSheet = true
                }
            } else {
                switch selectedMode.id {
                case "themes":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Recurring themes", subtitle: "The motifs most present in current reflection.")
                        if data.recurringThemes.isEmpty {
                            mutedLine("No extracted themes yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.recurringThemes.prefix(8)) { theme in
                                    WorkspaceListRow(
                                        title: theme.name,
                                        subtitle: theme.changeLabel,
                                        accentColor: Color(hex: theme.colorHex)
                                    ) {
                                        Text("\(theme.mentionCount)x")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Emerging themes", subtitle: "Patterns gaining strength this week.")
                        if data.emergingThemes.isEmpty {
                            mutedLine("No new emerging themes yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.emergingThemes.prefix(5)) { theme in
                                    WorkspaceListRow(
                                        title: theme.name,
                                        subtitle: theme.description,
                                        accentColor: accentColor
                                    ) {
                                        Text("+\(theme.mentionsThisWeek)")
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                case "insights":
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Grail insights", subtitle: "Cross-links worth carrying back into current work.")
                        if insights.isEmpty {
                            mutedLine("No grail insights yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(insights.prefix(6)) { insight in
                                    WorkspaceListRow(
                                        title: insight.preview,
                                        subtitle: insight.sourceEntryTitle,
                                        accentColor: accentColor
                                    ) {
                                        tagCloud(Array(insight.tags.prefix(3)), compact: true)
                                    }
                                }
                            }
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Predictions", subtitle: "Emerging patterns the reflection layer is already noticing.")
                        if data.predictions.isEmpty {
                            mutedLine("No reflection predictions yet.")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(data.predictions.prefix(4)) { prediction in
                                    WorkspaceListRow(
                                        title: prediction.condition,
                                        subtitle: prediction.prediction,
                                        accentColor: accentColor
                                    ) {
                                        Text(prediction.timeframe)
                                            .font(DS.cardMeta)
                                            .foregroundColor(DS.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                default:
                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Today's inner state", subtitle: "Mood, words, and meditation as immediate context.")
                        VStack(alignment: .leading, spacing: 12) {
                            WorkspaceBarRow(
                                label: "Meditation",
                                valueLabel: "\(data.meditationToday)m",
                                progress: data.meditationProgress,
                                tint: accentColor
                            )
                            WorkspaceBarRow(
                                label: "Writing",
                                valueLabel: "\(data.wordsToday)",
                                progress: min(1, data.journalWordProgress),
                                tint: DS.accent
                            )
                            Text("\(data.todayMood.emoji) \(data.todayMood.description)")
                                .font(DS.body)
                                .foregroundColor(DS.text)
                        }
                    }

                    WorkspaceSurface {
                        WorkspaceSectionHeader(title: "Latest journal surface", subtitle: "The most recent synthesis still active in memory.")
                        if data.todayEntryPreview.isEmpty {
                            mutedLine("No journal entry yet today.")
                        } else {
                            Text(data.todayEntryPreview)
                                .font(DS.body)
                                .foregroundColor(DS.textSecondary)
                                .lineLimit(6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rail

    private var quickActionsCard: some View {
        WorkspaceSurface {
            WorkspaceSectionHeader(title: "Quick actions", subtitle: "High-leverage actions linked to this workspace.")
            VStack(alignment: .leading, spacing: 10) {
                switch dimension {
                case .cognitive:
                    WorkspaceActionButton(
                        title: sessionEngine.activeSession == nil ? "Start deep work session" : "Resume active session",
                        icon: "timer",
                        tint: accentColor,
                        prominent: true
                    ) {
                        coordinator.startQuickDeepWorkSession()
                        coordinator.navigateToCommandCenter()
                    }
                    WorkspaceActionButton(
                        title: "Open command palette",
                        icon: "magnifyingglass",
                        tint: DS.accent
                    ) {
                        coordinator.showCommandPalette()
                    }
                case .creative:
                    WorkspaceActionButton(
                        title: "Open creator database",
                        icon: "person.3.sequence",
                        tint: accentColor,
                        prominent: true
                    ) {
                        coordinator.openCreatorDatabase()
                    }
                    if let post = coordinator.creativeProvider.data.recentPosts.first {
                        WorkspaceActionButton(
                            title: "Open latest draft in focus",
                            icon: "sparkles",
                            tint: DS.accent
                        ) {
                            coordinator.openAtomInFocusMode(uuid: post.id)
                        }
                    }
                case .knowledge:
                    WorkspaceActionButton(
                        title: "Jump to Thinkspace",
                        icon: "square.on.square.dashed",
                        tint: accentColor,
                        prominent: true
                    ) {
                        coordinator.navigateToThinkspace()
                    }
                    WorkspaceActionButton(
                        title: "Open command palette",
                        icon: "magnifyingglass",
                        tint: DS.accent
                    ) {
                        coordinator.showCommandPalette()
                    }
                case .behavioral:
                    WorkspaceActionButton(
                        title: "Quick-add a task",
                        icon: "plus.circle",
                        tint: accentColor,
                        prominent: true
                    ) {
                        coordinator.navigateToCommandCenter()
                        NotificationCenter.default.post(
                            name: Notification.Name("com.cosmo.commandCenter.quickAddTask"),
                            object: nil
                        )
                    }
                    WorkspaceActionButton(
                        title: "Jump to Thinkspace",
                        icon: "square.on.square.dashed",
                        tint: DS.accent
                    ) {
                        coordinator.navigateToThinkspace()
                    }
                case .physiological:
                    if coordinator.physiologicalProvider.isConnected {
                        WorkspaceActionButton(
                            title: "Refresh health signals",
                            icon: "heart.text.square",
                            tint: accentColor,
                            prominent: true
                        ) {
                            Task {
                                await coordinator.refresh(.physiological)
                            }
                        }
                    } else {
                        WorkspaceActionButton(
                            title: "Connect Apple Health",
                            icon: "heart.text.square",
                            tint: accentColor,
                            prominent: true
                        ) {
                            Task {
                                await coordinator.physiologicalProvider.connect()
                                await coordinator.refresh(.physiological)
                            }
                        }
                    }
                    WorkspaceActionButton(
                        title: "Open settings",
                        icon: "gearshape",
                        tint: DS.accent
                    ) {
                        coordinator.showSettings()
                    }
                case .reflection:
                    WorkspaceActionButton(
                        title: "New journal entry",
                        icon: "square.and.pencil",
                        tint: accentColor,
                        prominent: true
                    ) {
                        showJournalSheet = true
                    }
                    WorkspaceActionButton(
                        title: "Mood check-in",
                        icon: "face.smiling",
                        tint: DS.accent
                    ) {
                        showMoodCheckIn = true
                    }
                }
            }
        }
    }

    private var connectedSurfacesCard: some View {
        WorkspaceSurface {
            WorkspaceSectionHeader(title: "Connected surfaces", subtitle: "Routes back into the rest of the app shell.")
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceLinkLine(
                    icon: "hexagon",
                    title: "Command Center",
                    subtitle: "Tasks, plannerum, and dashboard state"
                )
                WorkspaceLinkLine(
                    icon: "rectangle.3.group",
                    title: "Thinkspaces",
                    subtitle: "Spatial canvases and active blocks"
                )
                WorkspaceLinkLine(
                    icon: "pencil.line",
                    title: "Unified Writing Engine",
                    subtitle: dimension == .creative ? "Primary handoff surface" : "Available when a content atom is linked"
                )
            }
        }
    }

    private var qualityCard: some View {
        WorkspaceSurface {
            WorkspaceSectionHeader(title: "Signal quality", subtitle: "How trustworthy and current this workspace is.")
            VStack(spacing: 10) {
                WorkspaceBarRow(
                    label: "Confidence",
                    valueLabel: "\(Int(currentIndex.confidence * 100))%",
                    progress: currentIndex.confidence,
                    tint: accentColor
                )
                WorkspaceBarRow(
                    label: "Index",
                    valueLabel: "\(Int(currentIndex.score.rounded()))",
                    progress: currentIndex.score / 100,
                    tint: DS.accent
                )
                Text(coordinator.freshnessLabel(for: dimension))
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)
            }
        }
    }

    // MARK: - Reflection Overlay

    @ViewBuilder
    private var reflectionOverlay: some View {
        if dimension == .reflection && showMoodCheckIn {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showMoodCheckIn = false
                    }

                MoodCheckInView(isPresented: $showMoodCheckIn) { valence, energy, note in
                    Task {
                        await coordinator.reflectionProvider.recordMood(valence: valence, energy: energy, note: note)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }

        if dimension == .reflection && showJournalSheet {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showJournalSheet = false
                    }

                JournalEntrySheet(isPresented: $showJournalSheet) { text, prompt in
                    Task {
                        await coordinator.reflectionProvider.createJournalEntry(text: text, prompt: prompt)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Utilities

    private func matchesSearch(_ values: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return values.joined(separator: " ").localizedCaseInsensitiveContains(query)
    }

    private func copyDeepLink() {
        let link = "cosmo://dimensions/\(dimension.rawValue)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copiedDeepLink = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            copiedDeepLink = false
        }
    }

    private func profileChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.buttonText)
                .foregroundColor(isSelected ? accentColor : DS.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? accentColor.opacity(0.12) : DS.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? accentColor.opacity(0.22) : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func emptyState(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        WorkspaceSurface {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(DS.cardTitle)
                    .foregroundColor(DS.text)

                Text(message)
                    .font(DS.body)
                    .foregroundColor(DS.textSecondary)

                WorkspaceActionButton(
                    title: buttonTitle,
                    icon: "arrow.right",
                    tint: accentColor,
                    prominent: true,
                    action: action
                )
            }
        }
    }

    private func mutedLine(_ text: String) -> some View {
        Text(text)
            .font(DS.sectionDesc)
            .foregroundColor(DS.textSecondary)
    }

    private func secondaryLine(_ text: String) -> some View {
        Text(text)
            .font(DS.cardMeta)
            .foregroundColor(DS.textSecondary)
    }

    private func tagCloud(_ tags: [String], compact: Bool = false) -> some View {
        let visibleTags = Array(tags.prefix(compact ? 3 : 10))

        return FlexibleTagCloud(tags: visibleTags, tint: accentColor)
    }

    private func routineCard(_ routine: RoutineTracker, tint: Color) -> some View {
        WorkspaceSurface(innerPadding: 14, shadowed: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text(routine.name)
                    .font(DS.cardTitle)
                    .foregroundColor(DS.text)
                WorkspaceBarRow(
                    label: "Consistency",
                    valueLabel: "\(Int(routine.consistency.rounded()))%",
                    progress: routine.consistency / 100,
                    tint: tint
                )
                Text("Target \(routine.formattedTarget) • Avg \(routine.formattedAverage)")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)
            }
        }
    }

    private static func modes(for dimension: LevelDimension) -> [DimensionWorkspaceMode] {
        switch dimension {
        case .cognitive:
            return [
                .init(id: "today", title: "Today", icon: "sun.max"),
                .init(id: "trends", title: "Trends", icon: "chart.line.uptrend.xyaxis"),
                .init(id: "insights", title: "Insights", icon: "sparkles")
            ]
        case .creative:
            return [
                .init(id: "today", title: "Today", icon: "wand.and.stars"),
                .init(id: "pipeline", title: "Pipeline", icon: "point.3.connected.trianglepath.dotted"),
                .init(id: "insights", title: "Insights", icon: "chart.bar.doc.horizontal")
            ]
        case .physiological:
            return [
                .init(id: "today", title: "Today", icon: "heart"),
                .init(id: "recovery", title: "Recovery", icon: "bed.double"),
                .init(id: "insights", title: "Insights", icon: "waveform.path.ecg")
            ]
        case .behavioral:
            return [
                .init(id: "today", title: "Today", icon: "checklist"),
                .init(id: "routines", title: "Routines", icon: "repeat"),
                .init(id: "forecast", title: "Forecast", icon: "calendar.badge.clock")
            ]
        case .knowledge:
            return [
                .init(id: "today", title: "Today", icon: "books.vertical"),
                .init(id: "map", title: "Map", icon: "point.3.connected.trianglepath.dotted"),
                .init(id: "insights", title: "Insights", icon: "sparkles")
            ]
        case .reflection:
            return [
                .init(id: "today", title: "Today", icon: "person"),
                .init(id: "themes", title: "Themes", icon: "quote.bubble"),
                .init(id: "insights", title: "Insights", icon: "brain")
            ]
        }
    }
}

// MARK: - Shared Components

private struct WorkspaceSurface<Content: View>: View {
    let innerPadding: CGFloat
    let shadowed: Bool
    let content: Content

    init(
        innerPadding: CGFloat = DS.cardPadding,
        shadowed: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.innerPadding = innerPadding
        self.shadowed = shadowed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .modifier(WorkspaceShadowModifier(enabled: shadowed))
    }
}

private struct WorkspaceShadowModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dsRestingShadow()
        } else {
            content
        }
    }
}

private struct WorkspaceSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.cardTitle)
                .foregroundColor(DS.text)

            Text(subtitle)
                .font(DS.sectionDesc)
                .foregroundColor(DS.textSecondary)
        }
    }
}

private struct WorkspaceHeroMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

private struct WorkspaceMetricTile: View {
    let metric: WorkspaceHeroMetric
    let accentColor: Color

    var body: some View {
        WorkspaceSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text(metric.title)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)

                Text(metric.value)
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Text(metric.detail)
                    .font(DS.cardMeta)
                    .foregroundColor(accentColor)
                    .lineLimit(2)
            }
        }
    }
}

private struct WorkspaceBadge: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(DS.cardMeta)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct WorkspaceActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(DS.buttonText)
            }
            .foregroundColor(prominent ? DS.textOnAccent : tint)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(prominent ? tint : tint.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(prominent ? tint : tint.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceBarRow: View {
    let label: String
    let valueLabel: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Text(valueLabel)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.text)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.borderSubtle)
                        .frame(height: 6)

                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct WorkspaceActionStrip: View {
    let primaryTitle: String
    let primaryIcon: String
    let primaryTint: Color
    let action: () -> Void

    var body: some View {
        WorkspaceActionButton(
            title: primaryTitle,
            icon: primaryIcon,
            tint: primaryTint,
            prominent: true,
            action: action
        )
    }
}

private struct WorkspaceListRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        accentColor: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accentColor = accentColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accentColor)
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.body)
                    .foregroundColor(DS.text)
                    .lineLimit(2)

                Text(subtitle)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            trailing
        }
    }
}

private struct WorkspaceLinkLine: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.cardMeta)
                    .foregroundColor(DS.text)
                Text(subtitle)
                    .font(DS.timestamp)
                    .foregroundColor(DS.textSecondary)
            }
        }
    }
}

private struct FlexibleTagCloud: View {
    let tags: [String]
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(DS.cardMeta)
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.10))
                    )
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.14), lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Preferences

private enum DimensionWorkspacePreferences {
    static func selectedMode(for dimension: LevelDimension, fallback: String) -> String {
        UserDefaults.standard.string(forKey: selectedModeKey(for: dimension)) ?? fallback
    }

    static func setSelectedMode(_ mode: String, for dimension: LevelDimension) {
        UserDefaults.standard.set(mode, forKey: selectedModeKey(for: dimension))
    }

    static func isPinned(_ dimension: LevelDimension) -> Bool {
        pinnedDimensions.contains(dimension.rawValue)
    }

    static func setPinned(_ pinned: Bool, for dimension: LevelDimension) {
        var updated = pinnedDimensions
        if pinned {
            updated.insert(dimension.rawValue)
        } else {
            updated.remove(dimension.rawValue)
        }
        UserDefaults.standard.set(Array(updated), forKey: pinnedKey)
    }

    private static let pinnedKey = "com.cosmo.dimensionWorkspace.pinned"

    private static var pinnedDimensions: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
    }

    private static func selectedModeKey(for dimension: LevelDimension) -> String {
        "com.cosmo.dimensionWorkspace.mode.\(dimension.rawValue)"
    }
}
