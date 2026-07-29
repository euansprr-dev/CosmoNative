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

    // MARK: - Attach ladder (alias + token-subset before minting)

    func testAccrualFeedsExistingSeedlingThroughAlias() {
        var existing = seedling("Silence", items: [item("e-1")])
        existing.aliases = ["Strategic pause"]
        let result = ConceptSeedbedReducer.accrue([existing], entries: [
            entry(["Strategic pause"], extractUUID: "e-2")
        ])
        XCTAssertEqual(result.seedbed.count, 1)
        XCTAssertEqual(result.seedbed.first?.conceptKey, "silence")
        XCTAssertEqual(result.seedbed.first?.stagedItems.count, 2)
    }

    func testAccrualFeedsUniqueTokenSubsetInsteadOfMinting() {
        let existing = seedling("Silence", items: [item("e-1")])
        let result = ConceptSeedbedReducer.accrue([existing], entries: [
            entry(["Silence at the end of talking"], extractUUID: "e-2")
        ])
        XCTAssertEqual(result.seedbed.count, 1)
        XCTAssertEqual(result.seedbed.first?.conceptKey, "silence")
        XCTAssertEqual(result.seedbed.first?.stagedItems.count, 2)
        // The wording that arrived is recorded, so the next capture with that
        // phrasing resolves on the alias rung.
        XCTAssertEqual(result.seedbed.first?.aliases, ["Silence at the end of talking"])
    }

    func testAmbiguousSubsetMintsInsteadOfGuessing() {
        let a = seedling("Silence", items: [item("e-1")])
        let b = seedling("Talking", items: [item("e-2")])
        // "Silence while talking" subset-matches BOTH — ambiguity mints.
        let result = ConceptSeedbedReducer.accrue([a, b], entries: [
            entry(["Silence while talking"], extractUUID: "e-3")
        ])
        XCTAssertEqual(result.seedbed.count, 3)
        XCTAssertTrue(result.seedbed.contains { $0.conceptKey == "silence while talking" })
    }

    func testDismissedSeedlingDoesNotAttractSubsetMatches() {
        // Dismissing "Breathing" must not swallow "Box breathing".
        let dismissed = seedling("Breathing", items: [item("e-1")], status: .dismissed)
        let result = ConceptSeedbedReducer.accrue([dismissed], entries: [
            entry(["Box breathing"], extractUUID: "e-2")
        ])
        XCTAssertEqual(result.seedbed.count, 2)
        XCTAssertTrue(result.seedbed.contains { $0.conceptKey == "box breathing" })
    }

    func testSubsetFeedDoesNotStealMergeTargetPage() {
        let existing = seedling("Breathing", items: [item("e-1")])
        let result = ConceptSeedbedReducer.accrue(
            [existing],
            entries: [entry(["Box breathing"], extractUUID: "e-2")],
            existingPageUUIDsByKey: ["box breathing": "conn-1"]
        )
        XCTAssertEqual(result.seedbed.count, 1)
        XCTAssertNil(result.seedbed.first?.mergeTargetConnectionUUID)
    }

    func testAliasFeedReportsRipenessUnderTheSeedlingsOwnKey() {
        var existing = seedling("Silence", items: [
            item("e-1", session: "s-0"), item("e-2", session: "s-0"), item("e-3", session: "s-0")
        ])
        existing.aliases = ["Strategic pause"]
        let result = ConceptSeedbedReducer.accrue([existing], entries: [
            entry(["Strategic pause"], extractUUID: "e-4", session: "s-1")
        ])
        XCTAssertEqual(result.newlyRipeKeys, ["silence"])
    }

    // MARK: - Sprout tier

    func testSproutTierDerivation() {
        XCTAssertTrue(seedling("Pitch", items: [item("e-1")]).isSprout)
        XCTAssertFalse(seedling("Pitch", items: [item("e-1"), item("e-2")]).isSprout)
        XCTAssertFalse(seedling("Pitch", items: [item("e-1")], pinned: true).isSprout)
        var pageTied = seedling("Pitch", items: [item("e-1")])
        pageTied.mergeTargetConnectionUUID = "conn-1"
        XCTAssertFalse(pageTied.isSprout)
        var developed = seedling("Pitch", items: [item("e-1")], status: .developed)
        developed.developedConnectionUUID = "conn-2"
        XCTAssertFalse(developed.isSprout)
    }

    // MARK: - Tidy: alias-declared folds

    func testTidyFoldsSeedlingDeclaredAsAliasRegardlessOfItemCoverage() {
        // The resolver named "Silence" and declared "Silence at the end of
        // talking" one of its aliases. The rival seedling folds even though
        // its item (e-9) appears in NO assignment.
        let survivor = seedling("Silence", items: [item("e-1")])
        let rival = seedling("Silence at the end of talking", items: [item("e-9")])
        let tidied = ConceptSeedbedReducer.applyTidy(
            [survivor, rival],
            assignments: [assignment(
                "Silence",
                extracts: ["e-1"],
                aliases: ["Silence at the end of talking"]
            )],
            extracts: [],
            sessionUUID: "s-1"
        )
        XCTAssertEqual(tidied.count, 1)
        XCTAssertEqual(tidied.first?.conceptKey, "silence")
        XCTAssertEqual(Set(tidied.first?.stagedItems.map(\.sourceExtractUUID) ?? []), ["e-1", "e-9"])
        XCTAssertTrue(tidied.first?.aliases.contains("Silence at the end of talking") ?? false)
    }

    // MARK: - Reconciliation offers (debrief consolidation)

    func testEstablishedSeedlingWithReHomedMajorityBecomesAnOffer() {
        // Post-tidy bed: "Vocal delivery" (the survivor) and "Vocal register"
        // (2 items, both assigned to Vocal delivery, but NOT all its items
        // were seen so it did not silently fold — one item e-7 is unseen).
        let survivor = seedling("Vocal delivery", items: [item("e-1"), item("e-2")])
        let register = seedling("Vocal register", items: [item("e-3"), item("e-4"), item("e-7")])
        let offers = ConceptSeedbedReducer.reconciliationOffers(
            [survivor, register],
            assignments: [assignment("Vocal delivery", extracts: ["e-1", "e-2", "e-3", "e-4"])]
        )
        XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(offers.first?.seedlingKey, "vocal register")
        XCTAssertEqual(offers.first?.targetKey, "vocal delivery")
        XCTAssertEqual(offers.first?.targetName, "Vocal delivery")
        XCTAssertEqual(offers.first?.itemCount, 3)
    }

    func testSproutsAndPinnedAndResolverNamedSeedlingsAreNeverOffered() {
        let survivor = seedling("Vocal delivery", items: [item("e-1")])
        let sprout = seedling("Pace", items: [item("e-2")])
        let pinned = seedling("Prosody", items: [item("e-3"), item("e-4")], pinned: true)
        let named = seedling("Pitch", items: [item("e-5"), item("e-6")])
        let offers = ConceptSeedbedReducer.reconciliationOffers(
            [survivor, sprout, pinned, named],
            assignments: [
                assignment("Vocal delivery", extracts: ["e-1", "e-2", "e-3", "e-4", "e-5", "e-6"]),
                assignment("Pitch", extracts: ["e-5"])
            ]
        )
        XCTAssertTrue(offers.isEmpty)
    }

    func testOneStrayReHomedCaptureIsNotConsolidationEvidence() {
        let survivor = seedling("Vocal delivery", items: [item("e-1")])
        let hail = seedling("HAIL framework", items: [
            item("e-2"), item("e-3"), item("e-4"), item("e-5"), item("e-6")
        ])
        // Only 1 of HAIL's 5 captures was filed under Vocal delivery.
        let offers = ConceptSeedbedReducer.reconciliationOffers(
            [survivor, hail],
            assignments: [assignment("Vocal delivery", extracts: ["e-1", "e-2"])]
        )
        XCTAssertTrue(offers.isEmpty)
    }

    // MARK: - Fold (umbrella consolidation)

    func testFoldMergesMembersIntoUmbrellaWithAliasesAndRelated() {
        let pitch = seedling("Pitch", items: [item("e-1")])
        let pace = seedling("Pace", items: [item("e-2")])
        var prosody = seedling("Prosody", items: [item("e-3"), item("e-4")])
        prosody.aliases = ["Vocal melody"]
        let (folded, changed) = ConceptSeedbedReducer.foldSeedlings(
            [pitch, pace, prosody],
            umbrellaName: "Vocal delivery",
            memberKeys: ["pitch", "pace", "prosody"]
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(folded.count, 1)
        let umbrella = folded[0]
        XCTAssertEqual(umbrella.conceptKey, "vocal delivery")
        XCTAssertEqual(Set(umbrella.stagedItems.map(\.sourceExtractUUID)), ["e-1", "e-2", "e-3", "e-4"])
        XCTAssertEqual(Set(umbrella.aliases), ["Pitch", "Pace", "Prosody", "Vocal melody"])
        XCTAssertEqual(Set(umbrella.relatedConceptNames), ["Pitch", "Pace", "Prosody"])
        XCTAssertFalse(umbrella.isSprout)
    }

    func testFoldIntoExistingUmbrellaSeedlingKeepsItsIdentity() {
        var umbrella = seedling("Vocal delivery", items: [item("e-1")])
        umbrella.pinnedAt = ISO8601.string(from: Date())
        let pitch = seedling("Pitch", items: [item("e-2")])
        let (folded, changed) = ConceptSeedbedReducer.foldSeedlings(
            [umbrella, pitch],
            umbrellaName: "Vocal delivery",
            memberKeys: ["pitch"]
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(folded.count, 1)
        XCTAssertNotNil(folded.first?.pinnedAt)   // The umbrella's own pin survives.
        XCTAssertEqual(folded.first?.stagedItems.count, 2)
    }

    func testFoldNeverTouchesPinnedDevelopedOrPageTiedMembers() {
        let pinned = seedling("Pitch", items: [item("e-1")], pinned: true)
        var developed = seedling("Pace", items: [item("e-2")], status: .developed)
        developed.developedConnectionUUID = "conn-1"
        var pageTied = seedling("Prosody", items: [item("e-3")])
        pageTied.mergeTargetConnectionUUID = "conn-2"
        let (folded, changed) = ConceptSeedbedReducer.foldSeedlings(
            [pinned, developed, pageTied],
            umbrellaName: "Vocal delivery",
            memberKeys: ["pitch", "pace", "prosody"]
        )
        // Nothing foldable: the original bed comes back untouched — no empty
        // umbrella sprout is left behind.
        XCTAssertFalse(changed)
        XCTAssertEqual(folded.count, 3)
        XCTAssertFalse(folded.contains { $0.conceptKey == "vocal delivery" })
    }

    func testDebriefOfferAcceptIsASingleMemberFold() {
        let target = seedling("Vocal delivery", items: [item("e-1")])
        let register = seedling("Vocal register", items: [item("e-2"), item("e-3")])
        let (folded, changed) = ConceptSeedbedReducer.foldSeedlings(
            [target, register],
            umbrellaName: "Vocal delivery",
            memberKeys: ["vocal register"]
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded.first?.stagedItems.count, 3)
        XCTAssertTrue(folded.first?.aliases.contains("Vocal register") ?? false)
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

// MARK: - Unified-store adapters (July 2026)

/// The dive seedbed's storage moved onto the global `seedlings` table; these
/// lock the boundary: a round trip through the row loses NOTHING — item ids,
/// extract/session provenance, section hints, pins, merge targets, statuses.
extension ConceptSeedbedTests {

    private func richSeedling() -> IncubatingConcept {
        var concept = IncubatingConcept(
            conceptKey: "vagal tone",
            name: "Vagal tone",
            aliases: ["Vagus tone"],
            parentConceptName: "Breathwork",
            relatedConceptNames: ["HRV"],
            stagedItems: [
                StagedConceptItem(
                    id: "item-1",
                    sourceExtractUUID: "e-1",
                    rawSnippet: "Slow exhales raise vagal tone",
                    proposedSection: ConnectionSectionType.evidence.rawValue,
                    sourceUUID: "source-9",
                    sessionUUID: "s-1",
                    capturedAt: "2026-07-01T09:00:00Z"
                ),
                StagedConceptItem(
                    id: "item-2",
                    sourceExtractUUID: "e-2",
                    rawSnippet: "HRV rises with vagal tone",
                    sessionUUID: "s-2",
                    capturedAt: "2026-07-02T09:00:00Z",
                    consumedAt: "2026-07-03T09:00:00Z"
                ),
            ],
            status: .incubating,
            mergeTargetConnectionUUID: "conn-3",
            pinnedAt: "2026-07-04T09:00:00Z",
            createdAt: "2026-07-01T08:00:00Z",
            lastTouchedAt: "2026-07-02T09:00:00Z"
        )
        concept.developedConnectionUUID = nil
        return concept
    }

    func testIncubatingConceptRoundTripsThroughSeedlingRow() {
        let original = richSeedling()
        let row = Seedling.fromIncubating(original, scopeDeepDiveUUID: "dive-1")
        XCTAssertEqual(row.scopeDeepDiveUUID, "dive-1")
        XCTAssertEqual(row.status, .growing)
        XCTAssertEqual(row.createdAt, original.createdAt)

        let back = IncubatingConcept(row: row)
        XCTAssertEqual(back, original)
    }

    func testStatusMappingCoversAllCases() {
        var concept = richSeedling()

        concept.status = .developed
        concept.developedConnectionUUID = "conn-7"
        var row = Seedling.fromIncubating(concept, scopeDeepDiveUUID: "dive-1")
        XCTAssertEqual(row.status, .developed)
        XCTAssertEqual(IncubatingConcept(row: row).status, .developed)
        XCTAssertEqual(IncubatingConcept(row: row).developedConnectionUUID, "conn-7")

        concept.status = .dismissed
        row = Seedling.fromIncubating(concept, scopeDeepDiveUUID: "dive-1")
        XCTAssertEqual(row.status, .folded)
        XCTAssertEqual(IncubatingConcept(row: row).status, .dismissed)
    }

    func testStudyThoughtCarriesResearchProvenance() {
        let item = StagedConceptItem(
            id: "item-1",
            sourceExtractUUID: "e-1",
            rawSnippet: "text",
            proposedSection: "evidence",
            sourceUUID: "source-9",
            sessionUUID: "s-1"
        )
        let thought = item.asThought
        XCTAssertEqual(thought.sourceKind, .study)
        XCTAssertEqual(thought.sourceExtractUUID, "e-1")
        XCTAssertEqual(thought.sourceAtomUUID, "source-9")
        XCTAssertEqual(thought.proposedSection, "evidence")
        XCTAssertEqual(thought.sessionUUID, "s-1")
        XCTAssertNil(thought.sourceUUID)

        let back = StagedConceptItem(thought: thought)
        XCTAssertEqual(back, item)
    }

    func testDiveRipenessSurvivesTheRowRoundTrip() {
        // Four captures across two sessions is the dive ripeness rule —
        // sessionUUIDs must survive storage or ripeness silently breaks.
        let concept = seedling("Vagus nerve", items: [
            item("e-1", session: "s-0"), item("e-2", session: "s-0"),
            item("e-3", session: "s-1"), item("e-4", session: "s-1")
        ])
        let back = IncubatingConcept(row: .fromIncubating(concept, scopeDeepDiveUUID: "dive-1"))
        XCTAssertTrue(ConceptRipeness.evaluate(back).isRipe)
    }
}
