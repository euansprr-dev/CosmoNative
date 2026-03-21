import SwiftUI

struct CanvasSelectionInspector: View {
    let block: CanvasBlock
    let currentThinkspaceId: String?
    let onClose: () -> Void

    // Action callbacks
    var onFocusMode: (() -> Void)?
    var onOpenAsPane: (() -> Void)?
    var onAskCosmo: (() -> Void)?
    var onConnectTo: (() -> Void)?
    var onAIAssist: (() -> Void)?
    var onSave: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var atom: Atom?
    @State private var project: Atom?
    @State private var provenanceThinkspaces: [Thinkspace] = []
    @State private var outlinedAtoms: [Atom] = []
    @State private var backlinks: [Atom] = []
    @State private var addReferenceQuery = ""
    @State private var addReferenceCandidates: [Atom] = []
    @State private var isSaving = false
    @State private var hoveredAction: String?
    @State private var hoveredColor: StickyNoteColor?

    private let repository = AtomRepository.shared
    private let inspectorWidth: CGFloat = 320

    private var isStickyNote: Bool { block.entityType == .stickyNote }

    var body: some View {
        Group {
            if isStickyNote {
                VStack(alignment: .leading, spacing: 20) {
                    stickyNoteHeader
                    stickyColorPalette
                    stickyActionsGrid
                }
                .padding(18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if let atom {
                            header(atom)
                            actionsGrid(atom)
                            sectionDivider
                            provenanceSection
                            sectionDivider
                            outlineSection(atom)
                            sectionDivider
                            backlinksSection
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 600)
            }
        }
        .frame(width: inspectorWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DS.surfaceElevated.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.borderActive, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        .task(id: block.entityUuid) {
            guard !isStickyNote else { return }
            await loadInspectorData()
        }
        .task(id: addReferenceQuery) {
            guard !isStickyNote else { return }
            await loadReferenceCandidates()
        }
    }

    @ViewBuilder
    private func header(_ atom: Atom) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color(for: atom.type).opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: atom.type.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(color(for: atom.type))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(atom.title ?? block.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        tag(atom.type.displayName, tint: color(for: atom.type))

                        if atom.outlineReferenceCount > 0 {
                            tag("\(atom.outlineReferenceCount) refs", tint: DS.accent)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button("Close", systemImage: "xmark", action: onClose)
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let preview = atom.body?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Sticky Note Inspector

    @ViewBuilder
    private var stickyNoteHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(currentStickyColor.paper)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(currentStickyColor.selectedBorder)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sticky Note")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.text)

                    tag("Sticky Note", tint: DS.entityStickyNote)
                }

                Spacer(minLength: 0)

                Button("Close", systemImage: "xmark", action: onClose)
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let content = block.metadata["content"],
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
            }
        }
    }

    private var currentStickyColor: StickyNoteColor {
        if let key = block.metadata["stickyColor"],
           let color = StickyNoteColor(rawValue: key) {
            return color
        }
        return .yellow
    }

