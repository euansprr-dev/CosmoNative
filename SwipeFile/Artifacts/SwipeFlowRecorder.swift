// CosmoOS/SwipeFile/Artifacts/SwipeFlowRecorder.swift
// Recording a funnel as you walk it.
//
// A funnel is an ORDER, and order is the one thing you cannot reconstruct
// afterwards from a pile of saved pages. So the recorder captures it at the
// only moment it exists: while you are walking through. Open a session, then
// every swipe from every surface — ⌘⇧S in the browser, a dropped screenshot,
// an Inbox verb — appends as the next step instead of landing loose.
//
// Exactly ONE session is open at a time. Two would mean every capture surface
// needs a "which flow?" picker, which is the brain-overload this whole design
// exists to avoid.

import Foundation
import Observation

@MainActor
@Observable
final class SwipeFlowRecorder {
    static let shared = SwipeFlowRecorder()
    private init() {}

    struct Session: Equatable {
        var flowUUID: String
        var name: String
        var stepCount: Int

        /// "Client X funnel · 3 steps" — the pill's whole content.
        var pillLabel: String {
            stepCount == 1 ? "\(name) · 1 step" : "\(name) · \(stepCount) steps"
        }
    }

    private(set) var session: Session?

    var isRecording: Bool { session != nil }

    /// Start recording into a new flow. Returns nil when the flow could not be
    /// created; the caller shows nothing rather than a pill with no flow.
    @discardableResult
    func start(named name: String) async -> Session? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultName() : trimmed
        guard let flow = await SwipeFlowStore.createFlow(named: resolved) else { return nil }
        let started = Session(flowUUID: flow.uuid, name: resolved, stepCount: 0)
        session = started
        return started
    }

    /// Resume recording into an existing flow — reopening a funnel you started
    /// yesterday must not fork a second one.
    @discardableResult
    func resume(flowUUID: String) async -> Session? {
        guard let flow = try? await AtomRepository.shared.fetch(uuid: flowUUID),
              flow.swipeKind == .flow else { return nil }
        let resumed = Session(
            flowUUID: flow.uuid,
            name: flow.title ?? Self.defaultName(),
            stepCount: flow.swipeArtifactUnits.count
        )
        session = resumed
        return resumed
    }

    /// Close the session. The flow itself survives — stopping the recording is
    /// not deleting the funnel.
    func stop() {
        session = nil
    }

    /// Append a freshly captured swipe as the next step. Called from the one
    /// completion path in `SwipeIntakeRouter`, so no capture surface has to
    /// know flows exist.
    ///
    /// Returns the session as it now stands, or nil when nothing was appended
    /// (no open session, or the swipe is already a step).
    @discardableResult
    func appendCapturedSwipe(uuid: String) async -> Session? {
        guard var open = session else { return nil }
        // A flow must never contain itself, and a flow captured while
        // recording is a sibling, not a step.
        guard uuid != open.flowUUID else { return nil }

        let before = await stepCount(of: open.flowUUID)
        guard await SwipeFlowStore.append(swipeUUID: uuid, toFlow: open.flowUUID) else { return nil }
        let after = await stepCount(of: open.flowUUID)
        // `append` is idempotent — a revisited page returns true without
        // growing the flow, and the pill must not claim a step that isn't there.
        guard after > before else { return nil }

        open.stepCount = after
        session = open
        return open
    }

    private func stepCount(of flowUUID: String) async -> Int {
        guard let flow = try? await AtomRepository.shared.fetch(uuid: flowUUID) else { return 0 }
        return flow.swipeArtifactUnits.count
    }

    /// A name you can rename later beats a modal you have to answer now — the
    /// point of the recorder is that it costs one click to start.
    static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "Funnel · \(formatter.string(from: Date()))"
    }
}
