// CosmoOS/Data/Migrations/DeepDiveBodyMigration.swift
// One-time, lazy cleanup of Deep Dive bodies polluted by the legacy raw-markdown
// append path ("_Appended from Inquiry Session <uuid> ..._" blocks). Each block
// becomes a structured UnderstandingNarrativeRevision; the body keeps only the
// original pre-pollution "about" text. Idempotent via DeepDiveMetadata.bodyMigratedAt.
// Nothing is deleted — every appended block is preserved verbatim as a revision.

import Foundation

enum DeepDiveBodyMigration {

    struct AppendedBlock: Equatable {
        var title: String
        var body: String
        var sessionUUID: String
        var sourceArtifactUUID: String
        var date: String
    }

    private static let blockPattern =
        #"(?s)\n*## (.+?)\n(.*?)\n+_Appended from Inquiry Session ([0-9A-Fa-f-]+), source artifact ([0-9A-Fa-f-]+)(?:, operation [^,]+)?, ([^.]+(?:\.\d+)?[^.]*)\._"#

    /// Pure parser: splits a polluted body into the clean leading text and the appended blocks.
    static func parseAppendedBlocks(from body: String) -> (cleanBody: String, blocks: [AppendedBlock]) {
        guard body.contains("_Appended from Inquiry Session"),
              let regex = try? NSRegularExpression(pattern: blockPattern) else {
            return (body, [])
        }
        let fullRange = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, range: fullRange)
        guard !matches.isEmpty else { return (body, []) }

        var blocks: [AppendedBlock] = []
        var cleaned = body
        for match in matches.reversed() {
            guard match.numberOfRanges >= 6,
                  let whole = Range(match.range, in: body),
                  let titleRange = Range(match.range(at: 1), in: body),
                  let bodyRange = Range(match.range(at: 2), in: body),
                  let sessionRange = Range(match.range(at: 3), in: body),
                  let artifactRange = Range(match.range(at: 4), in: body),
                  let dateRange = Range(match.range(at: 5), in: body) else { continue }
            blocks.insert(AppendedBlock(
                title: String(body[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                body: String(body[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                sessionUUID: String(body[sessionRange]),
                sourceArtifactUUID: String(body[artifactRange]),
                date: String(body[dateRange]).trimmingCharacters(in: .whitespaces)
            ), at: 0)
            if let cleanedRange = cleaned.range(of: String(body[whole])) {
                cleaned.removeSubrange(cleanedRange)
            }
        }
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), blocks)
    }

    /// Migrates a polluted Deep Dive atom once, persisting the result. Safe to call on every load.
    @MainActor
    static func migrateIfNeeded(_ atom: Atom) async throws -> Atom {
        guard atom.type == .deepDive else { return atom }

        // Refuse to migrate when either JSON column holds data we can't decode —
        // proceeding with defaults would overwrite the real (still-recoverable)
        // payload with an empty struct.
        let metadataState = atom.decodedMetadata(as: DeepDiveMetadata.self)
        let structuredState = atom.decodedStructured(as: DeepDiveStructured.self)
        if metadataState.isCorrupt || structuredState.isCorrupt {
            PersistenceHealth.note(.decodeFailure, context: "DeepDiveBodyMigration(\(atom.uuid.prefix(8)))", detail: "metadata/structured undecodable; skipping migration to avoid wiping it")
            return atom
        }

        var metadata = metadataState.value ?? DeepDiveMetadata()
        guard metadata.bodyMigratedAt == nil else { return atom }
        guard let body = atom.body, body.contains("_Appended from Inquiry Session") else {
            return atom
        }

        let (cleanBody, blocks) = parseAppendedBlocks(from: body)
        guard !blocks.isEmpty else { return atom }

        var structured = structuredState.value ?? DeepDiveStructured()
        for block in blocks {
            structured.currentUnderstanding.recordNarrativeRevision(
                UnderstandingNarrativeRevision(
                    id: "migration-\(block.sessionUUID)-\(block.sourceArtifactUUID)",
                    date: block.date,
                    text: "\(block.title)\n\(block.body)",
                    sessionUUID: block.sessionUUID,
                    originOperationId: "migration-\(block.sessionUUID)-\(block.sourceArtifactUUID)",
                    kind: .migration
                )
            )
        }
        // The newest appended understanding becomes the live narrative.
        if let latest = blocks.last {
            structured.currentUnderstanding.narrative = latest.body
        }
        metadata.bodyMigratedAt = ISO8601.string(from: Date())

        var copy = atom
        copy.body = cleanBody.isEmpty ? nil : cleanBody
        // Key-merge so sibling JSON keys owned by other writers survive.
        copy = copy.mergingStructuredKeys(structured)
        copy = copy.mergingMetadataKeys(metadata)
        return try await AtomRepository.shared.update(copy)
    }
}
