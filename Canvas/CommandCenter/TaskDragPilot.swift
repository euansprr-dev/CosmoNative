// Canvas/CommandCenter/TaskDragPilot.swift
// One live task drag for the whole Command Center. There is no system drag
// session any more: the row itself lifts under the pointer and its band
// reorders live (iOS Today parity), and the surfaces outside the list — the
// sidebar's smart lists, project rows, the Day Spine's blocks and time slots —
// register themselves as zones the travelling row can be dropped into.
//
// Why not `.draggable`/`.dropDestination`: a system drag can't reorder live
// (the original row sits still under a floating ghost), it has no observable
// end (the old code inferred the session's lifetime from the preview view's
// onAppear/onDisappear and needed a hover watchdog to un-stick it), and its
// insertion indicator disagreed with the index it committed.
// July 2026

import SwiftUI
import AppKit

// MARK: - The shared drag space

/// The one coordinate space every drag-aware Command Center surface measures
/// in: declared on the dashboard root, so the sidebar, the ledger and the Day
/// Spine all speak the same points.
enum CommandCenterDragSpace {
    static let name = "cc-task-drag"
}

// MARK: - The pilot

@MainActor
@Observable
final class TaskDragPilot {

    static let shared = TaskDragPilot()

    /// What a released row did, so the band knows whether to commit its
    /// reorder or glide the row home untouched.
    enum Landing {
        /// The pointer never left the ledger — the band owns this drop.
        case band
        /// A zone outside the ledger took the task.
        case zone(id: String)
        /// Travelled out and landed on nothing.
        case nowhere
    }

    // MARK: Observed state

    /// A row is riding the pointer. Coarse — flips twice per drag.
    private(set) var liftedTaskUUID: String?

    /// The pointer has left the ledger column: the lifted row hands off to the
    /// travel card, and the band stops shuffling (a row on its way to the
    /// sidebar is not being reordered).
    private(set) var isTravelling = false

    /// The zone under the pointer. Zones observe *only* this, so a pointer move
    /// repaints the one zone whose answer changed — never all of them.
    private(set) var hoveredZoneID: String?

    /// The travel card's anchor, in dashboard space. Written every frame of a
    /// travel, so ONLY the travel card may read it — any other reader would
    /// repaint itself 120 times a second.
    private(set) var pointer: CGPoint = .zero

    /// The travelling row's title, for the card.
    private(set) var travelTitle = ""

    /// True from the instant a lift begins until just after the drop's mouse-up
    /// has been consumed. A row's tap — and its checkbox and play button — fire
    /// on that mouse-up: SwiftUI's Button and TapGesture do not know a drag
    /// happened. So every row action asks this before acting, or dropping a task
    /// opens it (and a short drag off the checkbox completes it). The pane deck's
    /// tab strip and the iOS Today lift both learned this the same way.
    ///
    /// Untracked: it is read inside gesture and button closures, never in a body,
    /// so it must not invalidate a single row.
    @ObservationIgnored private(set) var suppressesRowTap = false
    @ObservationIgnored private var tapSuppressionToken = 0

    // MARK: Untracked plumbing
    //
    // Frames and callbacks are written during layout and read inside gesture
    // handlers. Keeping them out of observation means a zone re-measuring
    // itself (every scroll tick) invalidates nothing.

    @ObservationIgnored private var zones: [String: Zone] = [:]
    @ObservationIgnored private var ledgerFrame: CGRect = .zero
    @ObservationIgnored private let edgeScroller = TaskListEdgeScroller()

    private struct Zone {
        var frame: CGRect
        var drop: (String, CGPoint) -> Bool
    }

    /// How far outside the ledger's side edges the pointer goes before the row
    /// stops being a reorder and starts being a delivery.
    private static let travelSlack: CGFloat = 10

    // MARK: Zone registry

    func registerZone(id: String, frame: CGRect, drop: @escaping (String, CGPoint) -> Bool) {
        zones[id] = Zone(frame: frame, drop: drop)
    }

    func unregisterZone(id: String) {
        zones.removeValue(forKey: id)
        if hoveredZoneID == id { hoveredZoneID = nil }
    }

    /// The ledger column's frame — the fence that separates "reordering" from
    /// "carrying this somewhere".
    func registerLedger(frame: CGRect) {
        ledgerFrame = frame
    }

    /// The list's scroll view, for edge autoscroll during a lift.
    func attachScrollView(_ scrollView: NSScrollView?) {
        edgeScroller.attach(scrollView)
    }

    // MARK: Session

    func begin(taskUUID: String, title: String, at point: CGPoint) {
        liftedTaskUUID = taskUUID
        travelTitle = title
        pointer = point
        isTravelling = false
        hoveredZoneID = nil
        suppressesRowTap = true
        tapSuppressionToken += 1
        Sound.dragPickup()
        NSCursor.closedHand.push()
    }

