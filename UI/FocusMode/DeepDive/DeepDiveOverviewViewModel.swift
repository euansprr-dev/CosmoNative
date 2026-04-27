// CosmoOS/UI/FocusMode/DeepDive/DeepDiveOverviewViewModel.swift
// View model backing DeepDiveOverviewView. Loads linked atoms (questions, sources,
// lexicon, connections, sessions, topic-inbox items) and drives Current Understanding
// inline edits.

import Foundation
import SwiftUI
import GRDB

@MainActor
@Observable
final class DeepDiveOverviewViewModel {
    private(set) var atom: Atom

    // Linked atoms
    var questions: [Atom] = []
    var sources: [Atom] = []
    var lexicon: [Atom] = []
    var connections: [Atom] = []
    var sessions: [Atom] = []
    var topicInboxItems: [InboxItem] = []

    // Computed
    var currentQuestionTitle: String? {
        let active = questions.first { ($0.questionMetadata?.status ?? .open) == .researching }
            ?? questions.first { ($0.questionMetadata?.status ?? .open) == .open }
            ?? questions.first
        return active?.title
    }

    // Current Understanding editor state
    var isEditingUnderstanding: Bool = false
    var understandingDraftOneSentence: String = ""

    // Output angles surfaced inside Current Understanding (V1 read-only render)
    var outputAngles: [OutputAngle] {
        atom.deepDiveStructured?.outputAngles ?? []
    }

    var understanding: CurrentUnderstanding {
        atom.deepDiveStructured?.currentUnderstanding ?? CurrentUnderstanding()
    }

    init(atom: Atom) {
        self.atom = atom
        self.understandingDraftOneSentence = atom.deepDiveStructured?.currentUnderstanding.oneSentenceModel ?? ""
    }

    // MARK: - Loading

    func load() async {
        // Reload root atom (in case Telegram capture mutated it while view was open).
        if let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
            atom = fresh
            understandingDraftOneSentence = atom.deepDiveStructured?.currentUnderstanding.oneSentenceModel ?? understandingDraftOneSentence
        }

        async let qs = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: atom.uuid)) ?? []
        async let lex = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: atom.uuid)) ?? []
        async let ses = (try? await InquiryRepository.shared.fetchSessions(forDeepDive: atom.uuid)) ?? []
        async let src = (try? await InquiryRepository.shared.fetchSources(forDeepDive: atom)) ?? []
        async let cons = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: atom)) ?? []
        async let inbox = (try? await loadTopicInboxItems()) ?? []

        let (loadedQs, loadedLex, loadedSes, loadedSrc, loadedCons, loadedInbox) = await (qs, lex, ses, src, cons, inbox)
        questions = loadedQs.sorted { ($0.updatedAt) > ($1.updatedAt) }
        lexicon = loadedLex.sorted { ($0.title ?? "") < ($1.title ?? "") }
        sessions = loadedSes
        sources = loadedSrc
        connections = loadedCons
        topicInboxItems = loadedInbox
    }

    /// Topic Inbox = pending InboxItems whose recommendation targets this Deep Dive (by UUID match in
    /// place fields or by primary recommendation thinkspace path containing this title).
    private func loadTopicInboxItems() async throws -> [InboxItem] {
        let database = CosmoDatabase.shared
        let deepDiveUUID = atom.uuid
        let title = atom.title ?? ""
        return try await database.asyncRead { db in
            let allPending = try InboxItem
                .filter(Column("status") == InboxItemStatus.pending.rawValue
                        || Column("status") == InboxItemStatus.classified.rawValue)
                .fetchAll(db)
            return allPending.filter { item in
                if let uuid = item.placeThinkspaceId, uuid == deepDiveUUID { return true }
                if let path = item.destinationPath, path.localizedCaseInsensitiveContains(title), !title.isEmpty { return true }
                if let bundle = item.recommendationBundleValue {
                    return bundle.recommendations.contains { rec in
                        rec.thinkspaceId == deepDiveUUID
                            || (rec.thinkspaceName?.localizedCaseInsensitiveContains(title) == true && !title.isEmpty)
                    }
                }
                return false
            }
        }
    }

    // MARK: - Current Understanding edits

    func saveUnderstanding() async {
        var structured = atom.deepDiveStructured ?? DeepDiveStructured()
        let trimmed = understandingDraftOneSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != structured.currentUnderstanding.oneSentenceModel {
            structured.currentUnderstanding.oneSentenceModel = trimmed
            structured.currentUnderstanding.lastUpdated = ISO8601DateFormatter().string(from: Date())
            do {
                let updated = try await InquiryRepository.shared.saveDeepDive(atom, metadata: nil, structured: structured)
                atom = updated
            } catch {
                print("[DeepDiveOverviewVM] saveUnderstanding failed: \(error)")
            }
        }
        isEditingUnderstanding = false
    }
}
