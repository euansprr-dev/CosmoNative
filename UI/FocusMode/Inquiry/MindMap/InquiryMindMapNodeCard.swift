// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapNodeCard.swift
// Node cards for the mind map. Concept-first visual hierarchy: concepts are
// the substantial cards (core = large with a branch-color accent bar, child =
// medium tinted), questions are small muted satellites, and question groups
// read as quiet dashed buckets.

import SwiftUI

@MainActor
struct InquiryMindMapNodeCard: View {
    let node: MindMapNode
    let branchColor: Color
    let onSelect: (MindMapNode) -> Void

    @State private var isHovered = false

    static func size(for node: MindMapNode) -> CGSize {
        switch node.kind {
        case .root: return CGSize(width: 230, height: 72)
        case .coreConcept: return CGSize(width: 220, height: 64)
        case .childConcept: return CGSize(width: 180, height: 52)
        case .question: return CGSize(width: 232, height: 40)
        case .subQuestion: return CGSize(width: 208, height: 36)
        case .questionGroup: return CGSize(width: 170, height: 44)
        }
    }

    var body: some View {
        Button {
            onSelect(node)
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .overlay(alignment: .topLeading) { hoverRevealCard }
        .zIndex(isHovered ? 50 : 0)
        .help(node.title)
        .accessibilityLabel(accessibilityText)
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
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(node.isConcept || node.kind == .root ? 2 : 1)
                    .multilineTextAlignment(.leading)
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(background, in: shape)
        .overlay(borderOverlay)
        .shadow(color: .black.opacity(shadowOpacity), radius: isHovered ? 10 : 6, y: 3)
        .contentShape(shape)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.snappy, value: isHovered)
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        switch node.kind {
        case .coreConcept:
            RoundedRectangle(cornerRadius: 2)
                .fill(branchColor)
                .frame(width: 3, height: 34)
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
        case .root, .childConcept:
            EmptyView()
        }
    }

    private var titleFont: Font {
        switch node.kind {
        case .root: return .system(.title3, design: .serif).weight(.semibold)
        case .coreConcept: return .system(.body, design: .serif).weight(.semibold)
        case .childConcept: return .system(.callout, design: .serif)
        case .question, .subQuestion: return CosmoTypography.labelSmall
        case .questionGroup: return CosmoTypography.label
        }
    }

    private var titleColor: Color {
        switch node.kind {
        case .question, .subQuestion, .questionGroup: return CosmoColors.textSecondary
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
        switch node.kind {
        // surfaceElevated, not vellum: vellum on the parchment page differs
        // by a hair — the root card's right half dissolved into the
        // background and read as a rendering fade.
        case .root: return DS.surfaceElevated
        case .coreConcept: return DS.surfaceElevated
        case .childConcept: return branchColor.opacity(0.08)
        case .question, .subQuestion: return node.isActive ? branchColor.opacity(0.10) : DS.surface
        case .questionGroup: return DS.surface.opacity(0.6)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if node.kind == .questionGroup {
            shape.strokeBorder(DS.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.stroke(borderColor, lineWidth: node.isActive ? 1.5 : 0.5)
        }
    }

    private var borderColor: Color {
        if node.isActive { return branchColor }
        switch node.kind {
        case .root: return DS.sepiaBorder
        case .coreConcept: return branchColor.opacity(0.45)
        case .childConcept: return branchColor.opacity(0.3)
        case .question, .subQuestion: return DS.borderSubtle
        case .questionGroup: return DS.borderSubtle
        }
    }

    private var shadowOpacity: Double {
        switch node.kind {
        case .question, .subQuestion, .questionGroup: return isHovered ? 0.06 : 0.02
        default: return isHovered ? 0.10 : 0.05
        }
    }

    private var accessibilityText: String {
        switch node.kind {
        case .root: return "Topic: \(node.title)"
        case .coreConcept, .childConcept: return "Open concept page \(node.title)"
        case .question, .subQuestion: return "Open question \(node.title)"
        case .questionGroup: return "\(node.title)"
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
