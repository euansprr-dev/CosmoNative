import Foundation

enum CommandKCaptureKind: String, Codable, Equatable {
    case swipe
    case research
    case idea
    case task
    case content
    case inquiryExtract
}

enum CommandKCaptureSource: String, Codable, Equatable {
    case instagram
    case youtube
    case x
    case threads
    case tiktok
    case loom
    case website
    case text
}

struct CommandKCapturePreview: Identifiable, Equatable {
    let id: String
    let kind: CommandKCaptureKind
    let source: CommandKCaptureSource
    let title: String
    let subtitle: String
    let primaryAction: CommandKContextualAction
}
