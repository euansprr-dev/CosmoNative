import Foundation
import GRDB

actor ContextIndexStore {
    static let shared = ContextIndexStore()

    private let usePersistentStore: Bool
    private var schemaEnsured = false
    private var sourcesByID: [String: ContextSource] = [:]
    private var sourceIDByAtomUUID: [String: String] = [:]
    private var chunksBySourceID: [String: [ContextChunk]] = [:]
    private var sessionsByID: [String: ContextSession] = [:]

    init(usePersistentStore: Bool = true) {
        self.usePersistentStore = usePersistentStore
    }

    static func inMemoryForTests() -> ContextIndexStore {
        ContextIndexStore(usePersistentStore: false)
    }

    func upsert(source: ContextSource, chunks: [ContextChunk]) async throws {
        let contextualizedChunks = contextualize(chunks, source: source)
        sourcesByID[source.id] = source
        if let atomUUID = source.atomUUID {
            sourceIDByAtomUUID[atomUUID] = source.id
        }
        chunksBySourceID[source.id] = contextualizedChunks

        guard usePersistentStore, let database = DatabaseActorCore.shared else { return }
        try await ensureSchema(database)
        try await database.asyncWrite { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO context_sources
                    (id, kind, title, atom_uuid, external_id, body_hash, metadata_hash, client_uuid, pin_state, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    source.id,
                    source.kind.rawValue,
                    source.title,
                    source.atomUUID,
                    source.externalID,
                    source.bodyHash,
                    source.metadataHash,
                    source.clientUUID,
                    source.pinState.rawValue,
                    Self.dateString(source.createdAt),
                    Self.dateString(source.updatedAt)
                ]
            )
            try db.execute(sql: "DELETE FROM context_chunks WHERE source_id = ?", arguments: [source.id])
            try db.execute(sql: "DELETE FROM context_chunks_fts WHERE source_id = ?", arguments: [source.id])

            for chunk in contextualizedChunks {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO context_chunks
                        (id, source_id, ordinal, raw_text, contextual_header, anchor, token_count, body_hash)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        chunk.sourceID,
                        chunk.ordinal,
                        chunk.rawText,
                        chunk.contextualHeader,
                        chunk.anchor,
                        chunk.tokenCount,
                        chunk.bodyHash
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO context_chunks_fts(id, source_id, title, searchable_text)
                        VALUES (?, ?, ?, ?)
                    """,
                    arguments: [chunk.id, chunk.sourceID, source.title, chunk.searchableText]
                )
            }
        }
    }

    func upsert(atom: Atom, pinState: ContextPinState = .pinned) async throws -> String {
        let source = Self.source(for: atom, pinState: pinState)
        let body = Self.indexableBody(for: atom)
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: body,
            bodyHash: source.bodyHash
        )
        try await upsert(source: source, chunks: chunks)
        return source.id
    }

    func upsert(session: ContextSession) async throws {
        sessionsByID[session.id] = session

        guard usePersistentStore, let database = DatabaseActorCore.shared else { return }
        try await ensureSchema(database)
        try await database.asyncWrite { db in
            let decisionsData = try JSONEncoder().encode(session.recentDecisionSummaries)
            let decisions = String(data: decisionsData, encoding: .utf8) ?? "[]"
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO context_sessions
                    (id, surface, active_atom_uuid, active_client_uuid, recent_decision_summaries, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    session.id,
                    session.surface.rawValue,
                    session.activeAtomUUID,
                    session.activeClientUUID,
                    decisions,
                    Self.dateString(session.updatedAt)
                ]
            )
            try db.execute(sql: "DELETE FROM context_session_sources WHERE session_id = ?", arguments: [session.id])
            for (index, sourceID) in session.pinnedSourceIDs.enumerated() {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO context_session_sources
                        (session_id, source_id, ordinal)
                        VALUES (?, ?, ?)
                    """,
                    arguments: [session.id, sourceID, index]
                )
            }
        }
    }

    func session(id: String) async throws -> ContextSession? {
        if let session = sessionsByID[id] {
            return session
        }
        guard usePersistentStore, let database = DatabaseActorCore.shared else { return nil }
        try await ensureSchema(database)
        let loaded = try await database.asyncRead { db -> ContextSession? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM context_sessions WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            let sourceIDs = try String.fetchAll(
                db,
                sql: "SELECT source_id FROM context_session_sources WHERE session_id = ? ORDER BY ordinal ASC",
                arguments: [id]
            )
            return Self.session(from: row, pinnedSourceIDs: sourceIDs)
        }
        if let loaded {
            sessionsByID[loaded.id] = loaded
        }
        return loaded
    }

    func source(id: String) async throws -> ContextSource? {
        if let source = sourcesByID[id] {
            return source
        }
        guard usePersistentStore, let database = DatabaseActorCore.shared else { return nil }
        try await ensureSchema(database)
        let loaded = try await database.asyncRead { db -> ContextSource? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM context_sources WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            return Self.source(from: row)
        }
        if let loaded {
            remember(source: loaded)
        }
        return loaded
    }

    func sourceID(atomUUID: String) async -> String? {
        if let sourceID = sourceIDByAtomUUID[atomUUID] {
            return sourceID
        }
        guard usePersistentStore, let database = DatabaseActorCore.shared else { return nil }
        try? await ensureSchema(database)
        let loaded = try? await database.asyncRead { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT id FROM context_sources WHERE atom_uuid = ? ORDER BY updated_at DESC LIMIT 1",
                arguments: [atomUUID]
            )
        }
        if let loaded {
            sourceIDByAtomUUID[atomUUID] = loaded
        }
        return loaded
    }

    func sources(ids: [String]) async throws -> [ContextSource] {
        let memoryIDs = ids.isEmpty ? Array(sourcesByID.keys) : ids
        var output = memoryIDs.compactMap { sourcesByID[$0] }
        let loadedIDs = Set(output.map(\.id))
        let missingIDs = ids.filter { !loadedIDs.contains($0) }

        if usePersistentStore, let database = DatabaseActorCore.shared, (ids.isEmpty || !missingIDs.isEmpty) {
            try await ensureSchema(database)
            let persistent = try await database.asyncRead { db -> [ContextSource] in
                if ids.isEmpty {
                    let rows = try Row.fetchAll(db, sql: "SELECT * FROM context_sources ORDER BY updated_at DESC")
                    return rows.map(Self.source(from:))
                }

                let placeholders = Array(repeating: "?", count: missingIDs.count).joined(separator: ",")
                guard !placeholders.isEmpty else { return [] }
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM context_sources WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(missingIDs)
                )
                return rows.map(Self.source(from:))
            }
            for source in persistent {
                remember(source: source)
            }
            output.append(contentsOf: persistent.filter { !loadedIDs.contains($0.id) })
        }

        if ids.isEmpty {
            return output
        }
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        return output.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
    }

    func chunks(sourceIDs: [String]) async throws -> [ContextChunk] {
        let memoryIDs = sourceIDs.isEmpty ? Array(chunksBySourceID.keys) : sourceIDs
        var output = memoryIDs.flatMap { chunksBySourceID[$0] ?? [] }

        let loadedSourceIDs = Set(output.map(\.sourceID))
        let missingIDs = sourceIDs.filter { !loadedSourceIDs.contains($0) }
        if usePersistentStore, let database = DatabaseActorCore.shared, (sourceIDs.isEmpty || !missingIDs.isEmpty) {
            try await ensureSchema(database)
            let persistent = try await database.asyncRead { db -> [ContextChunk] in
                if sourceIDs.isEmpty {
                    let rows = try Row.fetchAll(db, sql: "SELECT * FROM context_chunks ORDER BY source_id, ordinal")
                    return rows.map(Self.chunk(from:))
                }

                let placeholders = Array(repeating: "?", count: missingIDs.count).joined(separator: ",")
                guard !placeholders.isEmpty else { return [] }
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM context_chunks WHERE source_id IN (\(placeholders)) ORDER BY source_id, ordinal",
                    arguments: StatementArguments(missingIDs)
                )
                return rows.map(Self.chunk(from:))
            }
            remember(chunks: persistent)
            output.append(contentsOf: persistent)
        }

        return output.sorted { lhs, rhs in
            if lhs.sourceID == rhs.sourceID {
                return lhs.ordinal < rhs.ordinal
            }
            return lhs.sourceID < rhs.sourceID
        }
    }

    func keywordSearch(query: String, sourceIDs: [String], limit: Int) async throws -> [(ContextSource, ContextChunk, Double)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if usePersistentStore, let database = DatabaseActorCore.shared {
            do {
                try await ensureSchema(database)
                let hits = try await persistentKeywordSearch(query: trimmed, sourceIDs: sourceIDs, limit: limit, database: database)
                if !hits.isEmpty {
                    for hit in hits {
                        remember(source: hit.source)
                        remember(chunks: [hit.chunk])
                    }
                    return hits.map { ($0.source, $0.chunk, $0.score) }
                }
            } catch {
                // Keep exact lookup reliable even if FTS rejects a query.
            }
        }

        let resolvedSourceIDs = sourceIDs.isEmpty ? Array(sourcesByID.keys) : sourceIDs
        let phrases = Self.quotedPhrases(in: trimmed)
        let terms = Self.searchTerms(in: trimmed)

        var scored: [(ContextSource, ContextChunk, Double)] = []
        for sourceID in resolvedSourceIDs {
            guard let source = sourcesByID[sourceID] else { continue }
            for chunk in chunksBySourceID[sourceID] ?? [] {
                let haystack = chunk.searchableText.lowercased()
                let score = Self.keywordScore(haystack: haystack, phrases: phrases, terms: terms)
                guard score > 0 else { continue }
                scored.append((source, chunk, score))
            }
        }

        return Array(scored.sorted { $0.2 > $1.2 }.prefix(max(1, limit)))
    }

    private func contextualize(_ chunks: [ContextChunk], source: ContextSource) -> [ContextChunk] {
        chunks.enumerated().map { index, chunk in
            var mutable = chunk
            mutable.contextualHeader = ContextualChunkAnnotator.deterministicHeader(
                source: source,
                chunkOrdinal: index,
                totalChunks: chunks.count
            )
            return mutable
        }
    }

    private func ensureSchema(_ database: DatabaseActorCore) async throws {
        guard !schemaEnsured else { return }
        try await database.asyncWrite { db in
            try CosmoDatabase.createContextIndexSchema(db)
        }
        schemaEnsured = true
    }

    private func persistentKeywordSearch(
        query: String,
        sourceIDs: [String],
        limit: Int,
        database: DatabaseActorCore
    ) async throws -> [StoredKeywordHit] {
        let match = Self.ftsQuery(for: query)
        guard !match.isEmpty else { return [] }

        return try await database.asyncRead { db -> [StoredKeywordHit] in
            let sourceFilter: String
            var arguments = StatementArguments([match])
            if sourceIDs.isEmpty {
                sourceFilter = ""
            } else {
                let placeholders = Array(repeating: "?", count: sourceIDs.count).joined(separator: ",")
                sourceFilter = "AND c.source_id IN (\(placeholders))"
                arguments += StatementArguments(sourceIDs)
            }
            arguments += StatementArguments([max(1, limit)])

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        s.id AS source_id_value,
                        s.kind AS source_kind,
                        s.title AS source_title,
                        s.atom_uuid AS source_atom_uuid,
                        s.external_id AS source_external_id,
                        s.body_hash AS source_body_hash,
                        s.metadata_hash AS source_metadata_hash,
                        s.client_uuid AS source_client_uuid,
                        s.pin_state AS source_pin_state,
                        s.created_at AS source_created_at,
                        s.updated_at AS source_updated_at,
                        c.id AS chunk_id,
                        c.source_id AS chunk_source_id,
                        c.ordinal AS chunk_ordinal,
                        c.raw_text AS chunk_raw_text,
                        c.contextual_header AS chunk_contextual_header,
                        c.anchor AS chunk_anchor,
                        c.token_count AS chunk_token_count,
                        c.body_hash AS chunk_body_hash,
                        bm25(context_chunks_fts) AS rank
                    FROM context_chunks_fts
                    JOIN context_chunks c ON c.id = context_chunks_fts.id
                    JOIN context_sources s ON s.id = c.source_id
                    WHERE context_chunks_fts MATCH ? \(sourceFilter)
                    ORDER BY rank ASC
                    LIMIT ?
                """,
                arguments: arguments
            )

            return rows.map { row in
                StoredKeywordHit(
                    source: Self.source(fromPrefixed: row),
                    chunk: Self.chunk(fromPrefixed: row),
                    score: -(row["rank"] as? Double ?? 0)
                )
            }
        }
    }

    static func source(for atom: Atom, pinState: ContextPinState = .pinned) -> ContextSource {
        let body = indexableBody(for: atom)
        let metadata = [atom.metadata, atom.structured, atom.links]
            .compactMap { $0 }
            .joined(separator: "\n")
        return ContextSource(
            id: "atom:\(atom.uuid)",
            kind: sourceKind(for: atom),
            title: atom.title ?? "Untitled",
            atomUUID: atom.uuid,
            bodyHash: stableHash(body),
            metadataHash: stableHash(metadata),
            clientUUID: atom.type == .clientProfile ? atom.uuid : atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
            pinState: pinState
        )
    }

    static func indexableBody(for atom: Atom) -> String {
        var parts: [String] = []
        if let title = atom.title, !title.isEmpty {
            parts.append(title)
        }
        let body = DocumentElementContextFormatter.contextBody(for: atom)
        if !body.isEmpty {
            parts.append(body)
        }
        if let structured = atom.structured, !structured.isEmpty {
            parts.append(structured)
        }
        if atom.isSwipeFileAtom, let analysis = atom.swipeAnalysis {
            let summary = MentionContextHelper.swipeAnalysisSummary(analysis)
            if !summary.isEmpty {
                parts.append(summary)
            }
        }
        if atom.type == .clientProfile,
           let meta = atom.metadataValue(as: ClientProfileMetadata.self) {
            parts.append(contentsOf: clientProfileIndexableParts(meta))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func clientProfileIndexableParts(_ meta: ClientProfileMetadata) -> [String] {
        var parts: [String] = []

        var overview: [String] = ["Client profile: \(meta.clientName)"]
        if let niche = meta.niche ?? meta.industry, !niche.isEmpty {
            overview.append("Niche: \(niche)")
        }
        if !meta.platforms.isEmpty {
            overview.append("Platforms: \(meta.platforms.map(\.rawValue).joined(separator: ", "))")
        }
        if let handle = meta.handle, !handle.isEmpty {
            overview.append("Handle: \(handle)")
        }
        if let audience = meta.targetAudience, !audience.isEmpty {
            overview.append("Target audience: \(audience)")
        }
        if let notes = meta.notes, !notes.isEmpty {
            overview.append("Notes: \(notes)")
        }
        parts.append(overview.joined(separator: "\n"))

        func appendField(_ title: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            parts.append("\(title):\n\(value)")
        }

        appendField("Brand story", meta.brandStory)
        appendField("Brand vision", meta.brandVision)
        appendField("Voice notes", meta.voiceNotes)
        appendField("Unique angle", meta.uniqueAngle)
        appendField("Posting frequency", meta.postingFrequency)

        if let beliefs = meta.coreBeliefs, !beliefs.isEmpty {
            parts.append("Core beliefs:\n\(beliefs.joined(separator: "\n"))")
        }
        if let phrases = meta.signaturePhrases, !phrases.isEmpty {
            parts.append("Signature phrases:\n\(phrases.joined(separator: "\n"))")
        }
        if let bestFormats = meta.bestFormats, !bestFormats.isEmpty {
            parts.append("Best formats: \(bestFormats.joined(separator: ", "))")
        }
        if let beatPatterns = meta.preferredBeatPatterns, !beatPatterns.isEmpty {
            parts.append("Preferred beat patterns:\n\(beatPatterns.joined(separator: "\n"))")
        }
        if let times = meta.preferredPostTimes, !times.isEmpty {
            parts.append("Preferred post times: \(times.joined(separator: ", "))")
        }

        if let voice = meta.extractedVoicePatterns {
            parts.append([
                "Extracted voice profile:",
                "Average sentence length: \(String(format: "%.1f", voice.avgSentenceLength))",
                "Reading level: \(voice.readingLevel)",
                "Emotional range: \(voice.emotionalRange)",
                "Recurring phrases: \(voice.recurringPhrases.joined(separator: ", "))",
                "CTA patterns: \(voice.ctaPatterns.joined(separator: ", "))",
                "Stylistic quirks: \(voice.stylisticQuirks.joined(separator: ", "))"
            ].joined(separator: "\n"))
        }

        if let posts = meta.topPerformingPosts, !posts.isEmpty {
            for (index, post) in posts.enumerated() {
                parts.append([
                    "Top-performing post \(index + 1):",
                    "Platform: \(post.platform)",
                    "Views: \(post.views) Likes: \(post.likes) Shares: \(post.shares) Leads: \(post.leads)",
                    "Date posted: \(post.datePosted)",
                    post.transcript
                ].joined(separator: "\n"))
            }
        }

        if let transcripts = meta.topPerformingTranscripts, !transcripts.isEmpty {
            for (index, transcript) in transcripts.enumerated() {
                parts.append("Top-performing transcript \(index + 1):\n\(transcript)")
            }
        }

        if let documents = meta.documents, !documents.isEmpty {
            for document in documents {
                var lines = [
                    "Profile document: \(document.title)",
                    "Category: \(document.category.displayName)"
                ]
                if let platform = document.platform, !platform.isEmpty {
                    lines.append("Platform: \(platform)")
                }
                if let sourceURL = document.sourceURL, !sourceURL.isEmpty {
                    lines.append("Source URL: \(sourceURL)")
                }
                let metrics = [
                    document.likes.map { "Likes: \($0)" },
                    document.shares.map { "Shares: \($0)" },
                    document.saves.map { "Saves: \($0)" },
                    document.comments.map { "Comments: \($0)" },
                    document.leads.map { "Leads: \($0)" }
                ].compactMap { $0 }
                if !metrics.isEmpty {
                    lines.append(metrics.joined(separator: " "))
                }
                lines.append(document.content)
                parts.append(lines.joined(separator: "\n"))
            }
        }

        if let model = meta.intelligenceModel {
            parts.append(clientIntelligenceIndexablePart(model))
        }

        return parts
    }

    private static func clientIntelligenceIndexablePart(_ model: ClientIntelligenceModel) -> String {
        var lines: [String] = ["Client Intelligence Model"]

        let voice = model.voiceFingerprint
        lines.append("Voice fingerprint:")
        lines.append("Average sentence length: \(String(format: "%.1f", voice.avgSentenceLength))")
        lines.append("Reading level: \(voice.readingLevel)")
        lines.append("Punctuation style: \(voice.punctuationStyle)")
        lines.append("CTA pattern: \(voice.ctaPattern)")
        if !voice.powerWords.isEmpty { lines.append("Power words: \(voice.powerWords.joined(separator: ", "))") }
        if !voice.signaturePhrases.isEmpty { lines.append("Signature phrases: \(voice.signaturePhrases.joined(separator: ", "))") }
        if !voice.blacklistedPhrases.isEmpty { lines.append("Blacklisted phrases: \(voice.blacklistedPhrases.joined(separator: ", "))") }

        let performance = model.performanceFingerprint
        lines.append("Performance patterns:")
        lines.append("Optimal length: \(performance.optimalLength)")
        if !performance.bestTopics.isEmpty { lines.append("Best topics: \(performance.bestTopics.joined(separator: ", "))") }
        if !performance.engagementTriggers.isEmpty { lines.append("Engagement triggers: \(performance.engagementTriggers.joined(separator: ", "))") }
        if !performance.bestBeatPatterns.isEmpty { lines.append("Best beat patterns: \(performance.bestBeatPatterns.joined(separator: ", "))") }

        let audience = model.audienceModel
        lines.append("Audience model:")
        lines.append("Primary audience: \(audience.primaryAudience)")
        if !audience.topPainPoints.isEmpty { lines.append("Pain points: \(audience.topPainPoints.joined(separator: "; "))") }
        if !audience.aspirationalOutcomes.isEmpty { lines.append("Aspirational outcomes: \(audience.aspirationalOutcomes.joined(separator: "; "))") }
        if !audience.commonObjections.isEmpty { lines.append("Objections: \(audience.commonObjections.joined(separator: "; "))") }

        if let failure = model.failureFingerprint, !failure.rules.isEmpty {
            lines.append("Failure fingerprint:")
            for rule in failure.rules {
                lines.append("[\(rule.severity.rawValue)] \(rule.rule)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func sourceKind(for atom: Atom) -> ContextSourceKind {
        if atom.type == .clientProfile { return .clientProfile }
        if atom.isSwipeFileAtom { return .swipe }
        if atom.type == .content { return .content }
        return .atom
    }

    private static func keywordScore(haystack: String, phrases: [String], terms: [String]) -> Double {
        var score = 0.0

        for phrase in phrases {
            if haystack.contains(phrase) {
                score += 12.0 + Double(phrase.split(separator: " ").count)
            }
        }

        for term in terms where haystack.contains(term) {
            score += 1.0
        }

        if !terms.isEmpty && terms.allSatisfy({ haystack.contains($0) }) {
            score += 4.0
        }

        return score
    }

    private static func quotedPhrases(in query: String) -> [String] {
        var phrases: [String] = []
        var current = ""
        var insideQuote = false

        for character in query {
            if character == "\"" {
                if insideQuote {
                    let phrase = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !phrase.isEmpty {
                        phrases.append(phrase)
                    }
                    current = ""
                }
                insideQuote.toggle()
            } else if insideQuote {
                current.append(character)
            }
        }

        return phrases
    }

    private static func searchTerms(in query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !stopWords.contains($0) }
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func remember(source: ContextSource) {
        sourcesByID[source.id] = source
        if let atomUUID = source.atomUUID {
            sourceIDByAtomUUID[atomUUID] = source.id
        }
    }

    private func remember(chunks: [ContextChunk]) {
        let grouped = Dictionary(grouping: chunks, by: \.sourceID)
        for (sourceID, newChunks) in grouped {
            var existing = chunksBySourceID[sourceID] ?? []
            let newIDs = Set(newChunks.map(\.id))
            existing.removeAll { newIDs.contains($0.id) }
            chunksBySourceID[sourceID] = (existing + newChunks).sorted { $0.ordinal < $1.ordinal }
        }
    }

    private static func source(from row: Row) -> ContextSource {
        ContextSource(
            id: row["id"],
            kind: ContextSourceKind(rawValue: row["kind"] as String) ?? .atom,
            title: row["title"],
            atomUUID: row["atom_uuid"],
            externalID: row["external_id"],
            bodyHash: row["body_hash"],
            metadataHash: row["metadata_hash"],
            clientUUID: row["client_uuid"],
            pinState: ContextPinState(rawValue: row["pin_state"] as String) ?? .unpinned,
            createdAt: date(from: row["created_at"] as String?),
            updatedAt: date(from: row["updated_at"] as String?)
        )
    }

    private static func chunk(from row: Row) -> ContextChunk {
        ContextChunk(
            id: row["id"],
            sourceID: row["source_id"],
            ordinal: row["ordinal"],
            rawText: row["raw_text"],
            contextualHeader: row["contextual_header"],
            anchor: row["anchor"],
            tokenCount: row["token_count"],
            bodyHash: row["body_hash"]
        )
    }

    private static func source(fromPrefixed row: Row) -> ContextSource {
        ContextSource(
            id: row["source_id_value"],
            kind: ContextSourceKind(rawValue: row["source_kind"] as String) ?? .atom,
            title: row["source_title"],
            atomUUID: row["source_atom_uuid"],
            externalID: row["source_external_id"],
            bodyHash: row["source_body_hash"],
            metadataHash: row["source_metadata_hash"],
            clientUUID: row["source_client_uuid"],
            pinState: ContextPinState(rawValue: row["source_pin_state"] as String) ?? .unpinned,
            createdAt: date(from: row["source_created_at"] as String?),
            updatedAt: date(from: row["source_updated_at"] as String?)
        )
    }

    private static func chunk(fromPrefixed row: Row) -> ContextChunk {
        ContextChunk(
            id: row["chunk_id"],
            sourceID: row["chunk_source_id"],
            ordinal: row["chunk_ordinal"],
            rawText: row["chunk_raw_text"],
            contextualHeader: row["chunk_contextual_header"],
            anchor: row["chunk_anchor"],
            tokenCount: row["chunk_token_count"],
            bodyHash: row["chunk_body_hash"]
        )
    }

    private static func session(from row: Row, pinnedSourceIDs: [String]) -> ContextSession {
        let decisionsJSON = row["recent_decision_summaries"] as String? ?? "[]"
        let decisionsData = decisionsJSON.data(using: .utf8) ?? Data()
        let decisions = (try? JSONDecoder().decode([String].self, from: decisionsData)) ?? []
        return ContextSession(
            id: row["id"],
            surface: ContextSurface(rawValue: row["surface"] as String) ?? .cosmoWindow,
            activeAtomUUID: row["active_atom_uuid"],
            activeClientUUID: row["active_client_uuid"],
            pinnedSourceIDs: pinnedSourceIDs,
            recentDecisionSummaries: decisions,
            updatedAt: date(from: row["updated_at"] as String?)
        )
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from value: String?) -> Date {
        guard let value else { return Date() }
        return ISO8601DateFormatter().date(from: value) ?? Date()
    }

    private static func ftsQuery(for query: String) -> String {
        let phrases = quotedPhrases(in: query)
        if !phrases.isEmpty {
            return phrases
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: " OR ")
        }

        let terms = searchTerms(in: query)
        return terms
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
            .joined(separator: " OR ")
    }

    private struct StoredKeywordHit: Sendable {
        let source: ContextSource
        let chunk: ContextChunk
        let score: Double
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "from", "that", "this", "with", "does", "did",
        "brief", "mention", "mentions", "what", "where", "when", "how", "are",
        "was", "were", "you", "your", "into", "about", "there"
    ]
}
