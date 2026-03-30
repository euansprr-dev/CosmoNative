// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsBondsView.swift
// Long-range setup-payoff bonds, echo patterns, interferences

import SwiftUI

struct PhysicsBondsView: View {
    let interactions: LongRangeInteractions?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("LONG-RANGE BONDS")
                    .font(DS.caption)
                    .tracking(1.2)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                if let bonds = interactions?.setupPayoffBonds {
                    Text("\(bonds.count) bonds")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }

            if let inter = interactions {
                bondsList(inter)
                entanglementList(inter)
                echoList(inter)
                interferenceList(inter)
                absenceList(inter)
            } else {
                Text("No long-range interaction data")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private func bondsList(_ inter: LongRangeInteractions) -> some View {
        if let bonds = inter.setupPayoffBonds, !bonds.isEmpty {
            ForEach(bonds.sorted(by: { ($0.distance ?? 0) > ($1.distance ?? 0) })) { bond in
                bondRow(bond)
            }
        }
    }

    @ViewBuilder
    private func bondRow(_ bond: SetupPayoffBond) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space6) {
                Text("Slide \(bond.setupSlide)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.text)

                DashedLine()
                    .stroke(DS.entitySwipe.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1)

                Text("Slide \(bond.payoffSlide)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.text)

                if let dist = bond.distance {
                    Text("(\(dist) apart)")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
            }

            if let planted = bond.planted {
                HStack(spacing: DS.space4) {
                    Text("planted:")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.green)
                    Text(planted)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)

                }
            }
            if let harvested = bond.harvested {
                HStack(spacing: DS.space4) {
                    Text("harvested:")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.entitySwipe)
                    Text(harvested)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)

                }
            }
        }
        .padding(.vertical, DS.space4)
    }

    @ViewBuilder
    private func entanglementList(_ inter: LongRangeInteractions) -> some View {
        if let pairs = inter.entanglementPairs, !pairs.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("ENTANGLED PAIRS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)

                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: DS.space4) {
                        HStack(spacing: DS.space6) {
                            Text("Slide \(pair.slideA)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("⟷")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DS.red)
                            Text("Slide \(pair.slideB)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("(entangled)")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.red)
                        }
                        if let ifA = pair.ifARemoved {
                            Text("If \(pair.slideA) removed: \(ifA)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.red.opacity(0.8))

                        }
                        if let ifB = pair.ifBRemoved {
                            Text("If \(pair.slideB) removed: \(ifB)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.red.opacity(0.8))

                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func echoList(_ inter: LongRangeInteractions) -> some View {
        if let echoes = inter.echoPatterns, !echoes.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("ECHOES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)

                ForEach(echoes) { echo in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.space4) {
                            Text("\"\(echo.quarkType)\"")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.info)
                            if let positions = echo.positions {
                                Text("@ slides \(positions.map(String.init).joined(separator: ", "))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DS.textMuted)
                            }
                        }
                        if let transformation = echo.transformation, !transformation.isEmpty {
                            Text(transformation)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textSecondary)

                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func interferenceList(_ inter: LongRangeInteractions) -> some View {
        if let interferences = inter.interferences, !interferences.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("INTERFERENCE EFFECTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)

                ForEach(interferences) { interference in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.space4) {
                            if let slides = interference.slides {
                                Text("@\(slides.map(String.init).joined(separator: ","))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DS.text)
                            }
                            ForEach(interference.forces, id: \.self) { force in
                                Text(force)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DS.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DS.orangeSoft, in: Capsule())
                            }
                        }
                        if let effect = interference.emergentEffect, !effect.isEmpty {
                            Text("→ \(effect)")
                                .font(DS.caption2)
                                .foregroundStyle(DS.textSecondary)

                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func absenceList(_ inter: LongRangeInteractions) -> some View {
        if let absences = inter.deliberateAbsences, !absences.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("DELIBERATE ABSENCES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)

                ForEach(absences) { absence in
                    HStack(alignment: .top, spacing: DS.space6) {
                        Text("⊘")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(absence.what)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.text)
                            if let effect = absence.effect {
                                Text(effect)
                                    .font(DS.caption2)
                                    .foregroundStyle(DS.textMuted)
    
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
