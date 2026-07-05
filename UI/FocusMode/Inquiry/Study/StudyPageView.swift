// CosmoOS/UI/FocusMode/Inquiry/Study/StudyPageView.swift
// The manuscript — the Study's content layer and its one hero. The question
// and forming understanding are written directly on the parchment: no cards,
// no strokes, no boxes. Below them, open threads and scouted finds group by
// spacing rhythm alone (the Things 3 move). Everything assembles once on
// arrival and then stays calm.

import SwiftUI

@MainActor
struct StudyPageView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let hasArrived: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space32) {
                heroBlock
                    .studyRise(hasArrived, index: 0)
                if !openBranches.isEmpty || !branchProposals.isEmpty {
                    threadsSection
                        .studyRise(hasArrived, index: 1)
                }
                if !topCandidates.isEmpty {
                    worthALookSection
                        .studyRise(hasArrived, index: 2)
                }
            }
            .frame(maxWidth: StudyMetrics.pageMeasure, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.space24)
            .padding(.top, 88)
            .padding(.bottom, 150)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .animation(ProMotionSprings.focusTransition, value: viewModel.activeQuestionUUID)
    }

    // MARK: - Hero: question · understanding · counts

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text(viewModel.activeQuestionTitle)
                .font(DS.crucibleTitle)
                .foregroundStyle(DS.text)
                .lineSpacing(5)
                .accessibilityAddTraits(.isHeader)
            understandingBlock
            countsLine
        }
    }

    private var understandingBlock: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            understandingHeader
            understandingBody
        }
    }

    private var understandingHeader: some View {
        HStack(spacing: DS.space6) {
            Text(viewModel.liveUnderstandingIsForming ? "FORMING UNDERSTANDING" : "CURRENT UNDERSTANDING")
                .dsSmallCapsLabel()
            if viewModel.liveUnderstandingIsForming {
                ProvisionalPulseDot()
            }
            Spacer()
            if viewModel.structured.currentUnderstandingDraft != nil {
                regenerateButton
            }
        }
    }

    private var regenerateButton: some View {
        Button {
            Task { await viewModel.regenerateLiveUnderstanding(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Regenerate understanding")
        .accessibilityLabel("Regenerate understanding")
    }

    @ViewBuilder
    private var understandingBody: some View {
        if let draft = viewModel.structured.currentUnderstandingDraft, !draft.text.isEmpty {
            Text(draft.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(DS.text.opacity(0.88))
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .transition(.opacity)
        } else if let error = viewModel.liveUnderstandingError {
            Text(error)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(DS.textMuted)
        } else {
            Text("Think out loud below — every thought gets typed, routed, and kept. Synthesis forms here as the inquiry grows.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(DS.textMuted)
                .lineSpacing(4)
        }
    }

    /// One quiet line of living numbers — punctuation, not decoration.
    private var countsLine: some View {
        let counts = viewModel.counts(for: viewModel.activeQuestionUUID)
        return HStack(spacing: DS.space6) {
            countFragment(counts.claims, counts.claims == 1 ? "claim" : "claims")
            dot
            countFragment(counts.notes, counts.notes == 1 ? "note" : "notes")
            dot
            countFragment(counts.sources, counts.sources == 1 ? "source" : "sources")
            dot
            countFragment(counts.children, counts.children == 1 ? "branch" : "branches")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(counts.claims) claims, \(counts.notes) notes, \(counts.sources) sources, \(counts.children) branches")
    }

    private func countFragment(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(DS.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(value > 0 ? DS.textSecondary : DS.textMuted)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var dot: some View {
        Text("·")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .accessibilityHidden(true)
    }

    // MARK: - Threads (spacing-grouped, no container)

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            studyHeader("THREADS", count: openBranches.count + branchProposals.count)
            VStack(alignment: .leading, spacing: DS.space2) {
                ForEach(openBranches.prefix(5), id: \.uuid) { branch in
                    StudyThreadRow(
                        icon: "arrow.turn.down.right",
                        title: branch.title ?? "Untitled question",
                        detail: threadDetail(for: branch)
                    ) {
                        withAnimation(ProMotionSprings.focusTransition) {
                            viewModel.setActiveQuestion(branch.uuid)
                        }
                    }
                }
                ForEach(branchProposals, id: \.id) { card in
                    proposalRow(card)
                }
            }
        }
    }

    private func threadDetail(for branch: Atom) -> String? {
        let total = viewModel.counts(for: branch.uuid).total
        return total > 0 ? "\(total)" : nil
    }

    /// An AI-proposed branch is an offer with two quiet answers.
    private func proposalRow(_ card: InquiryRoutingCard) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "sparkles")
                .font(DS.caption)
                .foregroundStyle(DS.accent.opacity(0.7))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(card.proposedQuestion ?? card.title)
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
            Spacer(minLength: DS.space8)
            Button("Branch") {
                Task { await viewModel.acceptRoutingCard(card) }
            }
            .buttonStyle(.plain)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.accent)
            .accessibilityLabel("Create branch: \(card.proposedQuestion ?? card.title)")
            Button {
                viewModel.ignoreRoutingCard(card)
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ignore proposal")
            .accessibilityLabel("Ignore proposal")
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
    }

    // MARK: - Worth a look

    private var worthALookSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            studyHeader("WORTH A LOOK", count: topCandidates.count)
            VStack(alignment: .leading, spacing: DS.space2) {
                ForEach(topCandidates, id: \.id) { candidate in
                    StudyCandidateRow(candidate: candidate) {
                        Task { await viewModel.importSourceCandidate(candidate) }
                    }
                }
            }
        }
    }

    private func studyHeader(_ label: String, count: Int) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .dsSmallCapsLabel()
            Spacer()
            Text("\(count)")
                .font(DS.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space10)
    }

    // MARK: - Data

    private var openBranches: [Atom] {
        viewModel.childQuestionNodes(for: viewModel.activeBranchNodeId)
            .compactMap { node in
                guard let uuid = node.atomUUID else { return nil }
                return viewModel.questions.first { $0.uuid == uuid }
            }
            .filter { ($0.questionMetadata?.status ?? .open) != .archived }
    }

    private var branchProposals: [InquiryRoutingCard] {
        Array(
            viewModel.structured.routingCards
                .filter { $0.status == .pending && $0.proposedQuestion != nil }
                .suffix(2)
                .reversed()
        )
    }

    private var topCandidates: [InquirySourceCandidate] {
        Array(viewModel.activeSourceCandidates.filter { $0.importStatus == .candidate }.prefix(3))
    }
}

