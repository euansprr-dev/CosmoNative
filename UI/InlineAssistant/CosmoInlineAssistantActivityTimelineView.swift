// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantActivityTimelineView.swift
// The working thread made visible: a live timeline of the run's tool calls on a
// hairline rail, then — once the answer lands — a one-line receipt the reader
// can reopen. Conversation and activity stay separate streams.
// June 2026

import SwiftUI

// MARK: - Live timeline (in-flight run)

/// Renders the in-flight run: planning narration, each tool call as a step
/// cascading onto the rail, and the drafting tail while the answer streams.
struct CosmoInlineAssistantActivityTimelineView: View {
    let steps: [CosmoInlineAssistantActivityStep]
    let phase: CosmoInlineAssistantPhase

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if steps.isEmpty {
                CosmoInlineAssistantPhaseRow(
                    symbol: phase.symbolName,
                    label: phase.statusText ?? "Cosmo is thinking…",
                    isActive: true
                )
            } else {
                stepRows
                trailingPhaseRow
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cosmo is working: \(phase.statusText ?? "")")
    }

    private var stepRows: some View {
        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
            CosmoInlineAssistantActivityStepRow(
                step: step,
                isLast: index == steps.count - 1 && !showsDraftingTail,
                appearIndex: index
            )
        }
    }

    /// While the model writes after its last tool call, the rail ends in a
    /// drafting row so the thread never looks stalled.
    @ViewBuilder
    private var trailingPhaseRow: some View {
        if showsDraftingTail {
            CosmoInlineAssistantPhaseRow(
                symbol: "pencil.and.outline",
                label: "Cosmo is writing…",
                isActive: true
            )
            .padding(.leading, CosmoInlineAssistantTimelineMetrics.railInset)
        }
    }

    private var showsDraftingTail: Bool {
        if case .drafting = phase { return true }
        return false
    }
}

enum CosmoInlineAssistantTimelineMetrics {
    static let dotColumn: CGFloat = 22
    static let railWidth: CGFloat = 1.5
    /// Indents trailing phase rows so their icons align with step dots.
    static let railInset: CGFloat = 0
}

enum CosmoInlineAssistantActivityTimelineMotion {
    /// One revolution of the running-step circle. The spin is driven as a
    /// repeating transform animation rather than a per-frame re-render, so the
    /// duration is also the animation's cycle length.
    static let spinCycleDuration: TimeInterval = 1.1

    static func circleRotationDegrees(
        for state: CosmoInlineAssistantActivityStep.State,
        reduceMotion: Bool,
        date: Date
    ) -> Double {
        guard state == .running, !reduceMotion else { return 0 }
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: spinCycleDuration) / spinCycleDuration
        return progress * 360
    }
}

/// One step on the rail: category icon in a small tinted well, narration label,
/// and a checkmark once done. The running step's label shimmers.
private struct CosmoInlineAssistantActivityStepRow: View {
    let step: CosmoInlineAssistantActivityStep
    let isLast: Bool
    let appearIndex: Int

    @State private var hasAppeared = false
    @State private var spinDegrees: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSpinning: Bool { step.state == .running && !reduceMotion }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            railColumn
            label
            Spacer(minLength: 0)
            statusGlyph
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 6)
        .animation(ProMotionSprings.snappy, value: step.state)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            guard !hasAppeared else { return }
            withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.label), \(step.state == .done ? "done" : "in progress")")
    }

    private var railColumn: some View {
        VStack(spacing: 2) {
            // The circle spins as a repeating *transform* animation, never as a
            // per-frame re-render. A TimelineView(.animation) here re-evaluated
            // this row's body 60×/s for every running step, and each of those
            // re-evaluations re-entered the pane's (deeply nested) layout — with
            // a few steps in flight the main thread could stop draining its
            // transaction queue entirely and the window would wedge. rotationEffect
            // is applied after sizing, so animating it costs no layout at all.
            spinningIcon
                .frame(width: CosmoInlineAssistantTimelineMetrics.dotColumn,
                       height: CosmoInlineAssistantTimelineMetrics.dotColumn)

            if !isLast {
                RoundedRectangle(cornerRadius: CosmoInlineAssistantTimelineMetrics.railWidth / 2)
                    .fill(DS.borderSubtle)
                    .frame(width: CosmoInlineAssistantTimelineMetrics.railWidth)
                    .frame(minHeight: DS.space8)
            }
        }
    }

    private var spinningIcon: some View {
        Image(systemName: CosmoInlineAssistantToolTaxonomy.icon(forToolName: step.toolName))
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(step.state == .done ? DS.textSecondary : DS.accent)
            .frame(width: CosmoInlineAssistantTimelineMetrics.dotColumn,
                   height: CosmoInlineAssistantTimelineMetrics.dotColumn)
            .background(
                (step.state == .done ? DS.surfaceHover : DS.accentSoft),
                in: Circle()
            )
            .rotationEffect(.degrees(spinDegrees))
            .accessibilityHidden(true)
            .onAppear { syncSpin() }
            .onChange(of: isSpinning) { syncSpin() }
    }

    /// Starts (or stops) the continuous spin. The starting angle is seeded from
    /// absolute time via the same helper the old per-frame clock used, so every
    /// running circle on the rail stays in phase with every other one — a row
    /// that appears late still lands mid-revolution alongside its neighbours.
    private func syncSpin() {
        guard isSpinning else {
            var stop = Transaction()
            stop.disablesAnimations = true
            withTransaction(stop) { spinDegrees = 0 }
            return
        }

        let phase = CosmoInlineAssistantActivityTimelineMotion.circleRotationDegrees(
            for: .running,
            reduceMotion: false,
            date: Date()
        )

        var seed = Transaction()
        seed.disablesAnimations = true
        withTransaction(seed) { spinDegrees = phase }

        withAnimation(
            .linear(duration: CosmoInlineAssistantActivityTimelineMotion.spinCycleDuration)
            .repeatForever(autoreverses: false)
        ) {
            spinDegrees = phase + 360
        }
    }

    private var label: some View {
        Text(step.label)
            .font(DS.subheadline.weight(step.state == .running ? .medium : .regular))
            .foregroundStyle(step.state == .running ? DS.text : DS.textSecondary)
            .lineLimit(2)
            .padding(.top, 3)
            .cosmoShimmer(isActive: step.state == .running && !reduceMotion)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if step.state == .done {
            Image(systemName: "checkmark")
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(DS.textMuted)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                .accessibilityHidden(true)
        }
    }
}