    func update(pointer point: CGPoint) {
        guard liftedTaskUUID != nil else { return }

        let travelling = isOutsideLedger(point)
        // `pointer` is the one per-frame observed property in the app's task
        // surfaces, so it is only written while the travel card is actually on
        // screen (plus the frame it leaves) — an in-band reorder repaints rows,
        // never the card.
        if travelling || isTravelling { pointer = point }
        if travelling != isTravelling { isTravelling = travelling }

        let zone = travelling ? zoneID(under: point) : nil
        if zone != hoveredZoneID { hoveredZoneID = zone }

        // The ledger only scrolls itself while the row is still in it — chasing
        // the pointer across the sidebar would scroll the list out from under
        // the drop.
        edgeScroller.setActive(!travelling)
    }

    /// Ends the session and reports where the row landed. The band is the only
    /// caller; it commits (or abandons) its reorder on the answer.
    func end() -> Landing {
        defer { reset() }
        guard let taskUUID = liftedTaskUUID else { return .nowhere }
        guard isTravelling else { return .band }
        guard let zoneID = hoveredZoneID, let zone = zones[zoneID] else { return .nowhere }
        let local = CGPoint(x: pointer.x - zone.frame.minX, y: pointer.y - zone.frame.minY)
        guard zone.drop(taskUUID, local) else { return .nowhere }
        Sound.dragDrop()
        return .zone(id: zoneID)
    }

    func cancel() {
        reset()
    }

    private func reset() {
        guard liftedTaskUUID != nil else { return }
        liftedTaskUUID = nil
        isTravelling = false
        hoveredZoneID = nil
        travelTitle = ""
        edgeScroller.setActive(false)
        NSCursor.pop()

        // Let the drop's mouse-up land and be swallowed, then re-arm row taps.
        // Tokenised so a fresh lift inside the window keeps its own suppression.
        let token = tapSuppressionToken
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard token == tapSuppressionToken else { return }
            suppressesRowTap = false
        }
    }

    // MARK: Geometry

    private func isOutsideLedger(_ point: CGPoint) -> Bool {
        guard ledgerFrame.width > 0 else { return false }
        return point.x < ledgerFrame.minX - Self.travelSlack
            || point.x > ledgerFrame.maxX + Self.travelSlack
    }

    /// The topmost registered zone containing the pointer. Registration order
    /// is meaningless in a dictionary, so ties break on area — the smallest
    /// zone wins, which is what makes a block card inside the Day Spine's
    /// time-slot canvas catch the drop instead of the canvas behind it.
    private func zoneID(under point: CGPoint) -> String? {
        zones
            .filter { $0.value.frame.contains(point) }
            .min { lhs, rhs in
                lhs.value.frame.width * lhs.value.frame.height < rhs.value.frame.width * rhs.value.frame.height
            }?
            .key
    }
}

// MARK: - Zone registration

extension View {
    /// Registers this surface as a place a travelling task row can be dropped.
    /// `drop` receives the task uuid and the pointer in the surface's own
    /// coordinates; return false to refuse it.
    ///
    /// Additive on purpose: the existing `.dropDestination(for: String.self)`
    /// stays, because other surfaces (Library, ⌘K drag-out, the Thinkspace
    /// sidebar) still hand out task uuids through system drags.
    func taskDropZone(
        id: String,
        isEnabled: Bool = true,
        drop: @escaping (String, CGPoint) -> Bool
    ) -> some View {
        modifier(TaskDropZoneModifier(id: id, isEnabled: isEnabled, drop: drop))
    }

    /// Marks the ledger column — the fence a lifted row crosses to become a
    /// delivery instead of a reorder.
    func taskDragLedger() -> some View {
        modifier(TaskDragLedgerModifier())
    }

    /// Hands the pilot the ledger's `NSScrollView` for edge autoscroll. Must be
    /// applied to content INSIDE the scroll view — from outside, `enclosingScrollView`
    /// finds the wrong one (or none).
    func taskDragScrollAnchor() -> some View {
        background(TaskListScrollAnchor())
    }
}

private struct TaskDropZoneModifier: ViewModifier {
    let id: String
    let isEnabled: Bool
    let drop: (String, CGPoint) -> Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(CommandCenterDragSpace.name))
            } action: { frame in
                guard isEnabled else {
                    TaskDragPilot.shared.unregisterZone(id: id)
                    return
                }
                TaskDragPilot.shared.registerZone(id: id, frame: frame, drop: drop)
            }
            .onDisappear { TaskDragPilot.shared.unregisterZone(id: id) }
    }
}

private struct TaskDragLedgerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(CommandCenterDragSpace.name))
            } action: { frame in
                TaskDragPilot.shared.registerLedger(frame: frame)
            }
    }
}

