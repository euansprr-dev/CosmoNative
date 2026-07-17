import Foundation
import SwiftUI
import GRDB

/// What accepting a suggestion actually produced. Most verbs birth or mutate
/// an atom; the Seedbed verbs grow a seedling — no atom, no canvas object.
enum InboxExecutionOutcome {
    case atom(Atom)
    case seedling(Seedling)

    /// The produced atom, when the outcome is spatial/knowledge-graph work
    /// (navigation targets, reindex hooks). Seedling growth has none.
    var atom: Atom? {
        if case .atom(let atom) = self { return atom }
        return nil
    }
}

@MainActor
final class InboxActionExecutor {
    static let shared = InboxActionExecutor()

    private let atomRepo = AtomRepository.shared
    private let inboxRepo = InboxRepository.shared
    private let planner = SpatialPlacementPlanner.shared
    private let database = CosmoDatabase.shared
    private let flashModel = "google/gemini-3.1-flash-lite-preview"

    private init() {}

    @discardableResult
    func executePrimaryRecommendation(item: InboxItem) async throws -> InboxExecutionOutcome? {
        if let recommendation = item.primaryRecommendationValue {
            return try await executeRecommendation(item: item, recommendation: recommendation)
        }

        switch item.classification {
        case .merge:
            guard let targetUuid = item.mergeTargetUuid else { return nil }
            return try await executeMerge(item: item, targetAtomUuid: targetUuid).map { .atom($0) }
        case .place:
            guard let thinkspaceId = item.placeThinkspaceId else { return .atom(try await executeNew(item: item)) }
            let atomType = AtomType(rawValue: item.placeAtomType ?? AtomType.connection.rawValue) ?? .connection
            return .atom(try await executePlace(item: item, thinkspaceId: thinkspaceId, atomType: atomType))
        case .new, .unsorted, .none:
            return .atom(try await executeNew(item: item))
        }
    }

    @discardableResult
    func executeRecommendation(item: InboxItem, recommendation: InboxRecommendation) async throws -> InboxExecutionOutcome? {
        switch recommendation.kind {
        case .mergeAtom:
            guard let targetUuid = recommendation.mergeTargetUuid else { return nil }
            return try await executeMerge(item: item, targetAtomUuid: targetUuid).map { .atom($0) }
        case .placeInExistingCluster, .createClusterAndPlace, .placeInThinkspace, .createThinkspaceAndPlace:
            return try await executePlacementRecommendation(item: item, recommendation: recommendation).map { .atom($0) }
        case .advanceQuestion:
            return try await executeAdvanceQuestion(item: item, recommendation: recommendation).map { .atom($0) }
        case .spawnQuestion:
            return try await executeSpawnQuestion(item: item, recommendation: recommendation).map { .atom($0) }
        case .feedConnection:
            return try await executeFeedConnection(item: item, recommendation: recommendation).map { .atom($0) }
        case .attachClient:
            return try await executeAttachClient(item: item, recommendation: recommendation).map { .atom($0) }
        case .feedSeedling:
            return try await executeFeedSeedling(item: item, recommendation: recommendation).map { .seedling($0) }
        case .startSeedling, .germinateConnection:
            // germinateConnection is the pre-Seedbed kind (rows classified
            // before July 2026): it used to create a one-line concept page —
            // exactly the "seed packet" disease. Both now start a seedling;
            // pages are born ripe or not at all.
            return try await executeStartSeedling(item: item, recommendation: recommendation).map { .seedling($0) }
        case .germinateDeepDive:
            return try await executeGerminateDeepDive(item: item, recommendation: recommendation).map { .atom($0) }
        case .createStandaloneAtom:
            let atomType = AtomType(rawValue: recommendation.suggestedAtomType) ?? .connection
            return .atom(try await executeNew(item: item, atomType: atomType))
        }
    }

