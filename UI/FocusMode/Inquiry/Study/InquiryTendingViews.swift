// CosmoOS/UI/FocusMode/Inquiry/Study/InquiryTendingViews.swift
// TENDING — where the Gardener speaks. Quiet suggestion rows in the app's own
// grammar (the Photos "review duplicates" register: in context, dismissible,
// never a game). They appear in exactly two places you already look at
// structure: the topic dossier under QUESTIONS, and the Session map.

import SwiftUI

// MARK: - One proposal row

@MainActor
struct InquiryTendingRow: View {
    let proposal: InquiryGardenerProposal
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isWorking = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "leaf")
                .font(DS.caption)
                .foregroundStyle(DS.accent.opacity(0.7))
                .frame(width: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(proposal.reason)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: DS.space8)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                actions
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(isHovered ? DS.surfaceElevated.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tending suggestion: \(proposal.reason)")
    }

    private var actions: some View {
        HStack(spacing: DS.space8) {
            Button(proposal.actionLabel) {
                isWorking = true
                onAccept()
            }
            .buttonStyle(.plain)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.accent)
            .help(helpText)
            .accessibilityLabel(proposal.actionLabel)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Not now — won't be suggested again")
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.top, 1)
    }

    private var helpText: String {
        switch proposal.kind {
        case .promote: return "Move it to the topic's top level — history is kept"
        case .merge: return "Fold its notes and branches into “\(proposal.targetTitle ?? "the other question")”"
        case .graduate: return "Give it its own Deep Dive and move its work there"
        }
    }
}

// MARK: - Dossier section

/// The dossier's TENDING section: same Files grammar as every sibling section.
@MainActor
struct StudyTendingSection: View {
    let proposals: [InquiryGardenerProposal]
    let onAccept: (InquiryGardenerProposal) -> Void
    let onDismiss: (InquiryGardenerProposal) -> Void

    var body: some View {
        StudySection(label: "TENDING", count: proposals.count) {
            ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                if index > 0 { StudyPaneDivider() }
                InquiryTendingRow(
                    proposal: proposal,
                    onAccept: { onAccept(proposal) },
                    onDismiss: { onDismiss(proposal) }
                )
            }
        }
    }
}

// MARK: - Session-map strip

/// Compact footer inside the Session map panel — proposals shown exactly
/// where the structure they'd change is on screen.
@MainActor
struct InquiryTendingMapStrip: View {
    let proposals: [InquiryGardenerProposal]
    let onAccept: (InquiryGardenerProposal) -> Void
    let onDismiss: (InquiryGardenerProposal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.space6) {
                Text("TENDING")
                    .dsSmallCapsLabel()
                Spacer()
                Text("\(proposals.count)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space16)
            .padding(.top, DS.space10)
            .padding(.bottom, DS.space4)
            ForEach(proposals) { proposal in
                InquiryTendingRow(
                    proposal: proposal,
                    onAccept: { onAccept(proposal) },
                    onDismiss: { onDismiss(proposal) }
                )
                .padding(.horizontal, DS.space6)
            }
        }
        .padding(.bottom, DS.space6)
        .background(DS.glassSectionFill)
    }
}
