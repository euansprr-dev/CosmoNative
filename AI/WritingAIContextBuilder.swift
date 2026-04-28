// CosmoOS/AI/WritingAIContextBuilder.swift
// Compact context construction and retrieval for Content Focus Writing AI.

import Foundation

@MainActor
final class ClientProfileRetriever {
    func retrieve(query: String, profileAtom: Atom?, limit: Int = 5) async -> [WritingAIReference] {
        guard let profileAtom,
              let meta = profileAtom.metadataValue(as: ClientProfileMetadata.self) else {
            return []
        }

        let chunks = makeChunks(meta: meta, profileAtom: profileAtom)
        return rank(chunks: chunks, query: query, limit: limit)
    }

    private func makeChunks(meta: ClientProfileMetadata, profileAtom: Atom) -> [WritingAIReference] {
        var chunks: [WritingAIReference] = []

        func add(_ title: String, _ text: String?, detail: String? = nil) {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            chunks.append(WritingAIReference(
                source: .clientProfile,
                title: title,
                excerpt: WritingAIStringTools.excerpt(text, limit: 1_200),
                detail: detail,
                atomUUID: profileAtom.uuid
            ))
        }

        add("Client summary", [
            meta.clientName,
            meta.niche,
            meta.industry,
            meta.targetAudience,
            meta.uniqueAngle,
            meta.notes
        ].compactMap { $0 }.joined(separator: "\n"))
        add("Brand story", meta.brandStory)
        add("Brand vision", meta.brandVision)
        add("Voice notes", meta.voiceNotes)

        if let beliefs = meta.coreBeliefs, !beliefs.isEmpty {
            add("Core beliefs", beliefs.joined(separator: "\n"))
        }
        if let phrases = meta.signaturePhrases, !phrases.isEmpty {
            add("Signature phrases", phrases.joined(separator: "\n"))
        }
        if let patterns = meta.preferredBeatPatterns, !patterns.isEmpty {
            add("Preferred beat patterns", patterns.joined(separator: "\n"))
        }
        if let voice = meta.extractedVoicePatterns {
            add("Extracted voice profile", [
                "Average sentence length: \(String(format: "%.1f", voice.avgSentenceLength))",
                "Reading level: \(voice.readingLevel)",
                "Emotional range: \(voice.emotionalRange)",
                "Recurring phrases: \(voice.recurringPhrases.joined(separator: ", "))",
                "CTA patterns: \(voice.ctaPatterns.joined(separator: ", "))",
                "Stylistic quirks: \(voice.stylisticQuirks.joined(separator: ", "))"
            ].joined(separator: "\n"))
        }

        for (index, transcript) in (meta.topPerformingTranscripts ?? []).enumerated() {
            add("Top transcript \(index + 1)", transcript)
        }

        for post in meta.topPerformingPosts ?? [] {
            add(
                "Top post · \(post.platform)",
                post.transcript,
                detail: "Views \(post.views) · Likes \(post.likes) · Shares \(post.shares) · Leads \(post.leads) · \(post.datePosted)"
            )
        }

        for document in meta.documents ?? [] {
            let label = "\(document.category.displayName) · \(document.title)"
            let detail = metricsDetail(for: document)
            for (chunkIndex, chunk) in chunkText(document.content, maxLength: 1_400).enumerated() {
                chunks.append(WritingAIReference(
                    source: document.category.isHighPerformer ? .bestPosts : .clientProfile,
                    title: chunkIndex == 0 ? label : "\(label) · \(chunkIndex + 1)",
                    excerpt: chunk,
                    detail: detail,
                    url: document.sourceURL,
                    atomUUID: profileAtom.uuid
                ))
            }
        }

        return chunks
    }

