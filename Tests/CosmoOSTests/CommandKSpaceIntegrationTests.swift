import XCTest
@testable import CosmoOS

@MainActor
final class CommandKSpaceIntegrationTests: XCTestCase {
    func testPickerBasketIsIndependentFromPreviewAndPersistsAcrossQueries() {
        let model = CommandKViewModel()
        defer { model.clear(); model.setSurfaceActive(false) }
        let request = CommandKPickerRequest(spaceID: "captured-space", targetUUID: "captured-group", purpose: .addOriginals)
        model.selectionPicker = .init(request: request,
            destination: .init(spaceID: request.spaceID, spaceTitle: "Studio", containerUUID: request.targetUUID,
                containerTitle: "Sources", containerKind: .group), includedUUIDs: ["already"], isLoading: false)
        model.cortexMode = .expandedDomain(.database)
        model.expandedDomainOpenTargets = ["one": .atom("one"), "two": .atom("two")]
        model.selectedNodeId = "one"
        XCTAssertEqual(model.selectionPicker?.selection, [])
        model.openSelected()
        XCTAssertEqual(model.selectionPicker?.selection, ["one"])
        model.selectedNodeId = "two"
        XCTAssertEqual(model.selectionPicker?.selection, ["one"])
        model.openSelected()
        model.togglePickerSelection("already")
        model.togglePickerSelection("captured-group")
        model.togglePickerSelection("captured-space")
        XCTAssertEqual(model.selectionPicker?.selection, ["one", "two"])
        model.updateQuery("task: this must stay a search")
        XCTAssertFalse(model.isTaskCreationMode)
        model.updateQuery("different query")
        model.selectionPicker?.scope = .thisSpace
        model.captureSpaceContext(.init(spaceID: "other", spaceTitle: "Other Space"))
        XCTAssertEqual(model.selectionPicker?.request.spaceID, "captured-space")
        XCTAssertEqual(model.selectionPicker?.request.targetUUID, "captured-group")
        XCTAssertEqual(model.selectionPicker?.selection, ["one", "two"])
        model.togglePickerSelection("one")
        model.togglePickerSelection("one")
        XCTAssertEqual(model.selectionPicker?.selection, ["two", "one"])
    }

    func testClearDiscardsPickerScopeBasketAndCreationSuppression() {
        let model = CommandKViewModel()
        defer { model.setSurfaceActive(false) }
        model.selectionPicker = .init(request: .init(spaceID: "space", targetUUID: nil, purpose: .addOriginals),
            scope: .thisSpace, selection: ["original"], isLoading: false)
        model.initialExpandedTab = .database
        model.cortexMode = .expandedDomain(.database)
        model.clear()
        XCTAssertNil(model.selectionPicker)
        XCTAssertNil(model.initialExpandedTab)
        XCTAssertNil(model.spaceContext)
        XCTAssertEqual(model.cortexMode, .compact)
        model.updateQuery("task: Task")
        XCTAssertTrue(model.isTaskCreationMode)
        model.clear()
    }

    func testDeleteIsLastAfterDomainAndSpaceActionsInEveryMenuOrder() {
        let source = RecentDisplayItem(id: "source", title: "Source", type: .research, entityId: 1,
            relativeDate: "now", thumbnailURL: nil, preview: nil)
        let context = CommandKActionContext(query: "source", subject: .recent(source), hydratedAtom: nil,
            mode: .expandedDomain(.swipeGallery), activeInquirySessionUUID: "inquiry", activeContentDraftUUID: "draft",
            spaceContext: .init(spaceID: "space", spaceTitle: "Studio"))
        let registry = CommandKActionRegistry()
        let actions = registry.actions(for: context)
        XCTAssertEqual(actions.last?.id, .deleteObject)
        XCTAssertTrue(actions.contains { $0.id == .openSpaceMap })
        XCTAssertTrue(actions.contains { $0.id == .openSwipeGallery })
        XCTAssertEqual(registry.groupedActions(for: context).last?.category, .destructive)
        XCTAssertEqual(registry.groupedActions(for: context).flatMap(\.actions).last?.id, .deleteObject)
        let shuffled = actions.reversed()
        let ordered = CommandKActionRegistry.orderedActions(Array(shuffled))
        XCTAssertEqual(ordered.last?.id, .deleteObject)
        XCTAssertEqual(ordered.filter { $0.role != .destructive }.map(\.uniqueActionId),
            shuffled.filter { $0.role != .destructive }.map(\.uniqueActionId))
    }

    func testCompositionAndSpaceMapCommandsUseExistingParser() throws {
        let cases: [(String, CommandKActionKind)] = [
            ("page: Introduction", .createNote), ("new group Sources", .createGroup),
            ("new book Field guide", .createBook), ("course: Design", .createCourse),
            ("new space Studio", .createThinkspace), ("space map", .openSpaceMap)
        ]
        for (query, kind) in cases { XCTAssertEqual(CommandKActionParser.parse(query)?.kind, kind, query) }
    }

