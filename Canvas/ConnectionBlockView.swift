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
        return trimmed.isEmpty ? "Untitled Connection" : trimmed
    }

    // MARK: - Connection Content (V2 "The Crucible" preview)

    /// Ordering for the canvas block's compact station grid.
    private static let stationGridOrder: [ConnectionSectionType] = [
        .goal, .problems, .claims, .evidence,
        .benefits, .examples, .beliefsObjections, .process,
        .openQuestions, .conceptName, .references
    ]

    private var connectionContent: some View {
        VStack(spacing: 0) {
            crucibleMasthead
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)

            stationGrid
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            crucibleFooter
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Masthead (block)

    private var crucibleMasthead: some View {
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
            MaturityCrystalInline(filledCount: populatedSectionCount)
        }
    }

    private var inlineTitleEditor: some View {
        CosmoDocumentEditor(
            document: $titleDocument,
            fontSize: 15,
            compact: true,
            placeholder: "Untitled Connection",
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

    // MARK: - Station Grid

    private var stationGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.stationGridOrder, id: \.self) { type in
                stationCell(for: type)
            }
        }
    }

    private func stationCell(for type: ConnectionSectionType) -> some View {
        let section = sections.first(where: { $0.type == type })
        let isPopulated = (section?.items.isEmpty == false)
        return Button {
            openFocusAtStation(type)
        } label: {
            VStack(spacing: 3) {
                Text(isPopulated ? "◆" : "·")
                    .font(.system(size: isPopulated ? 12 : 14, weight: .regular, design: .serif))
                    .foregroundStyle(isPopulated ? type.accentColor.opacity(0.85) : DS.inkFaded)
                Text(type.abbreviation)
                    .font(DS.smallCaps)
                    .tracking(1.0)
                    .foregroundStyle(isPopulated ? DS.inkWash.opacity(0.8) : DS.inkFaded)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(type.accentColor.opacity(isPopulated ? 0.05 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DS.sepiaSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName), \(isPopulated ? "\(section?.items.count ?? 0) items" : "empty"). Tap to open focus mode.")
    }

    // MARK: - Footer

    private var crucibleFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 8))
                .foregroundStyle(accentColor.opacity(0.5))
            Text("\(totalItemCount) insights")
                .font(DS.caption2)
                .foregroundStyle(accentColor.opacity(0.6))
            Spacer()
            Text("drag here")
                .font(DS.caption2)
                .italic()
                .foregroundStyle(DS.textMuted)
        }
    }

    private func openFocusAtStation(_ type: ConnectionSectionType) {
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

    // MARK: - Compact Header

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Gilt corner ornament lives on the wrapper; leave top breathing room here.
            Color.clear.frame(height: 6)

            if isEditingTitle {
                CosmoDocumentEditor(
                    document: $titleDocument,
                    fontSize: titleFontSize,
                    compact: titleStyle.compact,
                    placeholder: "Untitled Connection",
                    allowSlashCommands: false,
                    allowMentions: true,
                    allowSelectionMenu: false,
                    allowImages: false,
                    titleConfiguration: titleStyle.titleConfiguration,
                    baseFontWeight: titleStyle.baseFontWeight,
                    scrollsInternally: true,
                    onContentHeightChange: { newHeight in
                        titleEditorHeight = min(titleEditingMaxHeight, max(titleMinHeight, newHeight))
                    },
                    onPlainTextChange: { _ in
                        // Don't update editableTitle during editing — it changes displayTitle
                        // which triggers a CosmoBlockWrapper re-render that can reset the NSTextView.
                        // editableTitle is set from commitTitleEdit when editing ends.
                    },
                    onStructuredDocumentChange: { document, _ in
                        titleDocument = document
                    },
                    onActivate: { isEditingTitle = true },
                    onDeactivate: { isEditingTitle = false },
                    onCommit: { isEditingTitle = false },
                    autoFocus: true
                )
                .frame(height: min(titleEditingMaxHeight, max(titleMinHeight, titleEditorHeight)))
            } else {
                Text(displayTitle)
                    .font(titleStyle.swiftUIFont)
                    .foregroundStyle(editableTitle.isEmpty ? DS.textMuted : DS.text)
                    .lineLimit(titleStyle.previewLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(titleStyle.swiftUITextAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        titleDocumentAtEditStart = titleDocument
                        isEditingTitle = true
                    }
            }

            Text("\(totalItemCount) items \u{00B7} \(populatedSectionCount)/\(ConnectionSectionType.allCases.count) sections")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.system(size: 9))
                .foregroundStyle(accentColor.opacity(0.5))
            Text("\(totalItemCount) items")
                .font(DS.caption2)
                .foregroundStyle(accentColor.opacity(0.6))

            Spacer()

            if let created = block.metadata["created"] ?? block.metadata["updated"] {
                Text(formatTimestamp(created))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
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
        observationCancellable = observation.publisher(in: CosmoDatabase.shared.dbQueue)
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
                    print("[BLOCK-CONN] 🔔 GRDB observation fired — uuid=\(atom.uuid) isEditingTitle=\(self.isEditingTitle) sectionsModifiedLocally=\(self.sectionsModifiedLocally) dbBodyLen=\(atom.body?.count ?? 0) dbStructuredLen=\(atom.structured?.count ?? 0)")
                    self.atom = atom
                    let newTitleDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .title,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.title
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
                fallbackPlainText: editableTitle
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

        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    atom = loaded
                    // Only update title if user hasn't started editing yet —
                    // otherwise the async load overwrites what the user is typing
                    if !isEditingTitle {
                        titleDocument = RichDocumentPersistence.loadAtomDocument(
                            field: .title,
                            metadata: loaded.metadata,
                            fallbackPlainText: loaded.title ?? block.title
                        )
                        editableTitle = RichDocumentPersistence.titlePlainText(from: titleDocument)
                    }
                    parseSections(from: loaded)
                }
            }
        }
    }

    private func parseSections(from atom: Atom) {
        // 1. Try ConnectionFocusModeState from UserDefaults (fastest, most up-to-date)
        if let state = ConnectionFocusModeState.load(atomUUID: atom.uuid) {
            let udItems = state.sections.flatMap(\.items).count
            let dbItems: Int = {
                guard let json = atom.structured, let data = ConnectionStructuredData.fromJSON(json) else { return 0 }
                return data.sections.flatMap(\.items).count
            }()
            print("[BLOCK-CONN] parseSections — USING UserDefaults for uuid=\(atom.uuid) udSections=\(state.sections.count) udItems=\(udItems) dbStructuredLen=\(atom.structured?.count ?? 0) dbItems=\(dbItems)")
            // If UserDefaults has FEWER items than DB, prefer DB (UserDefaults may be stale)
            if udItems < dbItems, let json = atom.structured, let data = ConnectionStructuredData.fromJSON(json) {
                print("[BLOCK-CONN] parseSections — ⚠️ UserDefaults STALE (udItems=\(udItems) < dbItems=\(dbItems)), falling through to DB")
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

    /// Remove duplicate items that appear across multiple sections (keeps first occurrence).
    private func deduplicateItemsAcrossSections() {
        var seenContent: Set<String> = []
        for i in sections.indices {
            sections[i].items.removeAll { item in
                let key = item.resolvedPlainText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { return false }
                if seenContent.contains(key) {
                    return true // duplicate — remove
                }
                seenContent.insert(key)
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

        // 1. Write to atom.structured
        Task {
            print("[BLOCK-CONN] saveChanges() async DB write starting — uuid=\(atomUUID)")
            try? await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET structured = ?, body = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                    arguments: [json, flattenedBodyText, ISO8601DateFormatter().string(from: Date()), atomUUID]
                )
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
                    arguments: [fields.title ?? newTitle, fields.metadata, ISO8601DateFormatter().string(from: Date()), atomUUID]
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
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
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

// MARK: - Compact Section Row

private struct CompactSectionRow: View {
    @Binding var section: ConnectionSection
    let onAddItem: (RichDocument, String) -> Void
    let onDeleteItem: (UUID) -> Void
    let onEditItem: (UUID, RichDocument, String) -> Void

    @State private var isAddingItem = false
    @State private var newItemText = ""
    @State private var newItemDocument: RichDocument = .empty
    @State private var addItemEditorHeight: CGFloat = 22
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (collapsible)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    section.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // Colored dot
                    Circle()
                        .fill(section.type.accentColor)
                        .frame(width: 6, height: 6)

                    // Section name
                    Text(section.type.displayName)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.text)

                    // Count badge
                    if !section.items.isEmpty {
                        Text("\(section.items.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(section.type.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(section.type.accentColor.opacity(0.15))
                            )
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .rotationEffect(.degrees(section.isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if section.isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    // Items
                    ForEach(section.items) { item in
                        CompactItemRow(
                            item: item,
                            accentColor: section.type.accentColor,
                            onEdit: { document, plainText in
                                onEditItem(item.id, document, plainText)
                            },
                            onDelete: {
                                onDeleteItem(item.id)
                            }
                        )
                    }

                    // Add item row
                    if isAddingItem {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 8))
                                .foregroundStyle(section.type.accentColor.opacity(0.5))
                                .frame(width: 12)

                            CosmoDocumentEditor(
                                document: $newItemDocument,
                                fontSize: 12,
                                compact: true,
                                placeholder: "Add item...",
                                allowSlashCommands: false,
                                allowMentions: true,
                                allowSelectionMenu: false,
                                allowImages: false,
                                onContentHeightChange: { height in
                                    addItemEditorHeight = height
                                },
                                onPlainTextChange: { plainText in
                                    print("[CONN-SECTION] onPlainTextChange — len=\(plainText.count) preview=\"\(String(plainText.prefix(40)))\"")
                                    newItemText = plainText
                                },
                                onDocumentChange: { _, plainText in
                                    print("[CONN-SECTION] onDocumentChange — len=\(plainText.count) preview=\"\(String(plainText.prefix(40)))\" newItemTextBefore=\(newItemText.count)")
                                    newItemText = plainText
                                },
                                onCommit: {
                                    print("[CONN-SECTION] onCommit — newItemText=\"\(newItemText)\" newItemDocPlain=\"\(newItemDocument.plainText)\"")
                                    commitAddItem()
                                }
                            )
                            .frame(height: max(22, addItemEditorHeight))

                            Button {
                                cancelAddItem()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DS.textMuted)
                            }
                            .buttonStyle(.plain)

                            Button {
                                print("[CONN-SECTION] checkmark button tapped — newItemText=\"\(newItemText)\"")
                                commitAddItem()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(section.type.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            isAddingItem = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isAddFieldFocused = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8))
                                Text("Add")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(section.type.accentColor.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.radiusXSmall + 2)
                .fill(sectionBackground)
        )
    }

    private var sectionBackground: Color {
        if section.items.isEmpty {
            return section.isExpanded ? DS.surfaceElevated : Color.clear
        }
        return section.type.accentColor.opacity(section.isExpanded ? 0.04 : 0.02)
    }

    private func commitAddItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        let docText = newItemDocument.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[CONN-SECTION] commitAddItem — newItemText=\"\(text)\" (\(text.count) chars) docPlainText=\"\(docText)\" (\(docText.count) chars)")
        if !text.isEmpty {
            onAddItem(newItemDocument, text)
        }
        // Clear and keep input open for the next item
        newItemText = ""
        newItemDocument = .empty
        addItemEditorHeight = 22
    }

    private func cancelAddItem() {
        newItemText = ""
        newItemDocument = .empty
        isAddingItem = false
    }
}

// MARK: - Compact Item Row

private struct CompactItemRow: View {
    let item: ConnectionItem
    let accentColor: Color
    let onEdit: (RichDocument, String) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editDocument: RichDocument = .empty
    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Bullet
            Circle()
                .fill(accentColor.opacity(0.4))
                .frame(width: 4, height: 4)
                .frame(width: 12)

            if isEditing {
                CosmoDocumentEditor(
                    document: $editDocument,
                    fontSize: 12,
                    compact: true,
                    placeholder: "",
                    allowSlashCommands: false,
                    allowMentions: true,
                    allowSelectionMenu: false,
                    allowImages: false,
                    onPlainTextChange: { plainText in
                        editText = plainText
                    },
                    onDocumentChange: { _, plainText in
                        editText = plainText
                    }
                )
                .frame(minHeight: 22)

                HStack(spacing: 4) {
                    Button {
                        cancelEdit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)

                    Button {
                        commitEdit()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            } else {
                CosmoDocumentRenderer(document: item.resolvedDocument, fontSize: 12, lineLimit: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Hover actions
            if isHovered && !isEditing {
                HStack(spacing: 4) {
                    Button {
                        startEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.red.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func startEdit() {
        editDocument = item.resolvedDocument
        editText = item.resolvedPlainText
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
    }

    private func commitEdit() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onEdit(editDocument, text)
        }
        isEditing = false
        editText = ""
        editDocument = .empty
    }

    private func cancelEdit() {
        isEditing = false
        editText = ""
        editDocument = .empty
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
