import XCTest
@testable import CosmoOS

/// The cheap classifier's contract, pinned:
/// - Parse is fence-tolerant and lands ONLY on the closed vocabulary.
/// - Confidence below the floor answers nil — wrong-but-confident is the one
///   failure mode the filing system never accepts.
/// - The prompt carries the full vocabulary and the collector's note.
/// - Heal-sweep candidacy: complete-but-unfiled rows classify; filed, locked,
///   or post rows never do.
@MainActor
final class SwipeGenreClassifierTests: XCTestCase {

    // MARK: - Parse

    func testParsesPlainAndFencedJSON() {
        XCTAssertEqual(
            SwipeGenreClassifier.parse(#"{"genre": "newsletter", "confidence": 0.92}"#),
            SwipeGenreClassifier.Verdict(genre: .newsletter, confidence: 0.92)
        )
        XCTAssertEqual(
            SwipeGenreClassifier.parse("```json\n{\"genre\": \"salesPage\", \"confidence\": 0.8}\n```"),
            SwipeGenreClassifier.Verdict(genre: .salesPage, confidence: 0.8)
        )
    }

    func testSynonymsResolveThroughTheClosedNet() {
        // "vsl" is not a rawValue; SwipeGenre.resolve's net lands it.
        XCTAssertEqual(
            SwipeGenreClassifier.parse(#"{"genre": "vsl", "confidence": 0.7}"#)?.genre,
            .salesPage
        )
    }

    func testLowConfidenceAndUnknownsAnswerNil() {
        XCTAssertNil(SwipeGenreClassifier.parse(#"{"genre": "newsletter", "confidence": 0.3}"#))
        XCTAssertNil(SwipeGenreClassifier.parse(#"{"genre": "vaporwave", "confidence": 0.9}"#))
        XCTAssertNil(SwipeGenreClassifier.parse("the model wrote prose instead"))
        XCTAssertNil(SwipeGenreClassifier.parse(#"{"confidence": 0.9}"#))
    }

    // MARK: - Prompt

    func testPromptCarriesVocabularyTieBreaksAndNote() {
        let prompt = SwipeGenreClassifier.prompt(note: "she sells launch", unitCopy: ["RSVP FOR THIS MASTERCLASS"])
        for genre in SwipeGenre.allCases {
            XCTAssertTrue(prompt.contains(genre.rawValue), "vocabulary must include \(genre.rawValue)")
        }
        XCTAssertTrue(prompt.contains("Tie-breaks"))
        XCTAssertTrue(prompt.contains("she sells launch"))
        XCTAssertTrue(prompt.contains("RSVP FOR THIS MASTERCLASS"))
        XCTAssertTrue(prompt.contains("ONLY this JSON"))
    }

    // MARK: - Heal-sweep candidacy (the genre-backfill arm)

    private func completeSwipe(kind: SwipeKind, genre: SwipeGenre?, locked: Bool = false) -> Atom {
        var atom = Atom.new(type: .research, title: "A swipe")
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = kind.rawValue
            meta.processingStatus = "complete"
        }
        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: kind,
            units: [SwipeArtifactUnit(index: 0, copy: "Some transcribed copy", attachmentUUID: "a1")],
            genre: genre,
            genreLockedByUser: locked ? true : nil,
            captureMode: "test"
        ))
        atom.updatedAt = ISO8601.string(from: Date().addingTimeInterval(-3600))
        return atom
    }

    func testCompleteButUnfiledFramesAndPagesClassify() {
        XCTAssertEqual(
            SwipeArtifactHealSweep.healAction(for: completeSwipe(kind: .frame, genre: nil), now: Date()),
            .classifyGenre
        )
        XCTAssertEqual(
            SwipeArtifactHealSweep.healAction(for: completeSwipe(kind: .page, genre: nil), now: Date()),
            .classifyGenre
        )
    }

    func testFiledLockedAndDecidedFallbackRowsNeverReclassify() {
        // A stored genre — even the structural fallback — is a DECISION; the
        // terminal rule depends on this ending candidacy forever.
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: completeSwipe(kind: .frame, genre: .screenshot), now: Date()))
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: completeSwipe(kind: .page, genre: .newsletter), now: Date()))
        XCTAssertNil(SwipeArtifactHealSweep.healAction(for: completeSwipe(kind: .frame, genre: nil, locked: true), now: Date()))
    }
}

/// Long pasted text splits into beats; short saved lines never do.
final class SwipeTextSlicerTests: XCTestCase {

    func testSingleLineHookStaysOneUnit() {
        let units = SwipeTextSlicer.units(from: "Nobody wants to hear this, but it works.")
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].copy, "Nobody wants to hear this, but it works.")
    }

    func testLongTextWithoutParagraphBreaksStaysOneUnit() {
        let wall = String(repeating: "word ", count: 300)  // long, but one block
        XCTAssertEqual(SwipeTextSlicer.units(from: wall).count, 1)
    }

    func testScriptSplitsAtBlankLinesWithHeadlines() {
        let paragraph = String(repeating: "A sentence of the script. ", count: 10)
        let script = (1...4).map { "Beat \($0) opening line.\n\(paragraph)" }
            .joined(separator: "\n\n\n")  // runs of blanks are ONE cut
        let units = SwipeTextSlicer.units(from: script)
        XCTAssertEqual(units.count, 4)
        XCTAssertEqual(units[0].headline, "Beat 1 opening line.")
        XCTAssertEqual(units[3].index, 3)
        XCTAssertTrue(units[2].copy?.contains("A sentence of the script.") == true)
    }

    func testWindowsNewlinesNormalize() {
        let paragraph = String(repeating: "Copy line here. ", count: 20)
        let text = (1...3).map { "Part \($0)\r\n\(paragraph)" }.joined(separator: "\r\n\r\n")
        XCTAssertEqual(SwipeTextSlicer.units(from: text).count, 3)
    }
}
