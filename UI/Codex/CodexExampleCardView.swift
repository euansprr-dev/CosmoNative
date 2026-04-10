// CosmoOS/UI/Codex/CodexExampleCardView.swift
// Rich example quote card for Codex element detail views — Akashic manuscript aesthetic.
// April 2026 — Akashic Records Premium Redesign

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
            replicationTemplateCallout
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsVellumCard(cornerRadius: DS.radiusMedium)
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
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkWash)
                .lineSpacing(4)
                .padding(.leading, 20)
        }
    }

    private var decorativeQuote: some View {
        Text("\u{201C}")
            .font(.system(size: 36, weight: .bold, design: .serif))
            .foregroundStyle(DS.gilt.opacity(0.2))
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
                        .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusXSmall))
                }
            }
            .foregroundStyle(DS.giltMuted)
        }
    }

    // MARK: - Mechanism

    @ViewBuilder
    private var mechanismCallout: some View {
        if let mechanism = example.mechanism, !mechanism.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                AkashicSectionHeader(title: "MECHANISM")
                Text(mechanism)
                    .font(DS.caption)
                    .foregroundStyle(DS.inkFaded)
                    .lineSpacing(2)
            }
            .padding(DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.sepiaSubtle, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Replication Template

    @ViewBuilder
    private var replicationTemplateCallout: some View {
        if let template = example.replicationTemplate, !template.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                AkashicSectionHeader(title: "REPLICATION TEMPLATE")
                Text(template)
                    .font(DS.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(DS.inkFaded)
                    .lineSpacing(2)
                    .italic()
            }
            .padding(DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.giltSoft.opacity(0.3), in: .rect(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.giltMuted.opacity(0.4), lineWidth: 0.5)
            )
        }
    }
}
