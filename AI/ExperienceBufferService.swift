// CosmoOS/AI/ExperienceBufferService.swift
// Stores past generation->edit pairs as retrievable few-shot examples per client.
// Prioritizes "surprising" examples (high edit distance) per SuRe research.
// February 2026

import Foundation

// MARK: - Experience Model

struct WritingExperience: Codable, Identifiable {
    let id: UUID
    let clientUUID: String?
    let contentFormat: String
    let generatedExcerpt: String  // first 500 chars
    let editedExcerpt: String     // first 500 chars
    let diffSummary: String
    let editDistance: Double       // 0.0-1.0
    let createdAt: Date

    init(
        id: UUID = UUID(),
        clientUUID: String? = nil,
        contentFormat: String,
        generatedExcerpt: String,
        editedExcerpt: String,
        diffSummary: String,
        editDistance: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clientUUID = clientUUID
        self.contentFormat = contentFormat
        self.generatedExcerpt = generatedExcerpt
        self.editedExcerpt = editedExcerpt
        self.diffSummary = diffSummary
        self.editDistance = editDistance
        self.createdAt = createdAt
    }
}

// MARK: - Experience Buffer Service

@MainActor
class ExperienceBufferService {
    static let shared = ExperienceBufferService()

    private let atomRepo = AtomRepository.shared

    /// Maximum number of experiences to store per client before pruning oldest
    private let maxExperiencesPerClient = 50

    private init() {}

    // MARK: - Store Experience

    /// Store a generation->edit experience (only if significant edits)
    func storeExperience(
        generated: String,
        edited: String,
        clientUUID: UUID?,
        contentFormat: String
    ) async {
        let editDistance = computeEditDistance(generated, edited)
        guard editDistance > 0.15 else { return }  // Only store significant edits

        // Generate diff summary
        let diffSummary = await generateDiffSummary(generated: generated, edited: edited)

        let experience = WritingExperience(
            clientUUID: clientUUID?.uuidString,
            contentFormat: contentFormat,
            generatedExcerpt: String(generated.prefix(500)),
            editedExcerpt: String(edited.prefix(500)),
            diffSummary: diffSummary,
            editDistance: editDistance
        )

        // Store as .agentLearning atom
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let structuredData = try encoder.encode(experience)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataDict: [String: Any] = [
                "lessonType": "experience",
                "clientUUID": clientUUID?.uuidString ?? "",
                "contentFormat": contentFormat,
                "editDistance": editDistance
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            let atom = Atom.new(
                type: .agentLearning,
                title: "Experience: \(contentFormat) (edit \(String(format: "%.0f%%", editDistance * 100)))",
                body: diffSummary,
                structured: structuredStr,
                metadata: metadataStr
            )
            _ = try await atomRepo.create(atom)

            // Prune old experiences if over limit
            await pruneOldExperiences(clientUUID: clientUUID)
        } catch {
            print("[ExperienceBufferService] Failed to store experience: \(error.localizedDescription)")
        }
    }

    // MARK: - Retrieve Experiences

    /// Retrieve relevant experiences for generation context
    func retrieveExperiences(
        clientUUID: UUID?,
        contentFormat: String,
        limit: Int = 3
    ) async -> [WritingExperience] {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var experiences: [WritingExperience] = []

            for atom in atoms {
                guard let meta = atom.metadataDict,
                      meta["lessonType"] as? String == "experience",
                      let structuredStr = atom.structured,
                      let data = structuredStr.data(using: .utf8),
                      let experience = try? decoder.decode(WritingExperience.self, from: data) else {
                    continue
                }

                // Filter by client: match specific client or universal (nil)
                if let clientUUID = clientUUID {
                    guard experience.clientUUID == nil || experience.clientUUID == clientUUID.uuidString else {
                        continue
                    }
                }

                // Prefer matching content format, but include others as fallback
                experiences.append(experience)
            }

            // Sort: matching format first, then by editDistance desc (prioritize surprising)
            let sorted = experiences.sorted { a, b in
                let aFormatMatch = a.contentFormat == contentFormat
                let bFormatMatch = b.contentFormat == contentFormat
                if aFormatMatch != bFormatMatch {
                    return aFormatMatch
                }
                return a.editDistance > b.editDistance
            }

            return Array(sorted.prefix(limit))
        } catch {
            print("[ExperienceBufferService] Failed to retrieve experiences: \(error.localizedDescription)")
            return []
        }
    }

    /// Format experiences as few-shot examples for AI prompt injection
    func formatExperiencesForPrompt(
        clientUUID: UUID?,
        contentFormat: String
    ) async -> String {
        let experiences = await retrieveExperiences(
            clientUUID: clientUUID,
            contentFormat: contentFormat,
            limit: 3
        )
        guard !experiences.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("=== PAST EDITING EXAMPLES ===")
        lines.append("The user previously made these edits to AI-generated content.")
        lines.append("Learn from these patterns to generate content closer to their preferences:")
        lines.append("")

        for (i, exp) in experiences.enumerated() {
            lines.append("--- Example \(i + 1) (\(exp.contentFormat)) ---")
            lines.append("AI Generated: \(exp.generatedExcerpt)")
            lines.append("User Edited To: \(exp.editedExcerpt)")
            lines.append("Key Change: \(exp.diffSummary)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    func computeEditDistance(_ a: String, _ b: String) -> Double {
        let wordsA = a.lowercased().split(separator: " ")
        let wordsB = b.lowercased().split(separator: " ")
        let maxLen = max(wordsA.count, wordsB.count)
        guard maxLen > 0 else { return 0 }
        let setA = Set(wordsA)
        let setB = Set(wordsB)
        return Double(setA.symmetricDifference(setB).count) / Double(maxLen)
    }

    private func generateDiffSummary(generated: String, edited: String) async -> String {
        let prompt = """
        In 1 sentence, what did the user change between these two versions? \
        Focus on style, structure, or content changes, not typo fixes.

        AI Version (first 500 chars):
        \(String(generated.prefix(500)))

        User's Edit (first 500 chars):
        \(String(edited.prefix(500)))

        Respond with ONLY one sentence describing the key change.
        """

        do {
            let response = try await ResearchService.shared.analyze(
                prompt: prompt,
                tier: .router,
                maxTokens: 100
            )
            let trimmed = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? "User edited the content" : trimmed
        } catch {
            return "User edited the content"
        }
    }

    private func pruneOldExperiences(clientUUID: UUID?) async {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            let clientStr = clientUUID?.uuidString ?? ""

            let experienceAtoms = atoms.filter { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonType"] as? String == "experience"
                    && (meta["clientUUID"] as? String ?? "") == clientStr
            }

            // Only prune if over the limit
            guard experienceAtoms.count > maxExperiencesPerClient else { return }

            // Atoms are already sorted by updatedAt desc from fetchAll — delete the oldest
            let toDelete = experienceAtoms.suffix(from: maxExperiencesPerClient)
            for var atom in toDelete {
                atom.isDeleted = true
                _ = try await atomRepo.update(atom)
            }
        } catch {
            print("[ExperienceBufferService] Pruning failed: \(error.localizedDescription)")
        }
    }
}
