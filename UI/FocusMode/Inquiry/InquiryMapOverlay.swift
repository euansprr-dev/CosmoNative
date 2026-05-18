// CosmoOS/UI/FocusMode/Inquiry/InquiryMapOverlay.swift
// Full-screen overlay (Cmd+M) showing the question/branch tree for the current session.

import SwiftUI

@MainActor
struct InquiryMapOverlay: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { viewModel.dismissMap() }
            mapPanel
        }
        .accessibilityAddTraits(.isModal)
    }

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(DS.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space12) {
                    ForEach(rootNodes, id: \.id) { node in
                        InquiryBranchMapNodeView(viewModel: viewModel, node: node, depth: 0)
                    }
                }
                .padding(.horizontal, DS.space24)
                .padding(.vertical, DS.space20)
            }
        }
        .frame(maxWidth: 720, maxHeight: 540)
        .background(DS.vellum, in: RoundedRectangle(cornerRadius: DS.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 32, y: 16)
    }

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "map")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text("Branch map")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Spacer()
            Button {
                viewModel.dismissMap()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CosmoColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DS.surface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close branch map")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var rootNodes: [ResearchTreeNode] {
        viewModel.rootQuestionNodeIds().compactMap { viewModel.structured.researchTree.nodes[$0] }
    }
}

// MARK: - Branch map node

@MainActor
struct InquiryBranchMapNodeView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let node: ResearchTreeNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Button {
                viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.id)
                viewModel.dismissMap()
            } label: {
                HStack(spacing: DS.space8) {
                    Image(systemName: isActive ? "circle.inset.filled" : "circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isActive ? DS.accent : CosmoColors.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(CosmoColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        let counts = viewModel.counts(for: node.atomUUID)
                        Text(counts.compactLabel)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space8)
                .background(isActive ? DS.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(label)")

            ForEach(childNodes, id: \.id) { child in
                InquiryBranchMapNodeView(viewModel: viewModel, node: child, depth: depth + 1)
                    .padding(.leading, DS.space20)
            }
        }
    }

    private var label: String {
        if let uuid = node.atomUUID {
            return viewModel.questionTitle(for: uuid)
        }
        return node.meta.label ?? "Untitled"
    }

    private var isActive: Bool {
        node.atomUUID == viewModel.activeQuestionUUID
    }

    private var childNodes: [ResearchTreeNode] {
        viewModel.childQuestionNodes(for: node.id)
    }
}
