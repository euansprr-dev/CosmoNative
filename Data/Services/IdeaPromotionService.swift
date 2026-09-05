// CosmoOS/Data/Services/IdeaPromotionService.swift
// Begin Writing, as a service: an idea becomes a content piece with everything
// it earned on the bench — blueprint and linked swipes (blueprint FIRST, the
// cloud engine reads index 0 as primary), linked concepts, the framework, the
// hooks (the starred one leads), the codex outline as the draft's skeleton,
// research, chat history — and the idea flips to In production, its writing
// sessions retargeted. The idea bench, the Pipeline board and the calendar
// all promote through THIS path, so the three can never drift again.
//
// Name matches the iPhone's `IdeaPromotionService` (a parity twin).

import Foundation
import GRDB

@MainActor
enum IdeaPromotionService {
    private static var inFlight: Set<String> = []

    struct PromotionOptions: Sendable {
        /// Run the insight pass when it is nil or older than an hour — the
        /// bench does; a board drop skips it (writing starts at once).
        var refreshInsightIfStale = true
        /// Land straight on a calendar day (calendar / Scheduled-column drops).
        var scheduleOn: Date? = nil
        /// The stage the piece lands in (board drops into Draft or Polish).
        var initialPhase: ContentPhase = .ideation
        var productionStage: ContentProductionStage = .inProgress
        /// Carry the inline assistant's ideation transcript into the piece.
        var carryAssistantSession = true
        /// Leave the Atelier breadcrumb and open the writing bench — bench only.
        var openFocusMode = false
        /// Session-only bench state the atom does not hold yet (nil = read the atom).
        var selectedFramework: String? = nil
        var selectedHookIndex: Int? = nil
        var titleOverride: String? = nil
        var bodyOverride: String? = nil
        var mentionedAtoms: [Atom]? = nil

        init(
            refreshInsightIfStale: Bool = true,
            scheduleOn: Date? = nil,
            initialPhase: ContentPhase = .ideation,
            productionStage: ContentProductionStage = .inProgress,
            carryAssistantSession: Bool = true,
            openFocusMode: Bool = false,
            selectedFramework: String? = nil,
            selectedHookIndex: Int? = nil,
            titleOverride: String? = nil,
            bodyOverride: String? = nil,
            mentionedAtoms: [Atom]? = nil
        ) {
            self.refreshInsightIfStale = refreshInsightIfStale
            self.scheduleOn = scheduleOn
            self.initialPhase = initialPhase
            self.productionStage = productionStage
            self.carryAssistantSession = carryAssistantSession
            self.openFocusMode = openFocusMode
            self.selectedFramework = selectedFramework
            self.selectedHookIndex = selectedHookIndex
            self.titleOverride = titleOverride
            self.bodyOverride = bodyOverride
            self.mentionedAtoms = mentionedAtoms
        }
    }

    struct PromotionResult: Sendable {
        let content: Atom
        /// The idea after the write (status In production, contentUUIDs appended).
        let idea: Atom
        let assistantSessionCarried: Bool
        let retargetedSessionCount: Int
        /// The idea's pre-write metadata and links, for `revert`.
        let ideaMetadataBefore: String?
        let ideaLinksBefore: String?
    }

    enum PromotionError: Error, LocalizedError {
        case ideaNotFound
        case alreadyStarting

        var errorDescription: String? {
            switch self {
            case .ideaNotFound: return "That idea no longer exists."
            case .alreadyStarting: return "A piece is already being started from this idea."
            }
        }
    }

    // MARK: - Promote

