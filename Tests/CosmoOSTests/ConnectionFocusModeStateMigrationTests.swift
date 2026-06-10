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

    /// Old persisted blobs carry collaborator history (collaboratorMessages,
    /// activeDraftProposal, collaboratorSession). Those features are gone —
    /// the keys must be silently ignored and the sections must survive.
    func testV2JSONWithCollaboratorKeysStillDecodes() throws {
        var state = ConnectionFocusModeState(atomUUID: "connection-uuid")
        state.addItem(ConnectionItem(content: "Trust compounds."), toSection: .claims)

        let encoded = try JSONEncoder().encode(state)
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
        json["activeDraftProposal"] = [
            "id": UUID().uuidString,
            "targetSection": "claims",
            "draftText": "Pending draft",
            "visibleText": "Pending draft",
            "rationale": "",
            "sourceIDs": [] as [String],
            "status": "streaming",
            "createdAt": 770000000.0
        ]
        json["collaboratorSession"] = [
            "presetID": "deepen.connection",
            "hasBootstrapped": true
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ConnectionFocusModeState.self, from: data)

        XCTAssertEqual(decoded.atomUUID, "connection-uuid")
        XCTAssertEqual(
            decoded.section(for: .claims)?.items.map(\.resolvedPlainText),
            ["Trust compounds."]
        )
    }

    /// V2 stored ForgeMode raw values under the `forgeMode` key. They map
    /// onto ConnectionViewMode: forge/chalkboard → board, manuscript stays.
    func testLegacyForgeModeMapsToViewMode() throws {
        for (legacy, expected): (String, ConnectionViewMode) in [
            ("forge", .board),
            ("chalkboard", .board),
            ("manuscript", .manuscript),
            ("outline", .outline),
            ("somethingUnknown", .board)
        ] {
            let state = ConnectionFocusModeState(atomUUID: "connection-uuid")
            let encoded = try JSONEncoder().encode(state)
            var json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            json["forgeMode"] = legacy

            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(ConnectionFocusModeState.self, from: data)

            XCTAssertEqual(decoded.viewMode, expected, "legacy \(legacy)")
        }
    }

    func testViewModeRoundTripsUnderForgeModeKey() throws {
        var state = ConnectionFocusModeState(atomUUID: "connection-uuid")
        state.viewMode = .outline

        let encoded = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(json["forgeMode"] as? String, "outline")

        let decoded = try JSONDecoder().decode(ConnectionFocusModeState.self, from: encoded)
        XCTAssertEqual(decoded.viewMode, .outline)
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
