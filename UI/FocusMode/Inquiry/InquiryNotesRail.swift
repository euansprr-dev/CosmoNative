// CosmoOS/UI/FocusMode/Inquiry/InquiryNotesRail.swift
// Left rail of the Stele shell. One chronological feed merging captures + extracts
// (notes, claims, evidence, etc.) routed to the active branch. Newest first.

import SwiftUI

@MainActor
struct InquiryNotesRail: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railHeader
            Divider().background(DS.borderSubtle)
            if items.isEmpty {
                emptyState
            } else {
                feed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var railHeader: some View {
        HStack(spacing: 6) {
            Text("YOUR NOTES")
                .dsSmallCapsLabel()
            Spacer()
            Text("\(items.count)")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Spacer(minLength: DS.space48)
            Image(systemName: "leaf")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("Notes you route to this question will appear here.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.space20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.space8) {
                ForEach(items, id: \.feedId) { item in
                    InquiryNoteRow(viewModel: viewModel, item: item)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space12)
        }
        .animation(ProMotionSprings.gentle, value: items.count)
    }

    // MARK: - Data

    private var items: [InquiryNoteFeedItem] {
        var merged: [InquiryNoteFeedItem] = []

        let savedExtracts = viewModel.extracts(
            for: viewModel.activeQuestionUUID,
            kinds: Set(ExtractKind.allCases)
        )
        for atom in savedExtracts where atom.extractMetadata?.status != .ignored {
            merged.append(.extract(atom))
        }

        let liveCaptures = viewModel.structured.sessionCaptures.filter {
            $0.status == .pending && ($0.attachedQuestionId ?? viewModel.activeQuestionUUID) == viewModel.activeQuestionUUID
        }
        for capture in liveCaptures {
            merged.append(.capture(capture))
        }

        return merged.sorted { $0.sortKey > $1.sortKey }
    }
}

// MARK: - Feed item

enum InquiryNoteFeedItem: Identifiable {
    case extract(Atom)
    case capture(SessionCapture)

    var id: String { feedId }

    var feedId: String {
        switch self {
        case .extract(let atom): return "extract-\(atom.uuid)"
        case .capture(let capture): return "capture-\(capture.id)"
        }
    }

    var sortKey: String {
        switch self {
        case .extract(let atom):
            return atom.extractMetadata?.committedAt ?? atom.createdAt
        case .capture(let capture):
            return capture.createdAt
        }
    }

    var isCapture: Bool {
        if case .capture = self { return true }
        return false
    }
}

// MARK: - Single row

@MainActor
struct InquiryNoteRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let item: InquiryNoteFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel)
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(kindColor)
                Text(bodyText)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                intentSuggestion
                Text(timestampText)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.sepiaSubtle, lineWidth: 0.5)
        )
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel). \(bodyText)")
    }

    // MARK: - Subviews

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(kindColor)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
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
            Button("Save as speculative claim") {
                Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: .speculativeClaim) }
            }
            Divider()
            Button("Discard", role: .destructive) {
                viewModel.discardCapture(capture.id)
            }
        case .extract:
            EmptyView()
        }
    }

    @ViewBuilder
    private var intentSuggestion: some View {
        if case .capture(let capture) = item,
           let suggestedKind = capture.suggestedKind,
           suggestedKind != .note,
           (capture.suggestedKindConfidence ?? 0) >= 0.7 {
            HStack(spacing: 4) {
                Text("Looks like \(suggestionArticle(for: suggestedKind)) \(suggestionNoun(for: suggestedKind))")
                Text("-")
                    .accessibilityHidden(true)
                Button(suggestionActionTitle(for: suggestedKind)) {
                    handleSuggestion(capture, suggestedKind: suggestedKind)
                }
                .buttonStyle(.plain)
                Text("·")
                    .accessibilityHidden(true)
                Button("Keep") {
                    Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: .note) }
                }
                .buttonStyle(.plain)
            }
            .font(.system(.caption, design: .serif))
            .foregroundStyle(DS.accent.opacity(0.7))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Looks like \(suggestionArticle(for: suggestedKind)) \(suggestionNoun(for: suggestedKind)). \(suggestionActionTitle(for: suggestedKind)) or keep.")
        }
    }

    // MARK: - Derived

    private var kind: ExtractKind {
        switch item {
        case .extract(let atom):
            return atom.extractMetadata?.kind ?? .note
        case .capture(let capture):
            return capture.suggestedKind ?? .note
        }
    }

    private var kindLabel: String {
        switch item {
        case .capture: return "Capture · awaiting route"
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

    private var kindColor: Color {
        switch item {
        case .capture: return DS.accent.opacity(0.7)
        case .extract:
            if kind.isClaimLike { return DS.accent }
            if kind.isEvidenceLike { return DS.green }
            if kind == .note { return CosmoColors.note }
            return CosmoColors.textSecondary
        }
    }

    private var timestampText: String {
        let iso: String
        switch item {
        case .extract(let atom): iso = atom.extractMetadata?.committedAt ?? atom.createdAt
        case .capture(let capture): iso = capture.createdAt
        }
        return RelativeISO8601Formatter.shared.relative(from: iso)
    }

    private func handleSuggestion(_ capture: SessionCapture, suggestedKind: ExtractKind) {
        if suggestedKind == .question {
            Task { _ = await viewModel.promoteCaptureToBranch(captureId: capture.id) }
        } else {
            Task { _ = await viewModel.commitCaptureWith(captureId: capture.id, kind: suggestedKind) }
        }
    }

    private func suggestionActionTitle(for kind: ExtractKind) -> String {
        if kind == .question { return "Make branch" }
        return "Make \(suggestionNoun(for: kind))"
    }

    private func suggestionNoun(for kind: ExtractKind) -> String {
        switch kind {
        case .question: return "question"
        case .claim: return "claim"
        case .speculativeClaim: return "maybe"
        case .evidence: return "evidence"
        case .counterevidence: return "counterpoint"
        case .practice: return "practice"
        case .outputIdea: return "output"
        case .term: return "term"
        case .reference: return "reference"
        case .sourceSnippet: return "snippet"
        case .quote: return "quote"
        case .highlight: return "highlight"
        case .mechanism: return "mechanism"
        case .example: return "example"
        case .objection: return "objection"
        case .principle: return "principle"
        case .assumption: return "assumption"
        case .sourceQualityNote: return "source note"
        case .aiInsight: return "insight"
        case .note: return "note"
        }
    }

    private func suggestionArticle(for kind: ExtractKind) -> String {
        switch suggestionNoun(for: kind).first?.lowercased() {
        case "a", "e", "i", "o", "u": return "an"
        default: return "a"
        }
    }
}

// MARK: - Relative date formatter

@MainActor
final class RelativeISO8601Formatter {
    static let shared = RelativeISO8601Formatter()
    private let parser = ISO8601DateFormatter()
    private let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func relative(from iso: String) -> String {
        guard let date = parser.date(from: iso) else { return "" }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
