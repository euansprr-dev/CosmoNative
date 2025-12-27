// CosmoOS/Data/Search/AtomSearchEngine.swift
// Unified search engine for Atoms
// Provides FTS (BM25) and semantic search capabilities for the Atom model

import GRDB
import Foundation

// MARK: - Search Result

/// A unified search result from any search method
struct AtomSearchResult: Identifiable, Sendable {
    let atom: Atom
    let score: Double
    let matchType: MatchType
    let snippet: String?

    var id: String { atom.uuid }

    enum MatchType: String, Sendable {
        case fts = "keyword"
        case semantic = "semantic"
        case hybrid = "hybrid"
        case exact = "exact"
    }
}

// MARK: - Search Options

/// Options for customizing search behavior
struct AtomSearchOptions: Sendable {
    var types: [AtomType]?          // Filter by atom types
    var limit: Int = 20             // Max results
    var offset: Int = 0             // Pagination offset
    var includeDeleted: Bool = false // Include soft-deleted atoms
    var projectUuid: String?        // Filter by project
    var minScore: Double = 0.0      // Minimum relevance score

    static let `default` = AtomSearchOptions()
}

// MARK: - Atom Search Engine

/// Unified search engine for all Atom queries
actor AtomSearchEngine {
    private var database: CosmoDatabase?

    init() {
        self.database = nil  // Lazy-loaded from MainActor when needed
    }

    /// Get or lazily initialize the CosmoDatabase from the MainActor
    private func getDatabase() async -> CosmoDatabase {
        if let db = database {
            return db
        }
        let db = await MainActor.run { CosmoDatabase.shared }
        database = db
        return db
    }

    // MARK: - FTS Search (BM25 Keyword Search)

    /// Full-text search using FTS5 BM25 ranking
    func search(query: String, options: AtomSearchOptions = .default) async throws -> [AtomSearchResult] {
        guard !query.isEmpty else { return [] }

        // Escape special FTS5 characters and prepare query
        let ftsQuery = prepareFtsQuery(query)

        let db = await getDatabase()
        return try await db.asyncRead { db in
            var results: [AtomSearchResult] = []

            // Build the FTS query
            var sql = """
                SELECT atoms.*, bm25(atoms_fts) as score
                FROM atoms_fts
                JOIN atoms ON atoms.uuid = atoms_fts.uuid
                WHERE atoms_fts MATCH ?
            """
            var arguments: [DatabaseValueConvertible] = [ftsQuery]

            // Apply filters
            if !options.includeDeleted {
                sql += " AND atoms.is_deleted = 0"
            }

            if let types = options.types, !types.isEmpty {
                let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
                sql += " AND atoms.type IN (\(typeList))"
            }

            if let projectUuid = options.projectUuid {
                sql += " AND atoms.links LIKE ?"
                arguments.append("%\(projectUuid)%")
            }

            // Order by relevance and apply pagination
            sql += " ORDER BY score LIMIT ? OFFSET ?"
            arguments.append(options.limit)
            arguments.append(options.offset)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            for row in rows {
                if let atom = try? Atom.fetchOne(db, sql: "SELECT * FROM atoms WHERE uuid = ?", arguments: [row["uuid"] as? String ?? ""]) {
                    let score = abs(row["score"] as? Double ?? 0.0) // BM25 returns negative scores
                    if score >= options.minScore {
                        let snippet = self.generateSnippet(atom: atom, query: query)
                        results.append(AtomSearchResult(
                            atom: atom,
                            score: score,
                            matchType: .fts,
                            snippet: snippet
                        ))
                    }
                }
            }

            return results
        }
    }

    /// Exact match search (case-insensitive)
    func exactSearch(query: String, field: SearchField = .title, options: AtomSearchOptions = .default) async throws -> [AtomSearchResult] {
        guard !query.isEmpty else { return [] }

        let database = await getDatabase()
        return try await database.asyncRead { db in
            var results: [AtomSearchResult] = []

            let column = field.columnName
            let pattern = "%\(query.lowercased())%"

            var sql = """
                SELECT * FROM atoms
                WHERE LOWER(\(column)) LIKE ?
            """
            var arguments: [DatabaseValueConvertible] = [pattern]

            if !options.includeDeleted {
                sql += " AND is_deleted = 0"
            }

            if let types = options.types, !types.isEmpty {
                let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
                sql += " AND type IN (\(typeList))"
            }

            sql += " ORDER BY updated_at DESC LIMIT ? OFFSET ?"
            arguments.append(options.limit)
            arguments.append(options.offset)

            let atoms = try Atom.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            for atom in atoms {
                results.append(AtomSearchResult(
                    atom: atom,
                    score: 1.0,
                    matchType: .exact,
                    snippet: nil
                ))
            }

            return results
        }
    }

    enum SearchField: String, Sendable {
        case title
        case body
        case metadata
        case all

        var columnName: String {
            switch self {
            case .title: return "title"
            case .body: return "body"
            case .metadata: return "metadata"
            case .all: return "title || ' ' || COALESCE(body, '')"
            }
        }
    }

    // MARK: - Query Preparation

    /// Prepare a query string for FTS5
    private func prepareFtsQuery(_ query: String) -> String {
        // Remove special FTS5 operators for safety
        let cleaned = query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into words and create OR query
        let words = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count == 1 {
            return "\(words[0])*" // Prefix search for single word
        } else {
            // Multiple words: match any word with prefix
            return words.map { "\($0)*" }.joined(separator: " OR ")
        }
    }

    /// Generate a snippet showing the match context
    private nonisolated func generateSnippet(atom: Atom, query: String) -> String? {
        let searchText = [atom.title, atom.body].compactMap { $0 }.joined(separator: " ")
        guard !searchText.isEmpty else { return nil }

        let queryLower = query.lowercased()
        let textLower = searchText.lowercased()

        if let range = textLower.range(of: queryLower) {
            let start = max(searchText.startIndex, searchText.index(range.lowerBound, offsetBy: -50, limitedBy: searchText.startIndex) ?? searchText.startIndex)
            let end = min(searchText.endIndex, searchText.index(range.upperBound, offsetBy: 50, limitedBy: searchText.endIndex) ?? searchText.endIndex)
            let snippet = String(searchText[start..<end])
            return "...\(snippet)..."
        }

        // No exact match, return first 100 chars
        let endIndex = searchText.index(searchText.startIndex, offsetBy: min(100, searchText.count))
        return String(searchText[..<endIndex]) + "..."
    }
}