    @ViewBuilder
    private var stickyColorPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                Text("Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }

            HStack(spacing: 12) {
                ForEach(StickyNoteColor.allCases) { color in
                    stickyColorSwatch(color)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func stickyColorSwatch(_ color: StickyNoteColor) -> some View {
        let isActive = color == currentStickyColor
        let isHover = hoveredColor == color

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.changeStickyColor,
                object: nil,
                userInfo: [
                    "blockId": block.id,
                    "color": color.rawValue
                ]
            )
        } label: {
            Circle()
                .fill(color.paper)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(color.selectedBorder, lineWidth: isActive ? 2.5 : (isHover ? 1.5 : 0))
                )
                .overlay {
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color.selectedBorder)
                    }
                }
                .scaleEffect(isHover ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredColor = hovering ? color : nil
            }
        }
    }

    private var stickyActions: [InspectorAction] {
        var actions: [InspectorAction] = []
        if let onDuplicate {
            actions.append(InspectorAction(id: "duplicate", icon: "plus.square.on.square", label: "Duplicate", tint: DS.text, handler: onDuplicate))
        }
        if let onDelete {
            actions.append(InspectorAction(id: "delete", icon: "trash", label: "Delete", tint: DS.red, handler: onDelete))
        }
        return actions
    }

    @ViewBuilder
    private var stickyActionsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(stickyActions, id: \.id) { action in
                actionPill(action)
            }
        }
    }

    // MARK: - Standard Inspector

    @ViewBuilder
    private func actionsGrid(_ atom: Atom) -> some View {
        let actions = inspectorActions(for: atom)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(actions, id: \.id) { action in
                actionPill(action)
            }
        }
    }

    private struct InspectorAction {
        let id: String
        let icon: String
        let label: String
        let tint: Color
        let handler: () -> Void
    }

    private func inspectorActions(for atom: Atom) -> [InspectorAction] {
        var actions: [InspectorAction] = []

        let supportsFocus: [EntityType] = [.idea, .content, .research, .connection, .cosmoAI, .note]
        if supportsFocus.contains(block.entityType), let onFocusMode {
            actions.append(InspectorAction(id: "focus", icon: "arrow.up.left.and.arrow.down.right", label: "Focus", tint: DS.text, handler: onFocusMode))
        }

        let supportsPane: [EntityType] = [.idea, .content, .research, .connection, .cosmoAI, .note]
        if supportsPane.contains(block.entityType), let onOpenAsPane {
            actions.append(InspectorAction(id: "pane", icon: "rectangle.split.2x1", label: "Pane", tint: DS.accent, handler: onOpenAsPane))
        }

        if block.entityType != .cosmoAI, let onAskCosmo {
            actions.append(InspectorAction(id: "askCosmo", icon: "sparkle", label: "Cosmo", tint: DS.accent, handler: onAskCosmo))
        }

        if let onConnectTo {
            actions.append(InspectorAction(id: "connect", icon: "link", label: "Connect", tint: DS.accent, handler: onConnectTo))
        }

        if let onAIAssist {
            actions.append(InspectorAction(id: "aiAssist", icon: "sparkles", label: "AI Assist", tint: DS.accent, handler: onAIAssist))
        }

        if let onSave {
            actions.append(InspectorAction(id: "save", icon: "bookmark.fill", label: "Save", tint: DS.text, handler: onSave))
        }

        if let onDuplicate {
            actions.append(InspectorAction(id: "duplicate", icon: "plus.square.on.square", label: "Duplicate", tint: DS.text, handler: onDuplicate))
        }

        if let onDelete {
            actions.append(InspectorAction(id: "delete", icon: "trash", label: "Delete", tint: DS.red, handler: onDelete))
        }

        return actions
    }

    @ViewBuilder
    private func actionPill(_ action: InspectorAction) -> some View {
        let isDelete = action.id == "delete"
        Button {
            action.handler()
            onClose()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isDelete
                    ? DS.red
                    : (hoveredAction == action.id ? DS.text : DS.textSecondary)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoveredAction == action.id ? DS.surfaceHover : DS.bg)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAction = hovering ? action.id : nil
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredAction)
    }

    @ViewBuilder
    private var provenanceSection: some View {
        inspectorSection("Context", systemImage: "tray.full") {
            VStack(alignment: .leading, spacing: 8) {
                if let project {
                    provenanceRow(
                        icon: "folder.fill",
                        tint: project.projectMetadata?.color.map { Color(hex: $0) } ?? DS.accent,
                        title: project.title ?? "Project",
                        subtitle: "Project"
                    )
                }

                if provenanceThinkspaces.isEmpty {
                    Text("No thinkspace provenance yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                } else {
                    ForEach(provenanceThinkspaces, id: \.id) { thinkspace in
                        provenanceRow(
                            icon: "rectangle.3.group",
                            tint: thinkspace.id == currentThinkspaceId ? DS.accent : DS.textSecondary,
                            title: thinkspace.name,
                            subtitle: thinkspace.id == currentThinkspaceId ? "Current thinkspace" : "Thinkspace"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outlineSection(_ atom: Atom) -> some View {
        inspectorSection("Reference Outline", systemImage: "list.bullet.indent") {
            VStack(alignment: .leading, spacing: 10) {
                if atom.outlineReferences.isEmpty {
                    Text("No outline references yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                } else {
                    ForEach(Array(zip(atom.outlineReferences.indices, atom.outlineReferences)), id: \.1.id) { index, reference in
                        outlineReferenceRow(index: index, reference: reference)
                    }
                }

                Divider().background(DS.borderSubtle)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Add reference...", text: $addReferenceQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if addReferenceQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        if addReferenceCandidates.isEmpty {
                            Text("No matching atoms")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.textMuted)
                        } else {
                            ForEach(addReferenceCandidates.prefix(5), id: \.uuid) { candidate in
                                addReferenceCandidateRow(candidate)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backlinksSection: some View {
        inspectorSection("Referenced By", systemImage: "arrow.uturn.backward.circle") {
            if backlinks.isEmpty {
                Text("No backlinks yet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(backlinks.prefix(6), id: \.uuid) { backlink in
                        backlinkRow(backlink)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outlineReferenceRow(index: Int, reference: OutlineReferenceItem) -> some View {
        let outlinedAtom = outlinedAtoms.first { $0.uuid == reference.atomUUID }
        Button {
            if let outlinedAtom {
                openInFocusMode(outlinedAtom)
            }
        } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(outlinedAtom?.title ?? reference.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    if let outlinedAtom {
                        Text(outlinedAtom.type.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textMuted)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button("Remove reference", systemImage: "minus.circle.fill") {
                removeReference(reference)
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .font(.system(size: 12))
            .foregroundStyle(DS.red)
            .padding(.trailing, 10)
        }
    }

    @ViewBuilder
    private func addReferenceCandidateRow(_ candidate: Atom) -> some View {
        Button {
            addReference(candidate)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: candidate.type.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(color(for: candidate.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title ?? "Untitled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(candidate.type.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func backlinkRow(_ backlink: Atom) -> some View {
        Button {
            openInFocusMode(backlink)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: backlink.type.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(color(for: backlink.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(backlink.title ?? "Untitled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(backlink.type.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }

            content()
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private func provenanceRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var preferredThinkspaceID: String? {
        if let currentThinkspaceId,
           provenanceThinkspaces.contains(where: { $0.id == currentThinkspaceId }) {
            return currentThinkspaceId
        }
        return provenanceThinkspaces.first?.id
    }

    private func loadInspectorData() async {
        guard !block.entityUuid.isEmpty else { return }

        let fetchedAtom = try? await repository.fetch(uuid: block.entityUuid)
        let fetchedThinkspaceIDs = (try? await repository.fetchThinkspaceMembership(for: block.entityUuid)) ?? []
        let fetchedBacklinks = (try? await repository.fetchOutlineBacklinks(to: block.entityUuid)) ?? []
        let thinkspaces = fetchedThinkspaceIDs.compactMap { id in
            ThinkspaceManager.shared.thinkspaces.first(where: { $0.id == id })
        }

        let resolvedProjectUUID = fetchedAtom?.link(ofType: .project)?.uuid
            ?? thinkspaces.compactMap(\.projectUuid).first
        let fetchedProject: Atom?
        if let resolvedProjectUUID {
            fetchedProject = try? await repository.fetch(uuid: resolvedProjectUUID)
        } else {
            fetchedProject = nil
        }

        let outlinedUUIDs = fetchedAtom?.outlineReferences.map(\.atomUUID) ?? []
        let fetchedOutlinedAtoms = outlinedUUIDs.isEmpty
            ? []
            : ((try? await repository.fetchBatch(uuids: outlinedUUIDs)) ?? [])

        await MainActor.run {
            atom = fetchedAtom
            provenanceThinkspaces = thinkspaces
            project = fetchedProject
            backlinks = fetchedBacklinks
            outlinedAtoms = fetchedOutlinedAtoms
        }
    }

    private func loadReferenceCandidates() async {
        guard let atom else { return }
        let trimmed = addReferenceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            addReferenceCandidates = []
            return
        }

        let types: [AtomType] = [.connection, .content, .idea, .research, .project]
        let matches = (try? await repository.search(query: trimmed, types: types)) ?? []
        let existingUUIDs = Set(atom.outlineReferences.map(\.atomUUID))

        await MainActor.run {
            addReferenceCandidates = matches.filter { candidate in
                candidate.uuid != atom.uuid && !existingUUIDs.contains(candidate.uuid)
            }
        }
    }

    private func addReference(_ candidate: Atom) {
        guard let atom, !isSaving else { return }
        var updated = atom.appendingOutlineReference(
            OutlineReferenceItem(
                atomUUID: candidate.uuid,
                atomType: candidate.type,
                title: candidate.title ?? "Untitled"
            )
        )
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        persist(updated, clearQuery: true)
    }

    private func removeReference(_ reference: OutlineReferenceItem) {
        guard let atom, !isSaving else { return }
        var updated = atom.removingOutlineReference(id: reference.id)
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        persist(updated, clearQuery: false)
    }

    private func persist(_ updatedAtom: Atom, clearQuery: Bool) {
        isSaving = true
        Task {
            let savedAtom = try? await repository.update(updatedAtom)
            NotificationCenter.default.post(name: .atomsDidChange, object: nil)
            await loadInspectorData()
            await MainActor.run {
                atom = savedAtom ?? updatedAtom
                if clearQuery {
                    addReferenceQuery = ""
                    addReferenceCandidates = []
                }
                isSaving = false
            }
        }
    }

    private func openInFocusMode(_ atom: Atom) {
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .idea
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": entityType, "id": atom.id ?? 0]
        )
    }

    private func color(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection: return DS.entityConnection
        case .project: return DS.accent
        case .note: return DS.entityNote
        case .stickyNote: return DS.entityStickyNote
        case .thinkspace: return DS.accent
        case .image: return DS.entityImage
        default: return DS.textSecondary
        }
    }
}
