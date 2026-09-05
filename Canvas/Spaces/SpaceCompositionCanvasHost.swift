import SwiftUI

/// The workspace contributes context and data; CanvasView remains the one
/// rendering/interaction engine. Its frame tracker is private to this viewport.
struct SpaceCompositionCanvasHost: View {
    let spaceID: String
    let container: Atom
    let items: [Atom]
    var onOpen: (Atom) -> Void
    @State private var session: SpaceCompositionCanvasSession
    @EnvironmentObject private var parentFrameTracker: CanvasBlockFrameTracker
    @StateObject private var frameTracker = CanvasBlockFrameTracker()

    init(spaceID: String, container: Atom, items: [Atom], onOpen: @escaping (Atom) -> Void) {
        self.spaceID = spaceID; self.container = container; self.items = items; self.onOpen = onOpen
        _session = State(initialValue: SpaceCompositionCanvasStore.session(spaceID: spaceID, containerUUID: container.uuid))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = session.error {
                HStack(spacing: DS.space12) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Retry") { session.retry() }
                }.font(DS.caption).foregroundStyle(DS.textSecondary).padding(DS.space12)
                    .background(DS.surfaceElevated)
            }
            CanvasView(thinkspaceId: spaceID, compositionSession: session)
                .environmentObject(frameTracker)
                .background(SpaceCanvasViewportBridge(tracker: frameTracker, parent: parentFrameTracker))
                .clipped()
        }
        .task(id: container.uuid) {
            session.onOpen = onOpen
            session.selectedUUID = SpaceWorkspaceStore.shared.location(spaceID).selectedUUID
            session.receive(container: container, items: items)
        }
        .onChange(of: container.localVersion) { _, _ in session.receive(container: container, items: items) }
        .onChange(of: items.map { $0.uuid + String($0.localVersion) }) { _, _ in session.receive(container: container, items: items) }
        .accessibilityIdentifier("space.collection.canvas")
    }
}

/// Geometry-only native bridge. It never takes mouse events from text/cards.
private struct SpaceCanvasViewportBridge: NSViewRepresentable {
    let tracker: CanvasBlockFrameTracker
    let parent: CanvasBlockFrameTracker
    func makeNSView(context: Context) -> Surface { Surface(tracker: tracker, parent: parent) }
    func updateNSView(_ view: Surface, context: Context) { view.publish() }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.release() }
    final class Surface: NSView {
        let tracker: CanvasBlockFrameTracker
        let parent: CanvasBlockFrameTracker
        init(tracker: CanvasBlockFrameTracker, parent: CanvasBlockFrameTracker) {
            self.tracker = tracker; self.parent = parent
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); publish() }
        override func layout() { super.layout(); publish() }
        func publish() {
            guard let window else { return }
            let frame = convert(bounds, to: nil)
            tracker.windowFrame = CGRect(x: frame.minX, y: window.frame.height - frame.maxY, width: frame.width, height: frame.height)
            tracker.nativeSurface = self
            parent.forwardedTracker = tracker
        }
        func release() {
            if parent.forwardedTracker === tracker { parent.forwardedTracker = nil }
            tracker.nativeSurface = nil
        }
    }
}
