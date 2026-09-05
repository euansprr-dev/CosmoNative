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
    private let analyticsEngine: ContentAnalyticsEngine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        database: (any DatabaseWriter)? = nil
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbPool! as any DatabaseWriter)
        self.analyticsEngine = ContentAnalyticsEngine(database: self.database)

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
            links.append(.contentToClient(clientUUID))
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

        await loadActiveContent()
        return atom
    }

    // MARK: - Phase Transitions

    /// Advance content to the next phase (the legacy forward-only API).
    /// Delegates to `setPhase`; returns the minted `.contentPhase` atom.
    @discardableResult
    public func advancePhase(
        contentUUID: String,
        notes: String? = nil
    ) async throws -> Atom {
        guard let contentAtom = try await fetchContentAtom(uuid: contentUUID) else {
            throw ContentPipelineError.contentNotFound
        }
        guard let currentPhase = Self.currentPhase(of: contentAtom) else {
            throw ContentPipelineError.invalidMetadata
        }
        guard let nextPhase = currentPhase.nextPhase else {
            throw ContentPipelineError.alreadyAtFinalPhase
        }
        guard let transition = try await setPhase(contentUUID: contentUUID, to: nextPhase, notes: notes) else {
            throw ContentPipelineError.alreadyAtFinalPhase
        }
        let phaseAtomUUID = transition.phaseAtomUUID
        guard let phaseAtom = try await database.read({ db in
            try Atom.filter(Column("uuid") == phaseAtomUUID).fetchOne(db)
        }) else {
            throw ContentPipelineError.invalidMetadata
        }
        return phaseAtom
    }

    // MARK: - Stage machine (Pipeline, Sept 2026)

    /// Move a piece to `target` in EITHER direction. Same phase = nil no-op.
    /// Every real move mints an honest `.contentPhase` record (a backward move
    /// earns 0 XP; a phase re-entered later earns nothing twice) and key-merges
    /// the stage keys onto the content atom. ⌘Z moves it back through the same
    /// door — an honest record, never a deleted one.
    @discardableResult
    func setPhase(
        contentUUID: String,
        to target: ContentPhase,
        notes: String? = nil,
        registerUndo: Bool = true
    ) async throws -> ContentPhaseTransition? {
        guard let transition = try await Self.applyPhase(
            contentUUID: contentUUID, to: target, notes: notes, database: database
        ) else { return nil }

        if registerUndo {
            // Static writes in the closures: the service instance that
            // registered the action is usually transient (`ContentPipelineService()`
            // in a Task) and must not be what keeps ⌘Z alive.
            let database = self.database
            let from = transition.from
            CosmoUndoManager.shared.register(InlineUndoAction(
                actionDescription: "Move to \(target.displayName)",
                undo: {
                    _ = try? await ContentPipelineService.applyPhase(
                        contentUUID: contentUUID, to: from, notes: "Undo", database: database
                    )
                },
                redo: {
                    _ = try? await ContentPipelineService.applyPhase(
                        contentUUID: contentUUID, to: target, notes: notes, database: database
                    )
                }
            ))
        }

        await loadActiveContent()
        return transition
    }

    /// The stage write itself — usable from stores and loaders WITHOUT paying
    /// for a service instance (`init` spawns the active-content + metrics
    /// loads). One transaction: mint the `.contentPhase` record, then key-merge
    /// `phase` / `lastPhaseTransition` / `createdPhaseAt` / `phaseEnteredAt`
    /// (+ the `phaseBeforeSchedule` rules) onto the FRESH content row. Sibling
    /// keys (focus state, rich documents, hooks, schedule) are never touched.
    ///
    /// `phaseBeforeSchedule`: entering `.scheduled` from ideation/draft/polish
    /// remembers where the piece came from; leaving `.scheduled`, or entering
    /// published/analyzing/archived, drops the key.
    @discardableResult
    nonisolated static func applyPhase(
        contentUUID: String,
        to target: ContentPhase,
        notes: String? = nil,
        database: (any DatabaseWriter)? = nil
    ) async throws -> ContentPhaseTransition? {
        let writer: any DatabaseWriter
        if let database {
            writer = database
        } else {
            writer = await MainActor.run { CosmoDatabase.shared.dbPool! as any DatabaseWriter }
        }
        let now = Date()

        let transition: ContentPhaseTransition? = try await writer.write { db in
            guard let fresh = try Atom
                .filter(Column("uuid") == contentUUID)
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchOne(db) else {
                throw ContentPipelineError.contentNotFound
            }

            // A content atom minted outside the pipeline (⌘K "new content")
            // carries no `phase` key yet — it has been in ideation all along.
            let from = Self.currentPhase(of: fresh) ?? .ideation
            guard from != target else { return nil }

            let typed = fresh.metadataValue(as: ContentAtomMetadata.self)
            let previouslyEntered = try Self.previouslyEnteredPhases(contentUUID: contentUUID, db: db)
            let xp = Self.xpForTransition(from: from, to: target, previouslyEntered: previouslyEntered)
            let timeInPreviousPhase = typed?.createdPhaseAt.map { now.timeIntervalSince($0) } ?? 0

            // 1. The honest record.
            let phaseMetadata = ContentPhaseMetadata(
                contentAtomUUID: contentUUID,
                fromPhase: from,
                toPhase: target,
                timestamp: now,
                wordCountAtTransition: typed?.wordCount ?? 0,
                timeSpentInPreviousPhase: timeInPreviousPhase,
                xpEarned: xp,
                transitionNotes: notes
            )
            var phaseAtom = Atom.new(
                type: .contentPhase,
                title: "\(from.displayName) → \(target.displayName)",
                body: notes
            )
            phaseAtom.metadata = phaseMetadata.toJSON()
            if let linksData = try? JSONEncoder().encode([
                AtomLink(type: "content", uuid: contentUUID, entityType: "content")
            ]) {
                phaseAtom.links = String(data: linksData, encoding: .utf8)
            }
            try phaseAtom.insert(db)

            // 2. The stage keys, merged over the fresh row.
            let storesPriorPhase = target == .scheduled && from.isSchedulable && from != .scheduled
            let dropsPriorPhase = from == .scheduled || target.isShipped || target == .archived
            let overlay = PhaseOverlay(
                phase: target,
                lastPhaseTransition: now,
                createdPhaseAt: now,
                phaseEnteredAt: ISO8601.string(from: now),
                phaseBeforeSchedule: storesPriorPhase ? from : nil
            )
            var merged = fresh.mergingMetadataKeys(overlay)
            if target == .archived {
                struct ArchiveContext: Encodable { let phaseBeforeArchive: String; let productionStage: String }
                merged = merged.mergingMetadataKeys(ArchiveContext(phaseBeforeArchive: from.rawValue, productionStage: ContentProductionStage.of(fresh).rawValue))
            } else if from == .archived {
                merged = merged.removingMetadataKeys(["phaseBeforeArchive"])
            }
            if dropsPriorPhase {
                merged = merged.removingMetadataKeys(["phaseBeforeSchedule"])
            }
            // The merge refuses an unparseable column rather than clobber it;
            // a refused merge must roll the record back with it.
            guard let metadata = merged.metadata, metadata != fresh.metadata else {
                throw ContentPipelineError.invalidMetadata
            }
            try db.execute(
                sql: """
                UPDATE atoms
                SET metadata = ?,
                    updated_at = ?,
                    _local_version = _local_version + 1,
                    _local_pending = 1
                WHERE uuid = ?
                """,
                arguments: [metadata, ISO8601.string(from: now), contentUUID]
            )

            return ContentPhaseTransition(
                contentUUID: contentUUID,
                from: from,
                to: target,
                phaseAtomUUID: phaseAtom.uuid,
                xpEarned: xp
            )
        }

        guard let transition else { return nil }

        // Queue for sync — the SQL above already bumped _local_version.
        if let updated = try? await writer.read({ db in
            try Atom.filter(Column("uuid") == contentUUID).fetchOne(db)
        }) {
            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updated, skipVersionIncrement: true)
        }
        await Self.notifyCalendar()
        return transition
    }

    /// XP is earned once per phase, and only moving forward. `previouslyEntered`
    /// is the set of phases this piece has ever reached (the `toPhase` of its
    /// `.contentPhase` records) — so ⌘Z + redo, or a round trip through the
    /// calendar, never awards the same phase twice.
    nonisolated static func xpForTransition(
        from: ContentPhase,
        to: ContentPhase,
        previouslyEntered: Set<ContentPhase>
    ) -> Int {
        guard to.ordinal > from.ordinal, !previouslyEntered.contains(to) else { return 0 }
        return to.completionXP
    }

    /// The piece's current phase. Typed decode first; a metadata column the
    /// typed struct can't read (a foreign platform value, say) still answers
    /// from its raw `phase` key. nil = the key was never written.
    nonisolated static func currentPhase(of atom: Atom) -> ContentPhase? {
        if let typed = atom.metadataValue(as: ContentAtomMetadata.self) {
            return typed.phase
        }
        guard let raw = atom.metadataDict?["phase"] as? String else { return nil }
        return ContentPhase(rawValue: raw)
    }

    /// Stage keys the machine owns. Encoded as an overlay so the merge writes
    /// exactly these keys (`phaseBeforeSchedule` nil = key left alone; removal
    /// is explicit via `removingMetadataKeys`).
    private struct PhaseOverlay: Encodable {
        var phase: ContentPhase
        var lastPhaseTransition: Date
        var createdPhaseAt: Date
        var phaseEnteredAt: String
        var phaseBeforeSchedule: ContentPhase?
    }

    /// Phases this piece has already reached — `links LIKE` prefilter (the
    /// `fetchPerformanceHistory` idiom), then a decode filter for the truth.
    nonisolated private static func previouslyEnteredPhases(contentUUID: String, db: Database) throws -> Set<ContentPhase> {
        let records = try Atom
            .filter(Column("type") == AtomType.contentPhase.rawValue)
            .filter(sql: "links LIKE ?", arguments: ["%\(contentUUID)%"])
            .fetchAll(db)
        return Set(
            records
                .compactMap { $0.metadataValue(as: ContentPhaseMetadata.self) }
                .filter { $0.contentAtomUUID == contentUUID }
                .map(\.toPhase)
        )
    }

    /// The calendar and shelf rails listen only to this (there is no
    /// `.atomsDidChange` observer in Canvas/CommandCenter). Posted on main —
    /// the rails' `.onReceive` closures mutate view state.
    nonisolated static func notifyCalendar() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
        }
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

        // Land on Published. `advancePhase` used to walk polish → archived here
        // (nextPhase skips the hidden phases) — `setPhase` goes straight there.
        // A piece already shipped or archived keeps its phase (never un-archive).
        let currentPhase = Self.currentPhase(of: contentAtom) ?? .ideation
        if !(currentPhase.isShipped || currentPhase == .archived) {
            try await setPhase(contentUUID: contentUUID, to: .published, notes: "Auto-advanced on publish")
        }
        // The calendar plots shipped pieces from publish records — mint one.
        await ContentPublishStore.markPublished(
            atomUuid: contentUUID,
            platform: platform.rawValue,
            url: postUrl
        )

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

        // Update aggregate metrics
        await calculateMetrics()

        return performanceAtom
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

    /// Merge typed metadata fields into existing metadata JSON, preserving untyped keys (e.g. focus state).
    /// `nonisolated static` so it can run inside database-writer closures.
    nonisolated static func mergedMetadataJSON<T: Encodable>(_ typed: T, existing: String?) -> String? {
        guard let existing,
              let existingData = existing.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any],
              let typedData = try? JSONEncoder().encode(typed),
              let typedDict = try? JSONSerialization.jsonObject(with: typedData) as? [String: Any] else {
            return (try? JSONEncoder().encode(typed)).flatMap { String(data: $0, encoding: .utf8) }
        }
        for (key, value) in typedDict { dict[key] = value }
        return (try? JSONSerialization.data(withJSONObject: dict)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Instance convenience for the static merge helper.
    private func mergedMetadataJSON<T: Encodable>(_ typed: T, existing: String?) -> String? {
        Self.mergedMetadataJSON(typed, existing: existing)
    }

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

        var updatedAtom = atom
        updatedAtom.metadata = mergedMetadataJSON(metadata, existing: atom.metadata)
        updatedAtom.updatedAt = ISO8601.string(from: Date())
        let atomToUpdate = updatedAtom

        try await database.write { db in
            try atomToUpdate.update(db)
        }
    }

    // MARK: - Swipe-Powered Idea Activation

    /// Activate an idea into a content atom with swipe-powered drafting enrichment.
    /// Runs IdeaInsightEngine.fullAnalysis() if stale, queries matching swipes by taxonomy,
    /// and generates a ContentDraftPackage if enough swipe data is available.
    ///
    /// Returns the enriched content atom and optional draft package.
    @discardableResult
    func activateIdea(
        ideaAtom: Atom,
        targetFormat: ContentFormat,
        contentAtomUUID: String
    ) async -> ContentDraftPackage? {
        guard ideaAtom.type == .idea else { return nil }

        let ideaText = ideaAtom.body ?? ideaAtom.title ?? ""
        guard !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Query swipes by taxonomy using the idea's format
        // Derive niche from the client profile if available
        var niche: String?
        if let clientUUID = ideaAtom.ideaClientUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
            if let clientMeta = client.metadataValue(as: ClientProfileMetadata.self) {
                niche = clientMeta.niche
            } else if let clientMeta = client.metadataValue(as: ClientMetadata.self) {
                niche = clientMeta.niche
            }
        }
        let matchingSwipes: [Atom]
        do {
            matchingSwipes = try await AtomRepository.shared.fetchSwipesByTaxonomy(
                contentType: targetFormat,
                niche: niche
            )
        } catch {
            print("ContentPipelineService: Failed to fetch swipes by taxonomy: \(error.localizedDescription)")
            return nil
        }

        // Store matched swipe UUIDs even if insufficient for drafting
        let matchedUUIDs = matchingSwipes.map(\.uuid)
        if var contentAtom = try? await fetchContentAtom(uuid: contentAtomUUID),
           var meta = contentAtom.metadataValue(as: ContentAtomMetadata.self) {
            meta.inheritedSwipeUUIDs = matchedUUIDs
            if matchingSwipes.count < 3 {
                meta.draftReady = false
                meta.draftingNote = "Capture more swipes to unlock AI drafting (\(matchingSwipes.count)/3 matched)"
            } else {
                meta.draftReady = true
                meta.draftingNote = nil
            }
            // Merge — a whole-blob toJSON() replacement here wiped every metadata key
            // the typed struct doesn't model (focus state, rich documents, hooks).
            contentAtom.metadata = mergedMetadataJSON(meta, existing: contentAtom.metadata)
            contentAtom.updatedAt = ISO8601.string(from: Date())
            let atomToUpdate = contentAtom
            do {
                try await database.write { db in
                    try atomToUpdate.update(db)
                }
            } catch {
                print("ContentPipelineService: Failed to update draft readiness: \(error)")
            }
        }

        // Require at least 3 matching swipes for AI drafting
        guard matchingSwipes.count >= 3 else {
            print("ContentPipelineService: Only \(matchingSwipes.count) matching swipes found. Need 3+ for AI drafting.")
            return nil
        }

        // Load client profile if idea has one (may already be loaded from niche derivation)
        var clientProfile: Atom?
        if let clientUUID = ideaAtom.ideaClientUUID {
            clientProfile = try? await AtomRepository.shared.fetch(uuid: clientUUID)
        }


        // Generate draft package via SwipeDraftEngine
        guard let draftPackage = await SwipeDraftEngine.shared.generateDraftPackage(
            idea: ideaAtom,
            targetFormat: targetFormat,
            matchingSwipes: Array(matchingSwipes.prefix(5)),
            clientProfile: clientProfile
        ) else {
            print("ContentPipelineService: SwipeDraftEngine returned nil")
            return nil
        }

        // Store the draft package on the content atom
        if var contentAtom = try? await fetchContentAtom(uuid: contentAtomUUID),
           var meta = contentAtom.metadataValue(as: ContentAtomMetadata.self) {

            // Store draft package in structured JSON
            if let packageData = try? JSONEncoder().encode(draftPackage),
               let packageString = String(data: packageData, encoding: .utf8) {
                contentAtom.structured = packageString
            }

            // Record swipe reference UUIDs in metadata — merged, never whole-blob replaced.
            meta.inheritedSwipeUUIDs = draftPackage.swipeReferences.map(\.swipeUUID)
            meta.draftingNote = nil
            contentAtom.metadata = mergedMetadataJSON(meta, existing: contentAtom.metadata)
            contentAtom.updatedAt = ISO8601.string(from: Date())

            let atomToUpdate = contentAtom
            do {
                try await database.write { db in
                    try atomToUpdate.update(db)
                }
            } catch {
                print("ContentPipelineService: Failed to store draft package: \(error)")
            }

            // Create AtomLinks from content to each referenced swipe
            var linkedAtom = contentAtom
            for ref in draftPackage.swipeReferences {
                linkedAtom = linkedAtom.addingLink(
                    .linksTo(ref.swipeUUID, entityType: .research)
                )
            }
            if let linksData = try? JSONEncoder().encode(linkedAtom.linksList),
               let linksString = String(data: linksData, encoding: .utf8) {
                linkedAtom.links = linksString
                linkedAtom.updatedAt = ISO8601.string(from: Date())
                let finalAtom = linkedAtom
                do {
                    try await database.write { db in
                        try finalAtom.update(db)
                    }
                } catch {
                    print("ContentPipelineService: Failed to persist swipe links: \(error)")
                }
            }
        }

        return draftPackage
    }

}

