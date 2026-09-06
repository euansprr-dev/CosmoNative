// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapNodeCard.swift
// Node cards for the mind map. Concept-first visual hierarchy: concepts are
// the substantial cards (core = large with a branch-color accent bar, child =
// medium tinted), questions are small muted satellites, and question groups
// read as quiet dashed buckets. Sections are chapter headers (small caps,
// quiet tint) and ghosts are PROPOSED sections — dashed, with inline ✓/✕.

import SwiftUI

@MainActor
struct InquiryMindMapNodeCard: View {
    let node: MindMapNode
    let branchColor: Color
    let onSelect: (MindMapNode) -> Void
    /// Wash applied to members while their ghost proposal is hovered.
    var isGhostHighlighted: Bool = false
    var onToggleCollapse: ((MindMapNode) -> Void)? = nil
    var onAcceptProposal: ((String) -> Void)? = nil
    var onDismissProposal: ((String) -> Void)? = nil
    var onGhostHover: ((String?) -> Void)? = nil

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func size(for node: MindMapNode) -> CGSize {
        if node.isGhost { return CGSize(width: 248, height: 64) }
        switch node.kind {
        case .root: return CGSize(width: 230, height: 72)
        case .coreConcept: return CGSize(width: 220, height: 64)
        case .childConcept: return CGSize(width: 180, height: 52)
        case .seedling: return CGSize(width: 168, height: 46)
        case .question: return CGSize(width: 232, height: 40)
        case .subQuestion: return CGSize(width: 208, height: 36)
        case .questionGroup: return CGSize(width: 170, height: 44)
        case .page: return CGSize(width: 200, height: 60)
        case .material: return CGSize(width: 190, height: 52)
        }
    }

