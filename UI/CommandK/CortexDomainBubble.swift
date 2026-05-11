// CosmoOS/UI/CommandK/CortexDomainBubble.swift
// Domain launcher card for the Command-K compact surface.

import SwiftUI

struct CortexDomainBubble: View {
    let tab: CommandKTab
    let count: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                topArtwork
                lowerPocket
            }
            .frame(width: CommandKMetrics.domainCardWidth, height: CommandKMetrics.domainCardHeight)
            .background(cardBase)
            .overlay(cardStroke)
            .clipShape(.rect(cornerRadius: 22))
            .matchedGeometryEffect(id: "domain-card-\(tab.rawValue)", in: namespace)
            .scaleEffect(isPressed ? 0.985 : (isHovered ? 1.012 : 1.0))
            .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0.08), radius: isHovered ? 22 : 14, x: 0, y: isHovered ? 10 : 5)
            .shadow(color: tab.accentColor.opacity(isHovered ? 0.16 : 0.07), radius: isHovered ? 26 : 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(ProMotionSprings.press) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(ProMotionSprings.release) { isPressed = false }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title), \(formattedCount) items")
        .accessibilityHint("Open \(tab.title)")
    }

    private var cardBase: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tab.accentColor.opacity(0.74),
                        tab.accentColor.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isHovered ? 0.72 : 0.54),
                        tab.accentColor.opacity(isHovered ? 0.75 : 0.44),
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isHovered ? 1.25 : 0.8
            )
    }

    private var topArtwork: some View {
            CortexDomainArtwork(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, DS.space16)
                .padding(.horizontal, DS.space12)
                .padding(.bottom, 90)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 166)
                    .padding(.trailing, DS.space20)
            }
    }

    private var lowerPocket: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(tab.title)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(tab.compactSubtitle)
                .font(DS.callout)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: DS.space6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .regular))
                    .accessibilityHidden(true)
                Text(formattedCount)
                    .font(DS.callout)
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, DS.space20)
        .padding(.top, DS.space48 + DS.space8)
        .padding(.bottom, DS.space18)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        .background {
            CortexPocketShape()
                .fill(
                    LinearGradient(
                        colors: [
                            tab.accentColor.opacity(0.98),
                            Color.black.opacity(0.46)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    CortexPocketShape()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    private var formattedCount: String {
        count.formatted(.number)
    }
}

struct CortexDomainArtwork: View {
    let tab: CommandKTab

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch tab {
                case .database:
                    databaseArtwork(in: geometry.size)
                case .swipeGallery:
                    swipeArtwork(in: geometry.size)
                case .ideas:
                    ideasArtwork(in: geometry.size)
                case .readwise:
                    libraryArtwork(in: geometry.size)
                case .inquiry:
                    databaseArtwork(in: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func databaseArtwork(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CortexPaperCard(accent: DS.accent, lineCount: 4 + index)
                    .frame(width: 82, height: 112)
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(x: CGFloat(index - 2) * 24, y: CGFloat(index % 2) * 8)
                    .opacity(index == 0 ? 0.88 : 1)
            }
            CortexNodeGraph()
                .stroke(Color.white.opacity(0.36), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 100, height: 80)
                .offset(x: 34, y: 26)
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(DS.accent.opacity(0.92))
                    .frame(width: 15, height: 15)
                    .offset(nodeOffset(index))
            }
        }
        .offset(y: 14)
    }

    private func swipeArtwork(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(index == 0 ? 0.96 : 0.78))
                    .frame(width: 84, height: 112)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.52), DS.entitySwipe.opacity(0.42)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(7)
                    }
                    .overlay {
                        if index == 0 {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.42), in: Circle())
                        }
                    }
                    .rotationEffect(.degrees(Double(index - 2) * 6))
                    .offset(x: CGFloat(index - 2) * 22, y: CGFloat(index % 2) * 8)
            }
        }
        .offset(y: 10)
    }

    private func ideasArtwork(in size: CGSize) -> some View {
        ZStack {
            CortexPaperCard(accent: DS.entityIdea, lineCount: 5)
                .frame(width: 92, height: 116)
                .rotationEffect(.degrees(-7))
                .offset(x: -36, y: 8)
            CortexPaperCard(accent: DS.entityIdea, lineCount: 4)
                .frame(width: 94, height: 120)
                .rotationEffect(.degrees(6))
                .offset(x: 34, y: 10)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .frame(width: 76, height: 82)
                .overlay {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(DS.entityIdea.opacity(0.62))
                }
                .offset(y: 34)
            Circle()
                .fill(DS.entityIdea.opacity(0.92))
                .frame(width: 14, height: 14)
                .offset(x: -18, y: -28)
        }
        .offset(y: 6)
    }

    private func libraryArtwork(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(bookColor(index))
                    .frame(width: 28, height: 112 + CGFloat(index % 2) * 10)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.white.opacity(0.32))
                            .frame(width: 18, height: 2)
                            .padding(.top, 16)
                    }
                    .offset(x: CGFloat(index - 2) * 24, y: 12)
            }
            CortexPaperCard(accent: DS.entityReadwise, lineCount: 6)
                .frame(width: 88, height: 122)
                .rotationEffect(.degrees(-5))
                .offset(x: 44, y: 4)
        }
        .offset(y: 8)
    }

    private func nodeOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: return CGSize(width: -4, height: 8)
        case 1: return CGSize(width: 42, height: -22)
        case 2: return CGSize(width: 44, height: 52)
        default: return CGSize(width: 86, height: 28)
        }
    }

    private func bookColor(_ index: Int) -> Color {
        [DS.entityReadwise, Color(hex: "7B5E3F"), Color(hex: "C09A64"), Color(hex: "4F5E5B"), Color(hex: "E8D3A4")][index]
    }
}

private struct CortexPaperCard: View {
    let accent: Color
    let lineCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent.opacity(0.26))
                        .frame(width: 34, height: 6)
                    ForEach(0..<lineCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.black.opacity(0.12))
                            .frame(width: CGFloat(52 + (index % 3) * 12), height: 3)
                    }
                }
                .padding(12)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

private struct CortexPocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 22
        let notchStart = rect.width * 0.33
        let notchEnd = rect.width * 0.55
        let top: CGFloat = 0
        let notchDepth: CGFloat = 28

        path.move(to: CGPoint(x: radius, y: top))
        path.addLine(to: CGPoint(x: notchStart, y: top))
        path.addCurve(
            to: CGPoint(x: notchEnd, y: notchDepth),
            control1: CGPoint(x: notchStart + 32, y: top),
            control2: CGPoint(x: notchEnd - 38, y: notchDepth)
        )
        path.addLine(to: CGPoint(x: rect.width - radius, y: notchDepth))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: notchDepth + radius), control: CGPoint(x: rect.width, y: notchDepth))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: top), control: CGPoint(x: 0, y: top))
        path.closeSubpath()
        return path
    }
}

private struct CortexNodeGraph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = [
            CGPoint(x: rect.minX + 6, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.minY + 8),
            CGPoint(x: rect.midX + 2, y: rect.maxY - 6),
            CGPoint(x: rect.maxX - 6, y: rect.midY + 12),
        ]
        path.move(to: points[0])
        path.addLine(to: points[1])
        path.move(to: points[0])
        path.addLine(to: points[2])
        path.move(to: points[1])
        path.addLine(to: points[3])
        path.move(to: points[2])
        path.addLine(to: points[3])
        return path
    }
}
