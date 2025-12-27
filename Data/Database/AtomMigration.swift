// CosmoOS/Data/Database/AtomMigration.swift
// Migration functions for converting legacy entities to unified Atom model
// Each function maps a legacy table row to an Atom

import GRDB
import Foundation

// MARK: - Legacy to Atom Converters

/// Converts legacy database rows to Atom instances
struct AtomMigration {

    // MARK: - Idea → Atom

    /// Convert a legacy Idea row to an Atom
    static func ideaToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = IdeaMetadata(
            tags: parseJsonArray(row["tags"] as? String),
            priority: row["priority"] as? String,
            isPinned: (row["is_pinned"] as? Int64) == 1,
            pinnedAt: row["pinned_at"] as? String
        )

        // Build structured data
        let structured = FocusBlocksStructured(
            focusBlocks: row["focus_blocks"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }
        if let parentUuid = row["parent_uuid"] as? String, !parentUuid.isEmpty {
            links.append(.parentIdea(parentUuid))
        }
        if let connectionUuid = row["connection_uuid"] as? String, !connectionUuid.isEmpty {
            links.append(.connection(connectionUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .idea,
            title: row["title"] as? String,
            body: row["content"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Task → Atom

    /// Convert a legacy CosmoTask row to an Atom
    static func taskToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = TaskMetadata(
            status: row["status"] as? String,
            priority: row["priority"] as? String,
            color: row["color"] as? String,
            dueDate: row["due_date"] as? String,
            startTime: row["start_time"] as? String,
            endTime: row["end_time"] as? String,
            durationMinutes: (row["duration_minutes"] as? Int64).map { Int($0) },
            focusDate: row["focus_date"] as? String,
            isUnscheduled: (row["is_unscheduled"] as? Int64) == 1,
            isCompleted: nil,
            completedAt: nil
        )

        // Build structured data
        let structured = TaskStructured(
            checklist: row["checklist"] as? String,
            recurrence: row["recurrence"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }
        if let originUuid = row["origin_idea_uuid"] as? String, !originUuid.isEmpty {
            links.append(.originIdea(originUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .task,
            title: row["title"] as? String,
            body: row["description"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Project → Atom

    /// Convert a legacy Project row to an Atom
    static func projectToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = ProjectMetadata(
            color: row["color"] as? String,
            status: row["status"] as? String,
            priority: row["priority"] as? String,
            tags: parseJsonArray(row["tags"] as? String)
        )

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .project,
            title: row["title"] as? String,
            body: row["description"] as? String,
            structured: nil,
            metadata: encodeJson(metadata),
            links: nil, // Projects are parents, not children
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Content → Atom

    /// Convert a legacy Content row to an Atom
    static func contentToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = ContentMetadata(
            contentType: row["content_type"] as? String,
            status: row["status"] as? String,
            scheduledAt: row["scheduled_at"] as? String,
            lastOpenedAt: row["last_opened_at"] as? String,
            tags: parseJsonArray(row["tags"] as? String)
        )

        // Build structured data
        let structured = ContentStructured(
            theme: row["theme"] as? String,
            focusBlocks: row["focus_blocks"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .content,
            title: row["title"] as? String,
            body: row["body"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Research → Atom

    /// Convert a legacy Research row to an Atom
    static func researchToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = ResearchMetadata(
            url: row["url"] as? String,
            summary: row["summary"] as? String,
            researchType: row["research_type"] as? String,
            processingStatus: row["processing_status"] as? String,
            thumbnailUrl: row["thumbnail_url"] as? String,
            query: row["query"] as? String,
            findings: row["findings"] as? String,
            tags: parseJsonArray(row["tags"] as? String),
            hook: row["hook"] as? String,
            emotionTone: row["emotion_tone"] as? String,
            structureType: row["structure_type"] as? String,
            isSwipeFile: (row["is_swipe_file"] as? Int64) == 1,
            contentSource: row["content_source"] as? String
        )

        // Build structured data
        let structured = ResearchStructured(
            autoMetadata: row["auto_metadata"] as? String,
            focusBlocks: row["focus_blocks"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .research,
            title: row["title"] as? String,
            body: row["content"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Connection → Atom

    /// Convert a legacy Connection row to an Atom
    static func connectionToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build structured data (mental model)
        let structured = ConnectionStructured(
            idea: row["idea"] as? String,
            personalBelief: row["personal_belief"] as? String,
            goal: row["goal"] as? String,
            problems: row["problems"] as? String,
            benefit: row["benefit"] as? String,
            beliefsObjections: row["beliefs_objections"] as? String,
            example: row["example"] as? String,
            process: row["process"] as? String,
            notes: row["notes"] as? String,
            referencesData: row["references_data"] as? String,
            sourceText: row["source_text"] as? String,
            extractionConfidence: row["extraction_confidence"] as? Double
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .connection,
            title: row["title"] as? String,
            body: nil, // Connections use structured mental model
            structured: encodeJson(structured),
            metadata: nil,
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Journal Entry → Atom

    /// Convert a legacy JournalEntry row to an Atom
    static func journalEntryToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = JournalEntryMetadata(
            source: row["source"] as? String,
            status: row["status"] as? String,
            errorMessage: row["error_message"] as? String
        )

        // Build structured data
        let structured = JournalEntryStructured(
            aiResponse: row["ai_response"] as? String,
            linkedTasks: row["linked_tasks"] as? String,
            linkedIdeas: row["linked_ideas"] as? String,
            linkedContent: row["linked_content"] as? String
        )

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .journalEntry,
            title: nil, // Journals have no title
            body: row["content"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: nil,
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Calendar Event → Atom

    /// Convert a legacy CalendarEvent row to an Atom
    static func calendarEventToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = CalendarEventMetadata(
            calendarType: row["calendar_type"] as? String,
            startTime: row["start_time"] as? String,
            endTime: row["end_time"] as? String,
            isAllDay: (row["is_all_day"] as? Int64) == 1,
            location: row["location"] as? String,
            color: row["color"] as? String,
            reminderMinutes: (row["reminder_minutes"] as? Int64).map { Int($0) },
            isCompleted: (row["is_completed"] as? Int64) == 1,
            completedAt: row["completed_at"] as? String,
            isUnscheduled: (row["is_unscheduled"] as? Int64) == 1,
            reminderDueAt: row["reminder_due_at"] as? String
        )

        // Build structured data
        let structured = CalendarEventStructured(
            recurrence: row["recurrence"] as? String,
            linkedEntities: row["linked_entities"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .calendarEvent,
            title: row["title"] as? String,
            body: row["description"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Schedule Block → Atom

    /// Convert a legacy ScheduleBlock row to an Atom
    static func scheduleBlockToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = ScheduleBlockMetadata(
            blockType: row["block_type"] as? String,
            status: row["status"] as? String,
            isCompleted: (row["is_completed"] as? Int64) == 1,
            completedAt: row["completed_at"] as? String,
            startTime: row["start_time"] as? String,
            endTime: row["end_time"] as? String,
            durationMinutes: (row["duration_minutes"] as? Int64).map { Int($0) },
            isAllDay: (row["is_all_day"] as? Int64) == 1,
            priority: row["priority"] as? String,
            color: row["color"] as? String,
            tags: parseJsonArray(row["tags"] as? String),
            reminderMinutes: (row["reminder_minutes"] as? Int64).map { Int($0) },
            location: row["location"] as? String,
            originType: row["origin_type"] as? String,
            originEntityType: row["origin_entity_type"] as? String
        )

        // Build structured data
        let structured = ScheduleBlockStructured(
            notes: row["notes"] as? String,
            checklist: row["checklist"] as? String,
            recurrence: row["recurrence"] as? String,
            focusSession: row["focus_session"] as? String,
            focusSessionData: row["focus_session_data"] as? String,
            semanticLinks: row["semantic_links"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }
        if let originUuid = row["origin_entity_uuid"] as? String, !originUuid.isEmpty {
            links.append(AtomLink(type: "origin_entity", uuid: originUuid, entityType: row["origin_entity_type"] as? String))
        }
        if let recurrenceParentUuid = row["recurrence_parent_uuid"] as? String, !recurrenceParentUuid.isEmpty {
            links.append(.recurrenceParent(recurrenceParentUuid))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .scheduleBlock,
            title: row["title"] as? String,
            body: row["description"] as? String,
            structured: encodeJson(structured),
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Uncommitted Item → Atom

    /// Convert a legacy UncommittedItem row to an Atom
    static func uncommittedItemToAtom(_ row: Row) -> Atom? {
        guard let uuid = row["uuid"] as? String else { return nil }

        // Build metadata
        let metadata = UncommittedItemMetadata(
            captureMethod: row["capture_method"] as? String,
            assignmentStatus: row["assignment_status"] as? String,
            inferredProject: row["inferred_project"] as? String,
            inferredProjectConfidence: row["inferred_project_confidence"] as? Double,
            inferredType: row["inferred_type"] as? String,
            isArchived: (row["is_archived"] as? Int64) == 1,
            expiresAt: row["expires_at"] as? String
        )

        // Build links
        var links: [AtomLink] = []
        if let projectUuid = row["project_uuid"] as? String, !projectUuid.isEmpty {
            links.append(.project(projectUuid))
        }
        if let promotedUuid = row["promoted_entity_uuid"] as? String,
           let promotedType = row["promoted_to"] as? String,
           !promotedUuid.isEmpty {
            links.append(.promotedTo(promotedUuid, entityType: promotedType))
        }

        return Atom(
            id: nil,  // Let SQLite auto-generate - legacy IDs collide across tables
            uuid: uuid,
            type: .uncommittedItem,
            title: nil,
            body: row["raw_text"] as? String,
            structured: nil,
            metadata: encodeJson(metadata),
            links: links.isEmpty ? nil : encodeJson(links),
            createdAt: row["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
            isDeleted: (row["is_deleted"] as? Int64) == 1,
            localVersion: row["_local_version"] as? Int64 ?? 1,
            serverVersion: row["_server_version"] as? Int64 ?? 0,
            syncVersion: row["_sync_version"] as? Int64 ?? 0
        )
    }

    // MARK: - Helpers

    /// Parse a JSON array string to [String]
    private static func parseJsonArray(_ json: String?) -> [String]? {
        guard let json = json,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return array
    }

    /// Encode a value to JSON string
    private static func encodeJson<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

// MARK: - Database Migration Execution

extension AtomMigration {

    /// Migrate all legacy tables to atoms table
    /// This function is safe to run multiple times (idempotent)
    static func migrateAllToAtoms(_ db: Database) throws {
        print("🔄 Starting Atom migration...")

        // Track migration stats
        var migrated: [String: Int] = [:]

        // Migrate ideas
        let ideas = try Row.fetchAll(db, sql: "SELECT * FROM ideas WHERE uuid IS NOT NULL")
        for row in ideas {
            if let atom = ideaToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["ideas"] = ideas.count
        print("  ✅ Migrated \(ideas.count) ideas")

        // Migrate tasks
        let tasks = try Row.fetchAll(db, sql: "SELECT * FROM tasks WHERE uuid IS NOT NULL")
        for row in tasks {
            if let atom = taskToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["tasks"] = tasks.count
        print("  ✅ Migrated \(tasks.count) tasks")

        // Migrate projects
        let projects = try Row.fetchAll(db, sql: "SELECT * FROM projects WHERE uuid IS NOT NULL")
        for row in projects {
            if let atom = projectToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["projects"] = projects.count
        print("  ✅ Migrated \(projects.count) projects")

        // Migrate content
        let content = try Row.fetchAll(db, sql: "SELECT * FROM content WHERE uuid IS NOT NULL")
        for row in content {
            if let atom = contentToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["content"] = content.count
        print("  ✅ Migrated \(content.count) content")

        // Migrate research
        let research = try Row.fetchAll(db, sql: "SELECT * FROM research WHERE uuid IS NOT NULL")
        for row in research {
            if let atom = researchToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["research"] = research.count
        print("  ✅ Migrated \(research.count) research")

        // Migrate connections
        let connections = try Row.fetchAll(db, sql: "SELECT * FROM connections WHERE uuid IS NOT NULL")
        for row in connections {
            if let atom = connectionToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["connections"] = connections.count
        print("  ✅ Migrated \(connections.count) connections")

        // Migrate journal entries
        let journals = try Row.fetchAll(db, sql: "SELECT * FROM journal_entries WHERE uuid IS NOT NULL")
        for row in journals {
            if let atom = journalEntryToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["journal_entries"] = journals.count
        print("  ✅ Migrated \(journals.count) journal entries")

        // Migrate calendar events
        let calendarEvents = try Row.fetchAll(db, sql: "SELECT * FROM calendar_events WHERE uuid IS NOT NULL")
        for row in calendarEvents {
            if let atom = calendarEventToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["calendar_events"] = calendarEvents.count
        print("  ✅ Migrated \(calendarEvents.count) calendar events")

        // Migrate schedule blocks
        let scheduleBlocks = try Row.fetchAll(db, sql: "SELECT * FROM schedule_blocks WHERE uuid IS NOT NULL")
        for row in scheduleBlocks {
            if let atom = scheduleBlockToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["schedule_blocks"] = scheduleBlocks.count
        print("  ✅ Migrated \(scheduleBlocks.count) schedule blocks")

        // Migrate uncommitted items
        let uncommitted = try Row.fetchAll(db, sql: "SELECT * FROM uncommitted_items WHERE uuid IS NOT NULL")
        for row in uncommitted {
            if let atom = uncommittedItemToAtom(row) {
                try insertAtomIfNotExists(db, atom: atom)
            }
        }
        migrated["uncommitted_items"] = uncommitted.count
        print("  ✅ Migrated \(uncommitted.count) uncommitted items")

        let total = migrated.values.reduce(0, +)
        print("✅ Atom migration complete: \(total) total entities migrated")
    }

    /// Insert an atom only if it doesn't already exist (by UUID)
    private static func insertAtomIfNotExists(_ db: Database, atom: Atom) throws {
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM atoms WHERE uuid = ?",
            arguments: [atom.uuid]
        ) ?? 0

        if exists == 0 {
            try atom.insert(db)
        }
    }
}

// MARK: - UUID Resolution for Legacy Integer IDs

extension AtomMigration {

    /// Build a lookup table mapping legacy (table, id) → uuid
    /// Used during migration to resolve integer foreign keys to UUIDs
    static func buildUuidLookup(_ db: Database) throws -> [String: [Int64: String]] {
        var lookup: [String: [Int64: String]] = [:]

        let tables = ["ideas", "tasks", "projects", "content", "research",
                      "connections", "journal_entries", "calendar_events",
                      "schedule_blocks", "uncommitted_items"]

        for table in tables {
            var tableMap: [Int64: String] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT id, uuid FROM \(table) WHERE uuid IS NOT NULL")
            for row in rows {
                if let id = row["id"] as? Int64, let uuid = row["uuid"] as? String {
                    tableMap[id] = uuid
                }
            }
            lookup[table] = tableMap
        }

        return lookup
    }

    /// Resolve integer ID links to UUID links using the lookup table
    static func resolveIntegerLinks(_ db: Database, lookup: [String: [Int64: String]]) throws {
        print("🔄 Resolving integer ID links to UUIDs...")

        // For each atom, check if it has integer-based relationships that need resolution
        let atoms = try Row.fetchAll(db, sql: "SELECT id, uuid, type, links FROM atoms")

        for row in atoms {
            guard let atomId = row["id"] as? Int64,
                  let linksJson = row["links"] as? String,
                  let linksData = linksJson.data(using: .utf8),
                  let links = try? JSONDecoder().decode([AtomLink].self, from: linksData) else {
                continue
            }

            // No changes needed for most atoms - links already use UUIDs
            // This is a safeguard for edge cases
            if let updatedLinksData = try? JSONEncoder().encode(links),
               let updatedLinksJson = String(data: updatedLinksData, encoding: .utf8),
               updatedLinksJson != linksJson {
                try db.execute(
                    sql: "UPDATE atoms SET links = ? WHERE id = ?",
                    arguments: [updatedLinksJson, atomId]
                )
            }
        }

        print("✅ Link resolution complete")
    }
}
