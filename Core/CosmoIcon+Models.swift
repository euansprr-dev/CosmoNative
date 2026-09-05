// Model adapters keep identity choices shared across every UI surface.
import SwiftUI

extension AtomType {
    var cosmoIcon: CosmoIcon {
        switch self {
        case .idea: return .idea
        case .content, .contentDraft: return .content
        case .connection: return .concept
        case .research: return .research
        case .thinkspace: return .space
        case .task: return .task
        case .project: return .project
        case .area: return .area
        case .note: return .note
        case .uncommittedItem: return .inbox
        case .calendarEvent: return .calendar
        case .clientProfile: return .clients
        case .creator: return .creators
        default: return .system(iconName)
        }
    }
}

extension Atom {
    /// Saved inspiration is a research atom in storage, but a Swipe in UI.
    var cosmoIcon: CosmoIcon { isSwipeFileAtom ? .swipe : type.cosmoIcon }
}
