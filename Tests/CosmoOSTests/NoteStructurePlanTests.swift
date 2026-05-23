import XCTest
@testable import CosmoOS

final class NoteStructurePlanTests: XCTestCase {
    func testModuleExtractsExactTextFromUTF16Range() throws {
        let body = "Intro\n\nModule one 💡\nLine two.\n\nModule two"
        let nsBody = body as NSString
        let exact = "Module one 💡\nLine two."
        let range = nsBody.range(of: exact)

        let module = NoteStructureModuleProposal(
            id: UUID(),
            clusterID: UUID(),
            title: "Module one",
            startUTF16Offset: range.location,
            lengthUTF16: range.length,
            position: CGPoint(x: 100, y: 100),
            size: CanvasBlock.documentLayoutSize
        )

        XCTAssertEqual(try module.copiedText(in: body), exact)
    }

    func testPlanValidationFailsWhenSourceHashChanges() throws {
        let noteID = UUID()
        let targetID = UUID()
        let snapshot = NoteStructureSourceSnapshot(sourceNoteUUID: noteID, sourceTitle: "Plan", body: "One\n\nTwo")
        let changed = NoteStructureSourceSnapshot(sourceNoteUUID: noteID, sourceTitle: "Plan", body: "One\n\nTwo\n\nThree")

        let clusterID = UUID()
        let moduleID = UUID()
        let plan = PendingNoteStructurePlan(
            title: "Structure note",
            rationale: "Split major concepts.",
            sourceNoteUUID: noteID,
            sourceTitle: "Plan",
            sourceBodyHash: snapshot.bodyHash,
            targetThinkspaceUUID: targetID,
            keepOriginalVisible: true,
            clusters: [
                NoteStructureClusterProposal(
                    id: clusterID,
                    name: "Core",
                    colorIndex: 0,
                    frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                    moduleIDs: [moduleID]
                )
            ],
            modules: [
                NoteStructureModuleProposal(
                    id: moduleID,
                    clusterID: clusterID,
                    title: "One",
                    startUTF16Offset: 0,
                    lengthUTF16: 3,
                    position: CGPoint(x: 80, y: 80),
                    size: CanvasBlock.documentLayoutSize
                )
            ]
        )

        XCTAssertThrowsError(try plan.validate(against: changed)) { error in
            guard case NoteStructurePlanError.sourceHashMismatch = error else {
                return XCTFail("Expected sourceHashMismatch")
            }
        }
    }

    func testOriginalNoteRemainsVisibleByDefault() throws {
        let snapshot = NoteStructureSourceSnapshot(sourceNoteUUID: UUID(), sourceTitle: "Long note", body: "A module")
        let clusterID = UUID()
        let moduleID = UUID()
        let plan = PendingNoteStructurePlan(
            title: "Structure note",
            rationale: "Create clusters.",
            sourceNoteUUID: snapshot.sourceNoteUUID,
            sourceTitle: snapshot.sourceTitle,
            sourceBodyHash: snapshot.bodyHash,
            targetThinkspaceUUID: UUID(),
            keepOriginalVisible: true,
            clusters: [
                NoteStructureClusterProposal(
                    id: clusterID,
                    name: "A",
                    colorIndex: 0,
                    frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                    moduleIDs: [moduleID]
                )
            ],
            modules: [
                NoteStructureModuleProposal(
                    id: moduleID,
                    clusterID: clusterID,
                    title: "A module",
                    startUTF16Offset: 0,
                    lengthUTF16: 8,
                    position: CGPoint(x: 80, y: 80),
                    size: CanvasBlock.documentLayoutSize
                )
            ]
        )

        XCTAssertTrue(plan.keepOriginalVisible)
        XCTAssertNoThrow(try plan.validate(against: snapshot))
    }

    @MainActor
    func testCanvasSpatialToolsIncludeNoteStructurePlan() {
        let tools = AgentToolRegistry.shared.tools(forBundles: [.canvasSpatial])
        XCTAssertTrue(tools.contains { $0.name == "propose_note_structure_plan" })
    }

