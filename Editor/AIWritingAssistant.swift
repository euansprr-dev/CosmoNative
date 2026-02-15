// CosmoOS/Editor/AIWritingAssistant.swift
// AI-powered writing assistance via OpenRouter API
// Rewritten February 2026 — replaces deprecated LocalLLM stubs

import SwiftUI

// MARK: - AI Writing Action

enum AIWritingAction: String, CaseIterable {
    case expand, condense, rephrase, continueWriting

    var displayName: String {
        switch self {
        case .expand: return "Expand"
        case .condense: return "Condense"
        case .rephrase: return "Rephrase"
        case .continueWriting: return "Continue"
        }
    }

    var iconName: String {
        switch self {
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .condense: return "arrow.down.right.and.arrow.up.left"
        case .rephrase: return "arrow.triangle.2.circlepath"
        case .continueWriting: return "arrow.right"
        }
    }

    var description: String {
        switch self {
        case .expand: return "Add more detail and examples"
        case .condense: return "Make it more concise"
        case .rephrase: return "Say it differently"
        case .continueWriting: return "Continue your thought"
        }
    }
}

// MARK: - AI Writing Result

struct AIWritingResult {
    let originalText: String
    let suggestedText: String
    let action: AIWritingAction
    let variants: [String]?
}

// MARK: - Word Diff

enum DiffType {
    case unchanged, added, removed
}

struct DiffWord: Identifiable {
    let id = UUID()
    let text: String
    let type: DiffType
}

// MARK: - AI Writing Assistant

@MainActor
class AIWritingAssistant: ObservableObject {
    @Published var isProcessing = false
    @Published var currentResult: AIWritingResult?
    @Published var error: String?

    /// Optional client profile atom for brand-aware writing. Set before calling actions.
    var clientProfileAtom: Atom?

    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "google/gemini-3-flash-preview"

    /// Returns profile context string if a client profile is set, empty otherwise.
    private var profileContextBlock: String {
        guard let atom = clientProfileAtom,
              let meta = atom.metadataValue(as: ClientProfileMetadata.self) else {
            return ""
        }
        return "\n\n" + meta.toAIContextString() + "\nMatch this client's brand voice and style in your output."
    }

    // MARK: - Public Actions

