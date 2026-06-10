// Tests for ConnectionSurfaceSerializer and the ConnectionContextProvider
// apply path — the bridge between inline-assistant reviewed diffs and
// ConnectionFocusModeState sections.

import Testing
import Foundation
import SwiftUI
@testable import CosmoOS

@MainActor
struct ConnectionEditableSurfaceTests {

    // MARK: - Helpers

    private func makeSections(
        _ seed: [ConnectionSectionType: [String]] = [:]
    ) -> [ConnectionSection] {
        ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { type in
                var section = ConnectionSection(type: type)
                for text in seed[type] ?? [] {
                    section.addItem(ConnectionItem(content: text))
                }
                return section
            }
    }

    private func makeProvider(
        seed: [ConnectionSectionType: [String]] = [:]
    ) -> (provider: ConnectionContextProvider, viewModel: ConnectionFocusModeViewModel) {
        let atom = Atom.new(type: .connection, title: "Trust Loops")
        let viewModel = ConnectionFocusModeViewModel(atom: atom)
        viewModel.state.sections = makeSections(seed)
        let provider = ConnectionContextProvider(atom: atom, viewModel: viewModel)
        return (provider, viewModel)
    }

    private func items(
        _ viewModel: ConnectionFocusModeViewModel,
        _ type: ConnectionSectionType
    ) -> [String] {
        viewModel.state.section(for: type)?.items.map(\.resolvedPlainText) ?? []
    }

