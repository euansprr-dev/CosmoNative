// CosmoOS/Editor/InlinePredictionEngine.swift
// Local LLM-powered word prediction with Tab-to-complete
// Leverages Apple Silicon for instant on-device inference

import Foundation
import SwiftUI
import Combine

/// Provides inline word/phrase predictions using the local LLM
/// Tab key accepts prediction, Escape dismisses
@MainActor
class InlinePredictionEngine: ObservableObject {
    // MARK: - Published State
    @Published var prediction: String? = nil
    @Published var isLoading = false
    @Published var ghostText: String = ""  // Rendered after cursor in tertiary color

    // MARK: - Configuration
    /// Minimum characters before triggering prediction
    private let minimumWordLength = 2
    /// Debounce delay in seconds
    private let debounceDelay: TimeInterval = 0.15
    /// Maximum tokens for prediction response
    private let maxPredictionTokens = 15

    // MARK: - Private State
    private let llm = LocalLLM.shared
    private var debounceTask: Task<Void, Never>?
    private var lastContext: String = ""
    private var lastCurrentWord: String = ""

    // MARK: - Prediction Request
    /// Request a prediction based on context and current partial word
    /// - Parameters:
    ///   - context: The full text context (last ~500 chars for efficiency)
    ///   - currentWord: The partial word being typed (characters since last space)
    func predictNext(context: String, currentWord: String) {
        // Don't predict for very short words
        guard currentWord.count >= minimumWordLength else {
            clearPrediction()
            return
        }

        // Skip if same request
        guard context != lastContext || currentWord != lastCurrentWord else {
            return
        }

        lastContext = context
        lastCurrentWord = currentWord

        // Cancel any pending prediction
        debounceTask?.cancel()

        // Debounce to avoid excessive LLM calls during fast typing
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            } catch {
                return  // Task was cancelled
            }

            guard !Task.isCancelled else { return }

            await performPrediction(context: context, currentWord: currentWord)
        }
    }

    // MARK: - Clear Prediction
    func clearPrediction() {
        debounceTask?.cancel()
        prediction = nil
        ghostText = ""
        isLoading = false
    }

    // MARK: - Accept Prediction
    /// Accept the current prediction - returns the text to insert
    func acceptPrediction() -> String? {
        guard let pred = prediction, !pred.isEmpty else { return nil }

        let accepted = pred
        clearPrediction()
        return accepted
    }

    // MARK: - Private: Perform Prediction
    private func performPrediction(context: String, currentWord: String) async {
        guard !Task.isCancelled else { return }

        isLoading = true

        // Build a focused prompt for word completion
        let trimmedContext = String(context.suffix(400))

        let prompt = """
        You are an intelligent text completion assistant. Complete the partial word based on context.

        Context: "\(trimmedContext)"
        Partial word: "\(currentWord)"

        Return ONLY the remaining characters to complete the word naturally. Do not include the partial word itself.
        If the word seems complete, return a likely next word preceded by a space.
        Keep it brief (1-3 words max). No explanation, just the completion.

        Completion:
        """

        let completion = await llm.generate(prompt: prompt, maxTokens: maxPredictionTokens)
        guard !Task.isCancelled else { return }

        // Clean up the completion
        var cleaned = completion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")

        // Remove any echo of the current word
        if cleaned.lowercased().hasPrefix(currentWord.lowercased()) {
            cleaned = String(cleaned.dropFirst(currentWord.count))
        }

        // Only show if we have a meaningful prediction
        if !cleaned.isEmpty && cleaned.count <= 50 {
            prediction = cleaned
            ghostText = cleaned
        } else {
            clearPrediction()
        }

        isLoading = false
    }
}

// MARK: - Prediction Overlay View
/// Ghost text overlay shown after the cursor position
struct PredictionOverlayView: View {
    let ghostText: String
    let cursorPosition: CGPoint
    let font: Font

    var body: some View {
        if !ghostText.isEmpty {
            Text(ghostText)
                .font(font)
                .foregroundColor(CosmoColors.textTertiary.opacity(0.6))
                .position(cursorPosition)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

// MARK: - Tab-to-Complete Hint View
/// Subtle hint shown when prediction is available
struct PredictionHintView: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: 4) {
                Text("Tab")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(CosmoColors.glassGrey.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))

                Text("to complete")
                    .font(.system(size: 10))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CosmoColors.softWhite.opacity(0.9), in: Capsule())
            .shadow(color: CosmoColors.glassGrey.opacity(0.3), radius: 4, y: 2)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Integration Extension for TextKit
extension TextKitEditorRepresentable {
    /// Configure text view to support inline predictions
    /// Called during text view setup
    func configurePredictionSupport(_ textView: NSTextView, predictionEngine: InlinePredictionEngine) {
        // The prediction engine observes text changes via the coordinator
        // Ghost text is rendered as an overlay in the SwiftUI layer
        // Tab key handling is done via keyboard event interception
    }
}
