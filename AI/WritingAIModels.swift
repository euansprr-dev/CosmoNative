// CosmoOS/AI/WritingAIModels.swift
// Shared models for the Content Focus Writing AI card.

import Foundation
import AppKit

enum WritingAIMode: String, CaseIterable, Identifiable {
    case selectedText
    case draft
    case clientProfile
    case bestPosts
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selectedText: return "Selected text"
        case .draft: return "Current draft"
        case .clientProfile: return "Client profile"
        case .bestPosts: return "Best posts"
        case .web: return "Web"
        }
    }
}

enum WritingAIReferenceSource: String, CaseIterable, Identifiable {
    case currentDraft
    case clientProfile
    case bestPosts
    case swipes
    case blueprint
    case source
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .currentDraft: return "Current draft"
        case .clientProfile: return "Client profile"
        case .bestPosts: return "Best posts"
        case .swipes: return "Swipes"
        case .blueprint: return "Blueprint"
        case .source: return "Source"
        case .web: return "Web"
        }
    }

    var iconName: String {
        switch self {
        case .currentDraft: return "doc.text"
        case .clientProfile: return "person.crop.circle"
        case .bestPosts: return "chart.line.uptrend.xyaxis"
        case .swipes: return "square.stack.3d.up"
        case .blueprint: return "rectangle.on.rectangle.angled"
        case .source: return "link"
        case .web: return "globe"
        }
    }
}

struct WritingAIReference: Identifiable, Equatable {
    let id: UUID
    var source: WritingAIReferenceSource
    var title: String
    var excerpt: String
    var detail: String?
    var url: String?
    var atomUUID: String?
    var score: Double

    init(
        id: UUID = UUID(),
        source: WritingAIReferenceSource,
        title: String,
        excerpt: String,
        detail: String? = nil,
        url: String? = nil,
        atomUUID: String? = nil,
        score: Double = 0
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.excerpt = excerpt
        self.detail = detail
        self.url = url
        self.atomUUID = atomUUID
        self.score = score
    }
}

enum WritingAIEditTarget: Equatable {
    case none
    case selection
    case draftPreview
}

enum WritingAIQuickAction: String, CaseIterable, Identifiable {
    case tighten
    case makeSharper
    case clientVoice
    case improveHook
    case addProof
    case findStory
    case findExamples
    case searchProfile
    case searchBestPosts
    case searchWeb
    case critique
    case variations

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tighten: return "Tighten"
        case .makeSharper: return "Make sharper"
        case .clientVoice: return "More client voice"
        case .improveHook: return "Improve hook"
        case .addProof: return "Add proof"
        case .findStory: return "Find story"
        case .findExamples: return "Find examples"
        case .searchProfile: return "Search profile"
        case .searchBestPosts: return "Search best posts"
        case .searchWeb: return "Search web"
        case .critique: return "Critique this"
        case .variations: return "Create variations"
        }
    }

    var iconName: String {
        switch self {
        case .tighten: return "arrow.down.right.and.arrow.up.left"
        case .makeSharper: return "bolt"
        case .clientVoice: return "person.wave.2"
        case .improveHook: return "lasso.badge.sparkles"
        case .addProof: return "checkmark.seal"
        case .findStory: return "book.pages"
        case .findExamples: return "square.stack.3d.up"
        case .searchProfile: return "person.text.rectangle"
        case .searchBestPosts: return "chart.bar.xaxis"
        case .searchWeb: return "globe"
        case .critique: return "text.magnifyingglass"
        case .variations: return "square.grid.2x2"
        }
    }

    var mode: WritingAIMode {
        switch self {
        case .tighten, .makeSharper, .clientVoice:
            return .selectedText
        case .improveHook, .critique, .variations:
            return .draft
        case .findStory, .searchProfile:
            return .clientProfile
        case .findExamples, .searchBestPosts:
            return .bestPosts
        case .addProof, .searchWeb:
            return .web
        }
    }

    var editTarget: WritingAIEditTarget {
        switch self {
        case .tighten, .makeSharper, .clientVoice:
            return .selection
        default:
            return .none
        }
    }

    var prompt: String {
        switch self {
        case .tighten:
            return "Tighten the selected text. Preserve meaning, remove drag, and return only the replacement."
        case .makeSharper:
            return "Rewrite the selected text to be sharper, more specific, and more direct. Return only the replacement."
        case .clientVoice:
            return "Rewrite the selected text so it sounds more like the active client. Return only the replacement."
        case .improveHook:
            return "Improve the opening hook for this draft. Give 5 options and explain which one is strongest."
        case .addProof:
            return "Find proof, current data, source material, or stronger evidence for the draft's key claim."
        case .findStory:
            return "Find client stories, beliefs, proof, or lived examples that support this angle."
        case .findExamples:
            return "Find similar winning posts or swipes and adapt their patterns to this draft."
        case .searchProfile:
            return "Search the client profile for the most relevant stories, beliefs, phrases, offers, objections, and proof."
        case .searchBestPosts:
            return "Search best-performing posts and swipes. Compare their hooks/structures to this draft."
        case .searchWeb:
            return "Search the web for current proof, examples, stats, or source links for this draft."
        case .critique:
            return "Critique this draft as a writing coach. Identify weak claims, unclear sections, voice drift, missing proof, and the next best edit."
        case .variations:
            return "Create strong variations for this draft's angle, hook, or framing. Keep them client-aware."
        }
    }
}

