import Foundation

struct CommandKCaptureRouter {
    private let classifier = SwipeURLClassifier()

    func preview(for input: String) -> CommandKCapturePreview? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard classifier.isURL(trimmed) else { return nil }

        let classification = classifier.classify(trimmed)
        guard classification.isUrl else { return nil }

        let kind: CommandKCaptureKind = Self.isSwipeSource(classification.sourceType) ? .swipe : .research
        let title = kind == .swipe ? "Capture Swipe" : "Capture Research"
        let toolName = kind == .swipe ? "capture_swipe" : "capture_research"
        let actionID: CommandKContextualActionID = kind == .swipe ? .captureSwipe : .captureResearch
        let icon = kind == .swipe ? "bolt.fill" : "doc.text.magnifyingglass"

        return CommandKCapturePreview(
            id: "\(kind.rawValue)-\(trimmed)",
            kind: kind,
            source: Self.source(for: classification.sourceType),
            title: title,
            subtitle: trimmed,
            primaryAction: CommandKContextualAction(
                id: actionID,
                category: .capture,
                title: title,
                subtitle: trimmed,
                systemImage: icon,
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: toolName, arguments: ["url": trimmed])
            )
        )
    }

    func suggestions(for input: String) -> [CommandKCapturePreview] {
        if let preview = preview(for: input) { return [preview] }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return [
            textPreview(kind: .task, title: "Create Task", actionID: .createTask, toolName: "create_task", input: trimmed),
            textPreview(kind: .idea, title: "Create Idea", actionID: .createIdea, toolName: "create_idea", input: trimmed),
            textPreview(
                kind: .inquiryExtract,
                title: "Add Inquiry Extract",
                actionID: .addInquiryExtract,
                toolName: "add_inquiry_extract",
                input: trimmed
            )
        ]
    }

    private func textPreview(
        kind: CommandKCaptureKind,
        title: String,
        actionID: CommandKContextualActionID,
        toolName: String,
        input: String
    ) -> CommandKCapturePreview {
        CommandKCapturePreview(
            id: "\(kind.rawValue)-\(input)",
            kind: kind,
            source: .text,
            title: title,
            subtitle: input,
            primaryAction: CommandKContextualAction(
                id: actionID,
                category: .capture,
                title: title,
                subtitle: input,
                systemImage: "text.badge.plus",
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: toolName, arguments: ["title": input])
            )
        )
    }

    private static func isSwipeSource(_ sourceType: ResearchRichContent.SourceType) -> Bool {
        switch sourceType {
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel,
             .youtube, .youtubeShort, .xPost, .twitter, .threads, .tiktok, .loom:
            return true
        default:
            return false
        }
    }

    private static func source(for sourceType: ResearchRichContent.SourceType) -> CommandKCaptureSource {
        switch sourceType {
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel:
            return .instagram
        case .youtube, .youtubeShort:
            return .youtube
        case .xPost, .twitter:
            return .x
        case .threads:
            return .threads
        case .tiktok:
            return .tiktok
        case .loom:
            return .loom
        case .website:
            return .website
        default:
            return .text
        }
    }
}
