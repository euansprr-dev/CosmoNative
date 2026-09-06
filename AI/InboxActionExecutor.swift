import Foundation
import SwiftUI
import GRDB

/// What accepting a suggestion actually produced. Most verbs birth or mutate
/// an atom; the Seedbed verbs grow a seedling — no atom, no canvas object.
enum InboxExecutionOutcome {
    case atom(Atom)
    case filed(Atom, InboxPlacementReceipt)
    case seedling(Seedling)

    /// The produced atom, when the outcome is spatial/knowledge-graph work
    /// (navigation targets, reindex hooks). Seedling growth has none.
    var atom: Atom? {
        switch self {
        case .atom(let atom), .filed(let atom, _): return atom
        case .seedling: return nil
        }
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

    func executeFiling(item: InboxItem, destination: InboxFilingDestination,
                       action: InboxFilingAction? = nil, section: String? = nil,
                       preparedAtom: Atom? = nil, existingAtomUUID: String? = nil) async throws -> (Atom, InboxPlacementReceipt) {
        var request = try await InboxPlacementService.shared.request(for: item, destination: destination, action: action)
        request.connectionSection = section
        request.existingAtomUUID = existingAtomUUID
        let receipt = try await InboxPlacementService.shared.execute(request, preparedAtom: preparedAtom)
        registerFilingUndo(receipt)
        guard let atom = try await atomRepo.fetch(uuid: receipt.resultAtomUUID) else { throw InboxPlacementError.conflict }
        return (atom, receipt)
    }

    private func registerFilingUndo(_ receipt: InboxPlacementReceipt) {
        CosmoUndoManager.shared.register(InlineUndoAction(actionDescription: receipt.request.action.title) {
            do { _ = try await InboxPlacementService.shared.undo(receipt) }
            catch { NotificationCenter.default.post(name: SpaceCompositionService.didFailUndo, object: nil, userInfo: ["message": error.localizedDescription]) }
        } redo: {
            do { _ = try await InboxPlacementService.shared.redo(receipt) }
            catch { NotificationCenter.default.post(name: SpaceCompositionService.didFailUndo, object: nil, userInfo: ["message": error.localizedDescription]) }
        })
    }

    private func spatialDestination(_ recommendation: InboxRecommendation) async throws -> InboxFilingDestination {
        let destinations = try await InboxPlacementService.shared.destinations()
        guard let spaceID = recommendation.thinkspaceId else { throw InboxPlacementError.missingDestination }
        if recommendation.kind == .placeInExistingCluster, let clusterID = recommendation.clusterId {
            let space = try await atomRepo.fetch(uuid: spaceID)
            let mapping = space?.metadataDict?[SpaceCompositionLegacyMigration.metadataKey] as? [String: Any]
            let groups = mapping?["groups"] as? [String: String] ?? [:]
            let uuid = groups[clusterID] ?? clusterID
            guard let group = destinations.first(where: { $0.kind == .group && $0.uuid == uuid && $0.spaceID == spaceID }) else {
                throw InboxPlacementError.missingDestination
            }
            return group
        }
        guard let space = destinations.first(where: { $0.kind == .space && $0.spaceID == spaceID }) else { throw InboxPlacementError.missingDestination }
        return space
    }

    @discardableResult
    func executePrimaryRecommendation(item: InboxItem) async throws -> InboxExecutionOutcome? {
        if let raw = item.primaryRouteKind, InboxRouteKind(rawValue: raw) == nil { throw InboxPlacementError.unsupported }
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
        if let destination = recommendation.filingDestination {
            let (atom, receipt) = try await executeFiling(item: item, destination: destination,
                action: recommendation.filingAction ?? destination.defaultAction)
            return .filed(atom, receipt)
        }
        switch recommendation.kind {
        case .fileToDestination: throw InboxPlacementError.unsupported
        case .mergeAtom:
            guard let targetUuid = recommendation.mergeTargetUuid else { return nil }
            return try await executeMerge(item: item, targetAtomUuid: targetUuid).map { .atom($0) }
        case .placeInExistingCluster, .placeInThinkspace:
            let destination = try await spatialDestination(recommendation)
            let (atom, receipt) = try await executeFiling(item: item, destination: destination)
            return .filed(atom, receipt)
        case .createClusterAndPlace, .createThinkspaceAndPlace:
            throw InboxPlacementError.unsupported
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
        case .startInquiry:
            return try await executeStartInquiry(item: item, recommendation: recommendation).map { .atom($0) }
        case .createStandaloneAtom:
            let atomType = AtomType(rawValue: recommendation.suggestedAtomType) ?? .connection
            return .atom(try await executeNew(item: item, atomType: atomType))
        case .fileAsSwipe:
            return .atom(try await executeSwipe(item: item))
        case .addToFlow:
            // The recommendation names no flow — the router never picks one.
            // Accepting it opens the flow picker, which is a UI move, so the
            // executor declines and the inspector's `→ Flow` verb takes over.
            return nil
        }
    }

    @discardableResult
    func executeMerge(item: InboxItem, targetAtomUuid: String) async throws -> Atom? {
        guard let target = try await atomRepo.fetch(uuid: targetAtomUuid), !target.isDeleted else { return nil }
        let kind: InboxFilingDestination.Kind = target.type == .connection ? .connection : .page
        guard kind == .connection || target.spaceCompositionKind?.isAuthored == true else { throw InboxPlacementError.unsupported }
        let name = target.title ?? "Untitled Page"
        let destination = InboxFilingDestination(kind: kind, uuid: target.uuid, name: name, path: name)
        return try await executeFiling(item: item, destination: destination).0
    }

    @discardableResult
    func executePlace(item: InboxItem, thinkspaceId: String, atomType: AtomType = .note) async throws -> Atom {
        let name = await resolveThinkspaceName(for: thinkspaceId) ?? "Space"
        let destination = InboxFilingDestination(kind: .space, uuid: thinkspaceId, spaceID: thinkspaceId, name: name, path: name)
        return try await executeFiling(item: item, destination: destination).0
    }

    @discardableResult
    func executeNew(item: InboxItem, atomType: AtomType = .note) async throws -> Atom {
        let destination: InboxFilingDestination
        switch atomType {
        case .idea: destination = .init(kind: .ideas, name: "Personal", path: "Content › Personal ideas")
        case .task: destination = .init(kind: .today, name: "Today", path: "Today › Tasks")
        default: destination = .init(kind: .pages, name: "Pages", path: "Pages")
        }
        return try await executeFiling(item: item, destination: destination).0
    }

    /// Create a `.connection` atom from the capture and link it to the atoms
    /// it bridges. A capture that strongly matches several existing objects is
    /// a connection between them, not a duplicate of any one.
    @discardableResult
    func executeConnect(item: InboxItem, relatedAtomUUIDs: [String]) async throws -> Atom {
        try await requireInboxSource(item)
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
    /// What filing produced: the swipe, plus whether it pre-existed the
    /// capture. Adoption is real news — the caller's toast must not claim
    /// "Saved as swipe" over a no-op (iOS twin: InboxActionEngine's receipt).
    struct SwipeFilingOutcome {
        let atom: Atom
        let adoptedExisting: Bool
    }

    @discardableResult
    func executeSwipe(item: InboxItem) async throws -> Atom {
        try await executeSwipeOutcome(item: item).atom
    }

    @discardableResult
    func executeSwipeOutcome(item: InboxItem) async throws -> SwipeFilingOutcome {
        // A capture that carries images and NO link is a frame swipe: the
        // pictures ARE what was saved. The link wins when both are present —
        // the original post beats a screenshot of it — and the images then
        // ride along as extra units rather than being stranded.
        if item.detectedSwipeURL == nil, !item.attachmentUUIDs.isEmpty,
           let framed = try await executeFrameSwipe(item: item) {
            return SwipeFilingOutcome(atom: framed, adoptedExisting: false)
        }

        let url = item.detectedSwipeURL
            ?? item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = await QuickCaptureProcessor.findExistingLiveSwipe(url: url) {
            let (saved, _) = try await executeFiling(item: item,
                destination: .init(kind: .swipe, name: "Swipe", path: "Swipe"), existingAtomUUID: existing.uuid)
            return SwipeFilingOutcome(atom: saved, adoptedExisting: true)
        }
        if item.detectedSwipeURL == nil {
            var prepared = Atom.swipeFromRawText(text: item.rawText, hook: item.title)
            prepared = prepared.withSwipeArtifact(SwipeArtifact(kind: .note, units: SwipeTextSlicer.units(from: item.rawText), captureMode: "inbox"))
            let (saved, _) = try await executeFiling(item: item,
                destination: .init(kind: .swipe, name: "Swipe", path: "Swipe"), preparedAtom: prepared)
            SwipeIntakeRouter.noteExternallyCreatedSwipe(saved, publishesReceipt: false)
            return SwipeFilingOutcome(atom: saved, adoptedExisting: false)
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
        atom = try await executeFiling(item: item,
            destination: .init(kind: .swipe, name: "Swipe", path: "Swipe"), preparedAtom: atom).0
        CloudSwipeAPI.kickProcessing(swipeUUID: atom.uuid)
        SwipeIntakeRouter.noteExternallyCreatedSwipe(atom, publishesReceipt: false)

        return SwipeFilingOutcome(atom: atom, adoptedExisting: false)
    }

    /// An image-only capture becomes a FRAME swipe, decomposed like any other.
    ///
    /// The attachments are re-homed onto the new atom (`adoptAttachments`)
    /// rather than copied, so the bytes the phone already mirrored are the
    /// same bytes the swipe reads — no second upload, no orphaned row.
    /// Returns nil when nothing readable survives, so the caller falls through
    /// to the link path rather than creating an empty swipe.
    private func executeFrameSwipe(item: InboxItem) async throws -> Atom? {
        let attachments = (try? await MediaAttachmentRepository.shared.fetch(uuids: item.attachmentUUIDs)) ?? []
        let images = attachments.filter { $0.kind == .image || $0.kind == .screenshot }
        guard !images.isEmpty else { return nil }

        var atom = Atom.new(
            type: .research,
            title: images.count == 1 ? "Screenshot" : "\(images.count) screenshots"
        )
        atom.updateResearchMetadata { meta in
            meta.isSwipeFile = true
            meta.contentSource = SwipeKind.frame.rawValue
            meta.processingStatus = "analyzing"
        }
        let note = item.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { atom.body = note }

        atom = atom.withSwipeArtifact(SwipeArtifact(
            kind: .frame,
            units: images.enumerated().map { index, attachment in
                SwipeArtifactUnit(index: index, attachmentUUID: attachment.uuid)
            },
            captureMode: "inbox"
        ))
        if let thumbnail = images.first?.thumbnailPath {
            atom.updateResearchMetadata { $0.thumbnailUrl = URL(fileURLWithPath: thumbnail).absoluteString }
        }
        atom = try await executeFiling(item: item,
            destination: .init(kind: .swipe, name: "Swipe", path: "Swipe"), preparedAtom: atom).0

        // The front door's completion hook — flow append + library refresh.
        // This executor owns its own undo (below) and the Inbox shows its own
        // toast, so it takes neither from the router.
        SwipeIntakeRouter.noteExternallyCreatedSwipe(atom, publishesReceipt: false)

        // Decompose off the main path — the capture is already filed, and the
        // vision + craft passes take seconds.
        let uuid = atom.uuid
        Task { @MainActor in
            await SwipeFrameDecomposition.run(swipeUUID: uuid, note: note.isEmpty ? nil : note)
        }

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
        try await requireInboxSource(item)
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
        try await requireInboxSource(item)
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
        guard let move = recommendation.atlasMove, let uuid = move.connectionUUID,
              let target = try await atomRepo.fetch(uuid: uuid), !target.isDeleted else { return nil }
        let name = target.title ?? "Concept"
        return try await executeFiling(item: item,
            destination: .init(kind: .connection, uuid: uuid, name: name, path: "Concepts › \(name)"),
            section: move.connectionSection).0
    }

    /// The capture is a content idea for a client: a typed idea atom carrying
    /// the client link + metadata (the FlashLiteRouter post-process contract),
    /// enriched by the idea pipeline.
    @discardableResult
    func executeAttachClient(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove, let uuid = move.clientUUID,
              let target = try await atomRepo.fetch(uuid: uuid), !target.isDeleted else { return nil }
        let name = target.title ?? "Client"
        let atom = try await executeFiling(item: item,
            destination: .init(kind: .ideas, uuid: uuid, name: name, path: "Content › \(name) › Ideas")).0
        Task { await IdeaInsightEngine.shared.quickEnrich(atom: atom) }
        return atom
    }

    /// The capture adds mass to a growing seedling — no atom is created, no
    /// canvas is touched. The thought accrues with provenance; the seedling
    /// ripens toward one development conversation.
    @discardableResult
    func executeFeedSeedling(item: InboxItem, recommendation: InboxRecommendation) async throws -> Seedling? {
        try await requireInboxSource(item)
        guard let move = recommendation.atlasMove,
              let seedlingUUID = move.seedlingUUID,
              let seedling = try await SeedlingRepository.shared.fetch(uuid: seedlingUUID),
              !seedling.isDeleted, seedling.status != .developed else { return nil }

        let thought = SeedlingThought(text: item.rawText, sourceKind: .inbox, sourceUUID: item.uuid)
        // A nil feed means the dedup guard caught a repeat (same capture) —
        // the thought is already growing there, which IS the desired state.
        let fed = try await SeedlingRepository.shared.feed(uuid: seedlingUUID, thought: thought) ?? seedling
        await stampAffinityIfNamed(seedlingUUID: seedlingUUID, move: move)
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
        try await requireInboxSource(item)
        let name = recommendation.atlasMove?.germinateTitle ?? item.title ?? fallbackTitle(for: item)
        let thought = SeedlingThought(text: item.rawText, sourceKind: .inbox, sourceUUID: item.uuid)

        // A live seedling already carries this concept key? Feed it instead
        // of forking a twin — starting twice is a vocabulary echo, not intent.
        let seedling: Seedling
        let fedExisting: Bool
        var scopeDive: Atom?
        if let existing = try await SeedlingRepository.shared.fetchLive(conceptKey: ConceptResolver.conceptKey(name)) {
            seedling = try await SeedlingRepository.shared.feed(uuid: existing.uuid, thought: thought) ?? existing
            fedExisting = true
        } else {
            // Born in its dive world when the routed home names one: the
            // seedling joins that dive's SEEDLINGS row and map instead of
            // the unrooted shelf.
            scopeDive = await inferDiveScope(homeThinkspaceId: recommendation.atlasMove?.homeThinkspaceId)
            seedling = try await SeedlingRepository.shared.create(
                Seedling.new(name: name, firstThought: thought, scopeDeepDiveUUID: scopeDive?.uuid)
            )
            fedExisting = false
            if let scopeDive {
                NotificationCenter.default.post(
                    name: CosmoNotification.Inquiry.seedbedChanged,
                    object: nil,
                    userInfo: ["deepDiveUUID": scopeDive.uuid]
                )
            }
        }
        await stampAffinityIfNamed(seedlingUUID: seedling.uuid, move: recommendation.atlasMove)

        let startedOutcome = scopeDive?.title.map { "Started concept \u{201C}\(seedling.name)\u{201D} in \($0)" }
            ?? "Started concept \u{201C}\(seedling.name)\u{201D}"
        try? await inboxRepo.updateMetadata(uuid: item.uuid, merging: [
            "actionOutcome": fedExisting
                ? "Grew \u{201C}\(seedling.name)\u{201D}"
                : startedOutcome
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

    /// The concept's home space names its dive world: when the routed home
    /// thinkspace hosts exactly ONE deep dive, a germinated seedling scopes
    /// to it. Ambiguity abstains — zero or several dives on that space means
    /// the seedling stays unrooted rather than guessing a home.
    private func inferDiveScope(homeThinkspaceId: String?) async -> Atom? {
        guard let homeThinkspaceId else { return nil }
        let dives = (try? await AtomRepository.shared.fetchAll(type: .deepDive)) ?? []
        let hosted = dives.filter { dive in
            !dive.isDeleted && dive.linksList.contains {
                $0.type == AtomLinkType.deepDiveParent.rawValue && $0.uuid == homeThinkspaceId
            }
        }
        return hosted.count == 1 ? hosted.first : nil
    }

    /// A routed move that named the concept's future home stamps the
    /// seedling's affinity — fill-only, so a hint never overwrites a home an
    /// earlier confident route (or the user's own development) established.
    private func stampAffinityIfNamed(seedlingUUID: String, move: InboxAtlasMove?) async {
        guard let move, move.homeThinkspaceId != nil || move.homeClusterId != nil else { return }
        try? await SeedlingRepository.shared.setAffinity(
            uuid: seedlingUUID,
            thinkspaceId: move.homeThinkspaceId,
            thinkspaceName: move.homeThinkspaceName,
            clusterId: move.homeClusterId,
            clusterName: move.homeClusterName
        )
    }

    // MARK: - Space inquiries (September 2026 — the capture → inquiry loop)

    /// What starting an inquiry produced: the session, its Space, and every
    /// atom the start CREATED (session, question, profile, first note) so
    /// undo takes back exactly those and leaves pre-existing research alone.
    struct InquiryStart: Sendable {
        let session: Atom
        let spaceID: String
        let spaceName: String
        let createdAtomUUIDs: [String]
        /// Set when the move also created the hosting Space.
        let createdSpaceID: String?
    }

    /// The capture is something to research inside a Space the user already
    /// has: an inquiry session starts there with the capture as its question.
    @discardableResult
    func executeStartInquiry(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        guard let move = recommendation.atlasMove, let spaceID = move.spaceUUID else { return nil }
        let question = move.newQuestionTitle ?? item.title ?? String(item.rawText.prefix(120))
        return try await executeStartInquiry(item: item, spaceID: spaceID, question: question)?.session
    }

    /// Manual verb twin — the inspector's "Start inquiry in…" menu and the
    /// destination sheet. Nil when the Space no longer exists.
    @discardableResult
    func executeStartInquiry(item: InboxItem, spaceID: String, question: String?) async throws -> InquiryStart? {
        _ = try await settlement(for: item)
        guard let space = try await atomRepo.fetch(uuid: spaceID), !space.isDeleted, space.type == .thinkspace else { return nil }
        let spaceName = space.metadataValue(as: ThinkspaceMetadata.self)?.name ?? space.title ?? "Space"
        return try await startInquiry(item: item, spaceID: spaceID, spaceName: spaceName, question: question, createdSpaceID: nil)
    }

    /// The capture opens a research topic no Space covers yet: a NEW Space
    /// named for the topic, with the inquiry started inside it. (Pre-September
    /// 2026 this made a standalone deep dive nobody could find; Spaces host
    /// inquiries now, so a topic with no home gets one.)
    @discardableResult
    func executeGerminateDeepDive(item: InboxItem, recommendation: InboxRecommendation) async throws -> Atom? {
        let topicTitle = recommendation.atlasMove?.germinateTitle ?? item.title ?? fallbackTitle(for: item)
        let question = item.title ?? String(item.rawText.prefix(120))
        return try await executeStartInquiryInNewSpace(item: item, spaceName: topicTitle, question: question)?.session
    }

    /// Manual twin of the new-Space move: create the Space, then start the
    /// inquiry inside it. Nil when the Space could not be created.
    @discardableResult
    func executeStartInquiryInNewSpace(item: InboxItem, spaceName: String, question: String?) async throws -> InquiryStart? {
        _ = try await settlement(for: item)
        let name = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let space = await ThinkspaceManager.shared.createThinkspace(name: name) else { return nil }
        do {
            return try await startInquiry(item: item, spaceID: space.id, spaceName: space.name, question: question, createdSpaceID: space.id)
        } catch {
            // The Space was made for this inquiry alone — a failed start must
            // not strand an empty Space in the sidebar.
            await ThinkspaceManager.shared.softDelete(space.id)
            throw error
        }
    }

    /// The one inquiry-start path: resumes an identical open question in the
    /// Space (SpaceResearchService.start dedups by question key), keeps any
    /// prose beyond the question as the session's first note, carries the
    /// capture's originals across, settles the capture, and registers undo.
    private func startInquiry(
        item: InboxItem,
        spaceID: String,
        spaceName: String,
        question: String?,
        createdSpaceID: String?
    ) async throws -> InquiryStart {
        let cleaned = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleaned.isEmpty ? fallbackTitle(for: item) : cleaned

        // Snapshot the Space's research BEFORE starting, so undo removes only
        // what this start created — never a question or profile that was
        // already there.
        let existing = await existingResearchUUIDs(in: spaceID)
        let session = try await SpaceResearchService.start(spaceID: spaceID, question: title)

        var created: [String] = []
        if !existing.contains(session.uuid) { created.append(session.uuid) }
        let questionUUID = session.inquirySessionMetadata?.mainQuestionUUID
        let profileUUID = session.inquirySessionMetadata?.parentDeepDiveUUID
        if let questionUUID, !existing.contains(questionUUID) { created.append(questionUUID) }
        if let profileUUID, !existing.contains(profileUUID) { created.append(profileUUID) }

        // The raw capture often carries more than the cleaned question —
        // keep it as the session's first note instead of throwing words away.
        if normalizedText(item.rawText) != normalizedText(title) {
            if let note = try? await InquiryRepository.shared.createExtract(
                body: item.rawText,
                kind: .note,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: questionUUID,
                deepDiveUUID: profileUUID,
                branchNodeId: nil,
                sourceTabId: nil,
                userNote: nil,
                originType: "inboxAtlasRoute",
                citation: nil
            ) {
                created.append(note.uuid)
                await reindex(atom: note)
            }
        }

        let provenance = captureProvenance(for: item)
        _ = try? await atomRepo.update(uuid: session.uuid) { atom in
            atom = atom.mergingMetadataKeys(provenance)
        }
        await adoptAttachments(from: item, into: session.uuid)
        await reindex(atom: session)

        let start = InquiryStart(
            session: session,
            spaceID: spaceID,
            spaceName: spaceName,
            createdAtomUUIDs: created,
            createdSpaceID: createdSpaceID
        )
        let source = try await settlement(for: item)
        try await settle(source, start: start)
        await registerInquiryUndo(start: start, source: source)
        NotificationCenter.default.post(name: CosmoNotification.Entity.updated, object: nil)
        return start
    }

    /// Where a capture lives — the queue or a lane ledger — decides how it
    /// settles and how undo puts it back. Lane captures arrive as proxies
    /// (`captureRecordKind == "lane"`), so the verb never has to know.
    private enum CaptureSettlement {
        case inbox(InboxItem)
        case lane(CapturedItem)
    }

    private func settlement(for item: InboxItem) async throws -> CaptureSettlement {
        switch item.captureReference.kind {
        case .inbox:
            guard try await inboxRepo.fetch(uuid: item.uuid) != nil else { throw InboxPlacementError.unsupported }
            return .inbox(item)
        case .lane:
            guard let row = try await CapturedItemRepository.shared.fetch(uuid: item.uuid) else { throw InboxPlacementError.unsupported }
            return .lane(row)
        }
    }

    /// Settle the capture as "became an inquiry": the queue row is actioned
    /// with the honest outcome; a lane row is applied with the session in its
    /// created-objects ledger and its inquiry parents stamped.
    private func settle(_ source: CaptureSettlement, start: InquiryStart) async throws {
        switch source {
        case .inbox(let item):
            try await inboxRepo.markActioned(uuid: item.uuid, outcome: "Inquiry started in \(start.spaceName)")
        case .lane(let row):
            try await CapturedItemRepository.shared.updateRouting(
                uuid: row.uuid,
                destinationId: row.captureDestinationId,
                parsedCommand: row.parsedCommand,
                parsedIntent: "lane_start_inquiry",
                confidence: row.routingConfidence,
                status: .applied,
                createdObjectIds: row.createdObjectIds + [start.session.uuid],
                parentDeepDiveId: start.session.inquirySessionMetadata?.parentDeepDiveUUID ?? row.parentDeepDiveId,
                parentInquirySessionId: start.session.uuid,
                parentQuestionId: start.session.inquirySessionMetadata?.mainQuestionUUID ?? row.parentQuestionId,
                parentProjectId: row.parentProjectId
            )
            NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
        }
    }

    /// The inverse of `settle` — the queue row comes back, or the lane row
    /// returns to exactly the routing it had.
    private func unsettle(_ source: CaptureSettlement) async {
        switch source {
        case .inbox(let item):
            try? await inboxRepo.restore(item)
        case .lane(let row):
            try? await CapturedItemRepository.shared.updateRouting(
                uuid: row.uuid,
                destinationId: row.captureDestinationId,
                parsedCommand: row.parsedCommand,
                parsedIntent: row.parsedIntent,
                confidence: row.routingConfidence,
                status: row.status,
                createdObjectIds: row.createdObjectIds,
                parentDeepDiveId: row.parentDeepDiveId,
                parentInquirySessionId: row.parentInquirySessionId,
                parentQuestionId: row.parentQuestionId,
                parentProjectId: row.parentProjectId
            )
            NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
        }
    }

    /// Every research atom already attached to the Space's profiles — the
    /// baseline `startInquiry` diffs against to know what it created.
    private func existingResearchUUIDs(in spaceID: String) async -> Set<String> {
        var uuids = Set<String>()
        var profiles = (try? await InquiryRepository.shared.fetchDeepDives(in: spaceID)) ?? []
        if let space = try? await atomRepo.fetch(uuid: spaceID),
           let explicit = (try? SpaceResearchSchema.object(space.metadata))?["deepDiveProfileUUID"] as? String,
           !profiles.contains(where: { $0.uuid == explicit }),
           let profile = try? await atomRepo.fetch(uuid: explicit) {
            profiles.append(profile)
        }
        for profile in profiles {
            uuids.insert(profile.uuid)
            for question in (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: profile.uuid)) ?? [] {
                uuids.insert(question.uuid)
            }
            for session in (try? await InquiryRepository.shared.fetchSessions(forDeepDive: profile.uuid)) ?? [] {
                uuids.insert(session.uuid)
            }
        }
        return uuids
    }

    /// Undo deletes exactly the atoms (and Space) the start created and puts
    /// the capture back; redo restores those snapshots and re-settles it.
    private func registerInquiryUndo(start: InquiryStart, source: CaptureSettlement) async {
        var snapshots: [Atom] = []
        for uuid in start.createdAtomUUIDs {
            if let atom = try? await atomRepo.fetch(uuid: uuid) { snapshots.append(atom) }
        }
        let createdSpaceID = start.createdSpaceID
        let createdUUIDs = start.createdAtomUUIDs
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Start Inquiry") { [weak self] in
                guard let self else { return }
                for uuid in createdUUIDs {
                    try? await self.atomRepo.delete(uuid: uuid)
                }
                if let createdSpaceID {
                    await ThinkspaceManager.shared.softDelete(createdSpaceID)
                }
                await self.unsettle(source)
                NotificationCenter.default.post(name: CosmoNotification.Entity.updated, object: nil)
            } redo: { [weak self] in
                guard let self else { return }
                if let createdSpaceID {
                    await ThinkspaceManager.shared.restoreThinkspace(createdSpaceID)
                }
                for atom in snapshots {
                    try? await self.restoreAtomSnapshot(atom)
                    await self.reindex(atom: atom)
                }
                try? await self.settle(source, start: start)
                NotificationCenter.default.post(name: CosmoNotification.Entity.updated, object: nil)
            }
        )
    }

    // MARK: - Move a queue capture into a lane (September 2026)

    /// File a queued capture into a capture lane by a direct choice — the
    /// inspector's "Move to lane" menu or the destination sheet. Builds the
    /// lane ledger row exactly as the alias-prefix path does, carries the
    /// capture's originals across (the lane ledger resolves pages by
    /// `capturedItemId`), settles the queue row with the honest outcome, and
    /// bumps the lane's recency. Undo archives the lane row, hands the
    /// originals back, and restores the queue item — the iOS engine's
    /// `route(item:toLane:)` contract, twin-for-twin.
    @discardableResult
    func executeRouteToLane(item: InboxItem, lane: CaptureDestination) async throws -> CapturedItem {
        try await requireInboxSource(item)
        let attachmentUUIDs = item.attachmentUUIDs

        var row = CapturedItem.makeTelegram(rawText: item.rawText, caption: nil, chatId: "", messageId: nil)
        row.source = .quickCapture
        row.telegramChatId = nil
        row.captureDestinationId = lane.uuid
        row.parsedIntent = "inbox_move_to_lane"
        row.status = .routed
        row.routingConfidence = 1
        if let data = try? JSONEncoder().encode(attachmentUUIDs) {
            row.mediaAttachmentIdsJSON = String(data: data, encoding: .utf8)
        }
        var provenance: [String: Any] = ["captureSource": "mac", "movedFromInboxUUID": item.uuid]
        if !attachmentUUIDs.isEmpty { provenance["attachmentUUIDs"] = attachmentUUIDs }
        if let data = try? JSONSerialization.data(withJSONObject: provenance) {
            row.provenanceMetadata = String(data: data, encoding: .utf8)
        }
        let saved = try await CapturedItemRepository.shared.create(row)

        // The originals follow the capture into the lane. A failed re-own
        // never fails the move — the thumbs still resolve by uuid.
        var previousOwners: [(uuid: String, ownerType: String, ownerUUID: String, capturedItemId: String)] = []
        for uuid in attachmentUUIDs {
            if let attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: uuid) {
                previousOwners.append((uuid, attachment.ownerType, attachment.ownerUUID, attachment.capturedItemId))
            }
            _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: uuid) { attachment in
                attachment.ownerType = MediaAttachmentOwner.capturedItem.rawValue
                attachment.ownerUUID = saved.uuid
                attachment.capturedItemId = saved.uuid
                return true
            }
        }

        await CaptureDestinationRepository.shared.markUsed(uuid: lane.uuid)
        try await inboxRepo.markActioned(uuid: item.uuid, outcome: "Moved to \(lane.name)")
        Self.postLaneChanged(laneID: lane.uuid)

        let originalItem = item
        let owners = previousOwners
        let laneName = lane.name
        let savedUUID = saved.uuid
        CosmoUndoManager.shared.register(
            InlineUndoAction(actionDescription: "Move Capture to Lane") { [weak self] in
                guard let self else { return }
                try? await Self.setLaneRowStatus(saved, to: .archived, intent: "inbox_move_to_lane_undo")
                for owner in owners {
                    _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: owner.uuid) { attachment in
                        attachment.ownerType = owner.ownerType
                        attachment.ownerUUID = owner.ownerUUID
                        attachment.capturedItemId = owner.capturedItemId
                        return true
                    }
                }
                try? await self.inboxRepo.restore(originalItem)
                Self.postLaneChanged(laneID: lane.uuid)
            } redo: { [weak self] in
                guard let self else { return }
                try? await Self.setLaneRowStatus(saved, to: .routed, intent: "inbox_move_to_lane")
                for owner in owners {
                    _ = try? await MediaAttachmentRepository.shared.trackedMutation(uuid: owner.uuid) { attachment in
                        attachment.ownerType = MediaAttachmentOwner.capturedItem.rawValue
                        attachment.ownerUUID = savedUUID
                        attachment.capturedItemId = savedUUID
                        return true
                    }
                }
                try? await self.inboxRepo.markActioned(uuid: originalItem.uuid, outcome: "Moved to \(laneName)")
                Self.postLaneChanged(laneID: lane.uuid)
            }
        )
        return saved
    }

