// CosmoOS/Data/Models/Seedling.swift
// The global Seedbed (July 2026) — a seedling is a named proto-concept
// accruing captured thoughts BEFORE it earns a Concept page. Quick thoughts
// routed "grow" here instead of landing as canvas note-cards; a page is born
// only through a development conversation, never from a checkbox (the
// CONCEPT_RIPENING_PLAN contract, generalized beyond Deep Dives).
// Synced Mac ↔ iPhone: column names match the iOS CosmoCoreKit table and the
// Supabase `seedlings` table exactly (camelCase data + snake sync columns).

import Foundation
import GRDB

// MARK: - Enums
// All decode tolerantly (shared contract): one row with an unknown rawValue
// (newer app version, sync drift) must not poison every fetch.

enum SeedlingStatus: String, Codable, Sendable {
    case growing        // Accruing mass — the resting state
    case developed      // A Concept page was born from it (developedConnectionUUID set)
    case folded         // User folded it away; thoughts stop accruing

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SeedlingStatus(rawValue: raw) ?? .growing
    }
}

enum SeedlingThoughtSource: String, Codable, Sendable {
    case inbox          // Routed from the triage queue
    case lane           // Routed from a capture lane
    case manual         // Typed directly into the seedling
    case study          // Deep Dive / research session material
    case mint           // Highlighted while developing another concept (the
                        // grow pill) — sourceAtomUUID names the origin page

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SeedlingThoughtSource(rawValue: raw) ?? .manual
    }
}

// MARK: - Staged thought

/// One captured thought inside a seedling, with full provenance back to the
/// capture that carried it. When the page is born, every claim keeps its
/// origin (`sourceUUID` + `capturedAt`). Study-born thoughts (the Deep Dive
/// seedbed, unified July 2026) additionally carry their research provenance —
/// the extract, its source atom, the session, and the section the routing
/// engine proposed.
struct SeedlingThought: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var sourceKind: SeedlingThoughtSource
    /// InboxItem / CapturedItem uuid this thought arrived through, if any.
    var sourceUUID: String?
    var capturedAt: String
    /// Set when a development conversation attached this thought into a page.
    var consumedAt: String?
    // Research provenance (sourceKind == .study; nil elsewhere)
    /// The extract atom this thought was captured as.
    var sourceExtractUUID: String?
    /// The source (video/article) the extract came from.
    var sourceAtomUUID: String?
    /// ConnectionSectionType rawValue the routing engine proposed.
    var proposedSection: String?
    /// The inquiry session that contributed it — the dive ripeness signal.
    var sessionUUID: String?

    init(
        id: String = UUID().uuidString,
        text: String,
        sourceKind: SeedlingThoughtSource,
        sourceUUID: String? = nil,
        capturedAt: String = ISO8601.string(from: Date()),
        consumedAt: String? = nil,
        sourceExtractUUID: String? = nil,
        sourceAtomUUID: String? = nil,
        proposedSection: String? = nil,
        sessionUUID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.sourceKind = sourceKind
        self.sourceUUID = sourceUUID
        self.capturedAt = capturedAt
        self.consumedAt = consumedAt
        self.sourceExtractUUID = sourceExtractUUID
        self.sourceAtomUUID = sourceAtomUUID
        self.proposedSection = proposedSection
        self.sessionUUID = sessionUUID
    }

    enum CodingKeys: String, CodingKey {
        case id, text, sourceKind, sourceUUID, capturedAt, consumedAt
        case sourceExtractUUID, sourceAtomUUID, proposedSection, sessionUUID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sourceKind = try c.decodeIfPresent(SeedlingThoughtSource.self, forKey: .sourceKind) ?? .manual
        sourceUUID = try c.decodeIfPresent(String.self, forKey: .sourceUUID)
        capturedAt = try c.decodeIfPresent(String.self, forKey: .capturedAt) ?? ISO8601.string(from: Date())
        consumedAt = try c.decodeIfPresent(String.self, forKey: .consumedAt)
        sourceExtractUUID = try c.decodeIfPresent(String.self, forKey: .sourceExtractUUID)
        sourceAtomUUID = try c.decodeIfPresent(String.self, forKey: .sourceAtomUUID)
        proposedSection = try c.decodeIfPresent(String.self, forKey: .proposedSection)
        sessionUUID = try c.decodeIfPresent(String.self, forKey: .sessionUUID)
    }
}

// MARK: - Seedling

struct Seedling: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable, Syncable, HasUUID {
    static let databaseTableName = "seedlings"

