// CosmoOS/UI/FocusMode/Inquiry/Crystallize/InquiryCrystallizationReviewV2.swift
// Branch-to-Connection review surface for Inquiry crystallization v2.

import SwiftUI

@MainActor
struct InquiryCrystallizationReviewV2: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    @State private var output: CrystallizationOutput?
    @State private var status: Status = .idle
    @State private var statusMessage: String = ""
    @State private var promotionResult: ConnectionPromotionResult?
    @State private var existingPages: [ConnectionDraftCard.PageRef] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(DS.borderSubtle)
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: DS.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Branch to Connection")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(CosmoColors.textPrimary)
                Text("Review each branch draft before it becomes a structured Connection.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
            }
            Spacer()
            if status == .ready {
                Button("Skip all") {
                    skipAll()
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textSecondary)

                Button("Promote selected") {
                    Task {
                        if let output {
                            await apply(output)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .foregroundStyle(DS.accent)

                Button("Accept all") {
                    Task { await acceptAll() }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 7)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
            }
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle:
            idleState
        case .running:
            runningState
        case .ready:
            reviewState
        case .failed:
            failedState
        case .applied:
            appliedState
        }
    }

    private var idleState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.accent.opacity(0.75))
                .accessibilityHidden(true)
            Text("Crystallize branches")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Each branch with enough routed material becomes one Connection draft. Captures stay verbatim inside sections.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
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
            Text(statusMessage.isEmpty ? "Routing branches..." : statusMessage)
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
                    }
                }

                if let output, hasSupportingOutput(output) {
                    supportingOutput(output)
                }
            }
            .padding(.horizontal, DS.space32)
            .padding(.vertical, DS.space20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var appliedState: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(DS.green)
                .accessibilityHidden(true)
            Text("Connections crystallized")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(CosmoColors.textPrimary)
            if let promotionResult {
                VStack(alignment: .leading, spacing: 5) {
                    resultLine("\(promotionResult.created) Connections created")
                    resultLine("\(promotionResult.updated) Connections updated")
                    resultLine("\(promotionResult.linked) links added")
                    resultLine("\(promotionResult.canvasBlocksCreated) canvas blocks placed")
                }
                .padding(DS.space16)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            }
            Text("Accepted branch drafts are now first-class Connections in the Library and on the canvas.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
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
            Text("Other accepted outputs")
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

    private func runCrystallization() async {
        status = .running
        statusMessage = "Reading session..."
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
            statusMessage = "Routing branches..."
            var crystallized = try await InquiryCrystallizationEngine.shared.crystallize(
                session: session,
                deepDive: dd,
                allExtracts: sessionExtracts
            )
            for i in crystallized.lexiconCandidates.indices { crystallized.lexiconCandidates[i].accepted = true }
            for i in crystallized.newQuestions.indices { crystallized.newQuestions[i].accepted = true }
            for i in crystallized.modelUpdates.indices { crystallized.modelUpdates[i].accepted = true }
            for i in crystallized.outputCandidates.indices { crystallized.outputCandidates[i].accepted = true }
            output = crystallized
            if let dd {
                let connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: dd)) ?? []
                existingPages = connections.compactMap { atom in
                    guard let title = atom.title, !title.isEmpty else { return nil }
                    return ConnectionDraftCard.PageRef(id: atom.uuid, title: title)
                }
            }
            status = .ready
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

    private func acceptAll() async {
        guard var current = output else { return }
        for index in current.possibleConnections.indices where current.possibleConnections[index].materialCount >= 3 {
            current.possibleConnections[index].accepted = true
        }
        await apply(current)
    }

    private func apply(_ current: CrystallizationOutput) async {
        status = .running
        statusMessage = "Promoting Connections..."
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
