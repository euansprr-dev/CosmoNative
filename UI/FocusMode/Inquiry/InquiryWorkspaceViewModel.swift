// CosmoOS/UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift
// View model for the 3-pane Inquiry Workspace.
// Owns: session atom, parent Deep Dive, root question, captures, AI conversation,
// layout mode, debounced persistence.

import Foundation
import SwiftUI

@MainActor
@Observable
final class InquiryWorkspaceViewModel {
    // Persistent atoms
    private(set) var session: Atom
    private(set) var deepDive: Atom?
    private(set) var rootQuestion: Atom?

    // Live structured + metadata (mirrors session.* but mutable)
    var structured: InquirySessionStructured
    var metadata: InquirySessionMetadata

    // Active branch / question for context-aware actions
    var activeBranchNodeId: String
    var activeQuestionUUID: String?
    var activeSourceTabId: String?

    // Local UI state
    var notebookMode: InquiryNotebookMode = .notes
    var noteDraft: String = ""
    var aiPromptDraft: String = ""
    var aiBusy: Bool = false

    // Captures (in-memory until commit/crystallize)
    var captures: [SessionCapture] {
        get { structured.sessionCaptures }
        set { structured.sessionCaptures = newValue }
    }

    // Persistence
    private var saveTask: Task<Void, Never>?

