import SwiftUI

struct DashboardHabitPanel: View {
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @State private var animateProgress = false
    @State private var completedHabitId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionHeader

            if viewModel.habits.isEmpty {
                emptyState
            } else {
                habitList
            }
        }
        .task { await viewModel.loadHabits() }
        .onAppear { triggerEntranceAnimation() }
    }

    // MARK: - Header

    // The ONE header voice (no fourth dialect): small-caps label + live
    // count + the ledger rule, with the rail's two actions docked trailing.
    // The old leading "repeat" glyph is gone — no other section label on the
    // page wears an icon.
    private var sectionHeader: some View {
        CosmoSectionHeader(
            label: "Habits",
            detail: viewModel.habits.isEmpty
                ? nil
                : "\(viewModel.habits.filter(\.isTodayComplete).count) of \(viewModel.habits.count)"
        ) {
            HStack(spacing: DS.space2) {
                CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                    .habitLibrary(anchor: anchor)
                } label: {
                    HeaderGlyphButton(systemName: "gearshape", tint: DS.commandCenterMutedText)
                }
                .help("Manage habits")
                .accessibilityLabel("Manage habits")

                CommandCenterComposerTrigger(composer: composer, alignment: .trailing) { anchor in
                    .habitEditor(habit: nil, anchor: anchor)
                } label: {
                    HeaderGlyphButton(systemName: "plus", tint: DS.accent, weight: .semibold)
                }
                .help("New habit")
                .accessibilityLabel("Add habit")
            }
        }
    }

    // MARK: - Habit List

    private var habitList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.space6) {
                ForEach(viewModel.habits) { habit in
                    DashboardHabitOrbitCard(
                        habit: habit,
                        definition: viewModel.habitDefinition(for: habit.id),
                        animateProgress: animateProgress,
                        completedHabitId: completedHabitId,
                        reduceMotion: reduceMotion,
                        onRecordManual: {
                            Task {
                                await viewModel.recordManualHabitCompletion(habitUUID: habit.id)
                                // The mini-bloom belongs to the ring closing,
                                // not to every check-in of a multi-count habit.
                                if viewModel.habits.first(where: { $0.id == habit.id })?.isTodayComplete == true {
                                    Sound.habitComplete()
                                }
                            }
                            if !reduceMotion {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    completedHabitId = habit.id
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        completedHabitId = nil
                                    }
                                }
                            }
                        },
                        composer: composer
                    )
                }
            }
            .padding(.bottom, DS.space6)
        }
    }

    // MARK: - Animations

    // The sweep plays once per app session (VM-owned flag, like the page
    // cascade): returning to the Habits tab remounts this panel, and a
    // panel-owned @State would replay all five rings every visit.
    private func triggerEntranceAnimation() {
        guard !animateProgress else { return }
        if reduceMotion || viewModel.hasPlayedHabitRingSweep {
            animateProgress = true
        } else {
            viewModel.hasPlayedHabitRingSweep = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animateProgress = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        CommandCenterEmptyPane(
            icon: "repeat",
            title: "No habits yet",
            subtitle: "Create a habit and completed tasks can begin feeding progress automatically."
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space8)
    }
}

/// Icon-only header control with the Mac's hover manners — a static glyph on
/// top of fully-alive rows reads unfinished the moment the cursor crosses it.
private struct HeaderGlyphButton: View {
    let systemName: String
    let tint: Color
    var weight: Font.Weight = .regular

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(DS.caption.weight(weight))
            .foregroundStyle(isHovered ? DS.text : tint)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(isHovered ? DS.glassCardFill : Color.clear)
            )
            .contentShape(Circle())
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
    }
}

private struct DashboardHabitOrbitCard: View {
    let habit: HabitState
    let definition: HabitDefinition?
    let animateProgress: Bool
    let completedHabitId: String?
    let reduceMotion: Bool
    let onRecordManual: () -> Void
    let composer: CommandCenterComposerController

    @State private var frame: CGRect = .zero
    @State private var isHovered = false

