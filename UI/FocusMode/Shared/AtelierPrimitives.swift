// CosmoOS/UI/FocusMode/Shared/AtelierPrimitives.swift
// Shared primitives for the Akashic Codex aesthetic used by both Idea Focus Mode
// (The Atelier) and Content Focus Mode (The Scriptorium).
//
// Every token, ornament, and motion here is load-bearing — if you change something,
// you are changing the feel of both focus modes simultaneously. That's intentional.

import SwiftUI

// MARK: - Section label (left-flush, hair-rule to the right)

/// Small-caps section label sitting at the left edge with a hair-rule extending
/// rightward to fill the column. Used for every section inside the manuscript
/// column (HOOKS, OUTLINE, SCORE, CRITIQUE).
struct AtelierOrnamentalSectionLabel: View {
    let label: String

    var body: some View {
        HStack(spacing: DS.space12) {
            Text(label)
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)
                .fixedSize()
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Marginalia label (gutter section header)

/// Small-caps label with a hair-rule and optional trailing mono count. Used for
/// every section inside a marginalia gutter (SWIPES, FRAMEWORK, SOURCE, etc).
struct MarginaliaLabel: View {
    let label: String
    let countText: String?

    init(_ label: String, countText: String? = nil) {
        self.label = label
        self.countText = countText
    }

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(label)
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)
            Rectangle()
                .fill(marginaliaRuleColor)
                .frame(height: 0.5)
            if let countText {
                // Counts are alive (the surface-system reward loop): they tick
                // with the work instead of re-laying out.
                Text(countText)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
                    .contentTransition(.numericText())
                    .animation(ProMotionSprings.gentle, value: countText)
            }
        }
    }

    private var marginaliaRuleColor: Color {
        DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder.opacity(0.9) : DS.sepiaSubtle
    }
}

// MARK: - Marginalia rail policy (shared calm rules)

/// The shared "quiet margins" rules both focus modes obey.
enum MarginaliaRailPolicy {
    /// Rails fall to a whisper while the user is actively typing.
    static let whisperOpacity: Double = 0.25
}

// MARK: - Marginalia disclosure section

/// The one section container for margin rails: the header (small-caps label +
/// hair-rule + live count) is itself the disclosure toggle. Collapsed, a
/// section is a single quiet line; a 3pt gilt diamond at the rule's end marks
/// that there is more (and appears on hover as the affordance). Expansion
/// persists per section via AppStorage.
struct MarginaliaDisclosureSection<Content: View>: View {
    let label: String
    var countText: String?
    var spacing: CGFloat = DS.space10

    @AppStorage private var isExpanded: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ label: String,
        countText: String? = nil,
        storageKey: String,
        defaultExpanded: Bool = false,
        spacing: CGFloat = DS.space10,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.countText = countText
        self.spacing = spacing
        self._isExpanded = AppStorage(wrappedValue: defaultExpanded, "marginalia.\(storageKey)")
        self.content = content
    }

    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            if isExpanded {
                content()
                    .transition(reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isExpanded)
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: DS.space8) {
                MarginaliaLabel(label, countText: countText)
                if isHovered || !isExpanded {
                    Rectangle()
                        .fill(isHovered ? DS.gilt : DS.giltMuted)
                        .frame(width: 3, height: 3)
                        .rotationEffect(.degrees(45))
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help(isExpanded ? "Collapse \(label.lowercased())" : "Expand \(label.lowercased())")
        .accessibilityLabel("\(label) section")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }
}

// MARK: - Marginalia hover reveal

/// Row-level controls (remove ✕, edit links) stay invisible until the rail is
/// hovered — at rest the margins are pure typography.
struct MarginaliaHoverReveal: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(ProMotionSprings.hover, value: visible)
            .allowsHitTesting(visible)
    }
}

extension View {
    func marginaliaHoverReveal(_ visible: Bool) -> some View {
        modifier(MarginaliaHoverReveal(visible: visible))
    }
}

// MARK: - Marginalia link hover

/// The one hover treatment for the serif arrow-links in the gutters
/// ("open assistant →", "select blueprint →"): ink deepens and the link leans
/// forward a hair — life without chrome, per the manners pass.
struct MarginaliaLinkHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovered ? -0.06 : 0)
            .offset(x: isHovered ? 1 : 0)
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) { isHovered = hovering }
            }
    }
}

extension View {
    func marginaliaLinkHover() -> some View {
        modifier(MarginaliaLinkHover())
    }
}

// MARK: - Gilt-bracketed CTA

/// Serif label flanked by four L-brackets (`GiltCornerBracket`). No background,
/// no border. On hover the brackets extend outward 2pt via a spring. This is the
/// one CTA pattern used anywhere in the Atelier/Scriptorium system.
struct GiltBracketedCTA: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                Text(title)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .italic(isHovered)
                    .foregroundStyle(DS.text)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.gilt.opacity(0.8))
            }
            .padding(.horizontal, DS.space20)
            .padding(.vertical, DS.space12)
            .overlay(alignment: .topLeading) { bracket(rotation: 0) }
            .overlay(alignment: .topTrailing) { bracket(rotation: 90) }
            .overlay(alignment: .bottomTrailing) { bracket(rotation: 180) }
            .overlay(alignment: .bottomLeading) { bracket(rotation: 270) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
    }

    private func bracket(rotation: Double) -> some View {
        GiltCornerBracket()
            .stroke(DS.gilt, lineWidth: 0.8)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .offset(
                x: rotation == 0 || rotation == 270 ? (isHovered ? -2 : 0) : (isHovered ? 2 : 0),
                y: rotation == 0 || rotation == 90 ? (isHovered ? -2 : 0) : (isHovered ? 2 : 0)
            )
    }
}

// MARK: - Atelier sheet header

/// A 16pt vertical header for an Atelier/Scriptorium sheet: small-caps title on
/// the left, xmark dismiss on the right, hair-rule beneath. Handles escape.
struct AtelierSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(DS.smallCaps)
                .tracking(2.0)
                .foregroundStyle(DS.giltMuted)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
        }
    }
}

// MARK: - Stagger-in modifier

extension View {
    /// Fade + 8pt rise with a delay. Applied to each manuscript section so the
    /// page settles from top to bottom on open.
    func atelierStaggerIn(delay: Double, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(.easeOut(duration: 0.55).delay(delay), value: appeared)
    }
}
