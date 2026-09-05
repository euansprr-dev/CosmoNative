// CosmoOS/Canvas/Spaces/SpaceViewStore.swift
// The active view of every space, for this session. Replaces the single
// global `@State thinkspaceMode` the keep-alive CanvasView used to hold for
// ALL spaces: each space now opens where it was left (persisted as
// `lastView`) and the switcher shows only that space's enabled views.
//
// Read this store only from CanvasView, the chrome row, and MainView's
// HANDLERS (trail replay, key monitor) — never inside MainView.body, or every
// view switch would re-evaluate the whole shell.

import SwiftUI

@MainActor
@Observable
final class SpaceViewStore {
    static let shared = SpaceViewStore()

    enum Source {
        case user
        case trail
        case deepDiveRedirect
        case placement
    }

    /// Session choice per space. Absent = the space's persisted opening view.
    private(set) var activeViews: [String: SpaceView] = [:]

    /// Coalesced per-space `lastView` writes — a switch right after a space
    /// switch must not land inside the 700 ms navigation window.
    @ObservationIgnored private var lastViewWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let manager: ThinkspaceManager
    @ObservationIgnored private let lastViewWriteDelay: Duration

    init(manager: ThinkspaceManager = .shared, lastViewWriteDelay: Duration = .milliseconds(750)) {
        self.manager = manager
        self.lastViewWriteDelay = lastViewWriteDelay
    }

    // MARK: Reads

    func activeView(for thinkspaceId: String) -> SpaceView {
        if let chosen = activeViews[thinkspaceId] {
            return chosen
        }
        return openingView(for: thinkspaceId)
    }

    /// The persisted opening view. Prefers `currentThinkspace` when the ids
    /// match — it carries the freshest `lastView` before the next reload.
    func openingView(for thinkspaceId: String) -> SpaceView {
        space(thinkspaceId)?.openingView ?? .canvas
    }

    func renderableViews(for thinkspaceId: String) -> [SpaceView] {
        space(thinkspaceId)?.renderableViews ?? [.canvas]
    }

    // MARK: Writes

    /// Switch a space to a view. Refuses views the space can't render and
    /// no-ops when already there. Records a trail moment (the trail is
    /// recency-unique, so Canvas ↔ Library ping-pong never stacks) and
    /// schedules the persisted `lastView` write.
    @discardableResult
    func select(_ view: SpaceView, for thinkspaceId: String, source: Source = .user) -> Bool {
        guard renderableViews(for: thinkspaceId).contains(view) else { return false }
        guard activeView(for: thinkspaceId) != view else {
            // Re-affirming the current view is still an arrival (a trail
            // replay landing where we already are must not be lost).
            if source == .trail { return true }
            return false
        }
        withAnimation(ProMotionSprings.focusTransition) {
            activeViews[thinkspaceId] = view
        }
        recordTrailMoment(view, for: thinkspaceId)
        scheduleLastViewWrite(view, for: thinkspaceId)
        return true
    }

    /// ⌘digit — index into the space's renderable views.
    @discardableResult
    func select(index: Int, for thinkspaceId: String) -> Bool {
        let views = renderableViews(for: thinkspaceId)
        guard views.indices.contains(index) else { return false }
        return select(views[index], for: thinkspaceId, source: .user)
    }

    /// After a settings change: if the active view was disabled, fall back to
    /// the space's opening view without recording a moment.
    func reconcile(_ thinkspace: Thinkspace) {
        guard let active = activeViews[thinkspace.id] else { return }
        if !thinkspace.renderableViews.contains(active) {
            withAnimation(ProMotionSprings.focusTransition) {
                activeViews[thinkspace.id] = thinkspace.openingView
            }
        }
    }

    func forget(thinkspaceId: String) {
        activeViews[thinkspaceId] = nil
        lastViewWrites[thinkspaceId]?.cancel()
        lastViewWrites[thinkspaceId] = nil
    }

    // MARK: Private

    private func space(_ thinkspaceId: String) -> Thinkspace? {
        if let current = manager.currentThinkspace, current.id == thinkspaceId {
            return current
        }
        return manager.thinkspaces.first { $0.id == thinkspaceId }
    }

    private func recordTrailMoment(_ view: SpaceView, for thinkspaceId: String) {
        let name = space(thinkspaceId)?.identityLabel ?? "Space"
        let title = view == .canvas ? name : "\(name) · \(view.title)"
        NavigationTrail.shared.recordArrival(
            .spaceView(thinkspaceId: thinkspaceId, view: view),
            title: title,
            glyph: view.trailGlyph
        )
    }

    private func scheduleLastViewWrite(_ view: SpaceView, for thinkspaceId: String) {
        lastViewWrites[thinkspaceId]?.cancel()
        let delay = lastViewWriteDelay
        lastViewWrites[thinkspaceId] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await manager.updateLastView(view, for: thinkspaceId)
            lastViewWrites[thinkspaceId] = nil
        }
    }
}
