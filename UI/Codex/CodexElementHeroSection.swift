// CosmoOS/UI/Codex/CodexElementHeroSection.swift
// Dramatic hero section for Codex element detail views — Akashic manuscript aesthetic.
// April 2026 — Akashic Records Premium Redesign

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
            DS.vellum
            RadialGradient(
                colors: [categoryColor.opacity(0.03), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )
        }
        .filmGrain(opacity: 0.02)
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
            AkashicCategoryDiamond(
                icon: element.category.icon,
                color: categoryColor,
                size: .large
            )
            Text(element.category.displayName)
                .font(DS.callout)
                .foregroundStyle(categoryColor)
        }
    }

    private var elementName: some View {
        Text(element.canonicalName)
            .font(DS.displaySerif)
            .foregroundStyle(DS.inkWash)
    }

    private var badgeRow: some View {
        HStack(spacing: DS.space8) {
            categoryDescription
            if !element.variants.isEmpty {
                variantCount
            }
        }
    }

    private var categoryDescription: some View {
        Text(element.category.description)
            .font(DS.dateSerif)
            .foregroundStyle(DS.inkFaded)
            .italic()
    }

    private var variantCount: some View {
        Text("\(element.variants.count) variants")
            .font(DS.smallCaps)
            .foregroundStyle(DS.giltMuted)
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
