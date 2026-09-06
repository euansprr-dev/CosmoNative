// CosmoOS/UI/Inbox/InboxTypes.swift
// Supporting types for the triage-queue Inbox — temporal sections and
// display helpers. June 2026 rebuild: filters, sort orders, stats rows, and
// intelligence groups were retired with the old dashboard UI.

import Foundation
import SwiftUI

// MARK: - Temporal Sections

struct InboxSection: Identifiable {
    let id: String
    let title: String
    let items: [InboxItem]
}

// MARK: - History

struct InboxHistoryEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case capture(InboxItem)
        case deletedLane(CaptureDestination)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .capture(let item): return "capture-\(item.uuid)"
        case .deletedLane(let lane): return "lane-\(lane.uuid)"
        }
    }

    var title: String {
        switch kind {
        case .capture(let item):
            return item.title ?? String(item.rawText.prefix(40))
        case .deletedLane(let lane):
            return lane.name
        }
    }

    var subtitle: String {
        switch kind {
        case .capture(let item):
            if item.status == .actioned {
                if let outcome = item.metadataDictionary["actionOutcome"] as? String { return outcome }
                return "Filed · \(item.destinationPath ?? item.placeThinkspaceName ?? "Saved capture")"
            }
            if item.status == .dismissed {
                return "Dismissed capture"
            }
            return item.status.rawValue.capitalized
        case .deletedLane(let lane):
            var parts = ["Deleted lane", captureCountLine(for: lane.itemCount)]
            if let alias = lane.aliases.first, !alias.isEmpty {
                parts.append("\(alias):")
            }
            return parts.joined(separator: " · ")
        }
    }

    var actionDate: Date {
        let raw: String?
        switch kind {
        case .capture(let item):
            raw = item.actionedAt ?? item.createdAt
        case .deletedLane(let lane):
            raw = lane.updatedAt
        }
        return raw.flatMap(ISO8601.date(from:)) ?? .distantPast
    }

    var isRestorable: Bool {
        switch kind {
        case .capture(let item):
            return item.status == .dismissed
        case .deletedLane:
            return true
        }
    }

    static func merged(
        captures: [InboxItem],
        deletedLanes: [CaptureDestination],
        limit: Int
    ) -> [InboxHistoryEntry] {
        let entries = captures.map { InboxHistoryEntry(kind: .capture($0)) }
            + deletedLanes.map { InboxHistoryEntry(kind: .deletedLane($0)) }
        return Array(entries.sorted { lhs, rhs in
            if lhs.actionDate == rhs.actionDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.actionDate > rhs.actionDate
        }.prefix(limit))
    }
}

private func captureCountLine(for count: Int) -> String {
    count == 1 ? "1 capture" : "\(count) captures"
}

// MARK: - Destination sheet focus

/// Which family of destinations the sheet opens on. Everything is always
/// listed; focus only decides what the user sees first.
enum InboxOverrideFocus: Equatable, Sendable {
    case destinations
    case inquiry
    case lanes
}

// MARK: - Inquiry destinations

/// A Space that can host an inquiry session — what the "Start inquiry in…"
/// menus and the destination sheet list.
struct InquirySpaceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Where a capture's inquiry should live: a Space the user already has, or
/// a NEW Space named for the topic (the honest answer to "I have no Space
/// for this yet").
enum InquirySpaceChoice: Hashable, Sendable {
    case existing(InquirySpaceOption)
    case new(name: String)

    var spaceName: String {
        switch self {
        case .existing(let option): return option.name
        case .new(let name): return name
        }
    }
}

// MARK: - Inspector host

