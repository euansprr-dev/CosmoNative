import Foundation

/// The durable original, independent of the inspector used to display it.
struct InboxCaptureReference: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case inbox, lane }
    var kind: Kind
    var uuid: String
}

struct InboxFilingDestination: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case pages, space, group, page, ideas, connection, swipe, today, research }
    var kind: Kind
    var uuid: String?
    var spaceID: String?
    var name: String
    var path: String
    var id: String { "\(kind.rawValue):\(spaceID ?? ""):\(uuid ?? "")" }

    var symbol: String {
        switch kind {
        case .pages, .page: return "doc.text"
        case .space: return "square.grid.2x2"
        case .group: return "folder"
        case .ideas: return "lightbulb"
        case .connection: return "point.3.connected.trianglepath.dotted"
        case .swipe: return "rectangle.stack"
        case .today: return "checkmark.circle"
        case .research: return "books.vertical"
        }
    }

    var defaultAction: InboxFilingAction {
        switch kind {
        case .page: return .reference
        case .ideas: return .idea
        case .connection: return .stageConnection
        case .swipe: return .swipe
        case .today: return .task
        case .research: return .research
        case .pages, .space, .group: return .page
        }
    }

    /// Destinations that can also receive the capture as a Research SOURCE
    /// (a link or scanned pages saved for their content): a Space (with its
    /// materials), a Group, a Page (as a reference), a Concept (linked, and
    /// staged in References), the Library, or the Research shelf itself.
    var acceptsResearch: Bool {
        switch kind {
        case .space, .group, .page, .connection, .pages, .research: return true
        case .ideas, .swipe, .today: return false
        }
    }

    /// The Library's research shelf — the home for a source with no Space.
    static let libraryResearch = InboxFilingDestination(kind: .research, name: "Research", path: "Library › Research")
}

enum InboxFilingAction: String, Codable, CaseIterable, Sendable {
    case page, childPage, reference, idea, stageConnection, swipe, task
    /// Save the capture as a Research SOURCE (research lens, never the swipe
    /// file) and put it where the destination says. September 2026.
    case research

    var title: String {
        switch self {
        case .page: return "Save Page"
        case .childPage: return "Add child Page"
        case .reference: return "Attach reference"
        case .idea: return "Save Content idea"
        case .stageConnection: return "Add for review"
        case .swipe: return "Save Swipe"
        case .task: return "Create task"
        case .research: return "Save Research"
        }
    }

    func consequence(in destination: InboxFilingDestination) -> String {
        switch self {
        case .page:
            switch destination.kind {
            case .group: return "Saves one Page and adds it to this Group. The canvas arrangement stays as it is."
            case .space: return "Saves one Page in this Space, ready to open or arrange on its canvas."
            default: return "Saves a Page with the complete capture and its originals."
            }
        case .childPage: return "Creates a new Page at the end of this Page’s sections. Its existing writing stays as it is."
        case .reference: return "Keeps the complete original and attaches a reference here. Existing writing and section order stay as they are."
        case .idea: return "Adds an idea to \(destination.name)’s Content ideas. It is ready for the existing production workflow."
        case .stageConnection: return "Adds this capture as evidence for review in the Concept. Its writing changes only when you accept the evidence."
        case .swipe: return "Saves external inspiration in Swipe. An existing saved original is reused."
        case .task: return "Creates a task in Today, preserving the capture’s notes and checklist."
        case .research:
            switch destination.kind {
            case .space: return "Saves the link as a Research source in this Space. It appears with the Space’s materials, ready to open in Study — not in the Swipe File."
            case .group: return "Saves the link as a Research source and adds it to this Group."
            case .connection: return "Saves the link as a Research source, links it to this Concept, and stages it in References for your review."
            case .page: return "Saves the link as a Research source and attaches it as a reference on this Page."
            default: return "Saves the link as a Research source in your Library — for reading and study, not the Swipe File."
            }
        }
    }
}

struct InboxPlacementRequest: Codable, Equatable, Sendable {
    var version = 1
    var operationID: String
    var source: InboxCaptureReference
    var expectedSourceVersion: Int64
    var destination: InboxFilingDestination
    var action: InboxFilingAction
    var connectionSection: String? = nil
    var existingAtomUUID: String? = nil
}

struct InboxPlacementReceipt: Codable, Equatable, Sendable {
    static let metadataKey = "inboxPlacementReceipt"
    var version = 1
    var request: InboxPlacementRequest
    var resultAtomUUID: String
    var outcome: String
    var createdAt: String
    var originalStatus: String
    var originalCreatedObjectIDs: [String]
    /// Exact new original, used only to recognize untouched creation on undo.
    var createdAtom: Atom?
    var membershipIDs: [String] = []
    var addedGroupMember: Bool = false
    var referenceID: String? = nil
    var stagedInsertID: String? = nil
    var attachmentOwners: [InboxAttachmentOwner] = []
    var addedAttachmentIDs: [String]? = nil
    var isUndone = false
    var retainedOriginal = false
    /// Research filing onto a source that already existed (a swipe of the
    /// same link, an inquiry source) ADDED the research lens — undo takes
    /// exactly that back. Optional so pre-September-2026 receipts decode.
    var addedResearchLens: Bool? = nil
    /// Research filing into a Concept added the concept → source link.
    var addedConceptLink: Bool? = nil
}

struct InboxAttachmentOwner: Codable, Equatable, Sendable {
    var uuid: String
    var ownerType: String
    var ownerUUID: String
    var capturedItemID: String
}

enum InboxPlacementError: Error, LocalizedError, Equatable {
    case missingSource, staleSource, alreadyFiled, missingDestination, unsupported, conflict, emptyCapture
    var errorDescription: String? {
        switch self {
        case .missingSource: return "The original capture is no longer available."
        case .staleSource: return "This capture changed. Review its latest text before filing."
        case .alreadyFiled: return "This capture has already been filed. Open its history to review the result."
        case .missingDestination: return "This destination is no longer available. Choose another destination."
        case .unsupported: return "This action cannot be completed here. Choose another destination."
        case .conflict: return "This filing changed since it was saved. Its original is safe; review the current destination before undoing."
        case .emptyCapture: return "Add text or an original attachment before saving."
        }
    }
}

extension InboxItem {
    var placementReceipt: InboxPlacementReceipt? {
        guard let value = metadataDictionary[InboxPlacementReceipt.metadataKey],
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(InboxPlacementReceipt.self, from: data)
    }

    var captureReference: InboxCaptureReference {
        InboxCaptureReference(kind: metadataDictionary["captureRecordKind"] as? String == "lane" ? .lane : .inbox, uuid: uuid)
    }

    /// For a lane proxy, the lane it rests in — so a "Move to lane" menu can
    /// leave that lane out. Nil for queue captures.
    var restingLaneID: String? {
        metadataDictionary["captureLaneId"] as? String
    }
}
