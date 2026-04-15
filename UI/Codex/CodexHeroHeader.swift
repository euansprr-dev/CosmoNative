// CosmoOS/UI/Codex/CodexHeroHeader.swift
// Dramatic hero header for the Content Physics Codex — Akashic manuscript aesthetic.
// April 2026 — Akashic Records Premium Redesign

import SwiftUI

struct CodexHeroHeader: View {
    @Binding var searchQuery: String
    let elementCount: Int
    let categoryCount: Int
    let isImporting: Bool
    let onImport: () -> Void

    @Binding var showGrid: Bool
    @State private var appeared = false

    var body: some View {
        heroContent
            .background {
                ZStack {
                    DS.vellum
                    RadialGradient(
                        colors: [DS.giltSoft.opacity(0.15), .clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 300
                    )
                }
                .filmGrain(opacity: 0.025)
            }
            .onAppear {
                withAnimation(ProMotionSprings.cardEntrance) {
                    appeared = true
                }
            }
    }

    // MARK: - Content

    private var heroContent: some View {
        HStack(alignment: .bottom) {
            titleColumn
            Spacer()
            controlsColumn
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space16)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            heroTitle
            heroSubtitle
            statsRow
        }
    }

    private var heroTitle: some View {
        Text("Content Physics Codex")
            .font(DS.displaySerif)
            .foregroundStyle(DS.inkWash)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
    }

    private var heroSubtitle: some View {
        Text("The complete language of viral content")
            .font(DS.dateSerif)
            .foregroundStyle(DS.inkFaded)
            .italic()
            .opacity(appeared ? 1 : 0)
    }

    private var statsRow: some View {
        HStack(spacing: 4) {
            Text("\(elementCount) elements")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
            Text("\u{00B7}")
                .foregroundStyle(DS.gilt)
            Text("\(categoryCount) categories")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
        }
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        HStack(spacing: DS.space12) {
            searchField
            importButton
            gridToggle
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(DS.inkFaded)
                .accessibilityHidden(true)
            TextField("Search elements...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DS.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .frame(width: 240)
    }

    private var importButton: some View {
        Button(action: onImport) {
            importButtonLabel
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
    }

    private var importButtonLabel: some View {
        HStack(spacing: 4) {
            if isImporting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.down.circle")
                    .accessibilityHidden(true)
            }
            Text(isImporting ? "Importing..." : "Import")
        }
        .font(DS.smallCaps)
        .foregroundStyle(DS.giltMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.giltMuted, lineWidth: 0.5)
        )
    }

    private var gridToggle: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { showGrid.toggle() }
        } label: {
            Image(systemName: showGrid ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 14))
                .foregroundStyle(DS.inkFaded)
                .frame(width: 32, height: 32)
                .background(DS.vellumDeep, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.sepiaBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showGrid ? "Switch to list view" : "Switch to grid view")
    }
}

// MARK: - Category Color Divider

struct CodexCategoryDivider: View {
    var body: some View {
        AkashicSectionDivider()
    }
}
