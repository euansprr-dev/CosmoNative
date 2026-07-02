// CosmoOS/UI/FocusMode/Inquiry/InquiryKindBadgeMenu.swift
// The kind badge IS the correction control: a kind-tinted capsule chip that
// opens a dropdown of ExtractKind.correctionOptions on click. Shown wherever
// a routed extract's kind appears (notes rail, notebook pane, receipts), so a
// misclassification is always one click from fixed. Corrections flow through
// viewModel.rerouteExtract, which stamps the user-correction guard and feeds
// the routing-correction memory.

import SwiftUI

extension ExtractKind {
    /// Badge tint per kind family — semantic tokens only.
    var accentColor: Color {
        switch self {
        case .claim, .speculativeClaim: return DS.accent
        case .evidence: return DS.green
        case .counterevidence, .objection: return DS.orange
        case .benefit, .outputIdea: return CosmoMentionColors.swipeFile
        case .problem: return CosmoColors.task
        case .goal: return CosmoColors.idea
        case .mechanism, .practice: return CosmoColors.content
        case .example: return CosmoMentionColors.stickyNote
        case .principle, .assumption, .sourceQualityNote, .reference: return CosmoColors.slate
        case .question: return CosmoColors.skyBlue
        case .aiInsight: return CosmoColors.cosmoAI
        case .term, .quote, .highlight, .sourceSnippet, .note: return CosmoColors.note
        }
    }
}

/// Kind-tinted capsule badge that opens the kind-correction dropdown.
@MainActor
struct InquiryKindBadgeMenu: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let extractUUID: String
    let kind: ExtractKind
    /// True when the kind came from the offline heuristic fallback rather than
    /// the classifier — rendered with a dashed stroke inviting correction.
    var isUnconfirmed: Bool = false

    @State private var isHovered = false

    var body: some View {
        Menu {
            menuItems
        } label: {
            InquiryKindBadgeLabel(kind: kind, isUnconfirmed: isUnconfirmed, showsChevron: isHovered)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("\(kind.displayName). Click to change kind.")
    }

    @ViewBuilder
    private var menuItems: some View {
        ForEach(ExtractKind.correctionOptions, id: \.self) { option in
            Button {
                Task { await viewModel.rerouteExtract(extractUUID, toKind: option) }
            } label: {
                if option == kind {
                    Label(option.displayName, systemImage: "checkmark")
                } else {
                    Label(option.displayName, systemImage: option.iconName)
                }
            }
            .disabled(option == kind)
        }
    }
}

/// The badge chip itself — reusable as a static label where no menu applies.
struct InquiryKindBadgeLabel: View {
    let kind: ExtractKind
    var isUnconfirmed: Bool = false
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.iconName)
                .font(.system(size: 8, weight: .semibold))
                .accessibilityHidden(true)
            Text(kind.displayName)
                .font(CosmoTypography.labelSmall)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(kind.accentColor)
        .padding(.horizontal, DS.space6)
        .padding(.vertical, 2)
        .background(kind.accentColor.opacity(0.1), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    kind.accentColor.opacity(isUnconfirmed ? 0.55 : 0.25),
                    style: StrokeStyle(lineWidth: 1, dash: isUnconfirmed ? [3, 2] : [])
                )
        )
        .contentShape(Capsule())
    }
}

/// Shimmering placeholder shown while a capture awaits its LLM classification.
struct InquiryClassifyingChip: View {
    var body: some View {
        HStack(spacing: 4) {
            ProvisionalPulseDot()
            Text("Classifying…")
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .padding(.horizontal, DS.space6)
        .padding(.vertical, 2)
        .background(DS.surface, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(DS.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
        .accessibilityLabel("Classifying capture")
    }
}
