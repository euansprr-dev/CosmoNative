// CosmoOS/AI/DistillationEngine.swift
// Progressive Distillation Engine - generates multi-level content representations
// February 2026 - Thinking Lab WP3

import SwiftUI
import Foundation

@MainActor
class DistillationEngine: ObservableObject {
    static let shared = DistillationEngine()

    /// Cache of generated layers keyed by atom UUID
    @Published var layersCache: [String: DistillationLayers] = [:]

    /// Track pending generations to avoid duplicates
    private var pendingGenerations: Set<String> = []
    private var generationTasks: [String: Task<Void, Never>] = [:]

    /// Debounce interval to handle rapid zooming
    private let debounceInterval: TimeInterval = 2.0

    /// Haiku model for cheap, fast generation
    private let model = "anthropic/claude-haiku-4.5"

    private init() {}

    // MARK: - Public API

    /// Ensure distillation layers exist for the given atom at the requested layer
    func ensureLayersExist(for atom: Atom, layer: DistillationLayer) {
        guard layer != .full else { return }
        let uuid = atom.uuid

        // Check if we already have the needed layer
        let existing = atom.distillationLayers ?? layersCache[uuid]
        if let existing = existing {
            switch layer {
            case .summary where existing.summary != nil: return
            case .essence where existing.essence != nil: return
            case .glyph where existing.glyph != nil: return
            default: break
            }
        }

        // Already pending
        guard !pendingGenerations.contains(uuid) else { return }

        // Cancel any existing debounce task for this atom
        generationTasks[uuid]?.cancel()

        // Debounced generation — cancel if called again within 2s (rapid zooming)
        let capturedAtom = atom
        generationTasks[uuid] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(2_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.generateMissingLayers(for: capturedAtom)
        }
    }

    /// Generate all missing distillation layers for an atom
    func generateMissingLayers(for atom: Atom) async {
        let uuid = atom.uuid
        guard !pendingGenerations.contains(uuid) else { return }
        pendingGenerations.insert(uuid)
        defer { pendingGenerations.remove(uuid) }

        // Get content to distill
        let content = extractContent(from: atom)
        guard !content.isEmpty, content.count > 20 else { return }

        // Load existing layers
        var layers = atom.distillationLayers ?? layersCache[uuid] ?? DistillationLayers()

        // Generate each missing layer (skip user-owned fields)
        if layers.summary == nil && !layers.userOwnedFlags.contains("summary") {
            layers.summary = await generateLayer(.summary, content: content)
        }
        if layers.essence == nil && !layers.userOwnedFlags.contains("essence") {
            layers.essence = await generateLayer(.essence, content: content)
        }
        if layers.glyph == nil && !layers.userOwnedFlags.contains("glyph") {
            layers.glyph = await generateLayer(.glyph, content: content)
        }

        layers.lastGeneratedAt = ISO8601DateFormatter().string(from: Date())

        // Update cache immediately for UI
        layersCache[uuid] = layers

        // Persist to atom via AtomRepository
        do {
            _ = try await AtomRepository.shared.update(uuid: uuid) { atom in
                atom.distillationLayers = layers
            }
        } catch {
            print("DistillationEngine: Failed to persist layers for \(uuid): \(error)")
        }

        // Clean up task reference
        generationTasks.removeValue(forKey: uuid)
    }

    /// Cancel pending generation for an atom
    func cancelPending(uuid: String) {
        generationTasks[uuid]?.cancel()
        generationTasks.removeValue(forKey: uuid)
        pendingGenerations.remove(uuid)
    }

    /// Get layers for an atom (from cache or atom data)
    func layers(for atom: Atom) -> DistillationLayers? {
        layersCache[atom.uuid] ?? atom.distillationLayers
    }

    /// Regenerate a specific layer (for user-triggered regeneration)
    func regenerateLayer(_ layer: DistillationLayer, for atom: Atom) async {
        let content = extractContent(from: atom)
        guard !content.isEmpty else { return }

        var layers = atom.distillationLayers ?? layersCache[atom.uuid] ?? DistillationLayers()

        if let generated = await generateLayer(layer, content: content) {
            switch layer {
            case .summary: layers.summary = generated
            case .essence: layers.essence = generated
            case .glyph: layers.glyph = generated
            case .full: break
            }
            layers.lastGeneratedAt = ISO8601DateFormatter().string(from: Date())
            layersCache[atom.uuid] = layers

            do {
                _ = try await AtomRepository.shared.update(uuid: atom.uuid) { atom in
                    atom.distillationLayers = layers
                }
            } catch {
                print("DistillationEngine: Failed to persist regenerated layer: \(error)")
            }
        }
    }

    // MARK: - Private

    private func extractContent(from atom: Atom) -> String {
        // Build content from available fields
        var parts: [String] = []
        if let title = atom.title, !title.isEmpty { parts.append(title) }
        if let body = atom.body, !body.isEmpty { parts.append(body) }

        // For connections, include structured mental model fields
        if atom.type == .connection {
            if let idea = atom.idea, !idea.isEmpty { parts.append(idea) }
            if let belief = atom.personalBelief, !belief.isEmpty { parts.append(belief) }
            if let example = atom.example, !example.isEmpty { parts.append(example) }
        }

        // For research, include transcript if available
        if atom.type == .research {
            if let transcript = atom.formattedTranscript { parts.append(transcript) }
            if let summary = atom.researchMetadata?.summary, !summary.isEmpty { parts.append(summary) }
        }

        return parts.joined(separator: "\n\n")
    }

    private func generateLayer(_ layer: DistillationLayer, content: String) async -> String? {
        let prompt: String
        let maxTokens: Int

        // Truncate content to avoid excessive token usage
        let truncatedContent = String(content.prefix(3000))

        switch layer {
        case .summary:
            prompt = "Summarize this in 3-5 sentences, preserving the key argument:\n\n\(truncatedContent)"
            maxTokens = 300
        case .essence:
            prompt = "Express the single core insight in one sentence:\n\n\(truncatedContent)"
            maxTokens = 100
        case .glyph:
            prompt = "Capture the core idea in exactly 3 words. Return ONLY 3 words, nothing else:\n\n\(truncatedContent)"
            maxTokens = 20
        case .full:
            return nil
        }

        do {
            let result = try await callOpenRouter(prompt: prompt, maxTokens: maxTokens)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("DistillationEngine: Generation failed for \(layer): \(error)")
            return nil
        }
    }

    private func callOpenRouter(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = APIKeys.openRouter, !apiKey.isEmpty else {
            throw DistillationError.noAPIKey
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CosmoOS/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CosmoOS", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a concise summarization assistant. Follow instructions exactly."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DistillationError.apiError(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DistillationError.invalidResponse
        }

        return content
    }
}

// MARK: - Errors

enum DistillationError: Error {
    case noAPIKey
    case apiError(String)
    case invalidResponse
}
