import Foundation
import GRDB

/// Filing is one database transaction. Suggestions and UI adapters never settle
/// a capture themselves, and post-save enrichment never owns its identity.
@MainActor
struct InboxPlacementService: Sendable {
    static let shared = InboxPlacementService(database: .shared)
    let database: CosmoDatabase

    func destinations() async throws -> [InboxFilingDestination] {
        try await database.asyncRead { db in try Self.destinations(db: db) }
    }

    func request(for item: InboxItem, destination: InboxFilingDestination,
                 action: InboxFilingAction? = nil, operationID: String = UUID().uuidString) async throws -> InboxPlacementRequest {
        try await database.asyncRead { db in
            let source = try Capture.read(item.captureReference, db: db)
            guard source.text == item.rawText, Set(source.attachments) == Set(item.attachmentUUIDs) else { throw InboxPlacementError.staleSource }
            if !source.isActive, let receipt = source.receipt, !receipt.isUndone,
               receipt.request.destination == destination,
               receipt.request.action == (action ?? destination.defaultAction) { return receipt.request }
            return InboxPlacementRequest(operationID: operationID, source: source.reference,
                expectedSourceVersion: source.version, destination: destination, action: action ?? destination.defaultAction)
        }
    }

    func execute(_ request: InboxPlacementRequest, preparedAtom: Atom? = nil) async throws -> InboxPlacementReceipt {
        let receipt = try await database.asyncWrite { db in try Self.commit(request, preparedAtom: preparedAtom, db: db) }
        await notify(receipt)
        return receipt
    }

    func undo(_ receipt: InboxPlacementReceipt) async throws -> InboxPlacementReceipt {
        let updated = try await database.asyncWrite { db in try Self.reverse(receipt, db: db) }
        await notify(updated)
        return updated
    }

    func redo(_ receipt: InboxPlacementReceipt) async throws -> InboxPlacementReceipt {
        let updated = try await database.asyncWrite { db in
            var capture = try Capture.read(receipt.request.source, db: db)
            guard let current = capture.receipt, current.request.operationID == receipt.request.operationID,
                  current.isUndone else { throw InboxPlacementError.conflict }
            var request = current.request
            request.expectedSourceVersion = capture.version
            if var original = try Atom.filter(Column("uuid") == current.resultAtomUUID).fetchOne(db), original.isDeleted {
                original.isDeleted = false
                try Self.save(&original, db: db)
            }
            if current.request.action == .childPage {
                var child = try Self.requireAtom(current.resultAtomUUID, db: db)
                guard var composition = try child.decodedSpaceComposition(),
                      composition.parentUUID == nil || composition.parentUUID == current.request.destination.uuid else { throw InboxPlacementError.conflict }
                composition.parentUUID = current.request.destination.uuid
                child = try child.replacingSpaceComposition(composition)
                try Self.save(&child, db: db)
            }
            request.existingAtomUUID = current.resultAtomUUID
            capture.removeReceipt()
            try capture.save(db: db)
            request.expectedSourceVersion = capture.version
            var result = try Self.commit(request, preparedAtom: nil, db: db)
            result.createdAtom = current.createdAtom
            var settled = try Capture.read(request.source, db: db)
            try settled.settle(result, db: db)
            return result
        }
        await notify(updated)
        return updated
    }

    private func notify(_ receipt: InboxPlacementReceipt) async {
        await MainActor.run {
            SpaceMembershipService.notifyMembersChanged()
            NotificationCenter.default.post(name: SpaceCompositionService.didChange, object: nil)
            NotificationCenter.default.post(name: CosmoNotification.Inbox.captureLaneChanged, object: nil)
            if receipt.request.destination.kind == .connection {
                NotificationCenter.default.post(name: CosmoNotification.Connection.stagedInsertsChanged, object: nil,
                    userInfo: ["connectionUUID": receipt.resultAtomUUID])
            }
        }
        await InboxDestinationAtlas.shared.invalidate()
        if let atom = try? await database.asyncRead({ db in try Atom.filter(Column("uuid") == receipt.resultAtomUUID).fetchOne(db) }) {
            await RecallIndexer.shared.noteAtomChanged(atom)
        }
    }

    // MARK: - Read-only destination catalogue

