// CosmoOS/UI/FocusMode/Shared/FocusTransitionCoordinator.swift
// Shared breadcrumb that lets the Content Focus Mode recognize it was mounted
// as a direct continuation of an Idea Focus Mode `begin writing →` press, so it
// can cross-fade in place instead of running the full entry stagger.

import Foundation

@MainActor
final class FocusTransitionCoordinator {
    static let shared = FocusTransitionCoordinator()
    private init() {}

    private var pendingContentUUID: String?
    private var pendingAt: Date?

    /// Window inside which a promotion signal is considered "fresh" enough to
    /// drive a cross-fade. Set just long enough to cover the navigation-router
    /// hop from Idea Focus closing to Content Focus mounting.
    private let freshnessWindow: TimeInterval = 3.0

    /// Called by Idea Focus right after a content atom has been created and the
    /// navigation notification is about to fire.
    func markPromotion(contentAtomUUID: String) {
        pendingContentUUID = contentAtomUUID
        pendingAt = Date()
    }

    /// Called by Content Focus on appear. Returns `true` exactly once if the
    /// given atom UUID matches a recent promotion — the caller should use a
    /// cross-fade entry instead of the full stagger. Subsequent calls return
    /// `false` so the signal is never applied twice.
    func consumePromotion(matching uuid: String) -> Bool {
        guard let pending = pendingContentUUID,
              pending == uuid,
              let at = pendingAt,
              Date().timeIntervalSince(at) < freshnessWindow else {
            return false
        }
        pendingContentUUID = nil
        pendingAt = nil
        return true
    }
}
