// CosmoOS/Canvas/Components/ConnectionSectionNavigator.swift
// Premium section navigator for Connection floating blocks
// Apple-grade segmented control with animated selection indicator

import SwiftUI

/// Premium segmented control for navigating mental model sections.
/// Features animated selection indicator, completion dots, and haptic feedback.
struct ConnectionSectionNavigator: View {
    let model: ConnectionMentalModel?
    @Binding var selectedSection: MentalModelSection?
    let onSectionTap: (MentalModelSection) -> Void
    
    @Namespace private var animation
    @State private var hoveredSection: MentalModelSection? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(MentalModelSection.allSections) { section in
                SectionTab(
                    section: section,
                    isSelected: selectedSection?.id == section.id,
                    isHovered: hoveredSection?.id == section.id,
                    isFilled: model?.hasContent(for: section) ?? false,
                    namespace: animation
                ) {
                    withAnimation(BlockAnimations.selection) {
                        selectedSection = section
                    }
                    onSectionTap(section)
                    // Haptic feedback
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .levelChange,
                        performanceTime: .default
                    )
                }
                .onHover { isHovered in
                    withAnimation(BlockAnimations.hover) {
                        hoveredSection = isHovered ? section : nil
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CosmoColors.mistGrey.opacity(0.4))
        )
    }
}

// MARK: - Section Tab

private struct SectionTab: View {
    let section: MentalModelSection
    let isSelected: Bool
    let isHovered: Bool
    let isFilled: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Icon
                Image(systemName: section.icon)
                    .font(.system(size: 10, weight: .medium))
                
                // Short name (always visible) or full name when selected/hovered
                if isSelected || isHovered {
                    Text(section.name)
                        .font(CosmoTypography.labelSmall)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                            removal: .opacity
                        ))
                } else {
                    Text(section.shortName)
                        .font(CosmoTypography.labelSmall)
                }
                
                // Completion indicator
                Circle()
                    .fill(isFilled ? section.color : CosmoColors.glassGrey)
                    .frame(width: 5, height: 5)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, isSelected || isHovered ? 10 : 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .shadow(color: section.color.opacity(0.2), radius: 4, y: 2)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CosmoColors.softWhite.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(BlockAnimations.selection, value: isSelected)
        .animation(BlockAnimations.hover, value: isHovered)
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return section.color
        } else if isFilled {
            return CosmoColors.textSecondary
        } else {
            return CosmoColors.textTertiary
        }
    }
}

// MARK: - Compact Section Navigator (For smaller blocks)

/// More compact version for use in collapsed block mode
struct CompactSectionNavigator: View {
    let model: ConnectionMentalModel?
    @Binding var selectedSection: MentalModelSection?
    let onSectionTap: (MentalModelSection) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MentalModelSection.allSections) { section in
                    CompactSectionPill(
                        section: section,
                        isSelected: selectedSection?.id == section.id,
                        isFilled: model?.hasContent(for: section) ?? false
                    ) {
                        withAnimation(BlockAnimations.selection) {
                            selectedSection = section
                        }
                        onSectionTap(section)
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .levelChange,
                            performanceTime: .default
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Compact Section Pill

private struct CompactSectionPill: View {
    let section: MentalModelSection
    let isSelected: Bool
    let isFilled: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 9, weight: .medium))
                
                // Show name when selected or hovered
                if isSelected || isHovered || isFilled {
                    Text(section.name)
                        .font(CosmoTypography.caption)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? section.color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .animation(.spring(response: 0.2), value: isSelected)
        .onHover { isHovered = $0 }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return section.color
        } else if isFilled {
            return section.color.opacity(0.8)
        } else {
            return CosmoColors.textTertiary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return section.color.opacity(0.15)
        } else if isFilled {
            return section.color.opacity(isHovered ? 0.12 : 0.08)
        } else {
            return CosmoColors.glassGrey.opacity(isHovered ? 0.4 : 0.3)
        }
    }
}

// MARK: - Section Indicator Dots (Ultra-compact for preview)

/// Ultra-compact section indicators showing just completion dots
struct SectionIndicatorDots: View {
    let model: ConnectionMentalModel?
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(MentalModelSection.allSections) { section in
                Circle()
                    .fill(dotColor(for: section))
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private func dotColor(for section: MentalModelSection) -> Color {
        let isFilled = model?.hasContent(for: section) ?? false
        return isFilled ? section.color : CosmoColors.glassGrey
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionSectionNavigator_Previews: PreviewProvider {
    @State static var selectedSection: MentalModelSection? = nil
    
    static var sampleModel: ConnectionMentalModel {
        var model = ConnectionMentalModel()
        model.goal = "Test goal content"
        model.problem = "Test problem"
        return model
    }
    
    static var previews: some View {
        VStack(spacing: 40) {
            // Full navigator
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Navigator")
                    .font(CosmoTypography.label)
                ConnectionSectionNavigator(
                    model: sampleModel,
                    selectedSection: $selectedSection,
                    onSectionTap: { _ in }
                )
            }
            
            // Compact navigator
            VStack(alignment: .leading, spacing: 8) {
                Text("Compact Navigator")
                    .font(CosmoTypography.label)
                CompactSectionNavigator(
                    model: sampleModel,
                    selectedSection: $selectedSection,
                    onSectionTap: { _ in }
                )
            }
            
            // Indicator dots
            VStack(alignment: .leading, spacing: 8) {
                Text("Indicator Dots")
                    .font(CosmoTypography.label)
                SectionIndicatorDots(model: sampleModel)
            }
        }
        .padding(40)
        .background(CosmoColors.softWhite)
        .frame(width: 500, height: 400)
    }
}
#endif