    nonisolated static func destinations(db: Database) throws -> [InboxFilingDestination] {
        var result = [InboxFilingDestination(kind: .pages, name: "Pages", path: "Pages")]
        let spaces = try Atom.filter(Column("type") == AtomType.thinkspace.rawValue)
            .filter(Column("uuid") != "00000000-CC00-4000-A000-COMMANDCENTER")
            .filter(Column("is_deleted") == false).order(Column("title")).fetchAll(db)
        var representedPages = Set<String>()
        for space in spaces {
            let name = space.title ?? "Untitled Space"
            result.append(.init(kind: .space, uuid: space.uuid, spaceID: space.uuid, name: name, path: name))
            let snapshot = try SpaceCompositionService.captureSnapshot(in: space.uuid, db: db)
            for atom in snapshot.atomsByUUID.values.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }) where atom.spaceCompositionKind != nil {
                let isGroup = atom.spaceCompositionKind == .group
                let names = snapshot.breadcrumbs(to: atom.uuid).map { $0.title ?? "Untitled Page" }
                let title = atom.title ?? (isGroup ? "Untitled Group" : "Untitled Page")
                let path = ([name] + (names.isEmpty ? [title] : names)).joined(separator: " › ")
                result.append(.init(kind: isGroup ? .group : .page, uuid: atom.uuid, spaceID: space.uuid, name: title, path: path))
                representedPages.insert(atom.uuid)
            }
        }
        let pages = try Atom.filter(Column("type") == AtomType.note.rawValue).filter(Column("is_deleted") == false)
            .order(Column("title")).fetchAll(db)
        for atom in pages where !representedPages.contains(atom.uuid) && atom.spaceCompositionKind?.isAuthored == true {
            let name = atom.title ?? "Untitled Page"
            result.append(.init(kind: .page, uuid: atom.uuid, name: name, path: "Pages › \(name)"))
        }
        result.append(.init(kind: .ideas, name: "Personal", path: "Content › Personal ideas"))
        let clients = try Atom.filter(Column("type") == AtomType.clientProfile.rawValue).filter(Column("is_deleted") == false)
            .order(Column("title")).fetchAll(db)
        for client in clients {
            let name = client.title ?? "Client"
            result.append(.init(kind: .ideas, uuid: client.uuid, name: name, path: "Content › \(name) › Ideas"))
        }
        let concepts = try Atom.filter(Column("type") == AtomType.connection.rawValue).filter(Column("is_deleted") == false)
            .order(Column("title")).fetchAll(db)
        for atom in concepts {
            let name = atom.title ?? "Untitled Concept"
            result.append(.init(kind: .connection, uuid: atom.uuid, name: name, path: "Concepts › \(name)"))
        }
        result.append(.init(kind: .swipe, name: "Swipe", path: "Swipe"))
        result.append(.init(kind: .today, name: "Today", path: "Today › Tasks"))
        return result
    }

    // MARK: - Atomic writer (also exercised with isolated test databases)

    nonisolated static func commit(_ request: InboxPlacementRequest, preparedAtom: Atom?, db: Database) throws -> InboxPlacementReceipt {
        guard request.version == 1 else { throw InboxPlacementError.unsupported }
        var capture = try Capture.read(request.source, db: db)
        if let receipt = capture.receipt, receipt.request.operationID == request.operationID, !receipt.isUndone { return receipt }
        guard capture.isActive else { throw InboxPlacementError.alreadyFiled }
        guard capture.version == request.expectedSourceVersion else { throw InboxPlacementError.staleSource }
        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !capture.attachments.isEmpty else {
            throw InboxPlacementError.emptyCapture
        }
        let destination = request.destination
        let target = try validate(request, db: db)
        var created: Atom?
        var result: Atom
        if request.action == .stageConnection {
            guard let target else { throw InboxPlacementError.missingDestination }
            result = target
        } else if let uuid = request.existingAtomUUID {
            result = try requireAtom(uuid, db: db)
        } else if let existing = try Atom.fetchOne(db, sql: """
            SELECT * FROM atoms WHERE is_deleted = 0 AND CASE WHEN json_valid(metadata)
            THEN json_extract(metadata, '$.sourceCaptureUuid') END = ? ORDER BY created_at LIMIT 1
            """, arguments: [capture.reference.uuid]) {
            guard request.action != .childPage else { throw InboxPlacementError.alreadyFiled }
            result = existing
        } else {
            guard request.action != .swipe || preparedAtom != nil else { throw InboxPlacementError.unsupported }
            result = try preparedAtom ?? makeAtom(capture: capture, request: request, db: db)
            result = result.mergingMetadataKeys(["sourceCaptureUuid": capture.reference.uuid])
            try result.insert(db)
            result.id = db.lastInsertedRowID
            try enqueue(result, table: "atoms", uuid: result.uuid, rowID: result.id, version: result.localVersion, insert: true, db: db)
            created = result
        }
        switch request.action {
        case .page, .childPage:
            guard result.type == .note, result.spaceCompositionKind?.isAuthored == true else { throw InboxPlacementError.unsupported }
        case .idea:
            guard result.type == .idea, result.ideaMetadata?.clientUUID == request.destination.uuid else { throw InboxPlacementError.unsupported }
        case .task: guard result.type == .task else { throw InboxPlacementError.unsupported }
        case .swipe: guard result.isSwipeFile else { throw InboxPlacementError.unsupported }
        case .reference, .stageConnection: break
        }
        var receipt = InboxPlacementReceipt(request: request, resultAtomUUID: result.uuid,
            outcome: outcome(request), createdAt: ISO8601.string(from: Date()), originalStatus: capture.status,
            originalCreatedObjectIDs: capture.createdObjectIDs, createdAtom: created)

        if let spaceID = destination.spaceID, request.action != .stageConnection {
            let rows = try SpaceCompositionService.captureAddMembership(result, in: spaceID, db: db)
            receipt.membershipIDs = rows.map(\.id)
            for row in rows {
                try enqueue(row, table: "canvas_blocks", uuid: row.uuid ?? row.id, rowID: nil,
                    version: Int64(row.localVersion ?? 1), insert: true, db: db)
            }
        }
        if destination.kind == .group, var group = target {
            guard var value = try group.decodedSpaceComposition(), value.kind == .group else { throw InboxPlacementError.conflict }
            guard result.uuid != group.uuid else { throw InboxPlacementError.conflict }
            if !value.memberUUIDs.contains(result.uuid) {
                value.memberUUIDs.append(result.uuid)
                group = try group.replacingSpaceComposition(value)
                try save(&group, db: db)
                receipt.addedGroupMember = true
            }
        }
        if request.action == .reference, var page = target {
            var value = try page.decodedSpaceComposition() ?? SpaceCompositionMetadata()
            let reference = SpaceCompositionReference(id: request.operationID, sourceUUID: result.uuid,
                sourceTitle: result.title, excerpt: capture.text)
            guard result.uuid != page.uuid else { throw InboxPlacementError.conflict }
            value.references.append(reference)
            page = try page.replacingSpaceComposition(value)
            try save(&page, db: db)
            receipt.referenceID = reference.id
        }
        if request.action == .stageConnection, var concept = target {
            let section = request.connectionSection ?? ConnectionSectionType.evidence.rawValue
            let inserts = concept.connectionStagedInserts
            if !inserts.contains(where: { $0.sourceUUID == capture.reference.uuid && $0.section == section }) {
                let insert = ConnectionStagedInsert(id: request.operationID, section: section, text: capture.text,
                    sourceKind: capture.reference.kind == .lane ? "lane" : "inbox", sourceUUID: capture.reference.uuid,
                    attachmentUUIDs: capture.attachments)
                concept = concept.withConnectionStagedInserts(inserts + [insert])
                try save(&concept, db: db)
                receipt.stagedInsertID = insert.id
            }
        } else {
            var ids = result.attachmentUUIDs
            for uuid in capture.attachments {
                guard var attachment = try MediaAttachment.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db) else {
                    throw InboxPlacementError.conflict
                }
                if !ids.contains(uuid) {
                    ids.append(uuid)
                    receipt.addedAttachmentIDs = (receipt.addedAttachmentIDs ?? []) + [uuid]
                }
                if attachment.ownerUUID != result.uuid || attachment.ownerType != "atom" {
                    receipt.attachmentOwners.append(.init(uuid: uuid, ownerType: attachment.ownerType,
                        ownerUUID: attachment.ownerUUID, capturedItemID: attachment.capturedItemId))
                    attachment.ownerType = "atom"; attachment.ownerUUID = result.uuid; attachment.capturedItemId = result.uuid
                    try saveAttachment(&attachment, db: db)
                }
            }
            if ids != result.attachmentUUIDs {
                result = result.mergingMetadataKeys(["attachmentUUIDs": ids])
                try save(&result, db: db)
            }
            if created != nil { receipt.createdAtom = result }
        }
        try capture.settle(receipt, db: db)
        return receipt
    }

    nonisolated private static func validate(_ request: InboxPlacementRequest, db: Database) throws -> Atom? {
        let destination = request.destination
        var snapshot: SpaceCompositionSnapshot?
        if let space = destination.spaceID { snapshot = try SpaceCompositionService.captureSnapshot(in: space, db: db) }
        switch destination.kind {
        case .space:
            guard request.action == .page, destination.spaceID != nil else { throw InboxPlacementError.unsupported }
            return nil
        case .group, .page:
            guard let uuid = destination.uuid else { throw InboxPlacementError.missingDestination }
            let atom = try requireAtom(uuid, db: db)
            if let snapshot, snapshot.atomsByUUID[uuid] == nil { throw InboxPlacementError.missingDestination }
            if destination.kind == .group {
                guard request.action == .page, atom.spaceCompositionKind == .group else { throw InboxPlacementError.unsupported }
            } else {
                guard atom.spaceCompositionKind?.isAuthored == true,
                      request.action == .reference || request.action == .childPage else { throw InboxPlacementError.unsupported }
            }
            return atom
        case .connection:
            guard request.action == .stageConnection, let uuid = destination.uuid,
                  ConnectionSectionType(rawValue: request.connectionSection ?? "evidence") != nil else { throw InboxPlacementError.unsupported }
            let atom = try requireAtom(uuid, db: db)
            guard atom.type == .connection else { throw InboxPlacementError.missingDestination }
            return atom
        case .ideas:
            guard request.action == .idea else { throw InboxPlacementError.unsupported }
            if let uuid = destination.uuid, try requireAtom(uuid, db: db).type != .clientProfile { throw InboxPlacementError.missingDestination }
            return nil
        case .pages: guard request.action == .page else { throw InboxPlacementError.unsupported }; return nil
        case .today: guard request.action == .task else { throw InboxPlacementError.unsupported }; return nil
        case .swipe: guard request.action == .swipe else { throw InboxPlacementError.unsupported }; return nil
        }
    }

    nonisolated private static func makeAtom(capture: Capture, request: InboxPlacementRequest, db: Database) throws -> Atom {
        let type: AtomType = request.action == .idea ? .idea : request.action == .task ? .task : .note
        var atom = Atom.new(type: type, title: capture.title, body: capture.text)
        if type == .note {
            let parent = request.action == .childPage ? request.destination.uuid : nil
            let order = try Double.fetchOne(db, sql: """
                SELECT COALESCE(MAX(CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.spaceComposition.sortOrder') END), -1) + 1
                FROM atoms WHERE is_deleted = 0 AND type = 'note' AND CASE WHEN json_valid(metadata)
                THEN json_extract(metadata, '$.spaceComposition.parentUUID') END IS ?
                """, arguments: [parent]) ?? 0
            atom = try atom.replacingSpaceComposition(.init(parentUUID: parent, sortOrder: order))
        }
        if type == .idea {
            atom = atom.withUpdatedIdeaMetadata { metadata in
                metadata.ideaStatus = .spark
                metadata.clientUUID = request.destination.uuid
                metadata.clientName = request.destination.uuid == nil ? nil : request.destination.name
            }
            if let client = request.destination.uuid {
                atom = atom.addingLink(AtomLink(type: AtomLinkType.ideaToClient.rawValue, uuid: client, entityType: AtomType.clientProfile.rawValue))
            }
        }
        if type == .task {
            atom = atom.mergingMetadataKeys(["status": "todo", "priority": "medium"])
            if let payload = CapturedChecklist.taskPayload(from: capture.text) {
                atom.title = payload.title; atom.body = payload.notes
                if let checklist = CapturedChecklist.checklistJSON(payload.checklist) { atom = atom.mergingMetadataKeys(["checklist": checklist]) }
            }
        }
        return atom
    }

    nonisolated private static func outcome(_ request: InboxPlacementRequest) -> String {
        switch request.action {
        case .reference: return "Reference added to \(request.destination.path)"
        case .childPage: return "Child Page added to \(request.destination.path)"
        case .stageConnection: return "Awaiting review in \(request.destination.path) › \(request.connectionSection.flatMap(ConnectionSectionType.init(rawValue:))?.displayName ?? "Evidence")"
        case .idea: return "Idea saved to \(request.destination.path)"
        case .task: return "Task created in Today"
        case .swipe: return request.existingAtomUUID == nil ? "Saved in Swipe" : "Existing Swipe reused"
        case .page: return "Page saved to \(request.destination.path)"
        }
    }

    // MARK: - Owned inverse

    nonisolated static func reverse(_ supplied: InboxPlacementReceipt, db: Database) throws -> InboxPlacementReceipt {
        var capture = try Capture.read(supplied.request.source, db: db)
        guard var receipt = capture.receipt, receipt.version == 1,
              receipt.request.operationID == supplied.request.operationID else { throw InboxPlacementError.conflict }
        if receipt.isUndone { return receipt }
        guard !capture.isActive else { throw InboxPlacementError.conflict }
        let request = receipt.request
        if receipt.addedGroupMember, let uuid = request.destination.uuid {
            var group = try requireAtom(uuid, db: db)
            guard var value = try group.decodedSpaceComposition(), value.kind == .group else { throw InboxPlacementError.conflict }
            guard value.memberUUIDs.contains(receipt.resultAtomUUID),
                  !value.placements.contains(where: { $0.itemUUID == receipt.resultAtomUUID }) else { throw InboxPlacementError.conflict }
            value.memberUUIDs.removeAll { $0 == receipt.resultAtomUUID }
            group = try group.replacingSpaceComposition(value); try save(&group, db: db)
        }
        if let referenceID = receipt.referenceID, let uuid = request.destination.uuid {
            var page = try requireAtom(uuid, db: db)
            guard var value = try page.decodedSpaceComposition() else { throw InboxPlacementError.conflict }
            guard value.references.contains(where: { $0.id == referenceID && $0.sourceUUID == receipt.resultAtomUUID }) else { throw InboxPlacementError.conflict }
            value.references.removeAll { $0.id == referenceID }
            page = try page.replacingSpaceComposition(value); try save(&page, db: db)
        }
        if let insertID = receipt.stagedInsertID {
            var concept = try requireAtom(receipt.resultAtomUUID, db: db)
            var inserts = concept.connectionStagedInserts
            guard inserts.contains(where: { $0.id == insertID }) else { throw InboxPlacementError.conflict }
            inserts.removeAll { $0.id == insertID }
            concept = concept.withConnectionStagedInserts(inserts); try save(&concept, db: db)
        }
        for id in receipt.membershipIDs {
            guard var row = try CanvasBlockRecord.filter(Column("id") == id).fetchOne(db), !row.isDeleted, row.isPlaced != true else {
                throw InboxPlacementError.conflict
            }
            row.isDeleted = true; row.localVersion = (row.localVersion ?? 0) + 1
            row.updatedAt = ISO8601.string(from: Date()); row.localPending = 1
            try row.update(db)
            try enqueue(row, table: "canvas_blocks", uuid: row.uuid ?? row.id, rowID: nil, version: Int64(row.localVersion ?? 1), db: db)
        }
        var originalWasUntouched = false
        if let original = receipt.createdAtom, let current = try Atom.filter(Column("uuid") == original.uuid).fetchOne(db) {
            originalWasUntouched = current.title == original.title && current.body == original.body && current.structured == original.structured && current.metadata == original.metadata && current.links == original.links
        }
        for owner in receipt.attachmentOwners {
            guard var attachment = try MediaAttachment.filter(Column("uuid") == owner.uuid).fetchOne(db),
                  attachment.ownerUUID == receipt.resultAtomUUID, attachment.ownerType == "atom", !attachment.isDeleted else { throw InboxPlacementError.conflict }
            attachment.ownerType = owner.ownerType; attachment.ownerUUID = owner.ownerUUID; attachment.capturedItemId = owner.capturedItemID
            try saveAttachment(&attachment, db: db)
        }
        if let added = receipt.addedAttachmentIDs, !added.isEmpty,
           var atom = try Atom.filter(Column("uuid") == receipt.resultAtomUUID).filter(Column("is_deleted") == false).fetchOne(db) {
            atom = atom.mergingMetadataKeys(["attachmentUUIDs": atom.attachmentUUIDs.filter { !added.contains($0) }])
            try save(&atom, db: db)
        }
        if let original = receipt.createdAtom, var atom = try Atom.filter(Column("uuid") == original.uuid).fetchOne(db), !atom.isDeleted {
            let memberships = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid = ? AND is_deleted = 0", arguments: [atom.uuid]) ?? 0
            let references = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM atoms WHERE uuid != ? AND is_deleted = 0
                AND (COALESCE(metadata, '') LIKE ? OR COALESCE(links, '') LIKE ?)
                """, arguments: [atom.uuid, "%\(atom.uuid)%", "%\(atom.uuid)%"]) ?? 0
            if originalWasUntouched && memberships == 0 && references == 0 {
                atom.isDeleted = true; try save(&atom, db: db)
            } else {
                receipt.retainedOriginal = true
                if request.action == .childPage {
                    if var value = try atom.decodedSpaceComposition(), value.parentUUID == request.destination.uuid {
                        value.parentUUID = nil
                        atom = try atom.replacingSpaceComposition(value)
                        try save(&atom, db: db)
                    }
                }
            }
        }
        receipt.isUndone = true
        try capture.restore(receipt, db: db)
        return receipt
    }

    // MARK: - Persistence primitives

    nonisolated private static func requireAtom(_ uuid: String, db: Database) throws -> Atom {
        guard let atom = try Atom.filter(Column("uuid") == uuid).filter(Column("is_deleted") == false).fetchOne(db) else {
            throw InboxPlacementError.missingDestination
        }
        return atom
    }

    nonisolated private static func save(_ atom: inout Atom, db: Database) throws {
        if let previous = try Atom.filter(Column("uuid") == atom.uuid).fetchOne(db) {
            AtomRevisionWriter.snapshotIfNeeded(db, previous: previous, incoming: atom, source: .userEdit)
            atom.localVersion = previous.localVersion + 1
        }
        atom.updatedAt = ISO8601.string(from: Date())
        try atom.update(db)
        try enqueue(atom, table: "atoms", uuid: atom.uuid, rowID: atom.id, version: atom.localVersion, db: db)
    }

    nonisolated private static func saveAttachment(_ attachment: inout MediaAttachment, db: Database) throws {
        attachment.localVersion += 1; attachment.updatedAt = ISO8601.string(from: Date()); attachment.syncUpdatedAt = attachment.updatedAt
        try attachment.update(db)
        try enqueue(attachment, table: "media_attachments", uuid: attachment.uuid, rowID: attachment.id, version: attachment.localVersion, db: db)
    }

    /// Durable sync intent commits with the record. The regular sync worker
    /// can retry independently; no post-commit notification is the only copy.
    nonisolated private static func enqueue<T: Encodable>(_ record: T, table: String, uuid: String, rowID: Int64?,
                                           version: Int64, insert: Bool = false, db: Database) throws {
        let allowed = ["atoms", "canvas_blocks", "inbox_items", "captured_items", "media_attachments"]
        guard allowed.contains(table) else { throw InboxPlacementError.unsupported }
        try db.execute(sql: "UPDATE \(table) SET _local_pending = 1 WHERE \(table == "canvas_blocks" ? "id" : "uuid") = ?", arguments: [table == "canvas_blocks" ? (record as? CanvasBlockRecord)?.id ?? uuid : uuid])
        let payload = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        if let row = try Row.fetchOne(db, sql: "SELECT id, operation FROM sync_queue WHERE uuid = ? AND table_name = ? AND status = 'pending'", arguments: [uuid, table]) {
            let operation: String = row["operation"]
            try db.execute(sql: "UPDATE sync_queue SET data = ?, local_version = ?, operation = ?, created_at = ? WHERE id = ?",
                arguments: [payload, version, operation == "INSERT" ? "INSERT" : (insert ? "INSERT" : "UPDATE"), Int64(Date().timeIntervalSince1970 * 1000), row["id"] as Int64])
        } else {
            try db.execute(sql: "INSERT INTO sync_queue (uuid,table_name,row_id,operation,data,local_version,status) VALUES (?,?,?,?,?,?,'pending')",
                arguments: [uuid, table, rowID, insert ? "INSERT" : "UPDATE", payload, version])
        }
    }

    private struct Capture {
        var inbox: InboxItem?
        var lane: CapturedItem?
        var reference: InboxCaptureReference { .init(kind: inbox == nil ? .lane : .inbox, uuid: inbox?.uuid ?? lane!.uuid) }
        var version: Int64 { inbox?.localVersion ?? lane!.localVersion }
        var text: String { inbox?.rawText ?? lane?.cleanText ?? lane?.rawText ?? lane?.caption ?? "" }
        var title: String { inbox?.title ?? String(text.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines) }
        var status: String { inbox?.status.rawValue ?? lane!.status.rawValue }
        var createdObjectIDs: [String] { lane?.createdObjectIds ?? [] }
        var metadata: [String: Any] { Self.dictionary(inbox?.metadata ?? lane?.provenanceMetadata) }
        var attachments: [String] { inbox?.attachmentUUIDs ?? lane?.mediaAttachmentIds ?? [] }
        var isActive: Bool {
            if let inbox { return !inbox.isDeleted && (inbox.status == .pending || inbox.status == .classified) }
            guard let lane else { return false }
            return !lane.isDeleted && lane.status != .applied && lane.status != .archived
        }
        var receipt: InboxPlacementReceipt? {
            guard let value = metadata[InboxPlacementReceipt.metadataKey], let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(InboxPlacementReceipt.self, from: data)
        }
        static func read(_ reference: InboxCaptureReference, db: Database) throws -> Self {
            switch reference.kind {
            case .inbox:
                if let item = try InboxItem.filter(Column("uuid") == reference.uuid).fetchOne(db) { return .init(inbox: item) }
                // Old Mac lane proxies had no discriminator. Resolve their real
                // source before writing; never insert a synthetic Inbox row.
                if let item = try CapturedItem.filter(Column("uuid") == reference.uuid).fetchOne(db) { return .init(lane: item) }
            case .lane:
                if let item = try CapturedItem.filter(Column("uuid") == reference.uuid).fetchOne(db) { return .init(lane: item) }
            }
            throw InboxPlacementError.missingSource
        }
        static func dictionary(_ json: String?) -> [String: Any] {
            guard let data = json?.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return value
        }
        mutating func setMetadata(_ object: [String: Any]) throws {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
            if inbox != nil { inbox?.metadata = json } else { lane?.provenanceMetadata = json }
        }
        mutating func removeReceipt() {
            var object = metadata; object.removeValue(forKey: InboxPlacementReceipt.metadataKey)
            try? setMetadata(object)
        }
        mutating func settle(_ receipt: InboxPlacementReceipt, db: Database) throws {
            var object = metadata
            object[InboxPlacementReceipt.metadataKey] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt))
            object["actionOutcome"] = receipt.outcome
            try setMetadata(object)
            if inbox != nil { inbox?.status = .actioned; inbox?.actionedAt = ISO8601.string(from: Date()) }
            else {
                lane?.status = .applied
                let ids = Array(Set(createdObjectIDs + [receipt.resultAtomUUID])).sorted()
                lane?.createdObjectIdsJSON = String(decoding: try JSONEncoder().encode(ids), as: UTF8.self)
            }
            try save(db: db)
        }
        mutating func restore(_ receipt: InboxPlacementReceipt, db: Database) throws {
            var object = metadata
            object[InboxPlacementReceipt.metadataKey] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt))
            object["actionOutcome"] = "Filing undone" + (receipt.retainedOriginal ? " · edited original retained" : "")
            try setMetadata(object)
            if inbox != nil {
                inbox?.status = InboxItemStatus(rawValue: receipt.originalStatus) ?? .classified
                inbox?.actionedAt = nil
            } else {
                lane?.status = CapturedItemStatus(rawValue: receipt.originalStatus) ?? .routed
                lane?.createdObjectIdsJSON = String(decoding: try JSONEncoder().encode(receipt.originalCreatedObjectIDs), as: UTF8.self)
            }
            try save(db: db)
        }
        mutating func save(db: Database) throws {
            let now = ISO8601.string(from: Date())
            if var item = inbox {
                item.localVersion += 1; item.syncUpdatedAt = now
                try item.update(db)
                try enqueue(item, table: "inbox_items", uuid: item.uuid, rowID: item.id, version: item.localVersion, db: db)
                inbox = item
            } else if var item = lane {
                item.localVersion += 1; item.updatedAt = now; item.syncUpdatedAt = now
                try item.update(db)
                try enqueue(item, table: "captured_items", uuid: item.uuid, rowID: item.id, version: item.localVersion, db: db)
                lane = item
            }
        }
    }
}
