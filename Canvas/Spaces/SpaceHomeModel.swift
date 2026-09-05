import Foundation
import SwiftUI
import GRDB

/// Only dependencies that affect the two rails. Editing the space's working
/// notes changes its atom, but must not reload every material and inquiry.
struct SpaceHomeDependencyVersion: Equatable, Sendable, FetchableRecord, Decodable {
    let uuid: String
    let updated_at: String
    let _local_version: Int

    static func fetch(_ db: Database, spaceID: String, diveID: String?) throws -> [Self] {
        try fetchAll(db, sql: """
            SELECT uuid, updated_at, _local_version FROM atoms
            WHERE is_deleted = 0 AND (
                uuid IN (SELECT entity_uuid FROM canvas_blocks
                         WHERE thinkspace_id = ? AND document_type = 'home'
                           AND document_id = 0 AND is_deleted = 0)
                OR (type IN ('question', 'inquiry_session') AND
                    CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.parentDeepDiveUUID') END = ?)
            ) ORDER BY uuid
            """, arguments: [spaceID, diveID])
    }
}

@MainActor
@Observable
final class SpaceHomeModel {
    let spaceID: String
    private(set) var name = "Space"
    var document = RichDocument.empty
    private(set) var materials: [Atom] = []
    private(set) var outputs: [Atom] = []
    private(set) var questions: [Atom] = []
    private(set) var lastSession: Atom?
    private(set) var isLoaded = false
    private(set) var isSaving = false
    var errorMessage: String?
    var materialQuery = ""
    var selectedText = ""
    var showingMaterials = true
    var showingMaterialPicker = false
    var isCreatingIdea = false

    @ObservationIgnored private var lastSaved = RichDocument.empty
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var diveUUID: String?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private let refresh = CoalescingRefresh()
    @ObservationIgnored private var loadedDependencies: [SpaceHomeDependencyVersion]?
    @ObservationIgnored private var loadedDiveUUID: String?
    static let documentKey = "spaceHomeDocument"

    init(spaceID: String) { self.spaceID = spaceID }

