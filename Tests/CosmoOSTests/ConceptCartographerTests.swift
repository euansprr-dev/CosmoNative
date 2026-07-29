import XCTest
import CoreGraphics
@testable import CosmoOS

/// The Cartographer's contracts: a calm map stays untouched, canvas clusters
/// become consent-only drafts, the validation ladder drops everything unsafe
/// (pins, cycles, unknowns, undersized groups), keys are rename-independent,
/// and the geometry/pruning helpers are deterministic.
final class ConceptCartographerTests: XCTestCase {

    private func fact(
        _ uuid: String,
        title: String,
        parent: String? = nil,
        pinned: Bool = false,
        section: Bool = false,
        notes: Int = 0
    ) -> ConceptCartographerSignals.ConceptFacts {
        ConceptCartographerSignals.ConceptFacts(
            uuid: uuid, title: title, parentUUID: parent,
            isPinned: pinned, isSection: section, noteCount: notes
        )
    }

    private func groupDraft(_ name: String, _ members: [String], reason: String = "r") -> ConceptCartographerSignals.Draft {
        .init(kind: .group(name: name, memberUUIDs: members), reason: reason)
    }

    private func nestDraft(_ child: String, _ parent: String, reason: String = "r") -> ConceptCartographerSignals.Draft {
        .init(kind: .nest(childUUID: child, parentUUID: parent), reason: reason)
    }

    private func foldDraft(_ umbrella: String, _ memberKeys: [String], reason: String = "r") -> ConceptCartographerSignals.Draft {
        .init(kind: .foldSeedlings(umbrellaName: umbrella, memberKeys: memberKeys), reason: reason)
    }

    private func seedlingFact(
        _ name: String,
        count: Int = 1,
        parent: String? = nil,
        pinned: Bool = false,
        foldable: Bool = true
    ) -> ConceptCartographerSignals.SeedlingFacts {
        ConceptCartographerSignals.SeedlingFacts(
            conceptKey: ConceptResolver.conceptKey(name),
            name: name,
            pendingCount: count,
            parentConceptName: parent,
            isPinned: pinned,
            isFoldable: foldable
        )
    }

    // MARK: - Gating

    func testSmallMapDoesNotWantOrganization() {
        let facts = (1...3).map { fact("c\($0)", title: "Concept \($0)", notes: 5) }
        XCTAssertFalse(ConceptCartographerSignals.wantsOrganization(facts: facts))
    }

    func testCrowdedTopLevelWantsOrganization() {
        let facts = (1...7).map { fact("c\($0)", title: "Concept \($0)", notes: 5) }
        XCTAssertTrue(ConceptCartographerSignals.wantsOrganization(facts: facts))
    }

    func testManyThinPillarsWantOrganization() {
        let facts = [
            fact("c1", title: "A", notes: 9),
            fact("c2", title: "B", notes: 1),
            fact("c3", title: "C", notes: 0),
            fact("c4", title: "D", notes: 1),
            fact("c5", title: "E", notes: 0)
        ]
        XCTAssertTrue(ConceptCartographerSignals.wantsOrganization(facts: facts))
    }

    func testNestedConceptsDoNotCount() {
        // 8 concepts but only 3 top-level — the map is already organized.
        var facts = (1...3).map { fact("c\($0)", title: "Concept \($0)", notes: 6) }
        facts += (4...8).map { fact("c\($0)", title: "Child \($0)", parent: "c1", notes: 6) }
        XCTAssertFalse(ConceptCartographerSignals.wantsOrganization(facts: facts))
    }

    // MARK: - Canvas cluster drafts

