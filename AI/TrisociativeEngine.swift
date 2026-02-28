// CosmoOS/AI/TrisociativeEngine.swift
// Trisociative Collision Engine — finds maximally distant ideas in the
// knowledge graph and creates novel three-way connections via AI bridging.
// Engineered serendipity: discovers ideas that SHOULD be connected but
// never would be by normal search.

import Foundation
import Combine

@MainActor
class TrisociativeEngine: ObservableObject {
    static let shared = TrisociativeEngine()

    @Published var pendingCollisions: [CollisionResult] = []
    @Published var isGenerating = false

    private let researchService = ResearchService.shared
    private let atomRepo = AtomRepository.shared
    private let model = "anthropic/claude-haiku-4.5"

    /// Max API calls per generation cycle (cost control)
    private let dailyBudget = 3

    /// Last generation date (prevent multiple runs per day)
    private var lastGenerationDate: String? {
        get { UserDefaults.standard.string(forKey: "trisociative_last_generation_date") }
        set { UserDefaults.standard.set(newValue, forKey: "trisociative_last_generation_date") }
    }

    private init() {
        loadPersistedCollisions()
    }

    // MARK: - Generate Collisions

    /// Main generation pipeline: sample atoms, find distant pairs, bridge with AI.
    func generateCollisions() async -> [CollisionResult] {
        // Guard against duplicate daily runs
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if lastGenerationDate == String(today) && !pendingCollisions.isEmpty {
            return pendingCollisions
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            // Step 1: Fetch user-facing atoms with content
            let pool = try await fetchContentAtoms(maxCount: 200)
            guard pool.count >= 6 else {
                print("[TrisociativeEngine] Not enough atoms for collision (\(pool.count))")
                return []
            }

            // Step 2: Bounded sampling — random 50
            let sample = Array(pool.shuffled().prefix(50))

            // Step 3: Estimate pairwise text distance
            let distantPairs = findMostDistantPairs(in: sample, topN: 3)

            // Step 4: For each pair, find a third atom distant from both
            var triplets: [(Atom, Atom, Atom)] = []
            var usedUUIDs: Set<String> = []

            for (a, b) in distantPairs {
                guard triplets.count < dailyBudget else { break }

                // Diversity: no atom appears in more than 1 collision
                guard !usedUUIDs.contains(a.uuid),
                      !usedUUIDs.contains(b.uuid) else { continue }

                if let c = findThirdAtom(distantFrom: a, and: b, in: sample, excluding: usedUUIDs) {
                    triplets.append((a, b, c))
                    usedUUIDs.insert(a.uuid)
                    usedUUIDs.insert(b.uuid)
                    usedUUIDs.insert(c.uuid)
                }
            }

            // Step 5: Call AI for each triplet
            var results: [CollisionResult] = []
            for (a, b, c) in triplets {
                if let collision = await bridgeTriplet(a, b, c) {
                    results.append(collision)
                }
            }

            // Persist
            pendingCollisions = results
            lastGenerationDate = String(today)
            persistCollisions()

            return results
        } catch {
            print("[TrisociativeEngine] Generation failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Rate Collision

    func rateCollision(id: String, rating: CollisionResult.CollisionRating) async {
        guard let index = pendingCollisions.firstIndex(where: { $0.id == id }) else { return }
        pendingCollisions[index].userRating = rating
        persistCollisions()

        // Track in outcome tracker for learning
        await AgentOutcomeTracker.shared.trackSuggestionAcceptance(
            suggestion: pendingCollisions[index].bridgingConcept,
            accepted: rating == .positive,
            category: "trisociative_collision"
        )
    }

    // MARK: - Promote to Connection

    /// Create a .connection atom from a collision and link it to all 3 source atoms.
    func promoteToConnection(collision: CollisionResult) async {
        let links = [
            AtomLink(linkType: .related, uuid: collision.atomAUUID),
            AtomLink(linkType: .related, uuid: collision.atomBUUID),
            AtomLink(linkType: .related, uuid: collision.atomCUUID)
        ]

        let connectionAtom = Atom.new(
            type: .connection,
            title: collision.bridgingConcept,
            body: """
            \(collision.bridgingExplanation)

            ---
            Bridging: "\(collision.atomATitle)" + "\(collision.atomBTitle)" + "\(collision.atomCTitle)"
            Novelty: \(Int(collision.noveltyScore * 100))%
            """,
            links: links
        )

        do {
            let saved = try await atomRepo.create(connectionAtom)
            print("[TrisociativeEngine] Promoted collision to connection: \(saved.uuid)")

            // Add backlinks from each source atom to the new connection
            let connectionUUID = saved.uuid
            for sourceUUID in [collision.atomAUUID, collision.atomBUUID, collision.atomCUUID] {
                _ = try? await atomRepo.update(uuid: sourceUUID) { atom in
                    var existingLinks = atom.linksList
                    existingLinks.append(AtomLink(linkType: .related, uuid: connectionUUID))
                    atom.links = try? String(data: JSONEncoder().encode(existingLinks), encoding: .utf8)
                }
            }

            // Remove from pending
            pendingCollisions.removeAll { $0.id == collision.id }
            persistCollisions()

            // Post notification for canvas
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.collisionPromoted,
                object: nil,
                userInfo: ["connectionUUID": connectionUUID]
            )
        } catch {
            print("[TrisociativeEngine] Failed to promote: \(error.localizedDescription)")
        }
    }

    // MARK: - Dismiss

    func dismissCollision(id: String) {
        pendingCollisions.removeAll { $0.id == id }
        persistCollisions()
    }

    // MARK: - Private: Fetch Atoms

    private func fetchContentAtoms(maxCount: Int) async throws -> [Atom] {
        let types: [AtomType] = [.idea, .research, .connection, .content]
        var allAtoms: [Atom] = []

        for type in types {
            let atoms = try await atomRepo.fetchAll(type: type)
            allAtoms.append(contentsOf: atoms)
        }

        // Filter to atoms with meaningful content
        let filtered = allAtoms.filter { atom in
            let title = atom.title ?? ""
            let body = atom.body ?? ""
            return !title.isEmpty && (title.count + body.count) > 20
        }

        return Array(filtered.prefix(maxCount))
    }

    // MARK: - Private: Distance Estimation

    /// Simple word-overlap based distance metric. Lower overlap = more distant.
    private func textDistance(_ a: Atom, _ b: Atom) -> Double {
        let wordsA = tokenize(a)
        let wordsB = tokenize(b)

        guard !wordsA.isEmpty && !wordsB.isEmpty else { return 1.0 }

        let setA = Set(wordsA)
        let setB = Set(wordsB)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count

        guard union > 0 else { return 1.0 }

        // Jaccard distance: 1 - (intersection / union)
        return 1.0 - (Double(intersection) / Double(union))
    }

    private func tokenize(_ atom: Atom) -> [String] {
        let text = "\(atom.title ?? "") \(atom.body ?? "")"
        return text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 } // Skip short words
    }

    /// Find the top N most distant pairs by text overlap.
    private func findMostDistantPairs(in atoms: [Atom], topN: Int) -> [(Atom, Atom)] {
        var distances: [(Atom, Atom, Double)] = []

        for i in 0..<atoms.count {
            for j in (i+1)..<atoms.count {
                let dist = textDistance(atoms[i], atoms[j])
                distances.append((atoms[i], atoms[j], dist))
            }
        }

        // Sort by distance descending (most distant first)
        distances.sort { $0.2 > $1.2 }

        return distances.prefix(topN).map { ($0.0, $0.1) }
    }

    /// Find a third atom that is distant from both A and B, excluding already-used UUIDs.
    private func findThirdAtom(distantFrom a: Atom, and b: Atom, in pool: [Atom], excluding used: Set<String>) -> Atom? {
        let candidates = pool.filter { atom in
            return atom.uuid != a.uuid && atom.uuid != b.uuid && !used.contains(atom.uuid)
        }

        // Score each candidate by combined distance from A and B
        let scored = candidates.map { c -> (Atom, Double) in
            let dA = textDistance(a, c)
            let dB = textDistance(b, c)
            return (c, dA + dB) // Combined distance
        }

        // Return the most distant candidate
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    // MARK: - Private: AI Bridging

    private func bridgeTriplet(_ a: Atom, _ b: Atom, _ c: Atom) async -> CollisionResult? {
        let snippet = { (atom: Atom) -> String in
            let title = atom.title ?? "Untitled"
            let body = String((atom.body ?? "").prefix(200))
            return "\"\(title)\": \(body)"
        }

        let systemPrompt = """
        You are a creative connection engine. Given three seemingly unrelated ideas, find the \
        non-obvious bridging concept that connects all three. Think laterally — the best connections \
        are surprising yet immediately compelling once revealed.

        Respond ONLY with valid JSON:
        {"bridgingConcept": "short phrase", "explanation": "2-3 sentences explaining the connection", "noveltyScore": 0.7}
        noveltyScore: 0.0 = obvious connection, 1.0 = deeply surprising.
        """

        let userMessage = """
        Find the hidden connection between these three ideas:

        Idea A: \(snippet(a))

        Idea B: \(snippet(b))

        Idea C: \(snippet(c))
        """

        do {
            let response = try await researchService.generateWithCaching(
                systemBlocks: [(content: systemPrompt, cacheControl: false)],
                messages: [["role": "user", "content": userMessage]],
                model: model,
                maxTokens: 512,
                temperature: 0.7
            )

            return parseCollisionResponse(
                response,
                a: a, b: b, c: c
            )
        } catch {
            print("[TrisociativeEngine] AI bridging failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseCollisionResponse(_ response: String, a: Atom, b: Atom, c: Atom) -> CollisionResult? {
        // Extract JSON from response (may be wrapped in markdown code fences)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: "\n")
            let jsonLines = lines.filter { !$0.hasPrefix("```") }
            jsonString = jsonLines.joined(separator: "\n")
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let concept = json["bridgingConcept"] as? String,
              let explanation = json["explanation"] as? String else {
            print("[TrisociativeEngine] Failed to parse JSON: \(response.prefix(200))")
            return nil
        }

        let novelty = json["noveltyScore"] as? Double ?? 0.5

        return CollisionResult(
            atomAUUID: a.uuid,
            atomBUUID: b.uuid,
            atomCUUID: c.uuid,
            atomATitle: a.title ?? "Untitled",
            atomBTitle: b.title ?? "Untitled",
            atomCTitle: c.title ?? "Untitled",
            bridgingConcept: concept,
            bridgingExplanation: explanation,
            noveltyScore: novelty
        )
    }

    // MARK: - Persistence (UserDefaults)

    private func persistCollisions() {
        guard let data = try? JSONEncoder().encode(pendingCollisions) else { return }
        UserDefaults.standard.set(data, forKey: "trisociative_pending_collisions")
    }

    private func loadPersistedCollisions() {
        guard let data = UserDefaults.standard.data(forKey: "trisociative_pending_collisions"),
              let collisions = try? JSONDecoder().decode([CollisionResult].self, from: data) else {
            return
        }
        pendingCollisions = collisions
    }
}
