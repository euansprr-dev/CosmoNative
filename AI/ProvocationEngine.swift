// CosmoOS/AI/ProvocationEngine.swift
// AI devil's advocate — scans canvas blocks for contradictions,
// unexamined assumptions, and missing evidence
// February 2026 — WP7 Provocation Layer

import SwiftUI
import CryptoKit

@MainActor
class ProvocationEngine: ObservableObject {
    static let shared = ProvocationEngine()

    @Published var provocations: [Provocation] = []
    @Published var isScanning = false

    // Cache by content hash to avoid redundant API calls
    private var contentHashCache: [String: [Provocation]] = [:]

    // Challenge intensity setting
    var challengeIntensity: ChallengeIntensity = .balanced
    var isSessionMuted: Bool = false

    enum ChallengeIntensity: String, CaseIterable {
        case gentle
        case balanced
        case aggressive

        var confidenceThreshold: Double {
            switch self {
            case .gentle: return 0.85
            case .balanced: return 0.7
            case .aggressive: return 0.5
            }
        }

        var label: String {
            switch self {
            case .gentle: return "Gentle"
            case .balanced: return "Balanced"
            case .aggressive: return "Aggressive"
            }
        }
    }

    private init() {}

    // MARK: - Scan Blocks

    func scanBlocks(atomUUIDs: [String]) async {
        guard !isSessionMuted else { return }
        guard !atomUUIDs.isEmpty else { return }
        guard !isScanning else { return }

        isScanning = true
        defer { isScanning = false }

        // 1. Load all atoms by UUID
        var atoms: [(uuid: String, title: String, body: String)] = []
        for uuid in atomUUIDs {
            if let atom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                let title = atom.title ?? ""
                let body = atom.body ?? ""
                guard !title.isEmpty || !body.isEmpty else { continue }
                atoms.append((uuid: uuid, title: title, body: body))
            }
        }

        guard atoms.count >= 2 else { return } // Need at least 2 blocks to find tensions

        // 2. Compute content hash
        let contentString = atoms.map { "\($0.title)|\($0.body)" }.joined(separator: "||")
        let hashData = SHA256.hash(data: Data(contentString.utf8))
        let contentHash = hashData.compactMap { String(format: "%02x", $0) }.joined()

