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

        // "scan…" / "page…" / "photo…" — the user is reaching for a physical
        // page, not typing a thought. Offer the two intakes first.
        if Self.looksLikeScanIntent(trimmed) {
            return [
                scanPreview(
                    title: "Scan with iPhone",
                    subtitle: "Wake your iPhone as a page scanner",
                    actionID: .scanWithIPhone,
                    toolName: "scan_with_iphone",
                    icon: "iphone.and.arrow.right.inward"
                ),
                scanPreview(
                    title: "Upload Page Images",
                    subtitle: "Digitize image files into your Inbox",
                    actionID: .uploadScanImages,
                    toolName: "upload_scan_images",
                    icon: "photo.badge.plus"
                ),
                textPreview(kind: .task, title: "Create Task", actionID: .createTask, toolName: "create_task", input: trimmed),
            ]
        }

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

    /// A short query whose FIRST word reaches for the scanner. Longer text is
    /// a thought that happens to mention scanning — never hijack those.
    static func looksLikeScanIntent(_ input: String) -> Bool {
        let words = input.lowercased().split(separator: " ")
        guard let first = words.first, words.count <= 4 else { return false }
        return ["scan", "page", "photo", "physical", "digitize", "digitise"]
            .contains { $0.hasPrefix(first) || first.hasPrefix($0) }
    }

    private func scanPreview(
        title: String,
        subtitle: String,
        actionID: CommandKContextualActionID,
        toolName: String,
        icon: String
    ) -> CommandKCapturePreview {
        CommandKCapturePreview(
            id: "scan-\(toolName)",
            kind: .research,
            source: .text,
            title: title,
            subtitle: subtitle,
            primaryAction: CommandKContextualAction(
                id: actionID,
                category: .capture,
                title: title,
                subtitle: subtitle,
                systemImage: icon,
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: toolName, arguments: [:])
            )
        )
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
