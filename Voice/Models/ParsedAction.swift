// CosmoOS/Voice/Models/ParsedAction.swift
// LLM output model that maps directly to Atom operations

import Foundation

// MARK: - Parsed Action

/// Output from any model tier - maps directly to Atom operations.
/// This is the bridge between voice/LLM output and AtomRepository operations.
public struct ParsedAction: Codable, Sendable, Equatable {
    let action: ActionType
    let atomType: AtomType?
    let title: String?
    let body: String?
    let metadata: [String: VoiceAnyCodable]?
    let links: [AtomLinkQuery]?
    let targetUuid: String?       // For update/delete - resolved from context
    let target: TargetReference?  // For update/delete - when UUID unknown
    let query: String?            // For search
    let types: [AtomType]?        // For search filter
    let filter: [String: VoiceAnyCodable]?  // For search filter
    let items: [ParsedAction]?    // For batch operations
    let destination: String?      // For navigate
    let mode: SearchMode?         // For search (keyword vs semantic)
    let queryType: QueryType?     // For level system queries
    let dimension: String?        // For dimension-specific queries

    init(
        action: ActionType,
        atomType: AtomType? = nil,
        title: String? = nil,
        body: String? = nil,
        metadata: [String: VoiceAnyCodable]? = nil,
        links: [AtomLinkQuery]? = nil,
        targetUuid: String? = nil,
        target: TargetReference? = nil,
        query: String? = nil,
        types: [AtomType]? = nil,
        filter: [String: VoiceAnyCodable]? = nil,
        items: [ParsedAction]? = nil,
        destination: String? = nil,
        mode: SearchMode? = nil,
        queryType: QueryType? = nil,
        dimension: String? = nil
    ) {
        self.action = action
        self.atomType = atomType
        self.title = title
        self.body = body
        self.metadata = metadata
        self.links = links
        self.targetUuid = targetUuid
        self.target = target
        self.query = query
        self.types = types
        self.filter = filter
        self.items = items
        self.destination = destination
        self.mode = mode
        self.queryType = queryType
        self.dimension = dimension
    }

    // MARK: - JSON Conversion

    /// Convert metadata to JSON string for Atom storage
    var metadataJson: String? {
        guard let metadata = metadata else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convert links to AtomLink array for Atom storage
    func resolveLinks(using context: VoiceContext) -> [AtomLink]? {
        guard let links = links else { return nil }
        return links.compactMap { linkQuery -> AtomLink? in
            // If UUID is provided, use it directly
            if let uuid = linkQuery.uuid {
                return AtomLink(type: linkQuery.type, uuid: uuid, entityType: linkQuery.entityType)
            }
            // If query is provided, we need to resolve it via search
            // This would typically be done asynchronously
            return nil
        }
    }

    // MARK: - Decoding from LLM Output

    /// Decode from LLM JSON output string
    static func decode(from json: String) -> ParsedAction? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ParsedAction.self, from: data)
    }
}

// MARK: - Action Type

extension ParsedAction {
    public enum ActionType: String, Codable, Sendable {
        case create = "create"
        case update = "update"
        case delete = "delete"
        case search = "search"
        case batch = "batch"
        case navigate = "navigate"
        case query = "query"       // Level system and status queries
    }

    /// Query type for level system and status queries
    public enum QueryType: String, Codable, Sendable {
        // Level System Queries
        case levelStatus = "level_status"           // "What's my level?"
        case xpToday = "xp_today"                   // "How much XP today?"
        case xpBreakdown = "xp_breakdown"           // "Show XP breakdown"
        case dimensionStatus = "dimension_status"   // "How's my cognitive dimension?"

        // Streak Queries
        case streakStatus = "streak_status"         // "What's my streak?"
        case allStreaks = "all_streaks"             // "Show all streaks"
        case streakHistory = "streak_history"       // "Streak history"

        // Badge Queries
        case badgesEarned = "badges_earned"         // "What badges do I have?"
        case badgeProgress = "badge_progress"       // "What badge am I close to?"
        case badgeDetails = "badge_details"         // "Tell me about X badge"

        // Quest Queries
        case activeQuests = "active_quests"         // "What quests are active?"
        case questProgress = "quest_progress"       // "How's my quest progress?"

        // Health Queries
        case readinessScore = "readiness_score"     // "What's my readiness?"
        case hrvStatus = "hrv_status"               // "What's my HRV?"
        case sleepScore = "sleep_score"             // "How did I sleep?"
        case todayHealth = "today_health"           // "Health summary"

        // Summary Queries
        case dailySummary = "daily_summary"         // "Give me today's summary"
        case weeklySummary = "weekly_summary"       // "Weekly summary"
        case monthProgress = "month_progress"       // "Monthly progress"

        // Content Performance Queries
        case contentPerformance = "content_performance"   // "How's my content performing?"
        case totalReach = "total_reach"                   // "What's my total reach?"
        case engagementRate = "engagement_rate"           // "What's my engagement rate?"
        case viralCount = "viral_count"                   // "How many viral posts?"
        case viralContent = "viral_content"               // "Show viral content"
        case topContent = "top_content"                   // "What's my top content?"
        case pipelineStatus = "pipeline_status"           // "Content pipeline status"
        case activeContent = "active_content"             // "What content is active?"
        case creativeDimension = "creative_dimension"     // "How's my creative dimension?"
        case clientPerformance = "client_performance"     // "How's client content doing?"
        case clientList = "client_list"                   // "Show my clients"
    }

    public enum TargetReference: String, Codable, Sendable {
        case context = "context"      // Use contextual atom (editing/selected)
        case lastCreated = "last"     // Most recently created atom
        case firstResult = "first"    // First search result
    }

    public enum SearchMode: String, Codable, Sendable {
        case keyword = "keyword"
        case semantic = "semantic"
    }
}

// MARK: - Atom Link Query

/// A link reference that may need resolution via search.
struct AtomLinkQuery: Codable, Sendable, Equatable {
    let type: String           // Link relationship type
    let uuid: String?          // If known
    let query: String?         // If needs resolution
    let entityType: String?    // Target entity type

    init(type: String, uuid: String? = nil, query: String? = nil, entityType: String? = nil) {
        self.type = type
        self.uuid = uuid
        self.query = query
        self.entityType = entityType
    }

    /// Convert to resolved AtomLink (if UUID is known)
    func toAtomLink() -> AtomLink? {
        guard let uuid = uuid else { return nil }
        return AtomLink(type: type, uuid: uuid, entityType: entityType)
    }
}

// MARK: - Voice Any Codable

/// Type-erased Codable for flexible JSON handling in Voice/ParsedAction
/// Named VoiceAnyCodable to avoid conflict with AnyCodable in CosmoVoiceDaemon
/// @unchecked Sendable because we only store primitive Sendable types (Bool, Int, Double, String, Arrays, Dictionaries)
struct VoiceAnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([VoiceAnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: VoiceAnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Could not decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { VoiceAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { VoiceAnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode value")
            throw EncodingError.invalidValue(value, context)
        }
    }

    static func == (lhs: VoiceAnyCodable, rhs: VoiceAnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        default:
            return false
        }
    }

    // Convenience accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
}
