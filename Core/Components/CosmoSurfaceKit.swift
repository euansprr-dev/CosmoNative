// CosmoOS/Core/Components/CosmoSurfaceKit.swift
// Cross-platform surface primitives, ported field-for-field from the iOS
// CosmoSurfaceKit (July 2026 polish pass) with Mac manners: hover states and
// tooltips instead of haptics. Tokens and grammar stay in lockstep — change
// both repos together.

import SwiftUI

// MARK: - Compact age (the one age voice)

extension Date {
    /// The one age voice — "2d", "38m" (the iOS FileTile register). Never
    /// "ago": a ledger column repeating "5m ago" down every row reads as
    /// noise. Paired with the iOS `Date.cosmoCompactAge`.
    var cosmoCompactAge: String {
        let relative = formatted(.relative(presentation: .named, unitsStyle: .narrow))
        return relative.hasSuffix(" ago") ? String(relative.dropLast(4)) : relative
    }
}

// MARK: - Segmented switcher (the one view-mode grammar)

/// One capsule, N segments, a sliding thumb — the app's single view-mode
/// switcher voice. The thumb travels between segments via matched geometry
/// (the Deep Dive study bar's shipped pattern, extracted). Segment weight is
/// constant so selection never re-layouts the control; selection is the thumb
/// plus ink. Scope pills stay reserved for scopes/filters — view modes are
/// never pills.
struct CosmoSegmentedSwitcher<Option: Hashable>: View {
    /// `.capsule` draws its own quiet input chrome (standalone placement on a
    /// page). `.bare` renders segments only — for placement inside existing
    /// glass chrome (a `CosmoChromeIsland`), where more chrome would be
    /// glass-on-glass.
    enum Chrome {
        case capsule
        case bare
    }

    let options: [Option]
    let label: (Option) -> String
    var icon: ((Option) -> String)? = nil
    var help: ((Option) -> String)? = nil
    var chrome: Chrome = .capsule
    @Binding var selection: Option

    @Namespace private var thumb
    @State private var hoveredOption: Option?

