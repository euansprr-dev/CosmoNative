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
    var typewriterMode: Bool
    var paragraphFocus: Bool
    var showsSaveStatus: Bool
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: SpacePageEditorSession
    @State private var confirmsReplacement = false

    init(atom: Atom, onSaved: ((Atom) -> Void)? = nil, initialBlockID: UUID? = nil, minimumBodyHeight: CGFloat = 220,
         typewriterMode: Bool = false, paragraphFocus: Bool = false, showsSaveStatus: Bool = true,
         onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil) {
        self.init(session: SpacePageEditorStore.shared.session(for: atom), onSaved: onSaved,
                  initialBlockID: initialBlockID, minimumBodyHeight: minimumBodyHeight,
                  typewriterMode: typewriterMode, paragraphFocus: paragraphFocus, showsSaveStatus: showsSaveStatus,
                  onSelectionChanged: onSelectionChanged)
    }

    init(session: SpacePageEditorSession, onSaved: ((Atom) -> Void)? = nil, initialBlockID: UUID? = nil,
         minimumBodyHeight: CGFloat = 220, typewriterMode: Bool = false, paragraphFocus: Bool = false,
         showsSaveStatus: Bool = true, onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil) {
        self.atom = session.atom
        self.onSaved = onSaved
        self.initialBlockID = initialBlockID
        self.minimumBodyHeight = minimumBodyHeight
        self.typewriterMode = typewriterMode
        self.paragraphFocus = paragraphFocus
        self.showsSaveStatus = showsSaveStatus
        self.onSelectionChanged = onSelectionChanged
        _session = State(initialValue: session)
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
        let style = session.style
        return BlockListView(
            document: Binding(get: { session.document }, set: { session.edit($0) }),
            fontSize: style.textSize.pointSize,
            fontDesign: style.fontFamily.design,
            lineSpacingAdjustment: style.lineSpacing.lineSpacingDelta,
            blockGap: style.lineSpacing.blockGap,
            dimsInactiveBlocks: paragraphFocus,
            placeholder: "Write, or press / for blocks…",
            darkMode: colorScheme == .dark,
            overrideTextColor: NSColor(DS.text),
            typewriterMode: typewriterMode,
            editorTargetID: EditorCommandTarget.noteBody(atom.uuid),
            navigationTargetID: initialBlockID,
            progressiveHydration: true,
            minimumWritingHeight: minimumBodyHeight,
            minimumTailHeight: 160,
            landingHighlightBlockID: initialBlockID,
            onSelectionChanged: onSelectionChanged
        )
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
        .opacity(showsSaveStatus && session.error == nil && (session.isSaving || session.hasSaved) ? 1 : 0)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: session.isSaving)
        .accessibilityHidden(!showsSaveStatus || session.error != nil || (!session.isSaving && !session.hasSaved))
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
        if let existing = sessions[atom.uuid] {
            existing.receive(atom)
            return existing
        }
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
    private(set) var titleDocument: RichDocument
    private(set) var style: NoteDocumentStyle
    private(set) var tags: [String]
    private(set) var isSaving = false
    private(set) var hasSaved = false
    private(set) var error: String?
    private(set) var hasConflict = false
    private(set) var isDeleted = false
    private(set) var savedVersion: Int64 = 0
    private(set) var dirtyFields: Set<SpacePageOwnedField> = []
    @ObservationIgnored private var base: SpacePageContentVersion
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fieldGenerations: [SpacePageOwnedField: Int] = [:]
    @ObservationIgnored private var attached = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var writer: Task<Bool, Never>?
    @ObservationIgnored private var replacesConflict = false
    @ObservationIgnored private var recovered = false
    @ObservationIgnored private let journal: SpacePageDraftJournal
    @ObservationIgnored private let save: @Sendable (SpacePageDraft, Bool) async throws -> Atom
    @ObservationIgnored private let saveImmediately: @MainActor @Sendable (SpacePageDraft, Bool) throws -> Atom
    @ObservationIgnored private let publishesChanges: Bool

    var title: String { RichDocumentPersistence.titlePlainText(from: titleDocument) }
    var isDirty: Bool { !dirtyFields.isEmpty }
    var canEvict: Bool { attached == 0 && !isDirty && !isSaving }
    var status: String { isSaving ? "Saving…" : "Saved" }
    private var registryID: String { "space-page-" + atom.uuid }

    init(atom: Atom, journal: SpacePageDraftJournal = .shared,
         publishesChanges: Bool = true,
         saveSynchronously: (@MainActor @Sendable (SpacePageDraft, Bool) throws -> Atom)? = nil,
         save: (@Sendable (SpacePageDraft, Bool) async throws -> Atom)? = nil) {
        self.atom = atom
        self.journal = journal
        self.publishesChanges = publishesChanges
        self.saveImmediately = saveSynchronously ?? { draft, replaces in
            try CosmoDatabase.shared.write { db in
                try SpacePageContentWriter.persist(draft, replacingConflict: replaces, in: db)
            }
        }
        self.save = save ?? { draft, replaces in
            try await CosmoDatabase.shared.asyncWrite { db in
                try SpacePageContentWriter.persist(draft, replacingConflict: replaces, in: db)
            }
        }
        base = SpacePageContentVersion(atom)
        document = SpacePageContentVersion.document(atom)
        titleDocument = SpacePageContentVersion.titleDocument(atom)
        style = NoteDocumentStyle.load(fromMetadata: atom.metadata)
        tags = atom.tagsList
        isDeleted = atom.isDeleted
        do {
            if let draft = try journal.load(uuid: atom.uuid), draft.uuid == atom.uuid {
                // A crash after commit can leave the checkpoint behind. Restore
                // only fields whose desired values are not already persisted.
                for field in draft.dirtyFields where !draft.matches(field, in: atom) {
                    base.copy(field, from: draft.base)
                    switch field {
                    case .body: document = draft.document
                    case .title: if let value = draft.titleDocument { titleDocument = value }
                    case .style: if let value = draft.style { style = value }
                    case .tags: if let value = draft.tags { tags = value }
                    }
                    dirtyFields.insert(field)
                    fieldGenerations[field] = 1
                }
                if isDirty {
                    generation = 1
                    recovered = true
                    error = "Recovered changes that had not finished saving. Your draft is kept on this Mac."
                } else {
                    // A prior process may have stopped between commit and
                    // cleanup. Retire that exact checkpoint now, before a
                    // later restore or remote edit changes the saved content.
                    try journal.removeSynchronously(uuid: atom.uuid, through: draft.id)
                }
            }
        } catch {
            self.error = "The local recovery copy could not be read. Your saved page has been kept."
        }
    }

    func attach() {
        attached += 1
        retainEditingOwnership()
        if isDirty {
            registerFlush()
            if recovered { recovered = false; Task { _ = await flush() } }
        }
    }

    func detach() {
        attached = max(0, attached - 1)
        // Teardown may deliver a final text-storage sync on the next turn.
        Task { @MainActor in
            await Task.yield()
            _ = await flush()
            releaseEditingOwnershipIfIdle()
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
        let current = SpacePageContentVersion(incoming)
        // Remote metadata can still reach controls while body text is dirty.
        // Dirty fields retain their original comparison base until committed.
        for field in SpacePageOwnedField.allCases where !dirtyFields.contains(field) {
            guard !base.matches(field, current) else { continue }
            base.copy(field, from: current)
            adopt(field, from: incoming)
        }
    }

    func edit(_ next: RichDocument) {
        guard next != document, !isDeleted else { return }
        // Mounting inserts an empty writing row, which is not an authored edit.
        if document.blocks.isEmpty && next.isEmpty && !dirtyFields.contains(.body) { document = next; return }
        document = next
        changed(.body)
    }

    func editTitle(_ next: RichDocument) {
        let normalized = RichDocumentPersistence.normalizedTitleDocument(next)
        guard normalized != titleDocument, !isDeleted else { return }
        titleDocument = normalized
        changed(.title)
    }

    func editStyle(_ next: NoteDocumentStyle) {
        guard next != style, !isDeleted else { return }
        style = next
        changed(.style)
    }

    func editTags(_ next: [String]) {
        var seen = Set<String>()
        let normalized = next.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard normalized != tags, !isDeleted else { return }
        tags = normalized
        changed(.tags)
    }

    private func changed(_ field: SpacePageOwnedField) {
        generation += 1
        fieldGenerations[field] = generation
        dirtyFields.insert(field)
        hasSaved = false
        retainEditingOwnership()
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

    /// History must not replace writing that failed to reach the database.
    func prepareForHistory() async -> Bool {
        guard !isDeleted else { return false }
        return await flush()
    }

    func adoptRestored(_ restored: Atom) {
        guard restored.uuid == atom.uuid else { return }
        guard !isDirty, !isSaving else {
            receive(restored)
            hasConflict = true
            error = "The restored version is saved. Your newer draft is still here; choose whether to keep it."
            return
        }
        debounce?.cancel(); debounce = nil
        receive(restored)
        hasConflict = false
        error = nil
        hasSaved = true
        savedVersion = restored.localVersion
    }

    @discardableResult
    func flush() async -> Bool {
        debounce?.cancel(); debounce = nil
        if let writer { return await writer.value }
        guard isDirty else { return !isDeleted }
        let task = Task { @MainActor in await drain() }
        writer = task
        let result = await task.value
        writer = nil
        releaseEditingOwnershipIfIdle()
        return result
    }

    private func drain() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        while isDirty {
            let draft = snapshot()
            let versionBeforeSave = savedVersion
            let replaces = replacesConflict
            replacesConflict = false
            do {
                try await journal.save(draft)
                let saved = try await save(draft, replaces)
                let publishesThisSave = saved.localVersion >= savedVersion
                acceptSaved(saved, draft: draft)
                try? await journal.remove(uuid: atom.uuid, through: draft.id)
                if publishesChanges && publishesThisSave { publish(saved, fields: draft.dirtyFields) }
            } catch {
                // A termination/history flush can commit a newer generation
                // synchronously while this async task awaits its result.
                if savedVersion > versionBeforeSave { continue }
                report(error)
                PersistenceHealth.note(.writeFailure, context: "space.page.save", detail: "uuid=\(atom.uuid): \(error)")
                return false
            }
        }
        return true
    }

    private func snapshot() -> SpacePageDraft {
        SpacePageDraft(uuid: atom.uuid, base: base, document: document, generation: generation,
                       dirtyFields: dirtyFields, titleDocument: titleDocument, style: style, tags: tags)
    }

    private func acceptSaved(_ saved: Atom, draft: SpacePageDraft) {
        guard saved.localVersion >= savedVersion else { return }
        let version = SpacePageContentVersion(saved)
        let newest = atom.localVersion > saved.localVersion ? atom : saved
        atom = newest
        for field in SpacePageOwnedField.allCases {
            if draft.dirtyFields.contains(field) {
                base.copy(field, from: version)
                if (fieldGenerations[field] ?? 0) <= draft.generation {
                    dirtyFields.remove(field)
                    fieldGenerations[field] = nil
                }
                if !dirtyFields.contains(field) { adopt(field, from: saved) }
            }
        }
        // Use the newest received structure and adopt its unedited fields.
        receive(newest)
        savedVersion = saved.localVersion
        hasSaved = !isDirty
        hasConflict = false
        error = nil
        if !isDirty { DirtyEditorRegistry.shared.unregister(id: registryID) }
    }

    private func adopt(_ field: SpacePageOwnedField, from value: Atom) {
        switch field {
        case .body:
            let loaded = SpacePageContentVersion.document(value)
            if document != loaded { document = loaded }
        case .title:
            let loaded = SpacePageContentVersion.titleDocument(value)
            if titleDocument != loaded { titleDocument = loaded }
        case .style:
            let loaded = NoteDocumentStyle.load(fromMetadata: value.metadata)
            if style != loaded { style = loaded }
        case .tags: if tags != value.tagsList { tags = value.tagsList }
        }
    }

    private func retainEditingOwnership() {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        AtomRestoreAdopterRegistry.shared.register(uuid: atom.uuid, prepare: { [weak self] in
            guard let self else { return true }
            return await self.prepareForHistory()
        }, adopt: { [weak self] restored in self?.adoptRestored(restored) })
    }

    private func releaseEditingOwnershipIfIdle() {
        guard attached == 0, !isDirty, !isSaving else { return }
        AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        AtomRestoreAdopterRegistry.shared.unregister(uuid: atom.uuid)
    }

    private func registerFlush() {
        DirtyEditorRegistry.shared.register(id: registryID) { [weak self] in _ = self?.flushSynchronously() }
    }

    @discardableResult
    func flushSynchronously() -> Bool {
        guard isDirty else { return !isDeleted }
        debounce?.cancel(); debounce = nil
        let draft = snapshot()
        do {
            try journal.saveSynchronously(draft)
            let saved = try saveImmediately(draft, false)
            // A restore may immediately follow this flush. A committed draft
            // must not survive and later masquerade as unsaved writing.
            try journal.removeSynchronously(uuid: atom.uuid, through: draft.id)
            acceptSaved(saved, draft: draft)
            if publishesChanges { publish(saved, fields: draft.dirtyFields) }
            releaseEditingOwnershipIfIdle()
            return true
        } catch {
            report(error)
            PersistenceHealth.note(.writeFailure, context: "space.page.terminate", detail: "uuid=\(atom.uuid): \(error)")
            return false
        }
    }

    private func report(_ failure: Error) {
        hasConflict = (failure as? SpacePageSaveFailure) == .contentChanged
        isDeleted = (failure as? SpacePageSaveFailure) == .deleted
        error = hasConflict
            ? "This page changed elsewhere. Your draft is kept on this Mac; choose whether to keep it."
            : "Your page could not finish saving. Your changes remain here. \(failure.localizedDescription)"
    }

    private func publish(_ saved: Atom, fields: Set<SpacePageOwnedField>) {
        NotificationCenter.default.post(name: .richDocumentDidChange, object: nil, userInfo: ["atomUUID": saved.uuid])
        NotificationCenter.default.post(name: .noteFocusStateDidChange, object: nil,
                                        userInfo: ["atomUUID": saved.uuid, "title": saved.title ?? "", "body": saved.body ?? ""])
        var changed = ["metadata"]
        if fields.contains(.body) { changed.append("body") }
        if fields.contains(.title) { changed.append("title") }
        let changedFields = changed
        Task { @MainActor in
            await ChangeTracker.shared.trackUpdate(table: "atoms", entity: saved, skipVersionIncrement: true)
            try? await NodeGraphEngine.shared.handleAtomUpdated(saved, changedFields: changedFields)
        }
        Task.detached(priority: .utility) { await RecallIndexer.shared.noteAtomChanged(saved) }
    }
}