// MARK: - LLM Schema Description

/// Provides a unified schema description for LLM tools
struct AtomSchemaDescription {

    /// Generate a schema description for LLM context
    static func generateSchemaDescription() -> String {
        """
        # CosmoOS Atom Schema

        All entities in CosmoOS are stored as Atoms. An Atom is a unified record with:

        ## Core Fields
        - uuid: Unique identifier (primary key)
        - type: Entity type (idea, task, project, content, research, connection, journal_entry, calendar_event, schedule_block, uncommitted_item)
        - title: Primary title/name
        - body: Main content/description

        ## JSON Fields
        - structured: Type-specific structured data (checklist, mental_model, theme, etc.)
        - metadata: Auxiliary data (tags, priority, status, color, flags, etc.)
        - links: Relationships to other atoms [{type, uuid, entityType}]

        ## Timestamps
        - created_at, updated_at: ISO8601 timestamps

        ## Type-Specific Metadata

        ### idea
        - metadata.tags: String array
        - metadata.priority: "Low" | "Medium" | "High"
        - metadata.isPinned: Boolean

        ### task
        - metadata.status: "todo" | "in_progress" | "completed"
        - metadata.priority: "low" | "medium" | "high"
        - metadata.dueDate, startTime, endTime: ISO8601 timestamps
        - structured.checklist: JSON array of checklist items
        - structured.recurrence: Recurrence rule object

        ### project
        - metadata.color: Hex color string
        - metadata.status: "active" | "archived" | "completed"
        - metadata.priority: "Low" | "Medium" | "High"

        ### content
        - metadata.contentType: Content format
        - metadata.status: "draft" | "published" | "archived"
        - structured.theme: Theme configuration object

        ### research
        - metadata.url: Source URL
        - metadata.summary: Research summary
        - metadata.researchType: Research category
        - metadata.processingStatus: "new" | "processing" | "complete"
        - metadata.isSwipeFile: Boolean for swipe file entries
        - structured.autoMetadata: Rich content metadata (transcripts, etc.)

        ### connection (Mental Model)
        - structured.idea: Core idea
        - structured.goal: Primary goal
        - structured.problems: Problems addressed
        - structured.benefit: Key benefits
        - structured.example: Concrete example
        - structured.process: Process steps
        - structured.referencesData: Related references

        ### schedule_block
        - metadata.blockType: "task" | "event" | "focus"
        - metadata.status: "todo" | "completed"
        - metadata.startTime, endTime: ISO8601 timestamps
        - structured.checklist: JSON array
        - structured.recurrence: Recurrence rule

        ### uncommitted_item
        - body: Raw captured text
        - metadata.captureMethod: "voice" | "keyboard" | "quick"
        - metadata.assignmentStatus: "assigned" | "suggested" | "unassigned"
        - links: May include promoted_to link when converted

        ## Relationships (via links field)
        - project: Link to parent project
        - parent_idea: Hierarchical link to parent idea
        - origin_idea: Task derived from idea
        - connection: Link to mental model connection
        - promoted_to: Uncommitted item converted to entity
        - recurrence_parent: Recurring event parent

        ## Querying Atoms
        - Filter by type: WHERE type = 'idea'
        - Filter by project: WHERE links LIKE '%{projectUuid}%'
        - Full-text search: Use atoms_fts table with BM25 ranking
        - Semantic search: Use semantic_chunks table with vector similarity
        """
    }

