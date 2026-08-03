import XCTest
@testable import CosmoOS

/// The stale-surface shield (Aug 3 incident): Begin Writing's idea→content
/// hand-off left the registry serving a twin of the content editor whose dead
/// @State read an EMPTY draft while the user's live editor held 470 words —
/// Cosmo answered "I need to see the draft" with the draft on screen. Three
/// layered guarantees prevent the whole class:
/// 1. a stale host's unregister can never evict a newer registration,
/// 2. typing re-seats the registry entry on the instance the user is editing,
/// 3. a submission snapshot that is missing or empty hydrates from the
///    persisted atom before the model ever sees it.
@MainActor
final class CosmoInlineStaleSurfaceShieldTests: XCTestCase {
    /// The registry holds providers WEAKLY — keep them alive per test.
    private var retainedSurfaces: [StaleShieldTestSurface] = []

    override func tearDown() {
        for surface in retainedSurfaces {
            CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: surface.surfaceID)
        }
        retainedSurfaces = []
        super.tearDown()
    }

    private func makeStore() -> CosmoInlineAssistantStore {
        CosmoInlineAssistantStore(agentBridge: CosmoInlineAssistantAgentBridge { _, _, _ in })
    }

    @discardableResult
    private func surface(_ surfaceID: String, title: String, text: String) -> StaleShieldTestSurface {
        let surface = StaleShieldTestSurface(surfaceID: surfaceID, title: title, text: text)
        retainedSurfaces.append(surface)
        return surface
    }

    // MARK: - Registry: instance-guarded unregister

    func testStaleTwinUnregisterDoesNotEvictNewerRegistration() {
        let registry = CosmoEditableSurfaceRegistry()
        let stale = surface("content:twin-1", title: "Draft", text: "")
        let live = surface("content:twin-1", title: "Draft", text: "SLIDE 1")

        registry.register(stale)
        registry.registerPresence(live) // remount twin takes the entry

        registry.unregister(stale) // stale host's onDisappear fires late
        XCTAssertTrue(registry.provider(surfaceID: "content:twin-1") === live,
                      "A departing stale host must not tear down the live registration")

        registry.unregister(live)
        XCTAssertNil(registry.provider(surfaceID: "content:twin-1"),
                     "The registered instance's own teardown still removes the surface")
    }

    // MARK: - Registry: typing reclaims the entry

    func testTypingReclaimReseatsRegistryEntryOnTheEditedInstance() {
        let registry = CosmoEditableSurfaceRegistry()
        let live = surface("content:twin-2", title: "Draft", text: "SLIDE 1")
        let ghost = surface("content:twin-2", title: "Draft", text: "")

        registry.register(live)
        registry.registerPresence(ghost) // ghost shadows the live editor

        registry.activateIfNeeded(live) // a keystroke names the real instance
        XCTAssertTrue(registry.provider(surfaceID: "content:twin-2") === live)
        XCTAssertEqual(registry.activeSurface?.editableSnapshot().text, "SLIDE 1")
    }

    // MARK: - Store: submission snapshot hydration

    func testSubmissionSnapshotHydratesEmptyLiveTextFromPersistedAtom() async {
        let registry = CosmoEditableSurfaceRegistry()
        let empty = surface("content:shield-1", title: "$50,000 draft", text: "")
        registry.register(empty)

        let store = makeStore()
        store.activateSessionIfIdle(surfaceID: "content:shield-1")

        let snapshot = await store.submissionEditableSnapshot(registry: registry, persistedTextLoader: { _ in
            "SLIDE 1\n$55,000 can buy you a home worth $300,000 with no mortgage."
        })

        XCTAssertEqual(snapshot?.surfaceID, "content:shield-1")
        XCTAssertEqual(snapshot?.targetID, empty.targetID,
                       "Hydration must keep the live snapshot's targetID so edits still bind")
        XCTAssertEqual(snapshot?.title, "$50,000 draft")
        XCTAssertTrue(snapshot?.text.hasPrefix("SLIDE 1") ?? false,
                      "An empty read from a registered surface takes the persisted draft")
    }

    func testSubmissionSnapshotHydratesMissingProviderFromPersistedAtom() async {
        let store = makeStore()
        store.activateSessionIfIdle(surfaceID: "content:shield-2")

        let snapshot = await store.submissionEditableSnapshot(
            registry: CosmoEditableSurfaceRegistry(),
            persistedTextLoader: { surfaceID in
                surfaceID == "content:shield-2" ? "SLIDE 1\nDraft body" : nil
            }
        )

        XCTAssertEqual(snapshot?.surfaceID, "content:shield-2")
        XCTAssertEqual(snapshot?.targetID, "content:shield-2:draft",
                       "Content hydration follows ContentContextProvider's targetID convention")
        XCTAssertEqual(snapshot?.text, "SLIDE 1\nDraft body")
    }

    func testSubmissionSnapshotKeepsHealthyLiveText() async {
        let registry = CosmoEditableSurfaceRegistry()
        let healthy = surface("content:shield-3", title: "Draft", text: "The real live text")
        registry.register(healthy)

        let store = makeStore()
        store.activateSessionIfIdle(surfaceID: "content:shield-3")

        var loaderCalled = false
        let snapshot = await store.submissionEditableSnapshot(registry: registry, persistedTextLoader: { _ in
            loaderCalled = true
            return "stale persisted text"
        })

        XCTAssertEqual(snapshot?.text, "The real live text")
        XCTAssertFalse(loaderCalled, "A healthy live snapshot never touches the DB")
    }

    func testSubmissionSnapshotStaysEmptyWhenPersistedAlsoEmpty() async {
        let registry = CosmoEditableSurfaceRegistry()
        let empty = surface("content:shield-4", title: "Fresh doc", text: "")
        registry.register(empty)

        let store = makeStore()
        store.activateSessionIfIdle(surfaceID: "content:shield-4")

        let snapshot = await store.submissionEditableSnapshot(registry: registry, persistedTextLoader: { _ in "" })

        XCTAssertEqual(snapshot?.text, "",
                       "A genuinely empty document stays empty — hydration is a no-op")
    }

    func testGeneralPinNeverHydrates() async {
        let store = makeStore()
        store.pinScopeToGeneral()

        var loaderCalled = false
        let snapshot = await store.submissionEditableSnapshot(
            registry: CosmoEditableSurfaceRegistry(),
            persistedTextLoader: { _ in
                loaderCalled = true
                return "document text"
            }
        )

        XCTAssertNil(snapshot, "General pin is an explicit opt-out of document context")
        XCTAssertFalse(loaderCalled)
    }
}

@MainActor
private final class StaleShieldTestSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    let title: String
    var text: String

    var targetID: String { "\(surfaceID):draft" }

    init(surfaceID: String, title: String, text: String) {
        self.surfaceID = surfaceID
        self.title = title
        self.text = text
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: title,
            text: text,
            sourceHash: CosmoEditableSurfaceHasher.hash(text),
            anchors: [.init(id: "draft", label: "Draft", utf16Start: 0, utf16Length: text.utf16.count)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
