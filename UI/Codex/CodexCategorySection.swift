// CosmoOS/UI/Codex/CodexCategorySection.swift
// Category section header for grouped Codex layout.
// April 2026 — Akashic Records Premium Redesign

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
            countLabel
        }
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space4)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var categoryIcon: some View {
        AkashicCategoryDiamond(
            icon: category.icon,
            color: category.color,
            size: .medium
        )
    }

    private var categoryInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(category.displayName)
                .font(DS.title3)
                .fontWeight(.semibold)
                .fontDesign(.serif)
                .foregroundStyle(DS.inkWash)
            Text(category.description)
                .font(DS.caption)
                .foregroundStyle(DS.inkFaded)
        }
    }

    private var countLabel: some View {
        Text("\(count) entries")
            .font(DS.smallCaps)
            .foregroundStyle(DS.giltMuted)
    }
}

// MARK: - Category Section Divider

struct CodexCategorySectionDivider: View {
    let color: Color

    var body: some View {
        AkashicSectionDivider()
    }
}
