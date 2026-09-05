import AppKit
import CryptoKit
import GRDB
import Observation
import SwiftUI

/// The same rich document used by Notes, embedded in a Space's reading column.
/// The host owns scrolling, page titles and composition navigation.
struct SpacePageEditor: View {
    let atom: Atom
    var onSaved: ((Atom) -> Void)?
    var initialBlockID: UUID?
    var minimumBodyHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: SpacePageEditorSession
    @State private var confirmsReplacement = false

    init(atom: Atom, onSaved: ((Atom) -> Void)? = nil, initialBlockID: UUID? = nil, minimumBodyHeight: CGFloat = 220) {
        self.atom = atom
        self.onSaved = onSaved
        self.initialBlockID = initialBlockID
        self.minimumBodyHeight = minimumBodyHeight
        _session = State(initialValue: SpacePageEditorStore.shared.session(for: atom))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if let message = session.error { recoveryNotice(message) }
            editor
            saveStatus
        }
        .onAppear { session.attach(); session.receive(atom) }
        .onDisappear { session.detach() }
        .onChange(of: atom.localVersion) { _, _ in session.receive(atom) }
        .onChange(of: session.savedVersion) { _, _ in onSaved?(session.atom) }
        .confirmationDialog("Keep your draft?", isPresented: $confirmsReplacement) {
            Button("Keep my draft") { session.keepDraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved version will be retained in this page’s version history before your draft replaces it.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space.page.editor.\(atom.uuid)")
    }

    private var editor: some View {
        let style = NoteDocumentStyle.load(fromMetadata: session.atom.metadata)
        return BlockListView(
            document: Binding(get: { session.document }, set: { session.edit($0) }),
            fontSize: style.textSize.pointSize,
            fontDesign: style.fontFamily.design,
            lineSpacingAdjustment: style.lineSpacing.lineSpacingDelta,
            blockGap: style.lineSpacing.blockGap,
            placeholder: "Write, or press / for blocks…",
            darkMode: colorScheme == .dark,
            overrideTextColor: NSColor(DS.text),
            editorTargetID: EditorCommandTarget.noteBody(atom.uuid),
            navigationTargetID: initialBlockID,
            progressiveHydration: true,
            landingHighlightBlockID: initialBlockID
        )
        .frame(minHeight: minimumBodyHeight, alignment: .topLeading)
        .disabled(session.isDeleted)
    }

    private var saveStatus: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: session.isSaving ? "arrow.triangle.2.circlepath" : "checkmark")
                .accessibilityHidden(true)
            Text(session.status)
        }
        .font(DS.caption).foregroundStyle(DS.textMuted)
        .padding(.leading, BlockInteractionPolicy.gutterWidth)
        .frame(height: 20, alignment: .leading)
        .opacity(session.error == nil && (session.isSaving || session.hasSaved) ? 1 : 0)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: session.isSaving)
        .accessibilityHidden(session.error != nil || (!session.isSaving && !session.hasSaved))
    }

    private func recoveryNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.space12) {
                if session.hasConflict {
                    Button { confirmsReplacement = true } label: { Text("Keep my draft").frame(minHeight: 44) }
                        .help("Keep your writing and retain the saved version in history")
                } else if !session.isDeleted {
                    Button { Task { _ = await session.flush() } } label: { Text("Retry save").frame(minHeight: 44) }
                        .help("Retry saving this page")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.document.plainText, forType: .string)
                } label: { Text("Copy draft").frame(minHeight: 44) }
                .help("Copy your draft text for safekeeping")
            }.font(DS.subheadline).buttonStyle(.bordered).controlSize(.regular)
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
        .accessibilityElement(children: .contain)
    }
}

/// Clean, inactive sessions are bounded. Dirty sessions are never evicted, so
/// changing representations cannot strand a draft or cancel its save task.
@MainActor
final class SpacePageEditorStore {
    static let shared = SpacePageEditorStore()
    private var sessions: [String: SpacePageEditorSession] = [:]
    private var order: [String] = []
    private let capacity = 24

    func session(for atom: Atom) -> SpacePageEditorSession {
        if let existing = sessions[atom.uuid] { return existing }
        let session = SpacePageEditorSession(atom: atom)
        sessions[atom.uuid] = session
        order.append(atom.uuid)
        prune()
        return session
    }

