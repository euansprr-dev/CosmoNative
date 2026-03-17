// CosmoOS/UI/CommandK/CommandKPremiumChrome.swift
// Shared Greenhouse chrome for the Command-K overlay

import SwiftUI

enum CommandKMetrics {
    static let overlayCornerRadius: CGFloat = 24
    static let searchBarHeight: CGFloat = 60
    static let tabBarHeight: CGFloat = 44
    static let contentPadding: CGFloat = 24
    static let toolbarSpacing: CGFloat = 12
    static let toolbarChipHeight: CGFloat = 32
    static let toolbarChipRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 14
    static let sectionCornerRadius: CGFloat = 18
    static let cardSpacing: CGFloat = 18
}

private struct CommandKToolbarChipModifier: ViewModifier {
    let isActive: Bool
    let activeFill: Color
    let activeBorder: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: CommandKMetrics.toolbarChipHeight)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? activeFill : DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isActive ? activeBorder : DS.borderSubtle, lineWidth: 1)
            )
    }
}

private struct CommandKToolbarGroupModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }
}

private struct CommandKGalleryCardModifier: ViewModifier {
    let isHovered: Bool
    let isSelected: Bool
    let accentColor: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? accentColor.opacity(0.38) : (isHovered ? DS.borderActive : DS.border),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                accentColor
                    .frame(height: 2)
                    .opacity(isHovered ? 1.0 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(isHovered ? 0.07 : 0.04),
                radius: isHovered ? 20 : 8,
                x: 0,
                y: isHovered ? 6 : 2
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.04 : 0.02),
                radius: isHovered ? 6 : 2,
                x: 0,
                y: isHovered ? 2 : 1
            )
    }
}

private struct CommandKSectionModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .dsRestingShadow()
    }
}

extension View {
    func commandKToolbarChip(
        isActive: Bool = false,
        activeFill: Color = DS.accentSoft,
        activeBorder: Color = DS.accent.opacity(0.18),
        cornerRadius: CGFloat = CommandKMetrics.toolbarChipRadius
    ) -> some View {
        modifier(
            CommandKToolbarChipModifier(
                isActive: isActive,
                activeFill: activeFill,
                activeBorder: activeBorder,
                cornerRadius: cornerRadius
            )
        )
    }

    func commandKToolbarGroup(
        cornerRadius: CGFloat = CommandKMetrics.toolbarChipRadius
    ) -> some View {
        modifier(CommandKToolbarGroupModifier(cornerRadius: cornerRadius))
    }

    func commandKGalleryCardChrome(
        isHovered: Bool,
        isSelected: Bool,
        accentColor: Color,
        cornerRadius: CGFloat = CommandKMetrics.cardCornerRadius
    ) -> some View {
        modifier(
            CommandKGalleryCardModifier(
                isHovered: isHovered,
                isSelected: isSelected,
                accentColor: accentColor,
                cornerRadius: cornerRadius
            )
        )
    }

    func commandKSectionChrome(
        cornerRadius: CGFloat = CommandKMetrics.sectionCornerRadius
    ) -> some View {
        modifier(CommandKSectionModifier(cornerRadius: cornerRadius))
    }
}