    func testCanvasClusterBecomesGroupDraft() {
        let drafts = ConceptCartographerSignals.clusterDrafts(
            facts: [],
            clusters: [.init(name: "Epistemics", memberConnectionUUIDs: ["b", "a"])]
        )
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.kind, .group(name: "Epistemics", memberUUIDs: ["a", "b"]))
    }

    func testSingletonAndUnnamedClustersAreIgnored() {
        let drafts = ConceptCartographerSignals.clusterDrafts(
            facts: [],
            clusters: [
                .init(name: "Solo", memberConnectionUUIDs: ["a"]),
                .init(name: "   ", memberConnectionUUIDs: ["a", "b"])
            ]
        )
        XCTAssertTrue(drafts.isEmpty)
    }

    // MARK: - Validation ladder

    func testValidGroupProposalKeyIsSortedAndRenameIndependent() {
        let facts = [
            fact("b", title: "Radical questioning"),
            fact("a", title: "Epistemic humility"),
            fact("z", title: "Flow state")
        ]
        let proposals = ConceptCartographerSignals.validated(
            [groupDraft("Epistemics", ["b", "a"])], facts: facts
        )
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.key, "cartographer.group:a~b")
        // A different name over the same members lands on the same key.
        let renamed = ConceptCartographerSignals.validated(
            [groupDraft("Epistemology", ["a", "b"])], facts: facts
        )
        XCTAssertEqual(renamed.first?.key, "cartographer.group:a~b")
    }

    func testPinnedAndNestedAndSectionMembersAreDropped() {
        let facts = [
            fact("a", title: "A"),
            fact("pinned", title: "P", pinned: true),
            fact("nested", title: "N", parent: "a"),
            fact("section", title: "S", section: true),
            fact("b", title: "B")
        ]
        let proposals = ConceptCartographerSignals.validated(
            [groupDraft("Group", ["a", "pinned", "nested", "section", "b"])], facts: facts
        )
        XCTAssertEqual(proposals.count, 1)
        guard case .group(_, let members)? = proposals.first?.kind else {
            return XCTFail("expected a group")
        }
        XCTAssertEqual(Set(members), ["a", "b"])
    }

    func testGroupBelowMinimumMembersIsDropped() {
        let facts = [fact("a", title: "A"), fact("pinned", title: "P", pinned: true)]
        let proposals = ConceptCartographerSignals.validated(
            [groupDraft("Group", ["a", "pinned"])], facts: facts
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testGroupNamedAfterExistingConceptConvertsToNests() {
        let facts = [
            fact("epistemics", title: "Epistemics"),
            fact("a", title: "Epistemic humility"),
            fact("b", title: "Radical questioning")
        ]
        let proposals = ConceptCartographerSignals.validated(
            [groupDraft("Epistemics", ["a", "b"])], facts: facts
        )
        XCTAssertEqual(proposals.count, 2)
        XCTAssertTrue(proposals.allSatisfy { proposal in
            if case .nest(_, let parent) = proposal.kind { return parent == "epistemics" }
            return false
        })
    }

    func testOverlappingGroupsLoseClaimedMembers() {
        let facts = [
            fact("a", title: "A"), fact("b", title: "B"),
            fact("c", title: "C"), fact("d", title: "D")
        ]
        let proposals = ConceptCartographerSignals.validated(
            [
                groupDraft("First", ["a", "b", "c"]),
                groupDraft("Second", ["c", "d"])   // c already claimed → below minimum
            ],
            facts: facts
        )
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.title, "First")
    }

    func testProposalCapHolds() {
        let facts = (1...12).map { fact("c\($0)", title: "Concept \($0)") }
        let drafts = [
            groupDraft("G1", ["c1", "c2"]),
            groupDraft("G2", ["c3", "c4"]),
            groupDraft("G3", ["c5", "c6"]),
            groupDraft("G4", ["c7", "c8"])
        ]
        XCTAssertEqual(
            ConceptCartographerSignals.validated(drafts, facts: facts).count,
            ConceptCartographerSignals.Thresholds.maxProposalsPerPass
        )
    }

    func testNestValidationDropsUnsafeDrafts() {
        let facts = [
            fact("a", title: "A"),
            fact("b", title: "B", parent: "a"),
            fact("pinned", title: "P", pinned: true),
            fact("section", title: "S", section: true)
        ]
        let proposals = ConceptCartographerSignals.validated(
            [
                nestDraft("a", "a"),          // self
                nestDraft("ghosty", "a"),     // unknown child
                nestDraft("a", "unknown"),    // unknown parent
                nestDraft("pinned", "a"),     // pinned child
                nestDraft("section", "a"),    // sections stay put
                nestDraft("b", "a"),          // already there
                nestDraft("a", "b")           // would cycle a → b → a
            ],
            facts: facts
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testValidNestSurvives() {
        let facts = [fact("a", title: "A"), fact("b", title: "B")]
        let proposals = ConceptCartographerSignals.validated(
            [nestDraft("b", "a")], facts: facts
        )
        XCTAssertEqual(proposals.first?.key, "cartographer.nest:b~a")
        XCTAssertEqual(proposals.first?.memberTitles, ["A"])
    }

    // MARK: - LLM parse

    func testParseDraftsMapsAliasesAndDropsUnknowns() {
        let raw = """
        {"proposals":[
          {"kind":"group","name":"Epistemics","members":["c1","c2"],"reason":"one territory"},
          {"kind":"group","name":"Bad","members":["c1","c9"],"reason":"unknown alias"},
          {"kind":"nest","child":"c3","parent":"c1","reason":"contained"},
          {"kind":"nest","child":"c9","parent":"c1","reason":"unknown child"},
          {"kind":"promote","name":"Nope"}
        ]}
        """
        let drafts = ConceptCartographer.parseDrafts(
            raw: raw,
            uuidByAlias: ["c1": "u1", "c2": "u2", "c3": "u3"]
        )
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].kind, .group(name: "Epistemics", memberUUIDs: ["u1", "u2"]))
        XCTAssertEqual(drafts[1].kind, .nest(childUUID: "u3", parentUUID: "u1"))
    }

    func testParseDraftsHandlesFencedJSONAndDefaultsReasons() {
        let raw = """
        ```json
        {"proposals":[{"kind":"nest","child":"c1","parent":"c2","reason":""}]}
        ```
        """
        let drafts = ConceptCartographer.parseDrafts(raw: raw, uuidByAlias: ["c1": "u1", "c2": "u2"])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertFalse(drafts[0].reason.isEmpty)
    }

    func testParseDraftsSurvivesGarbage() {
        XCTAssertTrue(ConceptCartographer.parseDrafts(raw: "not json", uuidByAlias: [:]).isEmpty)
        XCTAssertTrue(ConceptCartographer.parseDrafts(raw: "{\"proposals\":\"nope\"}", uuidByAlias: [:]).isEmpty)
    }

    // MARK: - Co-occurrence

    // MARK: - Seedling folds (umbrella consolidation)

    func testFragmentedSeedbedWantsConsolidation() {
        // The screenshot signature: many thin seedlings at once.
        let thin = ["Pitch", "Pace", "Prosody", "Vocal register"].map { seedlingFact($0, count: 1) }
        XCTAssertTrue(ConceptCartographerSignals.wantsSeedlingConsolidation(seedlings: thin))
        XCTAssertFalse(ConceptCartographerSignals.wantsSeedlingConsolidation(seedlings: Array(thin.prefix(3))))
        // Thick seedlings are established concepts, not fragmentation.
        let thick = ["A", "B", "C", "D"].map { seedlingFact($0, count: 5) }
        XCTAssertFalse(ConceptCartographerSignals.wantsSeedlingConsolidation(seedlings: thick))
    }

    func testParentFoldDraftsGroupSiblingsByResolverParent() {
        let seedlings = [
            seedlingFact("Pitch", parent: "Vocal delivery"),
            seedlingFact("Pace", parent: "Vocal delivery"),
            seedlingFact("Prosody", parent: "Vocal delivery"),
            seedlingFact("HAIL framework"),                        // No parent — untouched.
            seedlingFact("Silence", parent: "Vocal delivery", pinned: true)   // Pinned — never drafted.
        ]
        let drafts = ConceptCartographerSignals.parentFoldDrafts(seedlings: seedlings)
        XCTAssertEqual(drafts.count, 1)
        guard case .foldSeedlings(let umbrella, let members) = drafts[0].kind else {
            return XCTFail("expected a fold draft")
        }
        XCTAssertEqual(umbrella, "Vocal delivery")
        XCTAssertEqual(members, ["pace", "pitch", "prosody"])   // Sorted, pin excluded.
    }

    func testParentFoldDraftsIgnoreSelfParentAndSingletons() {
        let seedlings = [
            seedlingFact("Vocal delivery", parent: "Vocal delivery"),   // Self-parent never drafts.
            seedlingFact("Pitch", parent: "Articulation")               // A lone facet is no group.
        ]
        XCTAssertTrue(ConceptCartographerSignals.parentFoldDrafts(seedlings: seedlings).isEmpty)
    }

    func testFoldValidationDropsPinnedUnknownAndClaimedMembers() {
        let seedlings = [
            seedlingFact("Pitch"),
            seedlingFact("Pace"),
            seedlingFact("Prosody", pinned: true),
            seedlingFact("Vocal register", foldable: false)
        ]
        let proposals = ConceptCartographerSignals.validated(
            [
                foldDraft("Vocal delivery", ["pitch", "pace", "prosody", "vocal register", "unknown key"]),
                foldDraft("Delivery", ["pitch", "pace"])   // Members already claimed above.
            ],
            facts: [],
            seedlings: seedlings
        )
        XCTAssertEqual(proposals.count, 1)
        guard case .foldSeedlings(let umbrella, let members) = proposals[0].kind else {
            return XCTFail("expected a fold proposal")
        }
        XCTAssertEqual(umbrella, "Vocal delivery")
        XCTAssertEqual(members, ["pace", "pitch"])
        XCTAssertEqual(proposals[0].memberTitles.sorted(), ["Pace", "Pitch"])
    }

    func testFoldUmbrellaCollidingWithItsOnlyMemberIsDropped() {
        // "Silence" folding into "Silence" leaves one member — below minimum.
        let proposals = ConceptCartographerSignals.validated(
            [foldDraft("Silence", ["silence", "pace"])],
            facts: [],
            seedlings: [seedlingFact("Silence"), seedlingFact("Pace")]
        )
        XCTAssertTrue(proposals.isEmpty)
    }

    func testFoldKeyIsSortedAndStable() {
        XCTAssertEqual(
            ConceptCartographerProposal.foldKey(memberKeys: ["prosody", "pace", "pitch"]),
            "cartographer.fold:pace~pitch~prosody"
        )
    }

    func testParseDraftsMapsFoldAliasesAndDropsUnknowns() {
        let raw = """
        {"proposals":[
          {"kind":"fold","umbrella":"Vocal delivery","members":["s1","s2"],"reason":"facets of one topic"},
          {"kind":"fold","umbrella":"Ghost","members":["s9"],"reason":"unknown alias"},
          {"kind":"fold","umbrella":"","members":["s1"],"reason":"empty name"}
        ]}
        """
        let drafts = ConceptCartographer.parseDrafts(
            raw: raw,
            uuidByAlias: [:],
            seedlingKeyByAlias: ["s1": "pitch", "s2": "pace"]
        )
        XCTAssertEqual(drafts.count, 1)
        guard case .foldSeedlings(let umbrella, let members) = drafts[0].kind else {
            return XCTFail("expected a fold draft")
        }
        XCTAssertEqual(umbrella, "Vocal delivery")
        XCTAssertEqual(members, ["pitch", "pace"])
        XCTAssertEqual(drafts[0].reason, "facets of one topic")
    }

    func testCoOccurrencePairsAreCountedAndDeterministic() {
        let pairs = ConceptCartographerSignals.coOccurrencePairs(
            conceptNamesPerExtract: [
                ["Humility", "Questioning"],
                ["Humility", "Questioning"],
                ["Humility", "Flow"],
                ["Solo"]
            ],
            uuidByConceptKey: [
                ConceptResolver.conceptKey("Humility"): "h",
                ConceptResolver.conceptKey("Questioning"): "q",
                ConceptResolver.conceptKey("Flow"): "f",
                ConceptResolver.conceptKey("Solo"): "s"
            ],
            titleByUUID: ["h": "Humility", "q": "Questioning", "f": "Flow", "s": "Solo"]
        )
        XCTAssertEqual(pairs.first?.count, 2)
        XCTAssertEqual(Set([pairs.first?.a, pairs.first?.b].compactMap { $0 }), ["Humility", "Questioning"])
        XCTAssertEqual(pairs.count, 2)
    }

    // MARK: - Canvas geometry

    func testSectionClusterLayoutGeometry() {
        let layout = ConnectionPromotionService.sectionClusterLayout(
            memberCount: 3, center: CGPoint(x: 500, y: 400)
        )
        XCTAssertEqual(layout.memberFrames.count, 3)
        // No two member frames overlap.
        for (i, a) in layout.memberFrames.enumerated() {
            for (j, b) in layout.memberFrames.enumerated() where j > i {
                XCTAssertFalse(a.intersects(b), "frames \(i) and \(j) overlap")
            }
        }
        // The cluster wraps every member with padding, and the grid centers
        // on the requested point.
        for frame in layout.memberFrames {
            XCTAssertTrue(layout.clusterRect.contains(frame))
        }
        let union = layout.memberFrames.dropFirst().reduce(layout.memberFrames[0]) { $0.union($1) }
        XCTAssertEqual(union.midX, 500, accuracy: 0.5)
        XCTAssertEqual(union.midY, 400, accuracy: 0.5)
        // The section block seats fully above the cluster, inside the footprint.
        XCTAssertLessThanOrEqual(layout.sectionBlockOrigin.y + 220, layout.clusterRect.minY)
        XCTAssertTrue(layout.footprint.contains(layout.clusterRect))
        XCTAssertTrue(layout.footprint.contains(CGRect(origin: layout.sectionBlockOrigin, size: CGSize(width: 320, height: 220))))
    }

    // MARK: - Map pruning + ghosts

    func testPrunedFoldsChildrenAndCountsThem() {
        let root = MindMapNode(
            id: "root", kind: .root, title: "Topic",
            children: [
                MindMapNode(id: "a", kind: .coreConcept, title: "A", children: [
                    MindMapNode(id: "a1", kind: .childConcept, title: "A1"),
                    MindMapNode(id: "a2", kind: .childConcept, title: "A2", children: [
                        MindMapNode(id: "a2x", kind: .question, title: "Q")
                    ])
                ]),
                MindMapNode(id: "b", kind: .coreConcept, title: "B")
            ]
        )
        let pruned = MindMapBuilder.pruned(root: root, collapsed: ["a"])
        XCTAssertEqual(pruned.children.count, 2)
        XCTAssertTrue(pruned.children[0].children.isEmpty)
        XCTAssertEqual(pruned.children[0].collapsedCount, 3)
        XCTAssertEqual(pruned.children[1].collapsedCount, 0)
        // Not collapsed → untouched.
        let untouched = MindMapBuilder.pruned(root: root, collapsed: [])
        XCTAssertEqual(untouched.children[0].children.count, 2)
    }

    func testGhostProposalsLandBesideTheirFirstMember() {
        let graph = MindMapGraph(root: MindMapNode(
            id: "root", kind: .root, title: "Topic",
            children: [
                MindMapNode(id: "concept-x", kind: .coreConcept, title: "X", atomUUID: "x"),
                MindMapNode(id: "concept-y", kind: .coreConcept, title: "Y", atomUUID: "y"),
                MindMapNode(id: "concept-z", kind: .coreConcept, title: "Z", atomUUID: "z")
            ]
        ))
        let proposal = ConceptCartographerProposal(
            key: "cartographer.group:x~y",
            kind: .group(name: "Epistemics", memberUUIDs: ["y", "x"]),
            reason: "r", title: "Epistemics", memberTitles: ["Y", "X"]
        )
        let withGhosts = MindMapBuilder.addingGhostProposals(graph, proposals: [proposal])
        XCTAssertEqual(withGhosts.root.children.count, 4)
        let ghost = withGhosts.root.children[0]
        XCTAssertTrue(ghost.isGhost)
        XCTAssertTrue(ghost.isSection)
        XCTAssertEqual(ghost.proposalKey, "cartographer.group:x~y")
        XCTAssertEqual(withGhosts.ghostLinks.count, 2)
        XCTAssertEqual(Set(withGhosts.ghostLinks.map(\.toNodeId)), ["concept-x", "concept-y"])
    }

    func testGhostSkipsProposalsWhoseMembersAreOffTheMap() {
        let graph = MindMapGraph(root: MindMapNode(
            id: "root", kind: .root, title: "Topic",
            children: [MindMapNode(id: "concept-x", kind: .coreConcept, title: "X", atomUUID: "x")]
        ))
        let proposal = ConceptCartographerProposal(
            key: "cartographer.group:x~missing",
            kind: .group(name: "G", memberUUIDs: ["x", "missing"]),
            reason: "r", title: "G", memberTitles: ["X", "?"]
        )
        let withGhosts = MindMapBuilder.addingGhostProposals(graph, proposals: [proposal])
        XCTAssertEqual(withGhosts.root.children.count, 1)
        XCTAssertTrue(withGhosts.ghostLinks.isEmpty)
    }

    func testNestProposalsNeverBecomeGhosts() {
        let graph = MindMapGraph(root: MindMapNode(
            id: "root", kind: .root, title: "Topic",
            children: [
                MindMapNode(id: "concept-x", kind: .coreConcept, title: "X", atomUUID: "x"),
                MindMapNode(id: "concept-y", kind: .coreConcept, title: "Y", atomUUID: "y")
            ]
        ))
        let proposal = ConceptCartographerProposal(
            key: "cartographer.nest:x~y",
            kind: .nest(childUUID: "x", parentUUID: "y"),
            reason: "r", title: "X", memberTitles: ["Y"]
        )
        let withGhosts = MindMapBuilder.addingGhostProposals(graph, proposals: [proposal])
        XCTAssertEqual(withGhosts.root.children.count, 2)
        XCTAssertTrue(withGhosts.ghostLinks.isEmpty)
    }

    // MARK: - Copy micro-contracts

    func testNotesLabelSingular() {
        XCTAssertEqual(MindMapBuilder.notesLabel(1), "1 note")
        XCTAssertEqual(MindMapBuilder.notesLabel(2), "2 notes")
    }
}
