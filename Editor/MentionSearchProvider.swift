import Foundation
import GRDB

struct MentionSearchResult: Identifiable, Equatable, Sendable {
    let atomID: Int64?
    let atomUUID: String
    let atomType: AtomType
    let entityType: EntityType
    let title: String
    let subtitle: String?
    let typeLabel: String
    let updatedAt: String
    let recencyKey: String
    let score: Double

    var id: String { atomUUID }

    var mention: RichMention {
        RichMention(
            entityUUID: atomUUID,
            entityID: atomID,
            entityType: entityType,
            titleSnapshot: title
        )
    }
}

actor MentionSearchProvider {
    static let shared = MentionSearchProvider()

    private let searchEngine = AtomSearchEngine()

    init() {}

    func search(query: String, limit: Int = 12) async -> [MentionSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedTypes = AtomType.mentionableTypes

        if trimmed.isEmpty {
            return await recentResults(limit: limit, allowedTypes: allowedTypes)
        }

        var combined: [String: MentionSearchResult] = [:]
        let lowered = trimmed.lowercased()

        if let exactResults = try? await searchEngine.exactSearch(
            query: trimmed,
            field: .title,
            options: AtomSearchOptions(types: allowedTypes, limit: limit * 2)
        ) {
            for result in exactResults {
                merge(result: atomResult(for: result.atom, query: lowered, baseScore: 300), into: &combined)
            }
        }

        if let ftsResults = try? await searchEngine.search(
            query: trimmed,
            options: AtomSearchOptions(types: allowedTypes, limit: limit * 3)
        ) {
            for result in ftsResults {
                merge(result: atomResult(for: result.atom, query: lowered, baseScore: 100 + result.score), into: &combined)
            }
        }

        if combined.count < limit,
           let containsResults = try? await containsMatches(query: lowered, allowedTypes: allowedTypes, limit: limit * 3) {
            for atom in containsResults {
                merge(result: atomResult(for: atom, query: lowered, baseScore: 60), into: &combined)
            }
        }

        return combined.values
            .sorted(by: compareResults)
            .prefix(limit)
            .map { $0 }
    }

    private func recentResults(limit: Int, allowedTypes: [AtomType]) async -> [MentionSearchResult] {
        let database = await MainActor.run { CosmoDatabase.shared }
        guard let atoms = try? await database.asyncRead({ db in
            try Atom
                .filter(allowedTypes.map(\.rawValue).contains(Column("type")))
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }) else {
            return []
        }

        return atoms.map { atomResult(for: $0, query: "", baseScore: 10) }
    }

    private func containsMatches(query: String, allowedTypes: [AtomType], limit: Int) async throws -> [Atom] {
        let database = await MainActor.run { CosmoDatabase.shared }
        return try await database.asyncRead { db in
            try Atom
                .filter(allowedTypes.map(\.rawValue).contains(Column("type")))
                .filter(Column("is_deleted") == false)
                .filter(
                    Column("title").like("%\(query)%") ||
                    Column("body").like("%\(query)%")
                )
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    private func atomResult(for atom: Atom, query: String, baseScore: Double) -> MentionSearchResult {
        let title = (atom.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? (atom.body?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60).description ?? "Untitled") : title
        let subtitle = atom.body
            .flatMap { body -> String? in
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != displayTitle else { return nil }
                return String(trimmed.prefix(80))
            }

        let typeLabel = atom.type.displayName
        let entityType = atom.type.entityTypeForMention
        let titleLower = displayTitle.lowercased()

        var score = baseScore
        if !query.isEmpty {
            if titleLower == query {
                score += 200
            } else if titleLower.hasPrefix(query) {
                score += 140
            } else if titleLower.contains(query) {
                score += 80
            } else if subtitle?.lowercased().contains(query) == true {
                score += 35
            }
        }

        if let updated = ISO8601.date(from: atom.updatedAt) {
            score += max(0, 10 - Date().timeIntervalSince(updated) / 86_400.0)
        }

        let recencyKey = MentionSearchRanking.recencyKey(for: atom)

        return MentionSearchResult(
            atomID: atom.id,
            atomUUID: atom.uuid,
            atomType: atom.type,
            entityType: entityType,
            title: displayTitle,
            subtitle: subtitle,
            typeLabel: typeLabel,
            updatedAt: atom.updatedAt,
            recencyKey: recencyKey,
            score: score
        )
    }

    private func merge(result: MentionSearchResult, into combined: inout [String: MentionSearchResult]) {
        if let existing = combined[result.atomUUID], existing.score >= result.score {
            return
        }
        combined[result.atomUUID] = result
    }

    private func compareResults(lhs: MentionSearchResult, rhs: MentionSearchResult) -> Bool {
        MentionSearchRanking.compare(lhs, rhs)
    }
}

enum MentionSearchRanking {
    static func compare(_ lhs: MentionSearchResult, _ rhs: MentionSearchResult) -> Bool {
        if lhs.recencyKey != rhs.recencyKey {
            return lhs.recencyKey > rhs.recencyKey
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    static func recencyKey(for atom: Atom) -> String {
        if atom.type == .thinkspace,
           let metadata = atom.metadataValue(as: ThinkspaceMetadata.self) {
            return sortableTimestamp(from: metadata.lastOpened) ?? atom.updatedAt
        }

        if let lastOpenedAt = atom.lastOpenedAt,
           let normalized = sortableTimestamp(from: lastOpenedAt) {
            return normalized
        }

        if let normalized = sortableTimestamp(from: atom.updatedAt) {
            return normalized
        }

        if let normalized = sortableTimestamp(from: atom.createdAt) {
            return normalized
        }

        return atom.updatedAt
    }

    static func sortableTimestamp(from date: Date) -> String? {
        sortableTimestampFormatter.string(from: date)
    }

    static func sortableTimestamp(from rawValue: String) -> String? {
        guard !rawValue.isEmpty else { return nil }

        for formatter in parsers {
            if let date = formatter.date(from: rawValue) {
                return sortableTimestampFormatter.string(from: date)
            }
        }

        return normalizedSQLiteTimestamp(rawValue)
    }

    private static func normalizedSQLiteTimestamp(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 19 else { return nil }

        let prefix = String(trimmed.prefix(19))
        let allowedCharacters = CharacterSet(charactersIn: "0123456789-: ")
        guard prefix.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }

        return prefix.replacingOccurrences(of: " ", with: "T") + ".000Z"
    }

    private static let sortableTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let parsers: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractional.timeZone = TimeZone(secondsFromGMT: 0)

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        standard.timeZone = TimeZone(secondsFromGMT: 0)

        return [fractional, standard]
    }()
}

private extension AtomType {
    static let mentionableTypes: [AtomType] = [
        .idea,
        .content,
        .research,
        .connection,
        .task,
        .project,
        .note,
        .objective,
        .creator,
        .thinkspace,
        .image,
        .stickyNote
    ]

    var entityTypeForMention: EntityType {
        switch self {
        case .idea:
            return .idea
        case .content:
            return .content
        case .research:
            return .research
        case .connection:
            return .connection
        case .task:
            return .task
        case .project:
            return .project
        case .note:
            return .note
        case .thinkspace:
            return .thinkspace
        case .image:
            return .image
        case .creator:
            return .swipeFile
        case .objective:
            return .project
        default:
            return .idea
        }
    }
}
