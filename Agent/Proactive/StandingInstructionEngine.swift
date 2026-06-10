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
        guard let atom = try? await atomRepo.fetch(uuid: uuid) else {
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

    // MARK: - Execution Check

    /// Check all standing instructions and execute any that are due.
    /// Called by AgentProactiveScheduler every 5 minutes.
    func checkAndExecuteDue() async {
        guard let chatId = TelegramBridgeService.shared.activeChatId ?? UserDefaults.standard.string(forKey: "agent_telegram_chat_id") else {
            return
        }

        let instructions: [Atom]
        do {
            instructions = try await fetchAll()
        } catch {
            print("[StandingInstructions] Failed to fetch: \(error)")
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStr = ISO8601.string(from: calendar.startOfDay(for: now))
        let isoFormatter = ISO8601DateFormatter()

        for atom in instructions {
            let meta = atom.metadataDict ?? [:]
            guard meta["enabled"] as? Bool ?? true else { continue }

            let schedule = meta["schedule"] as? String ?? "daily"
            let hour = meta["hour"] as? Int ?? 9
            let minute = meta["minute"] as? Int ?? 0
            let lastExecutedAt = meta["lastExecutedAt"] as? String ?? ""

            // Handle "interval" schedule type separately — uses elapsed time, not daily check
            if schedule == "interval" {
                let intervalMinutes = meta["intervalMinutes"] as? Int ?? 60
                let shouldFire: Bool
                if lastExecutedAt.isEmpty {
                    // Never executed — fire if scheduled time has passed today
                    let currentHour = calendar.component(.hour, from: now)
                    let currentMinute = calendar.component(.minute, from: now)
                    shouldFire = currentHour > hour || (currentHour == hour && currentMinute >= minute)
                } else if let lastDate = isoFormatter.date(from: lastExecutedAt) {
                    let elapsed = now.timeIntervalSince(lastDate)
                    shouldFire = elapsed >= Double(intervalMinutes) * 60.0
                } else {
                    shouldFire = false
                }

                if shouldFire {
                    await executeInstruction(atom: atom, chatId: chatId, now: now)
                }
                continue
            }

            // For non-interval schedules, check if already executed today
            if lastExecutedAt.hasPrefix(String(todayStr.prefix(10))) { continue }

            // Check schedule type
            let shouldFireToday: Bool
            switch schedule {
            case "weekday":
                let weekday = calendar.component(.weekday, from: now)
                shouldFireToday = weekday >= 2 && weekday <= 6 // Mon-Fri
            case "weekly":
                let targetDay = meta["day"] as? Int ?? 2 // default Monday (2)
                let weekday = calendar.component(.weekday, from: now)
                shouldFireToday = weekday == targetDay
            case "specific_days":
                let days = meta["days"] as? [Int] ?? []
                let weekday = calendar.component(.weekday, from: now) // 1=Sun..7=Sat
                shouldFireToday = days.contains(weekday)
            case "monthly":
                let targetDay = meta["dayOfMonth"] as? Int ?? 1
                let currentDay = calendar.component(.day, from: now)
                shouldFireToday = currentDay == targetDay
            default: // "daily"
                shouldFireToday = true
            }
            guard shouldFireToday else { continue }

            // Check if the scheduled time has passed
            let currentHour = calendar.component(.hour, from: now)
            let currentMinute = calendar.component(.minute, from: now)
            guard currentHour > hour || (currentHour == hour && currentMinute >= minute) else { continue }

            // Execute the instruction
            await executeInstruction(atom: atom, chatId: chatId, now: now)
        }
    }

    /// Execute a single standing instruction, send result, and update metadata.
    private func executeInstruction(atom: Atom, chatId: String, now: Date) async {
        let instructionBody = atom.body ?? ""
        guard !instructionBody.isEmpty else { return }

        print("[StandingInstructions] Executing: \(instructionBody.prefix(60))")

        // Send typing indicator
        await TelegramBridgeService.shared.sendChatAction(chatId: chatId, action: "typing")

        // Process through agent (simple complexity, skips workflow planner)
        let (response, _) = await CosmoAgentService.shared.processMessage(
            instructionBody,
            conversationId: "standing_\(atom.uuid)",
            source: .telegram
        )

        // Send result to Telegram
        await TelegramBridgeService.shared.sendLongMessage(chatId: chatId, text: response)

        // Update lastExecutedAt and append to execution history
        _ = try? await atomRepo.update(uuid: atom.uuid, updates: { mutableAtom in
            var metaDict = mutableAtom.metadataDict ?? [:]
            metaDict["lastExecutedAt"] = ISO8601.string(from: now)

            // Append execution history entry (capped at 10)
            var history = metaDict["executionHistory"] as? [[String: Any]] ?? []
            let entry: [String: Any] = [
                "timestamp": ISO8601.string(from: now),
                "resultPreview": String(response.prefix(200))
            ]
            history.append(entry)
            if history.count > 10 {
                history = Array(history.suffix(10))
            }
            metaDict["executionHistory"] = history

            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                mutableAtom.metadata = json
            }
        })
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
