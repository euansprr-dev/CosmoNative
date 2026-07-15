// CosmoOS/Tests/CosmoOSTests/ConceptSeedbedTests.swift
// The Seedbed's contracts: live accrual dedups and never double-counts,
// dismissed seedlings stop accruing, ripeness is legible and deterministic,
// and the resolver's tidy pass canonicalizes/folds without ever destroying
// user-visible mass.

import XCTest
@testable import CosmoOS

final class ConceptSeedbedTests: XCTestCase {

    // MARK: - Helpers

    private func entry(
        _ names: [String],
        extractUUID: String,
        text: String = "Slow exhales raise vagal tone",
        kind: ExtractKind = .claim,
        session: String? = "s-1"
    ) -> ConceptSeedbedReducer.AccrualEntry {
        ConceptSeedbedReducer.AccrualEntry(
            conceptNames: names,
            extractUUID: extractUUID,
            rawSnippet: text,
            extractKind: kind,
            sessionUUID: session
        )
    }

    private func seedling(
        _ name: String,
        items: [StagedConceptItem],
        status: IncubatingConcept.Status = .incubating,
        pinned: Bool = false
    ) -> IncubatingConcept {
        IncubatingConcept(
            conceptKey: ConceptResolver.conceptKey(name),
            name: name,
            stagedItems: items,
            status: status,
            pinnedAt: pinned ? ISO8601.string(from: Date()) : nil
        )
    }

    private func item(_ extractUUID: String, session: String? = "s-1", consumed: Bool = false) -> StagedConceptItem {
        StagedConceptItem(
            sourceExtractUUID: extractUUID,
            rawSnippet: "capture \(extractUUID)",
            sessionUUID: session,
            consumedAt: consumed ? ISO8601.string(from: Date()) : nil
        )
    }

    private func extractAtom(_ uuid: String, body: String, kind: ExtractKind = .claim, session: String? = nil) -> Atom {
        let metadata = ExtractMetadata(kind: kind, parentSessionUUID: session)
        let json = String(data: try! JSONEncoder().encode(metadata), encoding: .utf8)
        var atom = Atom.new(type: .extract, title: String(body.prefix(40)), body: body, metadata: json)
        atom.uuid = uuid
        return atom
    }

    // MARK: - Accrual