// MARK: - Content Atom Metadata

/// Metadata stored in `.content` atoms for pipeline tracking
struct ContentAtomMetadata: Codable, Sendable {
    var phase: ContentPhase
    var platform: SocialPlatform?
    var contentFormat: String?
    var clientProfileUUID: String?
    var wordCount: Int
    var createdPhaseAt: Date?
    var lastPhaseTransition: Date?
    var predictedReach: Int?
    var predictedEngagement: Double?
    var sourceIdeaUUID: String?
    var blueprintSwipeUUID: String?
    var inheritedSwipeUUIDs: [String]?
    var inheritedConnectionIds: [String]?
    var inheritedFramework: String?
    var inheritedHooks: [String]?
    var activatedAt: String?
    var phaseEnteredAt: String?
    /// Where the piece sat before a calendar drop moved it to `.scheduled`;
    /// unscheduling restores it. Written/removed ONLY by `applyPhase`.
    var phaseBeforeSchedule: ContentPhase?
    var draftingNote: String?
    var draftReady: Bool?

    var inheritedMentionedAtomUUIDs: [String]?

    // Codex-era inherited fields
    var inheritedArcType: String?
    var inheritedCodexOutline: String?
    var inheritedCreativeDirection: String?
    var inheritedResearchResults: String?
    var inheritedChatHistory: String?
    var inheritedContext: String?
    var codexElementNames: [String]?

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Lenient decode (in an extension so the memberwise init survives): a content
/// atom minted outside the pipeline — ⌘K "new content", an older device, a
/// hand-written column — has no `wordCount` and sometimes no `phase`. The
/// synthesized decoder threw on the missing keys, so EVERY typed read of the
/// column failed and the stage machine fell back to raw-key guesses (the
/// `phaseBeforeSchedule` memory was unreadable, unscheduling always landed in
/// Polish). Missing = default; a genuinely unparseable column still throws.
extension ContentAtomMetadata {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(ContentPhase.self, forKey: .phase) ?? .ideation
        platform = try c.decodeIfPresent(SocialPlatform.self, forKey: .platform)
        contentFormat = try c.decodeIfPresent(String.self, forKey: .contentFormat)
        clientProfileUUID = try c.decodeIfPresent(String.self, forKey: .clientProfileUUID)
        wordCount = try c.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        createdPhaseAt = try c.decodeIfPresent(Date.self, forKey: .createdPhaseAt)
        lastPhaseTransition = try c.decodeIfPresent(Date.self, forKey: .lastPhaseTransition)
        predictedReach = try c.decodeIfPresent(Int.self, forKey: .predictedReach)
        predictedEngagement = try c.decodeIfPresent(Double.self, forKey: .predictedEngagement)
        sourceIdeaUUID = try c.decodeIfPresent(String.self, forKey: .sourceIdeaUUID)
        blueprintSwipeUUID = try c.decodeIfPresent(String.self, forKey: .blueprintSwipeUUID)
        inheritedSwipeUUIDs = try c.decodeIfPresent([String].self, forKey: .inheritedSwipeUUIDs)
        inheritedConnectionIds = try c.decodeIfPresent([String].self, forKey: .inheritedConnectionIds)
        inheritedFramework = try c.decodeIfPresent(String.self, forKey: .inheritedFramework)
        inheritedHooks = try c.decodeIfPresent([String].self, forKey: .inheritedHooks)
        activatedAt = try c.decodeIfPresent(String.self, forKey: .activatedAt)
        phaseEnteredAt = try c.decodeIfPresent(String.self, forKey: .phaseEnteredAt)
        phaseBeforeSchedule = try c.decodeIfPresent(ContentPhase.self, forKey: .phaseBeforeSchedule)
        draftingNote = try c.decodeIfPresent(String.self, forKey: .draftingNote)
        draftReady = try c.decodeIfPresent(Bool.self, forKey: .draftReady)
        inheritedMentionedAtomUUIDs = try c.decodeIfPresent([String].self, forKey: .inheritedMentionedAtomUUIDs)
        inheritedArcType = try c.decodeIfPresent(String.self, forKey: .inheritedArcType)
        inheritedCodexOutline = try c.decodeIfPresent(String.self, forKey: .inheritedCodexOutline)
        inheritedCreativeDirection = try c.decodeIfPresent(String.self, forKey: .inheritedCreativeDirection)
        inheritedResearchResults = try c.decodeIfPresent(String.self, forKey: .inheritedResearchResults)
        inheritedChatHistory = try c.decodeIfPresent(String.self, forKey: .inheritedChatHistory)
        inheritedContext = try c.decodeIfPresent(String.self, forKey: .inheritedContext)
        codexElementNames = try c.decodeIfPresent([String].self, forKey: .codexElementNames)
    }
}

