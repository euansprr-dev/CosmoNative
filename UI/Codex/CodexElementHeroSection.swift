// CosmoOS/UI/Codex/CodexElementHeroSection.swift
// Dramatic hero section for Codex element detail views.

import SwiftUI

struct CodexElementHeroSection: View {
    let element: CodexElement
    @State private var appeared = false

    private var categoryColor: Color { element.category.color }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
            heroContent
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                appeared = true
            }
        }
    }

    // MARK: - Background

    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: [categoryColor.opacity(0.05), categoryColor.opacity(0.02), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .filmGrain(opacity: 0.015)
        }
    }

    // MARK: - Content

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: DS.space24) {
            titleColumn
            Spacer()
            frequencyRing
        }
        .padding(.horizontal, DS.space32)
        .padding(.vertical, DS.space24)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            categoryIconRow
            elementName
            badgeRow
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    private var categoryIconRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: element.category.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(categoryColor)
                .frame(width: 40, height: 40)
                .background(categoryColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            Text(element.category.displayName)
                .font(DS.callout)
                .foregroundStyle(categoryColor)
        }
    }

    private var elementName: some View {
        Text(element.canonicalName)
            .font(DS.display)
            .foregroundStyle(DS.text)
    }

    private var badgeRow: some View {
        HStack(spacing: DS.space8) {
            categoryBadge
            if !element.variants.isEmpty {
                variantCount
            }
        }
    }

    private var categoryBadge: some View {
        Text(element.category.description)
            .font(DS.caption)
            .foregroundStyle(DS.textSecondary)
            .italic()
    }

    private var variantCount: some View {
        Text("\(element.variants.count) variants")
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.surface, in: Capsule())
    }

    private var frequencyRing: some View {
        CodexFrequencyIndicator(
            frequency: element.frequency,
            color: categoryColor,
            mode: .full
        )
        .opacity(appeared ? 1 : 0)
        .animation(ProMotionSprings.cardEntrance.delay(0.1), value: appeared)
    }
}
