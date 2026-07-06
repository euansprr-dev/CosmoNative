// CosmoOS/UI/FocusMode/Inquiry/Study/StudyTrailPanel.swift
// The left inspector: the capture trail in the Files grammar — ONE list,
// hairline separators inset to the text column, monochrome rows, no per-row
// cards. Docked edge-to-edge alongside the content (Apple's inspector idiom;
// only navigation floats). Successor of InquiryNotesRail.

import SwiftUI

@MainActor
struct StudyTrailPanel: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    var isOverlay: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if items.isEmpty {
                teachingState
            } else {
                feed
            }
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .leading, isOverlay: isOverlay)
    }

    // MARK: - Header (on the surface, below the floating islands)

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("TRAIL")
                .dsSmallCapsLabel()
            Spacer()
            Text("\(items.count)")
                .font(DS.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    StudyTrailGroupHeader(group: group, isActive: group.questionUUID == viewModel.activeQuestionUUID)
                    ForEach(Array(group.items.enumerated()), id: \.element.feedId) { index, item in
                        if index > 0 { rowSeparator }
                        StudyTrailRow(viewModel: viewModel, item: item)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            // The thinking bar floats over the panel's foot — keep the last
            // rows reachable above it.
            .padding(.bottom, StudyMetrics.panelBottomInset)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .animation(ProMotionSprings.gentle, value: groupAnimationKey)
    }

    private var rowSeparator: some View {
        Divider()
            .overlay(DS.glassBorder)
            .padding(.leading, 40)
    }

    private var teachingState: some View {
        VStack {
            Text("Notes you route to this question land here.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }

    // MARK: - Data (unchanged from the rail)

    private var groups: [NoteDestinationGroup] {
        let sessionQuestionUUIDs = Set(
            viewModel.structured.researchTree.nodes.values
                .filter { $0.kind == .question }
                .compactMap(\.atomUUID)
        )
        let trailExtracts = viewModel.extracts.filter { atom in
            guard let metadata = atom.extractMetadata, metadata.status != .ignored else { return false }
            if metadata.parentSessionUUID == viewModel.session.uuid { return true }
            return metadata.parentQuestionUUID.map(sessionQuestionUUIDs.contains) ?? false
        }
        let pendingCaptures = viewModel.structured.sessionCaptures.filter { $0.status == .pending }
        return InquiryNotesGrouping.groups(
            extracts: trailExtracts,
            captures: pendingCaptures,
            activeQuestionUUID: viewModel.activeQuestionUUID,
            questionTitle: { viewModel.questionTitle(for: $0) }
        )
    }

    private var items: [InquiryNoteFeedItem] {
        groups.flatMap(\.items)
    }

    private var groupAnimationKey: Int {
        var hasher = Hasher()
        for group in groups {
            hasher.combine(group.id)
            for item in group.items {
                hasher.combine(item.feedId)
                hasher.combine(item.isProvisional)
            }
        }
        return hasher.finalize()
    }
}

// MARK: - Group subheader

@MainActor
private struct StudyTrailGroupHeader: View {
    let group: NoteDestinationGroup
    let isActive: Bool

    var body: some View {
        HStack(spacing: DS.space6) {
            Circle()
                .fill(isActive ? DS.accent : DS.textMuted.opacity(0.5))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(group.title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(isActive ? DS.textSecondary : DS.textMuted)
                .lineLimit(1)
            Spacer()
            Text("\(group.items.count)")
                .font(DS.caption2)
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.items.count) items")
    }
}

// MARK: - Row (a line, never a card)

@MainActor
private struct StudyTrailRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let item: InquiryNoteFeedItem

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(bodyText)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                footer
                captureResolutionRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space8)
        .background(isHovered ? DS.surfaceElevated.opacity(0.6) : .clear)
        .offset(x: isHovered ? 2 : 0)
        .opacity(item.isProvisional ? 0.62 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu { contextMenu }
        .animation(ProMotionSprings.gentle, value: item.isProvisional)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel). \(bodyText)")
    }

    private var icon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(DS.caption)
                .foregroundStyle(kindColor)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            if item.isProvisional {
                ProvisionalPulseDot()
                    .offset(x: 4, y: -2)
            }
        }
    }

    /// Footer: time · kind (a tappable badge for routed extracts) · crystallized mark.
    /// The timestamp lives inside a TimelineView so "26s ago" keeps aging —
    /// a static render freezes the moment it was drawn.
    private var footer: some View {
        HStack(spacing: DS.space6) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(timestampText(asOf: context.date))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            kindBadge
            if item.isCrystallized {
                HStack(spacing: 2) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 5))
                        .accessibilityHidden(true)
                    Text("Crystallized")
                        .font(DS.caption2)
                }
                .foregroundStyle(DS.accent.opacity(0.65))
                .accessibilityLabel("Crystallized in a previous session")
            }
        }
    }

    /// A stranded pending capture offers its resolution inline — one click to
    /// branch it or keep it as a note, so nothing waits forever on a menu.
    @ViewBuilder
    private var captureResolutionRow: some View {
        if case .capture(let capture) = item, capture.status == .pending {
            HStack(spacing: DS.space8) {
                Button(capture.suggestedKind == .question ? "Make branch" : "Save note") {
                    Task {
                        if capture.suggestedKind == .question {
                            _ = await viewModel.promoteCaptureToBranch(captureId: capture.id)
                        } else {
                            _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: capture.suggestedKind ?? .note)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel(capture.suggestedKind == .question ? "Make this a branch question" : "Save as note")

                Button("Keep as note") {
                    Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: .note) }
                }
                .buttonStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .opacity(capture.suggestedKind == .question ? 1 : 0)
                .accessibilityLabel("Keep as a note")
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch item {
        case .capture:
            Text("awaiting route")
                .font(DS.caption2)
                .foregroundStyle(DS.accent.opacity(0.7))
        case .extract(let atom):
            if atom.extractMetadata?.kindPending == true {
                InquiryClassifyingChip()
            } else {
                InquiryKindBadgeMenu(
                    viewModel: viewModel,
                    extractUUID: atom.uuid,
                    kind: kind,
                    isUnconfirmed: atom.extractMetadata?.routingDecisionId?.hasPrefix("heuristic-fallback-") == true
                )
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch item {
        case .capture(let capture):
            Button("Save as note") {
                Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: .note) }
            }
            Button("Save as claim") {
                Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: .claim) }
            }
            Button("Make a branch question") {
                Task { _ = await viewModel.promoteCaptureToBranch(captureId: capture.id) }
            }
            Divider()
            Button("Discard", role: .destructive) {
                viewModel.discardCapture(capture.id)
            }
        case .extract(let atom):
            InquiryExtractCorrectionMenu(
                viewModel: viewModel,
                extractUUID: atom.uuid,
                currentKind: atom.extractMetadata?.kind
            )
        }
    }

    // MARK: - Derived

    private var kind: ExtractKind {
        switch item {
        case .extract(let atom): return atom.extractMetadata?.kind ?? .note
        case .capture(let capture): return capture.suggestedKind ?? .note
        }
    }

    private var kindLabel: String {
        switch item {
        case .capture: return "Capture awaiting route"
        case .extract: return kind.displayName
        }
    }

    private var bodyText: String {
        switch item {
        case .extract(let atom): return atom.body ?? atom.title ?? "Untitled"
        case .capture(let capture): return capture.body
        }
    }

    private var iconName: String {
        switch item {
        case .capture: return "circle.dashed"
        case .extract: return kind.iconName
        }
    }

    /// Monochrome until meaning demands otherwise: claims carry the accent,
    /// evidence the green — at 70%, as identity, not decoration.
    private var kindColor: Color {
        switch item {
        case .capture: return DS.textMuted
        case .extract:
            if kind.isClaimLike { return DS.accent.opacity(0.7) }
            if kind.isEvidenceLike { return DS.green.opacity(0.7) }
            return DS.textSecondary
        }
    }

    private func timestampText(asOf now: Date) -> String {
        let iso: String
        switch item {
        case .extract(let atom): iso = atom.extractMetadata?.committedAt ?? atom.createdAt
        case .capture(let capture): iso = capture.createdAt
        }
        return RelativeISO8601Formatter.shared.relative(from: iso, to: now)
    }
}