    @MainActor
    func testExecutorParsesNoteStructurePlanAndKeepsOriginalVisibleByDefault() async throws {
        let executor = AgentToolExecutor.shared
        let expectation = XCTestExpectation(description: "Plan callback")
        var received: PendingNoteStructurePlan?
        executor.onNoteStructurePlan = { plan in
            received = plan
            expectation.fulfill()
        }
        defer { executor.onNoteStructurePlan = nil }

        let sourceID = UUID()
        let targetID = UUID()
        let clusterID = UUID()
        let moduleID = UUID()

        _ = try await executor.execute(
            toolName: "propose_note_structure_plan",
            arguments: [
                "title": "Structure note",
                "rationale": "Split concepts.",
                "sourceNoteUUID": sourceID.uuidString,
                "sourceTitle": "Long note",
                "sourceBodyHash": "abc123",
                "targetThinkspaceUUID": targetID.uuidString,
                "clusters": [[
                    "id": clusterID.uuidString,
                    "name": "Core",
                    "colorIndex": 1,
                    "x": 0,
                    "y": 0,
                    "width": 900,
                    "height": 700,
                    "moduleIDs": [moduleID.uuidString]
                ]],
                "modules": [[
                    "id": moduleID.uuidString,
                    "clusterID": clusterID.uuidString,
                    "title": "Module",
                    "startUTF16Offset": 0,
                    "lengthUTF16": 10,
                    "x": 80,
                    "y": 80
                ]]
            ]
        )

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(received?.sourceNoteUUID, sourceID)
        XCTAssertEqual(received?.targetThinkspaceUUID, targetID)
        XCTAssertEqual(received?.keepOriginalVisible, true)
    }

    @MainActor
    func testNoteContextProviderIncludesFullNoteBodyForStructurePlanning() {
        let body = "## Voice\nExact wording.\n\n## System\nMore exact wording."
        let atom = Atom.new(type: .note, title: "Personal brand plan", body: body)
        let provider = NoteContextProvider(
            atom: atom,
            titleRef: { "Personal brand plan" },
            contentRef: { body },
            tagsRef: { [] }
        )

        let contextData = provider.contextData

        XCTAssertEqual(contextData.viewSpecificData["noteBody"], body)
        XCTAssertTrue(contextData.toContextBlock().contains("noteBody: \(body)"))
    }

    @MainActor
    func testActiveNoteStructureSnapshotUsesFullNoteBody() {
        let viewModel = CosmoWindowViewModel.shared
        let body = "## Voice\nExact wording."
        let provider = NoteStructureTestContextProvider(
            atomUUID: UUID().uuidString,
            title: "Personal brand plan",
            body: body,
            targetThinkspaceUUID: UUID().uuidString
        )

        viewModel.updateContext(provider: provider)
        let snapshot = viewModel.activeNoteStructureSnapshot()

        XCTAssertEqual(snapshot?.body, body)
        XCTAssertEqual(snapshot?.bodyHash, NoteStructureSourceSnapshot.hashBody(body))
    }

    @MainActor
    func testCanvasContextProviderExposesCurrentThinkspaceUUIDForStructurePlanning() {
        let targetID = UUID()
        let spatialEngine = SpatialEngine()
        spatialEngine.currentThinkspaceId = targetID.uuidString

        let provider = CanvasContextProvider(
            spatialEngine: spatialEngine,
            thinkspaceId: targetID.uuidString
        )
        let contextData = provider.contextData

        XCTAssertEqual(contextData.currentAtomUUID, targetID.uuidString)
        XCTAssertEqual(contextData.currentAtomType, "thinkspace")
        XCTAssertEqual(contextData.viewSpecificData["currentThinkspaceUUID"], targetID.uuidString)
        XCTAssertEqual(contextData.viewSpecificData["targetThinkspaceUUID"], targetID.uuidString)
    }

    @MainActor
    func testActiveNoteStructureSnapshotUsesMentionedNoteInsideThinkspace() {
        let viewModel = CosmoWindowViewModel.shared
        viewModel.clearMentions()
        defer {
            viewModel.clearMentions()
            viewModel.clearContext()
        }

        let targetID = UUID()
        let sourceBody = "Module A\n\nModule B"
        let sourceNote = Atom.new(type: .note, title: "Course knowledge", body: sourceBody)
        let spatialEngine = SpatialEngine()
        spatialEngine.currentThinkspaceId = targetID.uuidString
        let provider = CanvasContextProvider(
            spatialEngine: spatialEngine,
            thinkspaceId: targetID.uuidString
        )

        viewModel.updateContext(provider: provider)
        viewModel.addMention(sourceNote)

        let snapshot = viewModel.activeNoteStructureSnapshot()

        XCTAssertEqual(snapshot?.sourceNoteUUID.uuidString, sourceNote.uuid)
        XCTAssertEqual(snapshot?.sourceTitle, "Course knowledge")
        XCTAssertEqual(snapshot?.body, sourceBody)
        XCTAssertEqual(viewModel.resolvedTargetThinkspaceForNoteStructure(), targetID)
    }

