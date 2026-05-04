import XCTest
@testable import CosmoOS

final class CodexOutlineEditingTests: XCTestCase {
    func testInsertSlideAfterFocusedSlideRenumbersAndReturnsInsertedID() {
        let firstID = UUID()
        let secondID = UUID()
        var outline = CodexOutlineModel(arcShape: "Problem-Solution", slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: secondID, position: 2, note: "Proof")
        ])

        let insertedID = CodexOutlineEditing.insertSlide(after: firstID, in: &outline)

        XCTAssertEqual(outline.slides.count, 3)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, insertedID, secondID])
        XCTAssertEqual(outline.slides.map(\.position), [1, 2, 3])
        XCTAssertEqual(outline.slides[1].note, nil)
    }

    func testRemoveEmptySlideReturnsPreviousSlideForFocus() {
        let firstID = UUID()
        let emptyID = UUID()
        let thirdID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: emptyID, position: 2, note: ""),
            makeSlide(id: thirdID, position: 3, note: "CTA")
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(emptyID, in: &outline)

        XCTAssertEqual(focusID, firstID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, thirdID])
        XCTAssertEqual(outline.slides.map(\.position), [1, 2])
    }

    func testRemoveEmptySlideDoesNotRemoveFirstSlide() {
        let firstID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: nil)
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(firstID, in: &outline)

        XCTAssertNil(focusID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID])
    }

    func testRemoveEmptySlideIgnoresNonEmptySlide() {
        let firstID = UUID()
        let secondID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: secondID, position: 2, note: "Proof")
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(secondID, in: &outline)

        XCTAssertNil(focusID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, secondID])
    }

    func testDraftTemplateRepeatsSlideWorkspaceForEachOutlineSlide() {
        let outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: UUID(), position: 1, note: "Hook"),
            makeSlide(id: UUID(), position: 2, note: "Build tension"),
            makeSlide(id: UUID(), position: 3, note: "CTA")
        ])

        XCTAssertEqual(
            CodexOutlineDraftTemplate.make(from: outline),
            """
            SLIDE 1



            --
            SLIDE 2



            --
            SLIDE 3



            --
            """
        )
    }

    func testDraftTemplateRequiresMultipleSlides() {
        let outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: UUID(), position: 1, note: "Hook")
        ])

        XCTAssertNil(CodexOutlineDraftTemplate.make(from: outline))
    }

    private func makeSlide(id: UUID, position: Int, note: String?) -> CodexOutlineSlide {
        CodexOutlineSlide(
            id: id,
            position: position,
            speechAct: nil,
            readerDeltas: [],
            frame: nil,
            distance: nil,
            techniques: [],
            transition: nil,
            note: note
        )
    }
}
