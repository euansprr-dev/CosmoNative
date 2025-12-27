// CosmoOS/Data/Models/LevelSystem/ContentPipelineService.swift
// Content Pipeline Service - Orchestrates content lifecycle and performance tracking
// ALL operations create/update Atoms. No separate data structures.

import Foundation
import GRDB
import Combine

// MARK: - Content Pipeline Service

/// Main orchestration service for the content creation pipeline.
/// Tracks content through phases, records performance metrics, and integrates with Level System.
///
/// **Atom-First Architecture:**
/// - Content pieces are `.content` Atoms
/// - Drafts create `.contentDraft` Atoms linked to parent content
/// - Phase transitions create `.contentPhase` Atoms
/// - Performance data creates `.contentPerformance` Atoms
/// - Publishing creates `.contentPublish` Atoms
/// - Client profiles are `.clientProfile` Atoms
@MainActor
public final class ContentPipelineService: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var activeContent: [Atom] = []
    @Published public private(set) var recentPerformance: [Atom] = []
    @Published public private(set) var weeklyReach: Int = 0
    @Published public private(set) var monthlyViralCount: Int = 0
    @Published public private(set) var avgEngagementRate: Double = 0.0
    @Published public private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private let levelService: LevelSystemService
    private let analyticsEngine: ContentAnalyticsEngine
    private let predictionEngine: PerformancePredictionEngine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        database: (any DatabaseWriter)? = nil,
        levelService: LevelSystemService? = nil
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.levelService = levelService ?? LevelSystemService(database: CosmoDatabase.shared.dbQueue!)
        self.analyticsEngine = ContentAnalyticsEngine(database: self.database)
        self.predictionEngine = PerformancePredictionEngine(database: self.database)

        Task {
            await loadActiveContent()
            await calculateMetrics()
        }
    }

    // MARK: - Content Creation

    /// Create a new content piece as an Atom
    /// Returns a `.content` type Atom
    @discardableResult
    public func createContent(
        title: String,
        body: String? = nil,
        platform: SocialPlatform? = nil,
        clientUUID: String? = nil,
        projectUUID: String? = nil
    ) async throws -> Atom {

        let metadata = ContentAtomMetadata(
            phase: .ideation,
            platform: platform,
            clientProfileUUID: clientUUID,
            wordCount: body?.split(separator: " ").count ?? 0,
            createdPhaseAt: Date(),
            lastPhaseTransition: nil,
            predictedReach: nil,
            predictedEngagement: nil
        )

        var links: [AtomLink] = []
        if let projectUUID = projectUUID {
            links.append(.project(projectUUID))
        }
        if let clientUUID = clientUUID {
            links.append(AtomLink(type: "client", uuid: clientUUID, entityType: "clientProfile"))
        }

        // Capture immutable copies for Sendable closure
        let capturedMetadata = metadata
        let capturedLinks = links

        let atom = try await database.write { db -> Atom in
            var newAtom = Atom.new(
                type: .content,
                title: title,
                body: body
            )
            newAtom.metadata = capturedMetadata.toJSON()
            if !capturedLinks.isEmpty {
                if let linksData = try? JSONEncoder().encode(capturedLinks) {
                    newAtom.links = String(data: linksData, encoding: .utf8)
                }
            }
            try newAtom.insert(db)
            return newAtom
        }

        // Award XP for starting new content
        await awardContentXP(xp: 5, reason: "Started new content: \(title)", contentUUID: atom.uuid)

        await loadActiveContent()
        return atom
    }

    // MARK: - Phase Transitions

    /// Advance content to the next phase
    /// Creates a `.contentPhase` Atom to record the transition
    @discardableResult
    public func advancePhase(
        contentUUID: String,
        notes: String? = nil
    ) async throws -> Atom {

        // Fetch current content atom
        guard let contentAtom = try await fetchContentAtom(uuid: contentUUID) else {
            throw ContentPipelineError.contentNotFound
        }

        guard var metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self) else {
            throw ContentPipelineError.invalidMetadata
        }

        let currentPhase = metadata.phase
        guard let nextPhase = currentPhase.nextPhase else {
            throw ContentPipelineError.alreadyAtFinalPhase
        }

        let timeInPreviousPhase = metadata.createdPhaseAt.map { Date().timeIntervalSince($0) } ?? 0

        // Create phase transition atom
        let phaseMetadata = ContentPhaseMetadata(
            contentAtomUUID: contentUUID,
            fromPhase: currentPhase,
            toPhase: nextPhase,
            timestamp: Date(),
            wordCountAtTransition: metadata.wordCount,
            timeSpentInPreviousPhase: timeInPreviousPhase,
            xpEarned: nextPhase.completionXP,
            transitionNotes: notes
        )

        let phaseAtom = try await database.write { db -> Atom in
            var atom = Atom.new(
                type: .contentPhase,
                title: "\(currentPhase.displayName) → \(nextPhase.displayName)",
                body: notes
            )
            atom.metadata = phaseMetadata.toJSON()
            if let linksData = try? JSONEncoder().encode([
                AtomLink(type: "content", uuid: contentUUID, entityType: "content")
            ]) {
                atom.links = String(data: linksData, encoding: .utf8)
            }
            try atom.insert(db)
            return atom
        }

        // Update content atom with new phase
        metadata.phase = nextPhase
        metadata.lastPhaseTransition = Date()
        metadata.createdPhaseAt = Date()

        // Create immutable copy for Sendable closure
        var updatedAtom = contentAtom
        updatedAtom.metadata = metadata.toJSON()
        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
        let atomToUpdate = updatedAtom

        try await database.write { db in
            try atomToUpdate.update(db)
        }

        // Award XP for phase completion
        await awardContentXP(
            xp: nextPhase.completionXP,
            reason: "Completed \(currentPhase.displayName) phase",
            contentUUID: contentUUID
        )

        // If published, generate performance prediction
        if nextPhase == .published {
            await generatePerformancePrediction(for: contentUUID)
        }

        await loadActiveContent()
        return phaseAtom
    }

    // MARK: - Content Publishing

    /// Record a content publish event
    /// Creates a `.contentPublish` Atom
    @discardableResult
    public func recordPublish(
        contentUUID: String,
        platform: SocialPlatform,
        postId: String,
        postUrl: String? = nil,
        wasScheduled: Bool = false
    ) async throws -> Atom {

        guard let contentAtom = try await fetchContentAtom(uuid: contentUUID) else {
            throw ContentPipelineError.contentNotFound
        }

        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)

        let publishMetadata = ContentPublishMetadata(
            contentAtomUUID: contentUUID,
            platform: platform,
            postId: postId,
            publishedAt: Date(),
            postUrl: postUrl,
            clientProfileUUID: metadata?.clientProfileUUID,
            wasScheduled: wasScheduled,
            wordCount: metadata?.wordCount ?? 0,
            mediaType: .text
        )

        let publishAtom = try await database.write { db -> Atom in
            var atom = Atom.new(
                type: .contentPublish,
                title: "Published to \(platform.displayName)",
                body: postUrl
            )
            atom.metadata = publishMetadata.toJSON()
            if let linksData = try? JSONEncoder().encode([
                AtomLink(type: "content", uuid: contentUUID, entityType: "content")
            ]) {
                atom.links = String(data: linksData, encoding: .utf8)
            }
            try atom.insert(db)
            return atom
        }

        // Advance to published phase if not already
        if let currentMetadata = metadata, currentMetadata.phase != .published {
            try await advancePhase(contentUUID: contentUUID, notes: "Auto-advanced on publish")
        }

        // Award XP for publishing
        await awardContentXP(xp: 20, reason: "Published to \(platform.displayName)", contentUUID: contentUUID)

        return publishAtom
    }

    // MARK: - Performance Tracking

    /// Record performance metrics for published content
    /// Creates a `.contentPerformance` Atom
    @discardableResult
    public func recordPerformance(
        contentUUID: String,
        platform: SocialPlatform,
        postId: String,
        impressions: Int,
        reach: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        saves: Int,
        profileVisits: Int? = nil,
        followsGained: Int? = nil,
        views: Int? = nil,
        watchTimeSeconds: Int? = nil,
        avgWatchPercentage: Double? = nil
    ) async throws -> Atom {

        let engagement = likes + comments + shares + saves
        let engagementRate = impressions > 0 ? Double(engagement) / Double(impressions) : 0

        // Calculate virality
        let viralityThreshold = platform.viralityThreshold
        let isViral = impressions >= viralityThreshold.impressions && engagementRate >= viralityThreshold.engagementRate

        // Calculate virality score (0-100)
        let viralityScore = await analyticsEngine.calculateViralityScore(
            impressions: impressions,
            engagementRate: engagementRate,
            platform: platform
        )

        // Calculate vs average performance
        let avgPerformance = await analyticsEngine.calculateAveragePerformance(for: platform)
        let vsAverage = avgPerformance > 0 ? (Double(impressions) / avgPerformance) : 1.0

        let perfMetadata = ContentPerformanceMetadata(
            platform: platform,
            postId: postId,
            publishedAt: Date(),
            impressions: impressions,
            reach: reach,
            engagement: engagement,
            likes: likes,
            comments: comments,
            shares: shares,
            saves: saves,
            profileVisits: profileVisits,
            followsGained: followsGained,
            engagementRate: engagementRate,
            viralityScore: viralityScore,
            isViral: isViral,
            lastUpdated: Date(),
            views: views,
            watchTimeSeconds: watchTimeSeconds,
            avgWatchPercentage: avgWatchPercentage,
            vsAveragePerformance: vsAverage
        )

        let performanceAtom = try await database.write { db -> Atom in
            var atom = Atom.new(
                type: .contentPerformance,
                title: "\(impressions.formatted()) impressions",
                body: "Performance snapshot for \(platform.displayName)"
            )
            atom.metadata = perfMetadata.toJSON()
            if let linksData = try? JSONEncoder().encode([
                AtomLink(type: "content", uuid: contentUUID, entityType: "content")
            ]) {
                atom.links = String(data: linksData, encoding: .utf8)
            }
            try atom.insert(db)
            return atom
        }

        // Award XP based on performance
        let xp = perfMetadata.estimatedXP
        if xp > 0 {
            await awardContentXP(
                xp: xp,
                reason: isViral ? "Viral content on \(platform.displayName)!" : "Content performance on \(platform.displayName)",
                contentUUID: contentUUID
            )
        }

        // Update aggregate metrics
        await calculateMetrics()

        // Check for performance matching (actual vs predicted)
        await performanceMatching(contentUUID: contentUUID, actualImpressions: impressions)

        return performanceAtom
    }

    // MARK: - Performance Matching

    /// Compare actual performance to predictions and award bonus XP
    private func performanceMatching(contentUUID: String, actualImpressions: Int) async {
        guard let contentAtom = try? await fetchContentAtom(uuid: contentUUID),
              let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self),
              let predicted = metadata.predictedReach else {
            return
        }

        let ratio = Double(actualImpressions) / Double(predicted)

        // Award bonus XP for exceeding predictions
        if ratio >= 2.0 {
            await awardContentXP(
                xp: 100,
                reason: "Exceeded prediction by 2x+!",
                contentUUID: contentUUID
            )
        } else if ratio >= 1.5 {
            await awardContentXP(
                xp: 50,
                reason: "Exceeded prediction by 50%",
                contentUUID: contentUUID
            )
        } else if ratio >= 1.0 {
            await awardContentXP(
                xp: 25,
                reason: "Met performance prediction",
                contentUUID: contentUUID
            )
        }

        // Record the performance match result
        await predictionEngine.recordPredictionResult(
            contentUUID: contentUUID,
            predicted: predicted,
            actual: actualImpressions
        )
    }

    // MARK: - Predictions

    /// Generate performance prediction for content
    private func generatePerformancePrediction(for contentUUID: String) async {
        guard let contentAtom = try? await fetchContentAtom(uuid: contentUUID),
              var metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self) else {
            return
        }

        // Calculate prediction based on historical data
        let prediction = await predictionEngine.predictPerformance(
            platform: metadata.platform ?? .twitter,
            wordCount: metadata.wordCount,
            clientUUID: metadata.clientProfileUUID
        )

        metadata.predictedReach = prediction.reach
        metadata.predictedEngagement = prediction.engagementRate

        // Create immutable copy for Sendable closure
        var updatedAtom = contentAtom
        updatedAtom.metadata = metadata.toJSON()
        let atomToUpdate = updatedAtom

        try? await database.write { db in
            try atomToUpdate.update(db)
        }
    }

    // MARK: - Client Profiles

    /// Create a client profile Atom for ghostwriting
    @discardableResult
    public func createClientProfile(
        name: String,
        platforms: [SocialPlatform],
        industry: String? = nil,
        targetAudience: String? = nil,
        notes: String? = nil
    ) async throws -> Atom {

        let metadata = ClientProfileMetadata(
            clientId: UUID().uuidString,
            clientName: name,
            platforms: platforms,
            totalReach: 0,
            avgEngagementRate: 0,
            contentCount: 0,
            viralPostCount: 0,
            activeStatus: true,
            clientSince: Date(),
            lastContentDate: nil,
            notes: notes,
            industry: industry,
            targetAudience: targetAudience
        )

        let clientAtom = try await database.write { db -> Atom in
            var atom = Atom.new(
                type: .clientProfile,
                title: name,
                body: notes
            )
            atom.metadata = metadata.toJSON()
            try atom.insert(db)
            return atom
        }

        return clientAtom
    }

    // MARK: - Drafts

    /// Save a draft version of content
    /// Creates a `.contentDraft` Atom linked to parent content
    @discardableResult
    public func saveDraft(
        contentUUID: String,
        body: String,
        authorNotes: String? = nil
    ) async throws -> Atom {

        guard let contentAtom = try? await fetchContentAtom(uuid: contentUUID),
              let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self) else {
            throw ContentPipelineError.contentNotFound
        }

        // Get latest draft version
        let latestVersion = try await getLatestDraftVersion(contentUUID: contentUUID)
        let newVersion = latestVersion + 1

        let previousWordCount = metadata.wordCount
        let newWordCount = body.split(separator: " ").count

        let draftMetadata = ContentDraftMetadata(
            contentAtomUUID: contentUUID,
            version: newVersion,
            phase: metadata.phase,
            wordCount: newWordCount,
            createdAt: Date(),
            authorNotes: authorNotes,
            diffSummary: nil,
            wordsAdded: max(0, newWordCount - previousWordCount),
            wordsRemoved: max(0, previousWordCount - newWordCount)
        )

        let draftAtom = try await database.write { db -> Atom in
            var atom = Atom.new(
                type: .contentDraft,
                title: "Draft v\(newVersion)",
                body: body
            )
            atom.metadata = draftMetadata.toJSON()
            if let linksData = try? JSONEncoder().encode([
                AtomLink(type: "content", uuid: contentUUID, entityType: "content")
            ]) {
                atom.links = String(data: linksData, encoding: .utf8)
            }
            try atom.insert(db)
            return atom
        }

        // Update content atom with new word count
        try await updateContentWordCount(contentUUID: contentUUID, wordCount: newWordCount)

        // Award XP for writing
        if draftMetadata.wordsAdded > 100 {
            await awardContentXP(
                xp: 10,
                reason: "Added \(draftMetadata.wordsAdded) words",
                contentUUID: contentUUID
            )
        }

        return draftAtom
    }

    // MARK: - Queries

    /// Fetch content atom by UUID
    public func fetchContentAtom(uuid: String) async throws -> Atom? {
        try await database.read { db in
            try Atom
                .filter(Column("uuid") == uuid)
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchOne(db)
        }
    }

    /// Fetch all content in a specific phase
    public func fetchContentInPhase(_ phase: ContentPhase) async throws -> [Atom] {
        try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(sql: "json_extract(metadata, '$.phase') = ?", arguments: [phase.rawValue])
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch performance atoms for content
    public func fetchPerformanceHistory(contentUUID: String) async throws -> [Atom] {
        try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(sql: "links LIKE ?", arguments: ["%\(contentUUID)%"])
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch all viral content
    public func fetchViralContent(limit: Int = 20) async throws -> [Atom] {
        try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(sql: "json_extract(metadata, '$.isViral') = true")
                .order(sql: "json_extract(metadata, '$.impressions') DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Get today's content performance summary
    public func getTodayPerformanceSummary() async throws -> ContentPerformanceSummary {
        let todayStart = Calendar.current.startOfDay(for: Date())

        let performanceAtoms = try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.contentPerformance.rawValue)
                .filter(Column("created_at") >= todayStart.ISO8601Format())
                .fetchAll(db)
        }

        var totalImpressions = 0
        var totalEngagement = 0
        var viralCount = 0

        for atom in performanceAtoms {
            if let metadata = atom.metadataValue(as: ContentPerformanceMetadata.self) {
                totalImpressions += metadata.impressions
                totalEngagement += metadata.engagement
                if metadata.isViral { viralCount += 1 }
            }
        }

        return ContentPerformanceSummary(
            totalImpressions: totalImpressions,
            totalEngagement: totalEngagement,
            viralCount: viralCount,
            contentCount: performanceAtoms.count
        )
    }

    // MARK: - Private Helpers

    private func loadActiveContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeContent = try await database.read { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(sql: "json_extract(metadata, '$.phase') NOT IN (?, ?)",
                            arguments: [ContentPhase.archived.rawValue, ContentPhase.analyzing.rawValue])
                    .order(Column("updated_at").desc)
                    .limit(50)
                    .fetchAll(db)
            }
        } catch {
            activeContent = []
        }
    }

    private func calculateMetrics() async {
        do {
            weeklyReach = try await analyticsEngine.calculateWeeklyReach()
            monthlyViralCount = try await analyticsEngine.calculateMonthlyViralCount()
            avgEngagementRate = try await analyticsEngine.calculateAverageEngagementRate()
        } catch {
            // Metrics calculation failed, keep existing values
        }
    }

    private func getLatestDraftVersion(contentUUID: String) async throws -> Int {
        try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.contentDraft.rawValue)
                .filter(sql: "links LIKE ?", arguments: ["%\(contentUUID)%"])
                .order(Column("created_at").desc)
                .fetchOne(db)?
                .metadataValue(as: ContentDraftMetadata.self)?
                .version ?? 0
        }
    }

    private func updateContentWordCount(contentUUID: String, wordCount: Int) async throws {
        guard let atom = try await fetchContentAtom(uuid: contentUUID),
              var metadata = atom.metadataValue(as: ContentAtomMetadata.self) else {
            return
        }

        metadata.wordCount = wordCount

        // Create immutable copy for Sendable closure
        var updatedAtom = atom
        updatedAtom.metadata = metadata.toJSON()
        updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
        let atomToUpdate = updatedAtom

        try await database.write { db in
            try atomToUpdate.update(db)
        }
    }

    private func awardContentXP(xp: Int, reason: String, contentUUID: String) async {
        do {
            try await database.write { db in
                // Create XP event atom
                var xpAtom = Atom.new(
                    type: .xpEvent,
                    title: "+\(xp) XP",
                    body: reason
                )
                if let metaData = try? JSONEncoder().encode([
                    "xp": String(xp),
                    "dimension": "creative",
                    "source": "content_pipeline",
                    "contentUUID": contentUUID
                ]) {
                    xpAtom.metadata = String(data: metaData, encoding: .utf8)
                }
                try xpAtom.insert(db)

                // Update level state
                if var state = try CosmoLevelState.fetchOne(db) {
                    state.addXP(xp, dimension: "creative")
                    try state.update(db)
                }
            }

            // Post notification
            NotificationCenter.default.post(
                name: .xpAwarded,
                object: nil,
                userInfo: ["xp": xp, "reason": reason, "dimension": "creative"]
            )
        } catch {
            // XP award failed silently
        }
    }
}