    init(session: Atom) {
        self.session = session
        let meta = session.inquirySessionMetadata ?? InquirySessionMetadata()
        let structured = session.inquirySessionStructured ?? InquirySessionStructured(researchTree: ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: nil))
        self.metadata = meta
        self.structured = structured
        self.activeBranchNodeId = structured.researchTree.rootNodeId
        self.activeQuestionUUID = meta.mainQuestionUUID
    }

    // MARK: - Loading

    func loadDeepDiveAndRoot() async {
        if let ddUUID = metadata.parentDeepDiveUUID,
           let dd = try? await AtomRepository.shared.fetch(uuid: ddUUID) {
            deepDive = dd
        }
        if let rqUUID = metadata.mainQuestionUUID,
           let rq = try? await AtomRepository.shared.fetch(uuid: rqUUID) {
            rootQuestion = rq
        }
        if metadata.status != .active {
            metadata.status = .active
            metadata.lastActiveAt = ISO8601DateFormatter().string(from: Date())
            scheduleSave()
        }
    }

    // MARK: - Layout

    func setLayout(_ mode: InquiryLayoutMode) {
        guard metadata.layoutMode != mode else { return }
        metadata.layoutMode = mode
        scheduleSave()
    }

    // MARK: - Captures

    /// Append a temporary capture (not yet promoted to an atom).
    func addCapture(_ body: String, source: SessionCapture.Source = .type, suggestedKind: ExtractKind? = nil) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let capture = SessionCapture(
            body: trimmed,
            source: source,
            suggestedKind: suggestedKind,
            attachedQuestionId: activeQuestionUUID,
            attachedSourceTabId: activeSourceTabId
        )
        structured.sessionCaptures.append(capture)
        scheduleSave()
    }

    /// Commit a capture to an Extract atom. Returns the new Extract UUID on success.
    func commitCapture(_ captureId: String, kind: ExtractKind) async -> String? {
        guard let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) else { return nil }
        let capture = structured.sessionCaptures[idx]
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: capture.body,
                kind: kind,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: capture.attachedQuestionId,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: capture.attachedSourceTabId,
                userNote: nil,
                originType: capture.source.rawValue,
                citation: nil
            )
            structured.sessionCaptures[idx].status = .committed
            structured.sessionCaptures[idx].promotedToAtomUUID = extract.uuid

            // Append to research tree under active branch
            structured.researchTree.appendChild(
                parentId: activeBranchNodeId,
                kind: .extract,
                atomUUID: extract.uuid,
                label: capture.body.prefix(60).description,
                aiSuggested: false,
                accepted: true
            )
            scheduleSave()
            return extract.uuid
        } catch {
            print("[InquiryWorkspaceVM] commitCapture failed: \(error)")
            return nil
        }
    }

    func discardCapture(_ captureId: String) {
        if let idx = structured.sessionCaptures.firstIndex(where: { $0.id == captureId }) {
            structured.sessionCaptures[idx].status = .discarded
            scheduleSave()
        }
    }

    // MARK: - Notes (commits a note Atom on save)

    func saveNoteDraft() async {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Persist as an Extract atom of kind .note (preserves provenance).
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: trimmed,
                kind: .note,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: session.uuid,
                questionUUID: activeQuestionUUID,
                deepDiveUUID: deepDive?.uuid,
                branchNodeId: activeBranchNodeId,
                sourceTabId: activeSourceTabId,
                userNote: nil,
                originType: "manual",
                citation: nil
            )
            // Append to research tree
            structured.researchTree.appendChild(
                parentId: activeBranchNodeId,
                kind: .note,
                atomUUID: extract.uuid,
                label: trimmed.prefix(60).description,
                aiSuggested: false,
                accepted: true
            )
            scheduleSave()
            noteDraft = ""
        } catch {
            print("[InquiryWorkspaceVM] saveNoteDraft failed: \(error)")
        }
    }

    // MARK: - AI

    /// Append a record of an AI exchange (no LLM call yet — call site provides response).
    func recordAIInteraction(prompt: String, response: String, modelTier: String? = nil) {
        let interaction = AIInteractionRef(
            branchNodeId: activeBranchNodeId,
            sourceTabId: activeSourceTabId,
            prompt: prompt,
            response: response,
            modelTier: modelTier
        )
        structured.aiInteractions.append(interaction)
        // Also add a tree node so the conversation appears in the path
        structured.researchTree.appendChild(
            parentId: activeBranchNodeId,
            kind: .ai,
            atomUUID: nil,
            label: prompt.prefix(60).description,
            aiSuggested: false,
            accepted: true
        )
        scheduleSave()
    }

    /// Run an AI prompt via ResearchService. Records the interaction on completion.
    func runAIPrompt(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        aiBusy = true
        defer { aiBusy = false }

        let context = buildAIContext()
        let fullPrompt = """
        \(context)

        Question from Euan: \(trimmed)

        Answer thoughtfully, drawing on the provided context. If you don't know, say so.
        """

        let response = await InquiryAICopilot.shared.ask(prompt: fullPrompt)
        recordAIInteraction(prompt: trimmed, response: response)
        aiPromptDraft = ""
    }

    private func buildAIContext() -> String {
        var lines: [String] = []
        if let dd = deepDive, let title = dd.title {
            lines.append("You are inside the Deep Dive: \(title)")
            if let about = dd.body, !about.isEmpty {
                lines.append("About this Deep Dive: \(about)")
            }
            if let model = dd.deepDiveStructured?.currentUnderstanding.oneSentenceModel,
               !model.isEmpty {
                lines.append("Current understanding: \(model)")
            }
        }
        if let rq = rootQuestion, let qt = rq.title {
            lines.append("Root question: \(qt)")
        }
        if let activeQ = activeQuestionUUID, activeQ != rootQuestion?.uuid {
            // (best-effort — full question loading deferred)
            lines.append("Active branch question UUID: \(activeQ)")
        }
        let recent = structured.sessionCaptures.suffix(5).map { "- \($0.body.prefix(120))" }.joined(separator: "\n")
        if !recent.isEmpty {
            lines.append("Recent captures:\n\(recent)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pause / Save / Resume

    /// Persist pending changes immediately and mark the session paused.
    func pauseAndPersist() async {
        saveTask?.cancel()
        do {
            session = try await InquiryRepository.shared.saveSession(session, metadata: metadata, structured: structured)
            session = try await InquiryRepository.shared.pauseSession(session)
            metadata = session.inquirySessionMetadata ?? metadata
            structured = session.inquirySessionStructured ?? structured
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.sessionEnded,
                object: nil,
                userInfo: ["sessionUUID": session.uuid]
            )
        } catch {
            print("[InquiryWorkspaceVM] pauseAndPersist failed: \(error)")
        }
    }

    /// Debounced save (500ms).
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.persistNow()
        }
    }

    private func persistNow() async {
        do {
            metadata.lastActiveAt = ISO8601DateFormatter().string(from: Date())
            session = try await InquiryRepository.shared.saveSession(session, metadata: metadata, structured: structured)
            metadata = session.inquirySessionMetadata ?? metadata
            structured = session.inquirySessionStructured ?? structured
        } catch {
            print("[InquiryWorkspaceVM] persistNow failed: \(error)")
        }
    }
}

enum InquiryNotebookMode: String, CaseIterable {
    case notes
    case tree
    case captures
    case currentUnderstanding
    case localMap

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .tree: return "Tree"
        case .captures: return "Captures"
        case .currentUnderstanding: return "Current Understanding"
        case .localMap: return "Local Map"
        }
    }
}
