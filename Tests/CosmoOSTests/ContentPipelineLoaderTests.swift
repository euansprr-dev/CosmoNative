// Tests/CosmoOSTests/ContentPipelineLoaderTests.swift
// The one content loader: scope is decided in SQL (client / unassigned /
// space), archived rows stay out of the live read and come back from the
// archive read, the legacy `scheduledDate` key still schedules, and — the
// regression the whole loader exists for — more than 300 live rows all
// load. Rows are written raw inside the sync-suppression window and hard
// deleted raw, so nothing here ever reaches the cloud queue.

import XCTest
import GRDB
@testable import CosmoOS

final class ContentPipelineLoaderTests: XCTestCase {

    private var atomUUIDs: [String] = []
    private var blockIDs: [String] = []
    private let clientA = "loader-client-a-\(UUID().uuidString)"
    private let clientB = "loader-client-b-\(UUID().uuidString)"

    override func tearDown() async throws {
        let atoms = atomUUIDs
        let blocks = blockIDs
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                for uuid in atoms {
                    try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [uuid])
                }
                for id in blocks {
                    try db.execute(sql: "DELETE FROM canvas_blocks WHERE id = ?", arguments: [id])
                }
            }
        }
        atomUUIDs.removeAll()
        blockIDs.removeAll()
        ClientColorResolver.shared.refresh(with: [])
        try await super.tearDown()
    }

    // MARK: - Fixtures

    @discardableResult
    private func insert(_ atoms: [Atom]) async throws -> [Atom] {
        atomUUIDs.append(contentsOf: atoms.map(\.uuid))
        return try await CosmoDatabase.shared.asyncWrite { (db: Database) throws -> [Atom] in
            try CanvasBlockSyncObserver.suppressingSync { () throws -> [Atom] in
                var saved: [Atom] = []
                for atom in atoms {
                    var row = atom
                    try row.insert(db)
                    row.id = db.lastInsertedRowID
                    saved.append(row)
                }
                return saved
            }
        }
    }

    private func contentAtom(_ title: String, metadata: String?) -> Atom {
        Atom.new(type: .content, title: title, body: nil, metadata: metadata)
    }

    private func meta(phase: String? = "draft", client: String? = nil, extra: String = "") -> String {
        var parts: [String] = []
        if let phase { parts.append(#""phase":"\#(phase)""#) }
        if let client { parts.append(#""clientProfileUUID":"\#(client)""#) }
        if !extra.isEmpty { parts.append(extra) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func insertCanvasBlock(entityUUID: String, thinkspaceId: String) async throws {
        let id = UUID().uuidString
        blockIDs.append(id)
        try await CosmoDatabase.shared.asyncWrite { db in
            try CanvasBlockSyncObserver.suppressingSync {
                try db.execute(sql: """
                    INSERT INTO canvas_blocks
                        (id, document_type, document_id, entity_id, entity_uuid, entity_type,
                         position_x, position_y, is_deleted, thinkspace_id)
                    VALUES (?, 'home', 0, 0, ?, 'content', 0, 0, 0, ?)
                    """, arguments: [id, entityUUID, thinkspaceId])
            }
        }
    }

    // MARK: - Scope

    func testWorkspaceReadMatchesStandaloneCollections() async throws {
        let client = Atom.new(type: .clientProfile, title: "Performance client", metadata: #"{"clientName":"Fallback"}"#)
        let live = contentAtom("Working draft", metadata: meta(client: client.uuid))
        let archived = contentAtom("Filed draft", metadata: meta(phase: "archived", client: client.uuid))
        _ = try await insert([client, live, archived])
        let scope = PipelineScope.client(uuid: client.uuid)
        let workspace = try await ContentPipelineLoader.loadWorkspace(scope: scope)
        let expectedLive = try await ContentPipelineLoader.loadChecked(scope: scope)
        let expectedArchive = try await ContentPipelineLoader.loadChecked(scope: scope, archived: true)
        XCTAssertEqual(workspace.content, expectedLive)
        XCTAssertEqual(workspace.archived, expectedArchive)
        XCTAssertEqual(workspace.content.first?.clientName, "Performance client")
        XCTAssertTrue(workspace.clients.contains { $0.uuid == client.uuid })
    }

    func testClientScopeExcludesOtherClientsAndUnassigned() async throws {
        let rows = try await insert([
            contentAtom("A1", metadata: meta(client: clientA)),
            contentAtom("A2", metadata: meta(phase: "polish", client: clientA)),
            contentAtom("B1", metadata: meta(client: clientB)),
            contentAtom("U1", metadata: meta()),
        ])
        let scoped = await ContentPipelineLoader.load(scope: .client(uuid: clientA))
        XCTAssertEqual(Set(scoped.map(\.id)), Set(rows.prefix(2).map(\.uuid)))
        XCTAssertTrue(scoped.allSatisfy { $0.clientUUID == clientA })

        let all = await ContentPipelineLoader.load(scope: .all)
        let allIDs = Set(all.map(\.id))
        for row in rows {
            XCTAssertTrue(allIDs.contains(row.uuid), "all-scope must include \(row.title ?? "")")
        }
    }

    func testUnassignedScopeReadsMissingAndEmptyClientKeys() async throws {
        let rows = try await insert([
            contentAtom("Assigned", metadata: meta(client: clientA)),
            contentAtom("NoKey", metadata: meta()),
            contentAtom("EmptyKey", metadata: meta(client: "")),
            contentAtom("NoMetadata", metadata: nil),
        ])
        let unassigned = await ContentPipelineLoader.load(scope: .unassigned)
        let ids = Set(unassigned.map(\.id))
        XCTAssertFalse(ids.contains(rows[0].uuid))
        XCTAssertTrue(ids.contains(rows[1].uuid))
        XCTAssertTrue(ids.contains(rows[2].uuid))
        XCTAssertTrue(ids.contains(rows[3].uuid), "a row with no metadata at all is live, unassigned content")
        XCTAssertTrue(unassigned.allSatisfy { $0.clientUUID == nil })
    }

    func testSpaceScopeReadsThinkspaceCanvasPlacements() async throws {
        let thinkspace = "loader-space-\(UUID().uuidString)"
        let rows = try await insert([
            contentAtom("On canvas", metadata: meta(client: clientA)),
            contentAtom("Elsewhere", metadata: meta(client: clientA)),
        ])
        try await insertCanvasBlock(entityUUID: rows[0].uuid, thinkspaceId: thinkspace)
        try await insertCanvasBlock(entityUUID: rows[1].uuid, thinkspaceId: "some-other-space")

        let inSpace = await ContentPipelineLoader.load(scope: .space(thinkspaceId: thinkspace))
        XCTAssertEqual(inSpace.map(\.id), [rows[0].uuid])
    }

    // MARK: - Archive

    func testArchivedRowsLeaveTheLiveReadAndReturnFromTheArchiveRead() async throws {
        let rows = try await insert([
            contentAtom("Live", metadata: meta(client: clientA)),
            contentAtom("Archived", metadata: meta(phase: "archived", client: clientA)),
            contentAtom("Shipped", metadata: meta(phase: "published", client: clientA)),
        ])
        let live = await ContentPipelineLoader.load(scope: .client(uuid: clientA))
        XCTAssertEqual(Set(live.map(\.id)), [rows[0].uuid, rows[2].uuid])

        let archived = await ContentPipelineLoader.loadArchived(scope: .client(uuid: clientA))
        XCTAssertEqual(archived.map(\.id), [rows[1].uuid])
        XCTAssertEqual(archived.first?.phase, .archived)
        XCTAssertTrue(live.first { $0.id == rows[2].uuid }?.isShipped == true)
    }

    // MARK: - Decode

    func testLegacyScheduledDateIsReadAsAFallback() async throws {
        let rows = try await insert([
            contentAtom("Legacy", metadata: meta(phase: "scheduled", client: clientA, extra: #""scheduledDate":"2030-01-05T09:00:00Z""#)),
            contentAtom("Modern", metadata: meta(phase: "scheduled", client: clientA, extra: #""scheduledAt":"2030-02-06T09:00:00Z","scheduledDate":"2029-01-01T00:00:00Z""#)),
        ])
        let items = await ContentPipelineLoader.load(scope: .client(uuid: clientA))
        let legacy = try XCTUnwrap(items.first { $0.id == rows[0].uuid })
        XCTAssertEqual(legacy.scheduledAt, ISO8601.date(from: "2030-01-05T09:00:00Z"))
        let modern = try XCTUnwrap(items.first { $0.id == rows[1].uuid })
        XCTAssertEqual(modern.scheduledAt, ISO8601.date(from: "2030-02-06T09:00:00Z"), "scheduledAt wins over the legacy key")
    }

    func testRowsDecodeTolerantlyAndResolveClientNames() async throws {
        let client = Atom.new(type: .clientProfile, title: "Josh", body: nil,
                              metadata: ##"{"clientName":"Josh","colorHex":"#5e8c61","niche":"Fitness","postingFrequency":"3x/week","platforms":["instagram"]}"##)
        try await insert([client])
        let rows = try await insert([
            contentAtom("Full", metadata: meta(phase: "polish", client: client.uuid, extra:
                #""platform":"instagram","contentFormat":"reel","wordCount":42,"sourceIdeaUUID":"idea-1","status":"scheduled","phaseEnteredAt":"2030-03-03T10:00:00Z","phaseBeforeSchedule":"draft","publishRecords":[{"platform":"instagram","publishedAt":"2030-03-01T09:00:00Z"},{"platform":"linkedin","publishedAt":"2030-03-04T09:00:00Z"}]"#)),
            contentAtom("Sparse", metadata: meta(phase: nil, client: client.uuid, extra: #""platform":"hologram","phase":"not-a-phase""#)),
            contentAtom("Broken", metadata: "not json at all"),
        ])
        let items = await ContentPipelineLoader.load(scope: .client(uuid: client.uuid))
        let full = try XCTUnwrap(items.first { $0.id == rows[0].uuid })
        XCTAssertEqual(full.phase, .polish)
        XCTAssertEqual(full.clientName, "Josh")
        XCTAssertEqual(full.platform, .instagram)
        XCTAssertEqual(full.contentFormat, .reel)
        XCTAssertEqual(full.wordCount, 42)
        XCTAssertEqual(full.sourceIdeaUUID, "idea-1")
        XCTAssertEqual(full.status, "scheduled")
        XCTAssertEqual(full.phaseBeforeSchedule, .draft)
        XCTAssertEqual(full.phaseEnteredAt, ISO8601.date(from: "2030-03-03T10:00:00Z"))
        XCTAssertEqual(full.latestPublish?.platform, "linkedin", "the newest publish record is the latest")

        let sparse = try XCTUnwrap(items.first { $0.id == rows[1].uuid })
        XCTAssertEqual(sparse.phase, .draft, "an unknown phase reads as a draft, not a decode failure")
        XCTAssertNil(sparse.platform)
        XCTAssertEqual(sparse.clientName, "Josh")

        let broken = await ContentPipelineLoader.load(scope: .all)
        XCTAssertTrue(broken.contains { $0.id == rows[2].uuid }, "one malformed metadata blob must not fail the load")
        XCTAssertEqual(broken.first { $0.id == rows[2].uuid }?.phase, .draft)
    }

    func testLoadClientsFeedsTheColourResolver() async throws {
        let client = Atom.new(type: .clientProfile, title: "Ben", body: nil,
                              metadata: #"{"clientName":"Ben","colorHex":"a23b72","niche":"","postingFrequency":"daily","platforms":["linkedin","x"]}"#)
        try await insert([client])
        let clients = await ContentPipelineLoader.loadClients()
        let ben = try XCTUnwrap(clients.first { $0.uuid == client.uuid })
        XCTAssertEqual(ben.name, "Ben")
        XCTAssertEqual(ben.colorHex, "A23B72")
        XCTAssertNil(ben.niche, "an empty niche is no niche")
        XCTAssertEqual(ben.platforms, [.linkedin, .x])
        XCTAssertEqual(ben.cadence?.perWeek, 7)
        XCTAssertEqual(ClientColorResolver.shared.hex(for: client.uuid), "A23B72")
        XCTAssertEqual(clients.map(\.name), clients.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - No row cap

    func testMoreThanThreeHundredLiveRowsAllLoad() async throws {
        let rows = (0..<320).map { index in
            contentAtom("Bulk \(index)", metadata: meta(phase: index % 2 == 0 ? "draft" : "polish", client: clientB))
        }
        try await insert(rows)
        let loaded = await ContentPipelineLoader.load(scope: .client(uuid: clientB))
        XCTAssertEqual(loaded.count, 320, "the old 300-row cap silently dropped the oldest drafts")
        XCTAssertEqual(Set(loaded.map(\.id)), Set(rows.map(\.uuid)))

        let filtered = await ContentPipelineLoader.load(scope: .client(uuid: clientB), filters: PipelineFilters(query: "bulk 31"))
        XCTAssertEqual(filtered.count, 13, "\"bulk 31\" matches Bulk 31, 131, 231 and 310–319")
    }

    // MARK: - Shelf adapter

    func testQueueItemAdapterDerivesStatusFromPublicationAndDate() {
        func item(phase: ContentPhase, status: String?) -> PipelineContentItem {
            PipelineContentItem(
                atom: Atom.new(type: .content, title: "x", body: nil), phase: phase, phaseBeforeSchedule: nil,
                scheduledAt: nil, status: status, clientUUID: "c", clientName: "C", platform: nil, format: nil,
                sourceIdeaUUID: nil, latestPublish: nil, wordCount: 0, updatedAt: .distantPast, phaseEnteredAt: nil
            )
        }
        XCTAssertEqual(ContentQueueItem(item: item(phase: .draft, status: nil)).status, "draft")
        XCTAssertEqual(ContentQueueItem(item: item(phase: .published, status: nil)).status, "published")
        XCTAssertEqual(ContentQueueItem(item: item(phase: .analyzing, status: nil)).status, "published")
        XCTAssertEqual(ContentQueueItem(item: item(phase: .draft, status: "scheduled")).status, "draft")
        XCTAssertTrue(ContentQueueItem(item: item(phase: .analyzing, status: nil)).isPublished)
        XCTAssertEqual(ContentQueueItem(item: item(phase: .draft, status: nil)).clientUUID, "c")
    }
}