// MARK: - Content Atom Metadata

/// Metadata stored in `.content` atoms for pipeline tracking
struct ContentAtomMetadata: Codable, Sendable {
    var phase: ContentPhase
    var platform: SocialPlatform?
    var clientProfileUUID: String?
    var wordCount: Int
    var createdPhaseAt: Date?
    var lastPhaseTransition: Date?
    var predictedReach: Int?
    var predictedEngagement: Double?

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Content Performance Summary

public struct ContentPerformanceSummary: Sendable {
    public let totalImpressions: Int
    public let totalEngagement: Int
    public let viralCount: Int
    public let contentCount: Int

    public var engagementRate: Double {
        totalImpressions > 0 ? Double(totalEngagement) / Double(totalImpressions) : 0
    }
}

// MARK: - Content Pipeline Errors

enum ContentPipelineError: Error, LocalizedError {
    case contentNotFound
    case invalidMetadata
    case alreadyAtFinalPhase
    case publishFailed(String)
    case performanceUpdateFailed

    var errorDescription: String? {
        switch self {
        case .contentNotFound: return "Content atom not found"
        case .invalidMetadata: return "Invalid content metadata"
        case .alreadyAtFinalPhase: return "Content is already at final phase"
        case .publishFailed(let reason): return "Publish failed: \(reason)"
        case .performanceUpdateFailed: return "Failed to update performance metrics"
        }
    }
}

// MARK: - Codable Extensions

extension ContentPhaseMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ContentPerformanceMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ContentPublishMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ClientProfileMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ContentDraftMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