    /// Call before preview/export so output includes edits still in the debounce.
    func flushAll() async -> Bool {
        var succeeded = true
        for session in Array(sessions.values) where session.isDirty {
            if !(await session.flush()) { succeeded = false }
        }
        prune()
        return succeeded
    }

    private func prune() {
        guard sessions.count > capacity else { return }
        for id in order where sessions.count > capacity {
            guard let session = sessions[id], session.canEvict else { continue }
            sessions[id] = nil
        }
        order.removeAll { sessions[$0] == nil }
    }
}

@MainActor @Observable
final class SpacePageEditorSession {
    private(set) var atom: Atom
    private(set) var document: RichDocument
    private(set) var isSaving = false
    private(set) var hasSaved = false
    private(set) var error: String?
    private(set) var hasConflict = false
    private(set) var isDeleted = false
    private(set) var savedVersion: Int64 = 0
    @ObservationIgnored private var base: SpacePageContentVersion
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var persistedGeneration = 0
    @ObservationIgnored private var attached = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var writer: Task<Bool, Never>?
    @ObservationIgnored private var replacesConflict = false
    @ObservationIgnored private var recovered = false

    var isDirty: Bool { generation != persistedGeneration }
    var canEvict: Bool { attached == 0 && !isDirty && !isSaving }
    var status: String { isSaving ? "Saving…" : "Saved" }
    private var registryID: String { "space-page-" + atom.uuid }

    init(atom: Atom) {
        self.atom = atom
        base = SpacePageContentVersion(atom)
        document = SpacePageContentVersion.document(atom)
        do {
            if let draft = try SpacePageDraftJournal.shared.load(uuid: atom.uuid) {
                if draft.document != document {
                    base = draft.base
                    document = draft.document
                    generation = 1
                    recovered = true
                    error = "Recovered writing that had not finished saving. Your draft is kept on this Mac."
                }
            }
        } catch {
            self.error = "The local recovery copy could not be read. Your saved page has been kept."
        }
    }

    func attach() {
        attached += 1
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        if isDirty {
            registerFlush()
            if recovered { recovered = false; Task { _ = await flush() } }
        }
    }

    func detach() {
        attached = max(0, attached - 1)
        // Block editor teardown can deliver its final text-storage sync on the
        // next main-loop turn. Retain this session and flush after that handoff.
        Task { @MainActor in
            await Task.yield()
            _ = await flush()
            if attached == 0 { AtomRepository.shared.releaseEditingLock(uuid: atom.uuid) }
        }
    }

    func receive(_ incoming: Atom) {
        guard incoming.uuid == atom.uuid, incoming.localVersion >= atom.localVersion else { return }
        if incoming.isDeleted {
            isDeleted = true
            error = isDirty ? "This page was deleted elsewhere. Your draft is still kept on this Mac." : "This page was deleted elsewhere."
            return
        }
        atom = incoming
        // A save echo must not overwrite text typed while the write was in flight.
        if !isDirty && !isSaving {
            base = SpacePageContentVersion(incoming)
            let loaded = SpacePageContentVersion.document(incoming)
            if document != loaded { document = loaded }
        }
    }

