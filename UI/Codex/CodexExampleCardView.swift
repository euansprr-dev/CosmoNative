// CosmoOS/UI/Codex/CodexExampleCardView.swift
// Rich example quote card for Codex element detail views.

import SwiftUI

struct CodexExampleCardView: View {
    let example: CodexExample
    let categoryColor: Color
    let index: Int
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            quoteArea
            referenceRow
            mechanismCallout
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(categoryColor.opacity(0.12), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(ProMotionSprings.staggered(index: index)) {
                appeared = true
            }
        }
    }

    // MARK: - Quote

    private var quoteArea: some View {
        ZStack(alignment: .topLeading) {
            decorativeQuote
            Text(example.slideText)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .padding(.leading, 20)
        }
    }

    private var decorativeQuote: some View {
        Text("\u{201C}")
            .font(.system(size: 36, weight: .bold, design: .serif))
            .foregroundStyle(categoryColor.opacity(0.15))
            .offset(x: -4, y: -8)
    }

    // MARK: - Reference

    @ViewBuilder
    private var referenceRow: some View {
        if !example.postReference.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text(example.postReference)
                    .font(DS.caption2)
                if let slide = example.slideNumber {
                    Text("Slide \(slide)")
                        .font(DS.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DS.surface, in: Capsule())
                }
            }
            .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Mechanism

    @ViewBuilder
    private var mechanismCallout: some View {
        if let mechanism = example.mechanism, !mechanism.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("MECHANISM")
                    .font(DS.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(categoryColor.opacity(0.6))
                    .tracking(0.5)
                Text(mechanism)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(2)
            }
            .padding(DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(categoryColor.opacity(0.04), in: .rect(cornerRadius: DS.radiusSmall))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(categoryColor.opacity(0.3))
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
    }
}