enum SpacePageOwnedField: String, Codable, CaseIterable, Sendable {
    case body, title, style, tags
}

/// Baselines are compared per owned field. Older body-only recovery files
/// decode with nil auxiliary fields and continue to own only their body.
struct SpacePageContentVersion: Codable, Equatable, Sendable {
    var body: String?
    var richDocument: RichDocument?
    var title: String?
    var richTitleDocument: RichDocument?
    var style: NoteDocumentStyle?
    var tags: [String]?

    init(_ atom: Atom) {
        body = atom.body
        richDocument = RichDocumentMetadataStorage.readDocument(from: atom.metadata, key: RichDocumentField.body.metadataKey)
        title = atom.title
        richTitleDocument = RichDocumentMetadataStorage.readDocument(from: atom.metadata, key: RichDocumentField.title.metadataKey)
        style = NoteDocumentStyle.load(fromMetadata: atom.metadata)
        tags = atom.tagsList
    }

    func matches(_ field: SpacePageOwnedField, _ other: Self) -> Bool {
        switch field {
        case .body: body == other.body && richDocument == other.richDocument
        case .title: title == other.title && richTitleDocument == other.richTitleDocument
        case .style: style == other.style
        case .tags: tags == other.tags
        }
    }

    mutating func copy(_ field: SpacePageOwnedField, from value: Self) {
        switch field {
        case .body: body = value.body; richDocument = value.richDocument
        case .title: title = value.title; richTitleDocument = value.richTitleDocument
        case .style: style = value.style
        case .tags: tags = value.tags
        }
    }

