import Foundation

enum NoteWritePolicy {
    static func allowsBodyWrite(
        existingBody: String?,
        proposedBody: String,
        hasLocalEdits: Bool
    ) -> Bool {
        let existing = existingBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let proposed = proposedBody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard proposed.isEmpty, !existing.isEmpty else {
            return true
        }

        return hasLocalEdits
    }
}
