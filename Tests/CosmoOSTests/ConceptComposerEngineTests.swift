// Tests for ConceptComposerEngine.parseComposition — the pure JSON → drafts step
// that cleans, splits, content-routes, and provenance-tags a concept's captures —
// and for the split-safe dedup in ConnectionPromotionService.mergedSections.

import Testing
import Foundation
@testable import CosmoOS

struct ConceptComposerEngineTests {

    private func unit(
        _ index: Int,
        _ raw: String,
        section: ConnectionSectionType = .claims,
        kind: String = "Note",
        extractUUID: String? = nil,
        sourceUUID: String? = nil
    ) -> ConceptComposerEngine.MaterialUnit {
        ConceptComposerEngine.MaterialUnit(
            index: index,
            rawBody: raw,
            currentSection: section,
            kindHint: kind,
            originExtractUUID: extractUUID ?? "extract-\(index)",
            sourceUUID: sourceUUID ?? "source-\(index)"
        )
    }

    // MARK: - Split + route + provenance

    @Test func splitsOneCaptureAcrossSectionsWithProvenance() throws {
        let units = [unit(0, "the mind loves to judge things with zero experience, and being open-minded is the answer", section: .beliefsObjections)]
        let json = """
        {"bullets":[
          {"text":"The mind judges things prematurely, especially with zero experience.","section":"problems","sourceIndex":0},
          {"text":"Being radically open-minded is the answer.","section":"claims","sourceIndex":0}
        ]}
        """
        let sections = try #require(ConceptComposerEngine.parseComposition(raw: json, units: units))

        #expect(sections[.problems]?.count == 1)
        #expect(sections[.claims]?.count == 1)
        // Both split bullets keep the origin extract + the raw capture as provenance.
        let problem = try #require(sections[.problems]?.first)
        #expect(problem.originExtractUUID == "extract-0")
        #expect(problem.sourceUUID == "source-0")
        #expect(problem.rawSnippet == units[0].rawBody)
        #expect(sections[.claims]?.first?.rawSnippet == units[0].rawBody)
    }

    @Test func stripsEmDashesFromComposedBullets() throws {
        let units = [unit(0, "raw")]
        let json = #"{"bullets":[{"text":"doing one thing — fully — is calm","section":"claims","sourceIndex":0}]}"#
        let sections = try #require(ConceptComposerEngine.parseComposition(raw: json, units: units))
        #expect(sections[.claims]?.first?.body == "doing one thing, fully, is calm")
    }

    @Test func invalidSectionFallsBackToUnitSection() throws {
        let units = [unit(0, "raw", section: .evidence)]
        let json = #"{"bullets":[{"text":"a finding","section":"nonsense","sourceIndex":0}]}"#
        let sections = try #require(ConceptComposerEngine.parseComposition(raw: json, units: units))
        #expect(sections[.evidence]?.count == 1)
    }

    @Test func conceptNameAndReferencesTargetsAreRemappedOffLimits() throws {
        let units = [unit(0, "raw", section: .claims)]
        let json = #"{"bullets":[{"text":"x","section":"references","sourceIndex":0},{"text":"y","section":"conceptName","sourceIndex":0}]}"#
        let sections = try #require(ConceptComposerEngine.parseComposition(raw: json, units: units))
        #expect(sections[.references] == nil)
        #expect(sections[.conceptName] == nil)
        #expect(sections[.claims]?.count == 2)
    }

    @Test func returnsNilOnEmptyOrInvalidJSON() {
        let units = [unit(0, "raw")]
        #expect(ConceptComposerEngine.parseComposition(raw: "not json", units: units) == nil)
        #expect(ConceptComposerEngine.parseComposition(raw: #"{"bullets":[]}"#, units: units) == nil)
    }

    @Test func stripsMarkdownFencesBeforeParsing() throws {
        let units = [unit(0, "raw")]
        let json = "```json\n{\"bullets\":[{\"text\":\"a claim\",\"section\":\"claims\",\"sourceIndex\":0}]}\n```"
        let sections = try #require(ConceptComposerEngine.parseComposition(raw: json, units: units))
        #expect(sections[.claims]?.first?.body == "a claim")
    }

    // MARK: - Split-safe dedup

    @Test func mergedSectionsKeepsSplitBulletsSharingOneSourceUUID() {
        func section(_ type: ConnectionSectionType, _ items: [ConnectionItem]) -> ConnectionSection {
            var s = ConnectionSection(type: type)
            s.items = items
            return s
        }
        // Two distinct-content bullets from the SAME origin extract must both survive.
        let proposed = [
            section(.problems, [ConnectionItem(content: "The mind judges prematurely.", sourceAtomUUID: "extract-0")]),
            section(.claims, [ConnectionItem(content: "Open-mindedness is the answer.", sourceAtomUUID: "extract-0")])
        ]
        let merged = ConnectionPromotionService.mergedSections(existing: [], proposed: proposed)
        #expect(merged.first { $0.type == .problems }?.items.count == 1)
        #expect(merged.first { $0.type == .claims }?.items.count == 1)
    }

    @Test func mergedSectionsStillDedupsIdenticalContent() {
        func section(_ type: ConnectionSectionType, _ items: [ConnectionItem]) -> ConnectionSection {
            var s = ConnectionSection(type: type)
            s.items = items
            return s
        }
        let existing = [section(.claims, [ConnectionItem(content: "Same point.", sourceAtomUUID: "a")])]
        let proposed = [section(.claims, [ConnectionItem(content: "Same point.", sourceAtomUUID: "b")])]
        let merged = ConnectionPromotionService.mergedSections(existing: existing, proposed: proposed)
        #expect(merged.first { $0.type == .claims }?.items.count == 1)
    }
}