    var body: some View {
        HStack(spacing: DS.space2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(chrome == .capsule ? DS.space2 : 0)
        .background {
            if chrome == .capsule {
                Capsule().fill(DS.glassInputFill)
            }
        }
        .overlay {
            if chrome == .capsule {
                Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = selection == option
        let isHovered = hoveredOption == option
        return Button {
            guard selection != option else { return }
            withAnimation(ProMotionSprings.focusTransition) { selection = option }
        } label: {
            HStack(spacing: DS.space4) {
                if let icon {
                    Image(systemName: icon(option))
                        .font(DS.caption.weight(.medium))
                        .accessibilityHidden(true)
                }
                Text(label(option))
                    .font(DS.footnote.weight(.medium))
            }
            .foregroundStyle(isSelected ? DS.text : (isHovered ? DS.textSecondary : DS.textMuted))
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space6)
            .background {
                // Sanctioned selection-that-travels: the thumb slides between
                // segments via matchedGeometryEffect (motion.md).
                if isSelected {
                    Capsule()
                        .fill(DS.surfaceElevated)
                        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "cosmo-switcher-thumb", in: thumb)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredOption = hovering ? option : (hoveredOption == option ? nil : hoveredOption)
            }
        }
        .help(help?(option) ?? label(option))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Identity chip (the compact type mark)

/// The app's type mark, Raycast's register: the identity-colored glyph
/// standing bare in its slot — no tile, no backing shape. The color carries
/// the kind; a rounded-square container read as one more box in icon
/// territory. Used where a row's mark is a *kind* (entity type) rather than
/// an honest object preview; identity previews (thumbnails, favicons,
/// content excerpts) always outrank it.
struct CosmoIdentityChip: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.62, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Platform brand marks

/// Simplified vector marks for social platforms — a generic SF stand-in
/// (camera.fill for Instagram) is the same class of tell as an emoji-less
/// board (surfaces.md §4). Monochrome, drawn to read at caption size.
struct PlatformBrandMark: View {
    /// Platform raw value / name, matched case-insensitively.
    let platform: String
    var size: CGFloat = 12
    var color: Color = DS.textMuted

    var body: some View {
        Group {
            switch normalized {
            case "instagram":
                // Rounded viewfinder: square outline, lens circle, flash dot.
                GeometryReader { proxy in
                    let s = proxy.size.width
                    ZStack {
                        RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                            .strokeBorder(color, lineWidth: s * 0.1)
                        Circle()
                            .strokeBorder(color, lineWidth: s * 0.1)
                            .frame(width: s * 0.44, height: s * 0.44)
                        Circle()
                            .fill(color)
                            .frame(width: s * 0.12, height: s * 0.12)
                            .position(x: s * 0.76, y: s * 0.24)
                    }
                }
            case "youtube":
                // The tube: filled rounded rect, knocked-out play triangle.
                GeometryReader { proxy in
                    let s = proxy.size.width
                    RoundedRectangle(cornerRadius: s * 0.28, style: .continuous)
                        .fill(color)
                        .frame(height: s * 0.72)
                        .overlay(
                            PlayTriangle()
                                .fill(.background)
                                .frame(width: s * 0.34, height: s * 0.34)
                        )
                        .frame(maxHeight: .infinity)
                }
            case "tiktok":
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.9, weight: .semibold))
                    .foregroundStyle(color)
            case "twitter", "x", "x_post":
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.8, weight: .bold))
                    .foregroundStyle(color)
            default:
                Image(systemName: "globe")
                    .font(.system(size: size * 0.9, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(platform.capitalized)
    }

    private var normalized: String {
        let lowered = platform.lowercased()
        if lowered.contains("instagram") || lowered.contains("reel") { return "instagram" }
        if lowered.contains("youtube") || lowered.contains("short") { return "youtube" }
        if lowered.contains("tiktok") { return "tiktok" }
        if lowered.contains("twitter") || lowered == "x" || lowered.contains("x_post") { return "twitter" }
        return lowered
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Collection identity (the App Store emoji register)

/// Resolves a user collection's identity mark (Swipe boards, capture lanes)
/// the way the App Store's category pills do: an emoji, never a generic SF
/// stand-in. Order: an emoji the user typed into the name wins (and leaves
/// the label clean), then a curated keyword match. Callers fall back to
/// their own honest mark (color dot, stored icon) when this returns nil.
/// Ported field-for-field from the iOS CollectionEmoji.
enum CollectionEmoji {
    /// `matchKeywords: false` for collections whose fallback mark is the
    /// user's own explicit choice (capture lanes pick an icon in their
    /// composer — a keyword guess must never override it). Boards have no
    /// hand-picked mark, so they take the keyword pass too.
    static func resolve(name: String, matchKeywords: Bool = true) -> (emoji: String?, label: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // 1. A leading emoji in the name IS the identity — lift it out.
        if let first = trimmed.first, first.isIdentityEmoji {
            let label = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (String(first), label.isEmpty ? trimmed : label)
        }
        // 2. Curated keywords for the vocabulary of a creator's library —
        //    ordered specific-first so "Reel Ideas" reads 🎬, never 💡.
        if matchKeywords {
            let lowered = trimmed.lowercased()
            for (keyword, emoji) in Self.keywords where lowered.contains(keyword) {
                return (emoji, trimmed)
            }
        }
        return (nil, trimmed)
    }

    private static let keywords: [(String, String)] = [
        ("hook", "🪝"), ("reel", "🎬"), ("video", "🎬"), ("film", "🎬"),
        ("thread", "🧵"), ("tweet", "🐦"), ("carousel", "🎠"),
        ("script", "✍️"), ("writing", "✍️"), ("quote", "💬"),
        ("story", "📖"), ("book", "📚"), ("reading", "📚"),
        ("music", "🎵"), ("photo", "📷"), ("design", "🎨"),
        ("recipe", "🍳"), ("grocer", "🛒"), ("travel", "✈️"),
        ("gym", "🏋️"), ("fitness", "🏋️"), ("growth", "📈"),
        ("meditat", "🧘"), ("yoga", "🧘"), ("stretch", "🧘"),
        ("journal", "📓"), ("research", "🔎"), ("walk", "🏃"), ("run", "🏃"),
        ("water", "💧"), ("sleep", "😴"), ("code", "💻"),
        ("post", "✍️"), ("content", "✍️"),
        ("idea", "💡"), ("inspo", "✨"), ("inspiration", "✨"),
    ]

    /// One-tap mark suggestions for a collection editor: keyword matches for
    /// the current name lead, then the common marks — deduped, first eight.
    static func suggestions(for name: String) -> [String] {
        let lowered = name.lowercased()
        var result: [String] = []
        for (keyword, emoji) in keywords where lowered.contains(keyword) {
            if !result.contains(emoji) { result.append(emoji) }
        }
        for emoji in ["🛒", "📚", "💡", "✍️", "🎬", "💬", "📈", "✨", "🍳", "✈️"] {
            if !result.contains(emoji) { result.append(emoji) }
        }
        return Array(result.prefix(8))
    }

    /// Whether a character counts as an identity mark (shared validator for
    /// emoji input fields).
    static func isEmoji(_ character: Character) -> Bool {
        character.isIdentityEmoji
    }

    /// A content format's mark — curated per case, the same identity
    /// register as board pills and lanes. Never an SF stand-in. Ported
    /// field-for-field from the iOS CollectionEmoji.formatMark.
    static func formatMark(_ format: ContentFormat) -> String {
        switch format {
        case .voiceoverReel: return "🎙️"
        case .oneSliderReel, .multiSliderReel, .twoStepCTA, .reel: return "🎬"
        case .youtube: return "📺"
        case .carousel: return "🎠"
        case .tweet: return "🐦"
        case .thread: return "🧵"
        case .longForm: return "✍️"
        case .newsletter: return "✉️"
        case .post: return "📌"
        }
    }
}

// MARK: - Shelf header (the editorial register)

/// The browse-surface header voice: heavy sentence case with a quiet
/// trailing count — the App Store register for shelves of content you
/// explore. Ported from the iOS CosmoShelfHeader; Mac manners (hover wash
/// on the door, tooltip) replace the haptic.
struct CosmoShelfHeader: View {
    let title: String
    var detail: String? = nil
    /// Present = the whole header is a door (chevron joins the title).
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                content
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Open \(title)'s board")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            // The count rides the title ("Ben Rowe · 3") — a lone numeral
            // parked at the far trailing edge reads dashboard, not editorial.
            HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
                Text(title)
                    .font(DS.editorialHeader)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if let detail {
                    Text("· \(detail)")
                        .font(DS.subheadline.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                }
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(DS.subheadline.weight(.bold))
                        .foregroundStyle(isHovered ? DS.textSecondary : DS.textMuted)
                        .offset(x: isHovered ? 2 : 0)
                        .animation(ProMotionSprings.hover, value: isHovered)
                }
            }
            Spacer(minLength: DS.space8)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension Character {
    /// Emoji in the identity sense: pictographic presentation — never a
    /// bare digit or symbol that merely *can* render as emoji.
    var isIdentityEmoji: Bool {
        if unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return true }
        // Multi-scalar sequences (ZWJ families, skin tones, flags).
        return unicodeScalars.first?.properties.isEmoji == true && unicodeScalars.count > 1
    }
}
