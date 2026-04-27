// CosmoOS/UI/FocusMode/Inquiry/Review/InquiryReviewView.swift
// Crystallization review surface — section-by-section accept/edit/reject for
// lexicon, questions, model updates, output candidates, etc.
//
// Naming: InquiryReviewView (not CrystallizationView) to avoid name collision
// with existing CrystallizationEngine.swift in /AI/.

import SwiftUI

@MainActor
struct InquiryReviewView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    @State private var output: CrystallizationOutput? = nil
    @State private var status: ReviewStatus = .idle
    @State private var statusMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.borderSubtle)
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Crystallization")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Spacer()
            if status == .ready, output != nil {
                Button("Accept All") {
                    Task { await acceptAll() }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 6)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
            }
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle:
            idleState
        case .running:
            runningState
        case .ready:
            if let output = output {
                outputView(output)
            } else {
                Text("No output.").foregroundStyle(CosmoColors.textTertiary)
            }
        case .failed:
            failedState
        case .applied(let summary):
            appliedState(summary)
        }
    }

    private var idleState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(DS.accent.opacity(0.7))
            Text("Crystallize this session")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Cosmo will read your captures, extracts, and AI conversations and propose lexicon entries, new questions, model updates, and outputs. You approve what matters.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                Task { await runCrystallization() }
            } label: {
                Text("Crystallize Session")
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space20)
                    .padding(.vertical, 10)
                    .background(DS.accent, in: Capsule())
                    .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningState: some View {
        VStack(spacing: DS.space12) {
            ProgressView()
                .controlSize(.large)
            Text(statusMessage.isEmpty ? "Reading session…" : statusMessage)
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(DS.orange)
            Text("Crystallization failed")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text(statusMessage)
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Try again") { Task { await runCrystallization() } }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 6)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appliedState(_ summary: InquiryCrystallizationEngine.AppliedSummary) -> some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(DS.green)
            Text("Crystallized")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                if summary.lexiconCreated > 0 { line("\(summary.lexiconCreated) lexicon entries") }
                if summary.questionsCreated > 0 { line("\(summary.questionsCreated) new questions") }
                if summary.modelUpdatesApplied > 0 { line("\(summary.modelUpdatesApplied) model updates") }
                if summary.outputAnglesAdded > 0 { line("\(summary.outputAnglesAdded) output angles") }
            }
            .padding(DS.space16)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            Text("Session marked crystallized. The Deep Dive Overview reflects the changes.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func line(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.green)
            Text(text)
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textPrimary)
        }
    }

    // MARK: - Output sections

    private func outputView(_ out: CrystallizationOutput) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                if !out.summary.isEmpty {
                    summarySection(out.summary)
                }
                if !out.lexiconCandidates.isEmpty {
                    lexiconSection
                }
                if !out.newQuestions.isEmpty {
                    questionsSection
                }
                if !out.possibleConnections.isEmpty {
                    connectionsSection
                }
                if !out.modelUpdates.isEmpty {
                    modelUpdatesSection
                }
                if !out.contradictions.isEmpty {
                    contradictionsSection(out.contradictions)
                }
                if !out.openLoops.isEmpty {
                    openLoopsSection(out.openLoops)
                }
                if !out.outputCandidates.isEmpty {
                    outputCandidatesSection
                }
                Spacer(minLength: DS.space40)
            }
            .padding(.horizontal, DS.space40)
            .padding(.vertical, DS.space20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("SUMMARY")
            Text(summary)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
                .lineSpacing(6)
        }
    }

    private var lexiconSection: some View {
        sectionFrame(title: "NEW LEXICON ENTRIES (\(output?.lexiconCandidates.count ?? 0))") {
            ForEach(Array((output?.lexiconCandidates ?? []).enumerated()), id: \.element.id) { idx, candidate in
                acceptableRow(
                    title: candidate.term,
                    detail: candidate.definition.isEmpty ? "—" : candidate.definition,
                    meta: "\(candidate.mentionCount) mention\(candidate.mentionCount == 1 ? "" : "s")",
                    accepted: candidate.accepted,
                    onToggle: { toggleLexicon(at: idx) }
                )
            }
        }
    }

    private var questionsSection: some View {
        sectionFrame(title: "NEW QUESTIONS (\(output?.newQuestions.count ?? 0))") {
            ForEach(Array((output?.newQuestions ?? []).enumerated()), id: \.element.id) { idx, q in
                acceptableRow(
                    title: q.text,
                    detail: q.rationale ?? "",
                    meta: nil,
                    accepted: q.accepted,
                    onToggle: { toggleQuestion(at: idx) }
                )
            }
        }
    }

    private var connectionsSection: some View {
        sectionFrame(title: "POSSIBLE CONNECTIONS (\(output?.possibleConnections.count ?? 0))") {
            ForEach(Array((output?.possibleConnections ?? []).enumerated()), id: \.element.id) { _, c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name)
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textPrimary)
                    if let r = c.rationale {
                        Text(r)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textSecondary)
                    }
                    Text("Promotion to Connection ships in Phase 8.")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
                .padding(DS.space10)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            }
        }
    }

    private var modelUpdatesSection: some View {
        sectionFrame(title: "MODEL UPDATES (\(output?.modelUpdates.count ?? 0))") {
            ForEach(Array((output?.modelUpdates ?? []).enumerated()), id: \.element.id) { idx, update in
                modelUpdateRow(update, idx: idx)
            }
        }
    }

    private func modelUpdateRow(_ update: CrystallizationOutput.ModelUpdateProposal, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(update.kind.rawValue.capitalized)
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Before:")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                Text(update.before)
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .padding(.bottom, 2)
                Text("After:")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                Text(update.after)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(CosmoColors.textPrimary)
            }
            if let r = update.rationale {
                Text(r)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .padding(.top, 2)
            }
            HStack {
                Spacer()
                acceptToggleButton(accepted: update.accepted) { toggleModelUpdate(at: idx) }
            }
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private func contradictionsSection(_ items: [CrystallizationOutput.ContradictionAlert]) -> some View {
        sectionFrame(title: "CONTRADICTIONS (\(items.count))") {
            ForEach(items, id: \.id) { c in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.orange)
                    Text(c.description)
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textPrimary)
                }
            }
        }
    }

    private func openLoopsSection(_ items: [CrystallizationOutput.OpenLoop]) -> some View {
        sectionFrame(title: "OPEN LOOPS (\(items.count))") {
            ForEach(items, id: \.id) { loop in
                VStack(alignment: .leading, spacing: 2) {
                    Text("· \(loop.description)")
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textPrimary)
                    if let next = loop.suggestedNextStep {
                        Text("Next: \(next)")
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                }
            }
        }
    }

    private var outputCandidatesSection: some View {
        sectionFrame(title: "OUTPUT CANDIDATES (\(output?.outputCandidates.count ?? 0))") {
            ForEach(Array((output?.outputCandidates ?? []).enumerated()), id: \.element.id) { idx, o in
                acceptableRow(
                    title: o.title,
                    detail: o.rationale ?? "",
                    meta: o.format,
                    accepted: o.accepted,
                    onToggle: { toggleOutput(at: idx) }
                )
            }
        }
    }

    // MARK: - Row helpers

    private func acceptableRow(title: String, detail: String, meta: String?, accepted: Bool, onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textPrimary)
                Spacer()
                if let m = meta {
                    Text(m)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
            }
            HStack {
                Spacer()
                acceptToggleButton(accepted: accepted, onToggle: onToggle)
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private func acceptToggleButton(accepted: Bool, onToggle: @escaping () -> Void) -> some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(accepted ? "Accepted" : "Accept")
                    .font(CosmoTypography.caption)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(accepted ? DS.accent : Color.clear, in: Capsule())
            .foregroundStyle(accepted ? DS.textOnAccent : DS.accent)
            .overlay(Capsule().stroke(DS.accent.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .tracking(2)
            .foregroundStyle(CosmoColors.textSecondary.opacity(0.78))
    }

    @ViewBuilder
    private func sectionFrame<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionLabel(title)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }

    // MARK: - Toggles

    private func toggleLexicon(at idx: Int) {
        guard var out = output, out.lexiconCandidates.indices.contains(idx) else { return }
        out.lexiconCandidates[idx].accepted.toggle()
        output = out
    }

    private func toggleQuestion(at idx: Int) {
        guard var out = output, out.newQuestions.indices.contains(idx) else { return }
        out.newQuestions[idx].accepted.toggle()
        output = out
    }

    private func toggleModelUpdate(at idx: Int) {
        guard var out = output, out.modelUpdates.indices.contains(idx) else { return }
        out.modelUpdates[idx].accepted.toggle()
        output = out
    }

    private func toggleOutput(at idx: Int) {
        guard var out = output, out.outputCandidates.indices.contains(idx) else { return }
        out.outputCandidates[idx].accepted.toggle()
        output = out
    }

    // MARK: - Run / Apply

    private func runCrystallization() async {
        status = .running
        statusMessage = "Reading session…"
        let session = viewModel.session
        let dd = viewModel.deepDive
        let extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: dd?.uuid ?? "")) ?? []
        let sessionExtracts = extracts.filter { $0.extractMetadata?.parentSessionUUID == session.uuid }

        do {
            statusMessage = "Synthesizing…"
            let out = try await InquiryCrystallizationEngine.shared.crystallize(
                session: session,
                deepDive: dd,
                allExtracts: sessionExtracts
            )
            // Pre-accept everything by default ("Accept All" is the disciplined default)
            var preAccepted = out
            for i in preAccepted.lexiconCandidates.indices { preAccepted.lexiconCandidates[i].accepted = true }
            for i in preAccepted.newQuestions.indices { preAccepted.newQuestions[i].accepted = true }
            for i in preAccepted.modelUpdates.indices { preAccepted.modelUpdates[i].accepted = true }
            for i in preAccepted.outputCandidates.indices { preAccepted.outputCandidates[i].accepted = true }
            output = preAccepted
            status = .ready
        } catch {
            statusMessage = error.localizedDescription
            status = .failed
        }
    }

    private func acceptAll() async {
        guard let out = output else { return }
        do {
            let summary = try await InquiryCrystallizationEngine.shared.applyAcceptedOutput(
                out,
                toSession: viewModel.session,
                deepDive: viewModel.deepDive
            )
            // Persist crystallization result on session
            let summaryText = out.summary
            _ = try await InquiryRepository.shared.completeCrystallization(viewModel.session, output: out, summary: summaryText)
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.sessionCrystallized,
                object: nil,
                userInfo: ["sessionUUID": viewModel.session.uuid]
            )
            status = .applied(summary)
        } catch {
            statusMessage = error.localizedDescription
            status = .failed
        }
    }

    enum ReviewStatus: Equatable {
        case idle
        case running
        case ready
        case failed
        case applied(InquiryCrystallizationEngine.AppliedSummary)

        static func == (lhs: ReviewStatus, rhs: ReviewStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.running, .running), (.ready, .ready), (.failed, .failed): return true
            case (.applied, .applied): return true
            default: return false
            }
        }
    }
}
