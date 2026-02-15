// CosmoOS/Agent/Pipeline/BrainstormToThinkspacePipeline.swift
// Converts brainstorm conversations into Thinkspace atoms

import Foundation

struct MaterializeResult: Sendable {
    let ideaUUID: String?
    let contentUUID: String?
    let thinkspaceUUID: String?
    let summary: String
}

@MainActor
class BrainstormToThinkspacePipeline {
    static let shared = BrainstormToThinkspacePipeline()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Materialize

    func materialize(conversation: AgentConversation) async throws -> MaterializeResult {
        // 1. Extract key content from conversation
        let extraction = extractBrainstormContent(from: conversation)

        // 2. Create idea atom
        var ideaUUID: String? = nil
        if !extraction.ideaTitle.isEmpty {
            let ideaMeta: [String: Any] = [
                "source": "agent_brainstorm",
                "conversationId": conversation.id,
                "ideaStatus": "spark"
            ]
            let ideaMetaJSON = (try? JSONSerialization.data(withJSONObject: ideaMeta)).flatMap { String(data: $0, encoding: .utf8) }

            let ideaAtom = Atom.new(
                type: .idea,
                title: extraction.ideaTitle,
                body: extraction.ideaBody,
                metadata: ideaMetaJSON
            )
            let saved = try await atomRepo.create(ideaAtom)
            ideaUUID = saved.uuid
        }

        // 3. Optionally create content atom if format was decided
        var contentUUID: String? = nil
        if let format = extraction.contentFormat {
            var contentMeta: [String: Any] = [
                "phase": "brainstorm",
                "contentFormat": format
            ]
            if let iUUID = ideaUUID {
                contentMeta["sourceIdeaUUID"] = iUUID
            }
            let contentMetaJSON = (try? JSONSerialization.data(withJSONObject: contentMeta)).flatMap { String(data: $0, encoding: .utf8) }

            var links: [AtomLink] = []
            if let iUUID = ideaUUID {
                links.append(AtomLink(type: "sourceIdea", uuid: iUUID, entityType: "idea"))
            }

            let contentAtom = Atom.new(
                type: .content,
                title: extraction.ideaTitle,
                body: extraction.outline,
                metadata: contentMetaJSON,
                links: links.isEmpty ? nil : links
            )
            let saved = try await atomRepo.create(contentAtom)
            contentUUID = saved.uuid
        }

        // 4. Create thinkspace atom
        var blocks: [[String: Any]] = []

        if let iUUID = ideaUUID {
            blocks.append([
                "uuid": iUUID,
                "type": "idea",
                "x": 100,
                "y": 200,
                "width": 320,
                "height": 340
            ])
        }

        if let cUUID = contentUUID {
            blocks.append([
                "uuid": cUUID,
                "type": "content",
                "x": 500,
                "y": 200,
                "width": 320,
                "height": 340
            ])
        }

        let thinkspaceData: [String: Any] = [
            "blocks": blocks,
            "zoom": 1.0,
            "offsetX": 0,
            "offsetY": 0
        ]
        let structuredJSON = (try? JSONSerialization.data(withJSONObject: thinkspaceData)).flatMap { String(data: $0, encoding: .utf8) }

        var thinkspaceLinks: [AtomLink] = []
        if let iUUID = ideaUUID {
            thinkspaceLinks.append(AtomLink(type: "contains", uuid: iUUID, entityType: "idea"))
        }
        if let cUUID = contentUUID {
            thinkspaceLinks.append(AtomLink(type: "contains", uuid: cUUID, entityType: "content"))
        }

        let thinkspaceAtom = Atom.new(
            type: .thinkspace,
            title: "Brainstorm: \(extraction.ideaTitle)",
            structured: structuredJSON,
            links: thinkspaceLinks.isEmpty ? nil : thinkspaceLinks
        )
        let savedThinkspace = try await atomRepo.create(thinkspaceAtom)

        // 5. Post notification to open thinkspace on desktop
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.thinkspace,
                "id": Int64(savedThinkspace.id ?? 0)
            ]
        )

        let ideaLabel = ideaUUID != nil ? "idea" : ""
        let contentLabel = contentUUID != nil ? "+ content" : ""
        let summary = "Created \(ideaLabel) \(contentLabel) in Thinkspace '\(extraction.ideaTitle)'"

        return MaterializeResult(
            ideaUUID: ideaUUID,
            contentUUID: contentUUID,
            thinkspaceUUID: savedThinkspace.uuid,
            summary: summary
        )
    }

    // MARK: - Materialize Single Idea

    /// Quick path: extract just an idea from a conversation without creating a full thinkspace
    func materializeIdea(from conversation: AgentConversation) async throws -> String {
        let extraction = extractBrainstormContent(from: conversation)

        let ideaMeta: [String: Any] = [
            "source": "agent_brainstorm",
            "conversationId": conversation.id,
            "ideaStatus": "spark"
        ]
        let ideaMetaJSON = (try? JSONSerialization.data(withJSONObject: ideaMeta)).flatMap { String(data: $0, encoding: .utf8) }

        let atom = Atom.new(
            type: .idea,
            title: extraction.ideaTitle,
            body: extraction.ideaBody,
            metadata: ideaMetaJSON
        )
        let saved = try await atomRepo.create(atom)
        return saved.uuid
    }

    // MARK: - Extract Content

    private func extractBrainstormContent(from conversation: AgentConversation) -> BrainstormExtraction {
        let userMessages = conversation.messages.filter { $0.role == .user }
        let assistantMessages = conversation.messages.filter { $0.role == .assistant }

        // Use first user message as idea seed
        let rawTitle = userMessages.first?.content.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Brainstorm"
        let ideaTitle = String(rawTitle)

        // Combine all user messages for idea body
        let ideaBody = userMessages.map { $0.content }.joined(separator: "\n\n")

        // Check if a content format was mentioned
        var contentFormat: String? = nil
        let allText = conversation.messages.map { $0.content }.joined(separator: " ").lowercased()
        if allText.contains("thread") { contentFormat = "thread" }
        else if allText.contains("reel") { contentFormat = "reel" }
        else if allText.contains("carousel") { contentFormat = "carousel" }
        else if allText.contains("newsletter") { contentFormat = "newsletter" }
        else if allText.contains("article") || allText.contains("blog") { contentFormat = "longform" }

        // Build outline from last assistant response
        let outline = assistantMessages.last?.content ?? ""

        return BrainstormExtraction(
            ideaTitle: ideaTitle,
            ideaBody: ideaBody,
            contentFormat: contentFormat,
            outline: outline
        )
    }
}

private struct BrainstormExtraction {
    let ideaTitle: String
    let ideaBody: String
    let contentFormat: String?
    let outline: String
}