// MARK: - Rows (plain lines with a hover wash — never cards)

@MainActor
private struct StudyThreadRow: View {
    let icon: String
    let title: String
    var detail: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .foregroundStyle(DS.accent.opacity(0.7))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Spacer(minLength: DS.space8)
                if let detail {
                    Text(detail)
                        .font(DS.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                }
                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.surfaceElevated.opacity(0.5) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("Switch to branch: \(title)")
    }
}

@MainActor
private struct StudyCandidateRow: View {
    let candidate: InquirySourceCandidate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: (candidate.sourceLane ?? .webResource).iconName)
                    .font(DS.caption)
                    .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
                    .frame(width: 18)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(DS.body)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.space8)
                Image(systemName: "arrow.down.circle")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.surfaceElevated.opacity(0.5) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Import into this session")
        .accessibilityLabel("Import source: \(candidate.title)")
    }

    private var metaLine: String {
        var parts: [String] = []
        if let creator = DeepScoutTasteStore.creatorName(for: candidate) {
            parts.append(creator)
        }
        if !candidate.reason.isEmpty && !candidate.reason.hasPrefix("Deep Scout") {
            parts.append(candidate.reason)
        } else {
            parts.append((candidate.sourceLane ?? .webResource).displayName)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Arrival rise

/// The page assembles once on arrival: opacity + a 6pt rise, staggered.
struct StudyRise: ViewModifier {
    let hasArrived: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasArrived ? 1 : 0)
            .offset(y: hasArrived || reduceMotion ? 0 : 6)
            .animation(
                ProMotionSprings.gentle.delay(Double(min(index, 8)) * 0.06),
                value: hasArrived
            )
    }
}

extension View {
    func studyRise(_ hasArrived: Bool, index: Int) -> some View {
        modifier(StudyRise(hasArrived: hasArrived, index: index))
    }
}
