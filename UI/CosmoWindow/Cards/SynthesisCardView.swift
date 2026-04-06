// CosmoOS/UI/CosmoWindow/Cards/SynthesisCardView.swift
// Knowledge synthesis result card for inline chat results

import SwiftUI

struct SynthesisCardView: View {
    let data: SynthesisCardData
    @State private var sourcesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            synthesisHeader
            synthesisBody
            sourcesSection
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

    private var synthesisHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Knowledge synthesis")
            Text("Knowledge Synthesis: \(data.query)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(2)
        }
    }

    private var synthesisBody: some View {
        ScrollView {
            Text(data.synthesis)
                .font(.callout)
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourcesToggle
            if sourcesExpanded {
                sourcesList
            }
        }
    }

    private var sourcesToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                sourcesExpanded.toggle()
            }
        } label: {
            sourcesToggleLabel
        }
        .buttonStyle(.plain)
    }

    private var sourcesToggleLabel: some View {
        HStack(spacing: 4) {
            Text("Sources (\(data.sources.count))")
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.accent)
            Image(systemName: sourcesExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(DS.accent)
                .accessibilityLabel(sourcesExpanded ? "Collapse sources" : "Expand sources")
        }
    }

    private var sourcesList: some View {
        VStack(spacing: 8) {
            ForEach(data.sources, id: \.uuid) { source in
                AtomCardView(data: source)
            }
        }
    }
}
