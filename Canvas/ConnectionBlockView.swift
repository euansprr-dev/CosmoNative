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

    // MARK: - Connection Content

    private var connectionContent: some View {
        VStack(spacing: 0) {
            // Compact header
            compactHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Sections — flow naturally so the block grows to fit content
            VStack(spacing: 4) {
                ForEach(Array(sections.indices), id: \.self) { index in
                    CompactSectionRow(
                        section: $sections[index],
                        onAddItem: { document, plainText in
                            addItem(document: document, plainText: plainText, toSectionIndex: index)
                        },
                        onDeleteItem: { itemId in
                            deleteItem(id: itemId, fromSectionIndex: index)
                        },
                        onEditItem: { itemId, document, plainText in
                            editItem(id: itemId, document: document, plainText: plainText, inSectionIndex: index)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Footer
            footerBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Entity identity strip
            Capsule()
                .fill(accentColor.opacity(0.35))
                .frame(height: 3)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

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

            Text("\(totalItemCount) items \u{00B7} \(populatedSectionCount)/8 sections")
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
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { atom in
                    guard let atom else { return }
                    self.atom = atom
                    let newTitleDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .title,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.title
                    )
                    if self.isEditingTitle {
                        if newTitleDocument != self.titleDocument {
                            self.pendingObservedTitleDocument = newTitleDocument
                        }
                    } else {
                        self.applyObservedTitleDocument(newTitleDocument)
                    }
                    // Only re-parse sections from DB if user hasn't made local edits.
                    // After local edits, saveChanges() is the authority — observation echoes
                    // from auto-save would overwrite in-progress edits.
                    if !self.sectionsModifiedLocally {
                        self.parseSections(from: atom)
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
        if let json = atom.structured,
           let data = ConnectionStructuredData.fromJSON(json) {
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
        sectionsModifiedLocally = true
        let structuredData = ConnectionStructuredData(sections: sections)
        guard let json = structuredData.toJSON() else { return }
        let flattenedBodyText = flattenedSectionBodyText()

        persistBlockSnapshot(structuredJSON: json, flattenedBodyText: flattenedBodyText)

        guard let atom = atom else { return }
        let atomUUID = atom.uuid

        // 1. Write to atom.structured
        Task {
            try? await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET structured = ?, body = ?, updated_at = ?, _local_version = _local_version + 1, _local_pending = 1 WHERE uuid = ?",
                    arguments: [json, flattenedBodyText, ISO8601DateFormatter().string(from: Date()), atomUUID]
                )
            }
            // Sync: queue for Supabase push
            if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
            }
        }

        // 2. Also save to UserDefaults so focus mode picks up changes
        var focusState = ConnectionFocusModeState.load(atomUUID: atomUUID)
                         ?? ConnectionFocusModeState(atomUUID: atomUUID)
        focusState.sections = sections
        focusState.lastModified = Date()
        focusState.save()
    }

    // MARK: - Title Editing

    private func commitTitleEdit(document: RichDocument) {
        let newTitle = RichDocumentPersistence.titlePlainText(from: document)
        applyObservedTitleDocument(document)
        persistBlockSnapshot(
            structuredJSON: ConnectionStructuredData(sections: sections).toJSON(),
            flattenedBodyText: flattenedSectionBodyText(),
            titleDocumentOverride: document
        )

        guard let atom = atom else { return }
        let atomUUID = atom.uuid
        Task {
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
                await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom)
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
                                onPlainTextChange: { plainText in
                                    newItemText = plainText
                                },
                                onDocumentChange: { _, plainText in
                                    newItemText = plainText
                                }
                            )
                            .frame(minHeight: 24)

                            Button {
                                cancelAddItem()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DS.textMuted)
                            }
                            .buttonStyle(.plain)

                            Button {
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
        if !text.isEmpty {
            onAddItem(newItemDocument, text)
        }
        newItemText = ""
        newItemDocument = .empty
        isAddingItem = false
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
