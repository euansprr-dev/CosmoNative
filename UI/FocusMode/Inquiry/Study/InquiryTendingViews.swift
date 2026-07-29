// CosmoOS/UI/FocusMode/Inquiry/Study/InquiryTendingViews.swift
// TENDING — where the Gardener and the Cartographer speak. Quiet suggestion
// rows in the app's own grammar (the Photos "review duplicates" register: in
// context, dismissible, never a game). They appear exactly where you already
// look at structure: the topic dossier, the Session map, and the Map tab.

import SwiftUI

// MARK: - Row model (one voice for every tending source)

/// Display-ready tending row: the Gardener's question proposals and the
/// Cartographer's concept proposals render through the same grammar.
struct TendingRowModel: Identifiable, Equatable {
    var id: String
    var icon: String = "leaf"
    var primaryLine: String
    var secondaryLine: String?
    /// The full calm sentence — lives in the tooltip.
    var reason: String
    var actionLabel: String
    var helpText: String
}

extension InquiryGardenerProposal {
    var tendingRowModel: TendingRowModel {
        let primary: String
        let secondary: String?
        let help: String
        switch kind {
        case .merge:
            primary = "Fold “\(questionTitle)”"
            secondary = targetTitle.map { "into “\($0)” — they cover the same ground" }
                ?? "They cover the same ground"
            help = "Fold its notes and branches into “\(targetTitle ?? "the other question")”"
        case .promote:
            primary = "Promote “\(questionTitle)” to the top level"
            secondary = nil
            help = "Move it to the topic's top level — history is kept"
        case .graduate:
            primary = "Graduate “\(questionTitle)”"
            secondary = "into its own Deep Dive"
            help = "Give it its own Deep Dive and move its work there"
        }
        return TendingRowModel(
            id: key,
            icon: "leaf",
            primaryLine: primary,
            secondaryLine: secondary,
            reason: reason,
            actionLabel: actionLabel,
            helpText: help
        )
    }
}

extension ConceptCartographerProposal {
    var tendingRowModel: TendingRowModel {
        let primary: String
        let secondary: String?
        let help: String
        switch kind {
        case .group:
            primary = "Gather \(memberTitles.count) concepts under “\(title)”"
            let named = memberTitles.prefix(3).joined(separator: ", ")
            let overflow = memberTitles.count - min(memberTitles.count, 3)
            secondary = overflow > 0 ? "\(named) +\(overflow) more" : named
            help = "Creates the “\(title)” section and clusters them on the canvas"
        case .nest:
            primary = "Move “\(title)” under “\(memberTitles.first ?? "its parent")”"
            secondary = nil
            help = "Files it inside the broader concept — pinned, never auto-moved again"
        case .foldSeedlings:
            primary = "Fold \(memberTitles.count) seedlings into “\(title)”"
            let named = memberTitles.prefix(3).joined(separator: ", ")
            let overflow = memberTitles.count - min(memberTitles.count, 3)
            secondary = overflow > 0 ? "\(named) +\(overflow) more" : named
            help = "Their captures merge into one growing concept — the old names still route to it"
        }
        return TendingRowModel(
            id: key,
            icon: "rectangle.3.group",
            primaryLine: primary,
            secondaryLine: secondary,
            reason: reason,
            actionLabel: actionLabel,
            helpText: help
        )
    }
}

// MARK: - One proposal row

@MainActor
struct InquiryTendingRow: View {
    let model: TendingRowModel
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isWorking = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: model.icon)
                .font(DS.caption)
                .foregroundStyle(DS.accent.opacity(0.7))
                .frame(width: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)
            // Structured, not quoted: the raw reason repeats both titles
            // verbatim and three proposals stacked read as an LLM wall. The
            // titles carry the row; the full sentence lives in the tooltip.
            VStack(alignment: .leading, spacing: 2) {
                Text(model.primaryLine)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(DS.text)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let secondaryLine = model.secondaryLine {
                    Text(secondaryLine)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
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
        .help(model.reason)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tending suggestion: \(model.reason)")
    }

    private var actions: some View {
        HStack(spacing: DS.space8) {
            Button(model.actionLabel) {
                isWorking = true
                onAccept()
            }
            .buttonStyle(.plain)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.accent)
            .help(model.helpText)
            .accessibilityLabel(model.actionLabel)

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
}

// MARK: - Dossier section

/// The dossier's TENDING section: same Files grammar as every sibling
/// section. Gardener (question) rows first, Cartographer (concept) rows
/// after — one voice.
@MainActor
struct StudyTendingSection: View {
    let proposals: [InquiryGardenerProposal]
    let onAccept: (InquiryGardenerProposal) -> Void
    let onDismiss: (InquiryGardenerProposal) -> Void
    var cartographerProposals: [ConceptCartographerProposal] = []
    var onAcceptCartographer: (ConceptCartographerProposal) -> Void = { _ in }
    var onDismissCartographer: (ConceptCartographerProposal) -> Void = { _ in }

    var body: some View {
        StudySection(label: "TENDING", count: proposals.count + cartographerProposals.count) {
            ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                if index > 0 { StudyPaneDivider() }
                InquiryTendingRow(
                    model: proposal.tendingRowModel,
                    onAccept: { onAccept(proposal) },
                    onDismiss: { onDismiss(proposal) }
                )
            }
            ForEach(Array(cartographerProposals.enumerated()), id: \.element.id) { index, proposal in
                if index > 0 || !proposals.isEmpty { StudyPaneDivider() }
                InquiryTendingRow(
                    model: proposal.tendingRowModel,
                    onAccept: { onAcceptCartographer(proposal) },
                    onDismiss: { onDismissCartographer(proposal) }
                )
            }
        }
    }
}

// MARK: - Map strip

/// Compact footer inside a map panel — proposals shown exactly where the
/// structure they'd change is on screen. Model-agnostic: the Session map
/// feeds it Gardener rows, the Deep Dive Map tab feeds it Cartographer rows.
@MainActor
struct TendingMapStrip: View {
    let rows: [TendingRowModel]
    let onAccept: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.space6) {
                Text("TENDING")
                    .dsSmallCapsLabel()
                Spacer()
                Text("\(rows.count)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space16)
            .padding(.top, DS.space10)
            .padding(.bottom, DS.space4)
            ForEach(rows) { row in
                InquiryTendingRow(
                    model: row,
                    onAccept: { onAccept(row.id) },
                    onDismiss: { onDismiss(row.id) }
                )
                .padding(.horizontal, DS.space6)
            }
        }
        .padding(.bottom, DS.space6)
        .background(DS.glassSectionFill)
    }
}

/// Session-map strip: the Gardener's rows in the shared strip shell.
@MainActor
struct InquiryTendingMapStrip: View {
    let proposals: [InquiryGardenerProposal]
    let onAccept: (InquiryGardenerProposal) -> Void
    let onDismiss: (InquiryGardenerProposal) -> Void

    var body: some View {
        TendingMapStrip(
            rows: proposals.map(\.tendingRowModel),
            onAccept: { id in
                if let proposal = proposals.first(where: { $0.key == id }) { onAccept(proposal) }
            },
            onDismiss: { id in
                if let proposal = proposals.first(where: { $0.key == id }) { onDismiss(proposal) }
            }
        )
    }
}
