// CosmoOS/UI/FocusMode/Inquiry/MindMap/InquiryMindMapNodeCard.swift
// Node cards for the mind map: serif display titles, status-aware accents.

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
        case .question: return CGSize(width: 210, height: 64)
        case .subQuestion: return CGSize(width: 190, height: 56)
        case .concept: return CGSize(width: 150, height: 40)
        }
    }

    var body: some View {
        Button {
            onSelect(node)
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var cardLabel: some View {
        let size = Self.size(for: node)
        VStack(alignment: .leading, spacing: 2) {
            Text(node.title)
                .font(titleFont)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(node.kind == .concept ? 1 : 2)
                .multilineTextAlignment(.leading)
            if let subtitle = node.subtitle {
                Text(subtitle)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(background, in: shape)
        .overlay(shape.stroke(borderColor, lineWidth: node.isActive ? 1.5 : 0.5))
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.05), radius: isHovered ? 10 : 6, y: 3)
        .contentShape(shape)
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.snappy, value: isHovered)
    }

    private var titleFont: Font {
        switch node.kind {
        case .root: return .system(.title3, design: .serif).weight(.semibold)
        case .question: return .system(.body, design: .serif)
        case .subQuestion: return .system(.callout, design: .serif)
        case .concept: return CosmoTypography.label
        }
    }

    private var shape: some InsettableShape {
        node.kind == .concept
            ? AnyInsettableShape(Capsule())
            : AnyInsettableShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
    }

    private var background: Color {
        switch node.kind {
        case .root: return DS.vellum
        case .concept: return branchColor.opacity(0.08)
        case .question, .subQuestion: return node.isActive ? branchColor.opacity(0.08) : DS.surfaceElevated
        }
    }

    private var borderColor: Color {
        if node.isActive { return branchColor }
        switch node.kind {
        case .root: return DS.sepiaBorder
        case .concept: return branchColor.opacity(0.3)
        case .question, .subQuestion: return DS.borderSubtle
        }
    }

    private var accessibilityText: String {
        switch node.kind {
        case .root: return "Topic: \(node.title)"
        case .concept: return "Open concept page \(node.title)"
        case .question, .subQuestion: return "Open question \(node.title)"
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