    private func operation(
        kind: CosmoAssistantProposalOperationKind,
        original: String?,
        proposed: String?,
        anchorID: String? = nil
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: kind,
            targetID: "test-target",
            anchorID: anchorID,
            originalText: original,
            proposedText: proposed,
            sourceHash: "stale-hash",
            rationale: "test"
        )
    }

    // MARK: - Serialization

    @Test func serializationRendersTitleTypeHeadersAndMarkers() {
        let model = ConnectionSurfaceSerializer.serialize(
            title: "Trust Loops",
            conceptType: .framework,
            sections: makeSections([.goal: ["Earn compounding trust"]])
        )

        #expect(model.text.hasPrefix("# Trust Loops\nType: Framework\n"))
        #expect(model.text.contains("\n## Goal\n- Earn compounding trust"))
        #expect(model.text.contains("\n## Problems\n(empty)"))

        let headerOrder = ConnectionSectionType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { model.text.range(of: "## \($0.displayName)\n")?.lowerBound }
        #expect(headerOrder.count == ConnectionSectionType.allCases.count)
        #expect(headerOrder == headerOrder.sorted())
    }

    @Test func serializationEmitsOneAnchorPerSectionPlusTitle() {
        let model = ConnectionSurfaceSerializer.serialize(
            title: "Trust Loops",
            conceptType: .mentalModel,
            sections: makeSections()
        )
        #expect(model.anchors.count == ConnectionSectionType.allCases.count + 1)
        #expect(model.anchors.first?.id == "title")

        for anchor in model.anchors.dropFirst() {
            let start = String.Index(utf16Offset: anchor.utf16Start, in: model.text)
            let end = String.Index(utf16Offset: anchor.utf16Start + anchor.utf16Length, in: model.text)
            let headerText = String(model.text[start..<end])
            #expect(headerText.hasPrefix("## "))
            #expect(headerText.contains(anchor.label))
        }
    }

    @Test func multiLineItemsUseContinuationIndentAndMapToSameItem() {
        let sections = makeSections([.process: ["Step one\nwith detail"]])
        let model = ConnectionSurfaceSerializer.serialize(
            title: "T",
            conceptType: .mentalModel,
            sections: sections
        )
        #expect(model.text.contains("\n- Step one\n  with detail"))

        let itemID = sections.first { $0.type == .process }!.items[0].id
        let itemLines = model.lines.filter {
            switch $0.kind {
            case .item(.process, let id), .itemContinuation(.process, let id):
                return id == itemID
            default:
                return false
            }
        }
        #expect(itemLines.count == 2)
    }

    // MARK: - parseItems

    @Test func parseItemsSplitsBulletsAndJoinsContinuations() {
        let items = ConnectionSurfaceSerializer.parseItems(
            from: "- first\n  more first\n- second",
            targetSection: .claims
        )
        #expect(items == ["first\nmore first", "second"])
    }

    @Test func parseItemsDropsTargetHeaderAndEmptyMarker() {
        let items = ConnectionSurfaceSerializer.parseItems(
            from: "## Claims\n(empty)\n- a claim",
            targetSection: .claims
        )
        #expect(items == ["a claim"])
    }

    @Test func parseItemsRejectsForeignSectionHeader() {
        let items = ConnectionSurfaceSerializer.parseItems(
            from: "- a claim\n## Evidence\n- some proof",
            targetSection: .claims
        )
        #expect(items == nil)
    }

    @Test func parseItemsTreatsPlainProseAsSingleItem() {
        let items = ConnectionSurfaceSerializer.parseItems(
            from: "Trust compounds across repeated interactions.",
            targetSection: .goal
        )
        #expect(items == ["Trust compounds across repeated interactions."])
    }

    // MARK: - Apply: insertion

    @Test func headerAnchoredInsertionLandsAtTopOfSection() async throws {
        let (provider, viewModel) = makeProvider(seed: [.claims: ["existing claim"]])
        let op = operation(
            kind: .textInsertion,
            original: "## Claims",
            proposed: "- new claim one\n- new claim two"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .claims) == ["new claim one", "new claim two", "existing claim"])
    }

    @Test func bulletAnchoredInsertionLandsAfterThatItem() async throws {
        let (provider, viewModel) = makeProvider(seed: [.evidence: ["first proof", "last proof"]])
        let op = operation(
            kind: .textInsertion,
            original: "- first proof",
            proposed: "- inserted proof"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .evidence) == ["first proof", "inserted proof", "last proof"])
    }

    @Test func anchorIDFallbackResolvesSectionWhenOriginalTextIsMissing() async throws {
        let (provider, viewModel) = makeProvider()
        let op = operation(
            kind: .textInsertion,
            original: "totally not in the document",
            proposed: "- seeded via anchor id",
            anchorID: "section:openQuestions"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .openQuestions) == ["seeded via anchor id"])
    }

    @Test func unanchoredInsertionConflictsInsteadOfGuessing() async throws {
        let (provider, viewModel) = makeProvider()
        let op = operation(
            kind: .textInsertion,
            original: "nowhere to be found",
            proposed: "- orphan item"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .conflicted)
        #expect(viewModel.state.totalItemCount == 0)
    }

    // MARK: - Apply: replacement

    @Test func itemReplacementEditsInPlace() async throws {
        let (provider, viewModel) = makeProvider(seed: [.goal: ["rough goal"]])
        let op = operation(
            kind: .textReplacement,
            original: "- rough goal",
            proposed: "- sharpened goal"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .goal) == ["sharpened goal"])
    }

    @Test func emptyReplacementDeletesTheItem() async throws {
        let (provider, viewModel) = makeProvider(seed: [.problems: ["keep me", "delete me"]])
        let op = operation(
            kind: .textReplacement,
            original: "- delete me",
            proposed: ""
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .problems) == ["keep me"])
    }

    @Test func replacingHeaderPlusEmptyMarkerInsertsItems() async throws {
        let (provider, viewModel) = makeProvider()
        let op = operation(
            kind: .textReplacement,
            original: "## Claims\n(empty)",
            proposed: "## Claims\n- the first claim"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .applied)
        #expect(items(viewModel, .claims) == ["the first claim"])
    }

    @Test func crossSectionReplacementConflicts() async throws {
        let (provider, viewModel) = makeProvider(seed: [.claims: ["a claim"]])
        let op = operation(
            kind: .textReplacement,
            original: "- a claim\n\n## Evidence\n(empty)",
            proposed: "- rewritten everything"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .conflicted)
        #expect(items(viewModel, .claims) == ["a claim"])
    }

    @Test func headerRenameConflicts() async throws {
        let (provider, _) = makeProvider()
        let op = operation(
            kind: .textReplacement,
            original: "## Open Questions",
            proposed: "## Burning Questions"
        )

        let result = try await provider.apply(operation: op)

        #expect(result.status == .conflicted)
    }

    // MARK: - Snapshot

    // MARK: - Masonry layout math (crash regression)

    /// SwiftUI probes Layouts with nil/.infinity width proposals; `Int(.inf)`
    /// is a runtime trap. These guard the board against that crash.
    @Test func masonryLayoutSurvivesNonFiniteWidthProposals() {
        let layout = ConnectionMasonryLayout()

        #expect(layout.columnCount(forWidth: .infinity) == 1)
        #expect(layout.columnCount(forWidth: .nan) == 1)
        #expect(layout.columnCount(forWidth: 0) == 1)
        #expect(layout.columnCount(forWidth: 300) == 1)
        #expect(layout.columnCount(forWidth: 1000) == 3)

        let idealWidth = layout.resolvedWidth(from: ProposedViewSize(width: .infinity, height: nil))
        #expect(idealWidth.isFinite)
        let unspecified = layout.resolvedWidth(from: ProposedViewSize(width: nil, height: nil))
        #expect(unspecified.isFinite)
        let narrow = layout.resolvedWidth(from: ProposedViewSize(width: 100, height: nil))
        #expect(narrow >= layout.minColumnWidth)
    }

    @Test func snapshotHashChangesWhenStateChanges() async throws {
        let (provider, viewModel) = makeProvider()
        let before = provider.editableSnapshot()

        viewModel.state.addItem(ConnectionItem(content: "new"), toSection: .goal)
        let after = provider.editableSnapshot()

        #expect(before.sourceHash != after.sourceHash)
        #expect(before.targetID == after.targetID)
        #expect(after.kind == .structured)
        #expect(after.surfaceID.hasPrefix("connection:"))
    }
}
