// CosmoOS/Canvas/ConnectionBlockView.swift
// Purple-accented Connection block for Thinkspace canvas
// Scrollable editable sections with live GRDB sync
// February 2026 - Redesign: inline editing + bidirectional sync with Focus Mode

import SwiftUI
import GRDB
import Combine

struct ConnectionBlockView: View {
    let block: CanvasBlock

    @State private var sections: [ConnectionSection] = []
    @State private var atom: Atom?
    @State private var observationCancellable: AnyCancellable?
    @State private var editableTitle: String = ""
    @State private var titleDocument: RichDocument = .empty
    @State private var titleEditorHeight: CGFloat = 50
    @State private var pendingObservedTitleDocument: RichDocument?
    @State private var titleDocumentAtEditStart: RichDocument = .empty
    @State private var isEditingTitle = false
    @State private var sectionsModifiedLocally = false
    // Purple accent for connections
    private let accentColor = DS.entityConnection
    private let titleStyle = SharedTitleSurfaceStyle.connectionCanvas

    private var titleFontSize: CGFloat { titleStyle.fontSize }

    private var titleMinHeight: CGFloat { titleStyle.minimumHeight }

    private var titlePreviewMaxHeight: CGFloat { titleStyle.previewMaxHeight }

    private var titleEditingMaxHeight: CGFloat { titleStyle.editingMaxHeight }

