import XCTest
import GRDB
@testable import CosmoOS

final class SpaceCompositionModelTests: XCTestCase {
    private func page(_ uuid: String, parent: String? = nil, order: Double = 0, included: Bool = true) throws -> Atom {
        var atom = Atom.new(type: .note, title: uuid)
        atom.uuid = uuid
        return try atom.replacingSpaceComposition(SpaceCompositionMetadata(parentUUID: parent, sortOrder: order, includeInExport: included))
    }

    func testWritingOrderIsIndependentOfCanvasPositionAndStableForTies() throws {
        var root = try page("root")
        var metadata = try XCTUnwrap(root.spaceComposition)
        metadata.placements = [.init(itemUUID: "a", x: 900, y: 500), .init(itemUUID: "b", x: -200, y: 0)]
        root = try root.replacingSpaceComposition(metadata)
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [
            root, page("b", parent: "root", order: 2), page("a", parent: "root", order: 2)
        ])
        XCTAssertEqual(snapshot.children(of: "root").map(\.uuid), ["a", "b"])
        XCTAssertEqual(snapshot.orderedSections(of: "root").map(\.id), ["root", "a", "b"])
        XCTAssertEqual(snapshot.metadataByUUID["root"]?.placements.first?.x, 900)
    }

    func testExcludedBranchesAreAbsentFromExportButRemainInOutline() throws {
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [
            page("root"), page("planning", parent: "root", order: 0, included: false),
            page("private-notes", parent: "planning"), page("chapter", parent: "root", order: 1)
        ])
        XCTAssertEqual(snapshot.orderedSections(of: "root").map(\.id), ["root", "chapter"])
        XCTAssertEqual(snapshot.orderedSections(of: "root", includedOnly: false).map(\.id),
                       ["root", "planning", "private-notes", "chapter"])
        XCTAssertEqual(snapshot.breadcrumbs(to: "private-notes").map(\.uuid), ["root", "planning", "private-notes"])
    }

    func testNativeItemsKeepIdentityAndGroupReferencesDeduplicate() throws {
        var image = Atom.new(type: .image, title: "Light")
        image.uuid = "image"
        var group = Atom.new(type: .note, title: "Inspiration")
        group.uuid = "group"
        var metadata = SpaceCompositionMetadata(kind: .group)
        metadata.memberUUIDs = ["image", "image", "missing"]
        group = try group.replacingSpaceComposition(metadata)
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [group, image])
        XCTAssertEqual(snapshot.members(of: "group").map(\.uuid), ["image"])
        XCTAssertEqual(snapshot.members(of: "group").first?.type, .image)
        XCTAssertTrue(snapshot.orderedSections(of: "group").isEmpty)
        XCTAssertEqual(snapshot.roots.map(\.uuid), ["group"])
    }

    func testExplicitExportIncludesSelectedRootWhileRespectingChildExclusions() throws {
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [
            page("book"), page("planning", parent: "book", included: false),
            page("outline", parent: "planning"), page("private", parent: "planning", included: false)
        ])
        XCTAssertEqual(snapshot.orderedSections(of: "book").map(\.id), ["book"])
        XCTAssertEqual(snapshot.orderedSections(of: "planning").map(\.id), ["planning", "outline"])
    }

    func testSyncedCyclesExposeAStableRootAndTraversalTerminates() throws {
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [
            page("b", parent: "a"), page("a", parent: "b"), page("orphan", parent: "unavailable")
        ])
        XCTAssertEqual(snapshot.roots.map(\.uuid), ["a", "orphan"])
        XCTAssertEqual(snapshot.orderedSections(of: "a").map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.breadcrumbs(to: "a").count, 2)
    }

    func testKnownFieldRemovalPreservesRichDocumentAndFutureKeys() throws {
        let raw = #"{"bodyDocument":"rich-payload","futureRoot":{"color":7},"spaceComposition":{"schemaVersion":1,"kind":"page","parentUUID":"old-parent","origin":{"sourceUUID":"original","sourceVersion":2,"adaptedAt":"now"},"futureNested":"keep"}}"#
        let atom = Atom.new(type: .note, metadata: raw)
        var metadata = try XCTUnwrap(atom.decodedSpaceComposition())
        metadata.parentUUID = nil
        metadata.origin = nil
        let updated = try atom.replacingSpaceComposition(metadata)
        XCTAssertEqual(updated.metadataDict?["bodyDocument"] as? String, "rich-payload")
        XCTAssertEqual((updated.metadataDict?["futureRoot"] as? [String: Int])?["color"], 7)
        let composition = try XCTUnwrap(updated.metadataDict?["spaceComposition"] as? [String: Any])
        XCTAssertEqual(composition["futureNested"] as? String, "keep")
        XCTAssertNil(composition["parentUUID"])
        XCTAssertNil(composition["origin"])
    }

    func testCorruptAndFutureVersionsCannotBeReplacedWithDefaults() throws {
        let corrupt = Atom.new(type: .note, metadata: "{bad")
        XCTAssertThrowsError(try corrupt.replacingSpaceComposition(.init()))
        let future = Atom.new(type: .note, metadata: #"{"spaceComposition":{"schemaVersion":99,"kind":"page"}}"#)
        XCTAssertThrowsError(try future.decodedSpaceComposition()) { error in
            XCTAssertEqual(error as? SpaceCompositionError, .unsupportedVersion(99))
        }
        XCTAssertThrowsError(try future.replacingSpaceComposition(.init()))
        XCTAssertThrowsError(try SpaceCompositionSnapshot(spaceID: "space", atoms: [future]))
    }

    func testPortableReferenceAndCanvasContractRoundTrips() throws {
        var value = SpaceCompositionMetadata(kind: .book, parentUUID: "parent", sortOrder: 4)
        value.references = [.init(id: "ref", sourceUUID: "source", sourceTitle: "Interview", excerpt: "An exact excerpt",
            anchor: .init(blockUUID: "block", pageIndex: 2, timeSeconds: 74.5, url: "https://example.com/source"), annotation: "Counterargument")]
        value.placements = [.init(itemUUID: "chapter", x: -17.25, y: 29, width: 260, height: 170)]
        value.origin = .init(sourceUUID: "book", sourceTitle: "Original", sourceVersion: 7, adaptedAt: "2026-09-05T00:00:00Z")
        value.preferredView = .outline
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(SpaceCompositionMetadata.self, from: data), value)
    }

    func testUnsafeSourceCoordinatesAndDuplicateReferenceIDsAreRejected() throws {
        XCTAssertThrowsError(try SpaceSourceAnchor(pageIndex: Int.max).validate())
        XCTAssertThrowsError(try SpaceSourceAnchor(pageIndex: -1).validate())
        XCTAssertThrowsError(try SpaceSourceAnchor(timeSeconds: .infinity).validate())
        XCTAssertThrowsError(try SpaceSourceAnchor(timeSeconds: Double(Int.max)).validate())
        XCTAssertThrowsError(try SpaceCompositionPlacement(itemUUID: "image", x: .nan, y: 0).validate())
        var metadata = SpaceCompositionMetadata()
        metadata.references = [.init(id: "same", sourceUUID: "one"), .init(id: "same", sourceUUID: "two")]
        XCTAssertThrowsError(try Atom.new(type: .note).replacingSpaceComposition(metadata))
        let raw = #"{"spaceComposition":{"kind":"page","references":[{"id":"ref","sourceUUID":"source","anchor":{"timeSeconds":1e300}}]}}"#
        XCTAssertThrowsError(try Atom.new(type: .note, metadata: raw).decodedSpaceComposition())
    }
}

