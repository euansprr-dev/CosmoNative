// CosmoOS/UI/Codex/CodexCategorySection.swift
// Category section header for grouped Codex layout.

import SwiftUI

struct CodexCategorySectionHeader: View {
    let category: CodexElementCategory
    let count: Int
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            categoryIcon
            categoryInfo
            Spacer()
            countBadge
        }
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space4)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var categoryIcon: some View {
        Image(systemName: category.icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(category.color)
            .frame(width: 32, height: 32)
            .background(
                category.color.opacity(isHovered ? 0.18 : 0.1),
                in: Circle()
            )
            .accessibilityHidden(true)
    }

    private var categoryInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(category.displayName)
                .font(DS.title3)
                .fontWeight(.semibold)
                .foregroundStyle(DS.text)
            Text(category.description)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var countBadge: some View {
        Text("\(count)")
            .font(DS.caption)
            .fontWeight(.medium)
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Category Section Divider

struct CodexCategorySectionDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.15))
            .frame(height: 1)
    }
}
