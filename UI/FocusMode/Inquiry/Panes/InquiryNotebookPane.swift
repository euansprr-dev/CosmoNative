// CosmoOS/UI/FocusMode/Inquiry/Panes/InquiryNotebookPane.swift
// Notebook pane (Pane A) — five modes: Notes / Tree / Captures / Current Understanding / Local Map.
// Notes are auto-attached with provenance. Tree shows the live ResearchTreeDocument.

import SwiftUI

@MainActor
struct InquiryNotebookPane: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    @State private var renamingQuestionUUID: String?
    @State private var renameDraft: String = ""
    @State private var reparentingQuestionUUID: String?
    @State private var deletingQuestionUUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeSelector
            Divider().background(DS.borderSubtle)
            content
        }
        .sheet(isPresented: renameSheetBinding) {
            if let questionUUID = renamingQuestionUUID {
                questionRenameSheet(questionUUID)
            }
        }
        .sheet(isPresented: reparentSheetBinding) {
            if let questionUUID = reparentingQuestionUUID {
                questionReparentSheet(questionUUID)
            }
        }
        .confirmationDialog("Delete question?", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("Delete Question", role: .destructive) {
                Task { await viewModel.deleteQuestion(deletingQuestionUUID) }
                deletingQuestionUUID = nil
            }
            Button("Cancel", role: .cancel) {
                deletingQuestionUUID = nil
            }
        } message: {
            Text("The question atom will be moved to Recently Deleted. Child questions stay in the map.")
        }
    }

    // MARK: - Mode selector

    private var modeSelector: some View {
        HStack(spacing: DS.space12) {
            ForEach(InquiryNotebookMode.allCases, id: \.self) { mode in
                modeChip(mode)
            }
            Spacer()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
    }

    private func modeChip(_ mode: InquiryNotebookMode) -> some View {
        let isActive = viewModel.notebookMode == mode
        return Button {
            viewModel.notebookMode = mode
        } label: {
            Text(mode.title)
                .font(CosmoTypography.caption)
                .foregroundStyle(isActive ? CosmoColors.textPrimary : CosmoColors.textSecondary)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? DS.accent : Color.clear)
                        .frame(height: 1.5)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.notebookMode {
        case .notes: notesView
        case .tree: treeView
        case .captures: capturesView
        case .currentUnderstanding: currentUnderstandingView
        case .localMap: localMapView
        }
    }

    // MARK: - Notes

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            notesHeader
            Divider().background(DS.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space12) {
                    noteEditor(
                        text: $viewModel.noteDraft,
                        minHeight: 230,
                        placeholder: "Write under \(viewModel.activeQuestionTitle). Use Q:, Principle:, Idea:, Objection:, Practice:, Source:, Output:."
                    )
                    HStack {
                        provenanceLine
                        Spacer()
                        Button {
                            Task { await viewModel.saveNoteDraft() }
                        } label: {
                            Text(viewModel.noteSaveState ? "Saved" : "Save note")
                                .font(CosmoTypography.label)
                                .padding(.horizontal, DS.space12)
                                .padding(.vertical, 6)
                                .background(DS.accent, in: Capsule())
                                .foregroundStyle(DS.textOnAccent)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }

                    pinnedNotesSection
                }
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
            }
        }
    }

    private var notesHeader: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("WRITING UNDER")
                .font(CosmoTypography.labelSmall)
                .tracking(1.6)
                .foregroundStyle(CosmoColors.textTertiary)
            HStack(spacing: DS.space8) {
                Menu {
                    ForEach(viewModel.orderedQuestionNodes(), id: \.id) { node in
                        Button {
                            viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
                        } label: {
                            Text("\(viewModel.questionTitle(for: node.atomUUID))  \(viewModel.counts(for: node.atomUUID).compactLabel)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        statusGlyph(viewModel.questionStatus(for: viewModel.activeQuestionUUID))
                        Text(viewModel.activeQuestionTitle)
                            .font(CosmoTypography.label)
                            .foregroundStyle(CosmoColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 6)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.aiPromptDraft = "Suggest one branch question under: \(viewModel.activeQuestionTitle)"
                } label: {
                    Label("Branch", systemImage: "arrow.triangle.branch")
                        .font(CosmoTypography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textSecondary)

                Button {
                    viewModel.togglePinActiveQuestion()
                } label: {
                    Image(systemName: viewModel.structured.uiState.pinnedQuestionUUIDs.contains(viewModel.activeQuestionUUID ?? "") ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textSecondary)
                .help("Pin question notes")
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    private var provenanceLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(.system(size: 9))
            Text(provenanceText)
                .font(CosmoTypography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(CosmoColors.textTertiary)
    }

    private var provenanceText: String {
        var parts = ["Session", viewModel.activeQuestionTitle]
        if let source = viewModel.activeSourceTab?.title {
            parts.append(source)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var pinnedNotesSection: some View {
        let pinned = viewModel.pinnedQuestions().filter { $0.uuid != viewModel.activeQuestionUUID }
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("PINNED QUESTIONS")
                    .font(CosmoTypography.labelSmall)
                    .tracking(1.6)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .padding(.top, DS.space12)
                ForEach(pinned.prefix(3), id: \.uuid) { question in
                    pinnedQuestionEditor(question)
                }
                if pinned.count > 3 {
                    Text("+ \(pinned.count - 3) pinned")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
        }
    }

    private func pinnedQuestionEditor(_ question: Atom) -> some View {
        let counts = viewModel.counts(for: question.uuid)
        let binding = Binding(
            get: { viewModel.structured.uiState.pinnedNoteDraftsByQuestionUUID[question.uuid] ?? "" },
            set: {
                viewModel.structured.uiState.pinnedNoteDraftsByQuestionUUID[question.uuid] = $0
                viewModel.scheduleSave()
            }
        )
        return VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                statusGlyph(question.questionMetadata?.status ?? .open)
                Text(question.title ?? "Untitled question")
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(counts.compactLabel)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                Button {
                    viewModel.setActiveQuestion(question.uuid)
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textSecondary)
                Button {
                    viewModel.togglePinnedQuestion(question.uuid)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textTertiary)
            }
            noteEditor(
                text: binding,
                minHeight: 92,
                placeholder: "Add a note under this question."
            )
            HStack {
                Spacer()
                Button("Save") {
                    Task { await viewModel.savePinnedNoteDraft(for: question.uuid) }
                }
                .font(CosmoTypography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func noteEditor(text: Binding<String>, minHeight: CGFloat, placeholder: String) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .font(CosmoTypography.body)
            .frame(minHeight: minHeight)
            .padding(DS.space12)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .padding(.horizontal, DS.space16)
                        .padding(.top, DS.space16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Tree

    private var treeView: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: DS.space18) {
                topicColumn
                if viewModel.rootQuestionNodeIds().isEmpty {
                    emptyMapState
                } else {
                    ForEach(viewModel.rootQuestionNodeIds(), id: \.self) { nodeId in
                        branchMapNode(nodeId, depth: 0)
                    }
                    selectedMapInspector
                }
            }
            .padding(.horizontal, DS.space20)
            .padding(.vertical, DS.space18)
        }
        .background(mapBackground)
    }

    private var topicColumn: some View {
        VStack(alignment: .center, spacing: DS.space10) {
            topicNode
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(width: 1, height: 34)
            Text("ROOT QUESTIONS")
                .font(CosmoTypography.labelSmall)
                .tracking(1.6)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .frame(width: 190)
    }

    private var topicNode: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.deepDive?.title ?? "Deep Dive")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
            Text("topic anchor")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.accent.opacity(0.35), lineWidth: 1))
    }

    private var emptyMapState: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22))
                .foregroundStyle(CosmoColors.textTertiary)
            Text("No real branches yet")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Accepted conceptual questions will appear here. Evidence audits and source searches stay attached as tasks.")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .frame(width: 260, alignment: .leading)
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private var selectedMapInspector: some View {
        let notes = viewModel.recentNotes(for: viewModel.activeQuestionUUID, limit: 4)
        let claims = viewModel.claims(for: viewModel.activeQuestionUUID)
        let evidence = viewModel.evidence(for: viewModel.activeQuestionUUID)
        let tasks = viewModel.operationalTasks(for: viewModel.activeQuestionUUID)
        return VStack(alignment: .leading, spacing: DS.space10) {
            Text("ATTACHED")
                .font(CosmoTypography.labelSmall)
                .tracking(1.6)
                .foregroundStyle(CosmoColors.textTertiary)
            Text(viewModel.activeQuestionTitle)
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
            mapInspectorGroup("Notes", items: notes.map { $0.body ?? $0.title ?? "" })
            mapInspectorGroup("Claims", items: claims.map { $0.body ?? $0.title ?? "" })
            mapInspectorGroup("Evidence", items: evidence.map { $0.body ?? $0.title ?? "" })
            mapInspectorGroup("Tasks", items: tasks.map(\.title))
            Spacer(minLength: 0)
        }
        .padding(DS.space12)
        .frame(width: 250, alignment: .topLeading)
        .background(DS.surfaceElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func mapInspectorGroup(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
            if items.isEmpty {
                Text("None")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary.opacity(0.7))
            } else {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func branchMapNode(_ nodeId: String, depth: Int) -> AnyView {
        guard let node = viewModel.structured.researchTree.nodes[nodeId] else {
            return AnyView(EmptyView())
        }
        let isActive = viewModel.activeBranchNodeId == nodeId
        let counts = viewModel.counts(for: node.atomUUID)
        let children = viewModel.childQuestionNodes(for: nodeId)
        let relationship = node.meta.relationshipType ?? (depth == 0 ? .rootUnderTopic : .childOf)
        let nodeView = VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: 6) {
                statusGlyph(viewModel.questionStatus(for: node.atomUUID))
                Text(node.meta.label ?? viewModel.questionTitle(for: node.atomUUID))
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
                    viewModel.aiPromptDraft = "Suggest one branch question under: \(viewModel.questionTitle(for: node.atomUUID))"
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textTertiary)
            }
            if depth > 0 {
                Text(relationship.displayName)
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(DS.accent.opacity(0.82))
            }
            attachmentChips(counts)
        }
        .padding(DS.space10)
        .frame(width: depth == 0 ? 230 : 210, alignment: .leading)
        .background(isActive ? DS.accentSoft : DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(isActive ? DS.accent.opacity(0.65) : DS.borderSubtle, lineWidth: 1))
        .shadow(color: isActive ? DS.accentGlow.opacity(0.28) : .clear, radius: 10, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.setActiveQuestion(node.atomUUID, branchNodeId: nodeId)
        }
        .contextMenu {
            questionContextMenu(node)
        }

        return AnyView(
            VStack(alignment: .leading, spacing: DS.space8) {
                nodeView
                if !children.isEmpty {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        ForEach(children, id: \.id) { child in
                            HStack(alignment: .top, spacing: DS.space8) {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(isActive ? DS.accent.opacity(0.55) : DS.borderSubtle)
                                        .frame(width: 1.5, height: 18)
                                    Rectangle()
                                        .fill(isActive ? DS.accent.opacity(0.55) : DS.borderSubtle)
                                        .frame(width: 24, height: 1.5)
                                }
                                branchMapNode(child.id, depth: depth + 1)
                            }
                        }
                    }
                    .padding(.leading, DS.space18)
                }
            }
        )
    }

    private func attachmentChips(_ counts: InquiryQuestionCounts) -> some View {
        HStack(spacing: 5) {
            attachmentChip(icon: "doc.text", count: counts.sources)
            attachmentChip(icon: "note.text", count: counts.notes)
            attachmentChip(icon: "exclamationmark.bubble", count: counts.claims)
            attachmentChip(icon: "checkmark.seal", count: counts.evidence)
            attachmentChip(icon: "checklist", count: counts.tasks)
            attachmentChip(icon: "arrow.triangle.branch", count: counts.children)
        }
    }

    private func attachmentChip(icon: String, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text("\(count)")
                .font(CosmoTypography.labelSmall)
        }
        .foregroundStyle(count > 0 ? CosmoColors.textSecondary : CosmoColors.textTertiary.opacity(0.58))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(DS.surface, in: Capsule())
    }

    @ViewBuilder
    private func questionContextMenu(_ node: ResearchTreeNode) -> some View {
        Button("Open Inspector") {
            viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
        }
        Button("Rename") {
            renamingQuestionUUID = node.atomUUID
            renameDraft = viewModel.questionTitle(for: node.atomUUID)
        }
        Button("Reparent...") {
            reparentingQuestionUUID = node.atomUUID
        }
        Button("Make Root Question") {
            Task { await viewModel.reparentQuestion(node.atomUUID, to: nil, relationship: .rootUnderTopic) }
        }
        Button("Make Sibling") {
            Task { await viewModel.makeQuestionSibling(node.atomUUID) }
        }
        Divider()
        Button("Pin / Unpin") {
            if let uuid = node.atomUUID { viewModel.togglePinnedQuestion(uuid) }
        }
        Button("Mark Answered") {
            Task { await viewModel.updateQuestionStatus(node.atomUUID, status: .answered) }
        }
        Button("Archive") {
            Task { await viewModel.archiveQuestion(node.atomUUID) }
        }
        Button("Delete", role: .destructive) {
            deletingQuestionUUID = node.atomUUID
        }
    }

    private var mapBackground: some View {
        ZStack {
            DS.bg
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 32
                    var x: CGFloat = 0
                    while x < geo.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < geo.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(DS.borderSubtle.opacity(0.22), lineWidth: 0.5)
            }
        }
    }

    private var renameSheetBinding: Binding<Bool> {
        Binding(
            get: { renamingQuestionUUID != nil },
            set: { if !$0 { renamingQuestionUUID = nil } }
        )
    }

    private var reparentSheetBinding: Binding<Bool> {
        Binding(
            get: { reparentingQuestionUUID != nil },
            set: { if !$0 { reparentingQuestionUUID = nil } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deletingQuestionUUID != nil },
            set: { if !$0 { deletingQuestionUUID = nil } }
        )
    }

    private func questionRenameSheet(_ questionUUID: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("Rename Question")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            TextField("Question", text: $renameDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CosmoTypography.body)
                .padding(DS.space12)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderActive, lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel") {
                    renamingQuestionUUID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textSecondary)
                Button("Save") {
                    Task { await viewModel.renameQuestion(questionUUID, title: renameDraft) }
                    renamingQuestionUUID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
            }
        }
        .padding(DS.space20)
        .frame(width: 420)
        .background(DS.bg)
    }

    private func questionReparentSheet(_ questionUUID: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Move Question")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text(viewModel.questionTitle(for: questionUUID))
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
            Button {
                Task { await viewModel.reparentQuestion(questionUUID, to: nil, relationship: .rootUnderTopic) }
                reparentingQuestionUUID = nil
            } label: {
                reparentDestinationRow(title: "Root under \(viewModel.deepDive?.title ?? "Deep Dive")", icon: "circle.hexagongrid.circle")
            }
            .buttonStyle(.plain)
            Divider().background(DS.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space8) {
                    ForEach(viewModel.orderedQuestionNodes().filter { $0.atomUUID != questionUUID }, id: \.id) { node in
                        Button {
                            Task { await viewModel.reparentQuestion(questionUUID, to: node.atomUUID, relationship: .childOf) }
                            reparentingQuestionUUID = nil
                        } label: {
                            reparentDestinationRow(title: viewModel.questionTitle(for: node.atomUUID), icon: "questionmark.bubble")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(DS.space20)
        .frame(width: 460)
        .background(DS.bg)
    }

    private func reparentDestinationRow(title: String, icon: String) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(DS.accent)
            Text(title)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
            Spacer()
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func statusGlyph(_ status: QuestionStatus) -> some View {
        switch status {
        case .open:
            Circle().stroke(CosmoColors.textTertiary, lineWidth: 1).frame(width: 8, height: 8)
        case .researching:
            Circle().fill(DS.accent).frame(width: 8, height: 8)
        case .partiallyAnswered:
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 8)).foregroundStyle(DS.orange)
        case .answered:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(DS.green)
        case .promoted:
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 9)).foregroundStyle(DS.info)
        case .archived:
            Circle().fill(CosmoColors.textTertiary.opacity(0.45)).frame(width: 8, height: 8)
        }
    }

    private func nodeIcon(for kind: ResearchTreeNode.Kind) -> String {
        switch kind {
        case .question: return "questionmark.circle"
        case .source: return "doc.text"
        case .extract: return "highlighter"
        case .note: return "note.text"
        case .concept: return "circle.hexagongrid"
        case .ai: return "sparkles"
        case .branch: return "arrow.triangle.branch"
        }
    }

    // MARK: - Captures

    private var capturesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space8) {
                if viewModel.captures.filter({ $0.status == .pending }).isEmpty {
                    Text("No pending captures. Telegram and quick captures (⌘;) appear here for triage.")
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .padding(.top, DS.space20)
                }
                ForEach(viewModel.captures.filter { $0.status == .pending }, id: \.id) { capture in
                    captureRow(capture)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    private func captureRow(_ capture: SessionCapture) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: capture.suggestedKind?.iconName ?? "circle")
                .font(.system(size: 11))
                .foregroundStyle(DS.accent)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.body)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                HStack(spacing: 8) {
                    Menu {
                        ForEach(ExtractKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) {
                                Task { _ = await viewModel.commitCapture(capture.id, kind: kind) }
                            }
                        }
                    } label: {
                        Text("Commit as ▾")
                            .font(CosmoTypography.caption)
                            .foregroundStyle(DS.accent)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    Button("Discard") {
                        viewModel.discardCapture(capture.id)
                    }
                    .buttonStyle(.plain)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                    Spacer()
                    Text(capture.source.rawValue)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    // MARK: - Current Understanding

    private var currentUnderstandingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                if let dd = viewModel.deepDive {
                    let model = dd.deepDiveStructured?.currentUnderstanding.oneSentenceModel ?? ""
                    if model.isEmpty {
                        Text("This Deep Dive's current understanding is empty. Open the Deep Dive Overview to begin.")
                            .font(CosmoTypography.body)
                            .foregroundStyle(CosmoColors.textSecondary)
                    } else {
                        Text(model)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(CosmoColors.textPrimary)
                        let principles = dd.deepDiveStructured?.currentUnderstanding.corePrinciples ?? []
                        if !principles.isEmpty {
                            Text("CORE PRINCIPLES")
                                .font(CosmoTypography.labelSmall)
                                .foregroundStyle(CosmoColors.textSecondary)
                                .padding(.top, DS.space8)
                            ForEach(principles, id: \.id) { p in
                                Text("· \(p.text)")
                                    .font(CosmoTypography.body)
                                    .foregroundStyle(CosmoColors.textPrimary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    // MARK: - Local Map (placeholder)

    private var localMapView: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 28))
                .foregroundStyle(DS.accent.opacity(0.5))
            Text("Local Map")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Force-directed concept map renders after the cartographer detects enough structure.")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
