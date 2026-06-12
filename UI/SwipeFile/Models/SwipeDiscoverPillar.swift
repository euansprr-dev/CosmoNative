import SwiftUI

/// The Discover topic scopes — the old decorative pillar cards, now functional.
/// Selecting one writes its term set into `SocialDiscoveryQuery.topicTerms`.
enum SwipeDiscoverPillar: String, CaseIterable, Identifiable {
    case productivity
    case selfImprovement
    case business
    case psychology
    case contentCreation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productivity: return "Productivity"
        case .selfImprovement: return "Self-improvement"
        case .business: return "Business"
        case .psychology: return "Psychology"
        case .contentCreation: return "Content creation"
        }
    }

    var systemImage: String {
        switch self {
        case .productivity: return "bolt"
        case .selfImprovement: return "sparkles"
        case .business: return "briefcase"
        case .psychology: return "brain.head.profile"
        case .contentCreation: return "camera"
        }
    }

    var tint: Color {
        switch self {
        case .productivity: return DS.entityResearch
        case .selfImprovement: return DS.entityIdea
        case .business: return DS.entityContent
        case .psychology: return DS.entityConnection
        case .contentCreation: return DS.entitySwipe
        }
    }

    /// Any-match terms applied to post title/body.
    var searchTerms: [String] {
        switch self {
        case .productivity:
            return ["productivity", "deep work", "time management", "focus", "routine", "habits", "procrastination"]
        case .selfImprovement:
            return ["self improvement", "self-improvement", "discipline", "mindset", "growth", "confidence", "motivation"]
        case .business:
            return ["business", "revenue", "startup", "entrepreneur", "money", "profit", "marketing", "sales", "client"]
        case .psychology:
            return ["psychology", "brain", "dopamine", "cognitive", "behavior", "persuasion", "bias", "emotion"]
        case .contentCreation:
            return ["content", "creator", "audience", "youtube", "views", "hook", "viral", "post", "newsletter"]
        }
    }
}
