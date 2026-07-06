// CosmoOS/Navigation/NavigationTrail.swift
// Universal back/forward — a time-ordered trail of every place you've been:
// sidebar destinations, thinkspaces, and focus modes. Cmd+[ / Cmd+] from anywhere.
// Trail jumps replay the destination's own transition; the trail never invents one.

import SwiftUI

// MARK: - Navigation Trail Model

/// Records every arrival at a main-view destination or focus mode as a moment,
/// giving the whole app browser-grade back/forward. Pane focus changes and peeks
/// are deliberately not moments — only real "places" enter the trail.
///
/// Recency-unique law: a place lives at most once in the trail. Re-arriving
/// somewhere hoists it to the top instead of stacking a duplicate, so Back
/// walks distinct places in recency order — hopping deep dive ↔ inquiry
/// session (or folder in/out) all afternoon never turns Back into a circle.
@MainActor
@Observable
final class NavigationTrail {

    static let shared = NavigationTrail()

    // MARK: Moment

    struct Moment: Equatable, Identifiable {
        enum Destination: Equatable {
            case sidebar(SidebarDestination)
            case focusMode(EntitySelection)
            /// A folder opened inside a thinkspace's library mode — a real
            /// place in the trail, so the universal arrows walk in and out
            /// of folders instead of a bespoke breadcrumb.
            case libraryFolder(thinkspaceId: String, folderID: UUID)
        }

        let id: UUID
        let destination: Destination
        var title: String
        let glyph: String
        let timestamp: Date
    }

    // MARK: State

    private(set) var backStack: [Moment] = []
    private(set) var forwardStack: [Moment] = []
    private(set) var current: Moment?

    /// True while a back/forward jump is applying its state changes, so the
    /// resulting onChange arrivals don't re-record themselves.
    private(set) var isApplyingJump = false

    private let capacity = 300

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    // MARK: Recording

    func recordArrival(_ destination: Moment.Destination, title: String, glyph: String) {
        guard !isApplyingJump else { return }
        guard current?.destination != destination else { return }
        if let current {
            backStack.removeAll { $0.destination == current.destination }
            backStack.append(current)
        }
        backStack.removeAll { $0.destination == destination }
        if backStack.count > capacity {
            backStack.removeFirst(backStack.count - capacity)
        }
        forwardStack.removeAll()
        current = Moment(id: UUID(), destination: destination, title: title, glyph: glyph, timestamp: Date())
    }

    /// Upgrade a moment's title once a richer one resolves (e.g. the atom's real
    /// title arriving from the database after a focus-mode moment was recorded).
    func refineTitle(_ title: String, for destination: Moment.Destination) {
        guard !title.isEmpty else { return }
        if current?.destination == destination { current?.title = title }
        for index in backStack.indices where backStack[index].destination == destination {
            backStack[index].title = title
        }
        for index in forwardStack.indices where forwardStack[index].destination == destination {
            forwardStack[index].title = title
        }
    }

    // MARK: Jumps

    func stepBack() -> Moment? {
        guard let target = backStack.popLast() else { return nil }
        if let current { forwardStack.append(current) }
        current = target
        return target
    }

    func stepForward() -> Moment? {
        guard let target = forwardStack.popLast() else { return nil }
        if let current { backStack.append(current) }
        current = target
        return target
    }

    /// Jump several steps back at once (trail popover selection).
    func jumpBack(to momentID: UUID) -> Moment? {
        guard backStack.contains(where: { $0.id == momentID }) else { return nil }
        var landed: Moment?
        while let hop = stepBack() {
            landed = hop
            if hop.id == momentID { break }
        }
        return landed
    }

    func recentBackTrail(limit: Int = 10) -> [Moment] {
        Array(backStack.suffix(limit).reversed())
    }

    /// Wrap the state changes that *apply* a jump so the resulting arrivals
    /// don't push duplicate moments.
    func applyingJump(_ apply: () -> Void) {
        isApplyingJump = true
        apply()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            self.isApplyingJump = false
        }
    }

    /// Drop moments that no longer resolve (deleted thinkspace or atom).
    func prune(matching isStale: (Moment) -> Bool) {
        backStack.removeAll(where: isStale)
        forwardStack.removeAll(where: isStale)
    }
}

// MARK: - Trail Chrome (chevron capsule)

/// The floating back/forward control in the app shell's top-left.
/// Ghost-quiet until the trail has history; long-press the back chevron
/// for the recent-trail popover (Safari idiom).
struct NavigationTrailChrome: View {
    let onBack: () -> Void
    let onForward: () -> Void
    let onJump: (NavigationTrail.Moment) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTrail = false
    @State private var isChromeHovered = false

    private var trail: NavigationTrail { .shared }
    private var hasTrail: Bool { trail.canGoBack || trail.canGoForward }

    var body: some View {
        HStack(spacing: 2) {
            TrailChevronButton(
                symbol: "chevron.left",
                enabled: trail.canGoBack,
                help: "Back (⌘[)",
                label: "Back",
                action: onBack,
                onLongPress: { showTrail = true }
            )
            TrailChevronButton(
                symbol: "chevron.right",
                enabled: trail.canGoForward,
                help: "Forward (⌘])",
                label: "Forward",
                action: onForward,
                onLongPress: nil
            )
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
        // Ghost chrome: nearly silent until the pointer arrives, so it never
        // competes with page titles sitting close beneath it.
        .opacity(hasTrail ? (isChromeHovered || showTrail ? 1 : 0.4) : 0)
        .allowsHitTesting(hasTrail)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
                isChromeHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: hasTrail)
        .popover(isPresented: $showTrail, arrowEdge: .bottom) {
            TrailPopover(moments: trail.recentBackTrail()) { moment in
                showTrail = false
                onJump(moment)
            }
        }
    }
}

// MARK: - Chevron Button

private struct TrailChevronButton: View {
    let symbol: String
    let enabled: Bool
    let help: String
    let label: String
    let action: () -> Void
    let onLongPress: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var didLongPress = false

    var body: some View {
        Image(systemName: symbol)
            .font(DS.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: 30, height: 24)
            .background(Capsule().fill(isHovered && enabled ? DS.glassCardFill : .clear))
            .contentShape(Capsule())
            .scaleEffect(isPressed && enabled ? 0.97 : 1)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
            }
            .onTapGesture(perform: handleTap)
            .simultaneousGesture(pressGesture)
            .simultaneousGesture(longPressGesture)
            .help(help)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        guard enabled else { return DS.textMuted.opacity(0.4) }
        return isHovered ? DS.text : DS.textSecondary
    }

    private func handleTap() {
        if didLongPress {
            didLongPress = false
            return
        }
        guard enabled else { return }
        action()
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                withAnimation(ProMotionSprings.press) { isPressed = true }
            }
            .onEnded { _ in
                withAnimation(ProMotionSprings.release) { isPressed = false }
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                guard enabled, let onLongPress else { return }
                didLongPress = true
                onLongPress()
            }
    }
}

// MARK: - Trail Popover

private struct TrailPopover: View {
    let moments: [NavigationTrail.Moment]
    let onSelect: (NavigationTrail.Moment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Recent")
                .font(DS.caption)
                .tracking(0.3)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(moments) { moment in
                TrailPopoverRow(moment: moment) { onSelect(moment) }
            }
        }
        .padding(6)
        .frame(width: 264)
    }
}

private struct TrailPopoverRow: View {
    let moment: NavigationTrail.Moment
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: moment.glyph)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18)
                Text(moment.title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(moment.timestamp, format: .relative(presentation: .named))
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("Go back to \(moment.title)")
    }
}
