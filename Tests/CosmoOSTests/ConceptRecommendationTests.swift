// Tests for the Material rail's pure logic: the readiness gate, the evolving
// "seeking" ladder, intent-query assembly, provenance exclusions, and the
// diversity-guarded ranking. No DB, no embeddings — deterministic pieces only.

import Testing
import Foundation
@testable import CosmoOS

struct ConceptRecommendationTests {

    // MARK: - Fixtures

    private func state(
        goal: [String] = [],
        problems: [String] = [],
        claims: [String] = [],
        evidence: [String] = [],
        objections: [String] = [],
        examples: [String] = [],
        process: [String] = [],
        openQuestions: [String] = []
    ) -> ConnectionFocusModeState {
        var state = ConnectionFocusModeState(atomUUID: "concept-1")
        func fill(_ type: ConnectionSectionType, _ texts: [String]) {
            for text in texts {
                state.addItem(ConnectionItem(content: text), toSection: type)
            }
        }
        fill(.goal, goal)
        fill(.problems, problems)
        fill(.claims, claims)
        fill(.evidence, evidence)
        fill(.beliefsObjections, objections)
        fill(.examples, examples)
        fill(.process, process)
        fill(.openQuestions, openQuestions)
        return state
    }

    private func snapshot(
        title: String = "Attention Residue",
        state: ConnectionFocusModeState,
        linked: Set<String> = []
    ) -> ConceptRecommendationSnapshot {
        ConceptRecommendationSnapshot(
            atomUUID: "concept-1",
            title: title,
            conceptType: .mentalModel,
            state: state,
            linkedUUIDs: linked
        )
    }

    private func rec(
        _ id: String,
        origin: ConceptRecommendationOrigin,
        score: Double
    ) -> ConceptRecommendation {
        ConceptRecommendation(
            id: id,
            origin: origin,
            title: id,
            excerpt: "excerpt",
            detail: nil,
            score: score,
            atomUUID: nil,
            inboxItemUUID: nil,
            suggestedSection: .evidence
        )
    }

    // MARK: - Gate

    @Test func emptyConceptStaysDormantAskingForGoal() {
        #expect(ConceptRecommendationGate.evaluate(state: state()) == .needsGoal)
    }

    @Test func goalAloneAsksForOneMoreThought() {
        let s = state(goal: ["Protect deep work blocks"])
        #expect(ConceptRecommendationGate.evaluate(state: s) == .needsMoreMaterial)
    }

    @Test func goalPlusSecondItemUnlocks() {
        let s = state(goal: ["Protect deep work blocks"], claims: ["Switching costs are real"])
        #expect(ConceptRecommendationGate.evaluate(state: s) == .ready)
    }

    @Test func goallessConceptUnlocksOnMass() {
        let s = state(problems: ["d"], claims: ["a", "b"], examples: ["c"])
        #expect(ConceptRecommendationGate.evaluate(state: s) == .ready)
    }

    @Test func goallessConceptBelowMassStaysDormant() {
        let s = state(claims: ["a", "b"], examples: ["c"])
        #expect(ConceptRecommendationGate.evaluate(state: s) == .needsGoal)
    }

    // MARK: - Seeking ladder (the evolution driver)

    @Test func goalFilledSeeksClaims() {
        let s = state(goal: ["g"])
        #expect(ConceptRecommendationModel.seekingSection(in: s) == .claims)
    }

    @Test func claimsFilledSeeksEvidence() {
        let s = state(goal: ["g"], claims: ["c"])
        #expect(ConceptRecommendationModel.seekingSection(in: s) == .evidence)
    }

    @Test func evidenceFilledSeeksTheCounterargument() {
        let s = state(goal: ["g"], claims: ["c"], evidence: ["e"])
        #expect(ConceptRecommendationModel.seekingSection(in: s) == .beliefsObjections)
    }

    @Test func objectionsFilledSeeksExamples() {
        let s = state(goal: ["g"], claims: ["c"], evidence: ["e"], objections: ["o"])
        #expect(ConceptRecommendationModel.seekingSection(in: s) == .examples)
    }

    @Test func saturatedConceptSeeksNothing() {
        let s = state(
            goal: ["g"], problems: ["p"], claims: ["c"], evidence: ["e"],
            objections: ["o"], examples: ["x"], process: ["s"], openQuestions: ["q"]
        )
        #expect(ConceptRecommendationModel.seekingSection(in: s) == nil)
    }