    private var totalItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    private var populatedSectionCount: Int {
        sections.filter { !$0.items.isEmpty }.count
    }

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "link.circle.fill",
            title: displayTitle,
            autoHeight: true,
            onFocusMode: openFocusMode
        ) {
            connectionContent
        }
        .onAppear {
            loadInitialData()
            startObservingAtom()
            titleEditorHeight = titleMinHeight
        }
        .onDisappear {
            print("[BLOCK-CONN] onDisappear — entityId=\(block.entityId) uuid=\(atom?.uuid ?? "nil") isEditingTitle=\(isEditingTitle) sectionsCount=\(sections.count)")
            // Defer by one frame so the editor's flushPendingSync updates titleDocument first
            if isEditingTitle {
                DispatchQueue.main.async {
                    commitTitleEdit(document: titleDocument)
                }
            }
            observationCancellable?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingTitle = false
        }
        // Cover media banner follows the structured column (recomputed only
        // when the JSON actually changes — never per body pass).
        .task(id: atom?.structured) { await refreshCoverMedia() }
        .onChange(of: block.entityId) { _, newId in
            if newId > 0 {
                observationCancellable?.cancel()
                startObservingAtom()
            }
        }
        .onChange(of: isEditingTitle) { _, isEditing in
            if isEditing {
                titleDocumentAtEditStart = titleDocument
                pendingObservedTitleDocument = nil
                titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight))
            } else {
                // Defer commit by one frame so CosmoDocumentEditor's flushPendingSync()
                // has time to update titleDocument via the binding before we read it.
                // Without this, commitTitleEdit reads a stale titleDocument (the last
                // debounced sync, not the final text) and saves partial content.
                DispatchQueue.main.async {
                    if titleDocument != titleDocumentAtEditStart {
                        commitTitleEdit(document: titleDocument)
                    } else if let pendingObservedTitleDocument {
                        applyObservedTitleDocument(pendingObservedTitleDocument)
                    }
                    pendingObservedTitleDocument = nil
                }
            }
        }
    }

    private var displayTitle: String {
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Concept" : trimmed
    }

    // MARK: - Connection Content (at-a-glance preview)

    private var connectionContent: some View {
        VStack(spacing: 0) {
            crucibleMasthead
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)

            if coverMediaItem != nil {
                coverBanner
                Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
            }

            sectionPreviewList
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            crucibleFooter
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Cover media banner

    /// The concept's cover ref + its resolved source atom (for thumbnails).
    @State private var coverMediaItem: ConnectionMediaItem?
    @State private var coverSourceAtom: Atom?

    private func refreshCoverMedia() async {
        guard let json = atom?.structured,
              let data = ConnectionStructuredData.fromJSON(json),
              let cover = data.media?.first(where: { $0.isCover }) else {
            coverMediaItem = nil
            coverSourceAtom = nil
            return
        }
        coverMediaItem = cover
        if let sourceUUID = cover.atomUUID, coverSourceAtom?.uuid != sourceUUID {
            coverSourceAtom = try? await AtomRepository.shared.fetch(uuid: sourceUUID)
        }
    }

    /// A quiet wide banner under the masthead — the concept wears its cover.
    @ViewBuilder
    private var coverBanner: some View {
        if let cover = coverMediaItem {
            Group {
                if let poster = cover.thumbnailAssetPath {
                    ConceptLocalThumbnail(path: poster)
                } else if let path = cover.assetPath, !MediaAssetStore.isVideoPath(path) {
                    ConceptLocalThumbnail(path: path)
                } else if let source = coverSourceAtom,
                          let url = ConceptMediaThumbnailResolver.thumbnailURL(for: source) {
                    CachedAsyncImage(url: url, stableKey: "block-cover-\(cover.id.uuidString)") { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            Rectangle().fill(DS.sepiaSubtle)
                        @unknown default:
                            Rectangle().fill(DS.sepiaSubtle)
                        }
                    }
                } else {
                    Rectangle().fill(DS.sepiaSubtle)
                }
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Cover image")
        }
    }

    /// Populated sections in sortOrder, capped for the block preview.
    private var previewSections: [ConnectionSection] {
        sections
            .filter { !$0.items.isEmpty }
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    // MARK: - Masthead (block)

    private var crucibleMasthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if isEditingTitle {
                        inlineTitleEditor
                    } else {
                        Text(displayTitle)
                            .font(.system(size: 15, weight: .light, design: .serif))
                            .tracking(0.3)
                            .foregroundStyle(editableTitle.isEmpty ? DS.textMuted : DS.inkWash)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                titleDocumentAtEditStart = titleDocument
                                isEditingTitle = true
                            }
                    }
                    Text(frameworkTypeLabel)
                        .font(DS.smallCaps)
                        .tracking(1.6)
                        .foregroundStyle(DS.giltMuted)
                }
                Spacer(minLength: 6)
                Text("\(populatedSectionCount)/\(ConnectionSectionType.allCases.count)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
                    .help("\(populatedSectionCount) of \(ConnectionSectionType.allCases.count) sections filled")
            }
            maturityBar
        }
    }

    /// Thin completion bar — how filled this concept is, readable at a glance.
    private var maturityBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.sepiaSubtle)
                Capsule()
                    .fill(accentColor.opacity(0.75))
                    .frame(
                        width: geometry.size.width *
                            CGFloat(populatedSectionCount) / CGFloat(ConnectionSectionType.allCases.count)
                    )
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Maturity: \(populatedSectionCount) of \(ConnectionSectionType.allCases.count) sections filled")
    }

    private var inlineTitleEditor: some View {
        CosmoDocumentEditor(
            document: $titleDocument,
            fontSize: 15,
            compact: true,
            placeholder: "Untitled Concept",
            allowSlashCommands: false,
            allowMentions: true,
            allowSelectionMenu: false,
            allowImages: false,
            titleConfiguration: titleStyle.titleConfiguration,
            baseFontWeight: .light,
            scrollsInternally: true,
            onContentHeightChange: { newHeight in
                titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
            },
            onPlainTextChange: { _ in },
            onStructuredDocumentChange: { document, _ in
                titleDocument = document
            },
            onActivate: { isEditingTitle = true },
            onDeactivate: { isEditingTitle = false },
            onCommit: { isEditingTitle = false },
            autoFocus: true
        )
        .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
    }

    private var frameworkTypeLabel: String {
        // Prefer the persisted concept type from focus state when available.
        if block.entityId > 0,
           let state = atom.flatMap({ ConnectionFocusModeState.load(atomUUID: $0.uuid) }) {
            return state.conceptType.displayName.uppercased()
        }
        return "MENTAL MODEL"
    }

    // MARK: - Section previews

    /// Up to four populated sections with their first item — real content,
    /// not abbreviations. Empty connections show the opening prompts instead.
    @ViewBuilder
    private var sectionPreviewList: some View {
        let preview = previewSections
        if preview.isEmpty {
            emptyStatePrompts
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview.prefix(4)) { section in
                    sectionPreviewRow(section)
                }
                if preview.count > 4 {
                    Text("+\(preview.count - 4) more section\(preview.count - 4 == 1 ? "" : "s")")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .padding(.leading, 22)
                }
            }
        }
    }

    private func sectionPreviewRow(_ section: ConnectionSection) -> some View {
        Button {
            openFocusAtStation(section.type)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: section.type.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(section.type.accentColor)
                    .frame(width: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(section.type.displayName)
                            .font(DS.caption)
                            .foregroundStyle(DS.inkWash)
                        Text("\(section.items.count)")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.textMuted)
                    }
                    if let first = section.items.first {
                        Text(first.resolvedPlainText)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Open \(section.type.displayName) in focus mode")
        .accessibilityLabel("\(section.type.displayName), \(section.items.count) items. Opens focus mode.")
    }

    /// Teaches what a Connection is for instead of showing 11 empty cells.
    private var emptyStatePrompts: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach([ConnectionSectionType.goal, .problems, .conceptName], id: \.self) { type in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: type.icon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(type.accentColor.opacity(0.6))
                        .frame(width: 14)
                        .padding(.top, 1)
                    Text(type.promptQuestion)
                        .font(DS.caption2)
                        .italic()
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    /// Distinct sources cited by items across all sections.
    private var citedSourceCount: Int {
        Set(sections.flatMap { $0.items }.compactMap { $0.sourceAtomUUID }).count
    }

    private var crucibleFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 8))
                .foregroundStyle(accentColor.opacity(0.5))
            Text("\(totalItemCount) item\(totalItemCount == 1 ? "" : "s")\(citedSourceCount > 0 ? " · \(citedSourceCount) source\(citedSourceCount == 1 ? "" : "s")" : "")")
                .font(DS.caption2)
                .foregroundStyle(accentColor.opacity(0.6))
            Spacer()
            if let stamp = block.metadata["updated"] ?? block.metadata["created"] {
                Text(formatTimestamp(stamp))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func openFocusAtStation(_ type: ConnectionSectionType) {
        if let atomUUID = atom?.uuid {
            ConnectionFocusDeepLink.stash(atomUUID: atomUUID, section: type)
        }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.connection,
                "id": block.entityId,
                "focusStation": type.rawValue
            ]
        )
    }

    // MARK: - GRDB Observation

    private func startObservingAtom() {
        guard block.entityId > 0 else { return }
        let id = block.entityId
        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("id") == id)
                .fetchOne(db)
        }
        observationCancellable = observation.publisher(in: CosmoDatabase.shared.dbPool)
            .receive(on: DispatchQueue.main)
            .removeDuplicates(by: { prev, next in
                guard let prev, let next else { return prev == nil && next == nil }
                return prev.title == next.title
                    && prev.body == next.body
                    && prev.structured == next.structured
                    && prev.metadata == next.metadata
            })
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { atom in
                    guard let atom else { return }
                    ConsoleLog.verbose("[BLOCK-CONN] 🔔 GRDB observation fired — uuid=\(atom.uuid) isEditingTitle=\(self.isEditingTitle) sectionsModifiedLocally=\(self.sectionsModifiedLocally) dbBodyLen=\(atom.body?.count ?? 0) dbStructuredLen=\(atom.structured?.count ?? 0)", subsystem: .canvas)
                    self.atom = atom
                    let newTitleDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .title,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.title,
                        atomUUID: atom.uuid
                    )
                    if self.isEditingTitle {
                        if newTitleDocument != self.titleDocument {
                            print("[BLOCK-CONN] 🔔 observation DEFERRED title (editing) — uuid=\(atom.uuid)")
                            self.pendingObservedTitleDocument = newTitleDocument
                        }
                    } else {
                        print("[BLOCK-CONN] 🔔 observation APPLYING title — uuid=\(atom.uuid)")
                        self.applyObservedTitleDocument(newTitleDocument)
                    }
                    // Only re-parse sections from DB if user hasn't made local edits,
                    // OR if the DB section count differs from local (focus mode changed them).
                    if !self.sectionsModifiedLocally {
                        print("[BLOCK-CONN] 🔔 observation APPLYING sections from DB — uuid=\(atom.uuid)")
                        self.parseSections(from: atom)
                    } else {
                        // Check if focus mode changed sections — if DB item count differs
                        // from local, accept the update and reset the local-modified flag
                        let localItemCount = self.sections.flatMap(\.items).count
                        let dbItemCount: Int = {
                            guard let json = atom.structured,
                                  let data = ConnectionStructuredData.fromJSON(json) else { return 0 }
                            return data.sections.flatMap(\.items).count
                        }()
                        if dbItemCount != localItemCount {
                            print("[BLOCK-CONN] 🔔 observation APPLYING sections (focus mode changed items: local=\(localItemCount) db=\(dbItemCount)) — uuid=\(atom.uuid)")
                            self.sectionsModifiedLocally = false
                            self.parseSections(from: atom)
                        } else {
                            print("[BLOCK-CONN] 🔔 observation SKIPPED sections (locally modified) — uuid=\(atom.uuid)")
                        }
                    }
                }
            )
    }

    // MARK: - Data Loading

    private func loadInitialData() {
        guard block.entityId > 0 else {
            editableTitle = block.metadata["title"] ?? block.title
            titleDocument = RichDocumentPersistence.loadBlockDocument(
                key: RichDocumentMetadataKeys.titleDocument,
                metadata: block.metadata,
                fallbackPlainText: editableTitle,
                atomUUID: block.id
            )
            editableTitle = RichDocumentPersistence.titlePlainText(from: titleDocument)

            if let json = block.metadata["structured"],
               let data = ConnectionStructuredData.fromJSON(json) {
                sections = data.sections
                    .sorted { $0.type.sortOrder < $1.type.sortOrder }
                    .map { section in
                        var copy = section
                        copy.isExpanded = !section.items.isEmpty
                        return copy
                    }
            } else {
                sections = ConnectionSectionType.allCases
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { type in
                        ConnectionSection(type: type, isExpanded: false)
                    }
            }
            return
        }

        editableTitle = block.title

        // Warm store first — the thinkspace switch batch-fetched every entity
        // atom; the repository round-trip survives only as a fallback.
        if let warm = CanvasAtomWarmStore.shared.atom(id: block.entityId) {
            applyInitialAtom(warm)
            return
        }

        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    applyInitialAtom(loaded)
                }
            }
        }
    }

    /// Apply the initially-loaded entity atom to view state. Shared by the
    /// warm store hit (synchronous, at mount) and the repository fallback.
    private func applyInitialAtom(_ loaded: Atom) {
        atom = loaded
        // Only update title if user hasn't started editing yet —
        // otherwise the async load overwrites what the user is typing
        if !isEditingTitle {
            titleDocument = RichDocumentPersistence.loadAtomDocument(
                field: .title,
                metadata: loaded.metadata,
                fallbackPlainText: loaded.title ?? block.title,
                atomUUID: loaded.uuid
            )
            editableTitle = RichDocumentPersistence.titlePlainText(from: titleDocument)
        }
        parseSections(from: loaded)
    }

    private func parseSections(from atom: Atom) {
        // 1. Try ConnectionFocusModeState from UserDefaults (fastest, most up-to-date)
        if let state = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            print("[BLOCK-CONN] parseSections — USING UserDefaults for uuid=\(atom.uuid) udSections=\(state.sections.count) udLastModified=\(state.lastModified) dbUpdatedAt=\(atom.updatedAt)")
            // Freshness compare: the DB wins when its row is newer than the UD
            // blob. (The old count-based check preferred whichever store had
            // more items, which let a stale blob resurrect deleted items.)
            let atomUpdatedAt = ISO8601.date(from: atom.updatedAt) ?? .distantPast
            if state.lastModified < atomUpdatedAt, let json = atom.structured, let data = ConnectionStructuredData.fromJSON(json) {
                print("[BLOCK-CONN] parseSections — ⚠️ UserDefaults STALE (lastModified=\(state.lastModified) < updatedAt=\(atomUpdatedAt)), falling through to DB")
                sections = data.sections
                    .sorted { $0.type.sortOrder < $1.type.sortOrder }
                    .map { section in
                        var s = section
                        if let existing = sections.first(where: { $0.type == section.type }) {
                            s.isExpanded = existing.isExpanded
                        } else {
                            s.isExpanded = !section.items.isEmpty
                        }
                        return s
                    }
                deduplicateItemsAcrossSections()
                return
            }
            sections = state.sections
                .sorted { $0.type.sortOrder < $1.type.sortOrder }
                .map { section in
                    // Preserve local expansion state
                    var s = section
                    if let existing = sections.first(where: { $0.type == section.type }) {
                        s.isExpanded = existing.isExpanded
                    } else {
                        s.isExpanded = !section.items.isEmpty
                    }
                    return s
                }
            deduplicateItemsAcrossSections()
            return
        }

        // 2. Fall back to atom.structured JSON
        print("[BLOCK-CONN] parseSections — UserDefaults empty/nil for uuid=\(atom.uuid), trying atom.structured (len=\(atom.structured?.count ?? 0))")
        if let json = atom.structured,
           let data = ConnectionStructuredData.fromJSON(json) {
            print("[BLOCK-CONN] parseSections — USING atom.structured for uuid=\(atom.uuid) sections=\(data.sections.count) items=\(data.sections.flatMap(\.items).count)")
            sections = data.sections
                .sorted { $0.type.sortOrder < $1.type.sortOrder }
                .map { section in
                    var s = section
                    if let existing = sections.first(where: { $0.type == section.type }) {
                        s.isExpanded = existing.isExpanded
                    } else {
                        s.isExpanded = !section.items.isEmpty
                    }
                    return s
                }
            deduplicateItemsAcrossSections()
            return
        }

        // 3. Initialize empty sections (collapsed)
        print("[BLOCK-CONN] parseSections — NO data source for uuid=\(atom.uuid), using empty sections")
        if sections.isEmpty {
            sections = ConnectionSectionType.allCases
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { type in
                    ConnectionSection(type: type, isExpanded: false)
                }
        }
    }

    /// Remove TRUE duplicates only — items sharing the same id (e.g. from a
    /// double-applied merge). Never dedupe by text: identical wording in two
    /// sections is intentional authoring, and the old normalized-text dedupe
    /// deleted it at parse time and persisted the deletion on the next save.
    private func deduplicateItemsAcrossSections() {
        var seenIDs: Set<UUID> = []
        for i in sections.indices {
            sections[i].items.removeAll { item in
                if seenIDs.contains(item.id) {
                    return true // same item appearing twice — remove
                }
                seenIDs.insert(item.id)
                return false
            }
        }
    }

    // MARK: - Item Actions

    private func addItem(document: RichDocument, plainText: String, toSectionIndex index: Int) {
        guard !plainText.isEmpty else { return }
        let item = ConnectionItem(content: plainText, document: document, plainText: plainText)
        sections[index].items.append(item)
        sections[index].isExpanded = true
        saveChanges()
    }

    private func deleteItem(id: UUID, fromSectionIndex index: Int) {
        sections[index].items.removeAll { $0.id == id }
        saveChanges()
    }

    private func editItem(id: UUID, document: RichDocument, plainText: String, inSectionIndex index: Int) {
        guard !plainText.isEmpty else { return }
        if let itemIndex = sections[index].items.firstIndex(where: { $0.id == id }) {
            // Use plainText directly — the document may be stale due to CDE's 150ms debounce.
            // applyDocument() would read document.plainText which is behind.
            sections[index].items[itemIndex].document = document
            sections[index].items[itemIndex].plainText = plainText
            sections[index].items[itemIndex].content = plainText
            sections[index].items[itemIndex].updatedAt = Date()
            saveChanges()
        }
    }

    // MARK: - Persistence

    private func saveChanges() {
        print("[BLOCK-CONN] saveChanges() — uuid=\(atom?.uuid ?? "nil") sectionsCount=\(sections.count) totalItems=\(sections.flatMap(\.items).count)")
        sectionsModifiedLocally = true
        let structuredData = ConnectionStructuredData(sections: sections)
        guard let json = structuredData.toJSON() else { print("[BLOCK-CONN] saveChanges() FAILED — JSON serialization failed"); return }
        let flattenedBodyText = flattenedSectionBodyText()
        print("[BLOCK-CONN] saveChanges() — bodyLen=\(flattenedBodyText.count) structuredLen=\(json.count) bodyPreview=\"\(String(flattenedBodyText.prefix(80)))\"")

        persistBlockSnapshot(structuredJSON: json, flattenedBodyText: flattenedBodyText)

        guard let atom = atom else { print("[BLOCK-CONN] saveChanges() SKIPPED DB — no atom loaded"); return }
        let atomUUID = atom.uuid

        // 1. Write to atom.structured — merging the sections key over the
        // existing column so legacy mental-model keys survive (a whole-column
        // write here destroyed them).
        Task {
            print("[BLOCK-CONN] saveChanges() async DB write starting — uuid=\(atomUUID)")
            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    let existing: String? = try Row.fetchOne(
                        db,
                        sql: "SELECT structured FROM atoms WHERE uuid = ?",
                        arguments: [atomUUID]
                    )?["structured"]
                    guard let mergedStructured = Self.mergedSectionsJSON(existing: existing, sectionsJSON: json, atomUUID: atomUUID) else {
                        // Existing column is non-empty but unparseable — refuse a
                        // write that would drop whatever it holds.
                        return
                    }
                    try db.execute(
                        sql: "UPDATE atoms SET structured = ?, body = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                        arguments: [mergedStructured, flattenedBodyText, ISO8601.string(from: Date()), atomUUID]
                    )
                }
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "ConnectionBlockView.saveChanges(\(atomUUID.prefix(8)))",
                    detail: error.localizedDescription
                )
                return
            }
            print("[BLOCK-CONN] saveChanges() async DB write DONE — uuid=\(atomUUID)")
            // Sync: queue for Supabase push
            if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                // skipVersionIncrement: raw SQL already did _local_version + 1
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
            }
        }

        // 2. Also save to UserDefaults so focus mode picks up changes
        var focusState = ConnectionFocusModeState.load(atomUUID: atomUUID)
                         ?? ConnectionFocusModeState(atomUUID: atomUUID)
        focusState.sections = sections
        focusState.lastModified = Date()
        focusState.save()
        print("[BLOCK-CONN] saveChanges() UserDefaults saved — uuid=\(atomUUID)")
    }

    /// Merge a sections-only JSON payload into an existing structured column,
    /// preserving sibling keys (legacy mental-model data). Returns nil — refuse
    /// to write — when the existing column is non-empty but unparseable.
    /// nonisolated: runs inside the database write closure.
    nonisolated static func mergedSectionsJSON(existing: String?, sectionsJSON: String, atomUUID: String) -> String? {
        guard let sectionsData = sectionsJSON.data(using: .utf8),
              let sectionsObj = (try? JSONSerialization.jsonObject(with: sectionsData)) as? [String: Any],
              let sectionsValue = sectionsObj["sections"] else {
            PersistenceHealth.note(
                .writeFailure,
                context: "ConnectionBlockView.mergedSectionsJSON(\(atomUUID.prefix(8)))",
                detail: "sections payload encode failed; keeping existing column"
            )
            return nil
        }
        guard let existing, !existing.isEmpty else { return sectionsJSON }
        guard let existingData = existing.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: existingData)) as? [String: Any] else {
            PersistenceHealth.note(
                .decodeFailure,
                context: "ConnectionBlockView.mergedSectionsJSON(\(atomUUID.prefix(8)))",
                detail: "existing structured unparseable; refusing sections write that would drop its data"
            )
            return nil
        }
        dict["sections"] = sectionsValue
        guard let merged = try? JSONSerialization.data(withJSONObject: dict),
              let mergedStr = String(data: merged, encoding: .utf8) else {
            return nil
        }
        return mergedStr
    }

    // MARK: - Title Editing

    private func commitTitleEdit(document: RichDocument) {
        let newTitle = RichDocumentPersistence.titlePlainText(from: document)
        print("[BLOCK-CONN] commitTitleEdit() — uuid=\(atom?.uuid ?? "nil") newTitle=\"\(String(newTitle.prefix(60)))\"")
        applyObservedTitleDocument(document)
        persistBlockSnapshot(
            structuredJSON: ConnectionStructuredData(sections: sections).toJSON(),
            flattenedBodyText: flattenedSectionBodyText(),
            titleDocumentOverride: document
        )

        guard let atom = atom else { return }
        let atomUUID = atom.uuid
        Task {
            print("[BLOCK-CONN] commitTitleEdit() async DB write — uuid=\(atomUUID)")
            try? await CosmoDatabase.shared.asyncWrite { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]) {
                    existingMetadata = row["metadata"]
                }
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: document
                )
                try db.execute(
                    sql: "UPDATE atoms SET title = ?, metadata = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                    arguments: [fields.title ?? newTitle, fields.metadata, ISO8601.string(from: Date()), atomUUID]
                )
            }
            // Sync: queue for Supabase push
            if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                // skipVersionIncrement: raw SQL already did _local_version + 1
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
            }
        }
    }

    private func applyObservedTitleDocument(_ document: RichDocument) {
        titleDocument = document
        editableTitle = RichDocumentPersistence.titlePlainText(from: document)
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        guard block.entityId <= 0 else {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.connection,
                    "id": block.entityId
                ]
            )
            return
        }

        let structuredData = ConnectionStructuredData(sections: sections)
        guard let json = structuredData.toJSON() else { return }
        let flattenedBodyText = flattenedSectionBodyText()

        Task {
            do {
                var newAtom = Atom.new(
                    type: .connection,
                    title: RichDocumentPersistence.nilIfEmpty(editableTitle),
                    body: flattenedBodyText
                )
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: newAtom.metadata,
                    titleDocument: titleDocument
                )
                newAtom.title = fields.title
                newAtom.body = flattenedBodyText
                newAtom.metadata = fields.metadata
                newAtom.structured = json

                let atomId = try await CosmoDatabase.shared.asyncWrite { db -> Int64 in
                    try newAtom.insert(db)
                    return db.lastInsertedRowID
                }

                try await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET entity_id = ?, entity_uuid = ?
                        WHERE id = ?
                        """,
                        arguments: [atomId, newAtom.uuid, block.id]
                    )
                }

                await MainActor.run {
                    atom = newAtom
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: [
                            "type": EntityType.connection,
                            "id": atomId
                        ]
                    )
                }
            } catch {
                print("ConnectionBlockView: Failed to create backing atom: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601.date(from: timestamp) {
            return CosmoDateFormatters.relative.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }

    private func flattenedSectionBodyText() -> String {
        sections
            .filter { !$0.items.isEmpty }
            .map { section in
                "\(section.type.displayName)\n" + section.items.map { "• \($0.resolvedPlainText)" }.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    private func persistBlockSnapshot(
        structuredJSON: String?,
        flattenedBodyText: String,
        titleDocumentOverride: RichDocument? = nil
    ) {
        let resolvedTitleDocument = titleDocumentOverride ?? titleDocument
        let resolvedTitle = RichDocumentPersistence.titlePlainText(from: resolvedTitleDocument)

        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": resolvedTitle,
                "content": flattenedBodyText
            ]
        )

        var updatedMetadata = RichDocumentPersistence.writeBlockDocument(
            resolvedTitleDocument,
            key: RichDocumentMetadataKeys.titleDocument,
            metadata: block.metadata
        )
        updatedMetadata["title"] = resolvedTitle
        updatedMetadata["content"] = flattenedBodyText
        if let structuredJSON {
            updatedMetadata["structured"] = structuredJSON
        }

        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": updatedMetadata
            ]
        )
    }
}


// MARK: - Preview

#if DEBUG
struct ConnectionBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.canvas
                .ignoresSafeArea()

            ConnectionBlockView(
                block: CanvasBlock(
                    position: CGPoint(x: 200, y: 200),
                    size: CGSize(width: 340, height: 400),
                    entityType: .connection,
                    entityId: 1,
                    entityUuid: "preview",
                    title: "Second Brain Architecture"
                )
            )
        }
        .frame(width: 500, height: 500)
    }
}
#endif