    func testPageDraftPreservesEditedDestinationAndWritingAcrossQueryUpdates() throws {
        let model = CommandKViewModel()
        defer { model.setSurfaceActive(false) }
        let origin = CommandKSpaceContext(spaceID: "a", spaceTitle: "Studio", containerUUID: "book",
            containerTitle: "Field guide", containerKind: .book, path: ["Field guide"])
        model.captureSpaceContext(origin)
        let first = try XCTUnwrap(CommandKActionParser.parse("new page Intro"))
        model.ensureComposerDraft(for: first)
        XCTAssertEqual(model.composerDraft?.destination, origin)
        model.composerDraft?.form.setValue("My title", for: .title)
        model.composerDraft?.form.setValue("Keep this writing", for: .body)
        model.composerDraft?.titleEditedManually = true
        let chosen = CommandKSpaceContext(spaceID: "b", spaceTitle: "Other Space")
        model.composerDraft?.destination = chosen
        model.ensureComposerDraft(for: try XCTUnwrap(CommandKActionParser.parse("new page Different query")))
        XCTAssertEqual(model.composerDraft?.form.value(for: .title), "My title")
        XCTAssertEqual(model.composerDraft?.form.value(for: .body), "Keep this writing")
        XCTAssertEqual(model.composerDraft?.destination, chosen)
        XCTAssertEqual(model.spaceContext, origin)
    }

    func testStartersRequireSpaceWhileFreeStandingPageIsValid() throws {
        var book = try XCTUnwrap(CommandKComposerDraft.draft(for: try XCTUnwrap(CommandKActionParser.parse("new book Atlas"))))
        XCTAssertFalse(book.validation.isValid)
        book.destination = .init(spaceID: "a", spaceTitle: "Studio")
        XCTAssertTrue(book.validation.isValid)
        let page = try XCTUnwrap(CommandKComposerDraft.draft(for: try XCTUnwrap(CommandKActionParser.parse("new page Intro"))))
        XCTAssertTrue(page.validation.isValid)
    }

    func testRegistryUsesCapturedDestinationAndOriginalSelection() throws {
        let page = RecentDisplayItem(id: "source", title: "Source", type: .note, entityId: 7,
            relativeDate: "now", thumbnailURL: nil, preview: nil)
        let destination = CommandKSpaceContext(spaceID: "space", spaceTitle: "Studio", containerUUID: "book",
            containerTitle: "Atlas", containerKind: .book)
        let context = CommandKActionContext(query: "source", subject: .recent(page), hydratedAtom: nil,
            mode: .searchResults, activeInquirySessionUUID: nil, activeContentDraftUUID: nil,
            spaceContext: destination, selectedUUIDs: ["source", "other"])
        let actions = CommandKActionRegistry().actions(for: context)
        let add = try XCTUnwrap(actions.first { $0.id == .addToComposition })
        XCTAssertEqual(add.title, "Attach as source to Atlas")
        XCTAssertEqual(add.shortcut, .optionReturn)
        XCTAssertEqual(add.intent, .addOriginals(uuids: ["other", "source"], destination: destination))
        XCTAssertTrue(actions.contains { $0.id == .addToSpace })
        XCTAssertFalse(actions.contains { $0.id == .addToCanvas })
    }

    func testBreadcrumbPrefersAuthoredHierarchyInsideOverlappingGroup() throws {
        var group = Atom.new(type: .note, title: "Collection"); group.uuid = "group"
        var metadata = SpaceCompositionMetadata(kind: .group); metadata.memberUUIDs = ["book", "page"]
        group = try group.replacingSpaceComposition(metadata)
        var book = Atom.new(type: .note, title: "Book"); book.uuid = "book"
        book = try book.replacingSpaceComposition(.init(kind: .book))
        var page = Atom.new(type: .note, title: "Page"); page.uuid = "page"
        page = try page.replacingSpaceComposition(.init(parentUUID: book.uuid))
        let snapshot = try SpaceCompositionSnapshot(spaceID: "space", atoms: [page, group, book])
        XCTAssertEqual(CommandKSpaceService.navigationPath(to: page.uuid, in: snapshot).map(\.uuid), ["group", "book", "page"])
    }
}

@MainActor
final class CommandKSpaceMutationTests: XCTestCase {
    private var created = Set<String>()