    // MARK: - Intent query

    @Test func intentQueryCarriesTitleGoalClaimsAndSeek() {
        let s = state(goal: ["Protect deep work blocks"], claims: ["Switching costs compound"])
        let query = ConceptRecommendationModel.intentQuery(
            snapshot: snapshot(state: s),
            seeking: .evidence
        )
        #expect(query.contains("Attention Residue"))
        #expect(query.contains("Protect deep work blocks"))
        #expect(query.contains("Switching costs compound"))
        #expect(query.contains(ConnectionSectionType.evidence.promptQuestion))
    }

    @Test func intentQueryDedupesRepeatedTextAndCapsLength() {
        let long = String(repeating: "attention residue theory ", count: 80)
        let s = state(goal: [long, long], claims: [long])
        let query = ConceptRecommendationModel.intentQuery(
            snapshot: snapshot(state: s),
            seeking: nil
        )
        #expect(query.count <= 900)
    }

    @Test func keyPhraseInputsUseTitleConceptNameAndGoal() {
        var s = state(goal: ["Guard the first hour"])
        s.addItem(ConnectionItem(content: "Residue-Free Switching"), toSection: .conceptName)
        let keys = ConceptRecommendationModel.keyPhraseInputs(snapshot: snapshot(state: s))
        #expect(keys.name == "Attention Residue")
        #expect(keys.aliases.contains("Residue-Free Switching"))
        #expect(keys.aliases.contains("Guard the first hour"))
    }

    // MARK: - Exclusions

    @Test func excludedUUIDsCoverSelfLinksAndProvenance() {
        var s = state(goal: ["g"])
        s.addItem(
            ConnectionItem(content: "from a source", sourceAtomUUID: "source-9"),
            toSection: .evidence
        )
        s.addItem(
            ConnectionItem(content: "Sibling page", linkedConnectionUUID: "concept-7"),
            toSection: .references
        )
        let excluded = ConceptRecommendationModel.excludedUUIDs(
            snapshot: snapshot(state: s, linked: ["well-3"])
        )
        #expect(excluded.contains("concept-1"))   // self
        #expect(excluded.contains("source-9"))    // item provenance
        #expect(excluded.contains("concept-7"))   // reference link
        #expect(excluded.contains("well-3"))      // linked well source
    }

    // MARK: - Ranking

    @Test func rankOrdersByScoreAndCapsPerOrigin() {
        let candidates = [
            rec("b1", origin: .book, score: 0.9),
            rec("b2", origin: .book, score: 0.8),
            rec("b3", origin: .book, score: 0.7),
            rec("b4", origin: .book, score: 0.6),
            rec("n1", origin: .note, score: 0.5),
        ]
        let ranked = ConceptRecommendationModel.rank(candidates, originCap: 3, totalCap: 9)
        #expect(ranked.map(\.id) == ["b1", "b2", "b3", "n1"])
    }

    @Test func rankDedupesSharedIdsAndHonorsTotalCap() {
        let candidates = [
            rec("x", origin: .book, score: 0.9),
            rec("x", origin: .research, score: 0.85),
            rec("y", origin: .inquiry, score: 0.8),
            rec("z", origin: .inbox, score: 0.7),
        ]
        let ranked = ConceptRecommendationModel.rank(candidates, originCap: 3, totalCap: 2)
        #expect(ranked.map(\.id) == ["x", "y"])
        #expect(ranked.first?.origin == .book)
    }

    // MARK: - Inbox scoring through the shared phrase matcher

    @Test func inboxCaptureMatchingConceptWordsClearsTheFloor() {
        let keys = ReadwiseEvidenceMatcher.keyPhrases(
            conceptName: "Attention Residue",
            aliases: []
        )
        let hit = ReadwiseEvidenceMatcher.score(
            highlight: ReadwiseMirrorHighlight(
                id: "i1",
                text: "Noticed my attention residue lingering after every Slack check today."
            ),
            bookTitleNormalized: "",
            keys: keys
        )
        let miss = ReadwiseEvidenceMatcher.score(
            highlight: ReadwiseMirrorHighlight(id: "i2", text: "Buy oat milk and book flights."),
            bookTitleNormalized: "",
            keys: keys
        )
        #expect(hit >= ReadwiseEvidenceMatcher.scoreFloor)
        #expect(miss < ReadwiseEvidenceMatcher.scoreFloor)
    }
}
