import Foundation

enum CommandKSelectionKind: Equatable {
    case none
    case atom(AtomType)
    case swipe
    case idea
    case readwise
    case thinkspace
}

struct CommandKActionContext {
    let query: String
    let subject: CortexDetailSubject
    let hydratedAtom: Atom?
    let mode: CortexMode
    let activeInquirySessionUUID: String?
    let activeContentDraftUUID: String?

    var selectedAtomUUID: String? {
        subject.atomUUID ?? hydratedAtom?.uuid
    }

    var selectionKind: CommandKSelectionKind {
        switch subject {
        case .empty:
            return .none
        case .recent(let item):
            return .atom(item.type)
        case .result(let result):
            switch result.resultKind {
            case .atom, .project:
                return result.atomType.map(CommandKSelectionKind.atom) ?? .none
            case .thinkspace:
                return .thinkspace
            case .readwise:
                return .readwise
            case .browserPin:
                return .none
            }
        case .library(let item):
            return item.kind == .thinkspace ? .thinkspace : .atom(item.atomType)
        case .swipe:
            return .swipe
        case .idea:
            return .idea
        case .readwise:
            return .readwise
        case .action:
            return .none
        }
    }

    var hasActiveInquirySession: Bool {
        activeInquirySessionUUID?.isEmpty == false
    }

    var hasActiveContentDraft: Bool {
        activeContentDraftUUID?.isEmpty == false
    }
}

extension CommandKActionContext: Equatable {
    static func == (lhs: CommandKActionContext, rhs: CommandKActionContext) -> Bool {
        lhs.query == rhs.query
            && lhs.selectedAtomUUID == rhs.selectedAtomUUID
            && lhs.selectionKind == rhs.selectionKind
            && lhs.hydratedAtom == rhs.hydratedAtom
            && lhs.mode == rhs.mode
            && lhs.activeInquirySessionUUID == rhs.activeInquirySessionUUID
            && lhs.activeContentDraftUUID == rhs.activeContentDraftUUID
    }
}
