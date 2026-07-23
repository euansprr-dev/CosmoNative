// Tests for the Material rail's pure logic: the readiness gate, the evolving
// "seeking" ladder, facet-query assembly, the rare-term gate, provenance
// exclusions and lineage overlap, weave linkification, diversity-guarded
// ranking, and the judge's prompt/parse contract. No DB, no embeddings, no
// network — deterministic pieces only.

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

    @Test func saturatedConceptSeeksNothing() {
        let s = state(
            goal: ["g"], problems: ["p"], claims: ["c"], evidence: ["e"],
            objections: ["o"], examples: ["x"], process: ["s"], openQuestions: ["q"]
        )
        #expect(ConceptRecommendationModel.seekingSection(in: s) == nil)
    }

    // MARK: - Facet queries

    @Test func identityFacetCarriesTitleConceptNameAndGoal() {
        var s = state(goal: ["Protect deep work blocks"])
        s.addItem(ConnectionItem(content: "Residue-Free Switching"), toSection: .conceptName)
        let identity = ConceptRecommendationModel.identityQuery(snapshot: snapshot(state: s))
        #expect(identity.contains("Attention Residue"))
        #expect(identity.contains("Residue-Free Switching"))
        #expect(identity.contains("Protect deep work blocks"))
    }

    @Test func momentumFacetCarriesClaimsButNoPromptBoilerplate() {
        let s = state(goal: ["g"], claims: ["Switching costs compound"])
        let momentum = ConceptRecommendationModel.momentumQuery(snapshot: snapshot(state: s))
        #expect(momentum.contains("Switching costs compound"))
        // Generic prompt questions poison embeddings — banned from queries.
        for section in ConnectionSectionType.allCases {
            #expect(!momentum.contains(section.promptQuestion))
        }
    }

    @Test func signatureTracksSeekTargetAndCapsFacets() {
        let long = String(repeating: "attention residue theory ", count: 80)
        let s = state(goal: [long], claims: [long])
        let sig = ConceptRecommendationModel.signature(snapshot: snapshot(state: s), seeking: .evidence)
        #expect(sig.contains("#seek:evidence"))
        #expect(sig.count <= 600 + 600 + 32)
    }

    // MARK: - Rare-term gate

    @Test func semanticConvictionBypassesTheGate() {
        #expect(ConceptRecommendationModel.passesRareTermGate(
            matchedText: "totally unrelated words",
            title: "Whatever",
            vectorSimilarity: 0.55,
            distinctiveTerms: ["residue"]
        ))
    }

    @Test func distinctiveTermHitPassesTheGate() {
        #expect(ConceptRecommendationModel.passesRareTermGate(
            matchedText: "the residue of prior tasks lingers",
            title: "Deep Work",
            vectorSimilarity: 0.35,
            distinctiveTerms: ["residue"]
        ))
    }

    @Test func commonWordsAloneFailTheGate() {
        // The Power User Guide case: matches only on corpus-common words.
        #expect(!ConceptRecommendationModel.passesRareTermGate(
            matchedText: "the inquiry tab gives you a session experience",
            title: "Cosmo Power User Guide",
            vectorSimilarity: 0.34,
            distinctiveTerms: ["residue"]
        ))
    }

    @Test func noDistinctiveVocabularyMeansVectorOnly() {
        #expect(!ConceptRecommendationModel.passesRareTermGate(
            matchedText: "anything at all",
            title: "Anything",
            vectorSimilarity: 0.45,
            distinctiveTerms: []
        ))
    }

    // MARK: - Exclusions & lineage

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

    @Test func overlapRatioFlagsEmbodiedMaterial() {
        let page = """
        Self-experimentation
        Every single thing must be verified by yourself, by your own direct \
        experience. You cannot take anyone else's word for how to live.
        """
        let embodied = "Every single thing must be verified by your own direct experience."
        let fresh = "Perception collapses possibility into a single observed outcome."
        #expect(ConceptRecommendationModel.overlapRatio(of: embodied, within: page) >= 0.6)
        #expect(ConceptRecommendationModel.overlapRatio(of: fresh, within: page) < 0.3)
    }

    // MARK: - Weave linkification

    @Test func linkifiedWeaveTurnsKnownTitlesIntoMentions() {
        let parsed = ConceptRecommendationModel.linkified(
            text: "Self-experimentation is the only path; direct experience decides.",
            targets: [
                (uuid: "page-self-experimentation", title: "Self-experimentation"),
                (uuid: "page-direct-experience", title: "Direct experience"),
            ]
        )
        let mentions = parsed.mentions
        #expect(mentions.count == 2)
        #expect(mentions.contains { $0.entityUUID == "page-self-experimentation" })
        #expect(mentions.contains { $0.entityUUID == "page-direct-experience" })
        // Prose casing survives — the pill snapshots the matched words.
        #expect(mentions.contains { $0.titleSnapshot == "direct experience" })
    }

    @Test func linkificationRespectsWordBoundaries() {
        let parsed = ConceptRecommendationModel.linkified(
            text: "Restarting means restart, not art.",
            targets: [(uuid: "page-art-00000001", title: "art")]
        )
        // "art" is under the 4-char floor AND inside other words — no links.
        #expect(parsed.mentions.isEmpty)
    }

    @Test func linkificationOnlyClaimsFirstOccurrence() {
        let parsed = ConceptRecommendationModel.linkified(
            text: "Direct experience first; direct experience second.",
            targets: [(uuid: "page-direct-experience", title: "Direct experience")]
        )
        #expect(parsed.mentions.count == 1)
    }

    @Test func wholePhraseRangeRejectsEmbeddedMatches() {
        #expect(ConceptRecommendationModel.wholePhraseRange(of: "habit", in: "they inhabit caves") == nil)
        #expect(ConceptRecommendationModel.wholePhraseRange(of: "habit", in: "a habit forms") != nil)
    }

    // MARK: - Matched-phrase receipt

    @Test func containedPhraseNamesTheMatch() {
        let keys = ReadwiseEvidenceMatcher.keyPhrases(conceptName: "Attention Residue", aliases: [])
        let phrase = ConceptRecommendationModel.containedPhrase(
            in: "Notice the attention residue after each context switch.",
            keys: keys
        )
        #expect(phrase == "attention residue")
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

    @Test func weaveBoostsLiftTaughtOriginsWithinACap() {
        let candidates = [
            rec("n1", origin: .note, score: 0.50),
            rec("q1", origin: .inquiry, score: 0.46),
        ]
        // Ten weaves cap at +15% — inquiry (0.46 → 0.529) overtakes the note.
        let ranked = ConceptRecommendationModel.rank(
            candidates, originCap: 3, totalCap: 9,
            weaveBoosts: [ConceptRecommendationOrigin.inquiry.rawValue: 10]
        )
        #expect(ranked.map(\.id) == ["q1", "n1"])
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

    // MARK: - Judge contract

    private var judgeCandidates: [ConceptRecommendationJudge.Candidate] {
        [
            .init(rowID: "atom:aaa", originLabel: "Book", title: "Deep Work", excerpt: "Residue lingers."),
            .init(rowID: "atom:bbb", originLabel: "Note", title: "API's", excerpt: "Endpoints worth adding."),
        ]
    }

    @Test func judgeParseMapsAliasesSectionsAndCoverage() {
        let aliases = ConceptRecommendationJudge.aliasMap(for: judgeCandidates)
        let linked = ConceptRecommendationJudge.linkedAliasMap(for: [(uuid: "page-self-experimentation", title: "Self-experimentation")])
        let raw = """
        Here is my ruling:
        {"keep":[{"id":"m1","section":"evidence","why":"Shows residue empirically."}],
         "covered":[{"id":"m2","by":"r1"}]}
        """
        let rulings = ConceptRecommendationJudge.parse(raw, aliases: aliases, linkedAliases: linked)
        #expect(rulings?.count == 2)
        #expect(rulings?[0].rowID == "atom:aaa")
        #expect(rulings?[0].section == .evidence)
        #expect(rulings?[0].why == "Shows residue empirically.")
        #expect(rulings?[1].rowID == "atom:bbb")
        #expect(rulings?[1].coveredByUUID == "page-self-experimentation")
    }

    @Test func judgeParseReturnsNilOnGarbageAndSkipsUnknownAliases() {
        let aliases = ConceptRecommendationJudge.aliasMap(for: judgeCandidates)
        #expect(ConceptRecommendationJudge.parse("no json here", aliases: aliases, linkedAliases: [:]) == nil)
        let raw = #"{"keep":[{"id":"m9","section":"evidence","why":"ghost"}]}"#
        let rulings = ConceptRecommendationJudge.parse(raw, aliases: aliases, linkedAliases: [:])
        #expect(rulings?.isEmpty == true)
    }

    @Test func judgeEmptyKeepIsARealRuling() {
        let aliases = ConceptRecommendationJudge.aliasMap(for: judgeCandidates)
        let rulings = ConceptRecommendationJudge.parse(#"{"keep":[]}"#, aliases: aliases, linkedAliases: [:])
        #expect(rulings != nil)
        #expect(rulings?.isEmpty == true)
    }

    @Test func judgePromptCarriesDossierRulesAndAliases() {
        let dossier = ConceptRecommendationJudge.Dossier(
            title: "Experience & inquiry",
            typeName: "Mental Model",
            sections: [(name: "Goal", items: ["Understand experience as the ground of reality"])],
            seekingName: "Claims",
            linkedPages: [(uuid: "page-self-experimentation", title: "Self-experimentation")]
        )
        let aliases = ConceptRecommendationJudge.aliasMap(for: judgeCandidates)
        let linked = ConceptRecommendationJudge.linkedAliasMap(for: dossier.linkedPages)
        let prompt = ConceptRecommendationJudge.prompt(
            dossier: dossier, candidates: judgeCandidates, aliases: aliases, linkedAliases: linked
        )
        #expect(prompt.contains("Experience & inquiry"))
        #expect(prompt.contains("m1 [Book"))
        #expect(prompt.contains("m2 [Note"))
        #expect(prompt.contains("r1 · Self-experimentation"))
        #expect(prompt.contains("REJECT anything about operating software"))
        #expect(prompt.contains("\"keep\""))
    }
}