    var body: some View {
        let isComplete = habit.isTodayComplete

        HStack(alignment: .center, spacing: DS.space10) {
            habitRing

            VStack(alignment: .leading, spacing: DS.space4) {
                titleRow
                detailRow
            }

            Spacer(minLength: 0)

            trailingAccessory
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space8)
        // radiusSmall, matching the ledger's row glass: one row-container
        // radius on the page. Rows separate by rhythm — no per-row hairline
        // (no other row on the page draws its own separator).
        .background {
            if isHovered || isComplete {
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .fill(isComplete ? habit.accentColor.opacity(0.075) : DS.glassCardFill)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .strokeBorder(
                    isHovered || isComplete ? habit.accentColor.opacity(isComplete ? 0.22 : 0.16) : Color.clear,
                    lineWidth: 0.5
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
        .background(CommandCenterGlobalFrameReader(frame: $frame))
        .onTapGesture {
            guard let definition else { return }
            composer.present(.habitEditor(habit: definition, anchor: .init(sourceRect: frame, alignment: .trailing)))
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.01) : ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .help("\(habit.displayTitle) — \(habit.isTodayComplete ? "done today" : habit.todayProgressLabel) · click to edit")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.displayTitle), \(habit.isTodayComplete ? "done today" : habit.todayProgressLabel)")
    }

    private var habitRing: some View {
        let accent = habit.accentColor
        let progress = animateProgress ? habit.todayProgress : 0
        let isComplete = habit.isTodayComplete
        let justCompleted = completedHabitId == habit.id

        // iOS-parity ring: hollow interior, 3.5pt track at 18% accent,
        // full-accent progress arc with round caps.
        return ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : .spring(response: 0.6, dampingFraction: 0.7),
                    value: progress
                )

            // Habit identity, the App Store register: a typed emoji in the
            // name wins, then the curated keyword pass; the user's picked SF
            // icon stays as the explicit-choice fallback.
            if let emoji = habit.identityMark {
                Text(emoji)
                    .font(DS.navTitle)
            } else {
                Image(systemName: habit.iconName)
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(isComplete ? accent : DS.textSecondary)
            }
        }
        .frame(width: 34, height: 34)
        .scaleEffect(justCompleted ? 1.08 : 1.0)
        .animation(
            reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.5),
            value: justCompleted
        )
    }

    // The name owns its line (the row's identity truncates LAST — "Content
    // Re…" at 280pt was the dots eating 72pt of the title's 150). The dots
    // drop to the detail line's trailing edge; ephemeral values yield first.
    private var titleRow: some View {
        // The ring carries the mark — the label must never repeat it. And the
        // label stays ink even when complete: the wash, seal, and ring
        // already say "done" (color on a fourth carrier is spray).
        Text(habit.displayTitle)
            .font(DS.rowTitleCompact)
            .foregroundStyle(DS.text)
            .lineLimit(1)
            .layoutPriority(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Neutral history: the RING is the row's one identity mark — repeating
    // its hue across seven dots per row made the rail the page's chromatic
    // center of gravity (five rows × five hues at the composition's edge).
    private var sevenDayDots: some View {
        let accent = habit.accentColor
        return HStack(spacing: DS.space2) {
            ForEach(Array(habit.last7Days.enumerated()), id: \.offset) { index, completed in
                let isToday = index == 6
                RoundedRectangle(cornerRadius: 2)
                    .fill(completed ? AnyShapeStyle(DS.textSecondary) : AnyShapeStyle(isToday ? Color.clear : DS.commandCenterSeparatorStrong))
                    .frame(width: 6, height: 6)
                    .overlay {
                        // strokeBorder: a 1pt CENTERED stroke on a 6pt shape
                        // rendered ~7pt beside six 6pt siblings.
                        if isToday && !completed {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                        }
                    }
            }
        }
        .help("Last 7 days")
        .accessibilityHidden(true)
    }

    // The ONE second-line voice (DS.rowMeta) — the rail's detail line spoke a
    // fourth inline-invented combination (10pt + medium) beside the ledger's
    // 11pt one gutter away.
    private var detailRow: some View {
        HStack(spacing: 0) {
            if habit.isTodayComplete {
                Text("Done")
                    .font(DS.rowMeta)
                    .foregroundStyle(habit.accentColor)
            } else {
                Text(habit.todayProgressLabel)
                    .font(DS.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
            }

            if !habit.isTimeBased, habit.trackedMinutesToday > 0 {
                Text(" · \(habit.trackedMinutesToday)m")
                    .font(DS.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: DS.space8)

            if (habit.isTimeBased || habit.targetCount > 1) && !habit.isTodayComplete {
                inlineProgressBar
                Spacer().frame(width: DS.space6)
            }

            sevenDayDots
        }
    }

    private var inlineProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DS.borderSubtle)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DS.textMuted)
                    .frame(width: proxy.size.width * (animateProgress ? habit.todayProgress : 0), height: 3)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8),
                        value: animateProgress
                    )
            }
        }
        .frame(width: 32, height: 3)
    }

    // iOS-parity accessory: accent plus while incomplete, seal stamp once done.
    @ViewBuilder
    private var trailingAccessory: some View {
        let accent = habit.accentColor

        if habit.allowManualComplete && !habit.isTodayComplete {
            // Ink until it matters: the check-in affordance is a CONTROL, not
            // the habit's identity — the seal keeps the hue (state earned).
            Button(action: onRecordManual) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.railAccessoryGlyph)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Check in")
            .accessibilityLabel("Check in")
        } else if habit.isTodayComplete {
            Image(systemName: "checkmark.seal.fill")
                .font(DS.railAccessoryGlyph)
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        }
    }


}
