// CosmoOS/UI/FocusMode/Inquiry/Study/StudyTrailSupport.swift
// Pure trail models shared by the trail panel and its tests: destination
// grouping, the feed-item enum, the relative-time formatter, and the
// provisional pulse dot. (Moved from InquiryNotesRail.swift in the Study
// rebuild — logic unchanged, the views around it were replaced.)

import SwiftUI

// MARK: - Destination grouping

/// One destination section in the trail: a question and everything routed to it.
struct NoteDestinationGroup: Identifiable, Equatable {
    static func == (lhs: NoteDestinationGroup, rhs: NoteDestinationGroup) -> Bool {
        lhs.id == rhs.id && lhs.items.map(\.feedId) == rhs.items.map(\.feedId)
    }
    var id: String { questionUUID ?? "unassigned" }
    var questionUUID: String?
    var title: String
    var items: [InquiryNoteFeedItem]
    var conceptCounts: [(name: String, count: Int)]
}

enum InquiryNotesGrouping {
    /// Pure grouping: extracts + pending captures → destination sections.
    /// Active question pinned first, then by most-recent item.
    static func groups(
        extracts: [Atom],
        captures: [SessionCapture],
        activeQuestionUUID: String?,
        questionTitle: (String?) -> String
    ) -> [NoteDestinationGroup] {
        var itemsByQuestion: [String?: [InquiryNoteFeedItem]] = [:]
        for atom in extracts {
            itemsByQuestion[atom.extractMetadata?.parentQuestionUUID, default: []].append(.extract(atom))
        }
        for capture in captures {
            itemsByQuestion[capture.attachedQuestionId ?? activeQuestionUUID, default: []].append(.capture(capture))
        }

        var groups: [NoteDestinationGroup] = itemsByQuestion.map { questionUUID, items in
            let sorted = items.sorted { $0.sortKey > $1.sortKey }
            var conceptTally: [String: Int] = [:]
            for case .extract(let atom) in sorted {
                for concept in atom.extractMetadata?.conceptNames ?? [] {
                    conceptTally[concept, default: 0] += 1
                }
            }
            return NoteDestinationGroup(
                questionUUID: questionUUID,
                title: questionTitle(questionUUID),
                items: sorted,
                conceptCounts: conceptTally.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
            )
        }
        groups.sort { lhs, rhs in
            if lhs.questionUUID == activeQuestionUUID { return true }
            if rhs.questionUUID == activeQuestionUUID { return false }
            return (lhs.items.first?.sortKey ?? "") > (rhs.items.first?.sortKey ?? "")
        }
        return groups
    }
}

// MARK: - Feed item

enum InquiryNoteFeedItem: Identifiable {
    case extract(Atom)
    case capture(SessionCapture)

    var id: String { feedId }

    var feedId: String {
        switch self {
        case .extract(let atom): return "extract-\(atom.uuid)"
        case .capture(let capture): return "capture-\(capture.id)"
        }
    }

    var sortKey: String {
        switch self {
        case .extract(let atom):
            return atom.extractMetadata?.committedAt ?? atom.createdAt
        case .capture(let capture):
            return capture.createdAt
        }
    }

    var isCapture: Bool {
        if case .capture = self { return true }
        return false
    }

    /// True while the live router hasn't confirmed/refined this extract yet.
    var isProvisional: Bool {
        if case .extract(let atom) = self {
            return atom.extractMetadata?.status == .temporary
        }
        return false
    }

    /// True once this extract has been crystallized into a Connection
    /// (typically in a previous session).
    var isCrystallized: Bool {
        if case .extract(let atom) = self {
            return atom.extractMetadata?.status == .promoted
        }
        return false
    }
}

// MARK: - Relative date formatter

@MainActor
final class RelativeISO8601Formatter {
    static let shared = RelativeISO8601Formatter()
    private let parser = ISO8601DateFormatter()
    private let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func relative(from iso: String, to now: Date = Date()) -> String {
        guard let date = parser.date(from: iso) else { return "" }
        return relative.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Provisional pulse indicator

/// Small pulsing dot shown while the live router is still refining an extract.
struct ProvisionalPulseDot: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(DS.accent)
            .frame(width: 5, height: 5)
            .opacity(pulsing && !reduceMotion ? 0.35 : 0.9)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityLabel("Routing in progress")
    }
}