    var id: Int64?
    var uuid: String
    /// Normalized identity (`ConceptResolver.conceptKey(name)`) — the same
    /// key the Deep Dive seedbeds and the live router's capture-time tags
    /// use, so related thoughts accrue to ONE seedling everywhere.
    var conceptKey: String
    var name: String
    var aliasesJSON: String?
    var thoughtsJSON: String?
    var status: SeedlingStatus
    /// User-pinned = ripe regardless of mass.
    var pinnedAt: String?
    /// Existing Concept page this seedling feeds — developing it opens THAT
    /// page instead of creating a new one.
    var mergeTargetConnectionUUID: String?
    /// The page born from this seedling (set when status becomes .developed).
    var developedConnectionUUID: String?
    /// Optional research scope; NULL = a global seedling.
    var scopeDeepDiveUUID: String?
    /// The resolver's concept hierarchy (dive seedbeds): parent concept name
    /// and related concept names — centrality signals for ripeness surfacing.
    var parentConceptName: String?
    var relatedConceptNamesJSON: String?
    // Spatial affinity (where the mass would likely land once developed) —
    // powers "N growing" badges on cluster/space tiles without ever putting
    // a raw thought on a canvas.
    var affinityClusterId: String?
    var affinityClusterName: String?
    var affinityThinkspaceId: String?
    var affinityThinkspaceName: String?
    var createdAt: String
    var updatedAt: String
    var lastTouchedAt: String

    // Sync bookkeeping (snake columns shared with iOS + Supabase). `updatedAt`
    // above stays app data.
    var isDeleted: Bool
    var syncUpdatedAt: String?
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, uuid, conceptKey, name, aliasesJSON, thoughtsJSON
        case status, pinnedAt, mergeTargetConnectionUUID, developedConnectionUUID
        case scopeDeepDiveUUID, parentConceptName, relatedConceptNamesJSON
        case affinityClusterId, affinityClusterName, affinityThinkspaceId, affinityThinkspaceName
        case createdAt, updatedAt, lastTouchedAt
        case isDeleted = "is_deleted"
        case syncUpdatedAt = "updated_at"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    // MARK: - Derived

    var aliases: [String] {
        Self.decodeStringArray(aliasesJSON)
    }

    var relatedConceptNames: [String] {
        Self.decodeStringArray(relatedConceptNamesJSON)
    }

    var thoughts: [SeedlingThought] {
        guard let thoughtsJSON, let data = thoughtsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SeedlingThought].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Thoughts not yet attached into a page by a development conversation.
    var pendingThoughts: [SeedlingThought] {
        thoughts.filter { $0.consumedAt == nil }
    }

    /// Distinct calendar days that contributed thoughts — the inbox-world
    /// analogue of the Deep Dive seedbed's "distinct sessions" signal.
    var distinctCaptureDays: Int {
        Set(pendingThoughts.map { String($0.capturedAt.prefix(10)) }).count
    }

    /// Deterministic, legible ripeness (the Gardener philosophy — signals,
    /// not vibes): pinned, or 4+ thoughts across 2+ days, or 7+ in a burst.
    var isRipe: Bool {
        guard status == .growing else { return false }
        if pinnedAt != nil { return true }
        let pending = pendingThoughts
        if pending.count >= 7 { return true }
        return pending.count >= 4 && distinctCaptureDays >= 2
    }

    /// The reason shown on the card ("6 thoughts · 3 days"). Always present —
    /// growing seedlings show their mass, ripe ones show why they're ready.
    var massSummary: String {
        let pending = pendingThoughts
        let days = distinctCaptureDays
        let thoughtsPart = "\(pending.count) thought\(pending.count == 1 ? "" : "s")"
        guard days > 1 else { return thoughtsPart }
        return "\(thoughtsPart) · \(days) days"
    }

    // MARK: - Mutation helpers (value-level; the repository persists)

    mutating func appendThought(_ thought: SeedlingThought) {
        var current = thoughts
        current.append(thought)
        setThoughts(current)
    }

    mutating func setThoughts(_ newThoughts: [SeedlingThought]) {
        if let data = try? JSONEncoder().encode(newThoughts) {
            thoughtsJSON = String(data: data, encoding: .utf8)
        }
        lastTouchedAt = ISO8601.string(from: Date())
    }

    mutating func setAliases(_ newAliases: [String]) {
        if let data = try? JSONEncoder().encode(newAliases) {
            aliasesJSON = String(data: data, encoding: .utf8)
        }
    }

    mutating func setRelatedConceptNames(_ names: [String]) {
        if let data = try? JSONEncoder().encode(names) {
            relatedConceptNamesJSON = String(data: data, encoding: .utf8)
        }
    }

    // MARK: - Factory

    static func new(
        name: String,
        firstThought: SeedlingThought? = nil,
        scopeDeepDiveUUID: String? = nil
    ) -> Seedling {
        let now = ISO8601.string(from: Date())
        var seedling = Seedling(
            id: nil,
            uuid: UUID().uuidString,
            conceptKey: ConceptResolver.conceptKey(name),
            name: name,
            aliasesJSON: "[]",
            thoughtsJSON: "[]",
            status: .growing,
            pinnedAt: nil,
            mergeTargetConnectionUUID: nil,
            developedConnectionUUID: nil,
            scopeDeepDiveUUID: scopeDeepDiveUUID,
            parentConceptName: nil,
            relatedConceptNamesJSON: "[]",
            affinityClusterId: nil,
            affinityClusterName: nil,
            affinityThinkspaceId: nil,
            affinityThinkspaceName: nil,
            createdAt: now,
            updatedAt: now,
            lastTouchedAt: now,
            isDeleted: false,
            syncUpdatedAt: now,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
        if let firstThought {
            seedling.appendThought(firstThought)
        }
        return seedling
    }

    private static func decodeStringArray(_ value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }
}