/// Planning / drafting rows: a pulsing phase symbol with shimmer narration —
/// the orb's vocabulary carried into the pane.
private struct CosmoInlineAssistantPhaseRow: View {
    let symbol: String
    let label: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: symbol)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: CosmoInlineAssistantTimelineMetrics.dotColumn,
                       height: CosmoInlineAssistantTimelineMetrics.dotColumn)
                .background(DS.accentSoft, in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: isActive && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            Text(label)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .contentTransition(.opacity)
                .animation(ProMotionSprings.gentle, value: label)
                .lineLimit(1)
                .cosmoShimmer(isActive: isActive && !reduceMotion)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Collapsed receipt (finished run)

/// The per-answer receipt: one quiet line above the answer summarizing the work,
/// expandable back into the full timeline for auditing.
struct CosmoInlineAssistantActivityReceiptView: View {
    let steps: [CosmoInlineAssistantActivityStep]
    let sourceCount: Int

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            toggleRow
            if isExpanded {
                expandedSteps
            }
        }
        .animation(ProMotionSprings.focusTransition, value: isExpanded)
    }

    private var toggleRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "sparkle")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(isHovered ? DS.accent : DS.textMuted)
                    .accessibilityHidden(true)

                Text(CosmoInlineAssistantRunReceiptFormatter.summary(steps: steps, sourceCount: sourceCount))
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(isHovered ? DS.textSecondary : DS.textMuted)
                    .monospacedDigit()
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .cosmoHover { isHovered = $0 }
        .help(isExpanded ? "Hide Cosmo's steps" : "Show Cosmo's steps")
        .accessibilityLabel("Cosmo's work: \(CosmoInlineAssistantRunReceiptFormatter.summary(steps: steps, sourceCount: sourceCount))")
        .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
    }

    private var expandedSteps: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                    Image(systemName: CosmoInlineAssistantToolTaxonomy.icon(forToolName: step.toolName))
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(step.label)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let duration = stepDuration(step) {
                        Text(duration)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.leading, DS.space16)
        .padding(.vertical, DS.space4)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 0.75)
                .fill(DS.borderSubtle)
                .frame(width: 1.5)
                .padding(.leading, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
    }

    private func stepDuration(_ step: CosmoInlineAssistantActivityStep) -> String? {
        guard let finishedAt = step.finishedAt else { return nil }
        let interval = finishedAt.timeIntervalSince(step.startedAt)
        guard interval >= 0.5 else { return nil }
        return CosmoInlineAssistantRunReceiptFormatter.durationLabel(interval)
    }
}

// MARK: - Shimmer

/// A masked highlight that sweeps across the running step's label — work in
/// motion without a spinner. Strictly decorative; callers gate on Reduce Motion.
private struct CosmoShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var anchor: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, DS.text.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: anchor * proxy.size.width)
                        .onAppear {
                            anchor = -0.6
                            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                                anchor = 1.2
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .mask(content)
                    .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func cosmoShimmer(isActive: Bool) -> some View {
        modifier(CosmoShimmerModifier(isActive: isActive))
    }
}