    static func document(_ atom: Atom) -> RichDocument {
        RichDocumentPersistence.loadAtomDocument(field: .body, metadata: atom.metadata, fallbackPlainText: atom.body)
    }

    static func titleDocument(_ atom: Atom) -> RichDocument {
        RichDocumentPersistence.loadAtomDocument(field: .title, metadata: atom.metadata, fallbackPlainText: atom.title)
    }
}

struct SpacePageDraft: Codable, Sendable {
    var id: UUID
    let uuid: String
    let base: SpacePageContentVersion
    let document: RichDocument
    let generation: Int
    var savedAt: Date
    let dirtyFields: Set<SpacePageOwnedField>
    let titleDocument: RichDocument?
    let style: NoteDocumentStyle?
    let tags: [String]?

    init(id: UUID = UUID(), uuid: String, base: SpacePageContentVersion, document: RichDocument,
         generation: Int, savedAt: Date = Date(), dirtyFields: Set<SpacePageOwnedField> = [.body],
         titleDocument: RichDocument? = nil, style: NoteDocumentStyle? = nil, tags: [String]? = nil) {
        self.id = id
        self.uuid = uuid
        self.base = base
        self.document = document
        self.generation = generation
        self.savedAt = savedAt
        self.dirtyFields = dirtyFields
        self.titleDocument = titleDocument.map(RichDocumentPersistence.normalizedTitleDocument)
        self.style = style
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id, uuid, base, document, generation, savedAt, dirtyFields, titleDocument, style, tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        uuid = try values.decode(String.self, forKey: .uuid)
        base = try values.decode(SpacePageContentVersion.self, forKey: .base)
        document = try values.decode(RichDocument.self, forKey: .document)
        generation = try values.decode(Int.self, forKey: .generation)
        savedAt = try values.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        dirtyFields = try values.decodeIfPresent(Set<SpacePageOwnedField>.self, forKey: .dirtyFields) ?? [.body]
        titleDocument = try values.decodeIfPresent(RichDocument.self, forKey: .titleDocument)
        style = try values.decodeIfPresent(NoteDocumentStyle.self, forKey: .style)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        // A malformed new-format checkpoint must never become an empty edit.
        if (dirtyFields.contains(.title) && titleDocument == nil) ||
            (dirtyFields.contains(.style) && style == nil) || (dirtyFields.contains(.tags) && tags == nil) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "The page draft is missing an edited field."))
        }
    }

    func matches(_ field: SpacePageOwnedField, in atom: Atom) -> Bool {
        let current = SpacePageContentVersion(atom)
        switch field {
        case .body: return current.richDocument == document && atom.body == document.plainText
        case .title:
            guard let titleDocument else { return false }
            return current.richTitleDocument == titleDocument &&
                (atom.title ?? "") == RichDocumentPersistence.titlePlainText(from: titleDocument)
        case .style: return current.style == style
        case .tags: return current.tags == tags
        }
    }
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
        var fields: [String: Any] = [:]
        if let metadata = fresh.metadata, !metadata.isEmpty {
            guard let bytes = metadata.data(using: .utf8),
                  let decoded = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
                throw SpacePageSaveFailure.unreadableMetadata
            }
            fields = decoded
            for field in [RichDocumentField.body, .title] where fields[field.metadataKey] != nil {
                guard RichDocumentMetadataStorage.readDocument(from: metadata, key: field.metadataKey) != nil else {
                    throw SpacePageSaveFailure.unreadableMetadata
                }
            }
        }
        let current = SpacePageContentVersion(fresh)
        for field in draft.dirtyFields {
            guard replacingConflict || current.matches(field, draft.base) || draft.matches(field, in: fresh) else {
                throw SpacePageSaveFailure.contentChanged
            }
        }
        var result = fresh
        let writesTitle = draft.dirtyFields.contains(.title)
        let writesBody = draft.dirtyFields.contains(.body)
        if writesTitle && draft.titleDocument == nil { throw SpacePageSaveFailure.unreadableMetadata }
        let written = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata,
            titleDocument: writesTitle ? draft.titleDocument : nil,
            bodyDocument: writesBody ? draft.document : nil)
        if writesTitle { result.title = written.title }
        if writesBody { result.body = draft.document.plainText }
        result.metadata = written.metadata
        if draft.dirtyFields.contains(.style) || draft.dirtyFields.contains(.tags) {
            if let metadata = result.metadata {
                guard let decoded = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any] else {
                    throw SpacePageSaveFailure.unreadableMetadata
                }
                fields = decoded
            }
            if draft.dirtyFields.contains(.style) {
                guard let style = draft.style,
                      let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any] else {
                    throw SpacePageSaveFailure.unreadableMetadata
                }
                // Preserve future style keys alongside the controls this client owns.
                var merged = fields[NoteDocumentStyle.metadataKey] as? [String: Any] ?? [:]
                for key in ["fontFamily", "textSize", "pageWidth", "lineSpacing", "paperTone", "pageIcon", "cover"] {
                    merged[key] = encoded[key]
                }
                fields[NoteDocumentStyle.metadataKey] = merged
            }
            if draft.dirtyFields.contains(.tags) {
                guard let tags = draft.tags else { throw SpacePageSaveFailure.unreadableMetadata }
                fields["tags"] = tags
            }
            result.metadata = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys), as: UTF8.self)
        }
        return result
    }

    static func persist(_ draft: SpacePageDraft, replacingConflict: Bool, in db: Database) throws -> Atom {
        guard let fresh = try Atom.filter(Column("uuid") == draft.uuid).fetchOne(db) else { throw SpacePageSaveFailure.deleted }
        var result = try applying(draft, to: fresh, replacingConflict: replacingConflict)
        guard result.title != fresh.title || result.body != fresh.body || result.metadata != fresh.metadata else { return fresh }
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

    func removeSynchronously(uuid: String, through id: UUID) throws {
        try queue.sync {
            if try read(uuid: uuid)?.id == id { try FileManager.default.removeItem(at: url(uuid)) }
        }
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