    @discardableResult
    func executeMerge(item: InboxItem, targetAtomUuid: String) async throws -> Atom? {
        guard let targetAtom = try await atomRepo.fetch(uuid: targetAtomUuid) else {
            print("⚠️ [InboxAction] Merge target not found: \(targetAtomUuid)")
            return nil
        }

        let existingBody = targetAtom.body ?? ""
        let newText = item.rawText
        // Long targets never go through the LLM: blendMerge only sees the first
        // 3000 chars, so an LLM rewrite would silently amputate the tail.
        // The lossless append fallback preserves every byte.
        let mergedBody: String
        if existingBody.count > 3000 {
            mergedBody = fallbackMerge(existing: existingBody, newContext: newText)
        } else {
            mergedBody = await blendMerge(existing: existingBody, newContext: newText, title: targetAtom.title ?? "Note")
        }

        // Durable undo source: persist the pre-merge body on the inbox item
        // BEFORE mutating the target, so the original text survives app restarts.
        do {
            try await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
                "premergeBody": existingBody,
                "premergeTargetUuid": targetAtomUuid
            ])
        } catch {
            print("⚠️ [InboxAction] Failed to persist pre-merge snapshot: \(error)")
            PersistenceHealth.note(.writeFailure, context: "InboxActionExecutor.executeMerge", detail: "pre-merge snapshot store failed for \(item.uuid): \(error.localizedDescription)")
        }

        let updated = try await atomRepo.update(uuid: targetAtomUuid) { atom in
            atom.body = mergedBody
        }

        if let updated {
            await adoptAttachments(from: item, into: updated.uuid)
            await reindex(atom: updated)
            try await inboxRepo.markActioned(uuid: item.uuid)

            let originalItem = item
            let targetUUID = updated.uuid
            let merged = updated.body ?? mergedBody
            let previousBody = existingBody

            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "Merge Inbox Capture") { [weak self] in
                    guard let self else { return }
                    _ = try? await self.atomRepo.update(uuid: targetUUID) { atom in
                        atom.body = previousBody
                    }
                    if let restored = try? await self.atomRepo.fetch(uuid: targetUUID) {
                        await self.reindex(atom: restored)
                    }
                    try? await self.inboxRepo.restore(originalItem)
                } redo: { [weak self] in
                    guard let self else { return }
                    _ = try? await self.atomRepo.update(uuid: targetUUID) { atom in
                        atom.body = merged
                    }
                    if let restored = try? await self.atomRepo.fetch(uuid: targetUUID) {
                        await self.reindex(atom: restored)
                    }
                    try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
                }
            )
        }

        return updated
    }

    @discardableResult
    func executePlace(
        item: InboxItem,
        thinkspaceId: String,
        atomType: AtomType = .connection
    ) async throws -> Atom {
        let thinkspaceName = await resolveThinkspaceName(for: thinkspaceId) ?? "Thinkspace"
        let plan = await planner.planForThinkspacePlacement(
            title: item.title ?? fallbackTitle(for: item),
            atomType: atomType,
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            relatedAtomUUIDs: []
        )

        let recommendation = InboxRecommendation(
            kind: .placeInThinkspace,
            confidence: 1.0,
            suggestedAtomType: atomType.rawValue,
            destinationPath: thinkspaceName,
            rationale: "Manual override: place directly on \(thinkspaceName).",
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            placementPlan: plan
        )

        guard let atom = try await executePlacementRecommendation(item: item, recommendation: recommendation) else {
            throw NSError(domain: "InboxActionExecutor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to place inbox item"])
        }
        return atom
    }

    @discardableResult
    func executeNew(item: InboxItem, atomType: AtomType = .connection) async throws -> Atom {
        var atom = Atom.new(
            type: atomType,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )
        atom = applyingChecklist(to: atom, atomType: atomType, rawText: item.rawText)
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)

        let createdAtom = atom
        let originalItem = item

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Create Inbox Atom") { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    /// Create a `.connection` atom from the capture and link it to the atoms
    /// it bridges. A capture that strongly matches several existing objects is
    /// a connection between them, not a duplicate of any one.
    @discardableResult
    func executeConnect(item: InboxItem, relatedAtomUUIDs: [String]) async throws -> Atom {
        var atom = Atom.new(
            type: .connection,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )

        for uuid in relatedAtomUUIDs {
            guard let related = try? await atomRepo.fetch(uuid: uuid), !related.isDeleted else { continue }
            atom = atom.appendingLink(AtomLink(
                type: AtomLinkType.related.rawValue,
                uuid: related.uuid,
                entityType: related.type.rawValue
            ))
        }

        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)

        let createdAtom = atom
        let originalItem = item

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Connect Inbox Capture") { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    /// S — the capture is a link worth studying: file it into the Swipe File.
    /// Builds a pending swipe atom (classified from the URL) and kicks the
    /// Railway worker to transcribe + analyze it, exactly like the command-bar
    /// capture path — the scan fallback tier catches anything the worker
    /// misses. Dedups against the existing library so filing a known link
    /// adopts it instead of forking a duplicate; the undo removes only a swipe
    /// THIS action created.
    @discardableResult
    func executeSwipe(item: InboxItem) async throws -> Atom {
        let url = item.detectedSwipeURL
            ?? item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Same link already swiped? Adopt the existing card — never a duplicate.
        if let existing = await QuickCaptureProcessor.findExistingLiveSwipe(url: url) {
            try await inboxRepo.markActioned(uuid: item.uuid)
            let originalItem = item
            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "File Inbox Swipe") { [weak self] in
                    // The swipe pre-existed this capture — undo only frees the capture.
                    try? await self?.inboxRepo.restore(originalItem)
                } redo: { [weak self] in
                    try? await self?.inboxRepo.markActioned(uuid: originalItem.uuid)
                }
            )
            return existing
        }

        let classification = SwipeURLClassifier().classify(url)
        let sourceType = classification.isUrl ? classification.sourceType : .website
        var atom = Atom.newSwipeFile(
            url: url,
            hook: nil,
            sourceType: sourceType,
            contentSource: .clipboard
        )
        atom.title = url                    // legible until the worker enriches it
        atom.processingStatus = "pending"   // the cloud worker (or scan fallback) takes it from here
        // The capture's prose (anything beyond the bare link) becomes the note.
        if let note = Self.swipeNote(rawText: item.rawText, url: url) {
            atom.body = note
        }
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)
        CloudSwipeAPI.kickProcessing(swipeUUID: atom.uuid)

        let createdAtom = atom
        let originalItem = item
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "File Inbox Swipe") { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    /// The capture's prose becomes the swipe's note — unless the capture is
    /// nothing but the link itself, in which case there's no note to carry.
    private static func swipeNote(rawText: String, url: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == url.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : trimmed
    }

    // MARK: - Atlas moves (July 2026)

    /// The capture is material for an open inquiry question: it lands as an
    /// extract on that question's thread, exactly where a study-session
    /// capture would.
    @discardableResult
    func executeAdvanceQuestion(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove,
              let questionUUID = move.questionUUID,
              let question = try await atomRepo.fetch(uuid: questionUUID),
              !question.isDeleted else { return nil }

        var extract = try await InquiryRepository.shared.createExtract(
            body: item.rawText,
            kind: .note,
            sourceUUID: nil,
            selectionRange: nil,
            sessionUUID: nil,
            questionUUID: questionUUID,
            deepDiveUUID: move.deepDiveUUID ?? question.questionMetadata?.parentDeepDiveUUID,
            branchNodeId: nil,
            sourceTabId: nil,
            userNote: nil,
            originType: "inboxAtlasRoute",
            citation: nil
        )
        let provenance = captureProvenance(for: item)
        if let stamped = try? await atomRepo.update(uuid: extract.uuid, updates: { atom in
            atom = atom.mergingMetadataKeys(provenance)
        }) {
            extract = stamped
        }
        await adoptAttachments(from: item, into: extract.uuid)
        await reindex(atom: extract)
        try await inboxRepo.markActioned(uuid: item.uuid)
        registerCreationUndo(created: extract, item: item, actionDescription: "Advance Inquiry Question")
        return extract
    }

    /// The capture IS a research question: it becomes a branch in the target
    /// deep dive, honoring the nesting-contract parent the router chose.
    @discardableResult
    func executeSpawnQuestion(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove,
              let deepDiveUUID = move.deepDiveUUID,
              let deepDive = try await atomRepo.fetch(uuid: deepDiveUUID),
              !deepDive.isDeleted else { return nil }

        let title = move.newQuestionTitle ?? item.title ?? String(item.rawText.prefix(120))
        let (question, created) = try await InquiryRepository.shared.findOrCreateQuestion(
            title: title,
            parentDeepDiveUUID: deepDiveUUID,
            originSessionUUID: nil,
            parentQuestionUUID: move.parentQuestionUUID,
            originExtractUUID: nil,
            placementOrigin: "inbox-atlas"
        )

        let linked = deepDive.addingLink(AtomLink(
            type: AtomLinkType.deepDiveQuestion.rawValue,
            uuid: question.uuid,
            entityType: AtomType.question.rawValue
        ))
        _ = try? await atomRepo.update(linked)

        // The raw capture often carries more than the cleaned question title —
        // keep it as the branch's first note instead of throwing words away.
        if normalizedText(item.rawText) != normalizedText(title) {
            _ = try? await InquiryRepository.shared.createExtract(
                body: item.rawText,
                kind: .note,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: nil,
                questionUUID: question.uuid,
                deepDiveUUID: deepDiveUUID,
                branchNodeId: nil,
                sourceTabId: nil,
                userNote: nil,
                originType: "inboxAtlasRoute",
                citation: nil
            )
        }

        // The originals follow the thought onto the question branch, matching
        // executeAdvanceQuestion — no route drops a capture's pages.
        await adoptAttachments(from: item, into: question.uuid)
        try await inboxRepo.markActioned(uuid: item.uuid)
        if created {
            registerCreationUndo(created: question, item: item, actionDescription: "Spawn Inquiry Question")
        }
        return question
    }

    /// The capture develops a concept page: it STAGES into the router's chosen
    /// section as a pending ghost row (✓/✗ on the next page visit) — a page
    /// you shaped by hand is never silently edited by a pipeline (the
    /// CONCEPT_RIPENING_PLAN contract). Attachments stay with the capture
    /// until the row is accepted.
    @discardableResult
    func executeFeedConnection(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove,
              let connectionUUID = move.connectionUUID,
              let sectionRaw = move.connectionSection,
              let sectionType = ConnectionSectionType(rawValue: sectionRaw),
              let connection = try await atomRepo.fetch(uuid: connectionUUID),
              !connection.isDeleted else { return nil }

        let insert = ConnectionStagedInsert(
            section: sectionType.rawValue,
            text: item.rawText,
            sourceKind: "inbox",
            sourceUUID: item.uuid,
            attachmentUUIDs: item.attachmentUUIDs
        )
        guard let updated = try await ConnectionStagingStore.stage(insert, onConnection: connectionUUID) else {
            return nil
        }

        let name = connection.title ?? "concept page"
        try? await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
            "actionOutcome": "Staged for \(name) › \(sectionType.displayName)"
        ])
        try await inboxRepo.markActioned(uuid: item.uuid)

        let originalItem = item
        let insertId = insert.id
        let stagedInsert = insert

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Feed Concept Page") { [weak self] in
                _ = try? await ConnectionStagingStore.remove(insertId: insertId, fromConnection: connectionUUID)
                try? await self?.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                _ = try? await ConnectionStagingStore.stage(stagedInsert, onConnection: connectionUUID)
                try? await self?.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return updated
    }

    /// The capture is a content idea for a client: a typed idea atom carrying
    /// the client link + metadata (the FlashLiteRouter post-process contract),
    /// enriched by the idea pipeline.
    @discardableResult
    func executeAttachClient(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove,
              let clientUUID = move.clientUUID,
              let client = try await atomRepo.fetch(uuid: clientUUID),
              !client.isDeleted else { return nil }

        var atom = Atom.new(
            type: .idea,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )
        atom = atom.addingLink(AtomLink(
            type: AtomLinkType.ideaToClient.rawValue,
            uuid: client.uuid,
            entityType: AtomType.clientProfile.rawValue
        ))
        atom = atom.withUpdatedIdeaMetadata { ideaMeta in
            ideaMeta.ideaStatus = ideaMeta.ideaStatus ?? .spark
            ideaMeta.clientUUID = client.uuid
            ideaMeta.clientName = client.title ?? move.clientName
        }
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)
        try await inboxRepo.markActioned(uuid: item.uuid)
        registerCreationUndo(created: atom, item: item, actionDescription: "File Idea for Client")

        let created = atom
        Task { await IdeaInsightEngine.shared.quickEnrich(atom: created) }
        return atom
    }

    /// The capture adds mass to a growing seedling — no atom is created, no
    /// canvas is touched. The thought accrues with provenance; the seedling
    /// ripens toward one development conversation.
    @discardableResult
    func executeFeedSeedling(item: InboxItem, recommendation: InboxRecommendation) async throws -> Seedling? {
        guard let move = recommendation.atlasMove,
              let seedlingUUID = move.seedlingUUID,
              let seedling = try await SeedlingRepository.shared.fetch(uuid: seedlingUUID),
              !seedling.isDeleted, seedling.status != .developed else { return nil }

        let thought = SeedlingThought(text: item.rawText, sourceKind: .inbox, sourceUUID: item.uuid)
        // A nil feed means the dedup guard caught a repeat (same capture) —
        // the thought is already growing there, which IS the desired state.
        let fed = try await SeedlingRepository.shared.feed(uuid: seedlingUUID, thought: thought) ?? seedling
        try? await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
            "actionOutcome": "Grew \u{201C}\(fed.name)\u{201D}"
        ])
        try await inboxRepo.markActioned(uuid: item.uuid)

        let originalItem = item
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Grow Seedling") { [weak self] in
                _ = try? await SeedlingRepository.shared.removeThought(uuid: seedlingUUID, sourceUUID: originalItem.uuid)
                try? await self?.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                _ = try? await SeedlingRepository.shared.feed(uuid: seedlingUUID, thought: thought)
                try? await self?.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )
        return fed
    }

    /// The capture names a new proto-concept: a seedling is born in the
    /// nursery. Deliberately NOT a connection atom — a one-line page on the
    /// canvas is a to-do item wearing a finished costume. The page comes
    /// later, through development, if the seedling earns it.
    @discardableResult
    func executeStartSeedling(item: InboxItem, recommendation: InboxRecommendation) async throws -> Seedling? {
        let name = recommendation.atlasMove?.germinateTitle ?? item.title ?? fallbackTitle(for: item)
        let thought = SeedlingThought(text: item.rawText, sourceKind: .inbox, sourceUUID: item.uuid)

        // A live seedling already carries this concept key? Feed it instead
        // of forking a twin — starting twice is a vocabulary echo, not intent.
        let seedling: Seedling
        let fedExisting: Bool
        if let existing = try await SeedlingRepository.shared.fetchLive(conceptKey: ConceptResolver.conceptKey(name)) {
            seedling = try await SeedlingRepository.shared.feed(uuid: existing.uuid, thought: thought) ?? existing
            fedExisting = true
        } else {
            seedling = try await SeedlingRepository.shared.create(Seedling.new(name: name, firstThought: thought))
            fedExisting = false
        }

        try? await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
            "actionOutcome": fedExisting
                ? "Grew \u{201C}\(seedling.name)\u{201D}"
                : "Started seedling \u{201C}\(seedling.name)\u{201D}"
        ])
        try await inboxRepo.markActioned(uuid: item.uuid)

        let originalItem = item
        let seedlingUUID = seedling.uuid
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Start Seedling") { [weak self] in
                if fedExisting {
                    _ = try? await SeedlingRepository.shared.removeThought(uuid: seedlingUUID, sourceUUID: originalItem.uuid)
                } else {
                    try? await SeedlingRepository.shared.delete(uuid: seedlingUUID)
                }
                try? await self?.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                if fedExisting {
                    _ = try? await SeedlingRepository.shared.feed(uuid: seedlingUUID, thought: thought)
                } else {
                    try? await SeedlingRepository.shared.undelete(uuid: seedlingUUID)
                }
                try? await self?.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )
        return seedling
    }

    /// The capture opens a research territory of its own: a new deep dive
    /// whose root question is the capture.
    @discardableResult
    func executeGerminateDeepDive(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        let topicTitle = recommendation.atlasMove?.germinateTitle ?? item.title ?? fallbackTitle(for: item)
        let dive = try await InquiryRepository.shared.createDeepDive(
            title: topicTitle,
            about: "Opened from an inbox capture."
        )
        let questionTitle = item.title ?? String(item.rawText.prefix(120))
        _ = try? await InquiryRepository.shared.findOrCreateQuestion(
            title: questionTitle,
            parentDeepDiveUUID: dive.uuid,
            originSessionUUID: nil,
            parentQuestionUUID: nil,
            originExtractUUID: nil,
            placementOrigin: "inbox-atlas"
        )
        // The capture's pages follow it into the new deep dive rather than
        // being orphaned on the resolved inbox item.
        await adoptAttachments(from: item, into: dive.uuid)
        try await inboxRepo.markActioned(uuid: item.uuid)
        registerCreationUndo(created: dive, item: item, actionDescription: "Germinate Deep Dive")
        return dive
    }

    /// Shared undo shape for Atlas moves that created one primary atom:
    /// undo deletes the atom and restores the capture; redo re-persists it.
    private func registerCreationUndo(created: Atom, item: InboxItem, actionDescription: String) {
        let createdAtom = created
        let originalItem = item
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: actionDescription) { [weak self] in
                guard let self else { return }
                try? await self.atomRepo.delete(uuid: createdAtom.uuid)
                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }
                try? await self.restoreAtomSnapshot(createdAtom)
                await self.reindex(atom: createdAtom)
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )
    }

    private func normalizedText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Quick-thought placement (compact card, never a letter page)

    /// A capture short enough to be a glanceable thought rather than a
    /// document. Mirrors NoteBlockView's graduation cap.
    static let quickThoughtWordCap = 60

    nonisolated static func isQuickThought(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return words > 0 && words <= quickThoughtWordCap
    }

    /// Card footprint sized to the thought: fixed 280pt column, height
    /// estimated from the text's wrap, clamped so one line still reads as a
    /// card and a 60-word thought never becomes a tower.
    nonisolated static func thoughtCardSize(for text: String) -> CGSize {
        let width: CGFloat = 280
        let charsPerLine: CGFloat = 30
        let lines = max(2, (CGFloat(text.count) / charsPerLine).rounded(.up))
        let height = min(340, max(116, lines * 21 + 62))
        return CGSize(width: width, height: height)
    }

    private func executePlacementRecommendation(
        item: InboxItem,
        recommendation: InboxRecommendation
    ) async throws -> Atom? {
        let atomType = AtomType(rawValue: recommendation.suggestedAtomType) ?? .connection
        let originalItem = item

        var targetThinkspaceId = recommendation.thinkspaceId
        var mutatedThinkspaceBefore: Atom?
        var mutatedThinkspaceAfter: Atom?

        if recommendation.kind == .createThinkspaceAndPlace {
            let thinkspaceName = recommendation.placementPlan?.targetThinkspaceName
                ?? recommendation.thinkspaceName
                ?? recommendation.destinationPath
            guard let thinkspace = await ThinkspaceManager.shared.createThinkspace(name: thinkspaceName) else {
                return nil
            }
            targetThinkspaceId = thinkspace.id
        }

        var atom = Atom.new(
            type: atomType,
            title: item.title ?? fallbackTitle(for: item),
            body: item.rawText
        )
        atom = applyingChecklist(to: atom, atomType: atomType, rawText: item.rawText)
        atom = atom.mergingMetadataKeys(captureProvenance(for: item))
        atom = try await atomRepo.create(atom)
        await adoptAttachments(from: item, into: atom.uuid)
        await reindex(atom: atom)

        var createdBlockRecord: CanvasBlockRecord?

        if let thinkspaceId = targetThinkspaceId {
            if recommendation.kind == .placeInExistingCluster || recommendation.kind == .createClusterAndPlace || recommendation.kind == .createThinkspaceAndPlace,
               let placementPlan = recommendation.placementPlan {
                let snapshots = try await applyClusterMutation(
                    thinkspaceId: thinkspaceId,
                    recommendation: recommendation,
                    placementPlan: placementPlan,
                    atomUUID: atom.uuid
                )
                mutatedThinkspaceBefore = snapshots.before
                mutatedThinkspaceAfter = snapshots.after
            }

            if let placementPlan = recommendation.placementPlan,
               let x = placementPlan.blockPositionX,
               let y = placementPlan.blockPositionY {
                var block = CanvasBlock.fromAtom(atom, position: CGPoint(x: x, y: y))
                // A quick thought never wears the letter-page costume: it
                // lands as a compact card sized to its own words (the block's
                // footprint IS the contract — NoteBlockView renders compact
                // short notes as thought cards, and growing the note past a
                // page's worth of words graduates it back to the page shape).
                if atom.type == .note, Self.isQuickThought(item.rawText) {
                    block.size = Self.thoughtCardSize(for: item.rawText)
                }
                let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: thinkspaceId)
                try await persistCanvasBlockSnapshot(record)
                createdBlockRecord = record
            }

            await refreshThinkspace(thinkspaceId)
        }

        try await inboxRepo.markActioned(uuid: item.uuid)

        let afterThinkspaceSnapshot = mutatedThinkspaceAfter
        let beforeThinkspaceSnapshot = mutatedThinkspaceBefore
        let createdAtom = atom
        let blockSnapshot = createdBlockRecord
        let affectedThinkspaceId = targetThinkspaceId

        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Apply Inbox Recommendation") { [weak self] in
                guard let self else { return }

                try? await self.atomRepo.delete(uuid: createdAtom.uuid)

                if let beforeThinkspaceSnapshot {
                    try? await self.persistAtomSnapshot(beforeThinkspaceSnapshot)
                } else if let afterThinkspaceSnapshot {
                    try? await self.atomRepo.delete(uuid: afterThinkspaceSnapshot.uuid)
                }

                if let affectedThinkspaceId {
                    await ThinkspaceManager.shared.loadThinkspaces()
                    await self.refreshThinkspace(affectedThinkspaceId)
                }

                try? await self.inboxRepo.restore(originalItem)
            } redo: { [weak self] in
                guard let self else { return }

                if let afterThinkspaceSnapshot {
                    try? await self.restoreAtomSnapshot(afterThinkspaceSnapshot)
                    await ThinkspaceManager.shared.loadThinkspaces()
                }

                try? await self.restoreAtomSnapshot(createdAtom)
                if let blockSnapshot {
                    try? await self.persistCanvasBlockSnapshot(blockSnapshot)
                }
                await self.reindex(atom: createdAtom)

                if let affectedThinkspaceId {
                    await self.refreshThinkspace(affectedThinkspaceId)
                }

                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid)
            }
        )

        return atom
    }

    private func applyClusterMutation(
        thinkspaceId: String,
        recommendation: InboxRecommendation,
        placementPlan: InboxPlacementPlan,
        atomUUID: String
    ) async throws -> (before: Atom, after: Atom) {
        guard var thinkspaceAtom = try await atomRepo.fetch(uuid: thinkspaceId) else {
            throw NSError(domain: "InboxActionExecutor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Thinkspace not found"])
        }

        let before = thinkspaceAtom
        var metadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self) ?? ThinkspaceMetadata(
            name: recommendation.thinkspaceName ?? thinkspaceAtom.title ?? "Thinkspace"
        )

        let clusterId = placementPlan.targetClusterId ?? recommendation.clusterId ?? UUID().uuidString
        let clusterName = placementPlan.targetClusterName ?? recommendation.clusterName ?? "Cluster"
        let rect = placementPlan.clusterRect

        if let index = metadata.clusters.firstIndex(where: { $0.id == clusterId }) {
            if !metadata.clusters[index].blockUUIDs.contains(atomUUID) {
                metadata.clusters[index].blockUUIDs.append(atomUUID)
            }
            metadata.clusters[index].name = clusterName
            metadata.clusters[index].intent = recommendation.rationale
            metadata.clusters[index].viewMode = placementPlan.clusterViewMode ?? metadata.clusters[index].viewMode
            if let rect {
                metadata.clusters[index].originX = rect.originX
                metadata.clusters[index].originY = rect.originY
                metadata.clusters[index].rectWidth = rect.width
                metadata.clusters[index].rectHeight = rect.height
                metadata.clusters[index].manualWidth = rect.width
                metadata.clusters[index].manualHeight = rect.height
            }
        } else {
            metadata.clusters.append(
                CodableCluster(
                    id: clusterId,
                    name: clusterName,
                    blockUUIDs: [atomUUID],
                    colorIndex: 0,
                    originX: rect?.originX,
                    originY: rect?.originY,
                    rectWidth: rect?.width,
                    rectHeight: rect?.height,
                    manualWidth: rect?.width,
                    manualHeight: rect?.height,
                    isZone: true,
                    zoneType: nil,
                    intent: recommendation.rationale,
                    viewMode: placementPlan.clusterViewMode ?? ClusterViewMode.canvas.rawValue,
                    sortOrder: ClusterSortOrder.dateUpdated.rawValue,
                    boardGrouping: ClusterBoardGrouping.auto.rawValue
                )
            )
        }

        if let json = try? JSONEncoder().encode(metadata),
           let string = String(data: json, encoding: .utf8) {
            thinkspaceAtom.metadata = string
        }
        thinkspaceAtom.title = metadata.name

        try await persistAtomSnapshot(thinkspaceAtom)
        return (before, thinkspaceAtom)
    }

    private func persistAtomSnapshot(_ atom: Atom) async throws {
        try await database.asyncWrite { db in
            var mutable = atom
            let existing = try Atom
                .filter(Column("uuid") == atom.uuid)
                .fetchOne(db)
            if existing != nil {
                try mutable.update(db)
            } else {
                try mutable.insert(db)
            }
        }
    }

    private func restoreAtomSnapshot(_ atom: Atom) async throws {
        try await persistAtomSnapshot(atom)
    }

    private func persistCanvasBlockSnapshot(_ record: CanvasBlockRecord) async throws {
        try await database.asyncWrite { db in
            var mutable = record
            let existing = try CanvasBlockRecord
                .filter(Column("id") == record.id)
                .fetchOne(db)
            if existing != nil {
                try mutable.update(db)
            } else {
                try mutable.insert(db)
            }
        }
    }

    private func refreshThinkspace(_ thinkspaceId: String) async {
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.refreshThinkspacePlacements,
            object: nil,
            userInfo: ["thinkspaceId": thinkspaceId]
        )
        // Placement changed cluster membership — routing centroids and the
        // destination atlas are stale.
        await InboxRoutingEngine.shared.invalidateCentroids()
        await InboxDestinationAtlas.shared.invalidate()
    }

    private func resolveThinkspaceName(for thinkspaceId: String) async -> String? {
        if let thinkspace = ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == thinkspaceId }) {
            return thinkspace.name
        }
        let fetchedAtom = try? await atomRepo.fetch(uuid: thinkspaceId)
        guard let atom = fetchedAtom ?? nil else {
            return nil
        }
        return atom.metadataValue(as: ThinkspaceMetadata.self)?.name
    }

    private func fallbackTitle(for item: InboxItem) -> String {
        item.title ?? String(item.rawText.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A checkbox-bearing capture routed as a TASK becomes a real one: prose
    /// names it, the checkboxes become its Things-style subtasks (checked
    /// state preserved from the page), the body keeps just the prose.
    private func applyingChecklist(to atom: Atom, atomType: AtomType, rawText: String) -> Atom {
        guard atomType == .task,
              let payload = CapturedChecklist.taskPayload(from: rawText) else { return atom }
        var copy = atom
        copy.title = payload.title
        copy.body = payload.notes.isEmpty ? nil : payload.notes
        if let checklistJSON = CapturedChecklist.checklistJSON(payload.checklist) {
            copy = copy.mergingMetadataKeys(["checklist": checklistJSON])
        }
        return copy
    }

    /// Provenance metadata stamped on every atom created from an inbox capture.
    /// The launch reconciler uses `sourceCaptureUuid` to safely auto-dismiss
    /// captures whose atoms already exist instead of guessing by text match.
    private func captureProvenance(for item: InboxItem) -> [String: String] {
        ["sourceCaptureUuid": item.uuid]
    }

    /// The originals follow the thought: page/photo attachments captured with
    /// the inbox item are re-homed on the atom it became, and listed in the
    /// atom's metadata so any surface can render them. Never fails the route —
    /// a failed adoption leaves attachments reachable via the inbox item.
    private func adoptAttachments(from item: InboxItem, into atomUUID: String) async {
        let uuids = item.attachmentUUIDs
        guard !uuids.isEmpty else { return }

        for uuid in uuids {
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { attachment in
                attachment.ownerType = MediaAttachmentOwner.atom.rawValue
                attachment.ownerUUID = atomUUID
                return true
            }
        }
        _ = try? await atomRepo.update(uuid: atomUUID) { atom in
            // UNION, never replace (the iOS engine's contract): routing a
            // second capture onto the same atom must not drop the pages the
            // first one carried.
            let existing = atom.attachmentUUIDs
            let union = existing + uuids.filter { !existing.contains($0) }
            atom = atom.mergingMetadataKeys(["attachmentUUIDs": union])
        }
    }

    private func reindex(atom: Atom) async {
        await RecallIndexer.shared.noteAtomChanged(atom)
    }

    private func blendMerge(existing: String, newContext: String, title: String) async -> String {
        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return newContext
        }

        do {
            let prompt = """
            You are merging new context into an existing note. Produce a single coherent document that integrates both.

            RULES:
            - Preserve all information from both texts
            - Do not add commentary or headings
            - Write naturally as if this were always one note
            - Keep contradictions if both perspectives matter
            - Return only the merged note

            EXISTING NOTE ("\(title)"):
            \(String(existing.prefix(3000)))

            NEW CONTEXT:
            \(String(newContext.prefix(2000)))
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
            return fallbackMerge(existing: existing, newContext: newContext)
        }
    }

    private func fallbackMerge(existing: String, newContext: String) -> String {
        let datestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        return existing + "\n\n---\n\nAdded \(datestamp):\n\n" + newContext
    }
}