    func expand(text: String, context: String? = nil) async -> AIWritingResult? {
        let systemPrompt = """
            You are a skilled writing assistant. Expand the given text by adding more detail, \
            examples, and supporting points while maintaining the original voice and meaning. \
            Return ONLY the expanded text, nothing else.\(profileContextBlock)
            """
        let userPrompt: String
        if let context = context {
            userPrompt = "Context:\n\(context)\n\nExpand this text:\n\(text)"
        } else {
            userPrompt = "Expand this text:\n\(text)"
        }

        return await perform(action: .expand, text: text, systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    func condense(text: String, context: String? = nil) async -> AIWritingResult? {
        let systemPrompt = """
            You are a skilled writing assistant. Condense the given text to be more concise \
            while preserving all key information and the original meaning. Remove filler words, \
            redundancies, and unnecessary qualifiers. Return ONLY the condensed text, nothing else.\(profileContextBlock)
            """
        let userPrompt: String
        if let context = context {
            userPrompt = "Context:\n\(context)\n\nCondense this text:\n\(text)"
        } else {
            userPrompt = "Condense this text:\n\(text)"
        }

        return await perform(action: .condense, text: text, systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    func rephrase(text: String, context: String? = nil) async -> AIWritingResult? {
        let systemPrompt = """
            You are a skilled writing assistant. Provide exactly 3 alternative ways to phrase \
            the given text. Each variant should preserve the original meaning but use different \
            wording, structure, or tone. Separate each variant with the delimiter: ---VARIANT---
            Return ONLY the three variants separated by ---VARIANT---, nothing else.\(profileContextBlock)
            """
        let userPrompt: String
        if let context = context {
            userPrompt = "Context:\n\(context)\n\nRephrase this text (3 variants):\n\(text)"
        } else {
            userPrompt = "Rephrase this text (3 variants):\n\(text)"
        }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        do {
            let response = try await callAPI(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let variants = response
                .components(separatedBy: "---VARIANT---")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let suggested = variants.first ?? response.trimmingCharacters(in: .whitespacesAndNewlines)
            let allVariants = variants.isEmpty ? nil : variants

            let result = AIWritingResult(
                originalText: text,
                suggestedText: suggested,
                action: .rephrase,
                variants: allVariants
            )
            currentResult = result
            return result
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func continueWriting(text: String, outline: [String]? = nil, coreIdea: String? = nil) async -> AIWritingResult? {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        var prompt = "Continue writing naturally from where this text leaves off. "
        prompt += "Match the existing tone, style, and pacing. "
        prompt += "Return ONLY the continuation text (do not repeat the original).\n\n"

        // Inject profile context if available
        if let atom = clientProfileAtom,
           let meta = atom.metadataValue(as: ClientProfileMetadata.self) {
            prompt += meta.toAIContextString() + "\nMatch this client's brand voice and style.\n\n"
        }

        if let coreIdea = coreIdea, !coreIdea.isEmpty {
            prompt += "Core idea: \(coreIdea)\n"
        }
        if let outline = outline, !outline.isEmpty {
            prompt += "Outline points to cover: \(outline.joined(separator: ", "))\n"
        }
        prompt += "\nText to continue from:\n\(text)"

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let suggested = response.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = AIWritingResult(
                originalText: text,
                suggestedText: text + "\n\n" + suggested,
                action: .continueWriting,
                variants: nil
            )
            currentResult = result
            return result
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Word Diff

    func computeWordDiff(original: String, suggested: String) -> [DiffWord] {
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let suggestedWords = suggested.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Simple LCS-based diff
        let m = originalWords.count
        let n = suggestedWords.count

        // Build LCS table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) {
            guard i <= m else { break }
            for j in 1...max(n, 1) {
                guard j <= n else { break }
                if originalWords[i - 1].lowercased() == suggestedWords[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to build diff
        var result: [DiffWord] = []
        var i = m, j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && originalWords[i - 1].lowercased() == suggestedWords[j - 1].lowercased() {
                result.append(DiffWord(text: suggestedWords[j - 1], type: .unchanged))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(DiffWord(text: suggestedWords[j - 1], type: .added))
                j -= 1
            } else if i > 0 {
                result.append(DiffWord(text: originalWords[i - 1], type: .removed))
                i -= 1
            }
        }

        return result.reversed()
    }

    // MARK: - Private Helpers

    private func perform(action: AIWritingAction, text: String, systemPrompt: String, userPrompt: String) async -> AIWritingResult? {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        do {
            let response = try await callAPI(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let suggested = response.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = AIWritingResult(
                originalText: text,
                suggestedText: suggested,
                action: action,
                variants: nil
            )
            currentResult = result
            return result
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func callAPI(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            throw AIWritingError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS Writing Assistant", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.5,
            "max_tokens": 3000,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWritingError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIWritingError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIWritingError.parsingError
        }

        return content
    }
}

// MARK: - AI Writing Errors

enum AIWritingError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured"
        case .invalidResponse:
            return "Invalid response from writing API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parsingError:
            return "Failed to parse API response"
        }
    }
}

// MARK: - Writing Suggestion (kept for backward compatibility)

struct WritingSuggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let description: String

    enum SuggestionType {
        case improve, summarize, expand, fix, tone, title, outline, `continue`
    }
}

// MARK: - Writing Tone (kept for backward compatibility)

enum WritingTone: String, CaseIterable {
    case professional = "professional"
    case casual = "casual"
    case formal = "formal"
    case friendly = "friendly"
    case persuasive = "persuasive"
    case academic = "academic"
}

// MARK: - AI Assistant Overlay

struct AIAssistantOverlay: View {
    @Binding var selectedText: String
    @Binding var isVisible: Bool
    let onApply: (String) -> Void

    @StateObject private var assistant = AIWritingAssistant()
    @State private var selectedVariantIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Content
            if assistant.isProcessing {
                processingView
            } else if let result = assistant.currentResult {
                resultView(result)
            } else if let error = assistant.error {
                errorView(error)
            } else {
                actionGrid
            }
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            Text("AI Assistant")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: { isVisible = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Action Grid (2x2)

    private var actionGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton(.expand)
                actionButton(.condense)
            }
            HStack(spacing: 8) {
                actionButton(.rephrase)
                actionButton(.continueWriting)
            }
        }
        .padding(16)
    }

    private func actionButton(_ action: AIWritingAction) -> some View {
        Button(action: { performAction(action) }) {
            actionButtonLabel(action)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionButtonLabel(_ action: AIWritingAction) -> some View {
        VStack(spacing: 6) {
            Image(systemName: action.iconName)
                .font(.system(size: 18))
                .foregroundColor(.purple)

            Text(action.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)

            Text(action.description)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.purple)

            Text("Processing...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(_ result: AIWritingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Action label
            HStack(spacing: 6) {
                Image(systemName: result.action.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text(result.action.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
            }

            // Variant picker for rephrase
            if result.action == .rephrase, let variants = result.variants, variants.count > 1 {
                rephraseVariantPicker(variants)
            } else if result.action == .continueWriting {
                // For continue, show only the new text
                continuationPreview(result)
            } else {
                // Diff preview
                diffPreview(result)
            }

            // Action buttons
            HStack(spacing: 10) {
                Button(action: {
                    if result.action == .rephrase,
                       let variants = result.variants,
                       selectedVariantIndex < variants.count {
                        onApply(variants[selectedVariantIndex])
                    } else {
                        onApply(result.suggestedText)
                    }
                    isVisible = false
                }) {
                    acceptButtonLabel
                }
                .buttonStyle(.plain)

                Button(action: {
                    assistant.currentResult = nil
                    assistant.error = nil
                }) {
                    rejectButtonLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var acceptButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
            Text("Accept")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple)
        )
    }

    @ViewBuilder
    private var rejectButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
            Text("Reject")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Diff Preview

    @ViewBuilder
    private func diffPreview(_ result: AIWritingResult) -> some View {
        let diffWords = assistant.computeWordDiff(
            original: result.originalText,
            suggested: result.suggestedText
        )
        ScrollView {
            WrappingDiffText(words: diffWords)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Continuation Preview

    @ViewBuilder
    private func continuationPreview(_ result: AIWritingResult) -> some View {
        let continuation = String(result.suggestedText.dropFirst(result.originalText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            Text(continuation)
                .font(.system(size: 13))
                .foregroundColor(.green.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Rephrase Variant Picker

    @ViewBuilder
    private func rephraseVariantPicker(_ variants: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                Button(action: { selectedVariantIndex = index }) {
                    variantRowLabel(index: index, variant: variant)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func variantRowLabel(index: Int, variant: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: selectedVariantIndex == index ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(selectedVariantIndex == index ? .purple : .white.opacity(0.3))
                .padding(.top, 2)

            Text(variant)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedVariantIndex == index
                      ? Color.purple.opacity(0.12)
                      : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedVariantIndex == index
                                ? Color.purple.opacity(0.3)
                                : Color.clear, lineWidth: 1)
                )
        )
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ errorMessage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundColor(.orange)

            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button(action: {
                assistant.error = nil
                assistant.currentResult = nil
            }) {
                Text("Try Again")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func performAction(_ action: AIWritingAction) {
        Task {
            switch action {
            case .expand:
                _ = await assistant.expand(text: selectedText)
            case .condense:
                _ = await assistant.condense(text: selectedText)
            case .rephrase:
                selectedVariantIndex = 0
                _ = await assistant.rephrase(text: selectedText)
            case .continueWriting:
                _ = await assistant.continueWriting(text: selectedText)
            }
        }
    }
}

// MARK: - Wrapping Diff Text

/// Displays diff words in a flowing text layout with color coding
private struct WrappingDiffText: View {
    let words: [DiffWord]

    var body: some View {
        // Build an attributed-style text using Text concatenation
        words.enumerated().reduce(Text("")) { result, pair in
            let w = pair.element
            let separator = pair.offset == 0 ? Text("") : Text(" ")
            switch w.type {
            case .unchanged:
                return result + separator + Text(w.text)
                    .foregroundColor(.white.opacity(0.7))
            case .removed:
                return result + separator + Text(w.text)
                    .foregroundColor(.red.opacity(0.8))
                    .strikethrough(true, color: .red.opacity(0.6))
            case .added:
                return result + separator + Text(w.text)
                    .foregroundColor(.green.opacity(0.9))
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - Suggestion Row (kept for backward compatibility)

struct SuggestionRow: View {
    let suggestion: WritingSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconForType(suggestion.type))
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(suggestion.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func iconForType(_ type: WritingSuggestion.SuggestionType) -> String {
        switch type {
        case .improve: return "wand.and.stars"
        case .summarize: return "arrow.down.right.and.arrow.up.left"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .fix: return "checkmark.circle"
        case .tone: return "speaker.wave.2"
        case .title: return "textformat"
        case .outline: return "list.bullet.rectangle"
        case .continue: return "arrow.right"
        }
    }
}