// MARK: - The travel card

/// The row-shaped card a task becomes once it leaves the ledger. The lifted row
/// stays behind as a hole in the list, so there is never a ghost hovering over
/// its own original (the tell of the old system drag).
struct TaskDragTravelCard: View {
    private var pilot: TaskDragPilot { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Structure never branches on the drag (the structural-identity law):
        // the card is always mounted and rides opacity, so a travel that starts
        // mid-flight can't restart its own transition.
        let isVisible = pilot.isTravelling
        HStack(spacing: DS.space6) {
            Circle()
                .stroke(DS.entityTask.opacity(0.5), lineWidth: 1.5)
                .frame(width: 12, height: 12)

            Text(pilot.travelTitle)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
        // A fixed card width: inside an overlay the proposal is the whole
        // dashboard, and a flexible frame would stretch the card across it.
        .frame(width: 232, alignment: .leading)
        .background(DS.vellum, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .stroke(pilot.hoveredZoneID == nil ? DS.giltMuted : DS.accent.opacity(0.55), lineWidth: 0.75)
        )
        .dsFloatingShadow()
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.94, anchor: .topLeading)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isVisible)
        // The offset sits OUTSIDE that animation on purpose: inside it, the
        // frame the card appears on would animate its position too and the card
        // would fly in from the corner. The card tracks the pointer raw; only
        // its arrival is sprung.
        //
        // It hangs below-right of the pointer so the cursor — and the zone it is
        // aiming at — stay visible.
        .offset(x: pilot.pointer.x + DS.space12, y: pilot.pointer.y + DS.space8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Edge autoscroll

/// Plants an invisible view in the ledger so the pilot can find the enclosing
/// `NSScrollView` — SwiftUI exposes no scroll offset to write to, and a drag
/// that can't reach past the visible rows isn't a reorder, it's a puzzle.
private struct TaskListScrollAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            TaskDragPilot.shared.attachScrollView(view.enclosingScrollView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            TaskDragPilot.shared.attachScrollView(scrollView)
        }
    }
}

/// Scrolls the ledger when a lifted row dwells against its top or bottom edge.
///
/// Driven by a timer rather than the drag's own change events: a hand held
/// still at the edge produces no events, and "the list stops scrolling unless I
/// keep jiggling" is the single most common home-made-reorder tell. The timer
/// runs in `.common` mode so it survives AppKit's event-tracking run loop, and
/// reads `NSEvent.mouseLocation` directly — the pointer's truth needs no
/// coordinate-space conversion.
@MainActor
private final class TaskListEdgeScroller {

    private weak var scrollView: NSScrollView?
    private var timer: Timer?

    /// How close to the edge the pointer gets before the list starts moving.
    private let threshold: CGFloat = 64
    /// Top speed, in points per tick (≈120 ticks/second).
    private let maxStep: CGFloat = 9

    func attach(_ scrollView: NSScrollView?) {
        guard let scrollView else { return }
        self.scrollView = scrollView
    }

    func setActive(_ active: Bool) {
        guard active else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let scrollView,
              let document = scrollView.documentView,
              let window = scrollView.window else { return }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = document.convert(windowPoint, from: nil)
        let visible = scrollView.documentVisibleRect
        guard visible.height > threshold * 2 else { return }

        // A flipped document view (SwiftUI's ScrollView) counts y downward;
        // AppKit's default counts it upward. Both reach the same "how far from
        // the leading edge of what I can see" number.
        let flipped = document.isFlipped
        let fromTop = flipped ? local.y - visible.minY : visible.maxY - local.y
        let fromBottom = flipped ? visible.maxY - local.y : local.y - visible.minY

        var step: CGFloat = 0
        if fromTop < threshold {
            step = -ramp(fromTop)
        } else if fromBottom < threshold {
            step = ramp(fromBottom)
        }
        guard step != 0 else { return }

        let documentHeight = document.bounds.height
        let maxOrigin = max(0, documentHeight - visible.height)
        let currentOrigin = flipped ? visible.minY : documentHeight - visible.maxY
        let nextOrigin = min(max(currentOrigin + step, 0), maxOrigin)
        guard abs(nextOrigin - currentOrigin) > 0.01 else { return }

        let originY = flipped ? nextOrigin : documentHeight - visible.height - nextOrigin
        scrollView.contentView.scroll(to: CGPoint(x: visible.minX, y: originY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Quadratic ramp: a nudge past the threshold creeps, the last few points
    /// before the edge fly. Linear speed feels either sluggish or unstoppable.
    private func ramp(_ distance: CGFloat) -> CGFloat {
        let closeness = min(max(1 - distance / threshold, 0), 1)
        return maxStep * closeness * closeness
    }
}
