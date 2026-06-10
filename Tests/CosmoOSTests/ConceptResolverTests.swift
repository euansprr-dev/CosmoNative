// CosmoOS/Tests/CosmoOSTests/ConceptResolverTests.swift
// Heuristic (offline) concept assignment + shared helpers.

import XCTest
@testable import CosmoOS

final class ConceptResolverTests: XCTestCase {

    private func extract(_ uuid: String, body: String, kind: ExtractKind = .claim, questionUUID: String? = nil) -> Atom {
        let metadata = ExtractMetadata(kind: kind, parentQuestionUUID: questionUUID)
        let json = String(data: try! JSONEncoder().encode(metadata), encoding: .utf8)
        var atom = Atom.new(type: .extract, title: String(body.prefix(40)), body: body, metadata: json)
        atom.uuid = uuid
        return atom
    }

    private func input(
        extracts: [Atom],
        lexicon: [Atom] = [],
        connections: [Atom] = [],
        questions: [Atom] = []
    ) -> ConceptResolver.Input {
        ConceptResolver.Input(
            deepDive: Atom.new(type: .deepDive, title: "Breathwork"),
            session: Atom.new(type: .inquirySession, title: "Session"),
            extracts: extracts,
            lexicon: lexicon,
            existingConnections: connections,
            questions: questions
        )
    }

    func testExistingConnectionTitleMatchProducesMerge() {
        var connection = Atom.new(type: .connection, title: "Pranayama")
        connection.uuid = "conn-1"
        let assignments = ConceptResolver.heuristicAssignments(input(
            extracts: [extract("e-1", body: "Bhastrika is an energizing pranayama technique")],
            connections: [connection]
        ))

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.action, .mergeInto(connectionUUID: "conn-1"))
        XCTAssertEqual(assignments.first?.extractUUIDs, ["e-1"])
    }

    func testLexiconTermMatchProducesCreate() {
        let term = Atom.new(type: .lexiconEntry, title: "Vagus nerve")
        let assignments = ConceptResolver.heuristicAssignments(input(
            extracts: [extract("e-2", body: "The vagus nerve links breath rate to heart rate")],
            lexicon: [term]
        ))

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.conceptName, "Vagus nerve")
        XCTAssertEqual(assignments.first?.action, .createNew)
    }

    func testUnmatchedExtractFallsBackToBranchQuestionConcept() {
        var question = Atom.new(type: .question, title: "What is coherent breathing?")
        question.uuid = "q-1"
        let assignments = ConceptResolver.heuristicAssignments(input(
            extracts: [extract("e-3", body: "Five breaths per minute synchronizes heart rhythms", questionUUID: "q-1")],
            questions: [question]
        ))

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.conceptName, "coherent breathing")
        XCTAssertEqual(assignments.first?.action, .createNew)
    }

    func testConceptKeyNormalization() {
        XCTAssertEqual(ConceptResolver.conceptKey("Vagus Nerve!"), "vagus nerve")
        XCTAssertEqual(ConceptResolver.conceptKey("  CO2-Tolerance "), "co2 tolerance")
    }

    func testConceptNameFromQuestionStripsInterrogatives() {
        XCTAssertEqual(ConceptResolver.conceptName(fromQuestion: "What is pranayama?"), "pranayama")
        XCTAssertEqual(ConceptResolver.conceptName(fromQuestion: "How does CO2 tolerance adapt?"), "CO2 tolerance adapt")
    }

    func testJSONObjectParsingHandlesFences() {
        let fenced = """
        ```json
        {"assignments": []}
        ```
        """
        XCTAssertNotNil(ConceptResolver.jsonObject(from: fenced))
        XCTAssertNil(ConceptResolver.jsonObject(from: "not json"))
    }

    // MARK: - Persisted-tag pre-assignment

    private func taggedExtract(_ uuid: String, body: String, concepts: [String]) -> Atom {
        var atom = extract(uuid, body: body)
        var metadata = atom.extractMetadata!
        metadata.conceptNames = concepts
        return atom.withMetadata(metadata)
    }

    func testPersistedTagsGroupExtractsWithoutLLM() {
        let assignments = ConceptResolver.assignmentsFromPersistedTags(input(
            extracts: [
                taggedExtract("e-1", body: "Morning light sets the circadian clock", concepts: ["Morning sunlight"]),
                taggedExtract("e-2", body: "Get 10-30 minutes of sun per day", concepts: ["Morning sunlight"]),
                extract("e-3", body: "Untagged thought")
            ]
        ))

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.conceptName, "Morning sunlight")
        XCTAssertEqual(assignments.first?.extractUUIDs, ["e-1", "e-2"])
        XCTAssertEqual(assignments.first?.action, .createNew)
    }

    func testPersistedTagMatchingExistingConnectionMerges() {
        var connection = Atom.new(type: .connection, title: "Morning Sunlight")
        connection.uuid = "conn-7"
        let assignments = ConceptResolver.assignmentsFromPersistedTags(input(
            extracts: [taggedExtract("e-1", body: "Sun exposure benefits the liver", concepts: ["morning sunlight"])],
            connections: [connection]
        ))

        XCTAssertEqual(assignments.first?.action, .mergeInto(connectionUUID: "conn-7"))
        XCTAssertEqual(assignments.first?.conceptName, "Morning Sunlight")
    }

    func testMergedCombinesByConceptKeyAndPrefersMergeTarget() {
        let preassigned = ConceptResolver.ConceptAssignment(
            conceptKey: "vagus nerve", conceptName: "Vagus nerve", aliases: [],
            action: .createNew, extractUUIDs: ["e-1"], rationale: "", confidence: 0.9
        )
        let fromLLM = ConceptResolver.ConceptAssignment(
            conceptKey: "vagus nerve", conceptName: "Vagus Nerve", aliases: [],
            action: .mergeInto(connectionUUID: "conn-2"), extractUUIDs: ["e-1", "e-4"], rationale: "", confidence: 0.7
        )
        let other = ConceptResolver.ConceptAssignment(
            conceptKey: "co2 tolerance", conceptName: "CO2 tolerance", aliases: [],
            action: .createNew, extractUUIDs: ["e-5"], rationale: "", confidence: 0.7
        )

        let merged = ConceptResolver.merged([preassigned], [fromLLM, other])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.extractUUIDs, ["e-1", "e-4"])
        XCTAssertEqual(merged.first?.action, .mergeInto(connectionUUID: "conn-2"))
        XCTAssertEqual(merged.last?.conceptKey, "co2 tolerance")
    }
}
