// CosmoOS/Tests/CosmoOSTests/ReadwiseMirrorTests.swift
// The Readwise mirror's contracts: the reducer upserts/prunes idempotently
// (re-running a full import changes nothing), and the evidence matcher only
// speaks when the concept's own words appear in a highlight — the "right
// concept, right time" guarantee is abstention-first.

import XCTest
@testable import CosmoOS

final class ReadwiseMirrorTests: XCTestCase {

    // MARK: - Fixtures

    private func exportHighlight(
        id: Int,
        text: String,
        note: String? = nil,
        location: Int? = nil,
        tags: [String] = [],
        isDiscard: Bool = false,
        isDeleted: Bool = false
    ) -> ReadwiseExportHighlight {
        ReadwiseExportHighlight(
            id: id,
            text: text,
            note: note,
            location: location,
            locationType: nil,
            url: "https://readwise.io/open/\(id)",
            color: nil,
            updated: nil,
            bookId: 7,
            tags: tags.map { ReadwiseTag(id: nil, name: $0) },
            highlightedAt: nil,
            isDiscard: isDiscard,
            isDeleted: isDeleted
        )
    }

    private func exportBook(_ highlights: [ReadwiseExportHighlight]) -> ReadwiseExportBook {
        ReadwiseExportBook(
            userBookId: 7,
            title: "Deep Work",
            author: "Cal Newport",
            readableTitle: nil,
            source: "kindle",
            coverImageUrl: nil,
            uniqueUrl: nil,
            bookTags: nil,
            category: "books",
            sourceUrl: nil,
            asin: nil,
            highlights: highlights
        )
    }

    private func mirrorAtom(bookTitle: String, author: String? = nil, highlights: [ReadwiseMirrorHighlight]) -> Atom {
        var atom = Atom.new(type: .research, title: bookTitle, body: nil)
        atom.structured = ReadwiseSourceStructured(highlights: highlights).toJSON()
        var overlay = ["subtype": "readwise", "readwiseBookId": "7"]
        if let author { overlay["author"] = author }
        atom = atom.mergingMetadataKeys(overlay)
        return atom
    }

    private func highlight(_ id: String, _ text: String, note: String? = nil, tags: [String] = []) -> ReadwiseMirrorHighlight {
        ReadwiseMirrorHighlight(id: id, text: text, note: note, tags: tags)
    }

    // MARK: - Reducer

    func testMergeUpsertsPrunesAndOrders() {
        let existing = ReadwiseSourceStructured(highlights: [
            highlight("1", "old text"),
            highlight("2", "kept"),
        ])
        let incoming = exportBook([
            exportHighlight(id: 1, text: "new text", location: 20),
            exportHighlight(id: 2, text: "kept", isDeleted: true),
            exportHighlight(id: 3, text: "brand new", location: 10),
        ])

        let merged = ReadwiseMirrorReducer.mergedStructured(existing: existing, incoming: incoming)
        XCTAssertTrue(merged.changed)
        XCTAssertEqual(merged.structured.highlights.map(\.id), ["3", "1"])   // location order
        XCTAssertEqual(merged.structured.highlights.last?.text, "new text") // upserted
    }

    func testDiscardedHighlightsPruneLikeDeleted() {
        let existing = ReadwiseSourceStructured(highlights: [highlight("1", "kept")])
        let incoming = exportBook([exportHighlight(id: 1, text: "kept", isDiscard: true)])
        let merged = ReadwiseMirrorReducer.mergedStructured(existing: existing, incoming: incoming)
        XCTAssertTrue(merged.changed)
        XCTAssertTrue(merged.structured.highlights.isEmpty)
    }

    func testReapplyingSameExportIsIdempotent() {
        let incoming = exportBook([
            exportHighlight(id: 1, text: "alpha", location: 1),
            exportHighlight(id: 2, text: "beta", note: "mine", location: 2, tags: ["focus"]),
        ])
        let first = ReadwiseMirrorReducer.mergedStructured(existing: nil, incoming: incoming)
        XCTAssertTrue(first.changed)
        let second = ReadwiseMirrorReducer.mergedStructured(existing: first.structured, incoming: incoming)
        XCTAssertFalse(second.changed)
    }

    func testIndexableBodyCarriesNotes() {
        let structured = ReadwiseSourceStructured(highlights: [
            highlight("1", "The line itself", note: "my reaction"),
        ])
        let body = ReadwiseMirrorReducer.indexableBody(structured)
        XCTAssertTrue(body.contains("The line itself"))
        XCTAssertTrue(body.contains("my reaction"))
    }