@MainActor
final class SpaceCompositionNavigationTests: XCTestCase {
    func testNestedPagesAndSpaceRootAreDistinctBackDestinations() {
        let trail = NavigationTrail()
        let root = NavigationTrail.Moment.Destination.spaceView(thinkspaceId: "space", view: .canvas)
        let book = NavigationTrail.Moment.Destination.spaceItem(thinkspaceId: "space", itemUUID: "book")
        let chapter = NavigationTrail.Moment.Destination.spaceItem(thinkspaceId: "space", itemUUID: "chapter")
        for destination in [root, book, chapter, book, chapter] {
            trail.recordArrival(destination, title: "Title", glyph: "doc.text")
        }
        XCTAssertEqual(trail.recentBackTrail(limit: 10).map(\.destination), [book, root])
        XCTAssertEqual(trail.stepBack()?.destination, book)
        XCTAssertEqual(trail.stepBack()?.destination, root)
        XCTAssertEqual(trail.stepForward()?.destination, book)
        XCTAssertEqual(trail.stepForward()?.destination, chapter)
    }

    func testReusedPagePreservesItsSpaceInNavigationHistory() {
        let trail = NavigationTrail()
        let first = NavigationTrail.Moment.Destination.spaceItem(thinkspaceId: "first", itemUUID: "shared-page")
        let second = NavigationTrail.Moment.Destination.spaceItem(thinkspaceId: "second", itemUUID: "shared-page")
        trail.recordArrival(first, title: "Shared page", glyph: "doc.text")
        trail.recordArrival(second, title: "Shared page", glyph: "doc.text")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(trail.stepBack()?.destination, first)
        XCTAssertEqual(trail.stepForward()?.destination, second)
    }
}

@MainActor
final class SpaceCompositionServiceTests: XCTestCase {
    private var created: Set<String> = []

