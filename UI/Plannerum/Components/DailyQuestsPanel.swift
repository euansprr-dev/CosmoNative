//
//  DailyQuestsPanel.swift
//  CosmoOS
//
//  Panel displaying daily quests with progress bars, XP rewards,
//  streak indicators, and completion animations. Wired to QuestEngine
//  for real data-driven progress.
//

import SwiftUI

// MARK: - DailyQuestsPanel

/// Panel showing today's quests with progress tracking.
/// Accepts either a QuestEngine (preferred) or legacy DailyQuests.
public struct DailyQuestsPanel: View {

    // MARK: - Properties

    /// QuestEngine for real data-driven quests (preferred)
    @ObservedObject var questEngine: QuestEngine

    /// Fallback legacy quests (used when QuestEngine is not wired)
    let dailyQuests: DailyQuests?
    let currentStreak: Int
    let onQuestTap: (String) -> Void

    @State private var isExpanded = true

    /// Convenience init with QuestEngine
    init(
        questEngine: QuestEngine,
        currentStreak: Int = 0,
        onQuestTap: @escaping (String) -> Void = { _ in }
    ) {
        self.questEngine = questEngine
        self.dailyQuests = nil
        self.currentStreak = currentStreak
        self.onQuestTap = onQuestTap
    }

    /// Legacy init for backwards compatibility
    init(
        dailyQuests: DailyQuests?,
        currentStreak: Int,
        onQuestTap: @escaping (Quest) -> Void
    ) {
        self.questEngine = QuestEngine()
        self.dailyQuests = dailyQuests
        self.currentStreak = currentStreak
        self.onQuestTap = { _ in }
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            if isExpanded {
                if !questEngine.quests.isEmpty {
                    liveQuestsList
                } else if let quests = dailyQuests {
                    legacyQuestsList(quests)
                } else {
                    loadingState
                }
            }
        }
        .background(DailyQuestsTokens.background)
        .clipShape(RoundedRectangle(cornerRadius: DailyQuestsTokens.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DailyQuestsTokens.cornerRadius, style: .continuous)
                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var panelHeader: some View {
        Button(action: { withAnimation(PlannerumSprings.expand) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.primary)

                Text("Daily Quests")
                    .font(DailyQuestsTokens.headerFont)
                    .tracking(PlannerumTypography.trackingWide)
                    .foregroundColor(PlannerumColors.textSecondary)

                Spacer()

                // Streak badge (max across all quests or provided streak)
                let maxStreak = questEngine.streaks.values.max() ?? currentStreak
                if maxStreak > 0 {
                    streakBadge(maxStreak)
                }

                // Progress summary
                progressBadge

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PlannerumColors.textMuted)
            }
            .padding(DailyQuestsTokens.padding)
        }
        .buttonStyle(.plain)
    }

    private func streakBadge(_ streak: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("\(streak)")
                .font(DailyQuestsTokens.streakFont)
        }
        .foregroundColor(DailyQuestsTokens.streakFire)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DailyQuestsTokens.streakFire.opacity(0.15))
        .clipShape(Capsule())
    }

    private var progressBadge: some View {
        let completed = questEngine.quests.isEmpty
            ? (dailyQuests?.completedQuestCount ?? 0)
            : questEngine.completedCount
        let total = questEngine.quests.isEmpty
            ? (dailyQuests?.totalQuestCount ?? 0)
            : questEngine.totalCount
        let allDone = questEngine.quests.isEmpty
            ? (dailyQuests?.allQuestsComplete ?? false)
            : questEngine.allComplete

        return Text("\(completed)/\(total)")
            .font(DailyQuestsTokens.progressFont)
            .foregroundColor(allDone ? DailyQuestsTokens.completeCheck : PlannerumColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
    }

    // MARK: - Live Quests (QuestEngine-driven)

    private var liveQuestsList: some View {
        VStack(spacing: DailyQuestsTokens.rowSpacing) {
            ForEach(questEngine.quests) { quest in
                LiveQuestRow(
                    quest: quest,
                    questEngine: questEngine,
                    onTap: { onQuestTap(quest.id) }
                )
            }
        }
        .padding(.horizontal, DailyQuestsTokens.padding)
        .padding(.bottom, DailyQuestsTokens.padding)
    }

    // MARK: - Legacy Quests (DailyQuests-driven)

    private func legacyQuestsList(_ quests: DailyQuests) -> some View {
        VStack(spacing: DailyQuestsTokens.rowSpacing) {
            QuestRow(
                quest: quests.mainQuest,
                questType: .main,
                onTap: { }
            )

            ForEach(quests.sideQuests) { quest in
                QuestRow(
                    quest: quest,
                    questType: .side,
                    onTap: { }
                )
            }

            if let bonus = quests.bonusQuest {
                QuestRow(
                    quest: bonus,
                    questType: .bonus,
                    isLocked: !quests.allQuestsComplete,
                    onTap: { }
                )
            }
        }
        .padding(.horizontal, DailyQuestsTokens.padding)
        .padding(.bottom, DailyQuestsTokens.padding)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: DailyQuestsTokens.questRowHeight)
            }
        }
        .padding(.horizontal, DailyQuestsTokens.padding)
        .padding(.bottom, DailyQuestsTokens.padding)
    }
}

