// CosmoOS/Navigation/FocusNavigationCoordinator.swift
// The single authority for entering, swapping, and exiting focus mode.

import SwiftUI
import AppKit

/// Every path that changes `appState.focusedEntity` funnels through here so a
/// document open always plays the same way: the atom is preloaded first (the
/// source screen stays live — no loading chrome), then one
/// `ProMotionSprings.focusTransition` drives the overlay in, out, or across a
/// doc→doc swap. The coordinator also carries the click-point anchor the
/// entrance bloom grows from and the exit recedes toward.
@MainActor
final class FocusNavigationCoordinator {
    static let shared = FocusNavigationCoordinator()

    /// Wired once by MainView on appear.
    weak var appState: AppState?

    /// Atoms fetched ahead of presentation; FocusCanvasView consumes them
    /// synchronously on first mount so the warm path never shows a loader.
    private var preloadedAtoms: [EntitySelection: Atom] = [:]

    /// Window-relative unit point the entrance grows from. Falls back to the
    /// pointer location for mouse-triggered opens, `.center` for keyboard ones.
    private(set) var entranceAnchor: UnitPoint = .center

    private var openTask: Task<Void, Never>?
    private var requestID = UUID()

    private init() {}

    // MARK: - Open

    /// Open (or doc→doc swap to) an entity. `sourceFrame` is the trigger's
    /// frame in SwiftUI global (window content) coordinates; when omitted the
    /// click location stands in, so every mouse-triggered open blooms from
    /// where the user clicked without per-site wiring.
    func open(entity: EntitySelection, sourceFrame: CGRect? = nil) {
        openTask?.cancel()
        let request = UUID()
        requestID = request
        // Capture the anchor before the async fetch — the pointer is still
        // on the trigger at this instant.
        let anchor = Self.anchor(for: sourceFrame)

        openTask = Task { @MainActor in
            var target = entity
            if target.id <= 0 {
                // Safety net: never enter focus mode with an invalid entity id.
                guard let createdId = await AppState.createEntityForFocusMode(type: entity.type) else {
                    print("⚠️ FocusNavigationCoordinator: could not create entity for \(entity.type.rawValue)")
                    return
                }
                target = EntitySelection(id: createdId, type: entity.type)
            }
            guard requestID == request, !Task.isCancelled else { return }

            if let atom = try? await AtomRepository.shared.fetch(id: target.id) {
                preloadedAtoms[target] = atom
            }
            guard requestID == request, !Task.isCancelled else { return }

            present(target, anchor: anchor)
        }
    }

    func open(atomUUID: String, sourceFrame: CGRect? = nil) {
        openTask?.cancel()
        let request = UUID()
        requestID = request
        let anchor = Self.anchor(for: sourceFrame)

        openTask = Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID),
                  let atomId = atom.id else {
                print("⚠️ FocusNavigationCoordinator: atom not found for uuid \(atomUUID)")
                return
            }
            guard requestID == request, !Task.isCancelled else { return }

            let target = EntitySelection(id: atomId, type: AtomWindowViewModel.entityType(for: atom.type))
            preloadedAtoms[target] = atom
            present(target, anchor: anchor)
        }
    }

    // MARK: - Close

    func close() {
        openTask?.cancel()
        guard let appState, appState.focusedEntity != nil else { return }
        AppPerformanceInstrumentation.event("focus-close")
        withAnimation(transitionAnimation) {
            appState.focusedEntity = nil
        }
        preloadedAtoms.removeAll()
    }

    /// FocusCanvasView pulls its atom here on first mount — synchronously,
    /// so the real document renders on frame 1 of the entrance.
    func consumePreloadedAtom(for entity: EntitySelection) -> Atom? {
        preloadedAtoms.removeValue(forKey: entity)
    }

    // MARK: - Presentation

    private func present(_ entity: EntitySelection, anchor: UnitPoint) {
        guard let appState else { return }
        AppPerformanceInstrumentation.event("focus-open")
        entranceAnchor = anchor
        // One assignment covers both fresh opens and doc→doc swaps: the
        // overlay's `.id(focusedEntity)` remount cross-fades removal and
        // insertion inside this single spring.
        withAnimation(transitionAnimation) {
            appState.focusedEntity = entity
        }
    }

    private var transitionAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.16)
            : ProMotionSprings.focusTransition
    }

    // MARK: - Anchor resolution

    private static func anchor(for sourceFrame: CGRect?) -> UnitPoint {
        guard let window = NSApp.keyWindow,
              let contentBounds = window.contentView?.bounds,
              contentBounds.width > 0, contentBounds.height > 0 else { return .center }

        // Explicit source frame (SwiftUI global space, top-left origin).
        if let sourceFrame {
            return clampedUnitPoint(
                x: sourceFrame.midX / contentBounds.width,
                y: sourceFrame.midY / contentBounds.height
            )
        }

        // Keyboard-triggered opens (Command-K return, shortcuts) have no
        // meaningful pointer position — bloom from the center.
        if let event = NSApp.currentEvent,
           event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
            return .center
        }

        // Mouse-triggered: the pointer is on the trigger right now.
        // AppKit window coordinates are bottom-left origin — flip the y.
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        return clampedUnitPoint(
            x: mouseInWindow.x / contentBounds.width,
            y: 1 - (mouseInWindow.y / contentBounds.height)
        )
    }

    private static func clampedUnitPoint(x: CGFloat, y: CGFloat) -> UnitPoint {
        UnitPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