// MARK: - Content Phase Transition

/// What one `setPhase` / `applyPhase` call did. `ContentPhaseTransition` (not
/// `PhaseTransition`) — that name is already taken by the physics profile's
/// slide-transition model in ContentPhysicsProfile.swift.
struct ContentPhaseTransition: Sendable, Equatable {
    let contentUUID: String
    let from: ContentPhase
    let to: ContentPhase
    /// The minted `.contentPhase` record.
    let phaseAtomUUID: String
    let xpEarned: Int
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

    /// Formats the profile as a context string for AI prompt injection.
    /// Returns a multi-line block suitable for embedding in system/user prompts.
    func toAIContextString() -> String {
        var lines: [String] = []
        lines.append("CLIENT PROFILE: \(clientName)")

        if let handle = handle, !handle.isEmpty {
            lines.append("Handle: \(handle)")
        }
        if let niche = niche, !niche.isEmpty {
            lines.append("Niche: \(niche)")
        } else if let industry = industry, !industry.isEmpty {
            lines.append("Industry: \(industry)")
        }
        if let targetAudience = targetAudience, !targetAudience.isEmpty {
            lines.append("Target Audience: \(targetAudience)")
        }
        if let voiceNotes = voiceNotes, !voiceNotes.isEmpty {
            lines.append("Brand Voice: \(voiceNotes)")
        }
        if let uniqueAngle = uniqueAngle, !uniqueAngle.isEmpty {
            lines.append("Unique Angle: \(uniqueAngle)")
        }
        if let brandStory = brandStory, !brandStory.isEmpty {
            lines.append("Brand Story: \(brandStory)")
        }
        if let brandVision = brandVision, !brandVision.isEmpty {
            lines.append("Vision: \(brandVision)")
        }
        if let beliefs = coreBeliefs, !beliefs.isEmpty {
            lines.append("Core Beliefs: \(beliefs.joined(separator: "; "))")
        }
        if let phrases = signaturePhrases, !phrases.isEmpty {
            lines.append("Signature Phrases: \(phrases.joined(separator: " | "))")
        }
        if !platforms.isEmpty {
            lines.append("Platforms: \(platforms.map(\.displayName).joined(separator: ", "))")
        }
        if let bestFormats = bestFormats, !bestFormats.isEmpty {
            lines.append("Best Formats: \(bestFormats.joined(separator: ", "))")
        }
        if let frequency = postingFrequency, !frequency.isEmpty {
            lines.append("Posting Frequency: \(frequency)")
        }
        if let times = preferredPostTimes, !times.isEmpty {
            lines.append("Preferred Post Times: \(times.joined(separator: ", "))")
        }
        if let transcripts = topPerformingTranscripts, !transcripts.isEmpty {
            lines.append("Top Performing Content Examples:")
            for (i, transcript) in transcripts.prefix(3).enumerated() {
                let snippet = String(transcript.prefix(500))
                lines.append("  \(i + 1). \(snippet)\(transcript.count > 500 ? "..." : "")")
            }
        }
        if let personal = isPersonalBrand {
            lines.append("Brand Type: \(personal ? "Personal Brand" : "Company/Agency")")
        }
        if let voice = extractedVoicePatterns {
            lines.append("EXTRACTED VOICE PROFILE:")
            if voice.avgSentenceLength > 0 {
                lines.append("  Avg Sentence Length: \(String(format: "%.1f", voice.avgSentenceLength)) words")
            }
            if !voice.readingLevel.isEmpty {
                lines.append("  Reading Level: \(voice.readingLevel)")
            }
            if !voice.emotionalRange.isEmpty {
                lines.append("  Emotional Range: \(voice.emotionalRange)")
            }
            if !voice.recurringPhrases.isEmpty {
                lines.append("  Recurring Phrases: \(voice.recurringPhrases.joined(separator: " | "))")
            }
            if !voice.ctaPatterns.isEmpty {
                lines.append("  CTA Patterns: \(voice.ctaPatterns.joined(separator: " | "))")
            }
            if !voice.stylisticQuirks.isEmpty {
                lines.append("  Stylistic Quirks: \(voice.stylisticQuirks.joined(separator: "; "))")
            }
        }
        if let beats = preferredBeatPatterns, !beats.isEmpty {
            lines.append("Preferred Beat Patterns: \(beats.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

extension ContentDraftMetadata {
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
