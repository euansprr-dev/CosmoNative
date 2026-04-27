// CosmoOS/UI/FocusMode/Inquiry/Panes/InquiryNotebookPane.swift
// Notebook pane (Pane A) — five modes: Notes / Tree / Captures / Current Understanding / Local Map.
// Notes are auto-attached with provenance. Tree shows the live ResearchTreeDocument.

import SwiftUI

@MainActor
struct InquiryNotebookPane: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeSelector
            Divider().background(DS.borderSubtle)
            content
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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                HStack(spacing: DS.space10) {
                    topicNode
                    Rectangle()
                        .fill(DS.borderSubtle)
                        .frame(width: 28, height: 1)
                    branchMapNode(viewModel.structured.researchTree.rootNodeId, depth: 0)
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space16)
        }
    }

    private var topicNode: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.deepDive?.title ?? "Deep Dive")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(2)
            Text("topic home")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private func branchMapNode(_ nodeId: String, depth: Int) -> AnyView {
        guard let node = viewModel.structured.researchTree.nodes[nodeId] else {
            return AnyView(EmptyView())
        }
        let isActive = viewModel.activeBranchNodeId == nodeId
        let counts = viewModel.counts(for: node.atomUUID)
        let children = viewModel.childQuestionNodes(for: nodeId)
        let nodeView = VStack(alignment: .leading, spacing: 5) {
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
            Text(counts.compactLabel)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .padding(DS.space10)
        .frame(width: max(174, 194 - CGFloat(depth * 12)), alignment: .leading)
        .background(isActive ? DS.accentSoft : DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(isActive ? DS.accent.opacity(0.65) : DS.borderSubtle, lineWidth: 1))
        .shadow(color: isActive ? DS.accentGlow.opacity(0.28) : .clear, radius: 10, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.setActiveQuestion(node.atomUUID, branchNodeId: nodeId)
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
                                        .fill(DS.borderSubtle)
                                        .frame(width: 1, height: 18)
                                    Rectangle()
                                        .fill(DS.borderSubtle)
                                        .frame(width: 20, height: 1)
                                }
                                branchMapNode(child.id, depth: depth + 1)
                            }
                        }
                    }
                    .padding(.leading, DS.space16)
                }
            }
        )
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
