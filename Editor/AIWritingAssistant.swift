// CosmoOS/Editor/AIWritingAssistant.swift
// Local AI-powered writing assistance

import SwiftUI
import GRDB

@MainActor
class AIWritingAssistant: ObservableObject {
    @Published var isProcessing = false
    @Published var suggestions: [WritingSuggestion] = []
    @Published var error: String?

    private let localLLM = LocalLLM.shared

    // MARK: - Writing Actions
    func improve(text: String) async -> String? {
        return await process(
            prompt: "Improve this text while maintaining the original meaning. Make it clearer and more engaging:\n\n\(text)",
            action: "improve"
        )
    }

    func summarize(text: String) async -> String? {
        return await process(
            prompt: "Summarize this text in 2-3 sentences:\n\n\(text)",
            action: "summarize"
        )
    }

    func expand(text: String) async -> String? {
        return await process(
            prompt: "Expand on this text with more details and examples:\n\n\(text)",
            action: "expand"
        )
    }

    func fixGrammar(text: String) async -> String? {
        return await process(
            prompt: "Fix any grammar, spelling, or punctuation errors in this text:\n\n\(text)",
            action: "fix"
        )
    }

    func changeTone(text: String, tone: WritingTone) async -> String? {
        return await process(
            prompt: "Rewrite this text in a \(tone.rawValue) tone:\n\n\(text)",
            action: "tone"
        )
    }

    func generateTitle(from content: String) async -> String? {
        return await process(
            prompt: "Generate a concise, compelling title (max 8 words) for this content:\n\n\(content)",
            action: "title"
        )
    }

    func generateOutline(topic: String) async -> String? {
        return await process(
            prompt: "Generate a structured outline for writing about:\n\n\(topic)",
            action: "outline"
        )
    }

    func continueWriting(text: String) async -> String? {
        return await process(
            prompt: "Continue writing naturally from where this text leaves off:\n\n\(text)",
            action: "continue"
        )
    }

    // MARK: - Smart Suggestions
    func getSuggestions(for text: String) async {
        guard !text.isEmpty else {
            suggestions = []
            return
        }

        isProcessing = true

        // Generate contextual suggestions based on text
        var newSuggestions: [WritingSuggestion] = []

        // Check if text is short - suggest expansion
        if text.count < 100 {
            newSuggestions.append(WritingSuggestion(
                type: .expand,
                title: "Expand this",
                description: "Add more details and examples"
            ))
        }

        // Check if text is long - suggest summarization
        if text.count > 500 {
            newSuggestions.append(WritingSuggestion(
                type: .summarize,
                title: "Summarize",
                description: "Create a concise summary"
            ))
        }

        // Always offer improvements
        newSuggestions.append(WritingSuggestion(
            type: .improve,
            title: "Improve writing",
            description: "Make it clearer and more engaging"
        ))

        // Grammar check
        newSuggestions.append(WritingSuggestion(
            type: .fix,
            title: "Fix grammar",
            description: "Correct spelling and grammar"
        ))

        // Continue writing
        newSuggestions.append(WritingSuggestion(
            type: .continue,
            title: "Continue writing",
            description: "Let AI continue your thought"
        ))

        suggestions = newSuggestions
        isProcessing = false
    }

    // MARK: - Processing
    private func process(prompt: String, action: String) async -> String? {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // Use local LLM for processing
        guard localLLM.isReady else {
            error = "AI not ready"
            return nil
        }

        // For now, return mock results
        // In production, this would call LocalLLM.generate()

        switch action {
        case "title":
            return generateMockTitle(from: prompt)
        case "summarize":
            return generateMockSummary(from: prompt)
        case "fix":
            return prompt // Return original (would fix grammar)
        default:
            return prompt
        }
    }

    // MARK: - Mock Implementations
    private func generateMockTitle(from content: String) -> String {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(5)
        return words.joined(separator: " ")
    }

    private func generateMockSummary(from content: String) -> String {
        let sentences = content.components(separatedBy: ". ")
        return sentences.prefix(2).joined(separator: ". ") + "."
    }
}

// MARK: - Writing Suggestion
struct WritingSuggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let description: String

    enum SuggestionType {
        case improve, summarize, expand, fix, tone, title, outline, `continue`
    }
}

// MARK: - Writing Tone
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
    @State private var result: String?

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)

                Text("AI Assistant")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Actions
            if assistant.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(height: 60)
            } else if let result = result {
                // Show result
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(result)
                        .font(.system(size: 13))
                        .padding(12)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)

                    HStack {
                        Button("Apply") {
                            onApply(result)
                            isVisible = false
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Discard") {
                            self.result = nil
                        }
                    }
                }
            } else {
                // Show suggestions
                LazyVStack(spacing: 8) {
                    ForEach(assistant.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion) {
                            performAction(suggestion.type)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .onAppear {
            Task {
                await assistant.getSuggestions(for: selectedText)
            }
        }
    }

    private func performAction(_ type: WritingSuggestion.SuggestionType) {
        Task {
            switch type {
            case .improve:
                result = await assistant.improve(text: selectedText)
            case .summarize:
                result = await assistant.summarize(text: selectedText)
            case .expand:
                result = await assistant.expand(text: selectedText)
            case .fix:
                result = await assistant.fixGrammar(text: selectedText)
            case .continue:
                result = await assistant.continueWriting(text: selectedText)
            default:
                break
            }
        }
    }
}

// MARK: - Suggestion Row
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
