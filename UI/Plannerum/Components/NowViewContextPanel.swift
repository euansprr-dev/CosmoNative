//
//  NowViewContextPanel.swift
//  CosmoOS
//
//  Context panel for the Now view — shows intent-specific context cards
//  below the active session card when a task has linked ideas/content/swipes.
//

import SwiftUI
import Foundation

// MARK: - NowViewContextPanel

/// Shows intent-aware context cards below the active session hero.
/// Only visible when a session is active AND the current task has linked context.
struct NowViewContextPanel: View {

    let session: ActiveSession?
    let taskViewModel: TaskViewModel?
    @StateObject private var viewModel = NowViewContextViewModel()

    /// Init for active session context
    init(session: ActiveSession) {
        self.session = session
        self.taskViewModel = nil
    }

    /// Init for pre-session recommended task context
    init(task: TaskViewModel) {
        self.session = nil
        self.taskViewModel = task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingMD) {
            // Section header
            contextSectionHeader

            // Intent-specific cards
            contextCards
        }
        .onAppear {
            loadContextData()
        }
        .onChange(of: session?.id) {
            loadContextData()
        }
        .onChange(of: taskViewModel?.id) {
            loadContextData()
        }
    }

    private func loadContextData() {
        if let session = session {
            Task { await viewModel.loadContext(for: session) }
        } else if let task = taskViewModel {
            Task { await viewModel.loadContext(from: task) }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private var contextSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(intentAccentColor)
            Text("Context for This Session")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(2)
            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Intent-Specific Cards

    @ViewBuilder
    private var contextCards: some View {
        let intent = viewModel.taskIntent

        switch intent {
        case .writeContent:
            writeContentCards
        case .research:
            researchCards
        case .studySwipes:
            swipeStudyCards
        default:
            EmptyView()
        }
    }

    // MARK: - Write Content Cards

    @ViewBuilder
    private var writeContentCards: some View {
        VStack(spacing: PlannerumLayout.spacingSM) {
            // Card 1: Source Idea
            if let idea = viewModel.linkedIdea {
                sourceIdeaCard(idea)
            }

            // Card 2: Content Progress
            if let content = viewModel.linkedContent {
                contentProgressCard(content)
            }

            // Card 3: Matched Swipes
            if !viewModel.matchedSwipes.isEmpty {
                matchedSwipesCard
            }

            // Card 4: Hook Variants
            if !viewModel.hookSuggestions.isEmpty {
                hookVariantsCard
            }
        }
    }

    // MARK: - Research Cards

    @ViewBuilder
    private var researchCards: some View {
        VStack(spacing: PlannerumLayout.spacingSM) {
            if let linkedAtom = viewModel.linkedResearchAtom {
                researchTopicCard(linkedAtom)
            }

            if !viewModel.recentCaptures.isEmpty {
                recentCapturesCard
            }
        }
    }

    // MARK: - Swipe Study Cards

    @ViewBuilder
    private var swipeStudyCards: some View {
        swipeGalleryShortcutCard
    }

    // MARK: - Source Idea Card

    @ViewBuilder
    private func sourceIdeaCard(_ idea: Atom) -> some View {
        let insight = idea.ideaInsight
        let hasContent = viewModel.linkedContent != nil

        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Title row
            HStack(spacing: 8) {
                contextCardIcon(systemName: "lightbulb.fill", color: TaskIntent.writeContent.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.title ?? "Untitled Idea")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)

                    sourceIdeaMetadataRow(insight: insight)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 8) {
                contextActionButton(
                    label: "Open Idea",
                    icon: "arrow.up.right",
                    color: TaskIntent.writeContent.color
                ) {
                    navigateToIdea(uuid: idea.uuid)
                }

                if hasContent {
                    contextActionButton(
                        label: "Resume",
                        icon: "pencil.line",
                        color: Color(red: 74/255, green: 222/255, blue: 128/255)
                    ) {
                        if let contentUUID = viewModel.linkedContent?.uuid {
                            navigateToContent(uuid: contentUUID)
                        }
                    }
                } else {
                    contextActionButton(
                        label: "Activate",
                        icon: "bolt.fill",
                        color: Color(red: 245/255, green: 158/255, blue: 11/255)
                    ) {
                        navigateToIdeaActivation(uuid: idea.uuid)
                    }
                }
            }
        }
        .contextCardStyle()
    }

    @ViewBuilder
    private func sourceIdeaMetadataRow(insight: IdeaInsight?) -> some View {
        HStack(spacing: 8) {
            if let framework = insight?.frameworkRecommendations?.first {
                Text(framework.framework.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TaskIntent.writeContent.color.opacity(0.8))
            }

            if let format = insight?.recommendedFormat {
                Text(format.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textTertiary)
            }
        }
    }

    // MARK: - Content Progress Card

    @ViewBuilder
    private func contentProgressCard(_ content: Atom) -> some View {
        let metadata = content.metadataValue(as: ContentAtomMetadata.self)
        let currentPhase = metadata?.phase ?? .ideation

        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Title
            HStack(spacing: 8) {
                contextCardIcon(systemName: "doc.text.fill", color: contentPhaseColor(currentPhase))

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title ?? "Content Draft")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)

                    Text("Currently in: \(currentPhase.displayName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()
            }

            // 8-phase progress bar
            contentPhaseProgressBar(currentPhase: currentPhase)

            // Open button
            contextActionButton(
                label: "Open Content Editor",
                icon: "pencil.line",
                color: contentPhaseColor(currentPhase)
            ) {
                navigateToContent(uuid: content.uuid)
            }
        }
        .contextCardStyle()
    }

    @ViewBuilder
    private func contentPhaseProgressBar(currentPhase: ContentPhase) -> some View {
        let phases = ContentPhase.allCases
        let currentIndex = phases.firstIndex(of: currentPhase) ?? 0

        HStack(spacing: 3) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                contentPhaseSegment(
                    phase: phase,
                    isCompleted: index < currentIndex,
                    isCurrent: index == currentIndex
                )
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func contentPhaseSegment(phase: ContentPhase, isCompleted: Bool, isCurrent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                isCompleted
                    ? Color(red: 74/255, green: 222/255, blue: 128/255)
                    : isCurrent
                        ? contentPhaseColor(phase)
                        : Color.white.opacity(0.08)
            )
            .frame(maxWidth: .infinity)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(contentPhaseColor(phase).opacity(0.3))
                }
            }
    }

    // MARK: - Matched Swipes Card

    @ViewBuilder
    private var matchedSwipesCard: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TaskIntent.studySwipes.color)
                Text("Matched Swipes")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(1.5)
                Spacer()
            }

            HStack(spacing: PlannerumLayout.spacingSM) {
                ForEach(viewModel.matchedSwipes.prefix(3)) { swipe in
                    matchedSwipeChip(swipe)
                }
            }
        }
        .contextCardStyle()
    }

    @ViewBuilder
    private func matchedSwipeChip(_ swipe: SwipeMatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(swipe.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let hookType = swipe.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(TaskIntent.studySwipes.color.opacity(0.8))
                }

                Text("\(Int(swipe.similarityScore * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onTapGesture {
            navigateToSwipe(uuid: swipe.swipeAtomUUID)
        }
    }

    // MARK: - Hook Variants Card

    @ViewBuilder
    private var hookVariantsCard: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TaskIntent.writeContent.color)
                Text("Hook Variants")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(1.5)
                Spacer()
            }

            ForEach(Array(viewModel.hookSuggestions.prefix(3).enumerated()), id: \.offset) { index, hook in
                hookVariantRow(index: index, hook: hook)
            }
        }
        .contextCardStyle()
    }

    @ViewBuilder
    private func hookVariantRow(index: Int, hook: HookSuggestion) -> some View {
        let isFirst = index == 0

        HStack(spacing: 8) {
            // Number badge
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isFirst ? TaskIntent.writeContent.color : PlannerumColors.textTertiary)
                .frame(width: 20, height: 20)
                .background(
                    (isFirst ? TaskIntent.writeContent.color : Color.white).opacity(isFirst ? 0.15 : 0.05)
                )
                .clipShape(Circle())

            // Hook text
            Text(hook.hookText)
                .font(.system(size: 12, weight: .regular))
                .italic()
                .foregroundColor(isFirst ? PlannerumColors.textPrimary : PlannerumColors.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 4)

            // Copy button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hook.hookText, forType: .string)
            }) {
                hookCopyButtonLabel
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, isFirst ? 6 : 0)
        .background(isFirst ? TaskIntent.writeContent.color.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var hookCopyButtonLabel: some View {
        Image(systemName: "doc.on.doc")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(PlannerumColors.textMuted)
            .frame(width: 24, height: 24)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Research Topic Card

    @ViewBuilder
    private func researchTopicCard(_ atom: Atom) -> some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 8) {
                contextCardIcon(systemName: "magnifyingglass", color: TaskIntent.research.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Research Topic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)

                    Text("Linked research source")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()
            }

            contextActionButton(
                label: "Open Research",
                icon: "arrow.up.right",
                color: TaskIntent.research.color
            ) {
                navigateToAtom(uuid: atom.uuid)
            }
        }
        .contextCardStyle()
    }

    // MARK: - Recent Captures Card

    @ViewBuilder
    private var recentCapturesCard: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TaskIntent.research.color)
                Text("Recent Captures")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(1.5)
                Spacer()
            }

            ForEach(viewModel.recentCaptures.prefix(3), id: \.uuid) { atom in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(TaskIntent.research.color.opacity(0.7))
                    Text(atom.title ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PlannerumColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .contextCardStyle()
    }

    // MARK: - Swipe Gallery Shortcut Card

    @ViewBuilder
    private var swipeGalleryShortcutCard: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 8) {
                contextCardIcon(systemName: "bolt.fill", color: TaskIntent.studySwipes.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Swipe Gallery")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)

                    Text("Browse and study swipe files")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PlannerumColors.textTertiary)
                }

                Spacer()
            }

            contextActionButton(
                label: "Open Gallery",
                icon: "arrow.up.right",
                color: TaskIntent.studySwipes.color
            ) {
                NotificationCenter.default.post(
                    name: .navigateToSwipeGallery,
                    object: nil
                )
            }
        }
        .contextCardStyle()
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func contextCardIcon(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private func contextActionButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            contextActionButtonLabel(label: label, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contextActionButtonLabel(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Navigation

    private func navigateToIdea(uuid: String) {
        NotificationCenter.default.post(
            name: .navigateToContentWorkflow,
            object: nil,
            userInfo: ["linkedIdeaUUID": uuid, "route": "ideaDetail"]
        )
    }

    private func navigateToIdeaActivation(uuid: String) {
        NotificationCenter.default.post(
            name: .navigateToContentWorkflow,
            object: nil,
            userInfo: ["linkedIdeaUUID": uuid, "route": "ideaDetail"]
        )
    }

    private func navigateToContent(uuid: String) {
        NotificationCenter.default.post(
            name: .navigateToContentWorkflow,
            object: nil,
            userInfo: ["linkedContentUUID": uuid, "route": "contentFocusMode"]
        )
    }

    private func navigateToSwipe(uuid: String) {
        NotificationCenter.default.post(
            name: .navigateToAtom,
            object: nil,
            userInfo: ["linkedAtomUUID": uuid]
        )
    }

    private func navigateToAtom(uuid: String) {
        NotificationCenter.default.post(
            name: .navigateToAtom,
            object: nil,
            userInfo: ["linkedAtomUUID": uuid]
        )
    }

    // MARK: - Helpers

    private var intentAccentColor: Color {
        viewModel.taskIntent.color
    }

    private func contentPhaseColor(_ phase: ContentPhase) -> Color {
        switch phase {
        case .ideation: return Color(red: 129/255, green: 140/255, blue: 248/255)
        case .draft: return Color(red: 56/255, green: 189/255, blue: 248/255)
        case .polish: return Color(red: 168/255, green: 85/255, blue: 247/255)
        case .scheduled: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .published: return Color(red: 74/255, green: 222/255, blue: 128/255)
        case .analyzing: return Color(red: 236/255, green: 72/255, blue: 153/255)
        case .archived: return Color(red: 148/255, green: 163/255, blue: 184/255)
        }
    }
}

// MARK: - Context Card Style Modifier

private struct ContextCardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PlannerumLayout.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func contextCardStyle() -> some View {
        modifier(ContextCardStyleModifier())
    }
}

// MARK: - NowViewContextViewModel

/// Loads context data (linked idea, content, swipes, hooks) for the active session's task.
@MainActor
final class NowViewContextViewModel: ObservableObject {

    @Published var taskIntent: TaskIntent = .general
    @Published var linkedIdea: Atom?
    @Published var linkedContent: Atom?
    @Published var matchedSwipes: [SwipeMatch] = []
    @Published var hookSuggestions: [HookSuggestion] = []
    @Published var linkedResearchAtom: Atom?
    @Published var recentCaptures: [Atom] = []
    @Published var isLoading = false

    private let atomRepository = AtomRepository.shared

    /// Load all context based on the active session's task metadata
    func loadContext(for session: ActiveSession) async {
        isLoading = true
        defer { isLoading = false }

        // Load the task atom to read its metadata
        guard let taskId = session.taskId,
              let taskAtom = try? await atomRepository.fetch(uuid: taskId) else {
            return
        }

        let metadata = taskAtom.metadataValue(as: TaskMetadata.self)
        let intent = metadata?.intent.flatMap { TaskIntent(rawValue: $0) } ?? .general
        taskIntent = intent

        switch intent {
        case .writeContent:
            await loadWriteContentContext(metadata: metadata)
        case .research:
            await loadResearchContext(metadata: metadata)
        case .studySwipes:
            break
        default:
            break
        }
    }

    /// Load context directly from a TaskViewModel (for pre-session recommendation display)
    func loadContext(from task: TaskViewModel) async {
        isLoading = true
        defer { isLoading = false }

        taskIntent = task.intent

        // Build lightweight metadata from TaskViewModel fields
        var syntheticMetadata = TaskMetadata()
        syntheticMetadata.intent = task.intent.rawValue
        syntheticMetadata.linkedIdeaUUID = task.linkedIdeaUUID
        syntheticMetadata.linkedContentUUID = task.linkedContentUUID
        syntheticMetadata.linkedAtomUUID = task.linkedAtomUUID

        switch task.intent {
        case .writeContent:
            await loadWriteContentContext(metadata: syntheticMetadata)
        case .research:
            await loadResearchContext(metadata: syntheticMetadata)
        case .studySwipes:
            break
        default:
            break
        }
    }

    // MARK: - Write Content Context

    private func loadWriteContentContext(metadata: TaskMetadata?) async {
        // Load linked idea
        if let ideaUUID = metadata?.linkedIdeaUUID {
            linkedIdea = try? await atomRepository.fetch(uuid: ideaUUID)

            // Load insight data (swipes + hooks) from the idea's structured JSON
            if let idea = linkedIdea, let insight = idea.ideaInsight {
                matchedSwipes = insight.matchingSwipes ?? []
                hookSuggestions = insight.hookSuggestions ?? []
            }
        }

        // Load linked content
        if let contentUUID = metadata?.linkedContentUUID {
            linkedContent = try? await atomRepository.fetch(uuid: contentUUID)
        }

        // If idea exists but no insight, try quick analysis
        if let idea = linkedIdea, idea.ideaInsight == nil {
            let ideaText = idea.body ?? idea.title ?? ""
            if !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let swipes = await IdeaInsightEngine.shared.findMatchingSwipes(ideaText: ideaText, limit: 3)
                matchedSwipes = swipes
            }
        }
    }

    // MARK: - Research Context

    private func loadResearchContext(metadata: TaskMetadata?) async {
        if let atomUUID = metadata?.linkedAtomUUID {
            linkedResearchAtom = try? await atomRepository.fetch(uuid: atomUUID)
        }

        // Load recent research captures (last 3 research atoms)
        do {
            let allResearch = try await atomRepository.fetchAll(type: .research)
            recentCaptures = Array(
                allResearch
                    .filter { !$0.isDeleted }
                    .sorted { $0.createdAt > $1.createdAt }
                    .prefix(3)
            )
        } catch {
            recentCaptures = []
        }
    }
}
