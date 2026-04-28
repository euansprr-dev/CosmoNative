// CosmoOS/AI/ContentWritingAssistant.swift
// Orchestrates the Content Focus floating Writing AI card.

import Foundation

@MainActor
final class ContentWritingAssistant: ObservableObject {
    enum Phase: Equatable {
        case idle
        case retrieving
        case thinking
        case answer
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentResponse: WritingAIResponse?
    @Published private(set) var activeReferences: [WritingAIReference] = []
    @Published private(set) var lastRequest: WritingAIRequest?

    private let contextBuilder = WritingAIContextBuilder()

    var isProcessing: Bool {
        phase == .retrieving || phase == .thinking
    }

    func submit(_ request: WritingAIRequest) async {
        lastRequest = request
        currentResponse = nil
        activeReferences = []
        phase = .retrieving

        var contextPack = await contextBuilder.build(for: request)
        activeReferences = contextPack.references

        if request.effectiveMode == .web || request.action == .addProof || request.action == .searchWeb {
            let webReferences = await webReferences(for: request)
            contextPack.references.append(contentsOf: webReferences)
            activeReferences = contextPack.references
        }

        phase = .thinking

        do {
            let wantsReplacement = request.action?.editTarget == .selection && request.hasSelection
            let response = try await callModel(
                instruction: request.prompt,
                contextPack: contextPack,
                wantsReplacement: wantsReplacement
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            currentResponse = WritingAIResponse(
                title: title(for: request),
                body: trimmed,
                references: contextPack.references,
                proposedReplacement: wantsReplacement ? trimmed : nil,
                editTarget: wantsReplacement ? .selection : .none,
                modelTier: contextPack.modelTier
            )
            phase = .answer
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func retry() async {
        guard let lastRequest else { return }
        await submit(lastRequest)
    }

    func reset() {
        phase = .idle
        currentResponse = nil
        activeReferences = []
    }

    private func callModel(
        instruction: String,
        contextPack: WritingAIContextPack,
        wantsReplacement: Bool
    ) async throws -> String {
        let systemPrompt = """
        You are Cosmo Writing AI inside Content Focus Mode.
        You are a precise writing instrument, not a generic chatbot.
        Keep the writer in flow.
        Use retrieved context only when it is relevant.
        Clearly distinguish client profile, best posts/swipes, source/blueprint, draft, and web evidence.
        Do not invent proof, metrics, client stories, or source links.
        If no relevant profile/post/source data exists, say so plainly.
        \(wantsReplacement ? "For this request, return only replacement text. No preamble, no bullets, no quotation marks." : "Answer in concise markdown with specific, usable writing guidance.")
        """

        let prompt = contextPack.promptBlock(userInstruction: instruction, wantsReplacement: wantsReplacement)

        return try await ResearchService.shared.analyze(
            prompt: prompt,
            systemPrompt: systemPrompt,
            tier: contextPack.modelTier,
            maxTokens: wantsReplacement ? 1_200 : min(contextPack.modelTier.maxTokens, 4_000)
        )
    }

    private func webReferences(for request: WritingAIRequest) async -> [WritingAIReference] {
        let query = webQuery(for: request)
        guard !query.isEmpty else { return [] }

        do {
            let result = try await ResearchService.shared.performResearch(
                query: query,
                searchType: .web,
                maxResults: 5
            )
            var references = result.findings.map { finding in
                WritingAIReference(
                    source: .web,
                    title: finding.title,
                    excerpt: finding.snippet ?? result.summary,
                    detail: "\(finding.source) · confidence \(finding.confidence)",
                    url: finding.url,
                    score: 0.8
                )
            }
            if references.isEmpty, !result.summary.isEmpty {
                references.append(WritingAIReference(
                    source: .web,
                    title: "Web research summary",
                    excerpt: result.summary,
                    detail: result.query,
                    score: 0.5
                ))
            }
            return references
        } catch {
            return [
                WritingAIReference(
                    source: .web,
                    title: "Web search unavailable",
                    excerpt: error.localizedDescription,
                    detail: "No web claims were added.",
                    score: 0
                )
            ]
        }
    }

    private func webQuery(for request: WritingAIRequest) -> String {
        let base = [
            request.prompt,
            request.selectedText,
            request.contentDescription,
            String(request.draftText.prefix(900))
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
        return WritingAIStringTools.excerpt(base, limit: 1_000)
    }

    private func title(for request: WritingAIRequest) -> String {
        if let action = request.action {
            return action.label
        }
        return request.hasSelection ? "Selection" : "Draft"
    }
}