    func edit(_ next: RichDocument) {
        guard next != document, !isDeleted else { return }
        // BlockList inserts an empty editing row on mount; that alone is not a
        // user edit and must not claim ownership over newer remote content.
        if document.blocks.isEmpty && next.isEmpty && !isDirty { document = next; return }
        document = next
        generation += 1
        hasSaved = false
        AtomRepository.shared.refreshEditingLock(uuid: atom.uuid)
        registerFlush()
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            _ = await self.flush()
        }
    }

    func keepDraft() {
        guard hasConflict else { return }
        replacesConflict = true
        Task { _ = await flush() }
    }

    @discardableResult
    func flush() async -> Bool {
        debounce?.cancel(); debounce = nil
        if let writer { return await writer.value }
        guard isDirty else { return true }
        let task = Task { @MainActor in await drain() }
        writer = task
        let result = await task.value
        writer = nil
        return result
    }

    private func drain() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        while isDirty {
            let draft = snapshot()
            let replaces = replacesConflict
            replacesConflict = false
            do {
                // The independent atomic file survives a database write failure.
                // It is removed only when this exact draft has committed.
                try await SpacePageDraftJournal.shared.save(draft)
                let saved = try await CosmoDatabase.shared.asyncWrite { db in
                    try SpacePageContentWriter.persist(draft, replacingConflict: replaces, in: db)
                }
                base = SpacePageContentVersion(saved)
                atom = saved
                persistedGeneration = draft.generation
                savedVersion = saved.localVersion
                hasSaved = true
                hasConflict = false
                error = nil
                try? await SpacePageDraftJournal.shared.remove(uuid: atom.uuid, through: draft.id)
                publish(saved)
                if !isDirty {
                    DirtyEditorRegistry.shared.unregister(id: registryID)
                    if attached == 0 { AtomRepository.shared.releaseEditingLock(uuid: atom.uuid) }
                }
            } catch {
                hasConflict = (error as? SpacePageSaveFailure) == .contentChanged
                isDeleted = (error as? SpacePageSaveFailure) == .deleted
                self.error = hasConflict
                    ? "This page changed elsewhere. Your draft is kept on this Mac; choose whether to keep it."
                    : "Your page could not finish saving. Your writing remains here. \(error.localizedDescription)"
                PersistenceHealth.note(.writeFailure, context: "space.page.save", detail: "uuid=\(atom.uuid): \(error)")
                return false
            }
        }
        return true
    }

    private func snapshot() -> SpacePageDraft {
        SpacePageDraft(uuid: atom.uuid, base: base, document: document, generation: generation)
    }

    private func registerFlush() {
        DirtyEditorRegistry.shared.register(id: registryID) { [weak self] in self?.flushSynchronously() }
    }

    private func flushSynchronously() {
        guard isDirty else { return }
        let draft = snapshot()
        do {
            try SpacePageDraftJournal.shared.saveSynchronously(draft)
            let saved = try CosmoDatabase.shared.write { db in
                try SpacePageContentWriter.persist(draft, replacingConflict: false, in: db)
            }
            base = SpacePageContentVersion(saved)
            atom = saved
            persistedGeneration = draft.generation
        } catch {
            PersistenceHealth.note(.writeFailure, context: "space.page.terminate", detail: "uuid=\(atom.uuid): \(error)")
        }
    }

    private func publish(_ saved: Atom) {
        NotificationCenter.default.post(name: .richDocumentDidChange, object: nil, userInfo: ["atomUUID": saved.uuid])
        NotificationCenter.default.post(name: .noteFocusStateDidChange, object: nil,
                                        userInfo: ["atomUUID": saved.uuid, "title": saved.title ?? "", "body": saved.body ?? ""])
        Task { @MainActor in
            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: saved, skipVersionIncrement: true)
            try? await NodeGraphEngine.shared.handleAtomUpdated(saved, changedFields: ["body", "metadata"])
        }
        Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(saved) }
    }
}

/// Compare content fields only. Concurrent title, reference or composition
/// changes are intentionally independent of a body edit.
struct SpacePageContentVersion: Codable, Equatable, Sendable {
    var body: String?
    var richDocument: RichDocument?

    init(_ atom: Atom) {
        body = atom.body
        richDocument = RichDocumentMetadataStorage.readDocument(from: atom.metadata, key: RichDocumentField.body.metadataKey)
    }

    static func document(_ atom: Atom) -> RichDocument {
        RichDocumentPersistence.loadAtomDocument(field: .body, metadata: atom.metadata, fallbackPlainText: atom.body)
    }
}

struct SpacePageDraft: Codable, Sendable {
    var id = UUID()
    let uuid: String
    let base: SpacePageContentVersion
    let document: RichDocument
    let generation: Int
    var savedAt = Date()
}

enum SpacePageSaveFailure: Error, LocalizedError, Equatable {
    case deleted, contentChanged, unreadableMetadata
    var errorDescription: String? {
        switch self {
        case .deleted: "The page was deleted. Its saved version has not been changed."
        case .contentChanged: "A newer version of this page is already saved."
        case .unreadableMetadata: "This page’s saved information could not be read."
        }
    }
}

