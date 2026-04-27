// CosmoOS/UI/FocusMode/Inquiry/InquirySessionLauncher.swift
// Centralizes how Inquiry Sessions are started or resumed from any surface.
// Handles: anchor resolution (Deep Dive / Connection / Question / cluster), session creation,
// session resume, and focus-mode entry.

import Foundation
import SwiftUI

@MainActor
final class InquirySessionLauncher {
    static let shared = InquirySessionLauncher()
    private init() {}

    /// Launch an Inquiry Session anchored to `anchorUUID`. If `resumeSessionUUID` is provided
    /// and the session is paused/active, resume it; otherwise create a new one.
    func launch(
        anchorUUID: String,
        anchorType: String,
        resumeSessionUUID: String?,
        mainQuestionTitle: String? = nil,
        rootQuestionUUID: String? = nil,
        appState: AppState?
    ) async {
        // Resume path
        if let resumeUUID = resumeSessionUUID,
           let session = try? await AtomRepository.shared.fetch(uuid: resumeUUID),
           session.type == .inquirySession {
            await openSession(session, appState: appState)
            return
        }

        // Resolve anchor
        guard let anchorAtom = try? await AtomRepository.shared.fetch(uuid: anchorUUID) else {
            print("[InquirySessionLauncher] anchor not found: \(anchorUUID)")
            return
        }

        // Anchor must reduce to a Deep Dive (parent of the new session). For Connection / Question /
        // cluster anchors we walk up to or create a Deep Dive home.
        let deepDive: Atom
        switch anchorAtom.type {
        case .deepDive:
            deepDive = anchorAtom
        case .connection, .question:
            // Try to find an existing Deep Dive linked to this object via .relatedDeepDive or
            // .questionParentDeepDive; otherwise create one named after the anchor.
            if let existing = await findOrCreateDeepDive(for: anchorAtom) {
                deepDive = existing
            } else {
                print("[InquirySessionLauncher] couldn't resolve Deep Dive for anchor \(anchorAtom.uuid)")
                return
            }
        default:
            print("[InquirySessionLauncher] unsupported anchor type: \(anchorAtom.type.rawValue)")
            return
        }

        let existingRootQuestion: Atom?
        if let rootQuestionUUID {
            existingRootQuestion = try? await AtomRepository.shared.fetch(uuid: rootQuestionUUID)
        } else {
            existingRootQuestion = nil
        }

        do {
            let result = try await InquiryRepository.shared.startSession(
                deepDive: deepDive,
                title: nil,
                mainQuestionTitle: mainQuestionTitle ?? (anchorAtom.type == .question ? anchorAtom.title : nil),
                existingRootQuestion: existingRootQuestion,
                anchorObjectUUID: anchorAtom.uuid == deepDive.uuid ? nil : anchorAtom.uuid,
                anchorObjectType: anchorAtom.uuid == deepDive.uuid ? nil : anchorAtom.type.rawValue
            )
            await openSession(result.session, appState: appState)
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.sessionStarted,
                object: nil,
                userInfo: [
                    "sessionUUID": result.session.uuid,
                    "deepDiveUUID": deepDive.uuid
                ]
            )
        } catch {
            print("[InquirySessionLauncher] startSession failed: \(error)")
        }
    }

    private func openSession(_ session: Atom, appState: AppState?) async {
        guard let id = session.id else { return }
        appState?.focusedEntity = EntitySelection(id: id, type: .inquirySession)
    }

    /// For Connection/Question anchors — find any related Deep Dive, or create one.
    private func findOrCreateDeepDive(for anchorAtom: Atom) async -> Atom? {
        // Try direct link from question metadata
        if anchorAtom.type == .question,
           let parentUUID = anchorAtom.questionMetadata?.parentDeepDiveUUID,
           let dd = try? await AtomRepository.shared.fetch(uuid: parentUUID) {
            return dd
        }
        // Otherwise create a new Deep Dive named after the anchor
        do {
            let title = anchorAtom.title ?? "Untitled Deep Dive"
            return try await InquiryRepository.shared.createDeepDive(
                title: title,
                about: "Spawned from \(anchorAtom.type.displayName): \(title)"
            )
        } catch {
            print("[InquirySessionLauncher] createDeepDive failed: \(error)")
            return nil
        }
    }
}
