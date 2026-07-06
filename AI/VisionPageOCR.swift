// CosmoOS/AI/VisionPageOCR.swift
// On-device line detection for scanned pages — the source of the normalized
// line boxes ("visionLines" in attachment metadata) that power provenance
// highlighting: click an extract → the original page opens with the matching
// handwritten lines glowing. The vision LLM owns the transcript; this pass
// owns the geometry. PARITY: keep in lockstep with
// CosmoOS-iOS/CosmoCoreKit/Sources/AI/VisionPageOCR.swift.

import Foundation
import Vision

enum VisionPageOCR {

    /// One recognized line with its normalized bounding box.
    /// Coordinates are TOP-LEFT origin, 0…1 of the image size (UI-ready).
    struct Line: Codable, Sendable, Equatable {
        let text: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Result: Sendable {
        let text: String
        let lines: [Line]

        var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func recognize(imageData: Data) async throws -> Result {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: imageData)

        var lines: [Line] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox.cgRect
            // Vision is bottom-left normalized; flip to top-left for UI overlays.
            lines.append(Line(
                text: candidate.string,
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                width: box.width,
                height: box.height
            ))
        }
        lines.sort { lhs, rhs in
            abs(lhs.y - rhs.y) > 0.015 ? lhs.y < rhs.y : lhs.x < rhs.x
        }

        return Result(text: lines.map(\.text).joined(separator: "\n"), lines: lines)
    }

    // MARK: - Metadata bridging

    static func encodeLines(_ lines: [Line]) -> Any? {
        guard let data = try? JSONEncoder().encode(lines),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object
    }

    static func decodeLines(fromMetadataValue value: Any?) -> [Line] {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value),
              let lines = try? JSONDecoder().decode([Line].self, from: data) else { return [] }
        return lines
    }

    // MARK: - Provenance matching

    /// Lines on the page that an extract's text plausibly came from — token
    /// overlap against each recognized line (handwriting OCR is fuzzy, so
    /// exact containment is too strict).
    static func matchingLines(for extractText: String, in lines: [Line]) -> [Line] {
        let extractTokens = tokenSet(extractText)
        guard !extractTokens.isEmpty else { return [] }
        return lines.filter { line in
            let lineTokens = tokenSet(line.text)
            guard lineTokens.count >= 2 else { return false }
            let overlap = lineTokens.intersection(extractTokens).count
            return Double(overlap) / Double(lineTokens.count) >= 0.6
        }
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
    }
}
