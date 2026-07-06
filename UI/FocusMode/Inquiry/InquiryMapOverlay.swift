// CosmoOS/UI/FocusMode/Inquiry/InquiryMapOverlay.swift
// The SESSION map (⌘M): this session's question tree, scoped to the inquiry
// at hand. The topic-wide map (crystallized concepts) lives on the Deep Dive
// overview's Map tab. Presents as a materializing glass panel over a
// whisper-dimmed page.

import SwiftUI

@MainActor
struct InquiryMapOverlay: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        ZStack {
            // A whisper, not a wall — the glass needs the page alive behind it.
            Color.black.opacity(0.10).ignoresSafeArea()
                .onTapGesture { viewModel.dismissMap() }
                .accessibilityLabel("Dismiss session map")
            mapPanel
        }
        .accessibilityAddTraits(.isModal)
    }

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            InquiryMindMapView(root: sessionRoot) { node in
                if node.atomUUID != nil || node.branchNodeId != nil {
                    viewModel.setActiveQuestion(node.atomUUID, branchNodeId: node.branchNodeId)
                    viewModel.dismissMap()
                }
            }
            if !viewModel.gardenerProposals.isEmpty {
                // The Gardener speaks where the structure it would change is
                // on screen.
                InquiryTendingMapStrip(
                    proposals: viewModel.gardenerProposals,
                    onAccept: { proposal in
                        Task { await viewModel.acceptGardenerProposal(proposal) }
                    },
                    onDismiss: { proposal in
                        Task { await viewModel.dismissGardenerProposal(proposal) }
                    }
                )
            }
        }
        .frame(maxWidth: 880, maxHeight: 620)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
        .padding(DS.space24)
    }

    private var sessionRoot: MindMapNode {
        MindMapBuilder.buildSessionTree(
            tree: viewModel.structured.researchTree,
            rootTitle: viewModel.deepDive?.title ?? "Inquiry",
            questionTitle: { viewModel.questionTitle(for: $0) },
            countsLabel: { uuid in
                let label = viewModel.counts(for: uuid).compactLabel
                return label.isEmpty ? nil : label
            },
            activeQuestionUUID: viewModel.activeQuestionUUID
        )
    }

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "circle.hexagongrid")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text("Session map")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text("this session's questions")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button {
                viewModel.dismissMap()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DS.glassSectionFill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close session map")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .background(DS.glassSectionFill)
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
