import SwiftUI

// MARK: - Card surface

/// Card surface for the rebuilt swipe surfaces: warm glass fill, low tint wash,
/// focus-aware hairline, and ONE static resting shadow. Hover reads through the
/// border + tint + the caller's 1.01 scale — shadow parameters never animate
/// (re-blurring hundreds of cards was the old grid's biggest GPU cost).
struct SwipeCardSurfaceModifier: ViewModifier {
    var isHovered = false
    var isSelected = false
    var tint: Color = DS.accent
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = DS.palette.isDark
        return content
            .background(tint.opacity(isHovered ? 0.10 : 0.06), in: shape)
            .background(DS.glassCardFill, in: shape)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? DS.accent.opacity(0.55) : (isHovered ? DS.glassBorderFocused : DS.glassBorder),
                    lineWidth: isSelected ? 2 : (isHovered ? 1 : 0.5)
                )
            )
            .shadow(color: .black.opacity(isDark ? 0.28 : 0.05), radius: isDark ? 5 : 10, x: 0, y: 2)
    }
}

extension View {
    func swipeCardSurface(
        isHovered: Bool = false,
        isSelected: Bool = false,
        tint: Color = DS.accent,
        cornerRadius: CGFloat = 14
    ) -> some View {
        modifier(SwipeCardSurfaceModifier(
            isHovered: isHovered,
            isSelected: isSelected,
            tint: tint,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Page background

struct SwipePageBackground: View {
    var body: some View {
        DS.swipeLibraryBackground
            .ignoresSafeArea()
    }
}

// MARK: - Platform brand color

extension SocialPlatform {
    /// Brand color for the tiny platform glyph — the single sanctioned place the
    /// swipe surfaces use non-DS hex. These are external brand identities that
    /// can't map to Greenhouse tokens; all other chrome uses warm DS.
    var swipeBrandColor: Color {
        switch self {
        case .instagram: return Color(hex: "#E1306C")
        case .youtube: return Color(hex: "#E0322B")
        case .linkedin: return Color(hex: "#0A66C2")
        case .facebook: return Color(hex: "#1877F2")
        case .substack: return Color(hex: "#E06A38")
        case .tiktok, .x, .twitter, .threads, .medium: return Color(hex: "#1C1C20")
        case .other: return DS.textMuted
        }
    }

    /// Maps the library's string platform keys (atom metadata) onto the shared enum.
    static func fromLibraryKey(_ key: String?) -> SocialPlatform? {
        switch key {
        case "youtube", "youtubeShort", "youtube_short": return .youtube
        case "instagram", "instagramPost", "instagram_post",
             "instagramReel", "instagram_reel",
             "instagramCarousel", "instagram_carousel": return .instagram
        case "xPost", "x_post", "twitter": return .x
        case "threads": return .threads
        case "tiktok": return .tiktok
        case "linkedin": return .linkedin
        case "substack": return .substack
        default: return nil
        }
    }
}

// MARK: - Formatting

enum SwipeFormatting {
    static func count(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// "17h", "2d", "3w" — the quiet age stamp on card meta rows.
    static func compactAge(from date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        if months < 12 { return "\(max(months, 1))mo" }
        return "\(days / 365)y"
    }

    static func duration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// Engagement rate stored either pre-multiplied (6.4 → "6.4%") or as a raw
    /// fraction (0.064 → "6.4%"); both provider conventions render correctly.
    static func engagementRate(_ rate: Double) -> String {
        let pct = rate < 1 ? rate * 100 : rate
        return String(format: "%.1f%%", pct)
    }
}
