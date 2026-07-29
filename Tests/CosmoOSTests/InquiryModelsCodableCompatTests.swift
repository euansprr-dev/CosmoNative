// CosmoOS/Tests/CosmoOSTests/InquiryModelsCodableCompatTests.swift
// Guards backward compatibility: atoms persisted before the concept-first
// revamp (no narrative/concept/routing fields) must still decode, and new
// fields must roundtrip.
// Realigned July 2026.

import XCTest
@testable import CosmoOS

final class InquiryModelsCodableCompatTests: XCTestCase {

    func testLegacyDeepDiveStructuredDecodes() throws {
        let legacy = """
        {
          "currentUnderstanding": {
            "oneSentenceModel": "Breath bridges conscious and unconscious processes.",
            "corePrinciples": [],
            "whatIBelieve": [],
            "whatImUnsureAbout": [],
            "recentUpdates": [],
            "openQuestionUUIDs": [],
            "explainSimply": "",
            "explainExpertly": "",
            "versionHistory": []
          },
          "practiceProtocols": [],
          "outputAngles": []
        }
        """
        let decoded = try JSONDecoder().decode(DeepDiveStructured.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.currentUnderstanding.oneSentenceModel, "Breath bridges conscious and unconscious processes.")
        XCTAssertNil(decoded.currentUnderstanding.narrative)
        XCTAssertNil(decoded.currentUnderstanding.narrativeHistory)
    }

    func testLegacyDeepDiveMetadataDecodes() throws {
        let legacy = """
        {"aliases":["bw"],"maturity":"exploring","lastInquiryAt":"2026-05-18T03:20:17Z"}
        """
        let decoded = try JSONDecoder().decode(DeepDiveMetadata.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.aliases, ["bw"])
        XCTAssertNil(decoded.bodyMigratedAt)
    }

    func testLegacyExtractMetadataDecodes() throws {
        let legacy = """
        {"kind":"claim","status":"committed","parentSessionUUID":"sess-1"}
        """
        let decoded = try JSONDecoder().decode(ExtractMetadata.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.kind, .claim)
        XCTAssertNil(decoded.routingDecisionId)
        XCTAssertNil(decoded.conceptNames)
    }

    func testLegacyConnectionCandidateDecodes() throws {
        let legacy = """
        {"name":"Pranayama","clusterExtractUUIDs":["e1"],"accepted":true}
        """
        let decoded = try JSONDecoder().decode(CrystallizationOutput.ConnectionCandidate.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.name, "Pranayama")
        XCTAssertNil(decoded.mergeTargetConnectionUUID)
        XCTAssertNil(decoded.conceptKey)
    }

    func testNewFieldsRoundtrip() throws {
        var understanding = CurrentUnderstanding(oneSentenceModel: "Model")
        understanding.recordNarrativeRevision(UnderstandingNarrativeRevision(
            date: "2026-06-10T00:00:00Z",
            text: "Synthesis text",
            sessionUUID: "sess-1",
            originOperationId: "op-1",
            kind: .canvasOp
        ))
        let structured = DeepDiveStructured(currentUnderstanding: understanding)
        let data = try JSONEncoder().encode(structured)
        let decoded = try JSONDecoder().decode(DeepDiveStructured.self, from: data)
        XCTAssertEqual(decoded.currentUnderstanding.narrative, "Synthesis text")
        XCTAssertEqual(decoded.currentUnderstanding.narrativeHistory?.count, 1)
        XCTAssertEqual(decoded.currentUnderstanding.narrativeHistory?.first?.kind, .canvasOp)

        let candidate = CrystallizationOutput.ConnectionCandidate(
            name: "Vagus nerve",
            mergeTargetConnectionUUID: "conn-1",
            conceptAliases: ["vagal tone"],
            conceptKey: "vagus nerve"
        )
        let candidateData = try JSONEncoder().encode(candidate)
        let decodedCandidate = try JSONDecoder().decode(CrystallizationOutput.ConnectionCandidate.self, from: candidateData)
        XCTAssertEqual(decodedCandidate.mergeTargetConnectionUUID, "conn-1")
        XCTAssertEqual(decodedCandidate.conceptKey, "vagus nerve")
    }
}
