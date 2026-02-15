// CosmoOS/UI/FocusMode/SwipeStudy/StructureMapView.swift
// Content structure visualization for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Structure Map View

struct StructureMapView: View {
    let frameworkType: SwipeFrameworkType?
    let sections: [SwipeSection]
    var onSectionTap: ((Double) -> Void)? = nil

    @State private var appeared: [String: Bool] = [:]
    @State private var hasAppeared = false
    @State private var hoveredSection: String? = nil

    private var totalLength: Int {
        validSections.map(\.endIndex).max() ?? 1
    }

    /// Sections filtered to only those with non-empty labels
    private var validSections: [SwipeSection] {
        sections.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("STRUCTURE")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)

            if validSections.isEmpty {
                placeholderView
            } else {
                structureContent
            }
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            animateBlocks()
        }
    }

    // MARK: - Structure Content

    private var structureContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Framework type pill
            if let fw = frameworkType {
                HStack(spacing: 6) {
                    Text(fw.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(fw.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .foregroundColor(fw.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(fw.color.opacity(0.15), in: Capsule())
            }

            // Horizontal blocks row — proportional widths within available space
            GeometryReader { geo in
                let availableWidth = geo.size.width
                let spacing: CGFloat = 4
                let totalSpacing = spacing * CGFloat(max(0, validSections.count - 1))
                let usableWidth = availableWidth - totalSpacing

                HStack(spacing: spacing) {
                    ForEach(Array(validSections.enumerated()), id: \.element.id) { index, section in
                        let relSize = section.relativeSize(totalLength: totalLength)
                        let blockWidth = max(50, usableWidth * CGFloat(relSize))
                        let blockColor = section.emotion?.color ?? defaultColor(for: index)
                        let isHovered = hoveredSection == section.id

                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(blockColor.opacity(0.25))
                                .frame(height: 60)
                                .overlay(
                                    ZStack {
                                        VStack(spacing: 2) {
                                            Text(section.label)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                        }
                                        .padding(.horizontal, 4)

                                        // Tap-to-navigate hint icon on hover
                                        if isHovered && onSectionTap != nil {
                                            VStack {
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(.white.opacity(0.3))
                                                }
                                                Spacer()
                                            }
                                            .padding(4)
                                        }
                                    }
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            isHovered ? Color.white.opacity(0.15) : blockColor.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(
                                    color: isHovered ? blockColor.opacity(0.2) : .clear,
                                    radius: isHovered ? 4 : 0
                                )
                                .scaleEffect(appeared[section.id] == true ? (isHovered ? 1.02 : 1) : 0)
                                .animation(ProMotionSprings.hover, value: isHovered)
                                .onHover { hovering in
                                    withAnimation(ProMotionSprings.hover) {
                                        hoveredSection = hovering ? section.id : nil
                                    }
                                }
                                .onTapGesture {
                                    let position = sectionStartPosition(for: section, in: validSections)
                                    onSectionTap?(position)
                                }

                            // Purpose label
                            Text(section.purpose)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                                .lineLimit(1)
                        }
                        .frame(width: blockWidth)
                    }
                }
            }
            .frame(height: 80)
        }
    }

    // MARK: - Helpers

    private func defaultColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "#818CF8"),
            Color(hex: "#38BDF8"),
            Color(hex: "#34D399"),
            Color(hex: "#FBBF24"),
            Color(hex: "#FB7185"),
            Color(hex: "#A78BFA"),
        ]
        return colors[index % colors.count]
    }

    /// Compute the cumulative start position (0.0-1.0) for a given section
    private func sectionStartPosition(for section: SwipeSection, in sections: [SwipeSection]) -> Double {
        var cumulative: Double = 0
        for s in sections {
            if s.id == section.id { return cumulative }
            cumulative += s.sizePercent ?? (1.0 / Double(sections.count))
        }
        return cumulative
    }

    private func animateBlocks() {
        for (index, section) in validSections.enumerated() {
            let delay = Double(index) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    appeared[section.id] = true
                }
            }
        }
    }

    private var placeholderView: some View {
        Text("Structure analysis pending...")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

// MARK: - Preview

#if DEBUG
struct StructureMapView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()
            StructureMapView(
                frameworkType: .aida,
                sections: [
                    SwipeSection(label: "Attention", startIndex: 0, endIndex: 50, purpose: "Hook the viewer", emotion: .curiosity),
                    SwipeSection(label: "Interest", startIndex: 50, endIndex: 150, purpose: "Build intrigue", emotion: .aspiration),
                    SwipeSection(label: "Desire", startIndex: 150, endIndex: 250, purpose: "Create want", emotion: .desire),
                    SwipeSection(label: "Action", startIndex: 250, endIndex: 300, purpose: "Drive CTA", emotion: .urgency),
                ]
            )
            .frame(width: 400)
            .padding()
        }
    }
}
#endif
