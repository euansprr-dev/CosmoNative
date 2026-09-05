import XCTest
@testable import CosmoOS

@MainActor
final class ContentHistoryDurabilityTests: XCTestCase {
    func testMetadataRoundTripRetainsFullConversationAndGenerationHistory() throws {
        var state = ContentFocusModeState(atomUUID: UUID().uuidString)
        state.conversationHistory = (0..<75).map { WritingMessage(role: .user, content: "Question \($0)") }
        state.generationHistory = (0..<65).map {
            GenerationRecord(mode: .draft, inputContext: "Input \($0)", outputSummary: "Result \($0)")
        }
        let fields = state.toAtomFields(existingMetadata: nil)
        let json = try XCTUnwrap(fields.metadata)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual((dict["conversationHistory"] as? [Any])?.count, 75)
        XCTAssertEqual((dict["generationHistory"] as? [Any])?.count, 65)
    }
}