    @MainActor
    func testReceivedNoteStructurePlanUsesSnapshotCapturedBeforeMentionsClear() {
        let viewModel = CosmoWindowViewModel.shared
        viewModel.clearMentions()
        defer {
            viewModel.cancelPendingNoteStructurePlan()
            viewModel.clearMentions()
            viewModel.clearContext()
        }

        let targetID = UUID()
        let sourceBody = "Module A\n\nModule B"
        let sourceNote = Atom.new(type: .note, title: "Course knowledge", body: sourceBody)
        let sourceID = UUID(uuidString: sourceNote.uuid)!
        let spatialEngine = SpatialEngine()
        spatialEngine.currentThinkspaceId = targetID.uuidString
        let provider = CanvasContextProvider(
            spatialEngine: spatialEngine,
            thinkspaceId: targetID.uuidString
        )

        viewModel.updateContext(provider: provider)
        viewModel.addMention(sourceNote)
        let capturedSnapshot = viewModel.activeNoteStructureSnapshot()
        XCTAssertNotNil(capturedSnapshot)

        viewModel.clearMentions()
        XCTAssertNil(viewModel.activeNoteStructureSnapshot())

        let clusterID = UUID()
        let moduleID = UUID()
        let plan = PendingNoteStructurePlan(
            title: "Structure course knowledge",
            rationale: "Split modules.",
            sourceNoteUUID: sourceID,
            sourceTitle: "Course knowledge",
            sourceBodyHash: NoteStructureSourceSnapshot.hashBody(sourceBody),
            targetThinkspaceUUID: targetID,
            clusters: [
                NoteStructureClusterProposal(
                    id: clusterID,
                    name: "Core",
                    colorIndex: 0,
                    frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                    moduleIDs: [moduleID]
                )
            ],
            modules: [
                NoteStructureModuleProposal(
                    id: moduleID,
                    clusterID: clusterID,
                    title: "Module A",
                    startUTF16Offset: 0,
                    lengthUTF16: 8,
                    position: CGPoint(x: 80, y: 80),
                    size: CanvasBlock.documentLayoutSize
                )
            ]
        )

        viewModel.receivePendingNoteStructurePlan(plan)

        XCTAssertNil(viewModel.pendingNoteStructurePreviewError)
        XCTAssertTrue(viewModel.canApplyPendingNoteStructurePlan)
        XCTAssertEqual(viewModel.noteStructurePreviewText(for: plan.modules[0]), "Module A")
    }

    @MainActor
    func testCanvasOrganizerPromptMentionsNoteStructurePlanTool() {
        let profile = CustomAgentProfileStore.defaultProfileForTests(id: "canvas-organizer")

        XCTAssertTrue(profile?.runtimePrompt.contains("propose_note_structure_plan") == true)
        XCTAssertTrue(profile?.runtimePrompt.contains("Keep the original source note visible by default") == true)
        XCTAssertTrue(profile?.seedPrompts.contains("Split this note into structured clusters") == true)
    }
}

@MainActor
private final class NoteStructureTestContextProvider: CosmoContextProvider {
    let atomUUID: String
    let title: String
    let body: String
    let targetThinkspaceUUID: String

    init(atomUUID: String, title: String, body: String, targetThinkspaceUUID: String) {
        self.atomUUID = atomUUID
        self.title = title
        self.body = body
        self.targetThinkspaceUUID = targetThinkspaceUUID
    }

    var contextType: CosmoContextType { .noteFocusMode }

    var contextSummary: String { "Note: \(title)" }

    var contextData: CosmoContextData {
        CosmoContextData(
            currentAtomUUID: atomUUID,
            currentAtomType: "note",
            currentAtomTitle: title,
            viewSpecificData: [
                "noteBody": body,
                "targetThinkspaceUUID": targetThinkspaceUUID
            ]
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
