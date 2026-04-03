// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsSlideQuarksView.swift
// Horizontal scroll of per-slide quark cards with tap-to-expand detail

import SwiftUI

struct PhysicsSlideQuarksView: View {
    let quarks: [SlideQuark]
    @Binding var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            slideCardStrip
            selectedSlideDetail
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
    }

    // MARK: - Header

    @ViewBuilder
    private var sectionHeader: some View {
        HStack {
            Text("SLIDE QUARKS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.entitySwipe)
            Spacer()
            Text("\(quarks.count) slides")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Slide Card Strip

    @ViewBuilder
    private var slideCardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(quarks) { quark in
                    slideCard(quark)
                }
            }
            .padding(.vertical, DS.space4)
        }
    }

    @ViewBuilder
    private func slideCard(_ quark: SlideQuark) -> some View {
        let isSelected = selectedSlide == quark.slideNumber

        Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedSlide = isSelected ? nil : quark.slideNumber
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.space6) {
                slideCardHeader(quark)
                propertyPill("Speech", quark.speechAct.type, DS.entitySwipe)
                deltasPills(quark)
                propertyPill("Proof", quark.proofType?.type, DS.green)
                propertyPill("Motive", quark.motivation?.type, DS.orange)
                propertyPill("Dist", quark.experientialDistance?.type, distanceColor(for: quark.experientialDistance?.type ?? ""))
            }
            .padding(DS.space10)
            .frame(width: 150, alignment: .leading)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(isSelected ? DS.entitySwipe : DS.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Slide \(quark.slideNumber) quarks")
    }

    @ViewBuilder
    private func slideCardHeader(_ quark: SlideQuark) -> some View {
        Text("Slide \(quark.slideNumber)")
            .font(DS.caption)
            .monospacedDigit()
            .foregroundStyle(DS.text)
    }

    @ViewBuilder
    private func deltasPills(_ quark: SlideQuark) -> some View {
        if let deltas = quark.readerDeltas {
            ForEach(Array(deltas.prefix(2).enumerated()), id: \.offset) { _, delta in
                propertyPill("Delta", delta.type, deltaColor(for: delta.type ?? ""))
            }
        }
    }

    @ViewBuilder
    private func propertyPill(_ label: String, _ value: String?, _ color: Color) -> some View {
        if let value, !value.isEmpty {
            HStack(spacing: DS.space4) {
                Text(label)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 40, alignment: .leading)
                CodexConceptTag(name: cleanTypeName(value), color: color)
            }
        }
    }

    // MARK: - Selected Slide Detail

    @ViewBuilder
    private var selectedSlideDetail: some View {
        if let slideNum = selectedSlide, let quark = quarks.first(where: { $0.slideNumber == slideNum }) {
            expandedPanel(quark)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private func expandedPanel(_ quark: SlideQuark) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            slideTextQuote(quark)
            quarkRow(label: "Speech Act", type: quark.speechAct.type, mechanism: quark.speechAct.mechanism, color: DS.entitySwipe)
            readerDeltasSection(quark)
            optionalRow(label: "Proof", qm: quark.proofType, color: DS.green)
            optionalRow(label: "Motivation", qm: quark.motivation, color: DS.orange)
            compressionRow(quark)
            optionalRow(label: "Frame", qm: quark.frame, color: DS.orange)
            experientialDistanceRow(quark)
            techniquesSection(quark)
            resonanceCard(quark)
        }
        .padding(DS.space12)
        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    @ViewBuilder
    private func slideTextQuote(_ quark: SlideQuark) -> some View {
        if let text = quark.text, !text.isEmpty {
            Text("Slide \(quark.slideNumber): \"\(text)\"")
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readerDeltasSection(_ quark: SlideQuark) -> some View {
        if let deltas = quark.readerDeltas {
            ForEach(Array(deltas.enumerated()), id: \.offset) { _, delta in
                quarkRow(label: "Reader Delta", type: delta.type, mechanism: delta.mechanism, color: deltaColor(for: delta.type ?? ""))
            }
        }
    }

    @ViewBuilder
    private func optionalRow(label: String, qm: QuarkMechanism?, color: Color) -> some View {
        if let qm { quarkRow(label: label, type: qm.type, mechanism: qm.mechanism, color: color) }
    }

    @ViewBuilder
    private func compressionRow(_ quark: SlideQuark) -> some View {
        if let c = quark.compression {
            quarkRow(label: "Compression", type: "\(c.type)\(c.size.map { " (\($0))" } ?? "")", mechanism: c.mechanism, color: DS.textMuted)
        }
    }

    @ViewBuilder
    private func resonanceCard(_ quark: SlideQuark) -> some View {
        if let resonance = quark.resonanceFrequency, let detail = resonance.detail {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("RESONANCE")
                    .font(DS.caption)
                    .tracking(1.0)
                    .foregroundStyle(DS.entitySwipe)
                Text(detail)
                    .font(DS.callout)
                    .foregroundStyle(DS.entitySwipe)
                if let exp = resonance.unspokenExperience {
                    Text(exp).font(DS.caption2).foregroundStyle(DS.textMuted)
                }
                if let reach = resonance.estimatedReach {
                    Text("Reach: \(reach)").font(DS.caption2).foregroundStyle(DS.textMuted)
                }
            }
            .padding(DS.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                DS.entitySwipe.frame(width: 3).clipShape(.rect(cornerRadius: 2))
            }
            .background(DS.entitySwipe.opacity(DS.opacitySubtle), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    // MARK: - Experiential Distance

    @ViewBuilder
    private func experientialDistanceRow(_ quark: SlideQuark) -> some View {
        if let ed = quark.experientialDistance {
            quarkRow(label: "Distance", type: ed.type, mechanism: ed.mechanism, color: distanceColor(for: ed.type ?? ""))
        }
    }

    private func distanceColor(for level: String) -> Color {
        switch level.lowercased() {
        case "zero": return DS.red
        case "near": return DS.orange
        case "far": return DS.textMuted
        default: return DS.textMuted
        }
    }

    // MARK: - Techniques

    @ViewBuilder
    private func techniquesSection(_ quark: SlideQuark) -> some View {
        if let techniques = quark.techniques, !techniques.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Techniques")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                ForEach(Array(techniques.enumerated()), id: \.offset) { _, tech in
                    HStack(spacing: DS.space4) {
                        CodexConceptTag(name: tech.technique, color: DS.info)
                        if let usage = tech.usage, !usage.isEmpty {
                            Text(usage)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quark Row

    @ViewBuilder
    private func quarkRow(label: String, type: String?, mechanism: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space6) {
                Text(label)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                if let type, !type.isEmpty {
                    CodexConceptTag(name: cleanTypeName(type), color: color)
                }
            }
            if let mechanism, !mechanism.isEmpty {
                Text(mechanism)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func cleanTypeName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    private func deltaColor(for type: String) -> Color {
        let t = type.lowercased()
        if t.contains("tension") || t.contains("empathy") { return DS.red }
        if t.contains("trust") || t.contains("hope") || t.contains("curiosity") { return DS.green }
        if t.contains("surprise") { return DS.orange }
        if t.contains("identification") { return DS.info }
        return DS.textMuted
    }
}
