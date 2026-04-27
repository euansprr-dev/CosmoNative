// CosmoOS/UI/FocusMode/Inquiry/Panes/InquiryCopilotPane.swift
// Inquiry Thread pane (Pane C) — chat-first Cosmo surface with context, routing cards, and map forming.

import SwiftUI

@MainActor
struct InquiryCopilotPane: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    threadHeader
                    contextStrip
                    quickActions
                    routingCards
                    questionInspector
                    answerForming
                    mapForming
                    recentSection
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space12)
            }
            Divider().background(DS.borderSubtle)
            askInput
        }
    }

    // MARK: - Context

    private var threadHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inquiry Thread")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Think here. Cosmo will route branches, notes, sources, and open loops.")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("CONTEXT")
            if let dd = viewModel.deepDive, let title = dd.title {
                contextLine(icon: "circle.hexagongrid.circle.fill", text: title)
            }
            contextLine(icon: "questionmark.bubble.fill", text: "Asking within: \(viewModel.activeQuestionTitle)")
            if let source = viewModel.activeSourceTab {
                contextLine(icon: "doc.text", text: "Current source: \(source.title)")
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func contextLine(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(CosmoColors.textTertiary)
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("QUICK ACTIONS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                quickAction("Summarize source", icon: "doc.text.magnifyingglass")
                quickAction("Challenge evidence", icon: "exclamationmark.triangle")
                quickAction("Create branch", icon: "arrow.triangle.branch")
                quickAction("Find related", icon: "point.3.connected.trianglepath.dotted")
            }
        }
    }

    private func quickAction(_ title: String, icon: String) -> some View {
        Button {
            viewModel.aiPromptDraft = title
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(CosmoTypography.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 6)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
            .foregroundStyle(CosmoColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Routing cards

    @ViewBuilder
    private var routingCards: some View {
        let pending = viewModel.structured.routingCards.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionLabel("ROUTING")
                ForEach(pending, id: \.id) { card in
                    routingCard(card)
                }
            }
        }
    }

    private func routingCard(_ card: InquiryRoutingCard) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: 6) {
                Image(systemName: routingIcon(for: card.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.accent)
                Text(card.title)
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
            }
            if let proposed = card.proposedQuestion {
                Text("\"\(proposed)\"")
                    .font(.system(size: 15, weight: .regular, design: .serif).italic())
                    .foregroundStyle(CosmoColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = card.detail {
                Text(detail)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .lineLimit(3)
            }
            if let extract = card.proposedExtractText {
                Text(extract)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(4)
            }
            HStack(spacing: DS.space8) {
                Button(card.actionTitle ?? defaultActionTitle(for: card.kind)) {
                    Task { await viewModel.acceptRoutingCard(card) }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(DS.accent)
                Button("Ignore") {
                    viewModel.ignoreRoutingCard(card)
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
            }
        }
        .padding(DS.space10)
        .background(DS.accentSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.accent.opacity(0.35), lineWidth: 1))
    }

    private func routingIcon(for kind: InquiryRoutingCard.Kind) -> String {
        switch kind {
        case .branchProposal, .childBranchProposal, .sourceFinding:
            return "arrow.triangle.branch"
        case .claimProposal:
            return "exclamationmark.bubble"
        case .evidenceProposal:
            return "checkmark.seal"
        case .counterevidenceProposal, .sourceQualityWarning:
            return "exclamationmark.triangle"
        case .mechanismProposal:
            return "gearshape.2"
        case .assumptionProposal:
            return "building.columns"
        case .noteRoute:
            return "note.text"
        case .modelUpdate:
            return "arrow.triangle.2.circlepath"
        }
    }

    private func defaultActionTitle(for kind: InquiryRoutingCard.Kind) -> String {
        switch kind {
        case .branchProposal: return "Create branch"
        case .childBranchProposal: return "Create child branch"
        case .sourceFinding: return "Create branch"
        case .claimProposal: return "Save claim"
        case .evidenceProposal: return "Save evidence"
        case .counterevidenceProposal: return "Save counterevidence"
        case .mechanismProposal: return "Save mechanism"
        case .assumptionProposal: return "Save assumption"
        case .sourceQualityWarning: return "Save warning"
        case .noteRoute: return "Apply"
        case .modelUpdate: return "Apply"
        }
    }

    // MARK: - Question inspector

    private var questionInspector: some View {
        let counts = viewModel.counts(for: viewModel.activeQuestionUUID)
        return VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("ACTIVE QUESTION")
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: "scope")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.activeQuestionTitle)
                        .font(CosmoTypography.label)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(viewModel.questionStatus(for: viewModel.activeQuestionUUID).displayName) · \(counts.compactLabel)")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
            HStack(spacing: DS.space8) {
                Button("Ask") {
                    viewModel.aiPromptDraft = "Help me think through \(viewModel.activeQuestionTitle)."
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(DS.accent)
                Button("Branch") {
                    viewModel.aiPromptDraft = "Suggest one branch question under: \(viewModel.activeQuestionTitle)"
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                Button("Answered") {
                    Task { await viewModel.updateQuestionStatus(viewModel.activeQuestionUUID, status: .answered) }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
            }
            let notes = viewModel.recentNotes(for: viewModel.activeQuestionUUID)
            if !notes.isEmpty {
                Divider().background(DS.borderSubtle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(CosmoTypography.labelSmall)
                        .foregroundStyle(CosmoColors.textTertiary)
                    ForEach(notes, id: \.uuid) { note in
                        Text(note.body ?? note.title ?? "")
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    // MARK: - Answer forming

    private var answerForming: some View {
        let claims = viewModel.claims(for: viewModel.activeQuestionUUID)
        let evidence = viewModel.evidence(for: viewModel.activeQuestionUUID)
        let mechanisms = viewModel.mechanisms(for: viewModel.activeQuestionUUID)
        return VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("ANSWER FORMING")
            if claims.isEmpty && evidence.isEmpty && mechanisms.isEmpty {
                Text("Claims, evidence, counterevidence, mechanisms, assumptions, and source quality notes will collect here.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            } else {
                if !claims.isEmpty {
                    answerGroup("CLAIMS", items: claims)
                }
                if !evidence.isEmpty {
                    answerGroup("EVIDENCE / COUNTEREVIDENCE", items: evidence)
                }
                if !mechanisms.isEmpty {
                    answerGroup("MECHANISMS / ASSUMPTIONS / QUALITY", items: mechanisms)
                }
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func answerGroup(_ title: String, items: [Atom]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
            ForEach(items.prefix(4), id: \.uuid) { item in
                answerItem(item)
            }
        }
    }

    private func answerItem(_ atom: Atom) -> some View {
        let kind = atom.extractMetadata?.kind ?? .aiInsight
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: kind.iconName)
                .font(.system(size: 10))
                .foregroundStyle(kind == .speculativeClaim || kind == .sourceQualityNote ? DS.orange : DS.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(CosmoColors.textTertiary)
                Text(atom.body ?? atom.title ?? "")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Map forming

    private var mapForming: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("MAP FORMING")
            let concepts = viewModel.structured.mapForming.concepts
            if concepts.isEmpty {
                Text("Start highlighting, asking, or taking notes. Cosmo will surface branches, terms, contradictions, and open loops here.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            } else {
                if !viewModel.structured.mapForming.branchSuggestions.isEmpty {
                    ForEach(viewModel.structured.mapForming.branchSuggestions.prefix(3), id: \.id) { s in
                        mapSignal(icon: "arrow.triangle.branch", text: s.proposedQuestion)
                    }
                }
                ForEach(concepts.prefix(6), id: \.id) { c in
                    mapSignal(icon: "circle.hexagongrid", text: "\(c.label) · \(c.mentionCount)")
                }
            }
            if !viewModel.structured.mapForming.openLoops.isEmpty {
                Text("OPEN LOOPS")
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .padding(.top, 4)
                ForEach(viewModel.structured.mapForming.openLoops.prefix(4), id: \.id) { loop in
                    Text("· \(loop.description)")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                }
            }
        }
    }

    private func mapSignal(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(DS.accent)
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("RECENT")
            let recent = viewModel.structured.activityEvents.suffix(8).reversed()
            if recent.isEmpty {
                Text("No thread messages yet. Ask, route a note, or deepen a highlight to begin.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            } else {
                ForEach(Array(recent), id: \.id) { event in
                    activityRow(event)
                }
            }
        }
    }

    private func activityRow(_ event: InquiryActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: activityIcon(for: event.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activityColor(for: event.kind))
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
                if let detail = event.detail {
                    Text(detail)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func activityIcon(for kind: InquiryActivityEvent.Kind) -> String {
        switch kind {
        case .noteSaved: return "checkmark"
        case .sourceOpened: return "doc.badge.plus"
        case .sourceClosed: return "xmark.circle"
        case .branchCreated: return "arrow.triangle.branch"
        case .claimSaved: return "exclamationmark.bubble"
        case .evidenceSaved: return "checkmark.seal"
        case .routingSuggested: return "diamond"
        case .routingIgnored: return "minus.circle"
        case .aiReply: return "sparkles"
        case .extractSaved: return "highlighter"
        }
    }

    private func activityColor(for kind: InquiryActivityEvent.Kind) -> Color {
        switch kind {
        case .sourceClosed, .routingIgnored:
            return CosmoColors.textTertiary
        default:
            return DS.accent
        }
    }

    // MARK: - Ask input

    private var askInput: some View {
        VStack(spacing: 4) {
            HStack {
                TextField("Ask, route, branch, or update...", text: $viewModel.aiPromptDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .padding(DS.space10)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                Button {
                    let prompt = viewModel.aiPromptDraft
                    Task { await viewModel.runAIPrompt(prompt) }
                } label: {
                    Image(systemName: viewModel.aiBusy ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.aiBusy || viewModel.aiPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 6) {
                quickPromptChip("Explain simply")
                quickPromptChip("What does this contradict?")
                quickPromptChip("Create a branch")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private func quickPromptChip(_ text: String) -> some View {
        Button {
            viewModel.aiPromptDraft = text
        } label: {
            Text(text)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .tracking(2)
            .foregroundStyle(CosmoColors.textSecondary.opacity(0.78))
    }
}
