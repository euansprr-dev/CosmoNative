// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsBondsView.swift
// Long-range setup-payoff bonds, echo patterns, interferences

import SwiftUI

struct PhysicsBondsView: View {
    let interactions: LongRangeInteractions?
    let totalSlides: Int
    @Binding var selectedSlide: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            headerRow
            if let inter = interactions {
                bondArcSection(inter)
                entanglementSection(inter)
                echoSection(inter)
                interferenceSection(inter)
                absenceSection(inter)
            } else {
                emptyState
            }
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Text("LONG-RANGE BONDS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.entityConnection)
            Spacer()
            if let bonds = interactions?.setupPayoffBonds {
                Text("\(bonds.count) bonds")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entityConnection)
            }
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        Text("No long-range interaction data")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Bond Cards

    @ViewBuilder
    private func bondArcSection(_ inter: LongRangeInteractions) -> some View {
        if let bonds = inter.setupPayoffBonds, !bonds.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                ForEach(bonds.sorted(by: { ($0.distance ?? 0) > ($1.distance ?? 0) })) { bond in
                    bondCard(bond)
                }
            }
        }
    }

    @ViewBuilder
    private func bondCard(_ bond: SetupPayoffBond) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space8) {
                Text("Slide \(bond.setupSlide)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                Image(systemName: "arrow.right")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entityConnection)
                    .accessibilityHidden(true)
                Text("Slide \(bond.payoffSlide)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.text)
                if let dist = bond.distance {
                    Text("(\(dist) apart)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
            if let planted = bond.planted {
                HStack(alignment: .top, spacing: DS.space4) {
                    Image(systemName: "leaf.fill")
                        .font(DS.caption2)
                        .foregroundStyle(DS.green)
                        .accessibilityHidden(true)
                    Text(planted)
                        .font(DS.caption2)
                        .foregroundStyle(DS.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let harvested = bond.harvested {
                HStack(alignment: .top, spacing: DS.space4) {
                    Image(systemName: "sparkles")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                        .accessibilityHidden(true)
                    Text(harvested)
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    // MARK: - Entanglement Pairs

    @ViewBuilder
    private func entanglementSection(_ inter: LongRangeInteractions) -> some View {
        if let pairs = inter.entanglementPairs, !pairs.isEmpty {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("ENTANGLED PAIRS")
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
                    .padding(.bottom, DS.space4)

                ForEach(pairs) { pair in
                    entanglementRow(pair)
                }
            }
        }
    }

    @ViewBuilder
    private func entanglementRow(_ pair: EntanglementPair) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space6) {
                Text("Slide \(pair.slideA)")
                    .font(DS.caption)
                    .monospaced()
                    .foregroundStyle(DS.text)
                Image(systemName: "arrow.left.arrow.right")
                    .font(DS.caption2)
                    .foregroundStyle(DS.red)
                    .accessibilityLabel("entangled with")
                Text("Slide \(pair.slideB)")
                    .font(DS.caption)
                    .monospaced()
                    .foregroundStyle(DS.text)
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

    // MARK: - Echo Patterns

    @ViewBuilder
    private func echoSection(_ inter: LongRangeInteractions) -> some View {
        if let echoes = inter.echoPatterns, !echoes.isEmpty {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("ECHO PATTERNS")
                    .font(DS.caption)
                    .foregroundStyle(DS.info)
                    .padding(.bottom, DS.space4)

                ForEach(echoes) { echo in
                    echoRow(echo)
                }
            }
        }
    }

    @ViewBuilder
    private func echoRow(_ echo: EchoPattern) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space4) {
                Text(echo.quarkType)
                    .font(DS.callout)
                    .foregroundStyle(DS.info)
                if let positions = echo.positions {
                    Text("@slides [\(positions.map(String.init).joined(separator: ", "))]")
                        .font(DS.caption2)
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

    // MARK: - Interference

    @ViewBuilder
    private func interferenceSection(_ inter: LongRangeInteractions) -> some View {
        if let interferences = inter.interferences, !interferences.isEmpty {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("INTERFERENCE")
                    .font(DS.caption)
                    .foregroundStyle(DS.orange)
                    .padding(.bottom, DS.space4)

                ForEach(interferences) { interference in
                    interferenceRow(interference)
                }
            }
        }
    }

    @ViewBuilder
    private func interferenceRow(_ interference: Interference) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space4) {
                if let slides = interference.slides {
                    Text("@\(slides.map(String.init).joined(separator: ","))")
                        .font(DS.caption)
                        .monospaced()
                        .foregroundStyle(DS.text)
                }
                forcePills(interference.forces)
            }
            if let effect = interference.emergentEffect, !effect.isEmpty {
                Text("-> \(effect)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func forcePills(_ forces: [String]) -> some View {
        ForEach(forces, id: \.self) { force in
            Text(force)
                .font(DS.caption2)
                .foregroundStyle(DS.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.orangeSoft, in: Capsule())
        }
    }

    // MARK: - Deliberate Absences

    @ViewBuilder
    private func absenceSection(_ inter: LongRangeInteractions) -> some View {
        if let absences = inter.deliberateAbsences, !absences.isEmpty {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("DELIBERATE ABSENCES")
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
                    .padding(.bottom, DS.space4)

                ForEach(absences) { absence in
                    absenceRow(absence)
                }
            }
        }
    }

    @ViewBuilder
    private func absenceRow(_ absence: DeliberateAbsence) -> some View {
        HStack(alignment: .top, spacing: DS.space6) {
            Image(systemName: "circle.slash")
                .font(DS.caption)
                .foregroundStyle(DS.red)
                .accessibilityLabel("Absent")
            VStack(alignment: .leading, spacing: 2) {
                Text(absence.what)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                if let effect = absence.effect {
                    Text(effect)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DS.red)
                .frame(width: 3)
        }
    }
}
