// CosmoOS/Data/Repositories/CodexRepository.swift
// In-memory cached repository for Content Physics Codex elements and walkthroughs.
// Loads once from GRDB atoms, provides O(1) lookup by canonical name.

import Foundation
import os

@MainActor @Observable
final class CodexRepository {
    static let shared = CodexRepository()

    private(set) var isLoaded = false
    private(set) var elementCount = 0

    private var elementCache: [String: (atom: Atom, element: CodexElement)] = [:]
    private var walkthroughCache: [String: (atom: Atom, walkthrough: CodexWalkthrough)] = [:]

    private let logger = Logger(subsystem: "com.cosmo.codex", category: "CodexRepository")

    private init() {}

    // MARK: - Loading

    func loadIfNeeded() async throws {
        guard !isLoaded else { return }
        try await reload()
    }

    func reload() async throws {
        let elementAtoms = try await AtomRepository.shared.fetchAll(type: .codexElement)
        let walkthroughAtoms = try await AtomRepository.shared.fetchAll(type: .codexWalkthrough)

        var newElementCache: [String: (atom: Atom, element: CodexElement)] = [:]
        for atom in elementAtoms {
            guard let structured = atom.structured,
                  let data = structured.data(using: .utf8) else { continue }
            do {
                let element = try JSONDecoder().decode(CodexElement.self, from: data)
                newElementCache[element.canonicalName.lowercased()] = (atom, element)
            } catch {
                logger.warning("Failed to decode CodexElement from atom \(atom.uuid): \(error.localizedDescription)")
            }
        }

        var newWalkthroughCache: [String: (atom: Atom, walkthrough: CodexWalkthrough)] = [:]
        for atom in walkthroughAtoms {
            guard let structured = atom.structured,
                  let data = structured.data(using: .utf8) else { continue }
            do {
                let walkthrough = try JSONDecoder().decode(CodexWalkthrough.self, from: data)
                newWalkthroughCache[walkthrough.postReference] = (atom, walkthrough)
            } catch {
                logger.warning("Failed to decode CodexWalkthrough from atom \(atom.uuid): \(error.localizedDescription)")
            }
        }

        elementCache = newElementCache
        walkthroughCache = newWalkthroughCache
        elementCount = newElementCache.count
        isLoaded = true

        logger.info("Codex loaded: \(newElementCache.count) elements, \(newWalkthroughCache.count) walkthroughs")
    }

    // MARK: - Element Queries

    func fetchAllElements() async throws -> [(Atom, CodexElement)] {
        try await loadIfNeeded()
        return elementCache.values.map { ($0.atom, $0.element) }
    }

    func fetchElements(category: CodexElementCategory) async throws -> [(Atom, CodexElement)] {
        try await loadIfNeeded()
        return elementCache.values
            .filter { $0.element.category == category }
            .map { ($0.atom, $0.element) }
    }

    func fetchElement(canonicalName: String) async throws -> (Atom, CodexElement)? {
        try await loadIfNeeded()
        guard let entry = elementCache[canonicalName.lowercased()] else { return nil }
        return (entry.atom, entry.element)
    }

    func fetchElementsForNames(_ names: [String]) async throws -> [(Atom, CodexElement)] {
        try await loadIfNeeded()
        return names.compactMap { name in
            guard let entry = elementCache[name.lowercased()] else { return nil }
            return (entry.atom, entry.element)
        }
    }

    func arcShapes() async throws -> [(Atom, CodexElement)] {
        try await fetchElements(category: .arcShape)
    }

    // MARK: - Walkthrough Queries

    func fetchAllWalkthroughs() async throws -> [(Atom, CodexWalkthrough)] {
        try await loadIfNeeded()
        return walkthroughCache.values.map { ($0.atom, $0.walkthrough) }
    }

    func fetchWalkthrough(postReference: String) async throws -> (Atom, CodexWalkthrough)? {
        try await loadIfNeeded()
        guard let entry = walkthroughCache[postReference] else { return nil }
        return (entry.atom, entry.walkthrough)
    }

    // MARK: - Search

    func searchElements(query: String) async throws -> [(Atom, CodexElement)] {
        try await loadIfNeeded()
        let lowered = query.lowercased()
        return elementCache.values
            .filter { entry in
                entry.element.canonicalName.lowercased().contains(lowered)
                || entry.element.definition.lowercased().contains(lowered)
                || entry.element.variants.contains { $0.lowercased().contains(lowered) }
            }
            .map { ($0.atom, $0.element) }
    }

    // MARK: - Status

    func isCodexImported() async -> Bool {
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .codexElement)
            return !atoms.isEmpty
        } catch {
            return false
        }
    }
}