    /// Generate a concise type list for LLM tools
    static func typeDescriptions() -> [String: String] {
        [
            "idea": "Thoughts, concepts, and notes",
            "task": "Actionable items with status tracking",
            "project": "Container for organizing related items",
            "content": "Long-form written content pieces",
            "research": "External content with source tracking",
            "connection": "Mental model connecting concepts",
            "journal_entry": "Daily reflections with AI response",
            "calendar_event": "Legacy calendar events",
            "schedule_block": "Scheduled time blocks",
            "uncommitted_item": "Captured thoughts before categorization"
        ]
    }
}

// MARK: - Atom Query Builder

/// Fluent query builder for Atom queries
struct AtomQueryBuilder {
    private var types: [AtomType] = []
    private var projectUuid: String?
    private var includeDeleted: Bool = false
    private var limit: Int = 100
    private var offset: Int = 0
    private var orderBy: String = "updated_at DESC"
    private var whereClauses: [(String, [DatabaseValueConvertible])] = []

    /// Filter by atom type
    func type(_ type: AtomType) -> AtomQueryBuilder {
        var copy = self
        copy.types.append(type)
        return copy
    }

    /// Filter by multiple types
    func types(_ types: [AtomType]) -> AtomQueryBuilder {
        var copy = self
        copy.types.append(contentsOf: types)
        return copy
    }

    /// Filter by project
    func project(_ uuid: String) -> AtomQueryBuilder {
        var copy = self
        copy.projectUuid = uuid
        return copy
    }

    /// Include deleted atoms
    func includingDeleted() -> AtomQueryBuilder {
        var copy = self
        copy.includeDeleted = true
        return copy
    }

    /// Set result limit
    func limit(_ limit: Int) -> AtomQueryBuilder {
        var copy = self
        copy.limit = limit
        return copy
    }

    /// Set pagination offset
    func offset(_ offset: Int) -> AtomQueryBuilder {
        var copy = self
        copy.offset = offset
        return copy
    }

    /// Order by field
    func orderBy(_ field: String, ascending: Bool = false) -> AtomQueryBuilder {
        var copy = self
        copy.orderBy = "\(field) \(ascending ? "ASC" : "DESC")"
        return copy
    }

    /// Add custom where clause
    func `where`(_ clause: String, _ arguments: DatabaseValueConvertible...) -> AtomQueryBuilder {
        var copy = self
        copy.whereClauses.append((clause, arguments))
        return copy
    }

    /// Execute the query
    func execute(in db: Database) throws -> [Atom] {
        var sql = "SELECT * FROM atoms WHERE 1=1"
        var arguments: [DatabaseValueConvertible] = []

        if !includeDeleted {
            sql += " AND is_deleted = 0"
        }

        if !types.isEmpty {
            let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
            sql += " AND type IN (\(typeList))"
        }

        if let projectUuid = projectUuid {
            sql += " AND links LIKE ?"
            arguments.append("%\(projectUuid)%")
        }

        for (clause, clauseArgs) in whereClauses {
            sql += " AND \(clause)"
            arguments.append(contentsOf: clauseArgs)
        }

        sql += " ORDER BY \(orderBy) LIMIT ? OFFSET ?"
        arguments.append(limit)
        arguments.append(offset)

        return try Atom.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }
}

// MARK: - Convenience Extensions

extension CosmoDatabase {
    /// Create a query builder for atoms
    func atomQuery() -> AtomQueryBuilder {
        AtomQueryBuilder()
    }
}
