import XCTest
@testable import CosmoOS

final class UserDefaultsPrunerTests: XCTestCase {
    private let uuid = "A0E34B9D-9E2E-4EF2-84C1-71D12C0721D0"

    func testExtractsAtomUUIDFromEachSweptFamily() {
        XCTAssertEqual(UserDefaultsPruner.atomUUID(inKey: "connectionFocusMode_\(uuid)"), uuid)
        XCTAssertEqual(UserDefaultsPruner.atomUUID(inKey: "researchFocusMode_\(uuid)"), uuid)
        XCTAssertEqual(UserDefaultsPruner.atomUUID(inKey: "ideaFocus_\(uuid)_intelligencePanelCollapsed"), uuid)
        XCTAssertEqual(UserDefaultsPruner.atomUUID(inKey: "cosmo.inlineAssistant.session.content:\(uuid)"), uuid)
    }

    func testNeverMatchesNonAtomKeys() {
        // Non-UUID suffixes (e.g. the inline assistant's global session) stay.
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "cosmo.inlineAssistant.session.global"))
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "ideaFocus_notAUUID_state"))
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "connectionFocusMode_trailing-junk"))
        // Unrelated keys are untouched.
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "cosmoWindow.lastConversationId"))
        XCTAssertNil(UserDefaultsPruner.atomUUID(inKey: "agent_custom_system_prompt"))
    }

    func testTrailingUUIDParsesCollaboratorConversationIds() {
        XCTAssertEqual(
            UserDefaultsPruner.trailingUUID(of: "cosmo-collaborator-outline-\(uuid)"),
            uuid
        )
        XCTAssertNil(UserDefaultsPruner.trailingUUID(of: "cosmo-window-ded03665"))
    }
}
