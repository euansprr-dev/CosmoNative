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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: String, countText: String? = nil) {
        self.label = label
        self.countText = countText
    }

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(label)
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                // giltInk, not giltMuted: gilt CARRYING TEXT must clear AA;
                // giltMuted stays ornament (rules, diamonds).
                .foregroundStyle(DS.giltInk)
            Rectangle()
                .fill(marginaliaRuleColor)
                .frame(height: 0.5)
            if let countText {
                // Counts are alive (the surface-system reward loop): they tick
                // with the work instead of re-laying out.
                // DS.keycap: the one mono voice — a hand-typed 9pt sat below
                // the DS's own smallest-readable floor.
                Text(countText)
                    .font(DS.keycap)
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: countText)
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
    /// At rest the rail sits just below full ink — faint marginalia until the
    /// pointer drifts over it, which brings it to 1.
    static let restOpacity: Double = 0.8
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

// MARK: - Workbench shell (the bench anatomy)

/// The app has two window species. **Rooms** (Notes, Content) are immersive
/// paper — chrome recedes, nothing between you and the text. **Benches**
/// (Study, Concept Desk, Idea) are places you work on a thing with
/// instruments around it: a navigation band up top, and beneath it the whole
/// working area clipped into ONE rounded sheet whose columns are welded by
/// hairlines. This is the bench's sheet — the mechanics extracted from the
/// Study shell (July 2026) so every bench displaces, overlays, and clips
/// identically. Panels self-size and carry their own `studyPanelSurface`;
/// the caller owns breakpoint policy and passes `panelsDisplace`.
struct WorkbenchShell<Leading: View, Center: View, Trailing: View>: View {
    /// True at regular widths: panels sit beside the center as true columns.
    /// False below: panels slide OVER the center, inside the sheet.
    var panelsDisplace: Bool
    var isLeadingShowing: Bool
    var isTrailingShowing: Bool
    /// Narrowest widths: a whisper of scrim behind overlay panels; tap
    /// dismisses (the Study's `.narrow` manner).
    var showsScrim: Bool = false
    var onScrimTap: () -> Void = {}
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing

    /// The sheet no longer carries a `cornerRadius` knob. A bench renders BOTH
    /// full-screen and inside a pane — two different containers — so a corner
    /// this view could name would be wrong in one of them. `cosmoInnerWindow`
    /// resolves it against whichever container it actually landed in, and owns
    /// the insets the callers used to repeat.
    var body: some View {
        ZStack {
            columns
            if showsScrim, !panelsDisplace, isLeadingShowing || isTrailingShowing {
                scrim
            }
            if !panelsDisplace {
                overlayPanels
            }
        }
        .background(DS.bg)
        .cosmoInnerWindow()
    }

    /// At regular width the panels are true columns of the sheet — welded by
    /// their hairlines, clipped by the sheet's one rounded edge.
    ///
    /// LAW: the shell itself never animates panel insertion — the slide only
    /// runs when the toggle site wraps its state change in `withAnimation`
    /// (every bench's toolbar/keyboard/scrim site already does). An implicit
    /// `.animation(value:)` here also animated BREAKPOINT-driven seats, and
    /// the first width resolve after mount is one of those: the column
    /// inserted inside the bench's own entrance transaction, whose teardown
    /// orphaned the slide mid-flight — panel laid out and hit-testable but
    /// never composited (the invisible idea inspector, July 2026). Breakpoint
    /// seats are instant by design; only user toggles animate.
    private var columns: some View {
        HStack(spacing: 0) {
            if panelsDisplace, isLeadingShowing {
                leading()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            center()
                .frame(maxWidth: .infinity)
            if panelsDisplace, isTrailingShowing {
                trailing()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    /// Below regular width the panels slide OVER the center inside the sheet.
    /// Same law as `columns`: the transaction comes from the toggle site.
    private var overlayPanels: some View {
        HStack(spacing: 0) {
            if isLeadingShowing {
                leading()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if isTrailingShowing {
                trailing()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.10)
            .transition(.opacity)
            .onTapGesture(perform: onScrimTap)
            .accessibilityLabel("Dismiss panels")
    }
}

// MARK: - Stagger-in modifier

/// Reduce Motion keeps the fade and drops the rise (the surface-system rule);
/// a ViewModifier so the environment is readable.
private struct AtelierStaggerIn: ViewModifier {
    let delay: Double
    let appeared: Bool
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(.easeOut(duration: duration).delay(delay), value: appeared)
    }
}

extension View {
    /// Fade + 8pt rise with a delay. Applied to each manuscript section so the
    /// page settles from top to bottom on open. The content the user came to
    /// read must lead the settle (near-zero delay, quick duration) — only
    /// ornaments earn a longer stagger.
    func atelierStaggerIn(delay: Double, appeared: Bool, duration: Double = 0.55) -> some View {
        modifier(AtelierStaggerIn(delay: delay, appeared: appeared, duration: duration))
    }
}
