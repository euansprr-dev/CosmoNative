// CosmoOS/UI/FocusMode/SwipeStudy/StructureMapView.swift
// Content structure visualization for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Structure Map View

struct StructureMapView: View {
    let frameworkType: SwipeFrameworkType?
    let sections: [SwipeSection]
    var showsHeader: Bool = true
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
        VStack(alignment: .leading, spacing: DS.space12) {
            if showsHeader {
                MarginaliaLabel("STRUCTURE")
            }

            if validSections.isEmpty {
                placeholderView
            } else {
                structureContent
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            animateBlocks()
        }
    }

    // MARK: - Structure Content

    private var structureContent: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if let fw = frameworkType {
                HStack(spacing: DS.space6) {
                    Text(fw.displayName)
                        .font(DS.dateSerif)
                        .italic()
                    Text(fw.description)
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                        .lineLimit(1)
                }
                .foregroundStyle(fw.color.opacity(0.85))
            }

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let spacing: CGFloat = 3
                let totalSpacing = spacing * CGFloat(max(0, validSections.count - 1))
                let usableWidth = availableWidth - totalSpacing

                HStack(spacing: spacing) {
                    ForEach(Array(validSections.enumerated()), id: \.element.id) { index, section in
                        let relSize = section.relativeSize(totalLength: totalLength)
                        let blockWidth = max(24, usableWidth * CGFloat(relSize))
                        let blockColor = section.emotion?.color ?? defaultColor(for: index)
                        let isHovered = hoveredSection == section.id

                        Button {
                            let position = sectionStartPosition(for: section, in: validSections)
                            onSectionTap?(position)
                        } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(blockColor.opacity(isHovered ? 0.82 : 0.48))
                                .frame(height: isHovered ? 6 : 4)
                                .scaleEffect(x: appeared[section.id] == true ? 1 : 0.08, anchor: .leading)
                        }
                        .buttonStyle(.plain)
                        .frame(width: blockWidth)
                        .disabled(onSectionTap == nil)
                        .onHover { hovering in
                            withAnimation(ProMotionSprings.hover) {
                                hoveredSection = hovering ? section.id : nil
                            }
                        }
                        .animation(ProMotionSprings.hover, value: isHovered)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            VStack(alignment: .leading, spacing: DS.space8) {
                ForEach(Array(validSections.enumerated()), id: \.element.id) { index, section in
                    let blockColor = section.emotion?.color ?? defaultColor(for: index)
                    HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                        Circle()
                            .fill(blockColor.opacity(0.75))
                            .frame(width: 5, height: 5)
                        Text(section.label.lowercased())
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                        Spacer()
                        Text(section.purpose.lowercased())
                            .font(DS.caption2)
                            .foregroundStyle(DS.inkFaded)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func defaultColor(for index: Int) -> Color {
        let colors: [Color] = [
            DS.entitySwipe,
            DS.entityIdea,
            DS.entityResearch,
            DS.entityContent,
            DS.entityConnection,
            DS.gilt,
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
        Text("structure analysis pending...")
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space20)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        DS.bg.ignoresSafeArea()
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
#endif
