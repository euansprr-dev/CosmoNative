// CosmoOS/UI/FocusMode/Connection/ConceptRecommendationPanel.swift
// The Material rail's face in the connection inspector. Replaces the old
// Live Insights appliance with the inspector's own unboxed grammar: one
// small-caps header with a live count, a tappable "seeking" line that names
// what the concept is hungry for, receipt rows with hover actions, and
// teaching states that hand the user the unlock instead of an empty shelf.

import SwiftUI

struct ConceptRecommendationPanel: View {

    @Bindable var model: ConceptRecommendationModel
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let actions: ConnectionWorkspaceActions

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            header
            if model.gate == .ready, let seeking = model.seeking {
                SeekingLine(section: seeking) {
                    workspace.openSection(seeking)
                }
            }
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space6) {
            Text("Material")
                .font(DS.smallCaps)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.textMuted)
            if model.gate == .ready, !model.visibleRows.isEmpty {
                Text("\(model.visibleRows.count)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if model.gate == .ready {
                headerControls
            }
        }
        .animation(ProMotionSprings.gentle, value: model.visibleRows.count)
    }

    private var headerControls: some View {
        HStack(spacing: DS.space6) {
            if model.presentOrigins.count > 1 {
                filterMenu
            }
            if model.isRefreshing {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 14, height: 14)
            } else {
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .help("Look again with the concept as it stands now")
        .accessibilityLabel("Refresh recommendations")
    }

    private var filterMenu: some View {
        Menu {
            Button("Everything") { model.filter = nil }
            Divider()
            ForEach(model.presentOrigins, id: \.self) { origin in
                Button(origin.label) { model.filter = origin }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(DS.caption2)
                .foregroundStyle(model.filter == nil ? DS.textMuted : DS.accent)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by source")
        .accessibilityLabel("Filter recommendations by source")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.gate {
        case .needsGoal:
            TeachingState(
                icon: "target",
                line: "State the goal first.",
                explanation: "Material arrives once the concept knows what it's for.",
                buttonTitle: "Open Goal"
            ) {
                workspace.openSection(.goal)
            }
        case .needsMoreMaterial:
            TeachingState(
                icon: "circle.dotted",
                line: "Add one more thought.",
                explanation: "A goal plus one more entry is enough to start matching your library."
            )
        case .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if model.visibleRows.isEmpty && !model.isRefreshing {
            TeachingState(
                icon: "moon.zzz",
                line: "Nothing resonates yet.",
                explanation: "Keep developing — highlights, inquiry moments, and captures join as the concept sharpens."
            )
            findMoreFooter
        } else {
            rowsList
            findMoreFooter
        }
    }

    private var rowsList: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(model.visibleRows) { row in
                ConceptRecommendationRow(
                    row: row,
                    onOpen: { open(row) },
                    onOpenVia: row.viaConceptUUID.map { uuid in
                        { actions.onSourceTap(uuid) }
                    },
                    onWeave: { section in
                        withAnimation(ProMotionSprings.gentle) {
                            model.weave(row, into: section, viewModel: viewModel)
                        }
                    },
                    onDismiss: {
                        withAnimation(ProMotionSprings.gentle) {
                            model.dismiss(row)
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .offset(x: 12).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }

    @ViewBuilder
    private var findMoreFooter: some View {
        if !model.didExpand && !model.isRefreshing {
            Button {
                Task { await model.findMore() }
            } label: {
                Text("Find more")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.space6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search wider — lower the match floor once")
            .accessibilityLabel("Find more recommendations")
        }
    }

    private func open(_ row: ConceptRecommendation) {
        guard let uuid = row.atomUUID else { return }
        actions.onSourceTap(uuid)
    }
}

// MARK: - Seeking line

/// One line naming the section the concept is hungry for. Tapping jumps
/// straight into that section — the rail's suggestions all aim here.
private struct SeekingLine: View {
    let section: ConnectionSectionType
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space6) {
                Image(systemName: "scope")
                    .font(DS.caption2)
                    .foregroundStyle(section.accentColor)
                    .accessibilityHidden(true)
                Text("Seeking \(section.displayName.lowercased())")
                    .font(DS.caption)
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(
                section.accentColor.opacity(isHovered ? 0.10 : 0.06),
                in: .rect(cornerRadius: 6)
            )
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(section.promptQuestion)
        .accessibilityLabel("Seeking \(section.displayName). \(section.promptQuestion)")
    }
}

// MARK: - Row

/// One recommendation: origin mark, source title, the receipt excerpt, and a
/// provenance line. Hover reveals add + dismiss; right-click retargets the
/// add to any section. Atom-backed rows open as panes; inbox captures unfold
/// in place (they have no page of their own).
private struct ConceptRecommendationRow: View {
    let row: ConceptRecommendation
    let onOpen: () -> Void
    /// Set when the row is badged "via <page>" — opens that page.
    var onOpenVia: (() -> Void)? = nil
    let onWeave: (ConnectionSectionType) -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        Button(action: primaryAction) {
            HStack(alignment: .top, spacing: DS.space8) {
                originMark
                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    excerptText
                    if let rationale = row.rationale, !rationale.isEmpty {
                        rationaleText(rationale)
                    }
                    metaLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isHovered { hoverActions }
            }
            .padding(DS.space8)
            .background(
                isHovered ? AnyShapeStyle(DS.surfaceElevated) : AnyShapeStyle(.clear),
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu { retargetMenu }
        .help(row.atomUUID != nil ? "Open source" : "Show the full capture")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.origin.label): \(row.title). \(row.excerpt)")
    }

    private func primaryAction() {
        if row.atomUUID != nil {
            onOpen()
        } else {
            withAnimation(ProMotionSprings.gentle) { isExpanded.toggle() }
        }
    }

    private var originMark: some View {
        Image(systemName: row.origin.icon)
            .font(DS.caption2)
            .foregroundStyle(row.origin.tint)
            .frame(width: 14)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }

    private var titleLine: some View {
        HStack(spacing: DS.space4) {
            if row.isNew {
                Circle()
                    .fill(row.origin.tint)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
            }
            Text(row.title)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
    }

    private var excerptText: some View {
        Text(row.excerpt)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .lineLimit(isExpanded ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(1.5)
    }

    /// The judge's one-sentence justification (or the matched-phrase
    /// receipt) — why this row earned its place.
    private func rationaleText(_ rationale: String) -> some View {
        Text(rationale)
            .font(DS.caption2)
            .italic()
            .foregroundStyle(DS.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 1)
    }

    private var metaLine: some View {
        HStack(spacing: DS.space4) {
            Text(row.origin.label)
                .font(DS.caption2)
                .foregroundStyle(row.origin.tint.opacity(0.85))
            if let detail = row.detail, !detail.isEmpty {
                Text("· \(detail)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailingBadge
        }
        .padding(.top, 1)
    }

    /// Material already embodied in a linked page says so instead of posing
    /// as new; everything else names its landing section.
    @ViewBuilder
    private var trailingBadge: some View {
        if let viaTitle = row.viaConceptTitle, let onOpenVia {
            Button(action: onOpenVia) {
                Text("via \(viaTitle)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entityConnection.opacity(0.9))
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Already lives in \(viaTitle) — open that page")
            .accessibilityLabel("Already in \(viaTitle)")
        } else {
            Text("→ \(row.suggestedSection.displayName)")
                .font(DS.caption2)
                .foregroundStyle(row.suggestedSection.accentColor.opacity(0.8))
                .lineLimit(1)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: DS.space4) {
            Button {
                onWeave(row.suggestedSection)
            } label: {
                Image(systemName: "plus")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16, height: 16)
                    .background(DS.border.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Add to \(row.suggestedSection.displayName) — right-click to choose a section")
            .accessibilityLabel("Add to \(row.suggestedSection.displayName)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16, height: 16)
                    .background(DS.border.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Don't suggest this here again")
            .accessibilityLabel("Dismiss recommendation")
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var retargetMenu: some View {
        ForEach(ConnectionSectionType.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.self) { section in
            Button("Add to \(section.displayName)") {
                onWeave(section)
            }
        }
        Divider()
        Button("Dismiss", role: .destructive, action: onDismiss)
    }
}

// MARK: - Teaching state

/// The dormant/empty voice: a quiet glyph, one line, the reason, and — when
/// there is one — the single button that performs the unlock.
private struct TeachingState: View {
    let icon: String
    let line: String
    let explanation: String
    var buttonTitle: String? = nil
    var onButton: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                Text(line)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Text(explanation)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
            if let buttonTitle {
                Button(buttonTitle, action: onButton)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, DS.space4)
        .accessibilityElement(children: .combine)
    }
}
