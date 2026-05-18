import XCTest
@testable import CosmoOS

final class ConnectionFocusModeStateMigrationTests: XCTestCase {

    func testLegacyLayoutStateIsClearedDuringDecode() throws {
        var state = ConnectionFocusModeState(atomUUID: "connection-uuid")
        state.setStationPosition(.goal, to: CGPoint(x: 120, y: 180))
        state.setCanvasPosition("masthead", to: CGPoint(x: 300, y: 220))
        state.setCanvasSize("well", to: CGSize(width: 320, height: 480))
        state.hidePanel("insights")

        let encoded = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        json.removeValue(forKey: "layoutVersion")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ConnectionFocusModeState.self, from: legacyData)

        XCTAssertEqual(decoded.atomUUID, "connection-uuid")
        XCTAssertTrue(decoded.stationPositions.isEmpty)
        XCTAssertTrue(decoded.canvasPositions.isEmpty)
        XCTAssertTrue(decoded.canvasSizes.isEmpty)
        XCTAssertTrue(decoded.hiddenPanels.isEmpty)
        XCTAssertEqual(decoded.sections.count, ConnectionSectionType.allCases.count)
    }

    func testLegacyCollaboratorCrystallizeMessageMigratesToDraftProposal() throws {
        let encoded = try JSONEncoder().encode(ConnectionFocusModeState(atomUUID: "connection-uuid"))
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json["collaboratorMessages"] = [
            [
                "id": UUID().uuidString,
                "role": "assistant",
                "text": "This belongs in Goal.",
                "crystallizeTarget": "goal",
                "crystallizeContent": "Trust is a loop, not a trait."
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ConnectionFocusModeState.self, from: data)

        XCTAssertEqual(decoded.collaboratorMessages.count, 1)
        XCTAssertEqual(decoded.collaboratorMessages.first?.draftProposal?.targetSection, .goal)
        XCTAssertEqual(decoded.collaboratorMessages.first?.draftProposal?.draftText, "Trust is a loop, not a trait.")
        XCTAssertFalse(decoded.collaboratorSession.hasBootstrapped)
        XCTAssertNil(decoded.activeDraftProposal)
    }

    func testConnectionStructuredDataBackfillsInquiryV2Sections() throws {
        let legacyTypes: [ConnectionSectionType] = [
            .goal,
            .problems,
            .benefits,
            .examples,
            .beliefsObjections,
            .process,
            .conceptName,
            .references
        ]
        let legacyData = ConnectionStructuredData(
            sections: legacyTypes.map { ConnectionSection(type: $0) }
        )
        let json = try XCTUnwrap(legacyData.toJSON())

        let decoded = try XCTUnwrap(ConnectionStructuredData.fromJSON(json))

        XCTAssertEqual(decoded.sections.map(\.type), ConnectionSectionType.allCases.sorted { $0.sortOrder < $1.sortOrder })
        XCTAssertEqual(decoded.sections.first(where: { $0.type == .claims })?.items, [])
        XCTAssertEqual(decoded.sections.first(where: { $0.type == .evidence })?.items, [])
        XCTAssertEqual(decoded.sections.first(where: { $0.type == .openQuestions })?.items, [])
    }
}
