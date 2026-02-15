// CosmoOS/Agent/Core/AgentToolExecutor.swift
// Executes agent tools against CosmoOS services

import Foundation

@MainActor
class AgentToolExecutor {
    static let shared = AgentToolExecutor()

    private let atomRepo = AtomRepository.shared

    /// Pending confirmations for Hard tier actions
    var pendingConfirmations: [String: PendingConfirmation] = [:]

    struct PendingConfirmation {
        let toolName: String
        let arguments: [String: Any]
        let description: String
        let createdAt: Date
    }

    private init() {}

    // MARK: - Execute

    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        // Ideas
        case "search_ideas": return try await searchIdeas(arguments)
        case "get_idea": return try await getIdea(arguments)
        case "create_idea": return try await createIdea(arguments)
        case "update_idea": return try await updateIdea(arguments)
        case "activate_idea": return try await activateIdea(arguments)
        // Swipes
        case "search_swipes": return try await searchSwipes(arguments)
        case "get_swipe_analysis": return try await getSwipeAnalysis(arguments)
        case "find_similar_swipes": return try await findSimilarSwipes(arguments)
        case "get_swipe_stats": return try await getSwipeStats(arguments)
        // Content
        case "get_content_pipeline": return try await getContentPipeline(arguments)
        case "advance_pipeline_phase": return try await advancePipelinePhase(arguments)
        case "create_content": return try await createContent(arguments)
        case "get_content": return try await getContent(arguments)
        case "create_thinkspace": return try await createThinkspace(arguments)
        // Plannerum
        case "get_calendar_blocks": return try await getCalendarBlocks(arguments)
        case "create_block": return try await createBlock(arguments)
        case "update_block": return try await updateBlock(arguments)
        case "delete_block": return try await deleteBlock(arguments)
        case "complete_block": return try await completeBlock(arguments)
        case "get_unscheduled_tasks": return try await getUnscheduledTasks(arguments)
        case "create_task": return try await createTask(arguments)
        // Quests
        case "get_quest_status": return try await getQuestStatus(arguments)
        case "complete_quest": return try await completeQuest(arguments)
        // Analytics
        case "get_dimension_xp": return try await getDimensionXP(arguments)
        case "get_streak_data": return try await getStreakData(arguments)
        // Preferences
        case "get_preferences": return try await getPreferences(arguments)
        case "store_preference": return try await storePreference(arguments)
        case "delete_preference": return try await deletePreference(arguments)
        default:
            return jsonError("Unknown tool: \(toolName)")
        }
    }

    // MARK: - Ideas

    private func searchIdeas(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 10

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.idea]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview,
                    "score": result.combinedScore
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            // Fallback to AtomRepository keyword search
            let atoms = try await atomRepo.fetchAll(type: .idea)
            let matching = atoms.filter { atom in
                let title = (atom.title ?? "").lowercased()
                let body = (atom.body ?? "").lowercased()
                let q = query.lowercased()
                return title.contains(q) || body.contains(q)
            }.prefix(limit)

            let items: [[String: Any]] = matching.map { atom in
                [
                    "uuid": atom.uuid,
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200)),
                    "score": 1.0
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        }
    }

    private func getIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Idea not found: \(uuid)")
        }
        return jsonEncode(atomToDict(atom))
    }

    private func createIdea(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String

        let atom = try await atomRepo.create(
            type: .idea,
            title: title,
            body: body
        )
        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": atom.title ?? title,
            "message": "Idea created: \(title)"
        ] as [String: Any])
    }

    private func updateIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            if let title = args["title"] as? String { atom.title = title }
            if let body = args["body"] as? String { atom.body = body }
            if let status = args["status"] as? String {
                // Update idea status in metadata
                var metaDict = (atom.metadataDict ?? [:])
                metaDict["ideaStatus"] = status
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                }
            }
        }) else {
            return jsonError("Idea not found: \(uuid)")
        }
        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "title": updated.title ?? "",
            "message": "Idea updated"
        ] as [String: Any])
    }

    private func activateIdea(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let ideaAtom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Idea not found: \(uuid)")
        }

        // Create content atom linked to the idea
        let contentAtom = try await atomRepo.create(
            type: .content,
            title: ideaAtom.title,
            body: nil,
            metadata: nil,
            links: [AtomLink(type: "ideaToContent", uuid: uuid, entityType: "idea")]
        )

        // Update idea status to activated
        _ = try await atomRepo.update(uuid: uuid, updates: { atom in
            var metaDict = (atom.metadataDict ?? [:])
            metaDict["ideaStatus"] = "activated"
            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        })

        return jsonEncode([
            "success": true,
            "ideaUUID": uuid,
            "contentUUID": contentAtom.uuid,
            "message": "Idea activated and content piece created: \(ideaAtom.title ?? "Untitled")"
        ] as [String: Any])
    }

    // MARK: - Swipes

    private func searchSwipes(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 10

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.swipeFile]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview,
                    "score": result.combinedScore
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            // Fallback to keyword search on research atoms that are swipe files
            let atoms = try await atomRepo.fetchAll(type: .research)
            let swipes = atoms.filter { $0.isSwipeFileAtom }
            let matching = swipes.filter { atom in
                let title = (atom.title ?? "").lowercased()
                let body = (atom.body ?? "").lowercased()
                let q = query.lowercased()
                return title.contains(q) || body.contains(q)
            }.prefix(limit)

            let items: [[String: Any]] = matching.map { atom in
                [
                    "uuid": atom.uuid,
                    "title": atom.title ?? "Untitled",
                    "preview": String((atom.body ?? "").prefix(200)),
                    "score": 1.0
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        }
    }

    private func getSwipeAnalysis(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Swipe file not found: \(uuid)")
        }

        var result = atomToDict(atom)

        // Include swipe analysis from structured field
        if let structured = atom.structured,
           let data = structured.data(using: .utf8),
           let analysis = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result["analysis"] = analysis
        }

        return jsonEncode(result)
    }

    private func findSimilarSwipes(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            return jsonError("Missing required parameter: query")
        }
        let limit = args["limit"] as? Int ?? 5

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: limit,
                entityTypes: [.swipeFile]
            )
            let items: [[String: Any]] = results.map { result in
                [
                    "uuid": result.entityUUID ?? "",
                    "title": result.title,
                    "preview": result.preview,
                    "similarity": result.vectorSimilarity
                ]
            }
            return jsonEncode(["results": items, "count": items.count])
        } catch {
            return jsonError("Search failed: \(error.localizedDescription)")
        }
    }

    private func getSwipeStats(_ args: [String: Any]) async throws -> String {
        let atoms = try await atomRepo.fetchAll(type: .research)
        let swipes = atoms.filter { $0.isSwipeFileAtom }

        var hookCounts: [String: Int] = [:]
        var frameworkCounts: [String: Int] = [:]

        for atom in swipes {
            let metaDict = (atom.metadataDict ?? [:])
            if let hook = metaDict["hookType"] as? String {
                hookCounts[hook, default: 0] += 1
            }
            if let framework = metaDict["framework"] as? String {
                frameworkCounts[framework, default: 0] += 1
            }
        }

        let topHooks = hookCounts.sorted { $0.value > $1.value }.prefix(5).map { ["hook": $0.key, "count": $0.value] as [String: Any] }
        let topFrameworks = frameworkCounts.sorted { $0.value > $1.value }.prefix(5).map { ["framework": $0.key, "count": $0.value] as [String: Any] }

        return jsonEncode([
            "totalSwipes": swipes.count,
            "topHooks": topHooks,
            "topFrameworks": topFrameworks
        ] as [String: Any])
    }

    // MARK: - Content

    private func getContentPipeline(_ args: [String: Any]) async throws -> String {
        let filterPhase = args["phase"] as? String
        let contentAtoms = try await atomRepo.fetchAll(type: .content)

        var grouped: [String: [[String: Any]]] = [:]

        for atom in contentAtoms {
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            let phase = meta?.phase.rawValue ?? "ideation"

            if let filterPhase = filterPhase, phase != filterPhase {
                continue
            }

            let item: [String: Any] = [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "phase": phase,
                "wordCount": meta?.wordCount ?? 0,
                "platform": meta?.platform?.rawValue ?? "none"
            ]
            grouped[phase, default: []].append(item)
        }

        var result: [String: Any] = ["pipeline": grouped]
        result["totalCount"] = contentAtoms.count
        return jsonEncode(result)
    }

    private func advancePipelinePhase(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        let notes = args["notes"] as? String

        do {
            let phaseAtom = try await ContentPipelineService().advancePhase(
                contentUUID: uuid,
                notes: notes
            )
            return jsonEncode([
                "success": true,
                "phaseTransition": phaseAtom.title ?? "",
                "message": "Content advanced to next phase"
            ] as [String: Any])
        } catch {
            return jsonError("Failed to advance phase: \(error.localizedDescription)")
        }
    }

    private func createContent(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String
        let platformStr = args["platform"] as? String

        let atom = try await atomRepo.create(
            type: .content,
            title: title,
            body: body
        )

        // Set initial metadata with phase and platform
        if let platformStr = platformStr {
            _ = try await atomRepo.update(uuid: atom.uuid, updates: { atom in
                var metaDict = (atom.metadataDict ?? [:])
                metaDict["phase"] = "ideation"
                metaDict["platform"] = platformStr
                metaDict["wordCount"] = (body ?? "").split(separator: " ").count
                if let data = try? JSONSerialization.data(withJSONObject: metaDict),
                   let json = String(data: data, encoding: .utf8) {
                    atom.metadata = json
                }
            })
        }

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Content created: \(title)"
        ] as [String: Any])
    }

    private func getContent(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let atom = try await atomRepo.fetch(uuid: uuid) else {
            return jsonError("Content not found: \(uuid)")
        }
        var result = atomToDict(atom)
        if let meta = atom.metadataValue(as: ContentAtomMetadata.self) {
            result["phase"] = meta.phase.rawValue
            result["platform"] = meta.platform?.rawValue ?? "none"
            result["wordCount"] = meta.wordCount
        }
        return jsonEncode(result)
    }

    private func createThinkspace(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let atom = try await atomRepo.create(
            type: .thinkspace,
            title: title
        )
        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Thinkspace created: \(title)"
        ] as [String: Any])
    }

    // MARK: - Plannerum

    private func getCalendarBlocks(_ args: [String: Any]) async throws -> String {
        let dateStr = args["date"] as? String
        let calendar = Calendar.current

        let targetDate: Date
        if let dateStr = dateStr, let parsed = ISO8601DateFormatter().date(from: dateStr) {
            targetDate = parsed
        } else if let dateStr = dateStr {
            // Try simple date format
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            targetDate = formatter.date(from: dateStr) ?? Date()
        } else {
            targetDate = Date()
        }

        let dayStart = calendar.startOfDay(for: targetDate)

        let blocks = try await atomRepo.fetchAll(type: .scheduleBlock)
        let dayBlocks = blocks.filter { atom in
            let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
            if let startStr = meta?.startTime,
               let startDate = ISO8601DateFormatter().date(from: startStr) {
                return calendar.isDate(startDate, inSameDayAs: dayStart)
            }
            // Fallback to createdAt
            if let date = ISO8601DateFormatter().date(from: atom.createdAt) {
                return calendar.isDate(date, inSameDayAs: dayStart)
            }
            return false
        }

        let items: [[String: Any]] = dayBlocks.map { atom in
            let meta = atom.metadataValue(as: ScheduleBlockMetadata.self)
            return [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "startTime": meta?.startTime ?? "",
                "endTime": meta?.endTime ?? "",
                "isCompleted": meta?.isCompleted ?? false,
                "blockType": meta?.blockType ?? "",
                "intent": meta?.originType ?? ""
            ] as [String: Any]
        }

        return jsonEncode([
            "date": ISO8601DateFormatter().string(from: dayStart),
            "blocks": items,
            "count": items.count
        ] as [String: Any])
    }

    private func createBlock(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        guard let startTime = args["startTime"] as? String else {
            return jsonError("Missing required parameter: startTime")
        }
        guard let endTime = args["endTime"] as? String else {
            return jsonError("Missing required parameter: endTime")
        }
        let intent = args["intent"] as? String

        var metaDict: [String: Any] = [
            "startTime": startTime,
            "endTime": endTime,
            "status": "scheduled"
        ]
        if let intent = intent {
            metaDict["originType"] = intent
        }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        let atom = try await atomRepo.create(
            type: .scheduleBlock,
            title: title,
            metadata: metaJSON
        )

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "startTime": startTime,
            "endTime": endTime,
            "message": "Schedule block created: \(title)"
        ] as [String: Any])
    }

    private func updateBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }
        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            if let title = args["title"] as? String { atom.title = title }

            var metaDict = (atom.metadataDict ?? [:])
            if let startTime = args["startTime"] as? String { metaDict["startTime"] = startTime }
            if let endTime = args["endTime"] as? String { metaDict["endTime"] = endTime }

            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        }) else {
            return jsonError("Schedule block not found: \(uuid)")
        }
        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "message": "Schedule block updated"
        ] as [String: Any])
    }

    private func deleteBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }

        // Check if this is a confirmed deletion
        let isConfirmed = args["_confirmed"] as? Bool ?? false
        if isConfirmed {
            try await atomRepo.delete(uuid: uuid)
            return jsonEncode([
                "success": true,
                "message": "Schedule block deleted"
            ] as [String: Any])
        }

        // Fetch block to show description
        let atom = try await atomRepo.fetch(uuid: uuid)
        let blockTitle = atom?.title ?? uuid

        // Hard confirmation — store pending and return confirmation request
        let confirmationId = UUID().uuidString
        pendingConfirmations[confirmationId] = PendingConfirmation(
            toolName: "delete_block",
            arguments: ["uuid": uuid, "_confirmed": true],
            description: "Delete schedule block: \(blockTitle)",
            createdAt: Date()
        )

        return jsonEncode([
            "confirmation_required": true,
            "confirmation_id": confirmationId,
            "action": "delete_block",
            "description": "Delete schedule block: \(blockTitle)"
        ] as [String: Any])
    }

    private func completeBlock(_ args: [String: Any]) async throws -> String {
        guard let uuid = args["uuid"] as? String else {
            return jsonError("Missing required parameter: uuid")
        }

        guard let updated = try await atomRepo.update(uuid: uuid, updates: { atom in
            var metaDict = (atom.metadataDict ?? [:])
            metaDict["isCompleted"] = true
            metaDict["completedAt"] = ISO8601DateFormatter().string(from: Date())
            metaDict["status"] = "completed"
            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let json = String(data: data, encoding: .utf8) {
                atom.metadata = json
            }
        }) else {
            return jsonError("Schedule block not found: \(uuid)")
        }

        return jsonEncode([
            "success": true,
            "uuid": updated.uuid,
            "title": updated.title ?? "",
            "message": "Block completed. XP awarded."
        ] as [String: Any])
    }

    private func getUnscheduledTasks(_ args: [String: Any]) async throws -> String {
        let limit = args["limit"] as? Int ?? 20

        let tasks = try await atomRepo.fetchAll(type: .task)
        let unscheduled = tasks.filter { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return meta?.isUnscheduled == true || meta?.startTime == nil
        }.prefix(limit)

        let items: [[String: Any]] = unscheduled.map { atom in
            let meta = atom.metadataValue(as: TaskMetadata.self)
            return [
                "uuid": atom.uuid,
                "title": atom.title ?? "Untitled",
                "priority": meta?.priority ?? "medium",
                "intent": meta?.intent ?? "",
                "dueDate": meta?.dueDate ?? ""
            ] as [String: Any]
        }

        return jsonEncode(["tasks": items, "count": items.count])
    }

    private func createTask(_ args: [String: Any]) async throws -> String {
        guard let title = args["title"] as? String else {
            return jsonError("Missing required parameter: title")
        }
        let body = args["body"] as? String
        let priority = args["priority"] as? String ?? "medium"
        let intent = args["intent"] as? String
        let dueDate = args["dueDate"] as? String

        var metaDict: [String: Any] = [
            "priority": priority,
            "isUnscheduled": true
        ]
        if let intent = intent { metaDict["intent"] = intent }
        if let dueDate = dueDate { metaDict["dueDate"] = dueDate }

        let metaJSON: String?
        if let data = try? JSONSerialization.data(withJSONObject: metaDict),
           let json = String(data: data, encoding: .utf8) {
            metaJSON = json
        } else {
            metaJSON = nil
        }

        let atom = try await atomRepo.create(
            type: .task,
            title: title,
            body: body,
            metadata: metaJSON
        )

        return jsonEncode([
            "success": true,
            "uuid": atom.uuid,
            "title": title,
            "message": "Task created: \(title)"
        ] as [String: Any])
    }

    // MARK: - Quests

    private func getQuestStatus(_ args: [String: Any]) async throws -> String {
        let questEngine = QuestEngine()
        await questEngine.evaluate()

        let quests: [[String: Any]] = questEngine.quests.map { quest in
            [
                "id": quest.id,
                "title": quest.title,
                "description": quest.description,
                "progress": quest.progress,
                "isComplete": quest.isComplete,
                "streak": quest.streak,
                "xpReward": quest.xpReward,
                "allowManualComplete": quest.allowManualComplete
            ] as [String: Any]
        }

        return jsonEncode(["quests": quests, "count": quests.count])
    }

    private func completeQuest(_ args: [String: Any]) async throws -> String {
        guard let questId = args["questId"] as? String else {
            return jsonError("Missing required parameter: questId")
        }

        let questEngine = QuestEngine()
        await questEngine.evaluate()

        guard let quest = questEngine.quests.first(where: { $0.id == questId }) else {
            return jsonError("Quest not found: \(questId)")
        }

        guard quest.allowManualComplete else {
            return jsonError("Quest '\(quest.title)' does not allow manual completion")
        }

        if quest.isComplete {
            return jsonEncode([
                "success": false,
                "message": "Quest '\(quest.title)' is already completed"
            ] as [String: Any])
        }

        await questEngine.manualComplete(questId: questId)

        return jsonEncode([
            "success": true,
            "questId": questId,
            "title": quest.title,
            "xpAwarded": quest.xpReward,
            "message": "Quest completed: \(quest.title) (+\(quest.xpReward) XP)"
        ] as [String: Any])
    }

    // MARK: - Analytics

    private func getDimensionXP(_ args: [String: Any]) async throws -> String {
        let engine = DimensionIndexEngine.shared

        let dimensionFilter = args["dimension"] as? String

        var dimensions: [[String: Any]] = []
        for (dimension, index) in engine.dimensionIndices {
            if let filter = dimensionFilter, dimension.rawValue != filter {
                continue
            }
            dimensions.append([
                "dimension": dimension.rawValue,
                "displayName": dimension.displayName,
                "score": index.score,
                "confidence": index.confidence,
                "trend": index.trend.rawValue
            ] as [String: Any])
        }

        return jsonEncode([
            "dimensions": dimensions,
            "sanctuaryLevel": engine.sanctuaryLevel,
            "overallTrend": engine.overallTrend.rawValue
        ] as [String: Any])
    }

    private func getStreakData(_ args: [String: Any]) async throws -> String {
        // Load streak data from dimensionSnapshot atoms
        let snapshots = try await atomRepo.fetchAll(type: .dimensionSnapshot)

        var streaks: [String: Int] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group snapshots by day, check consecutive
        let dailySnapshots = snapshots.compactMap { atom -> Date? in
            ISO8601DateFormatter().date(from: atom.createdAt)
        }.map { calendar.startOfDay(for: $0) }

        let uniqueDays = Set(dailySnapshots).sorted(by: >)
        var consecutiveDays = 0
        var checkDate = today

        for day in uniqueDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                consecutiveDays += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        streaks["overall"] = consecutiveDays

        return jsonEncode(["streaks": streaks])
    }

    // MARK: - Preferences

    private func getPreferences(_ args: [String: Any]) async throws -> String {
        let scopeStr = args["scope"] as? String
        let scope: PreferenceScope? = scopeStr.flatMap { PreferenceScope(rawValue: $0) }

        let preferences = await PreferenceLearningEngine.shared.getAllPreferences(scope: scope)

        let items: [[String: Any]] = preferences.map { pref in
            [
                "key": pref.key,
                "value": pref.value,
                "scope": pref.scope.rawValue,
                "confidence": pref.confidence,
                "source": pref.source
            ]
        }

        return jsonEncode(["preferences": items, "count": items.count])
    }

    private func storePreference(_ args: [String: Any]) async throws -> String {
        guard let key = args["key"] as? String else {
            return jsonError("Missing required parameter: key")
        }
        guard let value = args["value"] as? String else {
            return jsonError("Missing required parameter: value")
        }
        let scopeStr = args["scope"] as? String ?? "global"
        let scope = PreferenceScope(rawValue: scopeStr) ?? .global
        let scopeQualifier = args["scopeQualifier"] as? String

        await PreferenceLearningEngine.shared.learnPreference(
            key: key,
            value: value,
            scope: scope,
            source: "explicit",
            confidence: 1.0,
            scopeQualifier: scopeQualifier
        )

        return jsonEncode([
            "success": true,
            "key": key,
            "value": value,
            "scope": scopeStr,
            "message": "Preference stored: \(key) = \(value)"
        ] as [String: Any])
    }

    private func deletePreference(_ args: [String: Any]) async throws -> String {
        guard let key = args["key"] as? String else {
            return jsonError("Missing required parameter: key")
        }

        let scopeStr = args["scope"] as? String ?? "global"
        let scope: PreferenceScope = scopeStr == "client" ? .client : scopeStr == "taskType" ? .taskType : .global
        let scopeQualifier = args["scopeQualifier"] as? String

        await PreferenceLearningEngine.shared.deletePreference(key: key, scope: scope, scopeQualifier: scopeQualifier)

        return jsonEncode([
            "success": true,
            "key": key,
            "message": "Preference deleted: \(key)"
        ] as [String: Any])
    }

    // MARK: - Helpers

    private func atomToDict(_ atom: Atom) -> [String: Any] {
        var dict: [String: Any] = [
            "uuid": atom.uuid,
            "type": atom.type.rawValue,
            "title": atom.title ?? "",
            "body": String((atom.body ?? "").prefix(2000)),
            "createdAt": atom.createdAt,
            "updatedAt": atom.updatedAt
        ]
        if let metadata = atom.metadata,
           let data = metadata.data(using: .utf8),
           let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["metadata"] = meta
        }
        return dict
    }

    private func jsonEncode(_ dict: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode response\"}"
        }
        return json
    }

    private func jsonError(_ message: String) -> String {
        jsonEncode(["error": message])
    }
}

// Note: Uses Atom.metadataDict from Atom.swift (returns [String: Any]?)