    func testAccrualCreatesSeedlingWithSectionHint() {
        let result = ConceptSeedbedReducer.accrue([], entries: [
            entry(["Vagus nerve"], extractUUID: "e-1", kind: .claim)
        ])
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.seedbed.count, 1)
        XCTAssertEqual(result.seedbed.first?.conceptKey, "vagus nerve")
        XCTAssertEqual(result.seedbed.first?.name, "Vagus nerve")
        XCTAssertEqual(result.seedbed.first?.stagedItems.count, 1)
        XCTAssertEqual(result.seedbed.first?.stagedItems.first?.proposedSection, ConnectionSectionType.claims.rawValue)
    }

    func testAccrualDedupsBySourceExtract() {
        let first = ConceptSeedbedReducer.accrue([], entries: [entry(["Vagus nerve"], extractUUID: "e-1")])
        let second = ConceptSeedbedReducer.accrue(first.seedbed, entries: [entry(["Vagus nerve"], extractUUID: "e-1")])
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.seedbed.first?.stagedItems.count, 1)
    }

    func testOneExtractWithTwoTagsLandsInBothSeedlings() {
        let result = ConceptSeedbedReducer.accrue([], entries: [
            entry(["Pranayama", "Vagus nerve"], extractUUID: "e-1")
        ])
        XCTAssertEqual(result.seedbed.count, 2)
        XCTAssertTrue(result.seedbed.allSatisfy { $0.stagedItems.map(\.sourceExtractUUID) == ["e-1"] })
    }

    func testDismissedSeedlingStopsAccruing() {
        let dismissed = seedling("Vagus nerve", items: [item("e-1")], status: .dismissed)
        let result = ConceptSeedbedReducer.accrue([dismissed], entries: [entry(["Vagus nerve"], extractUUID: "e-2")])
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.seedbed.first?.stagedItems.count, 1)
    }

    func testDevelopedSeedlingKeepsCollectingNewMaterial() {
        var developed = seedling("Vagus nerve", items: [item("e-1", consumed: true)], status: .developed)
        developed.developedConnectionUUID = "conn-1"
        let result = ConceptSeedbedReducer.accrue([developed], entries: [entry(["Vagus nerve"], extractUUID: "e-2")])
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.seedbed.first?.pendingItems.map(\.sourceExtractUUID), ["e-2"])
    }

    func testExistingPageBecomesMergeTargetOnCreation() {
        let result = ConceptSeedbedReducer.accrue(
            [],
            entries: [entry(["Pranayama"], extractUUID: "e-1")],
            existingPageUUIDsByKey: ["pranayama": "conn-9"]
        )
        XCTAssertEqual(result.seedbed.first?.mergeTargetConnectionUUID, "conn-9")
    }

    func testCrossingRipenessLineReportsNewlyRipeKey() {
        // Three captures from an earlier session, the fourth (new session) ripens it.
        let existing = seedling("Vagus nerve", items: [
            item("e-1", session: "s-0"), item("e-2", session: "s-0"), item("e-3", session: "s-0")
        ])
        let result = ConceptSeedbedReducer.accrue([existing], entries: [
            entry(["Vagus nerve"], extractUUID: "e-4", session: "s-1")
        ])
        XCTAssertEqual(result.newlyRipeKeys, ["vagus nerve"])
    }

    // MARK: - Ripeness

    func testFourCapturesAcrossTwoSessionsIsRipeWithReason() {
        let verdict = ConceptRipeness.evaluate(seedling("Vagus nerve", items: [
            item("e-1", session: "s-0"), item("e-2", session: "s-0"),
            item("e-3", session: "s-1"), item("e-4", session: "s-1")
        ]))
        XCTAssertTrue(verdict.isRipe)
        XCTAssertEqual(verdict.reason, "4 captures · 2 sessions")
    }

    func testHeavySingleSessionIsRipe() {
        let items = (1...7).map { item("e-\($0)", session: "s-1") }
        let verdict = ConceptRipeness.evaluate(seedling("Box breathing", items: items))
        XCTAssertTrue(verdict.isRipe)
        XCTAssertEqual(verdict.reason, "7 captures this session")
    }

    func testThinSingleSessionSeedlingIsNotRipe() {
        let verdict = ConceptRipeness.evaluate(seedling("Box breathing", items: [
            item("e-1"), item("e-2"), item("e-3")
        ]))
        XCTAssertFalse(verdict.isRipe)
    }

    func testPinnedSeedlingIsAlwaysRipe() {
        let verdict = ConceptRipeness.evaluate(seedling("Box breathing", items: [item("e-1")], pinned: true))
        XCTAssertTrue(verdict.isRipe)
        XCTAssertEqual(verdict.reason, "Pinned")
    }

    func testDevelopedSeedlingIsNeverRipe() {
        let items = (1...9).map { item("e-\($0)") }
        let verdict = ConceptRipeness.evaluate(seedling("Vagus nerve", items: items, status: .developed))
        XCTAssertFalse(verdict.isRipe)
    }

    func testConsumedItemsDoNotCountTowardRipeness() {
        let items = [
            item("e-1", session: "s-0", consumed: true), item("e-2", session: "s-0", consumed: true),
            item("e-3", session: "s-1"), item("e-4", session: "s-1")
        ]
        XCTAssertFalse(ConceptRipeness.evaluate(seedling("Vagus nerve", items: items)).isRipe)
    }

    // MARK: - Tidy

    private func assignment(
        _ name: String,
        extracts: [String],
        action: ConceptResolver.Action = .createNew,
        aliases: [String] = [],
        parent: String? = nil,
        related: [String] = []
    ) -> ConceptResolver.ConceptAssignment {
        ConceptResolver.ConceptAssignment(
            conceptKey: ConceptResolver.conceptKey(name),
            conceptName: name,
            aliases: aliases,
            action: action,
            extractUUIDs: extracts,
            rationale: "",
            confidence: 0.8,
            relatedConceptNames: related,
            parentConceptName: parent
        )
    }

    func testTidyCanonicalizesAndBackfillsMissingItems() {
        let existing = seedling("vagal tone", items: [item("e-1")])
        let tidied = ConceptSeedbedReducer.applyTidy(
            [existing],
            assignments: [assignment(
                "Vagal tone",
                extracts: ["e-1", "e-2"],
                action: .mergeInto(connectionUUID: "conn-3"),
                aliases: ["Vagus tone"],
                parent: "Breathwork"
            )],
            extracts: [extractAtom("e-2", body: "HRV rises with vagal tone", kind: .evidence, session: "s-2")],
            sessionUUID: "s-1"
        )
        XCTAssertEqual(tidied.count, 1)
        XCTAssertEqual(tidied.first?.name, "Vagal tone")
        XCTAssertEqual(tidied.first?.aliases, ["Vagus tone"])
        XCTAssertEqual(tidied.first?.parentConceptName, "Breathwork")
        XCTAssertEqual(tidied.first?.mergeTargetConnectionUUID, "conn-3")
        XCTAssertEqual(tidied.first?.stagedItems.count, 2)
        XCTAssertEqual(
            tidied.first?.stagedItems.last?.proposedSection,
            ConnectionSectionType.evidence.rawValue
        )
        XCTAssertEqual(tidied.first?.stagedItems.last?.sessionUUID, "s-2")
    }

    func testTidyFoldsNearDuplicateIntoSurvivor() {
        // "Breathing" seedling's only extract was assigned to "Box breathing" —
        // it folds in, its name survives as an alias.
        let survivor = seedling("Box breathing", items: [item("e-1")])
        let duplicate = seedling("Breathing", items: [item("e-2")])
        let tidied = ConceptSeedbedReducer.applyTidy(
            [survivor, duplicate],
            assignments: [assignment("Box breathing", extracts: ["e-1", "e-2"])],
            extracts: [],
            sessionUUID: "s-1"
        )
        XCTAssertEqual(tidied.count, 1)
        XCTAssertEqual(tidied.first?.conceptKey, "box breathing")
        XCTAssertEqual(Set(tidied.first?.stagedItems.map(\.sourceExtractUUID) ?? []), ["e-1", "e-2"])
        XCTAssertTrue(tidied.first?.aliases.contains("Breathing") ?? false)
    }

    func testTidyNeverFoldsPinnedSeedlings() {
        let survivor = seedling("Box breathing", items: [item("e-1")])
        let pinned = seedling("Breathing", items: [item("e-2")], pinned: true)
        let tidied = ConceptSeedbedReducer.applyTidy(
            [survivor, pinned],
            assignments: [assignment("Box breathing", extracts: ["e-1", "e-2"])],
            extracts: [],
            sessionUUID: "s-1"
        )
        XCTAssertEqual(tidied.count, 2)
    }

    func testTidyLeavesUnseenSeedlingsAlone() {
        // A seedling whose items the resolver never saw must not fold or vanish.
        let unseen = seedling("CO2 tolerance", items: [item("e-9", session: "s-0")])
        let tidied = ConceptSeedbedReducer.applyTidy(
            [unseen],
            assignments: [assignment("Box breathing", extracts: ["e-1"])],
            extracts: [extractAtom("e-1", body: "Four counts in, four counts out")],
            sessionUUID: "s-1"
        )
        XCTAssertTrue(tidied.contains { $0.conceptKey == "co2 tolerance" })
        XCTAssertEqual(tidied.first { $0.conceptKey == "co2 tolerance" }?.stagedItems.count, 1)
    }

    func testTidyRespectsDismissedSeedlings() {
        let dismissed = seedling("Vagus nerve", items: [item("e-1")], status: .dismissed)
        let tidied = ConceptSeedbedReducer.applyTidy(
            [dismissed],
            assignments: [assignment("Vagus nerve", extracts: ["e-1", "e-2"])],
            extracts: [extractAtom("e-2", body: "New material")],
            sessionUUID: "s-1"
        )
        XCTAssertEqual(tidied.first?.stagedItems.count, 1)
        XCTAssertEqual(tidied.first?.status, .dismissed)
    }

    // MARK: - Decode back-compat

    func testDeepDiveStructuredDecodesWithoutSeedbedKey() throws {
        // A pre-seedbed blob is exactly today's encoding minus the new key.
        let modern = DeepDiveStructured(
            currentUnderstanding: CurrentUnderstanding(oneSentenceModel: "Breath is a lever."),
            conceptSeedbed: [seedling("Vagus nerve", items: [item("e-1")])]
        )
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(modern)) as! [String: Any]
        json.removeValue(forKey: "conceptSeedbed")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DeepDiveStructured.self, from: legacy)
        XCTAssertEqual(decoded.currentUnderstanding.oneSentenceModel, "Breath is a lever.")
        XCTAssertTrue(decoded.conceptSeedbed.isEmpty)
    }

    func testSeedbedRoundTripsThroughCoding() throws {
        let structured = DeepDiveStructured(conceptSeedbed: [
            seedling("Vagus nerve", items: [item("e-1"), item("e-2", consumed: true)])
        ])
        let data = try JSONEncoder().encode(structured)
        let decoded = try JSONDecoder().decode(DeepDiveStructured.self, from: data)
        XCTAssertEqual(decoded.conceptSeedbed.count, 1)
        XCTAssertEqual(decoded.conceptSeedbed.first?.stagedItems.count, 2)
        XCTAssertEqual(decoded.conceptSeedbed.first?.pendingItems.count, 1)
    }
}