    var body: some View {
        interactiveCard
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
                if node.isGhost { onGhostHover?(hovering ? node.proposalKey : nil) }
            }
            .overlay(alignment: .topLeading) { hoverRevealCard }
            .zIndex(isHovered ? 50 : 0)
            .help(helpText)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(node.isActive ? .isSelected : [])
    }

    /// Ghosts carry their own ✓/✕ buttons, so the card itself is not a
    /// button; every other node opens on click. (Stable per node identity —
    /// never a branch on animated state.)
    @ViewBuilder
    private var interactiveCard: some View {
        if node.isGhost {
            cardLabel
        } else {
            Button {
                onSelect(node)
            } label: {
                cardLabel
            }
            .buttonStyle(.plain)
        }
    }

    /// Question capsules truncate to one line — hovering reveals the full
    /// text in a floating card so nothing on the map stays unreadable.
    @ViewBuilder
    private var hoverRevealCard: some View {
        if isHovered, node.kind == .question || node.kind == .subQuestion {
            Text(node.title)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .frame(width: Self.size(for: node).width * 1.6, alignment: .leading)
                .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.borderSubtle, lineWidth: 1))
                .dsFloatingShadow()
                .offset(y: -(Self.size(for: node).height + 6))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .offset(y: 3)))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var cardLabel: some View {
        let size = Self.size(for: node)
        HStack(spacing: DS.space8) {
            leadingAccessory
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .tracking(node.isSection ? 0.6 : 0)
                    .font(titleFont)
                    .textCase(node.isSection ? .uppercase : nil)
                    .foregroundStyle(titleColor)
                    .lineLimit(node.isConcept || node.kind == .root || node.kind == .page || node.kind == .material ? 2 : 1)
                    .multilineTextAlignment(.leading)
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if node.isGhost {
                ghostControls
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(background, in: shape)
        .overlay(borderOverlay)
        .overlay(alignment: .trailing) { collapseControl }
        .shadow(color: .black.opacity(shadowOpacity), radius: isHovered ? 10 : 6, y: 3)
        .contentShape(shape)
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isHovered)
    }

    /// The ghost's verdict: accept materializes the section, ✕ dismisses it
    /// forever. Small circular targets with taught tooltips.
    private var ghostControls: some View {
        HStack(spacing: DS.space4) {
            Button {
                if let key = node.proposalKey { onAcceptProposal?(key) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 24, height: 24)
                    .background(DS.accent.opacity(0.12), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Group these concepts under “\(node.title)”")
            .accessibilityLabel("Accept section \(node.title)")

            Button {
                if let key = node.proposalKey { onDismissProposal?(key) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Not now — won't be suggested again")
            .accessibilityLabel("Dismiss proposed section \(node.title)")
        }
    }

    /// Fold affordance: collapsed nodes always show their "+N"; expanded
    /// concept parents reveal a chevron on hover. Overlaid at the trailing
    /// edge so hover never reflows the card.
    @ViewBuilder
    private var collapseControl: some View {
        if let onToggleCollapse, !node.isGhost {
            if node.collapsedCount > 0 {
                Button {
                    onToggleCollapse(node)
                } label: {
                    HStack(spacing: 2) {
                        Text("+\(node.collapsedCount)")
                            .font(CosmoTypography.caption.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(branchColor)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 3)
                    .background(branchColor.opacity(0.12), in: .capsule)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, DS.space6)
                .help("Show the \(node.collapsedCount) hidden")
                .accessibilityLabel("Expand \(node.title), \(node.collapsedCount) hidden")
            } else if isHovered, !node.children.isEmpty {
                Button {
                    onToggleCollapse(node)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CosmoColors.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(DS.surfaceElevated, in: .circle)
                        .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, DS.space6)
                .transition(.opacity)
                .help("Fold this branch")
                .accessibilityLabel("Collapse \(node.title)")
            }
        }
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if node.isGhost {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(branchColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 3, height: 30)
                .accessibilityHidden(true)
        } else {
            switch node.kind {
            case .coreConcept:
                RoundedRectangle(cornerRadius: 2)
                    .fill(node.isSection ? branchColor.opacity(0.6) : branchColor)
                    .frame(width: 3, height: node.isSection ? 24 : 34)
                    .accessibilityHidden(true)
            case .question, .subQuestion:
                Image(systemName: "questionmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .accessibilityHidden(true)
            case .questionGroup:
                Image(systemName: "tray")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .accessibilityHidden(true)
            case .seedling:
                Image(systemName: "leaf")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(node.isRipe ? branchColor : CosmoColors.textTertiary)
                    .accessibilityHidden(true)
            case .root, .childConcept:
                EmptyView()
            case .page, .material:
                Image(systemName: node.kind == .page ? "doc.text" : "link")
                    .font(DS.caption).foregroundStyle(DS.textMuted).accessibilityHidden(true)
            }
        }
    }

    private var titleFont: Font {
        if node.isSection { return CosmoTypography.label.weight(.semibold) }
        switch node.kind {
        case .root: return .system(.title3, design: .serif).weight(.semibold)
        case .coreConcept: return .system(.body, design: .serif).weight(.semibold)
        case .childConcept, .seedling: return .system(.callout, design: .serif)
        case .question, .subQuestion: return CosmoTypography.labelSmall
        case .questionGroup: return CosmoTypography.label
        case .page: return DS.headline
        case .material: return DS.callout
        }
    }

    private var titleColor: Color {
        if node.isGhost { return CosmoColors.textSecondary }
        if node.isSection { return CosmoColors.textSecondary }
        switch node.kind {
        case .question, .subQuestion, .questionGroup: return CosmoColors.textSecondary
        case .seedling: return node.isRipe ? CosmoColors.textPrimary : CosmoColors.textSecondary
        default: return CosmoColors.textPrimary
        }
    }

    private var shape: some InsettableShape {
        switch node.kind {
        case .question, .subQuestion:
            return AnyInsettableShape(Capsule())
        default:
            return AnyInsettableShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
        }
    }

    private var background: Color {
        if node.isGhost { return branchColor.opacity(isHovered ? 0.08 : 0.05) }
        if isGhostHighlighted { return branchColor.opacity(0.10) }
        if node.isSection { return branchColor.opacity(0.04) }
        switch node.kind {
        // surfaceElevated, not vellum: vellum on the parchment page differs
        // by a hair — the root card's right half dissolved into the
        // background and read as a rendering fade.
        case .root: return DS.surfaceElevated
        case .coreConcept: return DS.surfaceElevated
        case .childConcept: return branchColor.opacity(0.08)
        case .seedling: return node.isRipe ? branchColor.opacity(0.10) : DS.surface.opacity(0.6)
        case .question, .subQuestion: return node.isActive ? branchColor.opacity(0.10) : DS.surface
        case .questionGroup: return DS.surface.opacity(0.6)
        case .page: return DS.surfaceElevated
        case .material: return DS.surface
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if node.isGhost {
            // Dashed = not yet real (the seedling register).
            shape.strokeBorder(
                branchColor.opacity(isHovered ? 0.65 : 0.5),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        } else if node.kind == .questionGroup {
            shape.strokeBorder(DS.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else if node.kind == .seedling {
            // Dashed = not yet a page; the ripe accent says "ready to develop".
            shape.strokeBorder(
                node.isRipe ? branchColor.opacity(0.55) : DS.borderSubtle,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        } else {
            shape.stroke(borderColor, lineWidth: node.isActive || isGhostHighlighted ? 1.5 : 0.5)
        }
    }

    private var borderColor: Color {
        if node.isActive || isGhostHighlighted { return branchColor }
        if node.isSection { return branchColor.opacity(0.3) }
        switch node.kind {
        case .root: return DS.sepiaBorder
        case .coreConcept: return branchColor.opacity(0.45)
        case .childConcept: return branchColor.opacity(0.3)
        case .seedling, .question, .subQuestion, .page, .material: return DS.borderSubtle
        case .questionGroup: return DS.borderSubtle
        }
    }

    private var shadowOpacity: Double {
        if node.isGhost { return isHovered ? 0.06 : 0.02 }
        switch node.kind {
        case .question, .subQuestion, .questionGroup, .seedling: return isHovered ? 0.06 : 0.02
        default: return isHovered ? 0.10 : 0.05
        }
    }

    private var helpText: String {
        node.isGhost ? "Proposed section — accept to group, ✕ to dismiss" : node.title
    }

    private var accessibilityText: String {
        if node.isGhost { return "Proposed section \(node.title), grouping \(node.subtitle ?? "")" }
        switch node.kind {
        case .root: return "Topic: \(node.title)"
        case .coreConcept, .childConcept: return "Open concept page \(node.title)"
        case .seedling: return "Seedling \(node.title)\(node.isRipe ? ", ripe for development" : "")"
        case .question, .subQuestion: return "Open question \(node.title)"
        case .questionGroup: return "\(node.title)"
        case .page: return "Open page \(node.title)"
        case .material: return "Open \(node.title)"
        }
    }
}

/// Type-erased insettable shape so cards can switch between capsule and rect.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetAmount: CGFloat

    init<S: InsettableShape>(_ shape: S, inset: CGFloat = 0) {
        self.pathBuilder = { rect in shape.path(in: rect) }
        self.insetAmount = inset
    }

    private init(pathBuilder: @escaping @Sendable (CGRect) -> Path, inset: CGFloat) {
        self.pathBuilder = pathBuilder
        self.insetAmount = inset
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        AnyInsettableShape(pathBuilder: pathBuilder, inset: insetAmount + amount)
    }
}
