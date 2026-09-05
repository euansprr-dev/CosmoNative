import Foundation
import CryptoKit

/// Lab state lives under one optional metadata key on an inquiry-session atom.
/// Original media and transcripts stay on their source atoms.
struct SwipeLabEnvelope: Codable, Sendable {
    var swipeLab: SwipeLabSessionState
}

struct SwipeLabScope: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case board, selection, library, client }
    var kind: Kind
    var title: String
    var boardID: String? = nil
    var sourceIDs: [String] = []
    /// Author/source population, independent of the client used for adaptation.
    var populationClientID: String? = nil
    var platform: String? = nil
    var format: String? = nil
    var publishedAfter: Date? = nil
    var publishedBefore: Date? = nil

    var identity: String {
        SwipeLabHash.string([kind.rawValue, boardID ?? "", populationClientID ?? "",
            sourceIDs.sorted().joined(separator: ","), platform ?? "", format ?? "",
            publishedAfter.map { String($0.timeIntervalSince1970) } ?? "",
            publishedBefore.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "|"))
    }

    static func board(_ board: SwipeBoard) -> Self {
        .init(kind: .board, title: board.name, boardID: board.uuid)
    }
    static func selection(_ ids: [String], title: String = "Selected swipes") -> Self {
        .init(kind: .selection, title: title, sourceIDs: Array(Set(ids)).sorted())
    }
    static func client(_ id: String, name: String) -> Self {
        .init(kind: .client, title: "\(name)’s posts", populationClientID: id)
    }
}

enum SwipeLabMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case study, compare, practise, notebook, outcomes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .study: return "Study"
        case .compare: return "Compare"
        case .practise: return "Practise"
        case .notebook: return "Principles"
        case .outcomes: return "Outcomes"
        }
    }
    var icon: String {
        switch self {
        case .study: return "book"
        case .compare: return "rectangle.split.2x1"
        case .practise: return "pencil.and.outline"
        case .notebook: return "bookmark"
        case .outcomes: return "chart.xyaxis.line"
        }
    }
}

enum SwipeLabLens: String, Codable, CaseIterable, Identifiable, Sendable {
    case whole = "Whole post", hook = "Hook", structure = "Structure", voice = "Voice"
    case pacing = "Pacing", proof = "Proof", visuals = "Visuals", payoff = "Payoff", cta = "Call to action"
    var id: String { rawValue }
}

enum SwipeLabMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case views, likes, comments, shares, saves, follows
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SwipeLabMetricObservation: Codable, Equatable, Sendable, Identifiable {
    var metric: SwipeLabMetric
    var value: Int
    var platform: String
    var capturedAt: Date?
    var publishedAt: Date?
    var provenance: String
    var isPaid: Bool? = nil
    var id: String { "\(metric.rawValue)|\(platform)|\(capturedAt?.timeIntervalSince1970 ?? -1)" }
    var ageHours: Double? {
        guard let capturedAt, let publishedAt, capturedAt >= publishedAt else { return nil }
        return capturedAt.timeIntervalSince(publishedAt) / 3600
    }
}

struct SwipeLabAnchor: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case slide, speech, artifact, text }
    var sourceID: String
    var sourceHash: String
    var unitID: String
    var kind: Kind
    var label: String
    var quote: String
    var slideNumber: Int? = nil
    var startSeconds: Double? = nil
    var endSeconds: Double? = nil
    /// Ranges use UTF-16 offsets, matching NSTextView and NSRange.
    var utf16Start: Int? = nil
    var utf16Length: Int? = nil
    var id: String { "\(sourceID):\(unitID):\(utf16Start ?? 0):\(sourceHash.prefix(12))" }
}

struct SwipeLabUnit: Identifiable, Equatable, Sendable {
    var anchor: SwipeLabAnchor
    var job: String
    var text: String
    var hasVisual: Bool = false
    var id: String { anchor.id }
}

struct SwipeLabSource: Identifiable, Sendable {
    var atom: Atom
    var title: String
    var creator: String
    var creatorID: String?
    var platform: String
    var format: String
    var contentHash: String
    var units: [SwipeLabUnit]
    var metrics: [SwipeLabMetricObservation]
    var publishedAt: Date?
    var duplicateOf: String? = nil
    var isComparison: Bool = false
    var id: String { atom.uuid }
    var formatLabel: String { ContentFormat(rawValue: format)?.displayName ?? format.replacingOccurrences(of: "_", with: " ").capitalized }
    var platformLabel: String {
        if platform.lowercased().hasPrefix("instagram") { return "Instagram" }
        if platform.lowercased().hasPrefix("youtube") { return "YouTube" }
        return platform.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var isReadable: Bool { !units.isEmpty && duplicateOf == nil }
    var manifest: SwipeLabSourceManifest {
        .init(sourceID: id, title: title, contentHash: contentHash, unitCount: units.count,
              duplicateOf: duplicateOf, isComparison: isComparison, metricHash: metricHash)
    }
    var metricHash: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SwipeLabHash.string(String(data: (try? encoder.encode(metrics)) ?? Data(), encoding: .utf8) ?? "")
    }
}

struct SwipeLabSourceManifest: Codable, Equatable, Sendable, Identifiable {
    var sourceID: String
    var title: String
    var contentHash: String
    var unitCount: Int
    var duplicateOf: String?
    var isComparison: Bool
    var metricHash: String = ""
    var id: String { sourceID }
}