    /// A status flip that keeps every other routing field as the row has it
    /// (CaptureLanesViewModel's contract).
    private static func setLaneRowStatus(_ row: CapturedItem, to status: CapturedItemStatus, intent: String) async throws {
        try await CapturedItemRepository.shared.updateRouting(
            uuid: row.uuid,
            destinationId: row.captureDestinationId,
            parsedCommand: row.parsedCommand,
            parsedIntent: intent,
            confidence: row.routingConfidence,
            status: status,
            createdObjectIds: row.createdObjectIds,
            parentDeepDiveId: row.parentDeepDiveId,
            parentInquirySessionId: row.parentInquirySessionId,
            parentQuestionId: row.parentQuestionId,
            parentProjectId: row.parentProjectId
        )
    }

    private static func postLaneChanged(laneID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Inbox.itemAdded,
            object: nil,
            userInfo: ["captureDestinationId": laneID]
        )
        NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
    }

    /// Shared undo shape for Atlas moves that created one primary atom:
    /// undo deletes the atom and restores the capture; redo re-persists it.
    /// Specialized legacy development commands have queue-owned inverses.
    /// Lane originals use the typed filing commands until those domains expose
    /// a lane-aware transaction; never manufacture an Inbox row on Undo.
    private func requireInboxSource(_ item: InboxItem) async throws {
        guard item.captureReference.kind == .inbox,
              try await inboxRepo.fetch(uuid: item.uuid) != nil else { throw InboxPlacementError.unsupported }
    }

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

    /// Place an ALREADY-created atom on a thinkspace canvas at a planned
    /// position. The develop flow uses this so a concept page born from a
    /// seedling lands in the home its affinity named — same planner, same
    /// block persistence as inbox placements. No inbox item involved.
    func placeExistingAtomOnCanvas(atom: Atom, thinkspaceId: String) async {
        let thinkspaceName = await resolveThinkspaceName(for: thinkspaceId) ?? "Thinkspace"
        let plan = await planner.planForThinkspacePlacement(
            title: atom.title ?? "Untitled",
            atomType: atom.type,
            thinkspaceId: thinkspaceId,
            thinkspaceName: thinkspaceName,
            relatedAtomUUIDs: []
        )
        guard let x = plan?.blockPositionX, let y = plan?.blockPositionY else { return }
        let block = CanvasBlock.fromAtom(atom, position: CGPoint(x: x, y: y))
        let record = CanvasBlockRecord.from(block, documentType: "home", documentId: 0, thinkspaceId: thinkspaceId, isPlaced: false)
        try? await persistCanvasBlockSnapshot(record)
        await refreshThinkspace(thinkspaceId)
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

}
