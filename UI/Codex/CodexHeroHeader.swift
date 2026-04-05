// CosmoOS/UI/Codex/CodexHeroHeader.swift
// Dramatic hero header for the Content Physics Codex main page.

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
                    DS.surfaceElevated
                    ambientGradient
                }
                .filmGrain(opacity: 0.02)
            }
            .onAppear {
                withAnimation(ProMotionSprings.cardEntrance) {
                    appeared = true
                }
            }
    }

    private var ambientGradient: some View {
        LinearGradient(
            colors: [
                CodexElementCategory.speechAct.color.opacity(0.04),
                CodexElementCategory.readerDelta.color.opacity(0.03),
                CodexElementCategory.physicsEvent.color.opacity(0.04),
                .clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            Text("Content Physics Codex")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
            Text("The complete language of viral content")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .italic()
                .opacity(appeared ? 1 : 0)
            statsRow
        }
    }

    private var statsRow: some View {
        HStack(spacing: DS.space8) {
            statBadge(icon: "atom", text: "\(elementCount) elements")
            statBadge(icon: "square.grid.3x3", text: "\(categoryCount) categories")
        }
    }

    private func statBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(text)
                .font(DS.caption)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.accent.opacity(0.08), in: Capsule())
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
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField("Search elements...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DS.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
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
        .font(DS.caption)
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.accent.opacity(0.1), in: Capsule())
    }

    private var gridToggle: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { showGrid.toggle() }
        } label: {
            Image(systemName: showGrid ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 14))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 32, height: 32)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showGrid ? "Switch to list view" : "Switch to grid view")
    }
}

// MARK: - Category Color Divider

struct CodexCategoryDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                CodexElementCategory.speechAct.color.opacity(0.2),
                CodexElementCategory.readerDelta.color.opacity(0.15),
                CodexElementCategory.technique.color.opacity(0.2),
                CodexElementCategory.physicsEvent.color.opacity(0.15),
                CodexElementCategory.arcShape.color.opacity(0.2),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}
