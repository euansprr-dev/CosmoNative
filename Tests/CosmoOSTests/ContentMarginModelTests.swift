import XCTest
@testable import CosmoOS

/// The Margin's intent-query contract: suggestions exist from second zero
/// (title + dek + format + niche), and the draft gist joins as the
/// manuscript grows — opening plus the live tail.
@MainActor
final class ContentMarginModelTests: XCTestCase {

    private func contentAtom(title: String, format: String? = nil) -> Atom {
        var atom = Atom.new(type: .content, title: title)
        if let format {
            // ContentAtomMetadata requires phase + wordCount to decode.
            atom.metadata = "{\"phase\": \"ideation\", \"wordCount\": 0, \"contentFormat\": \"\(format)\"}"
        }
        return atom
    }

    func testIntentQueryColdStartUsesIntentSignalOnly() {
        let atom = contentAtom(title: "Hooks that survive the first second", format: "storytelling_reel")
        var state = ContentFocusModeState(atomUUID: atom.uuid)
        state.coreIdea = "Open with tension, not context"

        let query = ContentMarginModel.intentQuery(atom: atom, state: state, niche: "creator economy")

        XCTAssertTrue(query.contains("Hooks that survive"))
        XCTAssertTrue(query.contains("Open with tension"))
        XCTAssertTrue(query.contains("storytelling_reel"))
        XCTAssertTrue(query.contains("creator economy"))
    }

    func testIntentQueryIncludesDraftGistOnceWriting() {
        let atom = contentAtom(title: "T")
        var state = ContentFocusModeState(atomUUID: atom.uuid)
        let opening = String(repeating: "opening ", count: 40)
        let tail = String(repeating: "closing ", count: 80)
        state.draftContent = opening + tail

        let query = ContentMarginModel.intentQuery(atom: atom, state: state, niche: nil)

        XCTAssertTrue(query.contains("opening"), "gist must include the opening")
        XCTAssertTrue(query.contains("closing"), "gist must include the live tail")
    }

    func testIntentQueryEmptyWhenNoSignal() {
        let atom = Atom.new(type: .content, title: nil)
        let state = ContentFocusModeState(atomUUID: atom.uuid)
        XCTAssertTrue(ContentMarginModel.intentQuery(atom: atom, state: state, niche: nil).isEmpty)
    }

    func testDismissalPersistsPerDocument() {
        let model = ContentMarginModel()
        let uuid = "margin-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "margin.dismissed.\(uuid)") }

        model.bind(atomUUID: uuid)
        let hit = RecallHit(
            atomUuid: "victim", atomType: .connection, title: "V",
            matchedText: "m", page: nil, score: 0.9,
            vectorSimilarity: 0.9, keywordScore: 0, updatedAt: nil
        )
        model.dismiss(hit)

        let stored = UserDefaults.standard.stringArray(forKey: "margin.dismissed.\(uuid)") ?? []
        XCTAssertTrue(stored.contains("victim"))
    }
}