    // MARK: - Matcher: what qualifies

    func testPhraseInHighlightTextQualifies() {
        let book = mirrorAtom(bookTitle: "Deep Work", highlights: [
            highlight("1", "Attention residue makes task switching expensive"),
            highlight("2", "Something entirely unrelated about sailing"),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "Attention residue", aliases: [], in: [book])
        XCTAssertEqual(matches.map(\.highlightId), ["1"])
        XCTAssertGreaterThanOrEqual(matches[0].score, 0.9)
        XCTAssertEqual(matches[0].bookTitle, "Deep Work")
    }

    func testAliasVocabularyMatchesToo() {
        let book = mirrorAtom(bookTitle: "Make It Stick", highlights: [
            highlight("1", "Spaced repetition beats massed practice"),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(
            conceptName: "Distributed practice",
            aliases: ["Spaced repetition"],
            in: [book]
        )
        XCTAssertEqual(matches.count, 1)
    }

    func testUserNoteAndTagsQualify() {
        let book = mirrorAtom(bookTitle: "Range", highlights: [
            highlight("1", "Generalists triumph in wicked domains", note: "this is really about attention residue"),
            highlight("2", "Kind learning environments reward narrow drills", tags: ["attention residue"]),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "attention residue", aliases: [], in: [book])
        XCTAssertEqual(Set(matches.map(\.highlightId)), ["1", "2"])
    }

    // MARK: - Matcher: what abstains (the core guarantee)

    func testBookTitleAloneNeverQualifies() {
        // A book ABOUT attention doesn't make every line evidence for it.
        let book = mirrorAtom(bookTitle: "Attention Management", highlights: [
            highlight("1", "Start the day with your most important task"),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "attention", aliases: [], in: [book])
        XCTAssertTrue(matches.isEmpty)
    }

    func testLoneCommonWordAbstainsWithoutSupport() {
        let book = mirrorAtom(bookTitle: "Deep Work", highlights: [
            highlight("1", "attention wanders when notifications arrive"),
        ])
        // Single-token key, single occurrence, no note/tag/title support →
        // below the floor. Silence beats a random quote.
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "attention", aliases: [], in: [book])
        XCTAssertTrue(matches.isEmpty)
    }

    func testLoneWordWithBookTitleSupportQualifies() {
        let book = mirrorAtom(bookTitle: "Attention Management", highlights: [
            highlight("1", "attention is the asset every system spends"),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "attention", aliases: [], in: [book])
        XCTAssertEqual(matches.count, 1)
    }

    func testStopWordsNeverCarryAMatch() {
        let book = mirrorAtom(bookTitle: "Essays", highlights: [
            highlight("1", "It is what it is, as they say"),
        ])
        // "Constraints as a creative gift" must match on constraints /
        // creative / gift — never on "as"/"a".
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "Constraints as a creative gift", aliases: [], in: [book])
        XCTAssertTrue(matches.isEmpty)
    }

    func testWholeTokenMatchingNeverSubstrings() {
        let book = mirrorAtom(bookTitle: "Linguistics", highlights: [
            highlight("1", "The inhabitants inhabit inhabitable places"),
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "habit", aliases: [], in: [book])
        XCTAssertTrue(matches.isEmpty)
    }

    func testRankingAndCap() {
        let book = mirrorAtom(bookTitle: "Deep Work", author: "Cal Newport", highlights: [
            highlight("1", "attention residue lingers after switching"),      // phrase: 0.9
            highlight("2", "residue of divided attention harms output"),      // tokens scattered: 0.75
        ])
        let matches = ReadwiseEvidenceMatcher.matches(conceptName: "attention residue", aliases: [], in: [book], limit: 1)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].highlightId, "1")
        XCTAssertEqual(matches[0].author, "Cal Newport")
    }

    // MARK: - Structured decode tolerance

    func testStructuredDecodesWithUnknownSiblingKeys() throws {
        let json = #"{"highlights":[{"id":"1","text":"line"}],"futureKey":true}"#
        let decoded = ReadwiseSourceStructured.fromJSON(json)
        XCTAssertEqual(decoded?.highlights.count, 1)
        XCTAssertEqual(decoded?.highlights.first?.tags, [])
    }
}