// MARK: - LiveQuestRow

/// Quest row driven by QuestState from QuestEngine.
/// Shows custom icon, accent color, streak badge, hover popover, context menu, and completion glow.
struct LiveQuestRow: View {

    let quest: QuestState
    @ObservedObject var questEngine: QuestEngine
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var showHoverPopover = false
    @State private var animatedProgress: Double = 0
    @State private var showCompletionGlow = false
    @State private var showEditPopover = false
    @State private var showDeleteAlert = false
    @State private var editTitle: String = ""
    @State private var editXP: Int = 0

    var body: some View {
        Button(action: onTap) {
            questRowContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                // Show popover after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovering { showHoverPopover = true }
                }
            } else {
                showHoverPopover = false
            }
        }
        .popover(isPresented: $showHoverPopover, arrowEdge: .trailing) {
            questHoverPopover
        }
        .contextMenu {
            questContextMenuItems
        }
        .popover(isPresented: $showEditPopover) {
            questEditPopover
        }
        .alert("Delete Quest", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                questEngine.deleteQuest(questId: quest.id)
            }
        } message: {
            Text("Remove \"\(quest.title)\" from your daily quests?")
        }
        .onAppear {
            withAnimation(DailyQuestsTokens.progressAnimation.delay(0.2)) {
                animatedProgress = quest.progress
            }
        }
        .onChange(of: quest.progress) { _, newValue in
            withAnimation(DailyQuestsTokens.progressAnimation) {
                animatedProgress = newValue
            }
        }
        .onChange(of: quest.isComplete) { wasComplete, isNowComplete in
            if isNowComplete && !wasComplete {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showCompletionGlow = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        showCompletionGlow = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var questRowContent: some View {
        HStack(spacing: 12) {
            questIcon

            VStack(alignment: .leading, spacing: 4) {
                titleRow
                progressBar
            }

            // Manual complete button
            if quest.allowManualComplete && !quest.isComplete {
                manualCompleteButton
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .overlay(completionGlowOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Manual Complete Button

    private var manualCompleteButton: some View {
        Button(action: {
            Task { await questEngine.manualComplete(questId: quest.id) }
        }) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)
        }
        .buttonStyle(.plain)
        .help("Mark as complete")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var questContextMenuItems: some View {
        Button {
            editTitle = quest.title
            editXP = quest.xpReward
            showEditPopover = true
        } label: {
            Label("Edit Quest", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Quest", systemImage: "trash")
        }
    }

    // MARK: - Edit Popover

    private var questEditPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Quest")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PlannerumColors.textPrimary)

            TextField("Quest title", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("XP Reward")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textSecondary)
                Spacer()
                Stepper("\(editXP) XP", value: $editXP, in: 5...500, step: 5)
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textPrimary)
            }

            // Criteria (read-only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Criteria")
                    .font(OnyxTypography.label)
                    .foregroundColor(OnyxColors.Text.muted)
                    .tracking(OnyxTypography.labelTracking)
                Text(quest.description)
                    .font(.system(size: 11))
                    .foregroundColor(PlannerumColors.textTertiary)
            }

            HStack {
                Button("Cancel") { showEditPopover = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)

                Spacer()

                Button("Save") {
                    questEngine.updateQuest(questId: quest.id, title: editTitle, xpReward: editXP)
                    showEditPopover = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PlannerumColors.primary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(PlannerumColors.glassPrimary)
    }

    // MARK: - Hover Popover

    private var questHoverPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + icon
            HStack(spacing: 8) {
                Image(systemName: quest.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(quest.accentColor)
                Text(quest.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)
            }

            // Description
            Text(quest.description)
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textSecondary)

            Divider().opacity(0.2)

            // Criteria
            VStack(alignment: .leading, spacing: 4) {
                Text("Completion Criteria")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(PlannerumColors.textMuted)
                    .tracking(1)
                Text(questCriteriaDescription)
                    .font(.system(size: 11))
                    .foregroundColor(PlannerumColors.textTertiary)
            }

            // Progress
            HStack {
                Text("Progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PlannerumColors.textSecondary)
                Spacer()
                Text(questProgressDescription)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(quest.isComplete ? DailyQuestsTokens.completeCheck : quest.accentColor)
            }

            // Streak
            if quest.streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DailyQuestsTokens.streakFire)
                    Text("\(quest.streak) day streak")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DailyQuestsTokens.streakFire)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(PlannerumColors.glassPrimary)
    }

    private var questCriteriaDescription: String {
        switch quest.requirement {
        case .deepWorkMinutes(let target):
            return "Complete a \(target)+ minute session with 70%+ focus score"
        case .journalEntry:
            return "Write a journal entry with 50+ words"
        case .tasksCompleted(let target):
            return "Complete \(target) tasks today"
        case .wordsWritten(let target):
            return "Advance \(target) content piece(s) to the next phase"
        case .workoutCompleted:
            return "Log any exercise or physical activity"
        case .streakMaintained:
            return "Complete all other daily quests"
        default:
            return quest.description
        }
    }

    private var questProgressDescription: String {
        if quest.isComplete { return "Complete" }
        let pct = Int(quest.progress * 100)
        return "\(pct)%"
    }

    // MARK: - Icon

    private var questIcon: some View {
        ZStack {
            Circle()
                .fill(quest.isComplete
                    ? DailyQuestsTokens.completeCheck.opacity(0.2)
                    : quest.accentColor.opacity(0.15))
                .frame(width: DailyQuestsTokens.iconSize, height: DailyQuestsTokens.iconSize)

            if quest.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DailyQuestsTokens.completeCheck)
            } else {
                Image(systemName: quest.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(quest.accentColor)
            }
        }
    }

    // MARK: - Title Row

    @ViewBuilder
    private var titleRow: some View {
        HStack {
            Text(quest.title)
                .font(DailyQuestsTokens.questTitleFont)
                .foregroundColor(quest.isComplete ? PlannerumColors.textTertiary : PlannerumColors.textPrimary)
                .strikethrough(quest.isComplete)
                .lineLimit(1)

            // Streak badge next to title
            if quest.streak > 1 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                    Text("\(quest.streak)")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(DailyQuestsTokens.streakFire)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DailyQuestsTokens.streakFire.opacity(0.12))
                .clipShape(Capsule())
            }

            Spacer()

            xpRewardLabel
        }
    }

    private var xpRewardLabel: some View {
        HStack(spacing: 2) {
            Text("+\(quest.xpReward)")
                .font(DailyQuestsTokens.xpFont)
            Image(systemName: "sparkles")
                .font(.system(size: 9))
        }
        .foregroundColor(quest.isComplete ? OnyxColors.Text.muted : OnyxColors.Accent.amber)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DailyQuestsTokens.progressBarRadius)
                    .fill(DailyQuestsTokens.progressBackground)
                    .frame(height: DailyQuestsTokens.progressBarHeight)

                RoundedRectangle(cornerRadius: DailyQuestsTokens.progressBarRadius)
                    .fill(
                        LinearGradient(
                            colors: [quest.accentColor, quest.accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(0, geometry.size.width * animatedProgress),
                        height: DailyQuestsTokens.progressBarHeight
                    )
                    .shadow(color: quest.accentColor.opacity(0.5), radius: animatedProgress > 0 ? 4 : 0)
            }
        }
        .frame(height: DailyQuestsTokens.progressBarHeight)
    }

    // MARK: - Completion Glow

    @ViewBuilder
    private var completionGlowOverlay: some View {
        if showCompletionGlow {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    DailyQuestsTokens.completeCheck.opacity(0.6),
                    lineWidth: 2
                )
                .shadow(color: DailyQuestsTokens.completeCheck.opacity(0.4), radius: 8)
        }
    }
}

