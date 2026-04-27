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
        VStack(alignment: .leading, spacing: DS.space10) {
            if let q = activeQuestionTitle {
                Text("Q: \(q)")
                    .font(.system(size: 16, weight: .regular, design: .serif).italic())
                    .foregroundStyle(CosmoColors.textPrimary)
                    .padding(.horizontal, DS.space16)
                    .padding(.top, DS.space12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.space12) {
                    TextEditor(text: $viewModel.noteDraft)
                        .scrollContentBackground(.hidden)
                        .font(CosmoTypography.body)
                        .frame(minHeight: 240)
                        .padding(DS.space12)
                        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusMedium)
                                .stroke(DS.borderSubtle, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if viewModel.noteDraft.isEmpty {
                                Text("Write a note. Use Q:, Principle:, Idea:, Practice:, Source: prefixes for inferred kind. ⌘↩ to save.")
                                    .font(CosmoTypography.body)
                                    .foregroundStyle(CosmoColors.textTertiary)
                                    .padding(.horizontal, DS.space16)
                                    .padding(.top, DS.space16)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Spacer()
                        Button {
                            Task { await viewModel.saveNoteDraft() }
                        } label: {
                            Text("Save note")
                                .font(CosmoTypography.label)
                                .padding(.horizontal, DS.space12)
                                .padding(.vertical, 6)
                                .background(DS.accent, in: Capsule())
                                .foregroundStyle(DS.textOnAccent)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
            }
        }
    }

    private var activeQuestionTitle: String? {
        viewModel.rootQuestion?.title
    }

    // MARK: - Tree

    private var treeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                treeNode(viewModel.structured.researchTree.rootNodeId, depth: 0)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    private func treeNode(_ nodeId: String, depth: Int) -> AnyView {
        guard let node = viewModel.structured.researchTree.nodes[nodeId] else {
            return AnyView(EmptyView())
        }
        let row = HStack(alignment: .top, spacing: 6) {
            Image(systemName: nodeIcon(for: node.kind))
                .font(.system(size: 11))
                .foregroundStyle(CosmoColors.textTertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.meta.label ?? node.kind.rawValue.capitalized)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(node.meta.aiSuggested && !node.meta.accepted ? CosmoColors.textSecondary : CosmoColors.textPrimary)
                    .lineLimit(2)
                if node.meta.aiSuggested && !node.meta.accepted {
                    Text("AI suggested · tap to accept")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activeBranchNodeId = nodeId
            if node.kind == .question, let atomUUID = node.atomUUID {
                viewModel.activeQuestionUUID = atomUUID
            }
        }
        .background(viewModel.activeBranchNodeId == nodeId ? DS.accentSoft : Color.clear)

        let children = node.childNodeIds
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                row
                ForEach(children, id: \.self) { childId in
                    treeNode(childId, depth: depth + 1)
                }
            }
        )
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
