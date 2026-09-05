import Foundation
import GRDB

@MainActor enum SpaceResearchService {
    /// Idempotent preservation. Original records remain intact for older clients;
    /// editable documents get deterministic identities and never overwrite edits.
    static func preserveDocuments(in spaceID: String) async throws {
        guard let space = try await AtomRepository.shared.fetch(uuid: spaceID), !space.isDeleted else { throw SpaceResearchSchema.Failure.missing }
        let metadata = try SpaceResearchSchema.object(space.metadata)
        if metadata["spaceDocumentsV2"] as? Bool == true { return }
        let home = RichDocumentMetadataStorage.readDocument(from: space.metadata, key: "spaceHomeDocument", atomUUID: spaceID)
            ?? RichDocument.migrateLegacy(space.body ?? "")
        if !home.isEmpty {
            try await preserve(document: home, title: "\(space.title ?? "Space") — working notes",
                id: SpaceResearchSchema.stableID("home:" + spaceID), source: space, spaceID: spaceID)
        }
        let profiles = try await InquiryRepository.shared.fetchDeepDives(in: spaceID)
        let members = try await SpaceMembershipService.memberUUIDs(in: spaceID)
        for profile in profiles {
            let text = SpaceResearchSchema.understandingText(try SpaceResearchSchema.object(profile.structured))
            if !text.isEmpty {
                try await preserve(document: .migrateLegacy(text), title: "\(profile.title ?? "Research") — understanding",
                    id: SpaceResearchSchema.stableID("understanding:" + profile.uuid), source: profile, spaceID: spaceID)
            }
            let concepts = try await InquiryRepository.shared.fetchConnections(forDeepDive: profile)
            let terms = try await InquiryRepository.shared.fetchLexicon(forDeepDive: profile.uuid)
            for atom in concepts + terms where !members.contains(atom.uuid) { _ = try await SpaceMembershipService.add(atom, to: spaceID) }
        }
        let saved = try await CosmoDatabase.shared.asyncWrite { db in
            guard var fresh = try Atom.filter(Column("uuid") == spaceID).filter(Column("is_deleted") == false).fetchOne(db) else { throw SpaceResearchSchema.Failure.missing }
            var fields = try SpaceResearchSchema.object(fresh.metadata); fields["spaceDocumentsV2"] = true
            fresh.metadata = try SpaceResearchSchema.json(fields); fresh.localVersion += 1; fresh.updatedAt = ISO8601.string(from: .now)
            try fresh.update(db); return fresh
        }
        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: saved, skipVersionIncrement: true)
    }

    private static func preserve(document: RichDocument, title: String, id: String, source: Atom, spaceID: String) async throws {
        let result: Atom? = try await CosmoDatabase.shared.asyncWrite { db in
            if try Atom.filter(Column("uuid") == id).fetchOne(db) != nil { return nil }
            var fields: [String: Any] = ["preservedFromUUID": source.uuid, "preservedAt": ISO8601.string(from: .now)]
            if let structured = source.structured { fields["preservedResearchHistory"] = structured }
            var atom = Atom.new(type: .note, title: title, body: document.plainText,
                metadata: RichDocumentMetadataStorage.writeDocument(document, into: try SpaceResearchSchema.json(fields), key: "bodyDocument"))
            atom.uuid = id
            var links = source.linksList + [AtomLink(type: source.type == .inquirySession ? "output_from_inquiry" : "source", uuid: source.uuid, entityType: source.type.rawValue)]
            if source.type == .inquirySession {
                links += SpaceResearchSchema.sourceIDs(try SpaceResearchSchema.object(source.structured)).map { AtomLink(type: "source", uuid: $0) }
            }
            atom.links = String(decoding: try JSONEncoder().encode(links), as: UTF8.self)
            try atom.insert(db); atom.id = db.lastInsertedRowID
            return atom
        }
        if let result { await ChangeTracker.shared.trackInsert(table: "atoms", entity: result) }
        guard let atom = try await AtomRepository.shared.fetch(uuid: id), !atom.isDeleted else { return }
        let members = try await SpaceMembershipService.memberUUIDs(in: spaceID)
        if !members.contains(id) { _ = try await SpaceMembershipService.add(atom, to: spaceID) }
    }

    static func saveFindings(from session: Atom, summary: String) async throws {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let profileID = session.inquirySessionMetadata?.parentDeepDiveUUID,
            let profile = try await AtomRepository.shared.fetch(uuid: profileID) else { return }
        let parents = Set((profile.deepDiveMetadata?.parentThinkspaceUUIDs ?? []) + [profile.deepDiveMetadata?.primaryThinkspaceUUID].compactMap { $0 })
        for parent in parents {
            try await preserve(document: .migrateLegacy(summary), title: "\(session.title ?? "Inquiry") — findings",
                id: SpaceResearchSchema.stableID("findings:" + session.uuid), source: session, spaceID: parent)
        }
    }

    static func start(spaceID: String, question title: String, sourceIDs: [String] = []) async throws -> Atom {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw SpaceResearchSchema.Failure.emptyTitle }
        let result: (Atom, [Atom], Set<String>) = try await CosmoDatabase.shared.asyncWrite { db in
            let now = ISO8601.string(from: .now)
            var changed: [Atom] = [], inserted = Set<String>()
            func save(_ atom: inout Atom) throws {
                if atom.id == nil { try atom.insert(db); atom.id = db.lastInsertedRowID; inserted.insert(atom.uuid) }
                else { atom.localVersion += 1; atom.updatedAt = now; try atom.update(db) }
                try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [atom.uuid])
                changed.append(atom)
            }
            guard var space = try Self.live(spaceID, db: db), space.type == .thinkspace else { throw SpaceResearchSchema.Failure.missing }
            var spaceFields = try SpaceResearchSchema.object(space.metadata)
            let profiles = try Self.profiles(in: space, db: db)
            let explicit = spaceFields["deepDiveProfileUUID"] as? String
            var profile = profiles.first { $0.uuid == explicit } ?? profiles.first ?? Atom.new(type: .deepDive, title: space.spaceResearchTitle)
            if profile.id == nil {
                profile.uuid = SpaceResearchSchema.stableID("profile:" + spaceID)
                // A deliberately deleted profile must never be resurrected.
                if try Atom.filter(Column("uuid") == profile.uuid).fetchOne(db) != nil { profile.uuid = UUID().uuidString }
                profile.metadata = try SpaceResearchSchema.json(["primaryThinkspaceUUID": spaceID, "parentThinkspaceUUIDs": [spaceID], "maturity": "spark"])
                profile.structured = "{}"
            }
            var profileFields = try SpaceResearchSchema.object(profile.metadata)
            let ids = Set(profiles.map(\.uuid) + [profile.uuid])
            let candidates = try Atom.filter([AtomType.inquirySession.rawValue, AtomType.question.rawValue].contains(Column("type")))
                .filter(Column("is_deleted") == false).order(Column("updated_at").desc).fetchAll(db)
                .filter { ids.contains($0.spaceResearchFields["parentDeepDiveUUID"] as? String ?? "") }
            let key = SpaceResearchSchema.questionKey(title)
            let existing = candidates.first { $0.type == .inquirySession && $0.spaceResearchFields["status"] as? String != "archived" && SpaceResearchSchema.questionKey($0.spaceResearchTitle) == key }
            var session: Atom
            if let existing { session = existing }
            else {
                var question = try candidates.first { $0.type == .question && $0.spaceResearchFields["status"] as? String != "archived" && SpaceResearchSchema.questionKey($0.spaceResearchTitle) == key }
                    ?? Atom.new(type: .question, title: title, metadata: try SpaceResearchSchema.json(["parentDeepDiveUUID": profile.uuid, "status": "open", "questionRole": "rootQuestion", "relationshipToParent": "root_under_topic"]))
                if question.id == nil {
                    question.uuid = SpaceResearchSchema.stableID("question:" + profile.uuid + ":" + key)
                    if try Atom.filter(Column("uuid") == question.uuid).fetchOne(db) != nil { question.uuid = UUID().uuidString }
                    question = try Self.linking(question, type: "question_parent_deep_dive", target: profile)
                    try save(&question)
                }
                session = Atom.new(type: .inquirySession, title: title,
                    structured: try SpaceResearchSchema.json(SpaceResearchSchema.bootstrap(questionID: question.uuid, title: title, now: now)),
                    metadata: try SpaceResearchSchema.json(["parentDeepDiveUUID": profile.uuid, "mainQuestionUUID": question.uuid, "parentObjectUUID": spaceID, "parentObjectType": "thinkspace", "status": "active", "lastActiveAt": now, "layoutMode": "research"]))
                session.uuid = SpaceResearchSchema.stableID("session:" + question.uuid)
                if try Atom.filter(Column("uuid") == session.uuid).fetchOne(db) != nil { session.uuid = UUID().uuidString }
                session = try Self.linking(session, type: "inquiry_root_question", target: question)
                session = try Self.linking(session, type: "inquiry_parent_deep_dive", target: profile)
                session = try Self.linking(session, type: "inquiry_parent_object", target: space)
                profile = try Self.linking(profile, type: "deep_dive_question", target: question)
            }
            var structured = try SpaceResearchSchema.object(session.structured)
            for id in Set(sourceIDs) {
                guard let source = try Self.live(id, db: db) else { throw SpaceResearchSchema.Failure.missing }
                try SpaceResearchSchema.attachSource(id: id, title: source.spaceResearchTitle, url: source.spaceResearchFields["url"] as? String, to: &structured, now: now)
                profile = try Self.linking(profile, type: "deep_dive_source", target: source)
            }
            session.structured = try SpaceResearchSchema.json(structured)
            var sessionFields = try SpaceResearchSchema.object(session.metadata)
            sessionFields["lastActiveAt"] = now
            session.metadata = try SpaceResearchSchema.json(sessionFields)
            try save(&session)
            profile = try Self.linking(profile, type: "deep_dive_session", target: session)
            profile = try Self.linking(profile, type: "deep_dive_parent", target: space)
            profileFields["lastInquiryAt"] = now; profile.metadata = try SpaceResearchSchema.json(profileFields)
            try save(&profile)
            if spaceFields["deepDiveProfileUUID"] as? String != profile.uuid {
                spaceFields["deepDiveProfileUUID"] = profile.uuid; space.metadata = try SpaceResearchSchema.json(spaceFields); try save(&space)
            }
            return (session, changed, inserted)
        }
        for atom in result.1 {
            if result.2.contains(atom.uuid) { await ChangeTracker.shared.trackInsert(table: "atoms", entity: atom) }
            else { await ChangeTracker.shared.trackUpdate(table: "atoms", entity: atom, skipVersionIncrement: true) }
        }
        return result.0
    }

    nonisolated private static func live(_ id: String, db: Database) throws -> Atom? {
        try Atom.filter(Column("uuid") == id).filter(Column("is_deleted") == false).fetchOne(db)
    }
    nonisolated private static func profiles(in space: Atom, db: Database) throws -> [Atom] {
        let explicit = try SpaceResearchSchema.object(space.metadata)["deepDiveProfileUUID"] as? String
        return try Atom.filter(Column("type") == AtomType.deepDive.rawValue).filter(Column("is_deleted") == false).order(Column("created_at")).fetchAll(db).filter {
            $0.uuid == explicit || $0.spaceResearchFields["primaryThinkspaceUUID"] as? String == space.uuid || ($0.spaceResearchFields["parentThinkspaceUUIDs"] as? [String] ?? []).contains(space.uuid)
        }
    }
    nonisolated private static func linking(_ atom: Atom, type: String, target: Atom) throws -> Atom {
        var atom = atom, links = atom.linksList
        if !links.contains(where: { $0.type == type && $0.uuid == target.uuid }) { links.append(AtomLink(type: type, uuid: target.uuid, entityType: target.type.rawValue)) }
        atom.links = String(decoding: try JSONEncoder().encode(links), as: UTF8.self); return atom
    }
}

private extension Atom {
    var spaceResearchFields: [String: Any] { metadataDict ?? [:] }
    var spaceResearchTitle: String { title ?? type.displayName }
}
