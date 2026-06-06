import Foundation

enum CosmoInlineAssistantDiffEngine {
    static func hunks(original: String, proposed: String) -> [CosmoProposalHunk] {
        let originalLines = normalizedLines(original)
        let proposedLines = normalizedLines(proposed)
        let maxCount = max(originalLines.count, proposedLines.count)
        var hunks: [CosmoProposalHunk] = []

        for index in 0..<maxCount {
            let oldLine = index < originalLines.count ? originalLines[index] : nil
            let newLine = index < proposedLines.count ? proposedLines[index] : nil

            switch (oldLine, newLine) {
            case let (.some(old), .some(new)) where old == new:
                hunks.append(CosmoProposalHunk(kind: .context, text: old))
            case let (.some(old), .some(new)):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case let (.some(old), .none):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
            case let (.none, .some(new)):
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case (.none, .none):
                break
            }
        }

        return hunks
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