    static func promote(ideaUUID: String, options: PromotionOptions = PromotionOptions()) async throws -> PromotionResult {
        guard inFlight.insert(ideaUUID).inserted else { throw PromotionError.alreadyStarting }
        defer { inFlight.remove(ideaUUID) }
        guard var idea = try await AtomRepository.shared.fetch(uuid: ideaUUID), idea.type == .idea, !idea.isDeleted else {
            throw PromotionError.ideaNotFound
        }

        // 1. Insight freshness — nil or stale (>1h) reruns the analysis and
        //    stamps lastAnalyzedAt, exactly as the bench did.
        var insight = idea.ideaInsight
        if options.refreshInsightIfStale, insight == nil || isInsightStale(idea) {
            let result = await IdeaInsightEngine.shared.fullAnalysis(atom: idea)
            insight = result
            var analysisAtom = idea.withIdeaInsight(result)
            analysisAtom = analysisAtom.withUpdatedIdeaMetadata { meta in
                meta.lastAnalyzedAt = ISO8601.string(from: Date())
            }
            analysisAtom.updatedAt = ISO8601.string(from: Date())
            idea = try await AtomRepository.shared.update(analysisAtom)
        }

        let meta = idea.ideaMetadata
        let title = (options.titleOverride ?? idea.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = options.bodyOverride ?? idea.body ?? ""
        let nowISO = ISO8601.string(from: Date())

        // 2. The content atom. The idea text goes into contentDescription;
        //    draftContent starts as a slide workspace only when the user
        //    composed a multi-slide outline.
        let contentAtom = Atom.new(type: .content, title: title.isEmpty ? "Untitled" : title,
                                   body: nil, metadata: nil)

        // 3. Swipe inheritance — blueprint FIRST, then supporting swipes,
        //    then insight matches; deduped, order preserved.
        var allSwipeUUIDs: [String] = []
        let blueprintUUID = meta?.blueprintUUID
        if let blueprintUUID { allSwipeUUIDs.append(blueprintUUID) }
        let linkedSwipeUUIDs = meta?.linkedSwipeIds ?? []
        let insightSwipeUUIDs = insight?.matchingSwipes?.map(\.swipeAtomUUID) ?? []
        for uuid in linkedSwipeUUIDs + insightSwipeUUIDs where !allSwipeUUIDs.contains(uuid) {
            allSwipeUUIDs.append(uuid)
        }

        // 4. Concepts; 5. framework (session choice, else the insight's first).
        let linkedConnectionUUIDs = meta?.linkedConnectionIds ?? []
        let inheritedFramework = options.selectedFramework
            ?? insight?.frameworkRecommendations?.first?.framework.rawValue

        // 6. The user's hooks only; the working (starred) hook leads.
        let inheritedHooks: [String] = {
            let hooks = meta?.hooks ?? []
            guard !hooks.isEmpty else { return [] }
            if let chosen = options.selectedHookIndex, hooks.indices.contains(chosen) {
                var reordered = hooks
                reordered.insert(reordered.remove(at: chosen), at: 0)
                return reordered
            }
            return hooks
        }()

        // 7. Client.
        let inheritedClientUUID = meta?.clientUUID

        // 8. Focus state: description = the idea text with mentions expanded.
        let mentionedUUIDs = meta?.mentionedAtomUUIDs ?? []
        let mentionedAtoms: [Atom]
        if let provided = options.mentionedAtoms {
            mentionedAtoms = provided
        } else if !mentionedUUIDs.isEmpty {
            mentionedAtoms = (try? await AtomRepository.shared.fetchBatch(uuids: mentionedUUIDs)) ?? []
        } else {
            mentionedAtoms = []
        }
        var enrichedBody = body
        if !mentionedAtoms.isEmpty {
            enrichedBody = MentionContextHelper.expandMentionsForWritingEngine(text: body, atoms: mentionedAtoms)
        }
        var focusState = ContentFocusModeState(atomUUID: contentAtom.uuid)
        focusState.contentDescription = enrichedBody
        focusState.coreIdea = enrichedBody
        focusState.hooks = inheritedHooks
        focusState.clientProfileUUID = inheritedClientUUID

        let codexOutline: CodexOutlineModel? = meta?.codexOutline
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(CodexOutlineModel.self, from: $0) }
        if let codexOutline, let draftTemplate = CodexOutlineDraftTemplate.make(from: codexOutline) {
            focusState.draftContent = draftTemplate
            focusState.richDraftDocument = RichDocument.migrateLegacy(draftTemplate)
        }
        if let codexOutline, !codexOutline.slides.isEmpty {
            focusState.outline = codexOutline.slides.compactMap { slide in
                guard let note = slide.note, !note.isEmpty else { return nil }
                return OutlineItem(title: note, reasoning: "", sortOrder: slide.position - 1)
            }
            if focusState.outline.isEmpty {
                focusState.outline = codexOutline.slides.map { slide in
                    OutlineItem(title: "Slide \(slide.position)", reasoning: "", sortOrder: slide.position - 1)
                }
            }
            focusState.isAISuggestedOutline = false
        }

        // 9. ContentAtomMetadata — every inherited field, plus the landing stage.
        var contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self)
            ?? ContentAtomMetadata(phase: .ideation, wordCount: 0)
        contentMeta.phase = options.initialPhase
        contentMeta.platform = meta?.platform.flatMap { SocialPlatform(rawValue: $0.rawValue) }
        contentMeta.contentFormat = meta?.contentFormat?.rawValue
        contentMeta.sourceIdeaUUID = idea.uuid
        contentMeta.inheritedSwipeUUIDs = allSwipeUUIDs.isEmpty ? nil : allSwipeUUIDs
        contentMeta.inheritedConnectionIds = linkedConnectionUUIDs.isEmpty ? nil : linkedConnectionUUIDs
        contentMeta.inheritedMentionedAtomUUIDs = mentionedUUIDs.isEmpty ? nil : mentionedUUIDs
        contentMeta.inheritedFramework = inheritedFramework
        contentMeta.inheritedHooks = inheritedHooks.isEmpty ? nil : inheritedHooks
        contentMeta.clientProfileUUID = inheritedClientUUID
        contentMeta.blueprintSwipeUUID = blueprintUUID
        contentMeta.activatedAt = nowISO
        contentMeta.phaseEnteredAt = nowISO
        contentMeta.inheritedArcType = meta?.arcType
        contentMeta.inheritedCodexOutline = meta?.codexOutline
        contentMeta.inheritedCreativeDirection = meta?.creativeDirection.flatMap { $0.isEmpty ? nil : $0 }
        contentMeta.inheritedContext = meta?.context.flatMap { $0.isEmpty ? nil : $0 }
        let includedResearch: [IdeaResearchResult] = (meta?.researchResults
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([IdeaResearchResult].self, from: $0) } ?? [])
            .filter { $0.isIncluded }
        if !includedResearch.isEmpty, let data = try? JSONEncoder().encode(includedResearch) {
            contentMeta.inheritedResearchResults = String(data: data, encoding: .utf8)
        }
        focusState.inheritedResearchResults = includedResearch.isEmpty ? nil : includedResearch
        contentMeta.inheritedChatHistory = meta?.chatHistory.flatMap { $0.isEmpty ? nil : $0 }
        var elementNames: Set<String> = []
        if let codexOutline {
            for slide in codexOutline.slides {
                if let act = slide.speechAct { elementNames.insert(act) }
                elementNames.formUnion(slide.readerDeltas)
                if let frame = slide.frame { elementNames.insert(frame) }
                if let distance = slide.distance { elementNames.insert(distance) }
                elementNames.formUnion(slide.techniques)
                if let transition = slide.transition { elementNames.insert(transition) }
            }
        }
        contentMeta.codexElementNames = elementNames.isEmpty ? nil : Array(elementNames)

        // 10. Merge the focus state into the content atom + links.
        let focusFields = focusState.toAtomFields(existingMetadata: contentMeta.toJSON())
        var updatedContent = contentAtom.addingLink(.contentToIdea(idea.uuid))
        if let inheritedClientUUID {
            updatedContent = updatedContent.addingLink(.contentToClient(inheritedClientUUID))
        }
        for source in idea.linksList where source.type == "source" {
            updatedContent = updatedContent.addingLink(source)
        }
        updatedContent.metadata = focusFields.metadata
        updatedContent.body = focusFields.body
        var contentFields = updatedContent.metadataDict ?? [:]
        contentFields["contentType"] = meta?.contentFormat?.rawValue ?? "post"
        contentFields["productionStage"] = options.productionStage.rawValue
        contentFields["status"] = options.scheduleOn == nil ? "draft" : "scheduled"
        if let day = options.scheduleOn {
            contentFields["scheduledAt"] = ISO8601.string(from: day)
            contentFields["scheduledDate"] = ISO8601.string(from: day)
        }
        updatedContent.metadata = String(decoding: try JSONSerialization.data(withJSONObject: contentFields), as: UTF8.self)
        updatedContent.updatedAt = nowISO
        let preparedContent = updatedContent
        let membershipTemplate = CanvasBlockRecord.from(
            CanvasBlock.fromAtom(updatedContent, position: .zero), documentType: "home", documentId: 0,
            thinkspaceId: nil, isPlaced: false)
        // Content, lineage and Space memberships commit together. A failed
        // write cannot leave an empty draft or a half-promoted source idea.
        let committed = try await CosmoDatabase.shared.asyncWrite { db -> (Atom, Atom, Atom) in
            guard let before = try Atom.filter(Column("uuid") == ideaUUID).fetchOne(db), !before.isDeleted,
                  before.metadata == nil || before.metadataDict != nil else { throw PromotionError.ideaNotFound }
            var output = preparedContent
            try output.insert(db)
            output.id = db.lastInsertedRowID
            var source = before.addingLink(.ideaToContent(output.uuid))
            source = source.withUpdatedIdeaMetadata { metadata in
                var ids = metadata.contentUUIDs ?? []
                if !ids.contains(output.uuid) { ids.append(output.uuid) }
                metadata.contentUUIDs = ids
            }
            source.updatedAt = nowISO
            source.localVersion += 1
            try source.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid IN (?, ?)", arguments: [source.uuid, output.uuid])
            let spaces = try String.fetchAll(db, sql: """
                SELECT DISTINCT thinkspace_id FROM canvas_blocks WHERE entity_uuid = ?
                AND document_type = 'home' AND document_id = 0 AND is_deleted = 0 AND thinkspace_id IS NOT NULL
                """, arguments: [ideaUUID])
            for spaceID in spaces {
                var row = membershipTemplate
                row.id = UUID().uuidString; row.uuid = row.id
                row.thinkspaceId = spaceID; row.documentUuid = spaceID
                row.entityId = Int(output.id ?? 0)
                try row.insert(db)
            }
            return (output, source, before)
        }
        let (savedContent, savedIdea, beforeIdea) = committed
        let ideaMetadataBefore = beforeIdea.metadata
        let ideaLinksBefore = beforeIdea.links
        await ChangeTracker.shared.trackInsert(table: Atom.databaseTableName, entity: savedContent)
        await ChangeTracker.shared.trackUpdate(table: Atom.databaseTableName, entity: savedIdea, skipVersionIncrement: true)
        try? await NodeGraphEngine.shared.handleAtomCreated(savedContent)
        Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(savedContent) }
        NotificationCenter.default.post(name: Notification.Name("com.cosmo.canvasBlocksChanged"), object: nil)

        // 12. Unfinished writing sessions now open the piece — never fatal.
        let retargeted = (try? await IdeaTaskLinkService.retargetToPromotedContent(
            ideaUUID: savedIdea.uuid,
            content: savedContent
        )) ?? 0

        // 13. The Ideas library drops the idea (it's a content piece now).
        NotificationCenter.default.post(
            name: Notification.Name("ideaActivated"),
            object: nil,
            userInfo: ["uuid": savedIdea.uuid]
        )

        // 14. The assistant's ideation memory follows the idea into writing.
        var carried = false
        if options.carryAssistantSession {
            let ideaSurfaceID = "idea:\(savedIdea.uuid)"
            let contentSurfaceID = "content:\(savedContent.uuid)"
            carried = CosmoInlineAssistantStore.shared.carrySessionIntoPromotedContent(
                fromSurfaceID: ideaSurfaceID,
                toSurfaceID: contentSurfaceID,
                paneNote: "Begin Writing — continued from the idea “\(title)”"
            )
            if carried {
                await CosmoInlineAssistantStore.shared.carryConversationMemoryIntoPromotedContent(
                    fromSurfaceID: ideaSurfaceID,
                    toSurfaceID: contentSurfaceID,
                    transitionNote: """
                    [Phase transition] The user pressed Begin Writing: the idea "\(title)" \
                    was promoted into a new content piece (content atom \(savedContent.uuid)), and the \
                    two atoms are linked. Ideation is finished — this conversation now continues on \
                    the content atom, where the user is drafting the actual piece. Treat the earlier \
                    messages as the brainstorm and research that led here.
                    """
                )
            }
        }

        // 15/16. Bench only: the Atelier breadcrumb and the writing surface.
        if options.openFocusMode {
            FocusTransitionCoordinator.shared.markPromotion(contentAtomUUID: savedContent.uuid)
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: [
                    "atomUUID": savedContent.uuid,
                    "autoGenerate": true,
                    "restoreCommandKOnFocusClose": false
                ]
            )
        }

        // 18/19. Everyone showing content reloads; one ⌘Z brings it all back.
        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
        let result = PromotionResult(
            content: savedContent,
            idea: savedIdea,
            assistantSessionCarried: carried,
            retargetedSessionCount: retargeted,
            ideaMetadataBefore: ideaMetadataBefore,
            ideaLinksBefore: ideaLinksBefore
        )
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: "Begin Writing",
            undo: { try? await revert(result) },
            redo: { try? await restore(result) }
        ))
        return result
    }

    // MARK: - Revert

    /// Undo of a promotion: the content piece goes to Recently Deleted, the
    /// idea gets its pre-write metadata and links back, and any session that
    /// was retargeted onto the piece points at the idea again.
    static func revert(_ result: PromotionResult) async throws {
        try await AtomRepository.shared.delete(uuid: result.content.uuid)

        if var idea = try await AtomRepository.shared.fetch(uuid: result.idea.uuid) {
            var dict = idea.metadataDict ?? [:]
            let before = result.ideaMetadataBefore?.data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            var outputs = dict["contentUUIDs"] as? [String] ?? []
            outputs.removeAll { $0 == result.content.uuid }
            dict["contentUUIDs"] = outputs.isEmpty ? before["contentUUIDs"] : outputs
            idea.metadata = dict.isEmpty && result.ideaMetadataBefore == nil ? nil
                : String(decoding: try JSONSerialization.data(withJSONObject: dict), as: UTF8.self)
            idea = idea.removingLink(ofType: .ideaToContent, toUUID: result.content.uuid)
            // `update` bumps the version itself and matches on the version we
            // read — bumping here first made the optimistic write miss silently.
            _ = try await AtomRepository.shared.update(idea)
        }

        // Un-retarget: sessions whose live link is the piece return to the idea
        // (the exact inverse of `IdeaTaskLinkService.retargetToPromotedContent`).
        let tasks = (try? await AtomRepository.shared.fetchByMetadataSubstring(result.content.uuid, type: .task)) ?? []
        for task in tasks {
            guard var metadata = task.metadataValue(as: TaskMetadata.self) else { continue }
            var linked = IdeaTaskLinkService.linkedAtoms(of: task)
            guard let index = linked.firstIndex(where: { $0.atomUUID == result.content.uuid }) else { continue }
            linked[index].atomUUID = result.idea.uuid
            linked[index].atomType = AtomType.idea.rawValue
            guard let linkedData = try? JSONEncoder().encode(linked),
                  let linkedJSON = String(data: linkedData, encoding: .utf8) else { continue }
            metadata.linkedAtoms = linkedJSON
            if let mentionsJSON = metadata.titleMentions,
               let mentionsData = mentionsJSON.data(using: .utf8),
               var mentions = try? JSONDecoder().decode([RichMention].self, from: mentionsData) {
                for i in mentions.indices where mentions[i].entityUUID == result.content.uuid {
                    mentions[i].entityUUID = result.idea.uuid
                    mentions[i].entityID = result.idea.id
                    mentions[i].entityType = .idea
                }
                if let data = try? JSONEncoder().encode(mentions),
                   let json = String(data: data, encoding: .utf8) {
                    metadata.titleMentions = json
                }
            }
            guard let merged = task.mergingTaskMetadata(
                metadata,
                context: "IdeaPromotionService.revert(\(task.uuid.prefix(8)))"
            ) else { continue }
            _ = try? await AtomRepository.shared.update(merged)
        }
        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
    }

    /// Redo restores the same output identity; it never creates another piece.
    static func restore(_ result: PromotionResult) async throws {
        try await AtomRepository.shared.restore(uuid: result.content.uuid)
        if var idea = try await AtomRepository.shared.fetch(uuid: result.idea.uuid) {
            idea = idea.addingLink(.ideaToContent(result.content.uuid))
            idea = idea.withUpdatedIdeaMetadata { metadata in
                var ids = metadata.contentUUIDs ?? []
                if !ids.contains(result.content.uuid) { ids.append(result.content.uuid) }
                metadata.contentUUIDs = ids
            }
            _ = try await AtomRepository.shared.update(idea)
        }
        _ = try await IdeaTaskLinkService.retargetToPromotedContent(ideaUUID: result.idea.uuid, content: result.content)
        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
    }

    // MARK: - Helpers

    private static func isInsightStale(_ idea: Atom) -> Bool {
        guard let lastAnalyzed = idea.ideaMetadata?.lastAnalyzedAt,
              let date = ISO8601.date(from: lastAnalyzed) else { return true }
        return Date().timeIntervalSince(date) > 3600
    }
}