/// Everything the floating capture inspector asks of its surface. The triage
/// queue's InboxViewModel is the native speaker; CaptureLanesViewModel talks
/// the same grammar for lane captures (delegating atom-creating verbs to the
/// queue model so toasts, undo, and the override sheet stay one pipeline).
@MainActor
protocol InboxInspectorHost {
    func closeInspector()
    func editCaptureText(_ item: InboxItem, to newText: String) async
    func place(_ item: InboxItem, adjustedPosition: CGPoint?) async
    func placeAndGo(_ item: InboxItem) async
    func applyAlternate(_ item: InboxItem, recommendation: InboxRecommendation) async
    func makeTask(_ item: InboxItem) async
    /// Spaces that can host an inquiry, for the "Start inquiry in…" menus.
    var inquirySpaces: [InquirySpaceOption] { get }
    /// The capture becomes a resumable inquiry session inside a Space —
    /// an existing one, or a new Space named for the topic.
    func startInquiry(_ item: InboxItem, in choice: InquirySpaceChoice) async
    /// Active capture lanes, for the "Move to lane" menus. Empty hides them.
    var lanes: [CaptureDestination] { get }
    /// The capture leaves the queue (or its current lane) for a lane.
    func moveToLane(_ item: InboxItem, lane: CaptureDestination) async
    func fileAsIdea(_ item: InboxItem) async
    func fileAsSwipe(_ item: InboxItem) async
    /// True when at least one flow exists to add a step to. Gates the `→ Flow`
    /// verb — an affordance with nothing to pick is worse than no affordance.
    var hasFlows: Bool { get }
    func addCaptureToFlow(_ item: InboxItem) async
    func growSeedling(_ item: InboxItem) async
    func connectCapture(_ item: InboxItem) async
    func showOverride(for item: InboxItem)
    func dismiss(item: InboxItem) async
}

// MARK: - Display Helpers

extension InboxRouteKind {
    /// The tint that pairs with `outcomeNoun`/`outcomeIcon` — the app's
    /// established entity-color language, accent for the growing/spatial
    /// flows, orange only for merges (the caught-a-duplicate warning voice).
    var outcomeTint: Color {
        switch self {
        case .fileToDestination: return DS.accent
        case .mergeAtom:
            return DS.orange
        case .feedConnection:
            return DS.entityConnection
        case .advanceQuestion, .spawnQuestion, .germinateDeepDive, .startInquiry:
            return DS.entityResearch
        case .attachClient:
            return DS.entityIdea
        case .feedSeedling, .startSeedling, .germinateConnection,
             .placeInExistingCluster, .createClusterAndPlace,
             .placeInThinkspace, .createThinkspaceAndPlace, .createStandaloneAtom:
            return DS.accent
        case .fileAsSwipe, .addToFlow:
            // The swipe file has its own entity colour throughout the app —
            // a routed swipe must read as the same object here as it does on
            // a canvas block or a Library row.
            return DS.entitySwipe
        }
    }
}

extension InboxItem {
    /// The primary suggestion's route kind, typed — decoded from the stored
    /// column, never the bundle (per-row JSON decodes are a ledger hot-path
    /// cost the revamp evicted).
    var primaryRouteKindValue: InboxRouteKind? {
        primaryRouteKind.flatMap(InboxRouteKind.init(rawValue:))
    }
    /// Human destination line for pills, toasts, and the inspector.
    var spatialDestinationTitle: String {
        if let destinationPath, !destinationPath.isEmpty { return destinationPath }
        if let placeThinkspaceName, !placeThinkspaceName.isEmpty { return placeThinkspaceName }
        if let mergeTargetTitle, !mergeTargetTitle.isEmpty { return mergeTargetTitle }
        if let placeAtomType, !placeAtomType.isEmpty { return placeAtomType.capitalized }
        return "Needs a home"
    }

    /// Entity color for the suggested atom type
    var entityColor: Color {
        guard let typeStr = placeAtomType,
              let type = AtomType(rawValue: typeStr) else {
            return DS.entityConnection
        }
        return Self.entityColor(for: type)
    }

    static func entityColor(for type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .note: return DS.entityNote
        case .connection: return DS.entityConnection
        case .task: return DS.entityTask
        default: return DS.entityConnection
        }
    }
}
