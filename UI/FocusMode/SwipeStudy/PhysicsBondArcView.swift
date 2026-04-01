// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsBondArcView.swift
// Canvas-based arc diagram visualizing long-range setup→payoff bonds

import SwiftUI

struct PhysicsBondArcView: View {
    let bonds: [SetupPayoffBond]
    let entanglements: [EntanglementPair]
    let echoes: [EchoPattern]
    let totalSlides: Int
    @Binding var selectedSlide: Int?
    @State private var hoveredBond: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            slideRuler
            arcCanvas
            hoveredBondDetail
        }
    }

    // MARK: - Slide Ruler

    @ViewBuilder
    private var slideRuler: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                ForEach(1...max(totalSlides, 1), id: \.self) { slide in
                    let isActive = isSlideInvolved(slide)
                    let isSelected = selectedSlide == slide
                    VStack(spacing: 2) {
                        Circle()
                            .fill(isSelected ? DS.entityConnection : (isActive ? DS.entityConnection.opacity(0.6) : DS.textMuted.opacity(0.3)))
                            .frame(width: isActive ? 10 : 7, height: isActive ? 10 : 7)
                        Text("\(slide)")
                            .font(DS.caption2)
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? DS.text : DS.textMuted.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedSlide = selectedSlide == slide ? nil : slide
                        }
                    }
                }
            }
        }
        .frame(height: 30)
    }

    // MARK: - Arc Canvas

    @ViewBuilder
    private var arcCanvas: some View {
        let maxDistance = bonds.compactMap(\.distance).max() ?? 1
        let canvasHeight: CGFloat = CGFloat(20 + maxDistance * 6)

        GeometryReader { geo in
            Canvas { context, size in
                drawBondArcs(context: context, size: size)
                drawEntanglementArcs(context: context, size: size)
                drawEchoArcs(context: context, size: size)
            }
        }
        .frame(height: max(canvasHeight, 50))
        .accessibilityLabel("\(bonds.count) setup-payoff bonds, \(entanglements.count) entangled pairs")
    }

    private func drawBondArcs(context: GraphicsContext, size: CGSize) {
        for bond in bonds {
            let startX = slideX(bond.setupSlide, width: size.width)
            let endX = slideX(bond.payoffSlide, width: size.width)
            let midX = (startX + endX) / 2
            let arcHeight = CGFloat(20 + (bond.distance ?? 1) * 6)
            let isHighlighted = selectedSlide == bond.setupSlide || selectedSlide == bond.payoffSlide

            var path = Path()
            path.move(to: CGPoint(x: startX, y: size.height))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: size.height),
                control: CGPoint(x: midX, y: size.height - arcHeight)
            )

            let color = isHighlighted ? DS.entityConnection : DS.entityConnection.opacity(0.5)
            context.stroke(path, with: .color(color), lineWidth: isHighlighted ? 2.5 : 1.5)

            // Arrowhead at payoff end
            drawArrowhead(context: context, at: CGPoint(x: endX, y: size.height), color: color)
        }
    }

    private func drawEntanglementArcs(context: GraphicsContext, size: CGSize) {
        for pair in entanglements {
            let startX = slideX(pair.slideA, width: size.width)
            let endX = slideX(pair.slideB, width: size.width)
            let midX = (startX + endX) / 2
            let arcHeight = CGFloat(15 + abs(pair.slideB - pair.slideA) * 4)

            var path = Path()
            path.move(to: CGPoint(x: startX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: 0),
                control: CGPoint(x: midX, y: arcHeight)
            )

            let dashStyle = StrokeStyle(lineWidth: 2, dash: [6, 3])
            context.stroke(path, with: .color(DS.red.opacity(0.6)), style: dashStyle)
        }
    }

    private func drawEchoArcs(context: GraphicsContext, size: CGSize) {
        for echo in echoes {
            guard let positions = echo.positions, positions.count >= 2 else { continue }
            let sorted = positions.sorted()
            for i in 0..<(sorted.count - 1) {
                let startX = slideX(sorted[i], width: size.width)
                let endX = slideX(sorted[i + 1], width: size.width)
                let midX = (startX + endX) / 2
                let arcHeight = CGFloat(10 + abs(sorted[i + 1] - sorted[i]) * 3)

                var path = Path()
                path.move(to: CGPoint(x: startX, y: size.height * 0.5))
                path.addQuadCurve(
                    to: CGPoint(x: endX, y: size.height * 0.5),
                    control: CGPoint(x: midX, y: size.height * 0.5 - arcHeight)
                )

                let dotStyle = StrokeStyle(lineWidth: 1.5, dash: [3, 4])
                context.stroke(path, with: .color(DS.info.opacity(0.4)), style: dotStyle)
            }
        }
    }

    private func drawArrowhead(context: GraphicsContext, at point: CGPoint, color: Color) {
        var arrow = Path()
        arrow.move(to: CGPoint(x: point.x - 4, y: point.y - 6))
        arrow.addLine(to: CGPoint(x: point.x, y: point.y))
        arrow.addLine(to: CGPoint(x: point.x + 4, y: point.y - 6))
        context.stroke(arrow, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - Hovered Bond Detail

    @ViewBuilder
    private var hoveredBondDetail: some View {
        if let slide = selectedSlide, let bond = bonds.first(where: { $0.setupSlide == slide || $0.payoffSlide == slide }) {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space6) {
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
                    Label(planted, systemImage: "leaf.fill")
                        .font(DS.caption2)
                        .foregroundStyle(DS.green)
                        .accessibilityLabel("Planted: \(planted)")
                }
                if let harvested = bond.harvested {
                    Label(harvested, systemImage: "sparkles")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                        .accessibilityLabel("Harvested: \(harvested)")
                }
            }
            .padding(DS.space10)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .transition(.opacity)
        }
    }

    // MARK: - Helpers

    private func slideX(_ slide: Int, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 16
        let usable = width - padding * 2
        return padding + usable * CGFloat(slide - 1) / CGFloat(max(totalSlides - 1, 1))
    }

    private func isSlideInvolved(_ slide: Int) -> Bool {
        bonds.contains { $0.setupSlide == slide || $0.payoffSlide == slide } ||
        entanglements.contains { $0.slideA == slide || $0.slideB == slide }
    }
}
