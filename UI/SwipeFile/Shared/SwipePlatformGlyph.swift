// CosmoOS/UI/SwipeFile/Shared/SwipePlatformGlyph.swift
// Honest platform marks — ported from the iPhone app's PlatformGlyph
// (CosmoiOS/Sources/Swipes/PlatformGlyph.swift; keep the two in lockstep).
// Generic SF stand-ins (camera.fill for Instagram, text.bubble for X) are the
// single loudest "template app" tell — these are simplified monochrome vector
// marks that read as the real thing at glyph size, drawn as paths so they
// inherit foregroundStyle like any symbol.
// July 2026

import SwiftUI

/// A platform's mark at glyph scale. Size via `.frame`; color via
/// `.foregroundStyle` — behaves like an SF Symbol at the call site.
/// Accepts every key style the Mac library uses ("instagramReel",
/// "instagram_reel", "youtube_short", "x", …).
struct SwipePlatformGlyph: View {
    let source: String?

    var body: some View {
        let family = (source ?? "").lowercased()
        Group {
            if family.hasPrefix("instagram") {
                SwipeInstagramMark()
            } else if family.hasPrefix("youtube") {
                SwipeYouTubeMark()
            } else if family == "x" || family == "twitter" || family == "x_post" || family == "xpost" {
                SwipeXMark()
            } else if family == "tiktok" {
                Image(systemName: "music.note").resizable().scaledToFit()
            } else if family == "threads" {
                Image(systemName: "at").resizable().scaledToFit()
            } else if family == "podcast" {
                Image(systemName: "mic.fill").resizable().scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rounded square + lens + dot — the camera mark, three strokes.
private struct SwipeInstagramMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let line = s * 0.115
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.30, style: .continuous)
                    .strokeBorder(lineWidth: line)
                Circle()
                    .strokeBorder(lineWidth: line)
                    .frame(width: s * 0.46, height: s * 0.46)
                Circle()
                    .frame(width: line * 1.15, height: line * 1.15)
                    .offset(x: s * 0.26, y: -s * 0.26)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Filled rounded rect with a knockout play triangle.
private struct SwipeYouTubeMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 0.7
            RoundedRectangle(cornerRadius: w * 0.22, style: .continuous)
                .frame(width: w, height: h)
                .overlay {
                    SwipePlayTriangle()
                        .fill(.black)
                        .blendMode(.destinationOut)
                        .frame(width: w * 0.34, height: w * 0.30)
                        .offset(x: w * 0.03)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1 / 0.7, contentMode: .fit)
    }
}

private struct SwipePlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The heavy X lettermark — two thick crossing bars, not an `xmark` glyph.
private struct SwipeXMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let bar = s * 0.26
            ZStack {
                Capsule()
                    .frame(width: s * 1.26, height: bar)
                    .rotationEffect(.degrees(45))
                Capsule()
                    .frame(width: s * 1.26, height: bar)
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: s, height: s)
            .clipShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
