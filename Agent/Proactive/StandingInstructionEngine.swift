// CosmoOS/Agent/Proactive/StandingInstructionEngine.swift
// Manages recurring standing instructions ("every day at 9am, give me 3 hooks")

import Foundation

@MainActor
class StandingInstructionEngine {
    static let shared = StandingInstructionEngine()

    private let atomRepo = AtomRepository.shared

    /// Maximum standing instructions per user (cost control)
    private let maxInstructions = 20

    private init() {}

    // MARK: - CRUD

    /// Add a new standing instruction. Stored as `.agentLearning` atom with subtype "standing_instruction".
    func addInstruction(
        body: String,
        schedule: String,
        hour: Int,
        minute: Int,
        days: [Int]? = nil,
        intervalMinutes: Int? = nil,
        dayOfMonth: Int? = nil
    ) async throws -> String {
        // Check max limit
        let existing = try await fetchAll()
        guard existing.count < maxInstructions else {
            return "{\"error\": \"Maximum \(maxInstructions) standing instructions allowed. Remove one first.\"}"
        }

        // Enforce minimum interval of 30 minutes
        if schedule == "interval" {
            let interval = intervalMinutes ?? 60
            if interval < 30 {
                return "{\"error\": \"Minimum interval is 30 minutes.\"}"
            }
        }

        var metaDict: [String: Any] = [
            "subtype": "standing_instruction",
            "schedule": schedule,
            "hour": hour,
            "minute": minute,
            "enabled": true,
            "lastExecutedAt": "",
            "executionHistory": [] as [[String: Any]]
        ]

        if let days = days { metaDict["days"] = days }
        if let intervalMinutes = intervalMinutes { metaDict["intervalMinutes"] = max(30, intervalMinutes) }
        if let dayOfMonth = dayOfMonth { metaDict["dayOfMonth"] = dayOfMonth }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        let atom = try await atomRepo.create(
            type: .agentLearning,
            title: "standing_instruction",
            body: body,
            metadata: metaJSON
        )

        return "{\"success\": true, \"uuid\": \"\(atom.uuid)\", \"message\": \"Standing instruction created: \(body.prefix(80))\"}"
    }

    /// List all standing instructions.
    func listInstructions() async throws -> [[String: Any]] {
        let instructions = try await fetchAll()
        return instructions.map { atom in
            let meta = atom.metadataDict ?? [:]
            var result: [String: Any] = [
                "uuid": atom.uuid,
                "body": atom.body ?? "",
                "schedule": meta["schedule"] as? String ?? "daily",
                "hour": meta["hour"] as? Int ?? 9,
                "minute": meta["minute"] as? Int ?? 0,
                "enabled": meta["enabled"] as? Bool ?? true,
                "lastExecutedAt": meta["lastExecutedAt"] as? String ?? ""
            ]
            if let days = meta["days"] as? [Int] { result["days"] = days }
            if let interval = meta["intervalMinutes"] as? Int { result["intervalMinutes"] = interval }
            if let dayOfMonth = meta["dayOfMonth"] as? Int { result["dayOfMonth"] = dayOfMonth }
            let history = meta["executionHistory"] as? [[String: Any]] ?? []
            result["executionCount"] = history.count
            return result
        }
    }

    /// Remove a standing instruction by UUID.
    func removeInstruction(uuid: String) async throws -> String {
        try await atomRepo.delete(uuid: uuid)
        return "{\"success\": true, \"message\": \"Standing instruction removed\"}"
    }

    /// Update an existing standing instruction's fields.
    func updateInstruction(
        uuid: String,
        body: String? = nil,
        schedule: String? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        enabled: Bool? = nil,
        days: [Int]? = nil,
        intervalMinutes: Int? = nil,
        dayOfMonth: Int? = nil
    ) async throws -> String {
        guard (try? await atomRepo.fetch(uuid: uuid)) != nil else {
            return "{\"error\": \"Standing instruction not found\"}"
        }

        // Enforce minimum interval
        if let interval = intervalMinutes, interval < 30 {
            return "{\"error\": \"Minimum interval is 30 minutes.\"}"
        }

        _ = try await atomRepo.update(uuid: uuid) { mutableAtom in
            if let body = body { mutableAtom.body = body }

            var metaDict = mutableAtom.metadataDict ?? [:]
            if let schedule = schedule { metaDict["schedule"] = schedule }
            if let hour = hour { metaDict["hour"] = hour }
            if let minute = minute { metaDict["minute"] = minute }
            if let enabled = enabled { metaDict["enabled"] = enabled }
            if let days = days { metaDict["days"] = days }
            if let intervalMinutes = intervalMinutes { metaDict["intervalMinutes"] = max(30, intervalMinutes) }
            if let dayOfMonth = dayOfMonth { metaDict["dayOfMonth"] = dayOfMonth }

            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                mutableAtom.metadata = json
            }
        }

        return "{\"success\": true, \"message\": \"Standing instruction updated\"}"
    }

    /// Get execution history for a standing instruction.
    func getExecutionHistory(uuid: String) async throws -> [[String: Any]] {
        guard let atom = try? await atomRepo.fetch(uuid: uuid) else { return [] }
        let meta = atom.metadataDict ?? [:]
        return meta["executionHistory"] as? [[String: Any]] ?? []
    }

    // MARK: - Helpers

    /// Fetch all standing instruction atoms.
    func fetchAll() async throws -> [Atom] {
        let learningAtoms = try await atomRepo.fetchAll(type: .agentLearning)
        return learningAtoms.filter { atom in
            let meta = atom.metadataDict ?? [:]
            return meta["subtype"] as? String == "standing_instruction"
        }
    }
}