// MARK: - QuestRow (Legacy)

/// Individual quest row with progress bar — legacy version using Quest model
struct QuestRow: View {

    let quest: Quest
    let questType: QuestType
    var isLocked: Bool = false
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var animatedProgress: Double = 0

    enum QuestType {
        case main
        case side
        case bonus

        var progressColor: Color {
            switch self {
            case .main: return DailyQuestsTokens.mainQuestProgress
            case .side: return DailyQuestsTokens.sideQuestProgress
            case .bonus: return DailyQuestsTokens.bonusQuestProgress
            }
        }

        var icon: String {
            switch self {
            case .main: return "star.fill"
            case .side: return "circle.fill"
            case .bonus: return "sparkles"
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                questIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(quest.title)
                            .font(DailyQuestsTokens.questTitleFont)
                            .foregroundColor(quest.isComplete ? PlannerumColors.textTertiary : PlannerumColors.textPrimary)
                            .strikethrough(quest.isComplete)
                            .lineLimit(1)

                        Spacer()

                        xpReward
                    }

                    progressBar
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isHovering ? Color.white.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isLocked ? 0.5 : 1.0)
            .overlay(lockedOverlay)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .onHover { isHovering = $0 }
        .onAppear {
            withAnimation(DailyQuestsTokens.progressAnimation.delay(0.2)) {
                animatedProgress = quest.progress
            }
        }
        .onChange(of: quest.progress) { _, newValue in
            withAnimation(DailyQuestsTokens.progressAnimation) {
                animatedProgress = newValue
            }
        }
    }

