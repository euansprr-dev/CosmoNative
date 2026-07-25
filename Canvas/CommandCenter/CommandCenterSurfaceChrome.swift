import SwiftUI

/// The Command Center's right rail — an INTEGRATED sidebar (the Things /
/// Fantastical / Apple split-view grammar, and the Concept navigator's exact
/// material): flat `DS.surface` on the page plane, full height, one leading
/// hairline, no glass, no shadow. Glass is for chrome; habits, reports, and
/// the task inspector are CONTENT — and content never levitates. A floating
/// pane's shadow outranked the page's actual hierarchy (elevation says
/// "look here" while habits are the day's quietest content).
struct CommandCenterRail<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.space12)
            .padding(.top, DS.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DS.surface)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DS.borderSubtle)
                    .frame(width: 0.5)
            }
    }
}

struct CommandCenterMaterialPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 10, contentPadding: CGFloat = DS.space10, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(DS.commandChromePanelFill, in: .rect(cornerRadius: cornerRadius))
            .commandCenterCardLift(cornerRadius: cornerRadius, restingBorder: DS.commandChromeBorder)
    }
}

/// Resting → hover card depth for Command Center content cards.
///
/// Adopts the Greenhouse Glass "controls float above content" signature: at rest it is
/// pixel-identical to a `commandChromeBorder` hairline + `dsRestingShadow()`; on hover it
/// lifts to a `glassBorderFocused` hairline + `dsHoverShadow()` depth. Per
/// `GREENHOUSE_GLASS.md` §7.1 every property is driven by *value* (ternaries on
/// color/opacity/radius/lineWidth) — never by branching structure — so a hover never
/// rebuilds the wrapped subtree, never drops child identity, never restarts inner state.
/// It owns its own hover flag and animates with `ProMotionSprings.hover`. Purely additive
/// depth: it changes no layout and touches no existing hover/selection/completion behavior.
struct CommandCenterCardLift: ViewModifier {
    var cornerRadius: CGFloat
    var restingBorder: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let isDark = DS.palette.isDark
        return content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovered ? DS.glassBorderFocused : restingBorder,
                            lineWidth: isHovered ? 1 : 0.5)
            }
            // Two-layer shadow interpolating dsRestingShadow() → dsHoverShadow().
            .shadow(color: .black.opacity(isHovered ? (isDark ? 0.4 : 0.06) : (isDark ? 0.3 : 0.04)),
                    radius: isHovered ? (isDark ? 8 : 16) : (isDark ? 4 : 8),
                    x: 0, y: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2))
            .shadow(color: .black.opacity(isHovered ? (isDark ? 0.25 : 0.03) : (isDark ? 0.2 : 0.02)),
                    radius: isHovered ? (isDark ? 2 : 4) : (isDark ? 1 : 2),
                    x: 0, y: isHovered ? (isDark ? 1 : 2) : (isDark ? 0 : 1))
            .animation(ProMotionSprings.hover, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Apply Command Center resting→hover card depth. See `CommandCenterCardLift`.
    func commandCenterCardLift(cornerRadius: CGFloat,
                              restingBorder: Color = DS.commandChromeBorder) -> some View {
        modifier(CommandCenterCardLift(cornerRadius: cornerRadius, restingBorder: restingBorder))
    }
}

struct CommandCenterLedgerSectionHeader: View {
    let title: String
    let count: String?
    let tint: Color
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.space6) {
            Text(title)
                .font(DS.caption).fontWeight(.semibold)
                .foregroundStyle(tint)

            if let count {
                Text(count)
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(tint.opacity(0.62))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
                .padding(.leading, DS.space8)

            Spacer(minLength: 0)

            if let actionTitle, let actionIcon, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(DS.caption)
                        .foregroundStyle(tint.opacity(0.9))
                        .padding(.horizontal, DS.space6)
                        .padding(.vertical, DS.space4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
    }
}

/// The ledger row's resting/hover/selected chrome.
///
/// Every shadow here has to fall off inside the `DS.space8` this glass is inset
/// by in the row (`DashboardTaskRow`): past that gutter the ledger's ScrollView
/// clips, and a radius that overruns it ends in a straight vertical line down
/// the row's sides. Keep radii ≤ 6.
struct CommandCenterRowGlass: View {
    let isActive: Bool
    let isSelected: Bool
    let isHovered: Bool
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke, lineWidth: isSelected ? 1 : 0.5)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var fill: Color {
        if isActive { return DS.glassInputFillFocused }
        if isSelected { return tint.opacity(0.10) }
        if isHovered { return DS.glassCardFill }
        return Color.clear
    }

    private var stroke: Color {
        if isActive { return tint.opacity(0.36) }
        if isSelected { return tint.opacity(0.26) }
        if isHovered { return DS.glassBorder }
        return Color.clear
    }

    private var shadowColor: Color {
        (isActive || isSelected || isHovered) ? Color.black.opacity(0.055) : Color.clear
    }

    private var shadowRadius: CGFloat {
        // 6, not 8: at 8 the selected/active row's falloff reached the clip
        // exactly and terminated on a hard edge — the same defect as the drag
        // shadow, just two shades fainter.
        isActive || isSelected ? 6 : (isHovered ? 4 : 0)
    }

    private var shadowY: CGFloat {
        isActive || isSelected ? 2 : (isHovered ? 1 : 0)
    }
}

struct CommandCenterEmptyPane: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.textMuted)
                .frame(width: 44, height: 44)

            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text(subtitle)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space24)
        .padding(.horizontal, DS.space16)
        .dsGlassCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}