struct SwipeLabSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var capturedAt: Date = Date()
    var sources: [SwipeLabSourceManifest]
    var fingerprint: String {
        SwipeLabHash.string(sources.map { "\($0.sourceID)|\($0.contentHash)|\($0.metricHash)|\($0.isComparison)" }.sorted().joined(separator: "\n"))
    }
}

struct SwipeLabCoverage: Codable, Equatable, Sendable {
    var total: Int = 0
    var readable: Int = 0
    var inspectedIDs: [String] = []
    var failedIDs: [String] = []
    var duplicateCount: Int = 0
    var comparisonCount: Int = 0
    var imagesInspected: Int? = nil
    var inspected: Int { Set(inspectedIDs).count }
    var isComplete: Bool { inspected == readable && failedIDs.isEmpty && total == readable + duplicateCount }
    var label: String { "\(inspected) of \(readable) readable posts studied" }
}

struct SwipeLabFinding: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable { case proposed, accepted, archived, rejected }
    var id: String = UUID().uuidString
    var title: String
    var observation: String
    var mechanism: String
    var limitations: String
    var transfer: String
    var support: [SwipeLabAnchor]
    var counterevidence: [SwipeLabAnchor]
    var snapshotID: String
    var promptHash: String
    var status: Status = .proposed
    var clientID: String? = nil
    var connectionID: String? = nil
    var updatedAt: Date = Date()
    var supportCount: Int { Set(support.map(\.sourceID)).count }
}

struct SwipeLabTurn: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id: String = UUID().uuidString
    var role: Role
    var text: String
    var createdAt: Date = Date()
    var snapshotID: String?
    var coverage: SwipeLabCoverage?
    var findingIDs: [String] = []
    var anchors: [SwipeLabAnchor] = []
    var promptHash: String? = nil
    var questionID: String? = nil
}

struct SwipeLabPractice: Codable, Equatable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var sourceID: String
    var anchor: SwipeLabAnchor
    var question: String
    var answer: String = ""
    var feedback: String? = nil
    var application: String = ""
    var principleID: String? = nil
    var completedAt: Date? = nil
    var updatedAt: Date = Date()
}

struct SwipeLabExperiment: Codable, Equatable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var principleID: String
    var ideaID: String
    var clientID: String?
    var hypothesis: String
    var deliberateChange: String
    var counterPrediction: String
    var metric: SwipeLabMetric = .views
    var observationDays: Int = 7
    var contentID: String? = nil
    var review: String? = nil
    var resultNote: String = ""
    var updatedAt: Date = Date()
}

struct SwipeLabPosition: Codable, Equatable, Sendable {
    var sourceID: String
    var anchorID: String?
    var timestamp: Double = 0
}

struct SwipeLabSessionState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var scope: SwipeLabScope
    var targetClientID: String? = nil
    var comparisonScope: SwipeLabScope? = nil
    var snapshots: [SwipeLabSnapshot] = []
    var turns: [SwipeLabTurn] = []
    var findings: [SwipeLabFinding] = []
    var practices: [SwipeLabPractice] = []
    var experiments: [SwipeLabExperiment] = []
    var position: SwipeLabPosition? = nil
    var positions: [String: SwipeLabPosition] = [:]
    var comparisonSourceID: String? = nil
    var lens: SwipeLabLens = .whole
    var mode: SwipeLabMode = .study
    var metric: SwipeLabMetric = .views
    var draftQuestion: String = ""
    var guidance: String = ""
    var additionalModuleIDs: [String] = []
    var observedJobs: [String: String] = [:]
    var updatedAt: Date = Date()

    /// Concurrent windows retain both conversations and edits. Navigation is
    /// window-local; only its latest position is used on the next cold open.
    func mergingDurableHistory(from other: Self) -> Self {
        var result = self
        result.turns = Self.union(other.turns, turns, id: \.id).sorted { $0.createdAt < $1.createdAt }
        result.snapshots = Self.union(other.snapshots, snapshots, id: \.id).sorted { $0.capturedAt < $1.capturedAt }
        result.findings = Self.newest(other.findings, findings, id: \.id, date: \.updatedAt)
        result.practices = Self.newest(other.practices, practices, id: \.id, date: \.updatedAt)
        result.experiments = Self.newest(other.experiments, experiments, id: \.id, date: \.updatedAt)
        return result
    }

    private static func union<T>(_ old: [T], _ new: [T], id: KeyPath<T, String>) -> [T] {
        var values: [String: T] = [:]
        for value in old + new { values[value[keyPath: id]] = value }
        return values.keys.sorted().compactMap { values[$0] }
    }
    private static func newest<T>(_ old: [T], _ new: [T], id: KeyPath<T, String>, date: KeyPath<T, Date>) -> [T] {
        var values: [String: T] = [:]
        for value in old + new {
            let key = value[keyPath: id]
            if let existing = values[key], existing[keyPath: date] > value[keyPath: date] { continue }
            values[key] = value
        }
        return values.values.sorted { $0[keyPath: date] < $1[keyPath: date] }
    }
}

enum SwipeLabHash {
    static func string(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension Atom {
    var swipeLabState: SwipeLabSessionState? { metadataValue(as: SwipeLabEnvelope.self)?.swipeLab }
    var isSwipeLab: Bool {
        guard type == .inquirySession, let metadata else { return false }
        return metadata.contains("\"swipeLab\"")
    }
}
