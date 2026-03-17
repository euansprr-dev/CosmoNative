// CosmoOS/AI/InboxActionExecutor.swift
// Executes inbox triage actions: merge, place, or create new
// March 2026

import Foundation
import SwiftUI

@MainActor
final class InboxActionExecutor {
    static let shared = InboxActionExecutor()

    private let atomRepo = AtomRepository.shared
    private let inboxRepo = InboxRepository.shared
    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    private init() {}

    // MARK: - Merge (AI-Blended)

    /// Merges inbox item text into an existing atom using LLM to blend coherently.
    /// Re-indexes the atom in the vector database after merge.
    @discardableResult
    func executeMerge(item: InboxItem, targetAtomUuid: String) async throws -> Atom? {
        guard let targetAtom = try await atomRepo.fetch(uuid: targetAtomUuid) else {
            print("⚠️ [InboxAction] Merge target not found: \(targetAtomUuid)")
            return nil
        }

        let existingBody = targetAtom.body ?? ""
        let newText = item.rawText

        // AI-blended merge: use LLM to weave new context into existing body
        let mergedBody = await blendMerge(existing: existingBody, newContext: newText, title: targetAtom.title ?? "Note")

        // Update atom body
        let updated = try await atomRepo.update(uuid: targetAtomUuid) { atom in
            atom.body = mergedBody
        }

        // Re-index in vector database
        if let atom = updated {
            try? await VectorDatabase.shared.index(
                text: mergedBody,
                entityType: atom.type.rawValue,
                entityId: atom.id ?? 0,
                entityUUID: atom.uuid
            )
        }

        // Mark inbox item as actioned
        try await inboxRepo.markActioned(uuid: item.uuid)

        print("✅ [InboxAction] Merged into \(targetAtom.title ?? "atom") (\(targetAtomUuid))")
        return updated
    }

    /// Uses LLM to intelligently blend new context into existing note body.
    private func blendMerge(existing: String, newContext: String, title: String) async -> String {
        // If existing body is empty, just use the new context
        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return newContext
        }

        do {
            let prompt = """
            You are merging new context into an existing note. Produce a single coherent document that integrates both.

            RULES:
            - Preserve ALL information from both the existing note and new context
            - Do NOT add commentary, headers like "Updated:" or "New addition:", or meta-text
            - Write naturally as if it was always one note
            - If the new context contradicts the existing note, keep both perspectives
            - Maintain the original writing style and tone
            - Return ONLY the merged text, nothing else

            EXISTING NOTE ("\(title)"):
            \(String(existing.prefix(3000)))

            NEW CONTEXT:
            \(String(newContext.prefix(2000)))

            MERGED NOTE:
            """

            let result = try await ResearchService.shared.analyze(
                prompt: prompt,
                model: flashModel,
                maxTokens: 4000,
                temperature: 0.1
            )

            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? fallbackMerge(existing: existing, newContext: newContext) : cleaned
        } catch {
            print("⚠️ [InboxAction] LLM merge failed, using fallback: \(error)")
            return fallbackMerge(existing: existing, newContext: newContext)
        }
    }

    /// Simple append fallback when LLM is unavailable.
    private func fallbackMerge(existing: String, newContext: String) -> String {
        let datestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        return existing + "\n\n---\n\nAdded \(datestamp):\n\n" + newContext
    }

    // MARK: - Place on Thinkspace

    /// Creates a new atom from inbox item and places it on a thinkspace canvas.
    @discardableResult
    func executePlace(
        item: InboxItem,
        thinkspaceId: String,
        atomType: AtomType = .connection
    ) async throws -> Atom {
        // Create atom
        var atom = Atom.new(
            type: atomType,
            title: item.title ?? String(item.rawText.prefix(60)),
            body: item.rawText
        )

        atom = try await atomRepo.create(atom)

        // Index in vector database
        try? await VectorDatabase.shared.index(
            text: item.rawText,
            entityType: atomType.rawValue,
            entityId: atom.id ?? 0,
            entityUUID: atom.uuid
        )

        // Place on canvas at center
        let block = CanvasBlock.fromAtom(atom, position: CGPoint(x: 500, y: 400))
        // SpatialEngine needs the thinkspace context — post notification for canvas to handle
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.createInboxBlock,
            object: nil,
            userInfo: [
                "atom": atom,
                "thinkspaceId": thinkspaceId,
                "position": NSValue(point: NSPoint(x: 500, y: 400))
            ]
        )

        // Mark inbox item as actioned
        try await inboxRepo.markActioned(uuid: item.uuid)

        print("✅ [InboxAction] Placed '\(atom.title ?? "")' on thinkspace \(thinkspaceId)")
        return atom
    }

    // MARK: - Create New (No Placement)

    /// Creates a new atom from inbox item without placing on any canvas.
    @discardableResult
    func executeNew(item: InboxItem, atomType: AtomType = .connection) async throws -> Atom {
        var atom = Atom.new(
            type: atomType,
            title: item.title ?? String(item.rawText.prefix(60)),
            body: item.rawText
        )

        atom = try await atomRepo.create(atom)

        // Index in vector database
        try? await VectorDatabase.shared.index(
            text: item.rawText,
            entityType: atomType.rawValue,
            entityId: atom.id ?? 0,
            entityUUID: atom.uuid
        )

        // Mark inbox item as actioned
        try await inboxRepo.markActioned(uuid: item.uuid)

        print("✅ [InboxAction] Created new \(atomType.rawValue): '\(atom.title ?? "")'")
        return atom
    }
}
