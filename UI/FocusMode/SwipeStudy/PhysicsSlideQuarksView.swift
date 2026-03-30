// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsSlideQuarksView.swift
// Horizontal scrolling strip of slide quark chords — tap to expand mechanisms

import SwiftUI

struct PhysicsSlideQuarksView: View {
    let quarks: [SlideQuark]
    @State private var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            slideStrip
            expandedDetail
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private var sectionHeader: some View {
        HStack {
            Text("SLIDE QUARKS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(quarks.count) slides")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private var slideStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space4) {
                ForEach(quarks) { quark in
                    slideNode(quark)
                }
            }
            .padding(.vertical, DS.space4)
        }
    }

    @ViewBuilder
    private func slideNode(_ quark: SlideQuark) -> some View {
        let isSelected = selectedSlide == quark.slideNumber
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedSlide = isSelected ? nil : quark.slideNumber
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(quark.slideNumber)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : DS.text)

                Circle()
                    .fill(deltaColor(quark))
                    .frame(width: 10, height: 10)

                Text(abbreviate(quark.speechAct.type ?? ""))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : DS.textSecondary)
                    .lineLimit(1)

                if let delta = quark.readerDeltas?.first {
                    Text(abbreviate((delta.type ?? "")))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : DS.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: 56, height: 80)
            .background(
                isSelected ? DS.entitySwipe : DS.surfaceHover,
                in: RoundedRectangle(cornerRadius: DS.radiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(isSelected ? DS.entitySwipe : DS.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedDetail: some View {
        if let slideNum = selectedSlide, let quark = quarks.first(where: { $0.slideNumber == slideNum }) {
            VStack(alignment: .leading, spacing: DS.space8) {
                if let text = quark.text, !text.isEmpty {
                    Text("Slide \(slideNum): \"\(text)\"")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                }

                quarkRow(label: "Speech Act", type: quark.speechAct.type ?? "", mechanism: quark.speechAct.mechanism, color: DS.entitySwipe)

                if let deltas = quark.readerDeltas {
                    ForEach(Array(deltas.enumerated()), id: \.offset) { _, delta in
                        quarkRow(label: "Reader", type: (delta.type ?? ""), mechanism: delta.mechanism, color: DS.info)
                    }
                }
                if let proof = quark.proofType {
                    quarkRow(label: "Proof", type: proof.type ?? "", mechanism: proof.mechanism, color: DS.green)
                }
                if let motivation = quark.motivation {
                    quarkRow(label: "Motivation", type: motivation.type ?? "", mechanism: motivation.mechanism, color: DS.orange)
                }
                if let compression = quark.compression {
                    quarkRow(label: "Compression", type: "\(compression.type)\(compression.size.map { " (\($0))" } ?? "")", mechanism: compression.mechanism, color: DS.textMuted)
                }
                if let resonance = quark.resonanceFrequency, let detail = resonance.detail {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.space4) {
                            Text("📡")
                                .font(.system(size: 10))
                            Text("RESONANCE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.entitySwipe)
                        }
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.entitySwipe)
                        if let experience = resonance.unspokenExperience {
                            Text(experience)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                        }
                        if let reach = resonance.estimatedReach {
                            Text("Reach: \(reach)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                        }
                    }
                }
            }
            .padding(DS.space12)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private func quarkRow(label: String, type: String, mechanism: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                Text(type)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 1)
                    .background(color.opacity(DS.opacitySubtle), in: Capsule())
            }
            if let mechanism, !mechanism.isEmpty {
                Text(mechanism)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
            }
        }
    }

    private func deltaColor(_ quark: SlideQuark) -> Color {
        guard let delta = quark.readerDeltas?.first?.type?.lowercased() else { return DS.textMuted }
        if delta.contains("tension+") || delta.contains("empathy") { return DS.red }
        if delta.contains("trust") || delta.contains("hope") || delta.contains("curiosity+") { return DS.green }
        if delta.contains("surprise") { return DS.orange }
        if delta.contains("identification") { return DS.info }
        return DS.textMuted
    }

    private func abbreviate(_ type: String) -> String {
        let t = type.lowercased()
        if t.starts(with: "conf") { return "conf" }
        if t.starts(with: "upd") { return "updt" }
        if t.starts(with: "vow") { return "vow" }
        if t.starts(with: "doubt") { return "dbt" }
        if t.starts(with: "rev") { return "rvl" }
        if t.starts(with: "grat") { return "grat" }
        if t.starts(with: "boast") { return "bst" }
        if t.starts(with: "defi") { return "def" }
        if t.starts(with: "lam") { return "lmt" }
        if t.contains("curiosity") { return "cur+" }
        if t.contains("tension") { return "ten+" }
        if t.contains("trust") { return "trs+" }
        if t.contains("identification") { return "idn+" }
        if t.contains("empathy") { return "emp+" }
        if t.contains("surprise") { return "sur" }
        if t.contains("hope") { return "hop+" }
        return String(t.prefix(4))
    }
}
