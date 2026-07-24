import XCTest
@testable import CosmoOS

/// The header scope switcher's contract: an explicit pick PINS the session,
/// passive focus churn can never unseat it, submit binds to the pin, the
/// "General" pin keeps document context out entirely, and a pin dies with
/// its document. Sessions stay isolated per surface throughout — switching
/// scope swaps whole conversations, never mixes two.
@MainActor
final class CosmoInlineScopePinningTests: XCTestCase {
    /// The registry holds providers WEAKLY — the test must keep them alive
    /// for its duration or they silently vanish mid-assertion.
    private var retainedSurfaces: [ScopeTestEditableSurface] = []

    override func tearDown() {
        for surface in retainedSurfaces {
            CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: surface.surfaceID)
        }
        retainedSurfaces = []
        super.tearDown()
    }

    @discardableResult
    private func registerSurface(
        _ surfaceID: String,
        title: String
    ) -> ScopeTestEditableSurface {
        let surface = ScopeTestEditableSurface(surfaceID: surfaceID, title: title)
        CosmoEditableSurfaceRegistry.shared.register(surface)
        retainedSurfaces.append(surface)
        return surface
    }

    private func makeStore(
        bridge: CosmoInlineAssistantAgentBridge = CosmoInlineAssistantAgentBridge { _, _, _ in }
    ) -> CosmoInlineAssistantStore {
        CosmoInlineAssistantStore(agentBridge: bridge)
    }

    func testPinScopeSwitchesSessionAndPreservesDraft() {
        registerSurface("idea:pin-a", title: "Main idea")
        let noteSurface = registerSurface("note:pin-b", title: "Secondary note")

        let store = makeStore()
        store.activateSessionIfIdle(surfaceID: "idea:pin-a")
        store.composerText = "tighten the opening"

        store.pinScope(toSurfaceID: noteSurface.surfaceID)

        XCTAssertEqual(store.currentScopeSurfaceID, "note:pin-b")
        XCTAssertEqual(store.pinnedScopeSurfaceID, "note:pin-b")
        XCTAssertEqual(store.composerText, "tighten the opening",
                       "A half-typed ask must survive retargeting at another document")
        XCTAssertEqual(store.activeEditableSnapshot()?.surfaceID, "note:pin-b")
    }

    func testPinScopeRefusesUnregisteredSurface() {
        let store = makeStore()
        store.pinScope(toSurfaceID: "note:never-registered")

        XCTAssertNil(store.pinnedScopeSurfaceID)
        XCTAssertEqual(store.currentScopeSurfaceID, CosmoInlineAssistantSessionScope.globalSurfaceID)
    }

    func testPassiveActivationCannotUnseatPin() {
        _ = registerSurface("idea:pin-c", title: "Main idea")
        let noteSurface = registerSurface("note:pin-d", title: "Secondary note")

        let store = makeStore()
        store.pinScope(toSurfaceID: noteSurface.surfaceID)
        store.activateSessionIfIdle(surfaceID: "idea:pin-c")

        XCTAssertEqual(store.currentScopeSurfaceID, "note:pin-d",
                       "Registration/key-window churn must not retarget a pinned session")
        XCTAssertEqual(store.pinnedScopeSurfaceID, "note:pin-d")
    }

    func testExplicitOpenPaneOverridesPin() {
        _ = registerSurface("idea:pin-e", title: "Main idea")
        let noteSurface = registerSurface("note:pin-f", title: "Secondary note")

        let store = makeStore()
        store.pinScope(toSurfaceID: noteSurface.surfaceID)
        store.openPane(forSurfaceID: "idea:pin-e")

        XCTAssertNil(store.pinnedScopeSurfaceID,
                     "An explicit per-document ask is newer than the pin and wins")
        XCTAssertEqual(store.currentScopeSurfaceID, "idea:pin-e")
    }

    func testSubmitBindsToPinnedSurfaceDespiteFocusElsewhere() async {
        _ = registerSurface("idea:pin-g", title: "Main idea")
        let noteSurface = registerSurface("note:pin-h", title: "Secondary note")

        var boundScopeAtSend: String?
        let store = makeStore(bridge: CosmoInlineAssistantAgentBridge { _, _, store in
            boundScopeAtSend = store.currentScopeSurfaceID
        })

        store.pinScope(toSurfaceID: noteSurface.surfaceID)
        // Focus churn after the pick: another surface becomes registry-top.
        CosmoEditableSurfaceRegistry.shared.activate(surfaceID: "idea:pin-g")

        store.composerText = "Rewrite this paragraph to be sharper"
        await store.submit()

        XCTAssertEqual(boundScopeAtSend, "note:pin-h",
                       "The ask must land on the pinned surface, not whatever holds focus")
        XCTAssertEqual(store.currentScopeSurfaceID, "note:pin-h")
    }

    func testGeneralPinBlocksDocumentContext() async {
        _ = registerSurface("idea:pin-i", title: "Main idea")

        var boundScopeAtSend: String?
        var snapshotAtSend: CosmoEditableSourceSnapshot?
        let store = makeStore(bridge: CosmoInlineAssistantAgentBridge { _, _, store in
            boundScopeAtSend = store.currentScopeSurfaceID
            snapshotAtSend = store.activeEditableSnapshot()
        })

        store.pinScopeToGeneral()

        XCTAssertTrue(store.isPinnedToGeneralScope)
        XCTAssertNil(store.activeEditableSnapshot(),
                     "Pinning General opts out of document context — the live-surface fallback must not leak it back")

        store.composerText = "What makes a hook strong?"
        await store.submit()

        XCTAssertEqual(boundScopeAtSend, CosmoInlineAssistantSessionScope.globalSurfaceID,
                       "Submit must not rebind a General-pinned session to the focused document")
        XCTAssertNil(snapshotAtSend)
    }

    func testPinClearedWhenPinnedSurfaceCloses() {
        _ = registerSurface("idea:pin-j", title: "Main idea")
        let noteSurface = registerSurface("note:pin-k", title: "Secondary note")

        let store = makeStore()
        store.pinScope(toSurfaceID: noteSurface.surfaceID)

        CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: "note:pin-k")
        store.releaseSessionIfScoped(toSurfaceID: "note:pin-k")

        XCTAssertNil(store.pinnedScopeSurfaceID, "A pin dies with its document")
        XCTAssertEqual(store.currentScopeSurfaceID, "idea:pin-j",
                       "Scope falls back to the next live surface")
    }

    func testUnpinReturnsToFollowingFocus() {
        registerSurface("idea:pin-l", title: "Main idea")
        let noteSurface = registerSurface("note:pin-m", title: "Secondary note")

        let store = makeStore()
        store.pinScope(toSurfaceID: noteSurface.surfaceID)
        // While pinned, focus moved elsewhere.
        CosmoEditableSurfaceRegistry.shared.activate(surfaceID: "idea:pin-l")

        store.unpinScope()

        XCTAssertNil(store.pinnedScopeSurfaceID)
        XCTAssertEqual(store.currentScopeSurfaceID, "idea:pin-l",
                       "Unpinning re-joins the focused surface")
    }

    func testSessionsStayIsolatedAcrossScopeSwitch() async {
        let ideaSurface = registerSurface("idea:pin-n", title: "Main idea")
        let noteSurface = registerSurface("note:pin-o", title: "Secondary note")

        let store = makeStore(bridge: CosmoInlineAssistantAgentBridge { _, _, store in
            store.receivePaneAnswer(title: nil, answer: "An answer for the idea document.")
        })

        store.pinScope(toSurfaceID: ideaSurface.surfaceID)
        store.composerText = "What is the strongest hook here?"
        await store.submit()
        XCTAssertFalse(store.paneMessages.isEmpty)

        store.pinScope(toSurfaceID: noteSurface.surfaceID)
        XCTAssertTrue(store.paneMessages.isEmpty,
                      "The note's session must not show the idea's conversation")

        store.pinScope(toSurfaceID: ideaSurface.surfaceID)
        XCTAssertTrue(store.paneMessages.contains { $0.role == .assistant },
                      "Switching back restores the idea's own conversation intact")
    }

    func testLiveSurfaceListingsOrderAndIdentity() {
        let registry = CosmoEditableSurfaceRegistry()
        let idea = ScopeTestEditableSurface(surfaceID: "idea:list-a", title: "Main idea")
        let note = ScopeTestEditableSurface(surfaceID: "note:list-b", title: "  ")
        registry.register(idea)
        registry.register(note)

        let listings = registry.liveSurfaceListings()

        XCTAssertEqual(listings.map(\.surfaceID), ["note:list-b", "idea:list-a"],
                       "Most recently active first")
        XCTAssertEqual(listings.first?.title, "Untitled")
        XCTAssertEqual(listings.first?.entity, "note")
        XCTAssertEqual(listings.last?.entity, "idea")
    }
}

@MainActor
private final class ScopeTestEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    let title: String

    init(surfaceID: String, title: String) {
        self.surfaceID = surfaceID
        self.title = title
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: "\(surfaceID):body",
            kind: .text,
            title: title,
            text: "Original text",
            sourceHash: CosmoEditableSurfaceHasher.hash("Original text"),
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: 13)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