    private func rank(chunks: [WritingAIReference], query: String, limit: Int) -> [WritingAIReference] {
        chunks
            .map { reference -> WritingAIReference in
                var copy = reference
                copy.score = WritingAIStringTools.lexicalScore(
                    query: query,
                    text: "\(reference.title)\n\(reference.excerpt)\n\(reference.detail ?? "")"
                )
                return copy
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.excerpt.count > rhs.excerpt.count
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func chunkText(_ text: String, maxLength: Int) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned.isEmpty ? [] : [cleaned] }

        var chunks: [String] = []
        var start = cleaned.startIndex
        while start < cleaned.endIndex {
            let tentativeEnd = cleaned.index(start, offsetBy: maxLength, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            var end = tentativeEnd
            if tentativeEnd < cleaned.endIndex,
               let sentenceBreak = cleaned[start..<tentativeEnd].lastIndex(where: { ".!?\n".contains($0) }) {
                end = cleaned.index(after: sentenceBreak)
            }
            chunks.append(String(cleaned[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            start = end
        }
        return chunks.filter { !$0.isEmpty }
    }

    private func metricsDetail(for document: ProfileDocument) -> String? {
        var parts: [String] = []
        if let platform = document.platform, !platform.isEmpty { parts.append(platform) }
        if let likes = document.likes { parts.append("\(likes) likes") }
        if let shares = document.shares { parts.append("\(shares) shares") }
        if let saves = document.saves { parts.append("\(saves) saves") }
        if let comments = document.comments { parts.append("\(comments) comments") }
        if let leads = document.leads { parts.append("\(leads) leads") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
final class BestPostRetriever {
    func retrieve(
        query: String,
        profileAtom: Atom?,
        matchedSwipeAtoms: [Atom],
        limit: Int = 5
    ) async -> [WritingAIReference] {
        var references = localBestPostReferences(profileAtom: profileAtom, matchedSwipeAtoms: matchedSwipeAtoms)

        if references.count < limit {
            references.append(contentsOf: await globalSwipeReferences(query: query, excluding: Set(references.compactMap(\.atomUUID))))
        }

        return references
            .map { reference -> WritingAIReference in
                var copy = reference
                let lexical = WritingAIStringTools.lexicalScore(
                    query: query,
                    text: "\(reference.title)\n\(reference.excerpt)\n\(reference.detail ?? "")"
                )
                copy.score = max(reference.score, lexical)
                return copy
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private func localBestPostReferences(profileAtom: Atom?, matchedSwipeAtoms: [Atom]) -> [WritingAIReference] {
        var refs: [WritingAIReference] = []

        if let profileAtom,
           let meta = profileAtom.metadataValue(as: ClientProfileMetadata.self) {
            for post in meta.topPerformingPosts ?? [] {
                refs.append(WritingAIReference(
                    source: .bestPosts,
                    title: "Client top post · \(post.platform)",
                    excerpt: WritingAIStringTools.excerpt(post.transcript, limit: 1_000),
                    detail: "Views \(post.views) · Likes \(post.likes) · Shares \(post.shares) · Leads \(post.leads) · \(post.datePosted)",
                    atomUUID: profileAtom.uuid,
                    score: performanceScore(views: post.views, likes: post.likes, shares: post.shares, leads: post.leads)
                ))
            }

            for document in meta.documents ?? [] where document.category.isHighPerformer {
                refs.append(WritingAIReference(
                    source: .bestPosts,
                    title: document.title,
                    excerpt: WritingAIStringTools.excerpt(document.content, limit: 1_000),
                    detail: metricsDetail(for: document),
                    url: document.sourceURL,
                    atomUUID: profileAtom.uuid,
                    score: performanceScore(
                        views: 0,
                        likes: document.likes ?? 0,
                        shares: document.shares ?? 0,
                        leads: document.leads ?? 0
                    )
                ))
            }
        }

        for swipe in matchedSwipeAtoms {
            refs.append(WritingAIReference(
                source: currentBlueprintCandidate(swipe, in: matchedSwipeAtoms) ? .blueprint : .swipes,
                title: swipe.title ?? "Attached swipe",
                excerpt: WritingAIStringTools.excerpt(swipe.body ?? swipe.researchMetadata?.summary ?? swipe.researchMetadata?.hook ?? "", limit: 900),
                detail: swipe.researchMetadata?.hook,
                url: swipe.researchMetadata?.url,
                atomUUID: swipe.uuid,
                score: 0.7
            ))
        }

        return refs
    }

    private func globalSwipeReferences(query: String, excluding excluded: Set<String>) async -> [WritingAIReference] {
        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 6,
                entityTypes: [.swipeFile, .research],
                excludedEntityUUIDs: Array(excluded)
            )
            return results.map { result in
                WritingAIReference(
                    source: .swipes,
                    title: result.title,
                    excerpt: result.preview,
                    atomUUID: result.entityUUID,
                    score: result.combinedScore
                )
            }
        } catch {
            return []
        }
    }

    private func currentBlueprintCandidate(_ atom: Atom, in swipes: [Atom]) -> Bool {
        swipes.first?.uuid == atom.uuid
    }

    private func performanceScore(views: Int, likes: Int, shares: Int, leads: Int) -> Double {
        let raw = Double(views) * 0.00001 + Double(likes) * 0.001 + Double(shares) * 0.004 + Double(leads) * 0.02
        return min(1.0, raw)
    }

    private func metricsDetail(for document: ProfileDocument) -> String? {
        var parts: [String] = []
        if let platform = document.platform, !platform.isEmpty { parts.append(platform) }
        if let likes = document.likes { parts.append("\(likes) likes") }
        if let shares = document.shares { parts.append("\(shares) shares") }
        if let saves = document.saves { parts.append("\(saves) saves") }
        if let comments = document.comments { parts.append("\(comments) comments") }
        if let leads = document.leads { parts.append("\(leads) leads") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
final class WritingAIContextBuilder {
    private let profileRetriever = ClientProfileRetriever()
    private let bestPostRetriever = BestPostRetriever()

    func build(for request: WritingAIRequest) async -> WritingAIContextPack {
        let query = compactQuery(for: request)
        var references: [WritingAIReference] = []

        if let source = request.sourceIdeaAtom {
            references.append(WritingAIReference(
                source: .source,
                title: source.title ?? "Source idea",
                excerpt: WritingAIStringTools.excerpt(source.body ?? "", limit: 800),
                atomUUID: source.uuid,
                score: 1
            ))
        }

        switch request.effectiveMode {
        case .selectedText:
            references.append(contentsOf: await profileRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, limit: 3))
            references.append(contentsOf: await bestPostRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, matchedSwipeAtoms: request.matchedSwipeAtoms, limit: 2))
        case .draft:
            references.append(contentsOf: await profileRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, limit: 4))
            references.append(contentsOf: await bestPostRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, matchedSwipeAtoms: request.matchedSwipeAtoms, limit: 4))
        case .clientProfile:
            references.append(contentsOf: await profileRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, limit: 6))
        case .bestPosts:
            references.append(contentsOf: await bestPostRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, matchedSwipeAtoms: request.matchedSwipeAtoms, limit: 6))
        case .web:
            references.append(contentsOf: await profileRetriever.retrieve(query: query, profileAtom: request.clientProfileAtom, limit: 2))
        }

        return WritingAIContextPack(
            mode: request.effectiveMode,
            contentTitle: request.contentTitle,
            formatLabel: request.contentFormat.displayName,
            stepLabel: request.currentStep.label,
            clientName: request.clientProfileAtom?.metadataValue(as: ClientProfileMetadata.self)?.clientName ?? request.clientProfileAtom?.title,
            selectedText: limited(request.selectedText, max: 4_000),
            selectionContext: limited(request.selectionContext, max: 2_000),
            draftExcerpt: draftExcerpt(request.draftText),
            contentDescription: limited(request.contentDescription, max: 1_200),
            outlineSummary: outlineSummary(request.outline),
            hooksSummary: request.hooks.prefix(6).joined(separator: "\n"),
            sourceSummary: request.sourceIdeaAtom.map { "\($0.title ?? "Source idea")\n\(WritingAIStringTools.excerpt($0.body ?? "", limit: 700))" },
            framework: request.framework,
            references: Array(references.prefix(10)),
            modelTier: modelTier(for: request)
        )
    }

    private func compactQuery(for request: WritingAIRequest) -> String {
        [
            request.prompt,
            request.selectedText,
            request.contentDescription,
            String(request.draftText.prefix(1_200)),
            request.hooks.joined(separator: " ")
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func modelTier(for request: WritingAIRequest) -> AgentModelTier {
        Self.modelTier(forDraftCharacterCount: request.draftText.count, action: request.action)
    }

    static func modelTier(forDraftCharacterCount draftCharacterCount: Int, action: WritingAIQuickAction?) -> AgentModelTier {
        if action?.mode == .web { return .strategist }
        if action?.editTarget == .selection { return .strategist }
        if draftCharacterCount > 12_000 || action == .critique {
            return .writer
        }
        return .strategist
    }

    private func draftExcerpt(_ draft: String) -> String {
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 7_000 else { return cleaned }
        let opening = WritingAIStringTools.excerpt(cleaned, limit: 3_500)
        let closingStart = cleaned.index(cleaned.endIndex, offsetBy: -3_000)
        let closing = cleaned[closingStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(opening)\n\n[...middle omitted for budget...]\n\n\(closing)"
    }

    private func outlineSummary(_ outline: [OutlineItem]) -> String {
        outline
            .prefix(12)
            .enumerated()
            .map { index, item in
                let reasoning = item.reasoning.isEmpty ? "" : " — \(WritingAIStringTools.excerpt(item.reasoning, limit: 140))"
                return "\(index + 1). \(item.title)\(reasoning)"
            }
            .joined(separator: "\n")
    }

    private func limited(_ text: String, max: Int) -> String {
        WritingAIStringTools.excerpt(text, limit: max)
    }
}
