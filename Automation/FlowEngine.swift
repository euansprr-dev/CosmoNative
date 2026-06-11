// CosmoOS/Automation/FlowEngine.swift
// Executes a flow's verb over its cluster's atoms and writes the ledger.
// Manual runs only in this phase — arrival triggers compile to AutomationRule
// in the next phase, keeping the rules engine the single source of behavior.

import Foundation
import GRDB

// MARK: - Ledger record

struct FlowFiringRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "flow_firings"

    var uuid: String
    var flowUUID: String
    var thinkspaceId: String?
    var summary: String
    var outputAtomUUID: String?
    var createdAt: String
}

// MARK: - Engine

@MainActor
enum FlowEngine {

    enum FlowError: LocalizedError {
        case emptyCluster

        var errorDescription: String? {
            switch self {
            case .emptyCluster: return "This cluster has no readable content yet."
            }
        }
    }

    struct RunResult {
        let outputAtom: Atom
        let summary: String
    }

    /// Run a flow over its cluster: gather atoms → execute the verb →
    /// create the output atom (linked to every source) → write the ledger.
    static func run(_ flow: CanvasFlow, cluster: CanvasCluster, thinkspaceId: String?) async throws -> RunResult {
        let result = try await execute(
            verb: flow.verb,
            clusterName: cluster.name,
            blockUUIDs: cluster.blockUUIDs
        )
        await recordFiring(
            flowUUID: flow.uuid,
            thinkspaceId: thinkspaceId,
            summary: result.summary,
            outputAtomUUID: result.outputAtom.uuid
        )
        return result
    }

    /// Autonomous run, invoked by the automation engine (arrival/schedule
    /// rules). Loads everything from persistence — no canvas required — and
    /// stages the output as a proposal: autonomous flows never place blocks
    /// without approval.
    static func runHeadless(flowUUID: String, thinkspaceId: String) async {
        var flows = await ThinkspaceManager.shared.flows(for: thinkspaceId)
        guard let index = flows.firstIndex(where: { $0.uuid == flowUUID }) else { return }
        let flow = flows[index]

        // One proposal at a time — don't stack outputs the user hasn't seen.
        guard flow.runMode != .manual, flow.pendingOutputAtomUUID == nil else { return }

        guard let atom = try? await AtomRepository.shared.fetch(uuid: thinkspaceId),
              let metadata = atom.metadataValue(as: ThinkspaceMetadata.self),
              let cluster = metadata.clusters.first(where: { $0.id == flow.sourceClusterId }) else { return }

        do {
            let result = try await execute(
                verb: flow.verb,
                clusterName: cluster.name,
                blockUUIDs: cluster.blockUUIDs
            )
            await recordFiring(
                flowUUID: flow.uuid,
                thinkspaceId: thinkspaceId,
                summary: result.summary + " · awaiting approval",
                outputAtomUUID: result.outputAtom.uuid
            )

            flows[index].pendingOutputAtomUUID = result.outputAtom.uuid
            flows[index].lastRunAt = Date()
            flows[index].runCount += 1
            await ThinkspaceManager.shared.saveFlows(flows, for: thinkspaceId)

            NotificationCenter.default.post(
                name: CosmoNotification.Automation.flowDidRun,
                object: nil,
                userInfo: [
                    "flowUUID": flow.uuid,
                    "thinkspaceId": thinkspaceId,
                    "outputAtomUUID": result.outputAtom.uuid
                ]
            )
        } catch {
            print("❌ Headless flow run failed: \(error)")
        }
    }

    /// The shared core: verb over sources → output atom + ledger summary.
    static func execute(verb: FlowVerb, clusterName: String, blockUUIDs: [String]) async throws -> RunResult {
        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: blockUUIDs)) ?? []
        let sources = atoms.filter {
            !($0.title ?? "").isEmpty || !($0.body ?? "").isEmpty
        }
        guard !sources.isEmpty else { throw FlowError.emptyCluster }

        let prompt = prompt(for: verb, clusterName: clusterName, sources: sources)
        let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // First line is the title (the prompts enforce this); rest is the body.
        let lines = response.components(separatedBy: "\n")
        let title = lines.first?
            .replacingOccurrences(of: "Title:", with: "")
            .trimmingCharacters(in: .whitespaces) ?? clusterName
        let body = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let links = sources.map { source in
            AtomLink(
                type: "distilled_from",
                uuid: source.uuid,
                entityType: source.type.rawValue
            )
        }

        let atom = Atom.new(
            type: verb.outputAtomType,
            title: title,
            body: body,
            links: links
        )
        let created = try await AtomRepository.shared.create(atom)

        let summary: String
        switch verb {
        case .distill:
            summary = "Distilled \(sources.count) blocks → \(title)"
        case .draft:
            summary = "Drafted \(title) from \(sources.count) blocks"
        }
        return RunResult(outputAtom: created, summary: summary)
    }

    // MARK: Ledger

    private static func recordFiring(flowUUID: String, thinkspaceId: String?, summary: String, outputAtomUUID: String?) async {
        let record = FlowFiringRecord(
            uuid: UUID().uuidString,
            flowUUID: flowUUID,
            thinkspaceId: thinkspaceId,
            summary: summary,
            outputAtomUUID: outputAtomUUID,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try? await CosmoDatabase.shared.asyncWrite { db in
            try record.insert(db)
        }
    }

    static func recentFirings(flowUUID: String, limit: Int = 5) async -> [FlowFiringRecord] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            try FlowFiringRecord
                .filter(Column("flowUUID") == flowUUID)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    // MARK: Prompts
    // Teach the whole job: grounding discipline, structure, output markers.

    private static func sourcesBlock(_ sources: [Atom]) -> String {
        sources.enumerated().map { index, atom in
            """
            SOURCE \(index + 1) — "\(atom.title ?? "Untitled")":
            \(String((atom.body ?? "").prefix(2400)))
            """
        }.joined(separator: "\n\n")
    }

    private static func prompt(for verb: FlowVerb, clusterName: String, sources: [Atom]) -> String {
        let shared = """
        You are synthesizing a cluster of a researcher's own notes called \
        "\(clusterName)". Stay strictly grounded in the sources below — never \
        invent a claim, statistic, or example that is not in them. Plain text \
        only, no markdown symbols.

        \(sourcesBlock(sources))
        """

        switch verb {
        case .distill:
            return shared + """


            TASK: Distill this cluster into one tight, sourced note.

            STRUCTURE — follow exactly:
            1. First line: a title of ≤8 words naming the cluster's core insight. \
            No prefix, just the title.
            2. Blank line, then a 2–3 sentence thesis: what these sources add up \
            to, stated as a position, not a topic.
            3. Then 3–6 claims, one per line, each starting with "• " and ending \
            with the attribution " — from <source title>". Each claim must be \
            specific enough to act on or argue with.
            4. End with "Open questions:" followed by 1–3 lines starting with \
            "• " — the gaps these sources leave.
            """

        case .draft:
            return shared + """


            TASK: Turn this cluster into a publishable first draft.

            STRUCTURE — follow exactly:
            1. First line: a working title of ≤10 words stating the concrete \
            payoff. No prefix, just the title.
            2. Blank line, then the draft: hook-first opening (2–3 sentences \
            that name the reader's problem and the insight coming), then short \
            sections that each carry ONE point from the sources with its \
            specific detail, then a closing takeaway with one next action.
            3. 400–700 words. Direct voice, short paragraphs, no hype words.
            """
        }
    }
}