    override func tearDown() async throws {
        CosmoUndoManager.shared.clearHistory()
        for uuid in created { try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true) }
        created.removeAll()
        try await super.tearDown()
    }

    private func atom(_ type: AtomType, title: String = "Command-K fixture") async throws -> Atom {
        let atom = try await AtomRepository.shared.create(Atom.new(type: type, title: title, body: "Original writing"))
        created.insert(atom.uuid)
        return atom
    }

    private func composition(_ kind: SpaceCompositionKind, in space: Atom) async throws -> Atom {
        let atom = try await SpaceCompositionService.create(kind: kind, title: kind.title, in: space.uuid)
        created.insert(atom.uuid)
        return atom
    }

    func testPickerLoadsExistingMembersAndReferencesWithoutChangingOriginals() async throws {
        let space = try await atom(.thinkspace), source = try await atom(.image)
        let group = try await composition(.group, in: space), page = try await composition(.page, in: space)
        try await SpaceCompositionService.addMembers([source.uuid], to: group.uuid, in: space.uuid)
        try await SpaceCompositionService.attachReferences([.init(sourceUUID: source.uuid, annotation: "Keep annotation")],
            to: page.uuid, in: space.uuid, expectedKind: .page)
        let grouped = try await CommandKSelectionPickerService.load(.init(spaceID: space.uuid,
            targetUUID: group.uuid, purpose: .addOriginals))
        XCTAssertTrue(grouped.includedUUIDs.contains(source.uuid))
        let referenced = try await CommandKSelectionPickerService.load(.init(spaceID: space.uuid,
            targetUUID: page.uuid, purpose: .attachReferences))
        XCTAssertTrue(referenced.includedUUIDs.contains(source.uuid))
        let canvas = try await CommandKSelectionPickerService.load(.init(spaceID: space.uuid,
            targetUUID: group.uuid, purpose: .placeOnCanvas, onConfirm: { _ in }))
        XCTAssertFalse(canvas.includedUUIDs.contains(source.uuid), "Unplaced members must remain available for canvas placement")
        let saved = try await AtomRepository.shared.fetch(uuid: page.uuid)
        XCTAssertEqual(saved?.spaceComposition?.references.first?.annotation, "Keep annotation")
    }

    func testPickerBrowseIncludesNativeStickyNotesFilesAndQuestions() async throws {
        let sticky = try await atom(.stickyNote), file = try await atom(.file), question = try await atom(.question)
        let model = LibraryViewModel()
        await model.loadLibrary(includingAllOriginals: true)
        let wanted: Set<String> = [sticky.uuid, file.uuid, question.uuid]
        let originals = model.allItems.filter { wanted.contains($0.uuid) }
        XCTAssertEqual(Set(originals.map(\.uuid)), wanted)
        XCTAssertEqual(Set(originals.map(\.atomType)), [.stickyNote, .file, .question])
        XCTAssertTrue(originals.allSatisfy { $0.preview == "Original writing" })
    }

    func testPickerSaveFailureKeepsBasketAndDoesNotReportCompletion() async throws {
        enum ExpectedFailure: LocalizedError {
            case save
            var errorDescription: String? { "Could not save this selection" }
        }
        let space = try await atom(.thinkspace), source = try await atom(.image)
        var completed = false
        let request = CommandKPickerRequest(spaceID: space.uuid, targetUUID: nil, purpose: .addOriginals,
            onConfirm: { _ in throw ExpectedFailure.save }, onComplete: { completed = true })
        let loaded = try await CommandKSelectionPickerService.load(request)
        let model = CommandKViewModel()
        defer { model.clear(); model.setSurfaceActive(false) }
        model.selectionPicker = .init(request: request, destination: loaded.destination,
            selection: [source.uuid], isLoading: false)
        model.confirmPickerSelection()
        await model.selectionPickerTask?.value
        XCTAssertFalse(completed)
        XCTAssertEqual(model.selectionPicker?.selection, [source.uuid])
        XCTAssertEqual(model.selectionPicker?.error, "Could not save this selection")
        XCTAssertEqual(model.selectionPicker?.isConfirming, false)
        let members = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertTrue(members.isEmpty)
    }

    func testPickerRevalidatesDeletedDestinationBeforeInvokingCallback() async throws {
        let space = try await atom(.thinkspace), source = try await atom(.image)
        let page = try await composition(.page, in: space)
        var invoked = false
        let request = CommandKPickerRequest(spaceID: space.uuid, targetUUID: page.uuid, purpose: .attachReferences,
            onConfirm: { _ in invoked = true })
        let loaded = try await CommandKSelectionPickerService.load(request)
        let model = CommandKViewModel()
        defer { model.clear(); model.setSurfaceActive(false) }
        model.selectionPicker = .init(request: request, destination: loaded.destination,
            selection: [source.uuid], isLoading: false)
        try await AtomRepository.shared.delete(uuid: page.uuid)
        model.confirmPickerSelection()
        await model.selectionPickerTask?.value
        XCTAssertFalse(invoked)
        XCTAssertEqual(model.selectionPicker?.selection, [source.uuid])
        XCTAssertNotNil(model.selectionPicker?.error)
        XCTAssertEqual(model.selectionPicker?.isConfirming, false)
    }

    func testAddingBatchPreservesOtherSpaceAndUndoOnlyRemovesAddedMembership() async throws {
        let first = try await atom(.thinkspace), second = try await atom(.thinkspace)
        let source = try await atom(.note), image = try await atom(.image)
        try await SpaceCompositionService.addOriginals([source.uuid], in: first.uuid)
        CosmoUndoManager.shared.clearHistory()
        try await SpaceCompositionService.addOriginals([source.uuid, image.uuid, source.uuid], in: second.uuid)
        let firstIDs = try await SpaceMembershipService.memberUUIDs(in: first.uuid)
        let secondIDs = try await SpaceMembershipService.memberUUIDs(in: second.uuid)
        XCTAssertEqual(firstIDs, [source.uuid])
        XCTAssertEqual(secondIDs, [source.uuid, image.uuid])
        await CosmoUndoManager.shared.undo()
        let remainingFirst = try await SpaceMembershipService.memberUUIDs(in: first.uuid)
        let remainingSecond = try await SpaceMembershipService.memberUUIDs(in: second.uuid)
        let original = try await AtomRepository.shared.fetch(uuid: source.uuid)
        XCTAssertEqual(remainingFirst, [source.uuid])
        XCTAssertTrue(remainingSecond.isEmpty)
        XCTAssertEqual(original?.body, "Original writing")
        XCTAssertEqual(original?.isDeleted, false)
    }

    func testInvalidMemberRollsBackEntireBatch() async throws {
        let space = try await atom(.thinkspace), original = try await atom(.image)
        do {
            try await SpaceCompositionService.addOriginals([original.uuid, "missing-original"], in: space.uuid)
            XCTFail("Missing original should reject the whole add")
        } catch { }
        let ids = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertTrue(ids.isEmpty)
        do {
            try await SpaceCompositionService.addOriginals([original.uuid, space.uuid], in: space.uuid)
            XCTFail("A Space must not be filed into itself")
        } catch { }
        let afterSelf = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertTrue(afterSelf.isEmpty)
    }

    func testAuthoredAddPreservesAnnotatedReferenceWithoutFilingOriginal() async throws {
        let space = try await atom(.thinkspace), original = try await atom(.image)
        let page = try await composition(.page, in: space)
        let destination = CommandKSpaceContext(spaceID: space.uuid, spaceTitle: "Studio",
            containerUUID: page.uuid, containerTitle: "Page", containerKind: .page)
        try await CommandKSpaceService.addOriginals([original.uuid], to: destination)
        var reference = SpaceCompositionReference(id: "source:\(page.uuid):\(original.uuid)", sourceUUID: original.uuid,
            excerpt: "A passage worth keeping", anchor: .init(pageIndex: 4), annotation: "Keep my annotation")
        reference.sourceTitle = original.title
        try await SpaceCompositionService.updateReference(reference, in: page.uuid)
        try await CommandKSpaceService.addOriginals([original.uuid], to: destination)
        let saved = try await AtomRepository.shared.fetch(uuid: page.uuid)
        XCTAssertEqual(saved?.spaceComposition?.references, [reference])
        let ids = try await SpaceMembershipService.memberUUIDs(in: space.uuid)
        XCTAssertFalse(ids.contains(original.uuid))

        let group = try await composition(.group, in: space)
        try await CommandKSpaceService.addOriginals([original.uuid], to: .init(spaceID: space.uuid,
            spaceTitle: "Studio", containerUUID: group.uuid, containerTitle: "Group", containerKind: .group))
        let grouped = try await AtomRepository.shared.fetch(uuid: group.uuid)
        XCTAssertEqual(grouped?.spaceComposition?.memberUUIDs, [original.uuid])
        XCTAssertEqual(grouped?.spaceComposition?.references, [])
    }

    func testReferenceWriterRejectsChangedDestinationKindAtomically() async throws {
        let space = try await atom(.thinkspace), original = try await atom(.image)
        let group = try await composition(.group, in: space)
        do {
            try await SpaceCompositionService.attachReferences([.init(sourceUUID: original.uuid)], to: group.uuid,
                in: space.uuid, expectedKind: .page)
            XCTFail("A stale Page destination must not write into a Group")
        } catch { XCTAssertEqual(error as? SpaceCompositionError, .invalidKind) }
        let saved = try await AtomRepository.shared.fetch(uuid: group.uuid)
        XCTAssertEqual(saved?.spaceComposition?.references, [])
    }
}
