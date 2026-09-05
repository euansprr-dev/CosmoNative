import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class SpaceContentWorkflowTests: XCTestCase {
    private var created: [String] = []

    override func tearDown() async throws {
        CosmoUndoManager.shared.clearHistory()
        for uuid in created.reversed() { try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true) }
        created.removeAll()
        try await super.tearDown()
    }

    private func atom(_ type: AtomType, title: String = "Workflow fixture", fields: [String: Any] = [:]) async throws -> Atom {
        let metadata = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
        let saved = try await AtomRepository.shared.create(Atom.new(type: type, title: title, metadata: metadata))
        created.append(saved.uuid)
        return saved
    }

    private func fresh(_ id: String) async throws -> Atom {
        let value = try await AtomRepository.shared.fetch(uuid: id)
        return try XCTUnwrap(value)
    }

    func testNewSpaceDocumentHasMembershipWithoutCanvasPlacement() async throws {
        let space = try await atom(.thinkspace)
        let note = try await SpaceMembershipService.create(type: .note, title: "Understanding", in: space.uuid)
        created.append(note.uuid)
        let members = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertEqual(members, [note.uuid])
        let row = try await CosmoDatabase.shared.asyncRead { db in
            try CanvasBlockRecord.filter(Column("entity_uuid") == note.uuid).fetchOne(db)
        }
        XCTAssertEqual(row?.isPlaced, false)
        XCTAssertEqual(row?.entityId, Int(note.id ?? -1))
        _ = try await SpaceMembershipService.add(note, to: space.uuid)
        let count = try await CosmoDatabase.shared.asyncRead { db in
            try CanvasBlockRecord.filter(Column("entity_uuid") == note.uuid).filter(Column("is_deleted") == false).fetchCount(db)
        }
        XCTAssertEqual(count, 1, "Adding an existing member is idempotent")
    }

    func testHomeSaveAndLegacySpaceEditsPreserveEachOthersFields() async throws {
        let space = try await atom(.thinkspace, fields: ["name": "Evidence", "futureField": ["key": 7], "materialGroups": []])
        let document = RichDocument.migrateLegacy("An observation with a source.")
        let saved = try await SpaceHomeModel.persist(document, spaceID: space.uuid)
        var legacy = saved.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(name: "Evidence")
        legacy.accentColorHex = "#2D6A4F"
        var changed = saved
        changed.metadata = legacy.mergedJSON(into: saved.metadata)
        _ = try await AtomRepository.shared.update(changed)
        let reloaded = try await fresh(space.uuid)
        XCTAssertEqual(RichDocumentMetadataStorage.readDocument(from: reloaded.metadata, key: SpaceHomeModel.documentKey, atomUUID: space.uuid)?.plainText,
                       document.plainText)
        XCTAssertEqual((reloaded.metadataDict?["futureField"] as? [String: Int])?["key"], 7)
        XCTAssertNotNil(reloaded.metadataDict?["materialGroups"])
    }

    func testMaterialMigrationHappensOnceAndNeverChangesCanvasGeometry() async throws {
        let groupID = UUID()
        let space = try await atom(.thinkspace, fields: ["name": "Evidence", "clusters": [
            ["id": groupID.uuidString, "name": "Primary sources", "blockUUIDs": ["source"], "colorIndex": 2,
             "originX": 170, "originY": 240, "rectWidth": 400, "rectHeight": 320]
        ], "futureField": "keep"])
        let first = try await SpaceMaterialsStore.update(spaceID: space.uuid) { _ in }
        XCTAssertEqual(first.groups.first?.id, groupID)
        XCTAssertEqual(first.groups.first?.itemUUIDs, ["source"])
        _ = try XCTUnwrap(first.groups.first)
        let second = try await SpaceMaterialsStore.update(spaceID: space.uuid) { $0[0].name = "Evidence"; $0[0].itemUUIDs = ["another-source"] }
        let reopened = try await SpaceMaterialsStore.update(spaceID: space.uuid) { _ in }
        XCTAssertEqual(reopened.groups.count, 1)
        XCTAssertEqual(reopened.groups.first?.name, "Evidence")
        XCTAssertEqual(reopened.groups.first?.itemUUIDs, ["another-source"])
        let clusters = second.after.metadataDict?["clusters"] as? [[String: Any]]
        XCTAssertEqual(clusters?.first?["name"] as? String, "Primary sources")
        XCTAssertEqual(clusters?.first?["blockUUIDs"] as? [String], ["source"])
        XCTAssertEqual(clusters?.first?["originX"] as? Int, 170)
        XCTAssertEqual(second.after.metadataDict?["futureField"] as? String, "keep")
    }

    func testAnEmptyMaterialCollectionDoesNotRemigrateOldClusters() async throws {
        let space = try await atom(.thinkspace, fields: ["materialGroups": [], "clusters": [
            ["id": UUID().uuidString, "name": "Old", "blockUUIDs": [], "colorIndex": 0]
        ]])
        let result = try await SpaceMaterialsStore.update(spaceID: space.uuid) { _ in }
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testCorruptMetadataRefusesHomeAndGroupingWrites() async throws {
        var space = try await atom(.thinkspace)
        space.metadata = "{invalid"
        space = try await AtomRepository.shared.update(space)
        do { _ = try await SpaceHomeModel.persist(.migrateLegacy("new"), spaceID: space.uuid); XCTFail("Must refuse") } catch {}
        do { _ = try await SpaceMaterialsStore.update(spaceID: space.uuid) { _ in }; XCTFail("Must refuse") } catch {}
        let after = try await fresh(space.uuid)
        XCTAssertEqual(after.metadata, "{invalid")
    }

    func testEditorialReadinessAndDatesDoNotAdvanceEachOther() async throws {
        let content = try await atom(.content, fields: ["phase": "polish", "productionStage": "review", "futureField": "keep"])
        let planned = ISO8601.date(from: "2030-03-31T00:30:00Z")!
        let scheduled = await ContentQueueLoader.setSchedule(planned, status: nil, for: content.uuid, registerUndo: false)
        XCTAssertTrue(scheduled)
        let dated = try await fresh(content.uuid)
        XCTAssertEqual(ContentProductionStage.of(dated), .review)
        XCTAssertEqual(ContentPipelineService.currentPhase(of: dated), .polish)
        _ = try await ContentPipelineService.applyProductionStage(contentUUID: content.uuid, to: .ready)
        let ready = try await fresh(content.uuid)
        XCTAssertEqual(ready.metadataDict?["scheduledAt"] as? String, ISO8601.string(from: planned))
        _ = await ContentQueueLoader.setSchedule(nil, status: nil, for: content.uuid, registerUndo: false)
        let undated = try await fresh(content.uuid)
        XCTAssertEqual(ContentProductionStage.of(undated), .ready)
        XCTAssertNil(undated.metadataDict?["scheduledAt"])
        XCTAssertEqual(undated.metadataDict?["futureField"] as? String, "keep")
    }

    func testDateUndoPreservesLaterManuscriptAndReadiness() async throws {
        let content = try await atom(.content, fields: ["phase": "draft"])
        CosmoUndoManager.shared.clearHistory()
        _ = await ContentQueueLoader.setSchedule(Date(), status: nil, for: content.uuid)
        _ = try await ContentPipelineService.applyProductionStage(contentUUID: content.uuid, to: .ready)
        var editing = try await fresh(content.uuid)
        editing.body = "Words added after the date was planned."
        _ = try await AtomRepository.shared.update(editing)
        await CosmoUndoManager.shared.undo()
        let undone = try await fresh(content.uuid)
        XCTAssertNil(undone.metadataDict?["scheduledAt"])
        XCTAssertEqual(undone.body, editing.body)
        XCTAssertEqual(ContentProductionStage.of(undone), .ready)
    }

    func testPromotionKeepsSpaceSourcesAndOneIdentityThroughUndoRedo() async throws {
        let space = try await atom(.thinkspace)
        var idea = try await atom(.idea, fields: ["ideaStatus": "developing", "clientUUID": "client-a", "platform": "instagram"])
        idea = idea.addingLink(AtomLink(type: "source", uuid: space.uuid, entityType: "thinkspace"))
        idea = try await AtomRepository.shared.update(idea)
        _ = try await SpaceMembershipService.add(idea, to: space.uuid)
        let result = try await IdeaPromotionService.promote(ideaUUID: idea.uuid,
            options: .init(refreshInsightIfStale: false, initialPhase: .draft, productionStage: .review, carryAssistantSession: false))
        created.append(result.content.uuid)
        XCTAssertEqual(ContentProductionStage.of(result.content), .review)
        XCTAssertEqual(result.content.metadataDict?["clientProfileUUID"] as? String, "client-a")
        XCTAssertEqual(result.content.metadataDict?["platform"] as? String, "instagram")
        XCTAssertTrue(result.content.linksList.contains { $0.type == "source" && $0.uuid == space.uuid })
        let visible = try await ContentIdeaLoader.load(scope: .space(thinkspaceId: space.uuid))
        XCTAssertTrue(visible.contains { $0.uuid == idea.uuid })
        let scopedContent = await ContentPipelineLoader.load(scope: .space(thinkspaceId: space.uuid))
        XCTAssertEqual(scopedContent.map(\.id), [result.content.uuid])
        try await IdeaPromotionService.revert(result)
        let removedMembers = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertFalse(removedMembers.contains(result.content.uuid))
        try await IdeaPromotionService.restore(result)
        let restoredMembers = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertTrue(restoredMembers.contains(result.content.uuid))
        let restoredIdea = try await fresh(idea.uuid)
        XCTAssertEqual(restoredIdea.ideaMetadata?.contentUUIDs, [result.content.uuid])
        XCTAssertEqual(restoredIdea.ideaMetadata?.ideaStatus, .developing)
    }

    func testSpaceAndPersonalIdeaScopesNeverFallBackToGlobal() async throws {
        let a = try await atom(.thinkspace)
        let b = try await atom(.thinkspace)
        let local = try await atom(.idea, fields: ["clientUUID": "client-a", "ideaStatus": "inProduction"])
        let foreign = try await atom(.idea, fields: ["clientUUID": "client-b"])
        let personal = try await atom(.idea)
        _ = try await SpaceMembershipService.add(local, to: a.uuid)
        _ = try await SpaceMembershipService.add(foreign, to: b.uuid)
        let scoped = try await ContentIdeaLoader.load(scope: .space(thinkspaceId: a.uuid))
        XCTAssertEqual(scoped.map(\.uuid), [local.uuid])
        let own = try await ContentIdeaLoader.load(scope: .unassigned)
        XCTAssertTrue(own.contains { $0.uuid == personal.uuid })
        XCTAssertFalse(own.contains { $0.uuid == foreign.uuid || $0.uuid == local.uuid })
    }

    func testClientReassignmentPreservesSourceLinksAndOtherMetadata() async throws {
        var content = try await atom(.content, fields: ["phase": "draft", "productionStage": "ready", "futureField": 9])
        content = content.addingLink(.contentToIdea("source-idea")).addingLink(.contentToClient("old-client"))
            .addingLink(AtomLink(type: "client", uuid: "legacy-client", entityType: "clientProfile"))
        content = try await AtomRepository.shared.update(content)
        _ = try await ContentPipelineService.assignClient(contentUUID: content.uuid, to: "new-client")
        let updated = try await fresh(content.uuid)
        XCTAssertEqual(updated.links(ofType: .contentToClient).map(\.uuid), ["new-client"])
        XCTAssertTrue(updated.links(ofType: "client").isEmpty)
        XCTAssertEqual(updated.links(ofType: .contentToIdea).map(\.uuid), ["source-idea"])
        XCTAssertEqual(updated.metadataDict?["futureField"] as? Int, 9)
        XCTAssertEqual(ContentProductionStage.of(updated), .ready)
        _ = try await ContentPipelineService.assignClient(contentUUID: content.uuid, to: nil)
        let personal = try await fresh(content.uuid)
        XCTAssertNil(personal.metadataDict?["clientProfileUUID"])
        XCTAssertTrue(personal.links(ofType: .contentToClient).isEmpty)
    }

    func testMalformedLegacyGroupsDoNotCommitAnEmptyMigration() async throws {
        let space = try await atom(.thinkspace, fields: ["clusters": [["id": "unreadable", "name": "Keep this", "blockUUIDs": ["source"]]]])
        do {
            _ = try await SpaceMaterialsStore.update(spaceID: space.uuid) { _ in }
            XCTFail("An unreadable group must leave the migration pending")
        } catch {}
        let saved = try await fresh(space.uuid)
        XCTAssertNil(saved.metadataDict?["materialGroups"])
        XCTAssertEqual((saved.metadataDict?["clusters"] as? [[String: Any]])?.first?["name"] as? String, "Keep this")
    }

    func testRemovingOneSpaceMembershipKeepsSourceAndOtherSpace() async throws {
        let a = try await atom(.thinkspace)
        let b = try await atom(.thinkspace)
        let source = try await atom(.research)
        _ = try await SpaceMembershipService.add(source, to: a.uuid)
        _ = try await SpaceMembershipService.add(source, to: b.uuid)
        try await SpaceMembershipService.remove(source.uuid, from: a.uuid)
        let first = try await SpaceMembershipService.memberUUIDs(in: a.uuid)
        let second = try await SpaceMembershipService.memberUUIDs(in: b.uuid)
        let saved = try await fresh(source.uuid)
        XCTAssertFalse(first.contains(source.uuid))
        XCTAssertTrue(second.contains(source.uuid))
        XCTAssertFalse(saved.isDeleted)
    }

    func testArchiveRestoreRetainsReadinessAndPublicationPlan() async throws {
        let content = try await atom(.content, fields: ["phase": "polish", "productionStage": "ready", "scheduledAt": "2030-09-12T00:00:00Z"])
        _ = try await ContentPipelineService.applyPhase(contentUUID: content.uuid, to: .archived, notes: nil)
        let archived = try await fresh(content.uuid)
        XCTAssertEqual(archived.metadataDict?["phaseBeforeArchive"] as? String, "polish")
        _ = try await ContentPipelineService.applyPhase(contentUUID: content.uuid, to: .polish, notes: nil)
        let restored = try await fresh(content.uuid)
        XCTAssertEqual(ContentProductionStage.of(restored), .ready)
        XCTAssertEqual(restored.metadataDict?["scheduledAt"] as? String, "2030-09-12T00:00:00Z")
        XCTAssertNil(restored.metadataDict?["phaseBeforeArchive"])
    }
}
