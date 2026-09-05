// CosmoOS/Canvas/LiveQueryBlockView.swift
// Canvas block that renders a live query — auto-updating list of matching atoms
// Query predicates stored in block.metadata["liveQuery"] as JSON

import SwiftUI
import GRDB
import Combine

struct LiveQueryBlockView: View {

    let block: CanvasBlock

    @State private var results: [LiveQueryResult] = []
    @State private var isLoading = true
    @State private var queryDescription = ""
    @State private var observation: AnyCancellable?
    @State private var queryConfig: LiveQueryConfig?
    @State private var decodedQuerySource: String?

    /// Decode block.metadata["liveQuery"] only when the JSON string actually
    /// changes — the computed-property version ran JSONDecoder on every read.
    private func refreshQueryConfigIfNeeded() {
        let source = block.metadata["liveQuery"]
        guard source != decodedQuerySource else { return }
        decodedQuerySource = source
        guard let source, let data = source.data(using: .utf8) else {
            queryConfig = nil
            return
        }
        queryConfig = try? JSONDecoder().decode(LiveQueryConfig.self, from: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 12)
            filterSummary
            resultsList
            footerSection
        }
        .frame(width: 280, height: 360)
        .background(DS.vellum)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            GiltCornerBracket()
                .stroke(DS.gilt, lineWidth: 0.8)
                .frame(width: 12, height: 12)
                .padding(7)
                .opacity(0.6)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
        .task {
            await executeQuery()
            startObservation()
        }
        .onDisappear {
            observation?.cancel()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            // Query name
            Text(block.title.isEmpty ? "Live Query" : block.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            // Live indicator
            liveIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DS.green)
                .frame(width: 5, height: 5)
                .overlay(
                    Circle()
                        .fill(DS.green.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .phaseAnimator([false, true]) { content, phase in
                            content
                                .opacity(phase ? 0.0 : 0.6)
                                .scaleEffect(phase ? 1.4 : 1.0)
                        } animation: { _ in
                            .easeInOut(duration: 2.0)
                        }
                )

            Text("Live")
                .font(DS.smallCaps)
                .foregroundStyle(DS.green)
        }
    }

    // MARK: - Filter Summary

    private var filterSummary: some View {
        Group {
            if !queryDescription.isEmpty {
                Text(queryDescription)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if isLoading {
                VStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Querying…")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(DS.gilt.opacity(0.45))

                    Text("NO MATCHES")
                        .dsSmallCapsLabel()

                    Text("widen the query to catch more")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func resultRow(_ result: LiveQueryResult) -> some View {
        HStack(spacing: 8) {
            // Type icon
            Image(cosmo: result.typeIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(result.typeColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                if let status = result.status {
                    Text(status)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 0) {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.surfaceHover.opacity(0.5))
    }

    // MARK: - Query Execution

    private func executeQuery() async {
        refreshQueryConfigIfNeeded()
        guard let config = queryConfig else {
            queryDescription = "No query configured"
            isLoading = false
            return
        }

        queryDescription = config.description

        do {
            var atoms: [Atom]

            if let atomType = config.atomType {
                atoms = try await AtomRepository.shared.fetchAll(type: AtomType(rawValue: atomType) ?? .idea)
            } else {
                atoms = try await AtomRepository.shared.fetchRecent(limit: 100)
            }

            // Apply conditions — build contexts async first, then filter synchronously
            let evaluator = AutomationRuleEvaluator()
            var filteredAtoms: [Atom] = []
            for atom in atoms {
                let context = await AutomationContextBuilder.build(
                    event: AutomationEvent(triggerType: .atomPropertyMatch, atomUUID: atom.uuid),
                    atom: atom,
                    thinkspaceId: nil
                )
                let allMatch = config.conditions.allSatisfy { condition in
                    let rule = AutomationRule.create(
                        name: "query",
                        triggerType: .atomPropertyMatch,
                        conditions: [condition],
                        actions: []
                    )
                    return evaluator.evaluate(rule: rule, context: context)
                }
                if allMatch {
                    filteredAtoms.append(atom)
                }
            }

            results = filteredAtoms.prefix(50).map { atom in
                LiveQueryResult(
                    id: atom.uuid,
                    title: atom.title ?? "(untitled)",
                    typeIcon: atom.cosmoIcon,
                    typeColor: entityColor(for: atom.type),
                    status: extractStatus(from: atom)
                )
            }

            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func startObservation() {
        guard let db = CosmoDatabase.shared.dbPool else { return }

        // Re-run query when the atoms count changes — removeDuplicates drops
        // the bookkeeping writes that leave the count unchanged, debounce
        // coalesces bursts.
        let obs = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM atoms WHERE is_deleted = 0") ?? 0
        }

        observation = obs.publisher(in: db)
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [self] _ in
                    Task { @MainActor in
                        await executeQuery()
                    }
                }
            )
    }

    // MARK: - Helpers

    private func entityColor(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .task: return DS.entityTask
        case .connection: return DS.entityConnection
        case .note: return DS.entityNote
        default: return DS.textMuted
        }
    }

    private func extractStatus(from atom: Atom) -> String? {
        if let meta = atom.ideaMetadata, let status = meta.ideaStatus {
            return status.rawValue
        }
        return nil
    }
}

// MARK: - Data Models

struct LiveQueryResult: Identifiable {
    let id: String
    let title: String
    let typeIcon: CosmoIcon
    let typeColor: Color
    let status: String?
}

struct LiveQueryConfig: Codable, Sendable {
    let name: String?
    let atomType: String?
    let conditions: [AutomationCondition]

    var description: String {
        var parts: [String] = []

        if let type = atomType {
            parts.append(type.capitalized + "s")
        } else {
            parts.append("All atoms")
        }

        for condition in conditions {
            parts.append("\(condition.field.displayName) \(condition.op.displayName) \(condition.value.stringValue ?? "…")")
        }

        return parts.joined(separator: " | ")
    }
}
