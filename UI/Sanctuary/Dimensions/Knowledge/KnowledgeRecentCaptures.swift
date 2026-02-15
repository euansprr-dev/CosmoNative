// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeRecentCaptures.swift
// Recent Captures - Knowledge capture carousel and cards
// Phase 7: Following SANCTUARY_UI_SPEC_V2.md section 3.5

import SwiftUI

// MARK: - Recent Captures Panel

/// Panel showing recent knowledge captures
public struct KnowledgeRecentCaptures: View {

    // MARK: - Properties

    let captures: [KnowledgeCapture]
    let onCaptureTap: (KnowledgeCapture) -> Void
    let onViewAll: () -> Void

    @State private var isVisible: Bool = false

    // MARK: - Initialization

    public init(
        captures: [KnowledgeCapture],
        onCaptureTap: @escaping (KnowledgeCapture) -> Void,
        onViewAll: @escaping () -> Void
    ) {
        self.captures = captures
        self.onCaptureTap = onCaptureTap
        self.onViewAll = onViewAll
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Recent Captures")
                .font(OnyxTypography.label)
                .foregroundColor(SanctuaryColors.Text.tertiary)
                .tracking(2)

            // Captures carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SanctuaryLayout.Spacing.md) {
                    ForEach(Array(captures.prefix(4).enumerated()), id: \.element.id) { index, capture in
                        CaptureCard(capture: capture)
                            .onTapGesture { onCaptureTap(capture) }
                            .opacity(isVisible ? 1 : 0)
                            .offset(x: isVisible ? 0 : 20)
                            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.08), value: isVisible)
                    }

                    // View more card
                    viewMoreCard
                        .opacity(isVisible ? 1 : 0)
                        .offset(x: isVisible ? 0 : 20)
                        .animation(.easeOut(duration: 0.3).delay(0.35), value: isVisible)
                }
                .padding(.horizontal, SanctuaryLayout.Spacing.xs)
                .padding(.vertical, SanctuaryLayout.Spacing.xs)
            }

            // Scroll indicator
            HStack {
                Spacer()

                Text("◀ ═══════════════════════════════════════════════ ▶")
                    .font(.system(size: 8))
                    .foregroundColor(SanctuaryColors.Glass.border)

                Spacer()
            }
        }
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }

    private var viewMoreCard: some View {
        Button(action: onViewAll) {
            VStack(spacing: SanctuaryLayout.Spacing.md) {
                Text("+ MORE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)

                Text("View")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("\(captures.count)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)

                Text("captures")
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            }
            .frame(width: 120, height: 180)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                    .fill(SanctuaryColors.Glass.highlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                            .stroke(SanctuaryColors.Dimensions.knowledge.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Capture Card

/// Individual capture card
public struct CaptureCard: View {

    let capture: KnowledgeCapture

    @State private var isHovered: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Type header
            HStack {
                Text("\(capture.type.emoji) \(capture.type.displayName.uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(typeColor)

                Spacer()
            }

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Title
            Text(capture.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SanctuaryColors.Text.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer()

            // Tags
            if !capture.tags.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8))
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    Text(capture.tags.joined(separator: ", "))
                        .font(.system(size: 9))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                        .lineLimit(1)
                }
            }

            // Connections
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 8))
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)

                Text("\(capture.connectionCount) connections")
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            // Time ago
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Text(capture.timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .frame(width: 180, height: 180)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.highlight)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(isHovered ? typeColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(SanctuarySprings.hover, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var typeColor: Color {
        Color(hex: capture.type == .paper ? "#3B82F6" :
                   capture.type == .idea ? "#F59E0B" :
                   capture.type == .bookmark ? "#10B981" : "#8B5CF6")
    }
}

// MARK: - Capture Detail View

/// Detailed view of a capture
public struct CaptureDetailView: View {

    let capture: KnowledgeCapture
    let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            HStack {
                Text("\(capture.type.emoji) \(capture.type.displayName.uppercased())")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(typeColor)

                Spacer()

                Text(capture.timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Title
            Text(capture.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.primary)

            Rectangle()
                .fill(SanctuaryColors.Glass.border)
                .frame(height: 1)

            // Preview
            Text(capture.preview)
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.secondary)
                .lineLimit(4)

            // Tags
            if !capture.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(capture.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Dimensions.knowledge)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
                            )
                    }
                }
            }

            // Stats
            HStack(spacing: SanctuaryLayout.Spacing.xl) {
                statItem(icon: "link", value: "\(capture.connectionCount)", label: "connections")

                if capture.sourceURL != nil {
                    Spacer()
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text("Open Source")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(SanctuaryColors.Dimensions.knowledge)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Actions
            HStack(spacing: SanctuaryLayout.Spacing.md) {
                actionButton(icon: "link.badge.plus", label: "Link")
                actionButton(icon: "tag", label: "Tag")
                actionButton(icon: "square.and.arrow.up", label: "Share")
                actionButton(icon: "trash", label: "Delete")
            }
        }
        .padding(SanctuaryLayout.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.lg)
                        .stroke(typeColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Dimensions.knowledge)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(SanctuaryColors.Text.primary)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(SanctuaryColors.Text.tertiary)
        }
    }

    private func actionButton(icon: String, label: String) -> some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))

                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(SanctuaryColors.Dimensions.knowledge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Dimensions.knowledge.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var typeColor: Color {
        Color(hex: capture.type == .paper ? "#3B82F6" :
                   capture.type == .idea ? "#F59E0B" :
                   capture.type == .bookmark ? "#10B981" : "#8B5CF6")
    }
}

// MARK: - Captures Summary Compact

/// Compact captures summary
public struct CapturesSummaryCompact: View {

    let captures: [KnowledgeCapture]
    let onExpand: () -> Void

    public init(captures: [KnowledgeCapture], onExpand: @escaping () -> Void) {
        self.captures = captures
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
            // Header
            HStack {
                Text("Recent Captures")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .tracking(1)

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 10))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(SanctuaryColors.Dimensions.knowledge)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Mini captures list
            VStack(spacing: SanctuaryLayout.Spacing.xs) {
                ForEach(captures.prefix(3)) { capture in
                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Text(capture.type.emoji)
                            .font(.system(size: 12))

                        Text(capture.title)
                            .font(.system(size: 11))
                            .foregroundColor(SanctuaryColors.Text.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(capture.timeAgo)
                            .font(.system(size: 9))
                            .foregroundColor(SanctuaryColors.Text.tertiary)
                    }
                }
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.md)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Flow Layout

fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct KnowledgeRecentCaptures_Previews: PreviewProvider {
    static var previews: some View {
        let data = KnowledgeDimensionData.preview

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    KnowledgeRecentCaptures(
                        captures: data.recentCaptures,
                        onCaptureTap: { _ in },
                        onViewAll: {}
                    )

                    CapturesSummaryCompact(
                        captures: data.recentCaptures,
                        onExpand: {}
                    )

                    if let capture = data.recentCaptures.first {
                        CaptureDetailView(
                            capture: capture,
                            onDismiss: {}
                        )
                        .frame(maxWidth: 400)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}
#endif