    override func tearDown() async throws {
        CosmoUndoManager.shared.clearHistory()
        for uuid in created { try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true) }
        created.removeAll()
        try await super.tearDown()
    }

    private func atom(_ type: AtomType, title: String = "Composition fixture", metadata: String? = nil) async throws -> Atom {
        let atom = try await AtomRepository.shared.create(Atom.new(type: type, title: title, metadata: metadata))
        created.insert(atom.uuid)
        return atom
    }

    private func fresh(_ uuid: String) async throws -> Atom {
        let atom = try await AtomRepository.shared.fetch(uuid: uuid)
        return try XCTUnwrap(atom)
    }

    private func page(in space: Atom, parent: Atom? = nil, kind: SpaceCompositionKind = .page, title: String = "Page") async throws -> Atom {
        let saved = try await SpaceCompositionService.create(kind: kind, title: title, in: space.uuid, parentUUID: parent?.uuid)
        created.insert(saved.uuid)
        return saved
    }

    private func starter(_ kind: SpaceCompositionKind, in space: Atom) async throws -> Atom {
        let root = try await SpaceCompositionService.createStarter(kind, in: space.uuid)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        created.formUnion(snapshot.atomsByUUID.keys)
        return root
    }

    func testPageCreationHasMembershipWithoutPlacementAndSupportsOrdinaryNotes() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space)
        let child = try await page(in: space, parent: root)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.roots.map(\.uuid), [root.uuid])
        XCTAssertEqual(snapshot.children(of: root.uuid).map(\.uuid), [child.uuid])
        let rows = try await CosmoDatabase.shared.asyncRead { db in
            try CanvasBlockRecord.filter(Column("thinkspace_id") == space.uuid).fetchAll(db)
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.isPlaced == false })
        XCTAssertTrue(rows.allSatisfy { $0.entityId > 0 })
    }

    private func canvasRows(in space: Atom) async throws -> [CanvasBlockRecord] {
        try await CosmoDatabase.shared.asyncRead { db in
            try CanvasBlockRecord.filter(Column("thinkspace_id") == space.uuid)
                .filter(Column("is_deleted") == false).fetchAll(db)
        }
    }

    func testCanvasCreationSavesGroupPlacementBeforeReturning() async throws {
        let space = try await atom(.thinkspace)
        CosmoUndoManager.shared.clearHistory()
        let group = try await SpaceCompositionService.create(kind: .group, title: "References", in: space.uuid,
            placingNear: CGPoint(x: 640, y: 480))
        created.insert(group.uuid)
        let rows = try await canvasRows(in: space)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.isPlaced, true)
        XCTAssertEqual(rows.first?.positionX, 640)
        await CosmoUndoManager.shared.undo()
        let undone = try await canvasRows(in: space)
        XCTAssertTrue(undone.isEmpty)
        XCTAssertFalse(CosmoUndoManager.shared.canUndo)
    }

    func testCanvasBatchPlacesWithoutOverlapAndUndoesExistingMembershipPlacement() async throws {
        let space = try await atom(.thinkspace), other = try await atom(.thinkspace)
        let one = try await page(in: space), two = try await atom(.image)
        try await SpaceCompositionService.addOriginals([one.uuid], in: other.uuid, placingNear: CGPoint(x: 80, y: 90))
        CosmoUndoManager.shared.clearHistory()
        try await SpaceCompositionService.addOriginals([one.uuid, two.uuid, one.uuid], in: space.uuid,
            placingNear: CGPoint(x: 500, y: 400))
        let saved = try await canvasRows(in: space)
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.isPlaced == true })
        let rects = saved.map { row in CGRect(x: CGFloat(row.positionX) - CGFloat(row.width ?? 320) / 2,
            y: CGFloat(row.positionY) - CGFloat(row.height ?? 240) / 2,
            width: CGFloat(row.width ?? 320), height: CGFloat(row.height ?? 240)) }
        XCTAssertFalse(rects[0].intersects(rects[1]))
        try await SpaceCompositionService.addOriginals([one.uuid], in: space.uuid, placingNear: CGPoint(x: -5000, y: -5000))
        let repeated = try await canvasRows(in: space)
        XCTAssertEqual(repeated.first { $0.entityUuid == one.uuid }?.positionX, saved.first { $0.entityUuid == one.uuid }?.positionX)
        await CosmoUndoManager.shared.undo()
        let undone = try await canvasRows(in: space)
        XCTAssertEqual(undone.count, 1)
        XCTAssertEqual(undone.first?.isPlaced, false)
        XCTAssertEqual(undone.first?.positionX, 0)
        let otherRows = try await canvasRows(in: other)
        XCTAssertEqual(otherRows.first?.positionX, 80)
        await CosmoUndoManager.shared.redo()
        let redone = try await canvasRows(in: space)
        XCTAssertEqual(redone.filter { $0.isPlaced == true }.count, 2)
    }

    func testInvalidCanvasBatchRollsBackMembershipAndPlacement() async throws {
        let space = try await atom(.thinkspace), image = try await atom(.image)
        do {
            try await SpaceCompositionService.addOriginals([image.uuid, "missing"], in: space.uuid, placingNear: .zero)
            XCTFail("A missing original must roll back the entire selection")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .notFound) }
        let rows = try await canvasRows(in: space)
        XCTAssertTrue(rows.isEmpty)
    }

    func testScopedCanvasPickerBatchCommitsAndUndoesTogetherWithoutRootPlacement() async throws {
        let space = try await atom(.thinkspace), group = try await page(in: space, kind: .group)
        let image = try await atom(.image), sticky = try await atom(.stickyNote)
        let session = SpaceCompositionCanvasSession(spaceID: space.uuid, containerUUID: group.uuid)
        session.reload()
        do {
            try await session.addExisting([image.uuid, "missing"], near: .zero)
            XCTFail("A failed selection must not add an earlier member")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .notFound) }
        XCTAssertFalse(session.hasPendingEdits)
        let failed = try await fresh(group.uuid)
        XCTAssertTrue(failed.spaceComposition?.memberUUIDs.isEmpty == true)
        CosmoUndoManager.shared.clearHistory()
        try await session.addExisting([image.uuid, sticky.uuid], near: .zero)
        let saved = try await fresh(group.uuid)
        XCTAssertEqual(Set(saved.spaceComposition?.memberUUIDs ?? []), [image.uuid, sticky.uuid])
        XCTAssertEqual(saved.spaceComposition?.placements.count, 2)
        let rows = try await canvasRows(in: space)
        XCTAssertFalse(rows.contains { $0.entityUuid == image.uuid || $0.entityUuid == sticky.uuid })
        await CosmoUndoManager.shared.undo()
        let undone = try await fresh(group.uuid)
        XCTAssertTrue(undone.spaceComposition?.memberUUIDs.isEmpty == true)
        XCTAssertTrue(undone.spaceComposition?.placements.isEmpty == true)
        XCTAssertFalse(CosmoUndoManager.shared.canUndo)
    }

    func testMovingParentIntoDescendantFailsAtomically() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space)
        let child = try await page(in: space, parent: root)
        do {
            try await SpaceCompositionService.move(root.uuid, to: child.uuid, in: space.uuid)
            XCTFail("Cycle must be rejected")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .cycle) }
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertNil(snapshot.metadataByUUID[root.uuid]?.parentUUID)
        XCTAssertEqual(snapshot.metadataByUUID[child.uuid]?.parentUUID, root.uuid)
    }

    func testMovingToRootClearsParentAndPreservesBody() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space)
        _ = try await page(in: space, kind: .group)
        let child = try await page(in: space, parent: root)
        var edited = try await fresh(child.uuid)
        edited.body = "Never overwrite this writing."
        _ = try await AtomRepository.shared.update(edited)
        try await SpaceCompositionService.move(child.uuid, to: nil, in: space.uuid, at: 0)
        let after = try await fresh(child.uuid)
        XCTAssertNil(after.spaceComposition?.parentUUID)
        XCTAssertEqual(after.body, "Never overwrite this writing.")
        await CosmoUndoManager.shared.undo()
        let undone = try await fresh(child.uuid)
        XCTAssertEqual(undone.spaceComposition?.parentUUID, root.uuid)
        XCTAssertEqual(undone.body, "Never overwrite this writing.")
    }

    func testReorderRejectsStaleOrderAndPreservesLayout() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space)
        let one = try await page(in: space, parent: root), two = try await page(in: space, parent: root)
        try await SpaceCompositionService.setPlacement(.init(itemUUID: one.uuid, x: 700, y: 40), for: one.uuid, in: root.uuid)
        try await SpaceCompositionService.reorderChildren(of: root.uuid, in: space.uuid, orderedUUIDs: [two.uuid, one.uuid])
        do {
            try await SpaceCompositionService.reorderChildren(of: root.uuid, in: space.uuid, orderedUUIDs: [one.uuid])
            XCTFail("A missing sibling cannot be silently discarded")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .invalidOrder) }
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.children(of: root.uuid).map(\.uuid), [two.uuid, one.uuid])
        XCTAssertEqual(snapshot.metadataByUUID[root.uuid]?.placements.first?.x, 700)
    }

    func testMixedGroupMembershipIsReusableAndRemovalKeepsOriginals() async throws {
        let space = try await atom(.thinkspace)
        let first = try await page(in: space, kind: .group), second = try await page(in: space, kind: .group)
        let image = try await atom(.image), file = try await atom(.file)
        try await SpaceCompositionService.addMembers([image.uuid, file.uuid, image.uuid], to: first.uuid, in: space.uuid)
        try await SpaceCompositionService.addMembers([image.uuid], to: second.uuid, in: space.uuid)
        try await SpaceCompositionService.removeMembers([image.uuid], from: first.uuid)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.members(of: first.uuid).map(\.uuid), [file.uuid])
        XCTAssertEqual(snapshot.members(of: second.uuid).map(\.uuid), [image.uuid])
        XCTAssertEqual(snapshot.atomsByUUID[image.uuid]?.type, .image)
        XCTAssertNil(snapshot.atomsByUUID[image.uuid]?.spaceComposition)
        try await SpaceCompositionService.remove(first.uuid, from: space.uuid)
        let remaining = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertNotNil(remaining.atomsByUUID[file.uuid])
        let original = try await fresh(first.uuid)
        XCTAssertFalse(original.isDeleted)
    }

    func testRemovingDirectMembershipDoesNotBreakRemainingGroupReference() async throws {
        let space = try await atom(.thinkspace)
        let group = try await page(in: space, kind: .group)
        let image = try await atom(.image)
        try await SpaceCompositionService.addMembers([image.uuid], to: group.uuid, in: space.uuid)
        try await SpaceCompositionService.remove(image.uuid, from: space.uuid)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.members(of: group.uuid).map(\.uuid), [image.uuid])
        let direct = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertFalse(direct.contains(image.uuid), "The loader must not undo an explicit root removal")
    }

    func testCreatingInsideGroupIsOneUndoOperation() async throws {
        let space = try await atom(.thinkspace)
        let group = try await page(in: space, kind: .group)
        CosmoUndoManager.shared.clearHistory()
        let note = try await SpaceCompositionService.create(title: "Observation", in: space.uuid, groupUUID: group.uuid)
        created.insert(note.uuid)
        let saved = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(saved.members(of: group.uuid).map(\.uuid), [note.uuid])
        XCTAssertEqual(saved.roots.map(\.uuid), [group.uuid])
        await CosmoUndoManager.shared.undo()
        let undone = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertTrue(undone.members(of: group.uuid).isEmpty)
        XCTAssertNil(undone.atomsByUUID[note.uuid])
        XCTAssertFalse(CosmoUndoManager.shared.canUndo)
        await CosmoUndoManager.shared.redo()
        let redone = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(redone.members(of: group.uuid).map(\.uuid), [note.uuid])
    }

    func testPageRetainedInGroupCanStillCreateAndReorderAfterRootRemoval() async throws {
        let space = try await atom(.thinkspace)
        let group = try await page(in: space, kind: .group)
        let work = try await page(in: space)
        try await SpaceCompositionService.addMembers([work.uuid], to: group.uuid, in: space.uuid)
        try await SpaceCompositionService.remove(work.uuid, from: space.uuid)
        let first = try await page(in: space, parent: work), second = try await page(in: space, parent: work)
        try await SpaceCompositionService.reorderChildren(of: work.uuid, in: space.uuid, orderedUUIDs: [second.uuid, first.uuid])
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.children(of: work.uuid).map(\.uuid), [second.uuid, first.uuid])
        let direct = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertFalse(direct.contains(work.uuid))
    }

    func testMovingBelowAnOrphanedPagePreservesItsUsableBranch() async throws {
        let space = try await atom(.thinkspace)
        let orphan = try await page(in: space), incoming = try await page(in: space)
        var edited = try await fresh(orphan.uuid)
        var metadata = try XCTUnwrap(edited.spaceComposition)
        metadata.parentUUID = "unavailable-ancestor"
        edited = try edited.replacingSpaceComposition(metadata)
        _ = try await AtomRepository.shared.update(edited)
        try await SpaceCompositionService.move(incoming.uuid, to: orphan.uuid, in: space.uuid)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.children(of: orphan.uuid).map(\.uuid), [incoming.uuid])
    }

    func testReachableSpaceLookupFindsSourceRetainedByNestedGroupsWithoutWrites() async throws {
        let space = try await atom(.thinkspace)
        let outer = try await page(in: space, kind: .group), inner = try await page(in: space, kind: .group)
        let source = try await page(in: space)
        try await SpaceCompositionService.addMembers([inner.uuid], to: outer.uuid, in: space.uuid)
        try await SpaceCompositionService.addMembers([source.uuid], to: inner.uuid, in: space.uuid)
        try await SpaceCompositionService.remove(inner.uuid, from: space.uuid)
        try await SpaceCompositionService.remove(source.uuid, from: space.uuid)
        let before = try await fresh(space.uuid)
        let reachable = try await SpaceCompositionService.reachableSpaceIDs(containing: source.uuid)
        XCTAssertEqual(reachable, [space.uuid])
        let direct = try await SpaceMembershipService.spaceIDs(containing: source.uuid)
        XCTAssertTrue(direct.isEmpty)
        let after = try await fresh(space.uuid)
        XCTAssertEqual(before.localVersion, after.localVersion)
        XCTAssertEqual(before.metadata, after.metadata)
        try await SpaceCompositionService.removeMembers([inner.uuid], from: outer.uuid)
        let removed = try await SpaceCompositionService.reachableSpaceIDs(containing: source.uuid)
        XCTAssertTrue(removed.isEmpty)
    }

    func testReachableSpaceLookupFindsAuthoredAncestorAndIgnoresDeletedSpaces() async throws {
        let space = try await atom(.thinkspace)
        let book = try await page(in: space, kind: .book), section = try await page(in: space, parent: book)
        let source = try await page(in: space, parent: section)
        try await SpaceCompositionService.remove(section.uuid, from: space.uuid)
        try await SpaceCompositionService.remove(source.uuid, from: space.uuid)
        let reachable = try await SpaceCompositionService.reachableSpaceIDs(containing: source.uuid)
        XCTAssertEqual(reachable, [space.uuid])
        try await AtomRepository.shared.delete(uuid: space.uuid)
        let deleted = try await SpaceCompositionService.reachableSpaceIDs(containing: source.uuid)
        XCTAssertTrue(deleted.isEmpty)
    }

    func testLegacyMigrationPreservesIdentityOriginalMetadataAndCanvas() async throws {
        let image = try await atom(.image)
        let legacyID = UUID()
        let fields: [String: Any] = ["futureField": "keep", "materialGroups": [[
            "id": legacyID.uuidString, "name": "Light", "colorIndex": 2, "itemUUIDs": [image.uuid], "viewMode": "grid"
        ]], "clusters": [["name": "Spatial arrangement", "originX": 170, "originY": 240]]]
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
        let space = try await atom(.thinkspace, metadata: raw)
        let first = try await SpaceCompositionService.load(in: space.uuid)
        created.formUnion(first.atomsByUUID.keys)
        let groupID = try XCTUnwrap(first.legacyGroupMapping[legacyID.uuidString])
        XCTAssertEqual(first.atomsByUUID[groupID]?.title, "Light")
        XCTAssertEqual(first.members(of: groupID).map(\.uuid), [image.uuid])
        XCTAssertEqual(first.metadataByUUID[groupID]?.preferredView, .grid)
        let again = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(again.legacyGroupMapping, first.legacyGroupMapping)
        XCTAssertEqual(again.atomsByUUID.count, first.atomsByUUID.count)
        let saved = try await fresh(space.uuid)
        XCTAssertEqual(saved.metadataDict?["futureField"] as? String, "keep")
        XCTAssertEqual((saved.metadataDict?["materialGroups"] as? [[String: Any]])?.first?["name"] as? String, "Light")
        XCTAssertEqual((saved.metadataDict?["clusters"] as? [[String: Any]])?.first?["originX"] as? Int, 170)
        try await SpaceCompositionService.remove(groupID, from: space.uuid)
        let afterRemoval = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertNil(afterRemoval.atomsByUUID[groupID], "Migration must not resurrect a removed group")
        XCTAssertNotNil(afterRemoval.atomsByUUID[image.uuid])
    }

    func testLegacyIOSStringGroupsMigrateWithStableIdentityAndNoFalseMaterialsError() async throws {
        for key in ["materialGroups", "clusters"] {
            let image = try await atom(.image)
            let memberKey = key == "clusters" ? "blockUUIDs" : "itemUUIDs"
            let canonical = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            let original: [[String: Any]] = [
                ["id": "c1", "name": "Pictures", memberKey: [image.uuid], "viewMode": "grid"],
                ["id": "c2", "name": "Notes", memberKey: [String]()],
                ["id": canonical, "name": "Canonical", memberKey: [String]()]
            ]
            var draft = Atom.new(type: .thinkspace, title: "Legacy iOS", metadata: String(decoding:
                try JSONSerialization.data(withJSONObject: [key: original, "future": "keep"]), as: UTF8.self))
            draft.uuid = key == "materialGroups" ? "11111111-1111-1111-1111-111111111111" : "11111111-1111-1111-1111-111111111112"
            let space = try await AtomRepository.shared.create(draft); created.insert(space.uuid)
            let snapshot = try await SpaceCompositionService.load(in: space.uuid)
            created.formUnion(snapshot.atomsByUUID.keys)
            let groupID = try XCTUnwrap(snapshot.legacyGroupMapping["c1"])
            if key == "materialGroups" {
                XCTAssertEqual(groupID, "CC880C5A-E729-5B52-B229-C679571EDA8E")
                XCTAssertEqual(snapshot.legacyGroupMapping["c2"], "77EFBCD5-5E5B-5D8A-BFAF-D3799DAA929F")
            }
            XCTAssertNotNil(snapshot.legacyGroupMapping[canonical.uppercased()])
            XCTAssertEqual(snapshot.members(of: groupID).map(\.uuid), [image.uuid])
            XCTAssertEqual(snapshot.metadataByUUID[groupID]?.preferredView, .grid)
            let again = try await SpaceCompositionService.load(in: space.uuid)
            XCTAssertEqual(again.legacyGroupMapping, snapshot.legacyGroupMapping)
            XCTAssertEqual(again.atomsByUUID.count, snapshot.atomsByUUID.count)
            let saved = try await fresh(space.uuid)
            XCTAssertTrue(NSArray(array: try XCTUnwrap(saved.metadataDict?[key] as? [[String: Any]])).isEqual(to: original))
            XCTAssertEqual(saved.metadataDict?["future"] as? String, "keep")
            let oldReader = SpaceMaterialsStore()
            await oldReader.load(spaceID: space.uuid)
            XCTAssertNil(oldReader.errorMessage)
            XCTAssertTrue(oldReader.groups.isEmpty)
        }
    }

    func testLegacyMigrationFailureDoesNotCommitPartialGroups() async throws {
        let valid = UUID().uuidString
        let metadata = #"{"materialGroups":[{"id":"\#(valid)","name":"Keep","colorIndex":0,"itemUUIDs":[]},{"id":"broken","name":"Bad","colorIndex":0,"itemUUIDs":42}]}"#
        let space = try await atom(.thinkspace, metadata: metadata)
        do {
            _ = try await SpaceCompositionService.load(in: space.uuid)
            XCTFail("Malformed legacy data must leave migration pending")
        } catch {}
        let saved = try await fresh(space.uuid)
        XCTAssertEqual(saved.metadata, metadata)
        let members = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertTrue(members.isEmpty)
    }

    func testGroupCyclesAndPartialBatchFailuresDoNotLeakMembership() async throws {
        let space = try await atom(.thinkspace)
        let outer = try await page(in: space, kind: .group), inner = try await page(in: space, kind: .group)
        let image = try await atom(.image)
        try await SpaceCompositionService.addMembers([inner.uuid], to: outer.uuid, in: space.uuid)
        do {
            try await SpaceCompositionService.addMembers([outer.uuid], to: inner.uuid, in: space.uuid)
            XCTFail("Group cycle must be rejected")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .cycle) }
        do {
            try await SpaceCompositionService.addMembers([image.uuid, "missing-source"], to: inner.uuid, in: space.uuid)
            XCTFail("The batch must fail atomically")
        } catch {}
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertTrue(snapshot.members(of: inner.uuid).isEmpty)
        XCTAssertNil(snapshot.atomsByUUID[image.uuid])
    }

    func testBookAndCourseStartersAreEditableOrdinaryPagesWithPrivatePlanning() async throws {
        let space = try await atom(.thinkspace)
        let book = try await starter(.book, in: space), course = try await starter(.course, in: space)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(snapshot.orderedSections(of: book.uuid).compactMap { $0.atom.title }, ["Untitled book", "Introduction", "Chapter 1", "Chapter 2"])
        let courseSections = snapshot.orderedSections(of: course.uuid)
        XCTAssertTrue(courseSections.contains { $0.atom.title == "Lesson 1" && $0.depth == 2 })
        XCTAssertTrue(courseSections.contains { $0.atom.body?.contains("Learning outcome") == true })
        XCTAssertFalse(courseSections.contains { $0.atom.title == "Recording notes" })
        XCTAssertTrue(snapshot.atomsByUUID.values.allSatisfy { $0.type == .note })
        let spaceAfter = try await fresh(space.uuid)
        XCTAssertNil(spaceAfter.spaceComposition)
    }

    func testAdaptationCopiesRichWritingAndRetainsIndependentProvenance() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space, kind: .book)
        let child = try await page(in: space, parent: root)
        var original = try await fresh(child.uuid)
        original.body = "Original wording"
        original.structured = #"{"rich":"payload"}"#
        original = original.mergingMetadataKeys(["bodyDocument": "exact-rich-document"])
        _ = try await AtomRepository.shared.update(original)
        let adapted = try await SpaceCompositionService.adapt(root.uuid, title: "Course", kind: .course, in: space.uuid)
        let snapshot = try await SpaceCompositionService.load(in: space.uuid)
        created.formUnion(snapshot.atomsByUUID.keys)
        let copy = try XCTUnwrap(snapshot.children(of: adapted.uuid).first)
        XCTAssertNotEqual(copy.uuid, child.uuid)
        XCTAssertEqual(copy.body, "Original wording")
        XCTAssertEqual(copy.structured, original.structured)
        XCTAssertEqual(copy.metadataDict?["bodyDocument"] as? String, "exact-rich-document")
        XCTAssertEqual(copy.spaceComposition?.origin?.sourceUUID, child.uuid)
        var changed = copy
        changed.body = "Adapted for learners"
        _ = try await AtomRepository.shared.update(changed)
        let unchanged = try await fresh(child.uuid)
        XCTAssertEqual(unchanged.body, "Original wording")
    }

    func testReferenceExcerptSurvivesMissingSourceAndCanBeAnnotated() async throws {
        let space = try await atom(.thinkspace)
        let page = try await page(in: space)
        let source = try await atom(.research, title: "Original interview")
        var reference = SpaceCompositionReference(sourceUUID: source.uuid, excerpt: "Preserve this quote", anchor: .init(timeSeconds: 42))
        try await SpaceCompositionService.attachReference(reference, to: page.uuid)
        try await AtomRepository.shared.delete(uuid: source.uuid)
        reference.annotation = "A useful counterexample"
        try await SpaceCompositionService.updateReference(reference, in: page.uuid)
        let saved = try await fresh(page.uuid)
        XCTAssertEqual(saved.spaceComposition?.references.first?.excerpt, "Preserve this quote")
        XCTAssertEqual(saved.spaceComposition?.references.first?.annotation, "A useful counterexample")
        XCTAssertEqual(saved.spaceComposition?.references.first?.sourceTitle, "Original interview")
        try await SpaceCompositionService.removeReference(reference.id, from: page.uuid)
        let after = try await fresh(page.uuid)
        XCTAssertTrue(after.spaceComposition?.references.isEmpty == true)
    }

    func testReferenceBatchIsAtomicAndUndoesTogether() async throws {
        let space = try await atom(.thinkspace), page = try await page(in: space)
        let one = try await atom(.research), two = try await atom(.file)
        let references: [SpaceCompositionReference] = [.init(sourceUUID: one.uuid), .init(sourceUUID: two.uuid)]
        do {
            try await SpaceCompositionService.attachReferences([references[0], .init(sourceUUID: "missing")], to: page.uuid)
            XCTFail("An unavailable batch member must roll back the entire attachment")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .notFound) }
        let before = try await fresh(page.uuid)
        XCTAssertTrue(before.spaceComposition?.references.isEmpty == true)
        CosmoUndoManager.shared.clearHistory()
        try await SpaceCompositionService.attachReferences(references, to: page.uuid)
        let saved = try await fresh(page.uuid)
        XCTAssertEqual(saved.spaceComposition?.references.count, 2)
        await CosmoUndoManager.shared.undo()
        let undone = try await fresh(page.uuid)
        XCTAssertTrue(undone.spaceComposition?.references.isEmpty == true)
        XCTAssertFalse(CosmoUndoManager.shared.canUndo)
        await CosmoUndoManager.shared.redo()
        let redone = try await fresh(page.uuid)
        XCTAssertEqual(redone.spaceComposition?.references.count, 2)
    }

    func testUndoReorderPreservesLaterWritingAndRedoRestoresOrder() async throws {
        let space = try await atom(.thinkspace)
        let root = try await page(in: space), a = try await page(in: space, parent: root), b = try await page(in: space, parent: root)
        CosmoUndoManager.shared.clearHistory()
        try await SpaceCompositionService.reorderChildren(of: root.uuid, in: space.uuid, orderedUUIDs: [b.uuid, a.uuid])
        var writing = try await fresh(a.uuid)
        writing.body = "Writing after the structural change"
        _ = try await AtomRepository.shared.update(writing)
        await CosmoUndoManager.shared.undo()
        let undone = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(undone.children(of: root.uuid).map(\.uuid), [a.uuid, b.uuid])
        XCTAssertEqual(undone.atomsByUUID[a.uuid]?.body, writing.body)
        await CosmoUndoManager.shared.redo()
        let redone = try await SpaceCompositionService.load(in: space.uuid)
        XCTAssertEqual(redone.children(of: root.uuid).map(\.uuid), [b.uuid, a.uuid])
    }

    func testFutureVersionMutationIsRejectedWithoutMetadataLoss() async throws {
        let raw = #"{"bodyDocument":"keep","spaceComposition":{"schemaVersion":25,"kind":"page","futureFeature":true}}"#
        let page = try await atom(.note, metadata: raw)
        do {
            try await SpaceCompositionService.setIncludedInExport(false, for: page.uuid)
            XCTFail("Future versions must remain read-only")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .unsupportedVersion(25)) }
        let after = try await fresh(page.uuid)
        XCTAssertEqual(after.metadata, raw)
    }
}
