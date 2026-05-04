// CosmoOS/Data/Models/Codex/CodexOutlineEditing.swift
// Pure outline editing helpers shared by focus-mode UI and tests.

import Foundation

enum CodexOutlineEditing {
    @discardableResult
    static func insertSlide(after slideID: UUID, in outline: inout CodexOutlineModel) -> UUID {
        let newID = UUID()
        let newSlide = CodexOutlineSlide(
            id: newID,
            position: 0,
            speechAct: nil,
            readerDeltas: [],
            frame: nil,
            distance: nil,
            techniques: [],
            transition: nil,
            note: nil
        )

        if let index = outline.slides.firstIndex(where: { $0.id == slideID }) {
            outline.slides.insert(newSlide, at: outline.slides.index(after: index))
        } else {
            outline.slides.append(newSlide)
        }

        renumberSlides(in: &outline)
        return newID
    }

    static func removeSlideIfEmpty(_ slideID: UUID, in outline: inout CodexOutlineModel) -> UUID? {
        guard let index = outline.slides.firstIndex(where: { $0.id == slideID }),
              index > outline.slides.startIndex,
              outline.slides[index].note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return nil
        }

        let previousID = outline.slides[outline.slides.index(before: index)].id
        outline.slides.remove(at: index)
        renumberSlides(in: &outline)
        return previousID
    }

    static func renumberSlides(in outline: inout CodexOutlineModel) {
        for index in outline.slides.indices {
            outline.slides[index].position = index + 1
        }
    }
}

enum CodexOutlineDraftTemplate {
    private static let linesPerSlide = 3

    static func make(from outline: CodexOutlineModel) -> String? {
        guard outline.slides.count > 1 else { return nil }

        return outline.slides.enumerated()
            .map { index, _ in slideSection(number: index + 1) }
            .joined(separator: "\n")
    }

    private static func slideSection(number: Int) -> String {
        let writingSpace = Array(repeating: "", count: linesPerSlide).joined(separator: "\n")
        return "SLIDE \(number)\n\(writingSpace)\n--"
    }
}
