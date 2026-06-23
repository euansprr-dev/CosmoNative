// CosmoOS/UI/CosmoWindow/Cards/AtomListView.swift
// Search results list for inline chat results

import SwiftUI

struct AtomListView: View {
    let data: AtomListData
    @State private var showAll = false

    private var visibleAtoms: [AtomCardData] {
        showAll ? data.atoms : Array(data.atoms.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            atomList
            showMoreButton
        }
        .padding(16)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: DS.text.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        Text("\(data.totalCount) results for '\(data.query)'")
            .font(.caption.weight(.medium))
            .foregroundStyle(DS.textSecondary)
    }

    private var atomList: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
            ForEach(visibleAtoms, id: \.uuid) { atom in
                AtomCardView(data: atom)
            }
        }
    }

    @ViewBuilder
    private var showMoreButton: some View {
        if data.totalCount > data.atoms.count || (!showAll && data.atoms.count > 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAll.toggle()
                }
            } label: {
                showMoreLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var showMoreLabel: some View {
        HStack(spacing: 4) {
            Text(showAll ? "Show less" : "Show more")
                .font(.caption.weight(.medium))
            Image(systemName: showAll ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .accessibilityLabel(showAll ? "Collapse results" : "Expand results")
        }
        .foregroundStyle(DS.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DS.accentSoft.opacity(0.5))
        .clipShape(.rect(cornerRadius: 8))
    }
}
