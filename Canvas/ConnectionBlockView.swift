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
    @State private var isExpanded = false
    @State private var observationCancellable: AnyCancellable?
    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Purple accent for connections
    private let accentColor = CosmoColors.blockConnection

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
            title: block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            connectionContent
        }
        .onAppear {
            loadInitialData()
            startObservingAtom()
        }
        .onDisappear {
            observationCancellable?.cancel()
        }
        .onChange(of: block.entityId) { _, newId in
            if newId > 0 {
                observationCancellable?.cancel()
                startObservingAtom()
            }
        }
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
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Scrollable sections
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(Array(sections.indices), id: \.self) { index in
                        CompactSectionRow(
                            section: $sections[index],
                            onAddItem: { content in
                                addItem(content: content, toSectionIndex: index)
                            },
                            onDeleteItem: { itemId in
                                deleteItem(id: itemId, fromSectionIndex: index)
                            },
                            onEditItem: { itemId, newContent in
                                editItem(id: itemId, newContent: newContent, inSectionIndex: index)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            // Footer
            footerBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(spacing: 10) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "link.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title.isEmpty ? "Untitled Connection" : block.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(totalItemCount) items \u{00B7} \(populatedSectionCount)/8 sections")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.35))
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if let created = block.metadata["created"] ?? block.metadata["updated"] {
                Text(formatTimestamp(created))
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            Spacer()
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
                    self.parseSections(from: atom)
                }
            )
    }

    // MARK: - Data Loading

    private func loadInitialData() {
        guard block.entityId > 0 else {
            // No backing atom yet — initialize empty sections
            sections = ConnectionSectionType.allCases
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { type in
                    ConnectionSection(type: type, isExpanded: false)
                }
            return
        }

        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    atom = loaded
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

    // MARK: - Item Actions

    private func addItem(content: String, toSectionIndex index: Int) {
        guard !content.isEmpty else { return }
        let item = ConnectionItem(content: content)
        sections[index].items.append(item)
        sections[index].isExpanded = true
        saveChanges()
    }

    private func deleteItem(id: UUID, fromSectionIndex index: Int) {
        sections[index].items.removeAll { $0.id == id }
        saveChanges()
    }

    private func editItem(id: UUID, newContent: String, inSectionIndex index: Int) {
        guard !newContent.isEmpty else { return }
        if let itemIndex = sections[index].items.firstIndex(where: { $0.id == id }) {
            sections[index].items[itemIndex].content = newContent
            sections[index].items[itemIndex].updatedAt = Date()
            saveChanges()
        }
    }

    // MARK: - Persistence

    private func saveChanges() {
        guard let atom = atom else { return }
        let atomUUID = atom.uuid

        // 1. Write to atom.structured
        let structuredData = ConnectionStructuredData(sections: sections)
        guard let json = structuredData.toJSON() else { return }
        Task {
            try? await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: "UPDATE atoms SET structured = ?, updated_at = ?, _local_version = _local_version + 1 WHERE uuid = ?",
                    arguments: [json, ISO8601DateFormatter().string(from: Date()), atomUUID]
                )
            }
        }

        // 2. Also save to UserDefaults so focus mode picks up changes
        var focusState = ConnectionFocusModeState.load(atomUUID: atomUUID)
                         ?? ConnectionFocusModeState(atomUUID: atomUUID)
        focusState.sections = sections
        focusState.lastModified = Date()
        focusState.save()
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        if block.entityId > 0 {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.connection,
                    "id": block.entityId
                ]
            )
        } else {
            // Create backing atom first
            Task {
                let newAtom = Atom.new(
                    type: .connection,
                    title: block.title.isEmpty ? "New Connection" : block.title,
                    body: ""
                )
                guard let created = try? await AtomRepository.shared.create(newAtom) else { return }
                let atomId = created.id ?? Int64(-1)

                try? await CosmoDatabase.shared.asyncWrite { db in
                    try db.execute(
                        sql: "UPDATE canvas_blocks SET entity_id = ?, entity_uuid = ? WHERE id = ?",
                        arguments: [atomId, created.uuid, block.id]
                    )
                }

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                        object: nil
                    )
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: [
                            "type": EntityType.connection,
                            "id": atomId
                        ]
                    )
                }
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
}

// MARK: - Compact Section Row

private struct CompactSectionRow: View {
    @Binding var section: ConnectionSection
    let onAddItem: (String) -> Void
    let onDeleteItem: (UUID) -> Void
    let onEditItem: (UUID, String) -> Void

    @State private var isAddingItem = false
    @State private var newItemText = ""
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    // Count badge
                    if !section.items.isEmpty {
                        Text("\(section.items.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(section.type.accentColor)
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
                        .foregroundColor(Color.white.opacity(0.3))
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
                            onEdit: { newContent in
                                onEditItem(item.id, newContent)
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
                                .foregroundColor(section.type.accentColor.opacity(0.5))
                                .frame(width: 12)

                            TextField("Add item...", text: $newItemText)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .textFieldStyle(.plain)
                                .focused($isAddFieldFocused)
                                .onSubmit {
                                    commitAddItem()
                                }
                                .onKeyPress(.escape) {
                                    cancelAddItem()
                                    return .handled
                                }
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
                            .foregroundColor(section.type.accentColor.opacity(0.5))
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
            RoundedRectangle(cornerRadius: 6)
                .fill(section.isExpanded ? Color.white.opacity(0.03) : Color.clear)
        )
    }

    private func commitAddItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onAddItem(text)
        }
        newItemText = ""
        isAddingItem = false
    }

    private func cancelAddItem() {
        newItemText = ""
        isAddingItem = false
    }
}

// MARK: - Compact Item Row

private struct CompactItemRow: View {
    let item: ConnectionItem
    let accentColor: Color
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false
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
                TextField("", text: $editText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        commitEdit()
                    }
                    .onKeyPress(.escape) {
                        cancelEdit()
                        return .handled
                    }
            } else {
                Text(item.content)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(2)
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
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(Color.red.opacity(0.5))
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
        editText = item.content
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
    }

    private func commitEdit() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onEdit(text)
        }
        isEditing = false
        editText = ""
    }

    private func cancelEdit() {
        isEditing = false
        editText = ""
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
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
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 500, height: 500)
    }
}
#endif
