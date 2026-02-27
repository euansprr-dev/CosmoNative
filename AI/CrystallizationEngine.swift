// CosmoOS/AI/CrystallizationEngine.swift
// Knowledge Crystallization Engine - computes how deeply knowledge has been processed
// February 2026 - Thinking Lab WP1

import SwiftUI
import Foundation

// MARK: - CrystallizationEngine

/// Computes and caches crystallization levels for atoms on the canvas.
/// Levels progress: raw -> highlighted -> distilled -> connected -> crystallized
/// based on annotation count, graph edges, and downstream synthesis references.
@MainActor
class CrystallizationEngine: ObservableObject {
    static let shared = CrystallizationEngine()

    /// Cached levels keyed by atom UUID
    @Published var levels: [String: CrystallizationLevel] = [:]

    private let graphEngine = GraphQueryEngine()

    private init() {}

    // MARK: - Public API

    /// Compute the crystallization level for a single atom
    func computeLevel(for atom: Atom) async -> CrystallizationLevel {
        // Check for user override first
        if let override = atom.crystallizationMetadata?.userOverride,
           let overrideLevel = CrystallizationLevel(rawValue: override) {
            levels[atom.uuid] = overrideLevel
            return overrideLevel
        }

        let annotationCount = countAnnotations(for: atom)
        let linkCount = atom.linksList.count
        let edgeCount = await countEdges(for: atom.uuid)
        let hasDownstreamSynthesis = await checkDownstreamSynthesis(for: atom.uuid)

        let level = determineLevel(
            annotationCount: annotationCount,
            linkCount: linkCount,
            edgeCount: edgeCount,
            hasDownstreamSynthesis: hasDownstreamSynthesis,
            hasSummary: atom.researchMetadata?.summary != nil && !(atom.researchMetadata?.summary?.isEmpty ?? true),
            hasPersonalNotes: atom.researchMetadata?.personalNotes != nil && !(atom.researchMetadata?.personalNotes?.isEmpty ?? true)
        )

        levels[atom.uuid] = level
        return level
    }

    /// Batch compute levels for multiple atoms
    func batchCompute(atoms: [Atom]) async {
        for atom in atoms {
            _ = await computeLevel(for: atom)
        }
    }

    /// Invalidate cached level for an atom (e.g. after annotation or link change)
    func invalidate(uuid: String) {
        levels.removeValue(forKey: uuid)
    }

    // MARK: - Level Determination

    private func determineLevel(
        annotationCount: Int,
        linkCount: Int,
        edgeCount: Int,
        hasDownstreamSynthesis: Bool,
        hasSummary: Bool,
        hasPersonalNotes: Bool
    ) -> CrystallizationLevel {
        // Crystallized: referenced by a connection or content atom (synthesis output)
        if hasDownstreamSynthesis {
            return .crystallized
        }

        // Connected: 3+ graph edges — well-integrated into the knowledge graph
        if edgeCount >= 3 {
            return .connected
        }

        // Distilled: 3+ annotations, or has a user-written summary/notes
        if annotationCount >= 3 || hasSummary || hasPersonalNotes {
            return .distilled
        }

        // Highlighted: at least 1 annotation or 1 link
        if annotationCount >= 1 || linkCount >= 1 {
            return .highlighted
        }

        // Raw: untouched
        return .raw
    }

    // MARK: - Data Queries

    /// Count annotations stored in the atom's structured JSON (ResearchFocusModeState format)
    private func countAnnotations(for atom: Atom) -> Int {
        guard let structured = atom.structured,
              let data = structured.data(using: .utf8) else { return 0 }

        // Try to decode transcript sections which contain annotations
        if let sections = try? JSONDecoder().decode([TranscriptSectionMinimal].self, from: data) {
            return sections.reduce(0) { $0 + $1.annotations.count }
        }

        // Fallback: check for highlights array in a wrapper
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let highlights = dict["highlights"] as? [[String: Any]] {
                return highlights.count
            }
            if let annotations = dict["annotations"] as? [[String: Any]] {
                return annotations.count
            }
        }

        return 0
    }

    /// Count graph edges for an atom
    private func countEdges(for uuid: String) async -> Int {
        do {
            let edges = try await graphEngine.getEdges(for: uuid)
            return edges.count
        } catch {
            return 0
        }
    }

    /// Check if any connection or content atom references this atom (downstream synthesis)
    private func checkDownstreamSynthesis(for uuid: String) async -> Bool {
        do {
            let neighbors = try await graphEngine.getNeighbors(of: uuid, direction: .incoming)
            return neighbors.contains { neighbor in
                let nodeType = neighbor.node.atomType
                return nodeType == AtomType.connection.rawValue || nodeType == AtomType.content.rawValue
            }
        } catch {
            return false
        }
    }
}

// MARK: - Minimal Decodable for Annotation Counting

/// Lightweight struct for counting annotations without importing full ResearchFocusModeState types
private struct TranscriptSectionMinimal: Decodable {
    let annotations: [AnnotationMinimal]

    struct AnnotationMinimal: Decodable {
        let id: String?
    }

    enum CodingKeys: String, CodingKey {
        case annotations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.annotations = (try? container.decode([AnnotationMinimal].self, forKey: .annotations)) ?? []
    }
}