enum SpacePageContentWriter {
    /// Pure ownership/conflict policy shared by the real writer and regression tests.
    static func applying(_ draft: SpacePageDraft, to fresh: Atom, replacingConflict: Bool = false) throws -> Atom {
        guard !fresh.isDeleted, fresh.uuid == draft.uuid else { throw SpacePageSaveFailure.deleted }
        if let metadata = fresh.metadata, !metadata.isEmpty {
            guard let bytes = metadata.data(using: .utf8),
                  let fields = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { throw SpacePageSaveFailure.unreadableMetadata }
            if fields[RichDocumentField.body.metadataKey] != nil,
               RichDocumentMetadataStorage.readDocument(from: metadata, key: RichDocumentField.body.metadataKey) == nil {
                throw SpacePageSaveFailure.unreadableMetadata
            }
        }
        let current = SpacePageContentVersion(fresh)
        let alreadySaved = current.richDocument == draft.document && fresh.body == draft.document.plainText
        guard replacingConflict || current == draft.base || alreadySaved else { throw SpacePageSaveFailure.contentChanged }
        var result = fresh
        let written = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata, bodyDocument: draft.document)
        result.body = draft.document.plainText
        result.metadata = written.metadata
        return result
    }

    static func persist(_ draft: SpacePageDraft, replacingConflict: Bool, in db: Database) throws -> Atom {
        guard let fresh = try Atom.filter(Column("uuid") == draft.uuid).fetchOne(db) else { throw SpacePageSaveFailure.deleted }
        var result = try applying(draft, to: fresh, replacingConflict: replacingConflict)
        guard result.body != fresh.body || result.metadata != fresh.metadata else { return fresh }
        if replacingConflict {
            // Explicit replacement must retain the pre-image even if the normal
            // five-minute autosave revision window has not elapsed.
            var revision = AtomRevision(of: fresh, source: .restore)
            try revision.insert(db)
        } else {
            AtomRevisionWriter.snapshotIfNeeded(db, previous: fresh, incoming: result, source: .userEdit)
        }
        result.localVersion = fresh.localVersion + 1
        result.updatedAt = ISO8601.string(from: .now)
        try result.update(db)
        try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [result.uuid])
        // Termination can occur before ChangeTracker runs. Queue in this same
        // transaction, scoped by table so legacy placement UUIDs cannot collide.
        let payload = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        let pending = try Int64.fetchOne(db, sql: "SELECT id FROM sync_queue WHERE uuid = ? AND table_name = 'atoms' AND status = 'pending'", arguments: [result.uuid])
        if let pending {
            try db.execute(sql: "UPDATE sync_queue SET operation = 'UPDATE', data = ?, local_version = ?, created_at = ? WHERE id = ?",
                           arguments: [payload, result.localVersion, Int64(Date().timeIntervalSince1970 * 1000), pending])
        } else {
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, row_id, operation, data, local_version, status) VALUES (?, 'atoms', ?, 'UPDATE', ?, ?, 'pending')",
                           arguments: [result.uuid, result.id, payload, result.localVersion])
        }
        return result
    }
}

/// A serial, atomic recovery journal independent of the database writer lock.
/// Revision IDs prevent a completed older save from erasing a newer checkpoint.
final class SpacePageDraftJournal: @unchecked Sendable {
    static let shared = SpacePageDraftJournal()
    private let queue = DispatchQueue(label: "com.cosmo.space-page-recovery", qos: .utility)
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CosmoOS/SpacePageDrafts", isDirectory: true)
    }

    func load(uuid: String) throws -> SpacePageDraft? {
        try queue.sync { try read(uuid: uuid) }
    }

    func saveSynchronously(_ draft: SpacePageDraft) throws {
        try queue.sync { try write(draft) }
    }

    func save(_ draft: SpacePageDraft) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.write(draft); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func remove(uuid: String, through id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if try self.read(uuid: uuid)?.id == id { try FileManager.default.removeItem(at: self.url(uuid)) }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func read(uuid: String) throws -> SpacePageDraft? {
        let location = url(uuid)
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        return try JSONDecoder().decode(SpacePageDraft.self, from: Data(contentsOf: location))
    }

    private func write(_ draft: SpacePageDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url(draft.uuid), options: .atomic)
    }

    private func url(_ uuid: String) -> URL {
        let name = SHA256.hash(data: Data(uuid.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