    var filteredMaterials: [Atom] {
        let tokens = materialQuery.lowercased().split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return materials }
        return materials.filter { atom in
            let text = ((atom.title ?? "") + " " + (atom.body ?? "")).lowercased()
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    func load() async {
        await refresh.run { [weak self] in await self?.loadSnapshot() }
    }

    private func loadSnapshot() async {
        let interval = AppPerformanceInstrumentation.begin("space-home-refresh")
        defer { AppPerformanceInstrumentation.end("space-home-refresh", interval) }
        do {
            guard let space = try await AtomRepository.shared.fetch(uuid: spaceID) else {
                errorMessage = "This space is no longer available."; return
            }
            name = Thinkspace(from: space).identityLabel
            if !isLoaded || document == lastSaved {
                document = RichDocumentMetadataStorage.readDocument(from: space.metadata, key: Self.documentKey, atomUUID: spaceID)
                    ?? RichDocument.migrateLegacy(space.body ?? "")
                lastSaved = document
            }
            diveUUID = space.metadataValue(as: ThinkspaceMetadata.self)?.deepDiveProfileUUID
            let spaceID = self.spaceID
            let diveID = diveUUID
            let dependencies = try await CosmoDatabase.shared.asyncRead { db in
                try SpaceHomeDependencyVersion.fetch(db, spaceID: spaceID, diveID: diveID)
            }
            if dependencies != loadedDependencies || diveID != loadedDiveUUID {
                let ids = try await SpaceMembershipService.memberUUIDs(in: spaceID)
                let members = try await AtomRepository.shared.fetchBatch(uuids: Array(ids))
                let nextMaterials = members.filter { $0.type != .content && $0.type != .thinkspace }
                    .sorted { $0.updatedAt > $1.updatedAt }
                let nextOutputs = members.filter { $0.type == .content }.sorted { $0.updatedAt > $1.updatedAt }
                if materials != nextMaterials { materials = nextMaterials }
                if outputs != nextOutputs { outputs = nextOutputs }
                if let diveID {
                    async let questionLoad = InquiryRepository.shared.fetchQuestions(forDeepDive: diveID)
                    async let sessionLoad = InquiryRepository.shared.fetchSessions(forDeepDive: diveID)
                    let (loadedQuestions, sessions) = try await (questionLoad, sessionLoad)
                    let nextQuestions = loadedQuestions.filter { $0.questionMetadata?.status != .archived }
                    if questions != nextQuestions { questions = nextQuestions }
                    if lastSession != sessions.first { lastSession = sessions.first }
                } else { questions = []; lastSession = nil }
                loadedDependencies = dependencies
                loadedDiveUUID = diveID
            }
            isLoaded = true
            errorMessage = nil
        } catch { errorMessage = "Couldn't open the space. Try again." }
    }

    func edited(_ value: RichDocument) {
        document = value
        guard isLoaded, value != lastSaved else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self?.saveTask = nil
            await self?.save()
        }
    }

    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        if let persistenceTask { await persistenceTask.value }
        await save()
    }

    private func save() async {
        guard isLoaded, document != lastSaved, persistenceTask == nil else { return }
        let task = Task { await persistPendingDocument() }
        persistenceTask = task
        await task.value
        persistenceTask = nil
    }

    private func persistPendingDocument() async {
        guard document != lastSaved else { return }
        let revision = document
        isSaving = true
        do {
            let saved = try await Self.persist(revision, spaceID: spaceID)
            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: saved, skipVersionIncrement: true)
            Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(saved) }
            lastSaved = revision
            errorMessage = nil
        } catch { errorMessage = "Your notes haven't saved yet. Keep this space open and retry." }
        isSaving = false
        if revision != document { await persistPendingDocument() }
    }

    func open(_ atom: Atom) {
        if atom.type == .inquirySession, let diveUUID {
            NotificationCenter.default.post(name: CosmoNotification.Inquiry.startInquiry, object: nil,
                userInfo: ["anchorUUID": diveUUID, "anchorType": AtomType.deepDive.rawValue, "resumeSessionUUID": atom.uuid])
            return
        }
        NotificationCenter.default.post(name: CosmoNotification.Navigation.openBlockInFocusMode,
                                        object: nil, userInfo: ["atomUUID": atom.uuid])
    }

    func createNote() {
        Task {
            do {
                let note = try await SpaceMembershipService.create(type: .note, title: "Untitled note", in: spaceID)
                open(note)
                await load()
            } catch { errorMessage = "Couldn't create the note. Try again." }
        }
    }

    func startInquiry(question: Atom? = nil) {
        Task {
            await flush()
            guard let uuid = await ThinkspaceManager.shared.ensureDeepDiveProfileUUID(for: spaceID) else {
                errorMessage = "Couldn't open the inquiry. Try again."; return
            }
            var info: [String: Any] = ["anchorUUID": uuid, "anchorType": AtomType.deepDive.rawValue]
            if let question { info["mainQuestionTitle"] = question.title; info["rootQuestionUUID"] = question.uuid }
            if question == nil {
                NotificationCenter.default.post(name: CosmoNotification.Inquiry.openDeepDive, object: nil,
                                                userInfo: ["uuid": uuid, "composeQuestion": true])
            } else {
                NotificationCenter.default.post(name: CosmoNotification.Inquiry.startInquiry, object: nil, userInfo: info)
            }
        }
    }

    func makeIdea() {
        guard !isCreatingIdea else { return }
        let text = (selectedText.isEmpty ? document.plainText : selectedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isCreatingIdea = true
        Task {
            defer { isCreatingIdea = false }
            do {
                await flush()
                let title = String((text.components(separatedBy: .newlines).first ?? "New idea").prefix(120))
                let prepared = Atom.new(type: .idea, title: title, body: text,
                                        links: [AtomLink(type: "source", uuid: spaceID, entityType: "thinkspace")])
                let idea = try await SpaceMembershipService.create(prepared, in: spaceID)
                open(idea)
                await load()
            } catch { errorMessage = "Couldn't create the idea. Your notes are still here." }
        }
    }

    func openBeside(_ atom: Atom) {
        guard let type = EntityType(rawValue: atom.type.rawValue), let id = atom.id else { open(atom); return }
        NotificationCenter.default.post(name: CosmoNotification.Navigation.openAsPane, object: nil,
                                        userInfo: ["type": type, "id": id])
    }

    func start() async {
        guard observation == nil, let db = CosmoDatabase.shared.dbPool else { return }
        let id = spaceID
        let tracked = ValueObservation.tracking { (db: Database) throws -> (Atom?, [SpaceHomeDependencyVersion]) in
            let space = try Atom.filter(Column("uuid") == id).fetchOne(db)
            let diveID = space?.metadataValue(as: ThinkspaceMetadata.self)?.deepDiveProfileUUID
            // Include inquiry changes as well as material membership; the
            // former wasn't observed until the user left and reopened Home.
            let dependencies = try SpaceHomeDependencyVersion.fetch(db, spaceID: id, diveID: diveID)
            return (space, dependencies)
        }
        let distinct = tracked.removeDuplicates { lhs, rhs in
            let sameSpace = lhs.0 == rhs.0
            let sameDependencies = lhs.1 == rhs.1
            return sameSpace && sameDependencies
        }
        observation = distinct.start(in: db, onError: { _ in }) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
    }

    func stop() async { observation?.cancel(); observation = nil; await flush() }

    static func persist(_ document: RichDocument, spaceID: String) async throws -> Atom {
        try await CosmoDatabase.shared.asyncWrite { db in
            guard var space = try Atom.filter(Column("uuid") == spaceID).filter(Column("is_deleted") == false).fetchOne(db),
                  space.metadata == nil || space.metadataDict != nil else { throw ContentPipelineError.invalidMetadata }
            let before = space
            space.metadata = RichDocumentMetadataStorage.writeDocument(document, into: space.metadata, key: documentKey)
            space.body = document.plainText
            space.updatedAt = ISO8601.string(from: Date()); space.localVersion += 1
            AtomRevisionWriter.snapshotIfNeeded(db, previous: before, incoming: space, source: .userEdit)
            try space.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [spaceID])
            return space
        }
    }

    func openContent() {
        NotificationCenter.default.post(name: CosmoNotification.Navigation.openPipeline, object: nil,
                                        userInfo: ["thinkspaceId": spaceID])
    }
}
