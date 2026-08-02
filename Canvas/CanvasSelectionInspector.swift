import SwiftUI

struct CanvasSelectionInspector: View {
    let block: CanvasBlock
    let currentThinkspaceId: String?
    let onClose: () -> Void

    // Action callbacks
    var onFocusMode: (() -> Void)?
    var onOpenAsPane: (() -> Void)?
    var onConnectTo: (() -> Void)?
    var onAIAssist: (() -> Void)?
    var onSave: (() -> Void)?
    var onDuplicate: (() -> Void)?
    // Two-tier removal: out of this thinkspace, or delete outright.
    var onRemoveFromThinkspace: (() -> Void)?
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
    @State private var deleteArmed = false
    @State private var hoveredColor: StickyNoteColor?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let repository = AtomRepository.shared
    private let inspectorWidth: CGFloat = 340

    private var isStickyNote: Bool { block.entityType == .stickyNote }

    var body: some View {
        panelBody
            .offset(x: appeared ? 0 : 24)
            .opacity(appeared ? 1 : 0)
            .compositingGroup()
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.gentle) {
                    appeared = true
                }
            }
    }

    @ViewBuilder
    private var panelBody: some View {
        Group {
            if isStickyNote {
                VStack(alignment: .leading, spacing: 20) {
                    stickyNoteHeader
                    stickyColorPalette
                    stickyActionsGrid
                    removalZone()
                }
                .padding(18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let atom {
                            header(atom)
                            actionsGrid(atom)
                            removalZone()
                            provenanceSection
                            outlineSection(atom)
                            backlinksSection
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: DS.accent))
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                    .padding(18)
                    // `.scrollIndicators(.hidden)` alone still leaves a legacy
                    // scroller drawn when the system is set to "Show scroll bars:
                    // Always" — reach the NSScrollView and turn the scroller off
                    // outright so the panel never grows a rail, only scrolls.
                    .background(CortexScrollViewIntrospector { _ in })
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 600)
            }
        }
        .frame(width: inspectorWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .cortexInspectorPanel(cornerRadius: 24)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color(for: atom.type).opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(color(for: atom.type).opacity(0.25), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: atom.type.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(color(for: atom.type))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(atom.title ?? block.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: atom.type))
                            .frame(width: 5, height: 5)
                        Text(atom.type.displayName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(DS.giltMuted)

                        if atom.outlineReferenceCount > 0 {
                            Text("·")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.giltMuted.opacity(0.6))
                            Text("\(atom.outlineReferenceCount) refs")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(DS.giltMuted)
                        }
                    }
                }

                Spacer(minLength: 0)

                glassCloseButton
            }

            if let preview = atom.body?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var glassCloseButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.text.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticky Note Inspector

    @ViewBuilder
    private var stickyNoteHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(currentStickyColor.paper)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(currentStickyColor.selectedBorder)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sticky Note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.text)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(DS.entityStickyNote)
                            .frame(width: 5, height: 5)
                        Text("STICKY NOTE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(DS.giltMuted)
                    }
                }

                Spacer(minLength: 0)

                glassCloseButton
            }

            if let content = block.metadata["content"],
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.text.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
        // Removal/delete live in their own dedicated zone below the grid.
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

        // Removal/delete live in their own dedicated zone below the grid.
        return actions
    }

    @ViewBuilder
    private func actionPill(_ action: InspectorAction) -> some View {
        let isDelete = action.id == "delete"
        Button {
            action.handler()
            onClose()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(action.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
        .buttonStyle(CortexChipStyle(isDestructive: isDelete))
    }

    // MARK: - Removal Zone (remove from thinkspace · delete)

    @ViewBuilder
    private func removalZone() -> some View {
        VStack(spacing: 8) {
            if currentThinkspaceId != nil, onRemoveFromThinkspace != nil {
                removeFromThinkspaceButton
            }
            if onDelete != nil {
                deleteButton
            }
        }
    }

    private var removeFromThinkspaceButton: some View {
        let isHovered = hoveredAction == "removeFromThinkspace"
        return Button {
            onRemoveFromThinkspace?()
            onClose()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 11, weight: .medium))
                Text("Remove from thinkspace")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? DS.text : DS.text.opacity(0.78))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered ? DS.glassInputFillFocused : DS.glassInputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Remove from this thinkspace. Stays in the database and any other thinkspaces.")
        .accessibilityLabel("Remove from thinkspace")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredAction = hovering ? "removeFromThinkspace" : nil
            }
        }
    }

    /// The prominent, full-width destructive action. First tap arms a warning
    /// state ("Tap again to delete"); the second tap commits. Auto-disarms after
    /// a few seconds so a stray first tap never lingers.
    private var deleteButton: some View {
        let isHovered = hoveredAction == "delete"
        return Button {
            if deleteArmed {
                onDelete?()
                onClose()
            } else {
                withAnimation(ProMotionSprings.snappy) { deleteArmed = true }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: deleteArmed ? "exclamationmark.triangle.fill" : "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text(deleteArmed ? "Tap again to delete" : "Delete")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(deleteArmed ? .white : DS.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(deleteArmed ? DS.red : DS.red.opacity(isHovered ? 0.16 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(deleteArmed ? .clear : DS.red.opacity(isHovered ? 0.42 : 0.26), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(deleteArmed ? "Tap again to move to Recently Deleted" : "Delete — moves to Recently Deleted")
        .accessibilityLabel(deleteArmed ? "Confirm delete" : "Delete")
        .accessibilityHint(deleteArmed ? "Removes it everywhere. Recoverable from Recently Deleted." : "")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredAction = hovering ? "delete" : nil
            }
        }
        .task(id: deleteArmed) {
            guard deleteArmed else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.18)) { deleteArmed = false }
            }
        }
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
                    TextField("Add reference…", text: $addReferenceQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )

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
                    .foregroundStyle(DS.text.opacity(0.45))
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
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
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
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
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
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.giltMuted)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(DS.giltMuted)
            }
            .padding(.leading, 2)

            content()
                .cortexSectionPane(cornerRadius: 16, padding: 12)
        }
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
        updated.updatedAt = ISO8601.string(from: Date())
        persist(updated, clearQuery: true)
    }

    private func removeReference(_ reference: OutlineReferenceItem) {
        guard let atom, !isSaving else { return }
        var updated = atom.removingOutlineReference(id: reference.id)
        updated.updatedAt = ISO8601.string(from: Date())
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