    private var questIcon: some View {
        ZStack {
            Circle()
                .fill(quest.isComplete ? DailyQuestsTokens.completeCheck.opacity(0.2) : questType.progressColor.opacity(0.15))
                .frame(width: DailyQuestsTokens.iconSize, height: DailyQuestsTokens.iconSize)

            if quest.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DailyQuestsTokens.completeCheck)
            } else {
                Image(systemName: questType.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(questType.progressColor)
            }
        }
    }

    private var xpReward: some View {
        HStack(spacing: 2) {
            Text("+\(quest.xpReward)")
                .font(DailyQuestsTokens.xpFont)
            Image(systemName: "sparkles")
                .font(.system(size: 9))
        }
        .foregroundColor(quest.isComplete ? OnyxColors.Text.muted : OnyxColors.Accent.amber)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DailyQuestsTokens.progressBarRadius)
                    .fill(DailyQuestsTokens.progressBackground)
                    .frame(height: DailyQuestsTokens.progressBarHeight)

                RoundedRectangle(cornerRadius: DailyQuestsTokens.progressBarRadius)
                    .fill(
                        LinearGradient(
                            colors: [questType.progressColor, questType.progressColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress, height: DailyQuestsTokens.progressBarHeight)
                    .shadow(color: questType.progressColor.opacity(0.5), radius: animatedProgress > 0 ? 4 : 0)
            }
        }
        .frame(height: DailyQuestsTokens.progressBarHeight)
    }

    @ViewBuilder
    private var lockedOverlay: some View {
        if isLocked {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DailyQuestsTokens.lockedOverlay)
                .overlay(
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Complete all quests to unlock")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(PlannerumColors.textMuted)
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DailyQuestsPanel_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            DailyQuestsPanel(
                questEngine: QuestEngine(),
                currentStreak: 7
            )
            .frame(width: 320)
            .padding(24)
        }
        .frame(width: 400, height: 500)
    }
}
#endif
