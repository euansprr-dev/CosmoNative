// CosmoOS/UI/Pipeline/ContentPipelineLoader.swift
// ONE loader for content rows: the Pipeline board/list/calendar, the Shelf
// rails (through the `ContentQueueItem` adapter) and the Clients pages all
// read the same decoded rows. Scope is applied in SQL — `json_extract` on
// the metadata column, the idiom `ContentPipelineService` already uses —
// so a client hub never pays for the whole library. Live rows carry NO row
// cap (the old 300-row limit silently dropped the oldest drafts); archive
// reads are capped at the newest 500.
//
// Perf law: everything a card shows is decoded HERE, once per load. Views
// never touch metadata.
// September 2026

import Foundation
import GRDB

// MARK: - Row models

struct PipelineContentItem: Identifiable, Equatable, Sendable {
    let atom: Atom
    let phase: ContentPhase
    /// Where the piece sat before it was scheduled — restored on unschedule.
    let phaseBeforeSchedule: ContentPhase?
    let scheduledAt: Date?
    /// Raw `status` lens value ("draft" / "scheduled" / "published"), kept so
    /// the Shelf-rail adapter reads exactly what it always read.
    let status: String?
    let clientUUID: String?
    /// Resolved ONCE at load — never a fetch in a view body.
    let clientName: String?
    let platform: SocialPlatform?
    /// Raw `ContentFormat` value as stored (unknown values survive).
    let format: String?
    let sourceIdeaUUID: String?
    let latestPublish: ContentPublishRecord?
    let wordCount: Int
    let updatedAt: Date
    let phaseEnteredAt: Date?
    var editorialStage: ContentProductionStage? = nil

    var id: String { atom.uuid }

    var productionStage: ContentProductionStage { phase.isShipped ? .published : (editorialStage ?? .inProgress) }

    var isShipped: Bool { productionStage == .published }

    var title: String {
        atom.title?.isEmpty == false ? atom.title! : "Untitled"
    }

    var contentFormat: ContentFormat? {
        format.flatMap(ContentFormat.init(rawValue:))
    }

    /// The day a shipped piece went out: the newest publish record, else the
    /// moment it entered its phase, else its last edit.
    var shippedAt: Date? {
        guard isShipped else { return nil }
        return latestPublish?.publishedAtDate ?? phaseEnteredAt ?? updatedAt
    }
}

struct PipelineClient: Identifiable, Equatable, Sendable {
    let uuid: String
    let name: String
    /// Normalised 6-digit hex when the dossier pinned a swatch.
    let colorHex: String?
    let niche: String?
    let platforms: [SocialPlatform]
    let postingFrequency: String?

    var id: String { uuid }

    var cadence: ClientCadence? { ClientCadence.parse(postingFrequency) }
}

// MARK: - Phase helper

extension ContentPhase {
    /// Published or analyzing — the two "it went out" phases. Twin of the
    /// stage-machine's `isShipped`; collapse onto that once it lands.
    var pipelineIsShipped: Bool {
        self == .published || self == .analyzing
    }
}

// MARK: - Loader

enum ContentPipelineLoader {

    struct Workspace: Sendable {
        let content: [PipelineContentItem]
        let archived: [PipelineContentItem]
        let clients: [PipelineClient]
    }

    /// The board needs all three collections. Read them in one database
    /// snapshot and decode on the reader queue, resolving client names once.
    /// Previously each content collection fetched clients again, and the idea
    /// rail fetched the full client table a second time.
    static func loadWorkspace(scope: PipelineScope) async throws -> Workspace {
        let workspace = try await CosmoDatabase.shared.asyncRead { db in
            let profiles = try Atom.filter(Column("type") == AtomType.clientProfile.rawValue)
                .filter(Column("is_deleted") == false).fetchAll(db)
            let clients = makeClients(profiles)
            let names = Dictionary(uniqueKeysWithValues: clients.map { ($0.uuid, $0.name) })
            func rows(archived: Bool) throws -> [PipelineContentItem] {
                try request(scope: scope, archived: archived, limit: nil).fetchAll(db).map { atom in
                    makeItem(atom: atom, lens: atom.metadataValue(as: RowLens.self), clientNames: names)
                }
            }
            return try Workspace(content: rows(archived: false), archived: rows(archived: true), clients: clients)
        }
        ClientColorResolver.shared.refresh(with: workspace.clients.map { (uuid: $0.uuid, colorHex: $0.colorHex) })
        return workspace
    }