struct WritingAIRequest {
    var prompt: String
    var action: WritingAIQuickAction?
    var selectedText: String
    var selectionContext: String
    var draftText: String
    var contentTitle: String
    var contentDescription: String
    var contentFormat: WritingContentFormat
    var currentStep: ContentStep
    var clientProfileAtom: Atom?
    var sourceIdeaAtom: Atom?
    var matchedSwipeAtoms: [Atom]
    var framework: String?
    var outline: [OutlineItem]
    var hooks: [String]

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveMode: WritingAIMode {
        if let action { return action.mode }
        return hasSelection ? .selectedText : .draft
    }
}

struct WritingAIContextPack {
    var mode: WritingAIMode
    var contentTitle: String
    var formatLabel: String
    var stepLabel: String
    var clientName: String?
    var selectedText: String
    var selectionContext: String
    var draftExcerpt: String
    var contentDescription: String
    var outlineSummary: String
    var hooksSummary: String
    var sourceSummary: String?
    var framework: String?
    var references: [WritingAIReference]
    var modelTier: AgentModelTier

    var contextLabels: [WritingAIReferenceSource] {
        var seen: Set<WritingAIReferenceSource> = []
        var labels: [WritingAIReferenceSource] = []
        for reference in references where !seen.contains(reference.source) {
            seen.insert(reference.source)
            labels.append(reference.source)
        }
        return labels
    }

    func promptBlock(userInstruction: String, wantsReplacement: Bool) -> String {
        let selectedBlock = selectedText.isEmpty ? "No active selection." : selectedText
        let replacementRule = wantsReplacement
            ? "The user needs an insertable replacement. Return only the replacement text unless context makes that impossible."
            : "Give a concise answer with clear next actions. Do not overwrite the draft."

        return """
        USER INSTRUCTION
        \(userInstruction)

        WRITING TARGET
        Title: \(contentTitle)
        Format: \(formatLabel)
        Mode: \(stepLabel)
        Client: \(clientName ?? "No active client")
        Task rule: \(replacementRule)

        SELECTED TEXT
        \(selectedBlock)

        SURROUNDING CONTEXT
        \(selectionContext.isEmpty ? "No surrounding context captured." : selectionContext)

        CURRENT DRAFT EXCERPT
        \(draftExcerpt.isEmpty ? "No draft text yet." : draftExcerpt)

        CORE IDEA / DESCRIPTION
        \(contentDescription.isEmpty ? "No core idea set." : contentDescription)

        OUTLINE
        \(outlineSummary.isEmpty ? "No outline set." : outlineSummary)

        HOOKS
        \(hooksSummary.isEmpty ? "No hooks set." : hooksSummary)

        SOURCE / BLUEPRINT
        \(sourceSummary ?? "No source idea attached.")
        \(framework.map { "Framework: \($0)" } ?? "No framework attached.")

        RETRIEVED CONTEXT
        \(references.map(Self.formatReference).joined(separator: "\n\n"))
        """
    }

    private static func formatReference(_ reference: WritingAIReference) -> String {
        var lines = [
            "[\(reference.source.label)] \(reference.title)",
            reference.excerpt
        ]
        if let detail = reference.detail, !detail.isEmpty {
            lines.append(detail)
        }
        if let url = reference.url, !url.isEmpty {
            lines.append("URL: \(url)")
        }
        return lines.joined(separator: "\n")
    }
}

struct WritingAIResponse: Identifiable {
    let id = UUID()
    var title: String
    var body: String
    var references: [WritingAIReference]
    var proposedReplacement: String?
    var editTarget: WritingAIEditTarget
    var modelTier: AgentModelTier

    var canReplaceSelection: Bool {
        editTarget == .selection && proposedReplacement?.isEmpty == false
    }
}

extension Notification.Name {
    static let contentFocusOpenWritingAI = Notification.Name("contentFocusOpenWritingAI")
}

@MainActor
final class ContentFocusWritingAIScope {
    static let shared = ContentFocusWritingAIScope()

    private var activeAtomUUID: String?
    private var openHandler: (() -> Void)?

    private init() {}

    func activate(atomUUID: String, openHandler: @escaping () -> Void) {
        activeAtomUUID = atomUUID
        self.openHandler = openHandler
    }

    func deactivate(atomUUID: String) {
        guard activeAtomUUID == atomUUID else { return }
        activeAtomUUID = nil
        openHandler = nil
    }

    @discardableResult
    func tryOpen() -> Bool {
        guard let openHandler else { return false }
        openHandler()
        return true
    }
}

enum WritingAIStringTools {
    static func excerpt(_ text: String, limit: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: limit)
        return cleaned[..<index].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func terms(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "have", "has", "you",
            "your", "are", "was", "were", "into", "about", "what", "when", "where",
            "why", "how", "can", "will", "would", "should", "could", "but", "not"
        ]
        return text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    static func lexicalScore(query: String, text: String) -> Double {
        let queryTerms = Set(terms(from: query))
        guard !queryTerms.isEmpty else { return 0 }
        let textTerms = terms(from: text)
        guard !textTerms.isEmpty else { return 0 }
        let textSet = Set(textTerms)
        let overlap = queryTerms.intersection(textSet).count
        let density = Double(overlap) / Double(max(queryTerms.count, 1))
        let repeated = textTerms.reduce(into: 0) { count, term in
            if queryTerms.contains(term) { count += 1 }
        }
        return density + min(Double(repeated) * 0.02, 0.35)
    }
}
