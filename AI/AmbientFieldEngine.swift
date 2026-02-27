// CosmoOS/AI/AmbientFieldEngine.swift
// Ambient Knowledge Field — surfaces related knowledge when a block is focused
// February 2026

import Foundation
import SwiftUI

// MARK: - Ambient Result

struct AmbientResult: Identifiable {
    let id: String  // atom UUID
    let atomType: EntityType
    let title: String
    let preview: String
    let relevanceReason: String  // "Semantic match", "2-hop via [X]", "Same project"
    let score: Double
}

// MARK: - Ambient Field Engine

/// Surfaces related knowledge from the graph when the user selects/focuses a block.
/// Debounces queries to avoid thrashing and deduplicates against already-connected atoms.
@MainActor
class AmbientFieldEngine: ObservableObject {
    @Published var ambientResults: [AmbientResult] = []
    @Published var isLoading = false

    private var queryTask: Task<Void, Never>?
    private var dismissedUUIDs: Set<String> = []
    private var lastFocusUUID: String?

    private let graphEngine = GraphQueryEngine()
    private let debounceInterval: TimeInterval = 1.5

    // MARK: - Public API

    /// Update the ambient context when focus changes.
    /// Debounces by 1.5s to avoid thrashing during rapid selection changes.
    func updateContext(focusAtomUUID: String, currentText: String) {
        // Skip if same atom is already focused
        guard focusAtomUUID != lastFocusUUID else { return }
        lastFocusUUID = focusAtomUUID

        // Cancel previous query
        queryTask?.cancel()

        isLoading = true

        queryTask = Task { @MainActor in
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await executeQuery(focusAtomUUID: focusAtomUUID, currentText: currentText)
        }
    }

    /// Dismiss a result so it won't appear again this session
    func dismiss(uuid: String) {
        dismissedUUIDs.insert(uuid)
        ambientResults.removeAll { $0.id == uuid }
    }

    /// Pull a result to the canvas — posts notification for CanvasView to handle
    func pullToCanvas(result: AmbientResult, sourceBlockUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.pullAmbientToCanvas,
            object: nil,
            userInfo: [
                "atomUUID": result.id,
                "sourceBlockUUID": sourceBlockUUID
            ]
        )
    }

    /// Clear results when no block is selected
    func clearContext() {
        queryTask?.cancel()
        lastFocusUUID = nil
        ambientResults = []
        isLoading = false
    }

    // MARK: - Query Pipeline

    private func executeQuery(focusAtomUUID: String, currentText: String) async {
        defer { isLoading = false }

        // Get the focus atom's existing links to exclude already-connected atoms
        let connectedUUIDs: Set<String>
        if let focusAtom = try? await AtomRepository.shared.fetch(uuid: focusAtomUUID) {
            connectedUUIDs = Set(focusAtom.linksList.map { $0.uuid })
        } else {
            connectedUUIDs = []
        }

        var candidateMap: [String: AmbientResult] = [:]

        // Pipeline 1: Hybrid search using the block's text content
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let searchResults = try await HybridSearchEngine.shared.search(
                    query: currentText,
                    limit: 15
                )

                for result in searchResults {
                    guard let uuid = result.entityUUID,
                          uuid != focusAtomUUID,
                          !connectedUUIDs.contains(uuid),
                          !dismissedUUIDs.contains(uuid) else { continue }

                    candidateMap[uuid] = AmbientResult(
                        id: uuid,
                        atomType: result.entityType,
                        title: result.title,
                        preview: result.preview,
                        relevanceReason: result.matchReason.rawValue,
                        score: result.combinedScore
                    )
                }
            } catch {
                print("AmbientField: Search failed: \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }

        // Pipeline 2: Graph neighbors (1-hop)
        do {
            let neighbors = try await graphEngine.getNeighbors(of: focusAtomUUID, limit: 10)

            for neighbor in neighbors {
                let uuid = neighbor.node.atomUUID
                guard uuid != focusAtomUUID,
                      !connectedUUIDs.contains(uuid),
                      !dismissedUUIDs.contains(uuid) else { continue }

                let atomType = EntityType(rawValue: neighbor.node.atomType) ?? .idea

                // If already in candidates, boost score
                if var existing = candidateMap[uuid] {
                    existing = AmbientResult(
                        id: existing.id,
                        atomType: existing.atomType,
                        title: existing.title,
                        preview: existing.preview,
                        relevanceReason: "Graph + Semantic match",
                        score: existing.score + neighbor.weight * 0.3
                    )
                    candidateMap[uuid] = existing
                } else {
                    // Fetch atom for title
                    let atom = try? await AtomRepository.shared.fetch(uuid: uuid)
                    let title = atom?.title ?? "Untitled"
                    let preview = String((atom?.body ?? "").prefix(200))
                    candidateMap[uuid] = AmbientResult(
                        id: uuid,
                        atomType: atomType,
                        title: title,
                        preview: preview,
                        relevanceReason: "Graph neighbor",
                        score: neighbor.weight
                    )
                }
            }
        } catch {
            print("AmbientField: Graph query failed: \(error.localizedDescription)")
        }

        guard !Task.isCancelled else { return }

        // Sort by score, take top 8
        let sorted = candidateMap.values
            .sorted { $0.score > $1.score }
            .prefix(8)

        ambientResults = Array(sorted)
    }
}