    /// Live (non-archived) content in `scope`, newest edit first, no row cap.
    /// `filters` narrow in memory after decode through the ONE predicate.
    static func load(scope: PipelineScope, filters: PipelineFilters = PipelineFilters()) async -> [PipelineContentItem] {
        (try? await loadChecked(scope: scope, filters: filters)) ?? []
    }

    static func loadChecked(scope: PipelineScope, filters: PipelineFilters = PipelineFilters(), archived: Bool = false) async throws -> [PipelineContentItem] {
        let atoms = try await CosmoDatabase.shared.asyncRead { db in
            try request(scope: scope, archived: archived, limit: nil).fetchAll(db)
        }
        let items = await decorate(atoms)
        guard !filters.isEmpty else { return items }
        return items.filter { item in
            filters.matches(
                title: item.title,
                clientName: item.clientName,
                platform: item.platform,
                format: item.contentFormat
            )
        }
    }

    /// Archived content in `scope` — the newest 500 edits.
    static func loadArchived(scope: PipelineScope) async -> [PipelineContentItem] {
        let atoms = await fetchAtoms(scope: scope, archived: true, limit: 500)
        return await decorate(atoms)
    }

    /// Every live client profile, name-sorted. Also feeds the colour resolver
    /// so `DS.clientColor(for:)` is right before the first card paints.
    static func loadClients() async -> [PipelineClient] {
        let atoms = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
        let clients = makeClients(atoms)
        ClientColorResolver.shared.refresh(with: clients.map { (uuid: $0.uuid, colorHex: $0.colorHex) })
        return clients
    }

    private static func makeClients(_ atoms: [Atom]) -> [PipelineClient] {
        var clients: [PipelineClient] = []
        clients.reserveCapacity(atoms.count)
        for atom in atoms {
            let meta = atom.metadataValue(as: ClientProfileMetadata.self)
            clients.append(PipelineClient(
                uuid: atom.uuid,
                name: resolvedName(title: atom.title, fallback: meta?.clientName) ?? "Untitled client",
                colorHex: ClientColorResolver.normalizedHex(meta?.colorHex),
                niche: nonEmpty(meta?.niche),
                platforms: meta?.platforms ?? [],
                postingFrequency: nonEmpty(meta?.postingFrequency)
            ))
        }
        clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return clients
    }

    // MARK: - SQL

    /// `json_extract` guarded by `json_valid` so one malformed metadata blob
    /// can never fail the whole page load (json_extract raises on bad JSON).
    private static let phaseSQL = "CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.phase') END"
    private static let clientSQL = "CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.clientProfileUUID') END"

    private static func fetchAtoms(scope: PipelineScope, archived: Bool, limit: Int?) async -> [Atom] {
        (try? await CosmoDatabase.shared.asyncRead { db in
            try request(scope: scope, archived: archived, limit: limit).fetchAll(db)
        }) ?? []
    }

    static func request(scope: PipelineScope, archived: Bool, limit: Int?) -> QueryInterfaceRequest<Atom> {
        var request = Atom
            .filter(Column("type") == AtomType.content.rawValue)
            .filter(Column("is_deleted") == false)

        if archived {
            request = request.filter(sql: "\(phaseSQL) = ?", arguments: [ContentPhase.archived.rawValue])
        } else {
            // COALESCE: a row with no phase key is live, not NULL-excluded.
            request = request.filter(sql: "COALESCE(\(phaseSQL), '') != ?", arguments: [ContentPhase.archived.rawValue])
        }

        request = scope.constraining(request, clientKey: "clientProfileUUID")

        request = request.order(Column("updated_at").desc)
        if let limit {
            request = request.limit(limit)
        }
        return request
    }

    // MARK: - Decode

    /// One tolerant lens over every key a card reads — the pipeline keys
    /// (`ContentAtomMetadata`), the queue keys (`ContentMetadata`) and the
    /// legacy `scheduledDate`. Each key decodes independently, so a stray
    /// value in one never blanks the rest.
    private struct RowLens: Decodable {
        var phase: ContentPhase?
        var productionStage: ContentProductionStage?
        var phaseBeforeSchedule: ContentPhase?
        var clientProfileUUID: String?
        var platform: SocialPlatform?
        var contentFormat: String?
        var wordCount: Int?
        var sourceIdeaUUID: String?
        var phaseEnteredAt: String?
        var scheduledAt: String?
        var scheduledDate: String?
        var status: String?

