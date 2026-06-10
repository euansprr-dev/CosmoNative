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
    var extracts: [Atom] = []

    // Computed
    var currentQuestionTitle: String? {
        let active = questions.first { ($0.questionMetadata?.status ?? .open) == .researching }
            ?? questions.first { ($0.questionMetadata?.status ?? .open) == .open }
            ?? questions.first
        return active?.title
    }

    /// Questions with normalized-title duplicates collapsed; the richest copy
    /// (most extracts, then most recent) represents each.
    var dedupedQuestions: [Atom] {
        Self.dedupeQuestions(questions, extractCount: { self.questionCounts($0).extracts })
    }

    nonisolated static func dedupeQuestions(_ questions: [Atom], extractCount: (Atom) -> Int) -> [Atom] {
        var byKey: [String: Atom] = [:]
        var order: [String] = []
        for question in questions {
            let key = ResearchTreeDocument.normalizedQuestionKey(question.title ?? "")
            guard !key.isEmpty else { continue }
            if let current = byKey[key] {
                let currentScore = (extractCount(current), current.updatedAt)
                let candidateScore = (extractCount(question), question.updatedAt)
                if candidateScore > currentScore { byKey[key] = question }
            } else {
                byKey[key] = question
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Narrative revisions, newest first, for the understanding history disclosure.
    var understandingRevisions: [UnderstandingNarrativeRevision] {
        (understanding.narrativeHistory ?? []).reversed()
    }

    /// Lexicon entries joined to their promoted/matching concept Connection.
    var conceptEntries: [(lexicon: Atom, connection: Atom?)] {
        lexicon.map { entry in
            if let promoted = entry.lexiconMetadata?.promotedToUUID,
               let connection = connections.first(where: { $0.uuid == promoted }) {
                return (entry, connection)
            }
            let key = ConceptResolver.conceptKey(entry.title ?? "")
            let match = key.isEmpty ? nil : connections.first {
                ConceptResolver.conceptKey($0.title ?? "") == key
            }
            return (entry, match)
        }
    }

    func questionCounts(_ question: Atom) -> (extracts: Int, sessions: Int) {
        let extractCount = extracts.filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }.count
        let sessionUUIDs = Set(
            extracts
                .filter { $0.extractMetadata?.parentQuestionUUID == question.uuid }
                .compactMap { $0.extractMetadata?.parentSessionUUID }
        )
        return (extractCount, sessionUUIDs.count)
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
            // Clean up legacy appended-markdown bodies into structured revisions.
            atom = (try? await DeepDiveBodyMigration.migrateIfNeeded(fresh)) ?? fresh
            understandingDraftOneSentence = atom.deepDiveStructured?.currentUnderstanding.oneSentenceModel ?? understandingDraftOneSentence
        }

        async let qs = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: atom.uuid)) ?? []
        async let lex = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: atom.uuid)) ?? []
        async let ses = (try? await InquiryRepository.shared.fetchSessions(forDeepDive: atom.uuid)) ?? []
        async let src = (try? await InquiryRepository.shared.fetchSources(forDeepDive: atom)) ?? []
        async let cons = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: atom)) ?? []
        async let inbox = (try? await loadTopicInboxItems()) ?? []
        async let ext = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: atom.uuid)) ?? []

        let (loadedQs, loadedLex, loadedSes, loadedSrc, loadedCons, loadedInbox, loadedExt) = await (qs, lex, ses, src, cons, inbox, ext)
        questions = loadedQs.sorted { ($0.updatedAt) > ($1.updatedAt) }
        lexicon = loadedLex.sorted { ($0.title ?? "") < ($1.title ?? "") }
        sessions = loadedSes
        sources = loadedSrc
        connections = loadedCons
        topicInboxItems = loadedInbox
        extracts = loadedExt
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
            structured.currentUnderstanding.lastUpdated = ISO8601.string(from: Date())
            do {
                let updated = try await InquiryRepository.shared.saveDeepDive(atom, metadata: nil, structured: structured)
                atom = updated
            } catch {
                print("[DeepDiveOverviewVM] saveUnderstanding failed: \(error)")
            }
        }
        isEditingUnderstanding = false
    }

    func renameSession(_ sessionUUID: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = sessions.firstIndex(where: { $0.uuid == sessionUUID }) else { return }
        var copy = sessions[idx]
        copy.title = trimmed
        do {
            copy = try await AtomRepository.shared.update(copy)
            sessions[idx] = copy
        } catch {
            print("[DeepDiveOverviewVM] renameSession failed: \(error)")
        }
    }

    func archiveSession(_ sessionUUID: String) async {
        guard let idx = sessions.firstIndex(where: { $0.uuid == sessionUUID }),
              var meta = sessions[idx].inquirySessionMetadata else { return }
        meta.status = .archived
        meta.lastActiveAt = ISO8601.string(from: Date())
        var copy = sessions[idx].withMetadata(meta)
        do {
            copy = try await AtomRepository.shared.update(copy)
            sessions[idx] = copy
        } catch {
            print("[DeepDiveOverviewVM] archiveSession failed: \(error)")
        }
    }

    func deleteSession(_ sessionUUID: String) async {
        do {
            try await AtomRepository.shared.delete(uuid: sessionUUID)
            sessions.removeAll { $0.uuid == sessionUUID }
        } catch {
            print("[DeepDiveOverviewVM] deleteSession failed: \(error)")
        }
    }
}