        // Check cache
        if let cached = contentHashCache[contentHash] {
            self.provocations = cached
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.provocationScanComplete,
                object: nil
            )
            return
        }

        // 3. Build prompt
        let threshold = challengeIntensity.confidenceThreshold
        var blocksDescription = ""
        for (index, atom) in atoms.enumerated() {
            blocksDescription += """

            [Block \(index + 1) | UUID: \(atom.uuid)]
            Title: \(atom.title)
            Content: \(atom.body.prefix(2000))

            """
        }

        let prompt = """
        Analyze these knowledge blocks for intellectual tensions. Look for:
        1. Contradictions: Two blocks say opposite or conflicting things
        2. Assumptions: A block assumes something without justification
        3. Missing evidence: A block claims something without supporting research
        4. Stale reasoning: A block's argument is based on outdated or questionable premises

        For each tension found, provide:
        - type: one of "contradiction", "assumption", "missingEvidence", "staleReasoning"
        - sourceAtomUUIDs: array of UUIDs of the blocks involved
        - description: clear description of the tension (1-2 sentences)
        - evidenceQuotes: specific text quotes from the blocks that create the tension
        - suggestedResolution: how the user might resolve this tension (1 sentence, or null)
        - confidence: 0-1 score (only report tensions with confidence > \(threshold))
        - severity: 0-1 score of how problematic this tension is

        Respond ONLY with valid JSON in this format (no markdown, no explanation):
        {
          "provocations": [
            {
              "type": "contradiction",
              "sourceAtomUUIDs": ["uuid1", "uuid2"],
              "description": "Block 1 claims X while Block 2 claims the opposite",
              "evidenceQuotes": ["quote from block 1", "quote from block 2"],
              "suggestedResolution": "Consider which claim has stronger evidence",
              "confidence": 0.85,
              "severity": 0.7
            }
          ]
        }

        If no tensions are found above the confidence threshold, return: {"provocations": []}

        Blocks:
        \(blocksDescription)
        """

        // 4. Call ResearchService (Sonnet tier for precision)
        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: "You are an intellectual devil's advocate. Your job is to find genuine tensions, contradictions, and unexamined assumptions in knowledge blocks. Be precise — false positives are worse than false negatives. Only flag real intellectual tensions.",
                tier: .strategist,
                maxTokens: 4096
            )

            // 5. Parse response
            let parsed = parseProvocations(from: response, threshold: threshold)

            // 6. Cache and store
            contentHashCache[contentHash] = parsed
            self.provocations = parsed

            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.provocationScanComplete,
                object: nil
            )
        } catch {
            print("[ProvocationEngine] Scan failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    func dismiss(provocationId: String) {
        if let index = provocations.firstIndex(where: { $0.id == provocationId }) {
            provocations[index].status = .dismissed
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.provocationDismissed,
                object: nil,
                userInfo: ["provocationId": provocationId]
            )
        }
    }

    func resolve(provocationId: String) {
        if let index = provocations.firstIndex(where: { $0.id == provocationId }) {
            provocations[index].status = .resolved
        }
    }

    func acceptAsTask(provocation: Provocation) async {
        // Create a new task atom from the provocation
        let taskTitle = "Resolve: \(provocation.description)"
        let taskBody = """
        Type: \(provocation.type.label)
        Confidence: \(Int(provocation.confidence * 100))%

        Evidence:
        \(provocation.evidenceQuotes.map { "- \"\($0)\"" }.joined(separator: "\n"))

        \(provocation.suggestedResolution.map { "Suggested resolution: \($0)" } ?? "")
        """

        // Build links to source atoms
        let links = provocation.sourceAtomUUIDs.map { uuid in
            AtomLink(linkType: .related, uuid: uuid)
        }

        do {
            _ = try await AtomRepository.shared.create(
                type: .task,
                title: taskTitle,
                body: taskBody,
                links: links
            )
            resolve(provocationId: provocation.id)
        } catch {
            print("[ProvocationEngine] Failed to create task: \(error.localizedDescription)")
        }
    }

    /// Active (non-dismissed, non-resolved) provocations
    var activeProvocations: [Provocation] {
        provocations.filter { $0.status == .active }
    }

    /// Provocations for a specific block
    func provocations(for atomUUID: String) -> [Provocation] {
        activeProvocations.filter { $0.sourceAtomUUIDs.contains(atomUUID) }
    }

    // MARK: - Parse

    private func parseProvocations(from response: String, threshold: Double) -> [Provocation] {
        // Strip markdown code fences if present
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["provocations"] as? [[String: Any]] else {
            print("[ProvocationEngine] Failed to parse response JSON")
            return []
        }

        let now = ISO8601.string(from: Date())

        return items.compactMap { item -> Provocation? in
            guard let typeStr = item["type"] as? String,
                  let type = Provocation.ProvocationType(rawValue: typeStr),
                  let sourceUUIDs = item["sourceAtomUUIDs"] as? [String],
                  let description = item["description"] as? String,
                  let confidence = item["confidence"] as? Double,
                  confidence >= threshold else { return nil }

            let evidenceQuotes = item["evidenceQuotes"] as? [String] ?? []
            let suggestedResolution = item["suggestedResolution"] as? String
            let severity = item["severity"] as? Double ?? 0.5

            return Provocation(
                id: UUID().uuidString,
                type: type,
                severity: severity,
                sourceAtomUUIDs: sourceUUIDs,
                description: description,
                evidenceQuotes: evidenceQuotes,
                suggestedResolution: suggestedResolution,
                status: .active,
                confidence: confidence,
                createdAt: now
            )
        }
    }
}