        private enum CodingKeys: String, CodingKey {
            case phase, phaseBeforeSchedule, clientProfileUUID, platform, contentFormat, productionStage
            case wordCount, sourceIdeaUUID, phaseEnteredAt, scheduledAt, scheduledDate, status
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // `try?` flattens: a missing key, a wrong type and a decode error
            // all read as nil for THAT key only.
            phase = Self.string(c, .phase).flatMap(ContentPhase.init(rawValue:))
            productionStage = Self.string(c, .productionStage).flatMap(ContentProductionStage.init(rawValue:))
            phaseBeforeSchedule = Self.string(c, .phaseBeforeSchedule).flatMap(ContentPhase.init(rawValue:))
            clientProfileUUID = Self.string(c, .clientProfileUUID)
            platform = Self.string(c, .platform).flatMap(SocialPlatform.init(rawValue:))
            contentFormat = Self.string(c, .contentFormat)
            wordCount = try? c.decodeIfPresent(Int.self, forKey: .wordCount)
            sourceIdeaUUID = Self.string(c, .sourceIdeaUUID)
            phaseEnteredAt = Self.string(c, .phaseEnteredAt)
            scheduledAt = Self.string(c, .scheduledAt)
            scheduledDate = Self.string(c, .scheduledDate)
            status = Self.string(c, .status)
        }

        private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            try? c.decodeIfPresent(String.self, forKey: key)
        }
    }

    private struct ClientNameLens: Decodable {
        var clientName: String?
    }

    private static func decorate(_ atoms: [Atom]) async -> [PipelineContentItem] {
        let lenses = atoms.map { $0.metadataValue(as: RowLens.self) }
        let names = await clientNames(for: Set(lenses.compactMap { $0?.clientProfileUUID }))

        var items: [PipelineContentItem] = []
        items.reserveCapacity(atoms.count)
        for (atom, lens) in zip(atoms, lenses) {
            items.append(makeItem(atom: atom, lens: lens, clientNames: names))
        }
        return items
    }

    private static func makeItem(atom: Atom, lens: RowLens?, clientNames: [String: String]) -> PipelineContentItem {
        let clientUUID = nonEmpty(lens?.clientProfileUUID)
        let records = ContentPublishStore.records(for: atom)
        return PipelineContentItem(
            atom: atom,
            phase: lens?.phase ?? .draft,
            phaseBeforeSchedule: lens?.phaseBeforeSchedule,
            scheduledAt: isoDate(lens?.scheduledAt) ?? isoDate(lens?.scheduledDate),
            status: nonEmpty(lens?.status),
            clientUUID: clientUUID,
            clientName: clientUUID.flatMap { clientNames[$0] },
            platform: lens?.platform,
            format: nonEmpty(lens?.contentFormat),
            sourceIdeaUUID: nonEmpty(lens?.sourceIdeaUUID),
            latestPublish: records.max { $0.publishedAtDate < $1.publishedAtDate },
            wordCount: lens?.wordCount ?? bodyWordCount(atom.body),
            updatedAt: ISO8601.date(from: atom.updatedAt) ?? .distantPast,
            phaseEnteredAt: isoDate(lens?.phaseEnteredAt),
            editorialStage: lens?.productionStage
        )
    }

    /// uuid → display name for every client referenced by the batch. One
    /// `fetch(uuids:)`, never a fetch per row.
    private static func clientNames(for uuids: Set<String>) async -> [String: String] {
        guard !uuids.isEmpty else { return [:] }
        let clients = (try? await AtomRepository.shared.fetch(uuids: Array(uuids))) ?? []
        var names: [String: String] = [:]
        for client in clients {
            let fallback = client.metadataValue(as: ClientNameLens.self)?.clientName
            if let name = resolvedName(title: client.title, fallback: fallback) {
                names[client.uuid] = name
            }
        }
        return names
    }

    // MARK: - Small helpers

    private static func resolvedName(title: String?, fallback: String?) -> String? {
        nonEmpty(title) ?? nonEmpty(fallback)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isoDate(_ value: String?) -> Date? {
        value.flatMap { ISO8601.date(from: $0) }
    }

    private static func bodyWordCount(_ body: String?) -> Int {
        guard let body, !body.isEmpty else { return 0 }
        return body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
