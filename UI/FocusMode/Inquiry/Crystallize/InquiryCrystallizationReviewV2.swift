// CosmoOS/UI/FocusMode/Inquiry/Crystallize/InquiryCrystallizationReviewV2.swift
// Branch-to-Concept review for Inquiry crystallization. Editorial takeover,
// not a utility modal: the run starts on arrival, draft cards cascade in,
// selection is a checkmark, and one sticky bar holds the single primary action.

import SwiftUI

@MainActor
struct InquiryCrystallizationReviewV2: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    var onDismiss: () -> Void = {}

    @State private var output: CrystallizationOutput?
    @State private var status: Status = .idle
    @State private var statusMessage: String = ""
    @State private var promotionResult: ConnectionPromotionResult?
    @State private var existingPages: [ConnectionDraftCard.PageRef] = []
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            masthead
            content
            if status == .ready, !candidates.isEmpty {
                actionBar
            }
        }
        // The review IS the crystallization — arriving here starts the run.
        .task {
            guard status == .idle else { return }
            await runCrystallization()
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Explore")
                        .font(CosmoTypography.label)
                }
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Explore")

            VStack(alignment: .leading, spacing: 2) {
                Text("Crystallize")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(CosmoColors.textPrimary)
                Text(mastheadSubtitle)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    private var mastheadSubtitle: String {
        switch status {
        case .idle, .running:
            return "Reading the session…"
        case .ready:
            let count = candidates.count
            guard count > 0 else { return "Nothing new to crystallize yet." }
            return "\(count) branch\(count == 1 ? "" : "es") ready to become Concept\(count == 1 ? "" : "s") — review, then promote."
        case .failed:
            return "The run hit a problem."
        case .applied:
            return "This session's knowledge is now first-class."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle, .running:
            runningState
        case .ready:
            reviewState
        case .failed:
            failedState
        case .applied:
            appliedState
        }
    }

    private var runningState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.accent.opacity(0.7))
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
            Text(statusMessage.isEmpty ? "Routing branches…" : statusMessage)
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(DS.orange)
                .accessibilityHidden(true)
            Text("Crystallization failed")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text(statusMessage)
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Try again") {
                Task { await runCrystallization() }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, 6)
            .background(DS.accent, in: Capsule())
            .foregroundStyle(DS.textOnAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                if candidates.isEmpty {
                    emptyCandidates
                } else {
                    ForEach(candidateBindings.indices, id: \.self) { index in
                        ConnectionDraftCard(
                            candidate: candidateBindings[index],
                            existingPages: existingPages,
                            otherDrafts: otherDrafts(excluding: candidates[index].id),
                            onFoldInto: { targetId in
                                foldCandidate(candidates[index].id, into: targetId)
                            }
                        )
                        .studyCascade(hasAppeared, index: index)
                    }
                }

                if let output, hasSupportingOutput(output) {
                    supportingOutput(output)
                        .studyCascade(hasAppeared, index: candidates.count)
                }
            }
            .padding(.horizontal, DS.space32)
            .padding(.vertical, DS.space20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Sticky action bar

    private var actionBar: some View {
        HStack(spacing: DS.space12) {
            Button("Skip all") {
                skipAll()
            }
            .buttonStyle(.plain)
            .font(CosmoTypography.label)
            .foregroundStyle(CosmoColors.textSecondary)
            .accessibilityLabel("Skip all drafts")

            Spacer()

            Text(selectionSummary)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .contentTransition(.numericText())

            Button {
                Task {
                    if let output {
                        await apply(output)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(promoteButtonTitle)
                        .font(CosmoTypography.label)
                }
                .padding(.horizontal, DS.space16)
                .padding(.vertical, 8)
                .background(acceptedCount == 0 ? DS.surfaceHover : DS.accent, in: Capsule())
                .foregroundStyle(acceptedCount == 0 ? CosmoColors.textTertiary : DS.textOnAccent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(acceptedCount == 0)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel(promoteButtonTitle)
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(DS.borderSubtle)
        }
    }

    private var acceptedCount: Int {
        candidates.filter(\.accepted).count
    }

    private var promoteButtonTitle: String {
        acceptedCount == 0
            ? "Promote"
            : "Promote \(acceptedCount) Concept\(acceptedCount == 1 ? "" : "s")"
    }

    private var selectionSummary: String {
        let total = candidates.count
        guard total > 0 else { return "" }
        return "\(acceptedCount) of \(total) selected"
    }

    private var appliedState: some View {
        VStack(spacing: DS.space16) {
            CrystallizedSeal()
            Text("Concepts crystallized")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(CosmoColors.textPrimary)
            if let promotionResult {
                VStack(alignment: .leading, spacing: 5) {
                    resultLine("\(promotionResult.created) Concepts created")
                    resultLine("\(promotionResult.updated) Concepts updated")
                    resultLine("\(promotionResult.linked) links added")
                    resultLine("\(promotionResult.canvasBlocksCreated) canvas blocks placed")
                }
                .padding(DS.space16)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            }
            Text("Accepted branch drafts are now first-class Concepts in the Library and on the canvas.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Back to Explore") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(CosmoTypography.label)
            .foregroundStyle(DS.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCandidates: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("No branch has enough routed material yet.")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Capture at least three claims, evidence items, practices, examples, or questions on a branch, then crystallize again.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .padding(DS.space20)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
    }

    private func supportingOutput(_ output: CrystallizationOutput) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Also riding this crystallization")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
            HStack(spacing: DS.space8) {
                if !output.lexiconCandidates.isEmpty { chip("\(output.lexiconCandidates.count) lexicon") }
                if !output.newQuestions.isEmpty { chip("\(output.newQuestions.count) questions") }
                if !output.modelUpdates.isEmpty { chip("\(output.modelUpdates.count) model updates") }
                if !output.outputCandidates.isEmpty { chip("\(output.outputCandidates.count) outputs") }
            }
        }
        .padding(DS.space16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
    }

    // MARK: - Run + apply

    private func runCrystallization() async {
        status = .running
        hasAppeared = false
        statusMessage = "Reading the session…"
        let session = viewModel.session
        let dd = viewModel.deepDive
        let extracts = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: dd?.uuid ?? "")) ?? []
        // Incremental: material already crystallized into Connections stays out
        // of the next run — only new captures since the last crystallization count.
        let sessionExtracts = extracts.filter {
            $0.extractMetadata?.parentSessionUUID == session.uuid
                && $0.extractMetadata?.status != .promoted
        }

        do {
            statusMessage = "Routing branches…"
            var crystallized = try await InquiryCrystallizationEngine.shared.crystallize(
                session: session,
                deepDive: dd,
                allExtracts: sessionExtracts
            )
            for i in crystallized.lexiconCandidates.indices { crystallized.lexiconCandidates[i].accepted = true }
            for i in crystallized.newQuestions.indices { crystallized.newQuestions[i].accepted = true }
            for i in crystallized.modelUpdates.indices { crystallized.modelUpdates[i].accepted = true }
            for i in crystallized.outputCandidates.indices { crystallized.outputCandidates[i].accepted = true }
            // Substantial drafts start selected — reviewing means deselecting
            // the ones you don't want, not re-approving every card.
            for i in crystallized.possibleConnections.indices
            where crystallized.possibleConnections[i].materialCount >= 3 {
                crystallized.possibleConnections[i].accepted = true
            }
            output = crystallized
            if let dd {
                let connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: dd)) ?? []
                existingPages = connections.compactMap { atom in
                    guard let title = atom.title, !title.isEmpty else { return nil }
                    return ConnectionDraftCard.PageRef(id: atom.uuid, title: title)
                }
            }
            status = .ready
            try? await Task.sleep(for: .milliseconds(16))
            hasAppeared = true
        } catch {
            statusMessage = error.localizedDescription
            status = .failed
        }
    }

    private func otherDrafts(excluding candidateId: String) -> [ConnectionDraftCard.PageRef] {
        candidates
            .filter { $0.id != candidateId && $0.accepted }
            .map { ConnectionDraftCard.PageRef(id: $0.id, title: $0.proposedTitle) }
    }

    /// Folds one draft's material into another: real items (extract-backed or
    /// source-backed) move over, deduped by origin extract; the source draft
    /// un-accepts so nothing promotes twice.
    private func foldCandidate(_ sourceId: String, into targetId: String) {
        guard var current = output,
              let sourceIdx = current.possibleConnections.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = current.possibleConnections.firstIndex(where: { $0.id == targetId }),
              sourceIdx != targetIdx else { return }
        var target = current.possibleConnections[targetIdx]
        let source = current.possibleConnections[sourceIdx]

        let knownOrigins = Set(target.proposedSections.values.flatMap { $0 }.compactMap(\.originExtractUUID))
        for (type, drafts) in source.proposedSections where type != .goal && type != .conceptName {
            let material = drafts.filter { draft in
                guard draft.originExtractUUID != nil || draft.sourceUUID != nil else { return false }
                guard let origin = draft.originExtractUUID else { return true }
                return !knownOrigins.contains(origin)
            }
            guard !material.isEmpty else { continue }
            target.proposedSections[type, default: []] += material
        }
        let knownExtracts = Set(target.clusterExtractUUIDs)
        target.clusterExtractUUIDs += source.clusterExtractUUIDs.filter { !knownExtracts.contains($0) }
        target.proposedNotes += source.proposedNotes
        target.materialCount = target.proposedSections.values.reduce(0) { $0 + $1.count }
        var related = target.relatedConceptNames ?? []
        for name in source.relatedConceptNames ?? [] where !related.contains(name) && name != target.proposedTitle {
            related.append(name)
        }
        target.relatedConceptNames = related.isEmpty ? nil : related

        current.possibleConnections[targetIdx] = target
        current.possibleConnections[sourceIdx].accepted = false
        output = current
    }

    private func apply(_ current: CrystallizationOutput) async {
        status = .running
        statusMessage = "Promoting Concepts…"
        do {
            let appliedOutput = current
            let promoted = try await ConnectionPromotionService.shared.applyAcceptedCandidates(
                appliedOutput.possibleConnections,
                session: viewModel.session,
                deepDive: viewModel.deepDive
            )
            promotionResult = promoted
            _ = try await InquiryCrystallizationEngine.shared.applyAcceptedOutput(
                appliedOutput,
                toSession: viewModel.session,
                deepDive: viewModel.deepDive
            )
            _ = try await InquiryRepository.shared.completeCrystallization(
                viewModel.session,
                output: appliedOutput,
                summary: appliedOutput.summary
            )
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.sessionCrystallized,
                object: nil,
                userInfo: ["sessionUUID": viewModel.session.uuid]
            )
            output = appliedOutput
            status = .applied
        } catch {
            statusMessage = error.localizedDescription
            status = .failed
        }
    }

    private func skipAll() {
        guard var current = output else { return }
        for index in current.possibleConnections.indices {
            current.possibleConnections[index].accepted = false
        }
        output = current
    }

    private var candidates: [CrystallizationOutput.ConnectionCandidate] {
        output?.possibleConnections ?? []
    }

    private var candidateBindings: [Binding<CrystallizationOutput.ConnectionCandidate>] {
        guard let count = output?.possibleConnections.count else { return [] }
        return (0..<count).map { index in
            Binding(
                get: { self.output?.possibleConnections[index] ?? CrystallizationOutput.ConnectionCandidate(name: "Untitled") },
                set: { self.output?.possibleConnections[index] = $0 }
            )
        }
    }

    private func hasSupportingOutput(_ output: CrystallizationOutput) -> Bool {
        !output.lexiconCandidates.isEmpty
            || !output.newQuestions.isEmpty
            || !output.modelUpdates.isEmpty
            || !output.outputCandidates.isEmpty
    }

    private func resultLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.green)
                .accessibilityHidden(true)
            Text(text)
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textPrimary)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.caption)
            .foregroundStyle(CosmoColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.surfaceElevated, in: Capsule())
    }

    private enum Status: Equatable {
        case idle
        case running
        case ready
        case failed
        case applied
    }
}

// MARK: - The earned delight

/// The workspace's one custom moment: knowledge crystallizing. The seal
/// springs in and a gilt ring flares once — then everything is still again.
/// Reduce Motion gets a plain fade.
@MainActor
private struct CrystallizedSeal: View {
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.gilt.opacity(arrived ? 0 : 0.55), lineWidth: 2)
                .frame(width: 56, height: 56)
                .scaleEffect(arrived ? 1.7 : 0.8)
                .accessibilityHidden(true)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(DS.green)
                .scaleEffect(arrived || reduceMotion ? 1 : 0.6)
                .opacity(arrived ? 1 : 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            guard !reduceMotion else {
                arrived = true
                return
            }
            withAnimation(ProMotionSprings.snappy) { arrived = true }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: arrived)
    }
}
