// CosmoOS/AI/BeatPatternService.swift
// Beat normalization and pattern intelligence for swipe file analysis
// Manages canonical beat vocabulary and structural fingerprinting

import Foundation
import SwiftUI
import GRDB

// MARK: - Data Models

struct CanonicalBeat: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String
    var function: String
    var originalVariants: [String]
    var usageCount: Int

    init(label: String, function: String, originalVariants: [String] = [], usageCount: Int = 0) {
        self.id = UUID()
        self.label = label
        self.function = function
        self.originalVariants = originalVariants
        self.usageCount = usageCount
    }
}

struct BeatPattern: Identifiable, Sendable {
    let id: UUID
    let fingerprint: String
    let beatSequence: [String]
    var frequency: Int
    var avgHookScore: Double
    var swipeUUIDs: [UUID]

    init(fingerprint: String, beatSequence: [String], frequency: Int = 1, avgHookScore: Double = 0, swipeUUIDs: [UUID] = []) {
        self.id = UUID()
        self.fingerprint = fingerprint
        self.beatSequence = beatSequence
        self.frequency = frequency
        self.avgHookScore = avgHookScore
        self.swipeUUIDs = swipeUUIDs
    }
}

// MARK: - BeatPatternService

@MainActor
class BeatPatternService: ObservableObject {
    static let shared = BeatPatternService()

    @Published var vocabulary: [CanonicalBeat] = []
    @Published var isLoaded = false

    private let database = CosmoDatabase.shared

    private init() {
        loadVocabulary()
    }

    // MARK: - Vocabulary Persistence

    private var vocabularyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cosmoDir = appSupport.appendingPathComponent("CosmoOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cosmoDir, withIntermediateDirectories: true)
        return cosmoDir.appendingPathComponent("canonical_beats.json")
    }

    func loadVocabulary() {
        if let data = try? Data(contentsOf: vocabularyFileURL),
           let beats = try? JSONDecoder().decode([CanonicalBeat].self, from: data),
           !beats.isEmpty {
            vocabulary = beats
        } else {
            vocabulary = Self.defaultVocabulary
            saveVocabulary()
        }
        isLoaded = true
    }

    func saveVocabulary() {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        try? data.write(to: vocabularyFileURL, options: .atomic)
    }

    // MARK: - Beat Normalization

    /// Map raw beat labels from AI analysis to canonical vocabulary using fuzzy string matching
    func normalizeBeats(rawLabels: [String]) -> [String] {
        rawLabels.map { raw in
            bestMatch(for: raw) ?? "Uncategorized: \(raw)"
        }
    }

    /// Find the best canonical beat match for a raw label
    private func bestMatch(for rawLabel: String) -> String? {
        let normalized = rawLabel.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Exact match (case-insensitive)
        if let exact = vocabulary.first(where: { $0.label.lowercased() == normalized }) {
            return exact.label
        }

        // Check known variants
        if let variant = vocabulary.first(where: { beat in
            beat.originalVariants.contains(where: { $0.lowercased() == normalized })
        }) {
            return variant.label
        }

        // Fuzzy match: find best similarity score
        var bestScore: Double = 0
        var bestLabel: String?

        for beat in vocabulary {
            let score = max(
                stringSimilarity(normalized, beat.label.lowercased()),
                stringSimilarity(normalized, beat.function.lowercased())
            )
            // Also check against known variants
            let variantScore = beat.originalVariants
                .map { stringSimilarity(normalized, $0.lowercased()) }
                .max() ?? 0
            let finalScore = max(score, variantScore)

            if finalScore > bestScore {
                bestScore = finalScore
                bestLabel = beat.label
            }
        }

        // Require at least 55% similarity
        if bestScore >= 0.55, let label = bestLabel {
            return label
        }

        return nil
    }

    /// Jaccard + substring similarity between two strings
    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        // Substring containment bonus
        if a.contains(b) || b.contains(a) {
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            return 0.6 + 0.4 * (Double(shorter) / Double(longer))
        }

        // Bigram Jaccard similarity
        let bigramsA = Set(bigrams(a))
        let bigramsB = Set(bigrams(b))
        guard !bigramsA.isEmpty || !bigramsB.isEmpty else { return 0 }
        let intersection = bigramsA.intersection(bigramsB).count
        let union = bigramsA.union(bigramsB).count
        return Double(intersection) / Double(union)
    }

    private func bigrams(_ s: String) -> [String] {
        let chars = Array(s)
        guard chars.count >= 2 else { return [s] }
        return (0..<chars.count - 1).map { String(chars[$0...$0 + 1]) }
    }

    // MARK: - Structural Fingerprint

    /// Compute a structural fingerprint from normalized beat labels
    func computeStructuralFingerprint(normalizedBeats: [String]) -> String {
        normalizedBeats
            .map { label in
                // Strip "Uncategorized: " prefix for fingerprint
                if label.hasPrefix("Uncategorized: ") {
                    return "Uncategorized"
                }
                return label
            }
            .joined(separator: ">")
    }

    // MARK: - Pattern Queries

    /// Find the most common beat patterns across all swipes
    func findTopPatterns(format: String? = nil, niche: String? = nil, limit: Int = 10) async -> [BeatPattern] {
        do {
            let swipes = try await fetchSwipeAtoms()

            // Group by structural fingerprint
            var patternGroups: [String: (beats: [String], hookScores: [Double], uuids: [UUID])] = [:]

            for swipe in swipes {
                guard let analysis = swipe.swipeAnalysis else { continue }

                // Filter by format if specified
                if let format = format, let swipeFormat = analysis.swipeContentFormat?.rawValue, swipeFormat != format {
                    continue
                }
                // Filter by niche if specified
                if let niche = niche, let swipeNiche = analysis.niche, swipeNiche != niche {
                    continue
                }

                guard let fp = analysis.beatFingerprint, !fp.isEmpty else { continue }

                let beats = fp.components(separatedBy: ">")
                let hookScore = analysis.hookScore ?? 0

                if patternGroups[fp] != nil {
                    patternGroups[fp]?.hookScores.append(hookScore)
                    if let uuid = UUID(uuidString: swipe.uuid) {
                        patternGroups[fp]?.uuids.append(uuid)
                    }
                } else {
                    var uuids: [UUID] = []
                    if let uuid = UUID(uuidString: swipe.uuid) {
                        uuids.append(uuid)
                    }
                    patternGroups[fp] = (beats: beats, hookScores: [hookScore], uuids: uuids)
                }
            }

            // Convert to BeatPattern array
            var patterns = patternGroups.map { fp, group in
                let avgScore = group.hookScores.isEmpty ? 0 : group.hookScores.reduce(0, +) / Double(group.hookScores.count)
                return BeatPattern(
                    fingerprint: fp,
                    beatSequence: group.beats,
                    frequency: group.uuids.count,
                    avgHookScore: avgScore,
                    swipeUUIDs: group.uuids
                )
            }

            // Sort by frequency descending, then by hook score
            patterns.sort { a, b in
                if a.frequency != b.frequency { return a.frequency > b.frequency }
                return a.avgHookScore > b.avgHookScore
            }

            return Array(patterns.prefix(limit))
        } catch {
            print("BeatPatternService: findTopPatterns failed: \(error)")
            return []
        }
    }

    /// Find patterns with 70%+ sequence similarity to a given fingerprint
    func findSimilarPatterns(fingerprint: String, threshold: Double = 0.7) async -> [BeatPattern] {
        let targetBeats = fingerprint.components(separatedBy: ">")
        let allPatterns = await findTopPatterns(limit: 100)

        return allPatterns.filter { pattern in
            let similarity = sequenceSimilarity(targetBeats, pattern.beatSequence)
            return similarity >= threshold && pattern.fingerprint != fingerprint
        }
    }

    /// Get the beat pattern for a specific swipe
    func getPatternForSwipe(swipeUUID: UUID) async -> BeatPattern? {
        do {
            let atom = try await fetchAtom(uuid: swipeUUID.uuidString)
            guard let analysis = atom?.swipeAnalysis,
                  let fp = analysis.beatFingerprint,
                  !fp.isEmpty else { return nil }

            let beats = fp.components(separatedBy: ">")
            return BeatPattern(
                fingerprint: fp,
                beatSequence: beats,
                frequency: 1,
                avgHookScore: analysis.hookScore ?? 0,
                swipeUUIDs: [swipeUUID]
            )
        } catch {
            print("BeatPatternService: getPatternForSwipe failed: \(error)")
            return nil
        }
    }

    /// Suggest beat patterns for an idea based on its content
    func suggestPatternForIdea(ideaAtom: Atom) async -> [BeatPattern] {
        let topPatterns = await findTopPatterns(limit: 20)
        guard !topPatterns.isEmpty else { return [] }

        let ideaText = (ideaAtom.body ?? "") + " " + (ideaAtom.title ?? "")
        guard !ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Return top 3 by hook score if no idea text
            return Array(topPatterns.sorted { $0.avgHookScore > $1.avgHookScore }.prefix(3))
        }

        // Use AI to suggest best matching patterns
        do {
            let patternsDescription = topPatterns.prefix(10).map { pattern in
                "[\(pattern.fingerprint)] (used \(pattern.frequency)x, avg score: \(String(format: "%.1f", pattern.avgHookScore)))"
            }.joined(separator: "\n")

            let prompt = """
            Given this content idea:
            "\(ideaText.prefix(500))"

            Which of these proven beat patterns would work best? Return the top 3 fingerprints as a JSON array of strings.

            Available patterns:
            \(patternsDescription)

            Return ONLY a JSON array like: ["BoldClaim>StepByStepProof>SocialProofNumbers>UrgencyCTA", ...]
            """

            let response = try await ResearchService.shared.analyze(prompt: prompt, tier: .router)

            // Parse response
            var jsonStr = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr.hasPrefix("```") {
                if let firstNewline = jsonStr.firstIndex(of: "\n") {
                    jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
                }
                if jsonStr.hasSuffix("```") {
                    jsonStr = String(jsonStr.dropLast(3))
                }
                jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let data = jsonStr.data(using: .utf8),
               let fingerprints = try? JSONDecoder().decode([String].self, from: data) {
                return fingerprints.compactMap { fp in
                    topPatterns.first(where: { $0.fingerprint == fp })
                }
            }
        } catch {
            print("BeatPatternService: suggestPatternForIdea failed: \(error)")
        }

        // Fallback: return top 3 by score
        return Array(topPatterns.sorted { $0.avgHookScore > $1.avgHookScore }.prefix(3))
    }

    // MARK: - Vocabulary Management

    func mergeBeats(source: String, target: String) {
        guard let sourceIdx = vocabulary.firstIndex(where: { $0.label == source }),
              let targetIdx = vocabulary.firstIndex(where: { $0.label == target }) else { return }

        // Transfer variants and usage count
        vocabulary[targetIdx].originalVariants.append(source)
        vocabulary[targetIdx].originalVariants.append(contentsOf: vocabulary[sourceIdx].originalVariants)
        vocabulary[targetIdx].usageCount += vocabulary[sourceIdx].usageCount

        // Remove source
        vocabulary.remove(at: sourceIdx)
        saveVocabulary()
    }

    func addBeat(_ beat: CanonicalBeat) {
        guard !vocabulary.contains(where: { $0.label == beat.label }) else { return }
        vocabulary.append(beat)
        saveVocabulary()
    }

    func deleteBeat(label: String) {
        vocabulary.removeAll { $0.label == label }
        saveVocabulary()
    }

    /// Find beat labels appearing 3+ times in swipes that are not in the canonical vocabulary
    func getUncategorizedBeats() async -> [(label: String, count: Int)] {
        do {
            let swipes = try await fetchSwipeAtoms()
            var uncategorizedCounts: [String: Int] = [:]
            let canonicalLabels = Set(vocabulary.map { $0.label })

            for swipe in swipes {
                guard let analysis = swipe.swipeAnalysis,
                      let fp = analysis.beatFingerprint else { continue }

                for beat in fp.components(separatedBy: ">") {
                    if beat.hasPrefix("Uncategorized") || !canonicalLabels.contains(beat) {
                        let cleanLabel = beat.replacingOccurrences(of: "Uncategorized: ", with: "")
                        uncategorizedCounts[cleanLabel, default: 0] += 1
                    }
                }
            }

            return uncategorizedCounts
                .filter { $0.value >= 3 }
                .map { (label: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        } catch {
            return []
        }
    }

    /// Increment usage count for beats in a sequence
    func trackUsage(beats: [String]) {
        for beat in beats {
            if let idx = vocabulary.firstIndex(where: { $0.label == beat }) {
                vocabulary[idx].usageCount += 1
            }
        }
        saveVocabulary()
    }

    // MARK: - Migration

    /// Batch-normalize existing swipes that lack beat fingerprints
    func migrateExistingSwipes() async {
        do {
            let swipes = try await fetchSwipeAtoms()
            let unmigrated = swipes.filter { atom in
                guard let analysis = atom.swipeAnalysis else { return false }
                return analysis.beatFingerprint == nil && analysis.sections != nil
            }

            guard !unmigrated.isEmpty else { return }

            // Process in batches of 20
            for batch in stride(from: 0, to: unmigrated.count, by: 20) {
                let end = min(batch + 20, unmigrated.count)
                let batchAtoms = Array(unmigrated[batch..<end])

                let batchDescriptions = batchAtoms.compactMap { atom -> String? in
                    guard let sections = atom.swipeAnalysis?.sections else { return nil }
                    let labels = sections.map { $0.label }
                    return "[\(atom.uuid)]: \(labels.joined(separator: ", "))"
                }.joined(separator: "\n")

                let canonicalList = vocabulary.map { $0.label }.joined(separator: ", ")

                let prompt = """
                Map these section labels to canonical beat types. For each swipe UUID, return the normalized beat sequence.

                Canonical beats: \(canonicalList)

                Swipes:
                \(batchDescriptions)

                Return JSON: {"results": [{"uuid": "...", "beats": ["BoldClaim", "StepByStepProof", ...]}]}
                """

                do {
                    let response = try await ResearchService.shared.analyze(prompt: prompt, tier: .router)

                    var jsonStr = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    if jsonStr.hasPrefix("```") {
                        if let firstNewline = jsonStr.firstIndex(of: "\n") {
                            jsonStr = String(jsonStr[jsonStr.index(after: firstNewline)...])
                        }
                        if jsonStr.hasSuffix("```") {
                            jsonStr = String(jsonStr.dropLast(3))
                        }
                        jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    struct MigrationResult: Codable {
                        let results: [SwipeMigration]
                        struct SwipeMigration: Codable {
                            let uuid: String
                            let beats: [String]
                        }
                    }

                    if let data = jsonStr.data(using: .utf8),
                       let migration = try? JSONDecoder().decode(MigrationResult.self, from: data) {
                        for result in migration.results {
                            guard var atom = batchAtoms.first(where: { $0.uuid == result.uuid }),
                                  var analysis = atom.swipeAnalysis else { continue }

                            let normalized = normalizeBeats(rawLabels: result.beats)
                            let fp = computeStructuralFingerprint(normalizedBeats: normalized)
                            analysis.normalizedBeats = normalized
                            analysis.beatFingerprint = fp
                            atom = atom.withSwipeAnalysis(analysis)

                            try await database.asyncWrite { db in
                                try atom.update(db)
                            }
                        }
                    }
                } catch {
                    print("BeatPatternService: migration batch failed: \(error)")
                }
            }
        } catch {
            print("BeatPatternService: migrateExistingSwipes failed: \(error)")
        }
    }

    // MARK: - Sequence Similarity

    /// Compute sequence similarity between two beat arrays (0.0 to 1.0)
    /// Uses longest common subsequence ratio
    private func sequenceSimilarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0 }

        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        let lcsLength = dp[m][n]
        return Double(2 * lcsLength) / Double(m + n)
    }

    // MARK: - GRDB Helpers

    private func fetchSwipeAtoms() async throws -> [Atom] {
        try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }.filter { $0.isSwipeFileAtom }
    }

    private func fetchAtom(uuid: String) async throws -> Atom? {
        try await database.asyncRead { db in
            try Atom
                .filter(Column("uuid") == uuid)
                .filter(Column("is_deleted") == false)
                .fetchOne(db)
        }
    }

    // MARK: - Canonical Vocabulary List

    /// The canonical beat labels as a comma-separated string for AI prompts
    var canonicalLabelsForPrompt: String {
        vocabulary.map { $0.label }.joined(separator: ", ")
    }

    // MARK: - Default Vocabulary

    static let defaultVocabulary: [CanonicalBeat] = [
        // 12 core beats from PRD
        CanonicalBeat(label: "BoldClaim", function: "Provocative statement to arrest attention", originalVariants: ["Bold Claim", "Bold Statement", "Strong Claim", "Hot Take"]),
        CanonicalBeat(label: "CuriosityGap", function: "Creates information gap viewer needs to close", originalVariants: ["Curiosity Gap", "Open Loop", "Information Gap", "Tease"]),
        CanonicalBeat(label: "PersonalFailure", function: "Relatable low point to build connection", originalVariants: ["Personal Failure", "Failure Story", "Rock Bottom", "Low Point", "Vulnerable Moment"]),
        CanonicalBeat(label: "DiscoveryMoment", function: "Turning point where solution was found", originalVariants: ["Discovery Moment", "Aha Moment", "Breakthrough", "Eureka", "Turning Point"]),
        CanonicalBeat(label: "StepByStepProof", function: "Walks through process with specifics", originalVariants: ["Step By Step", "Step-by-Step", "Process Walkthrough", "How I Did It", "Tutorial Steps"]),
        CanonicalBeat(label: "SocialProofNumbers", function: "Concrete evidence: revenue, results, followers", originalVariants: ["Social Proof", "Numbers", "Results", "Revenue Proof", "Stats", "Data Point"]),
        CanonicalBeat(label: "BeliefReframe", function: "Challenges common assumption or reframes a belief", originalVariants: ["Belief Reframe", "Reframe", "Paradigm Shift", "Mindset Shift", "New Perspective"]),
        CanonicalBeat(label: "AspirationalOutcome", function: "Paints desired end state vividly", originalVariants: ["Aspirational Outcome", "Dream State", "Vision", "Future Self", "End State"]),
        CanonicalBeat(label: "UrgencyCTA", function: "Drives immediate action with time pressure", originalVariants: ["Urgency CTA", "Call to Action", "CTA", "Act Now", "Time Pressure"]),
        CanonicalBeat(label: "ValueStack", function: "Layers benefits to overwhelm objections", originalVariants: ["Value Stack", "Benefit Stack", "Value Ladder", "Benefits List"]),
        CanonicalBeat(label: "EnemyCallout", function: "Names common enemy audience relates to", originalVariants: ["Enemy Callout", "Common Enemy", "Villain", "Us vs Them", "Enemy Naming"]),
        CanonicalBeat(label: "ObjectionCrusher", function: "Pre-handles viewer doubts before they arise", originalVariants: ["Objection Crusher", "Objection Handler", "But What About", "Doubt Killer", "Preemptive Answer"]),

        // Extended beats (13-27)
        CanonicalBeat(label: "StorySetup", function: "Sets scene and context for a narrative arc", originalVariants: ["Story Setup", "Scene Setting", "Context Setup", "Backstory", "Setting the Stage"]),
        CanonicalBeat(label: "EmotionalHook", function: "Opens with raw emotion to create instant connection", originalVariants: ["Emotional Hook", "Emotion Lead", "Feeling First", "Emotional Opener"]),
        CanonicalBeat(label: "TransitionBridge", function: "Smooth pivot between sections or ideas", originalVariants: ["Transition", "Bridge", "Pivot", "Segue", "Meanwhile"]),
        CanonicalBeat(label: "ListicleItem", function: "Single numbered item in a list-style structure", originalVariants: ["Listicle Item", "List Item", "Numbered Point", "Tip"]),
        CanonicalBeat(label: "AuthorityEstablishment", function: "Establishes credibility through credentials or experience", originalVariants: ["Authority", "Credibility", "Credentials", "Expert Positioning", "Trust Builder"]),
        CanonicalBeat(label: "PainAmplification", function: "Deepens awareness of the problem to increase urgency", originalVariants: ["Pain Amplification", "Pain Point", "Problem Deepening", "Agitation", "Twist the Knife"]),
        CanonicalBeat(label: "SolutionReveal", function: "Presents the answer or fix after building tension", originalVariants: ["Solution Reveal", "The Fix", "Answer", "Solution", "Here's How"]),
        CanonicalBeat(label: "ComparisonContrast", function: "Side-by-side comparison to highlight differences", originalVariants: ["Comparison", "Contrast", "vs", "Side by Side", "Before vs After"]),
        CanonicalBeat(label: "AudienceCallout", function: "Directly addresses a specific audience segment", originalVariants: ["Audience Callout", "If You're", "This Is For", "You Know Who You Are"]),
        CanonicalBeat(label: "FutureWarning", function: "Warns about consequences of inaction", originalVariants: ["Future Warning", "Warning", "If You Don't", "Consequence", "Risk Alert"]),
        CanonicalBeat(label: "MetaphorAnalogy", function: "Uses metaphor or analogy to simplify complex idea", originalVariants: ["Metaphor", "Analogy", "Like", "Think of It As", "Imagine"]),
        CanonicalBeat(label: "TestimonialQuote", function: "Uses direct quote from customer or third party", originalVariants: ["Testimonial", "Quote", "Customer Story", "User Said", "Review"]),
        CanonicalBeat(label: "IdentityShift", function: "Redefines how the viewer sees themselves", originalVariants: ["Identity Shift", "You're Not", "You Are", "Become", "Identity"]),
        CanonicalBeat(label: "ScarcityTrigger", function: "Highlights limited availability to drive action", originalVariants: ["Scarcity", "Limited", "Only X Left", "Running Out", "Exclusive Access"]),
        CanonicalBeat(label: "CommunitySignal", function: "Invokes belonging to an in-group or movement", originalVariants: ["Community Signal", "Community", "Movement", "Tribe", "Join Us", "We"]),
    ]
}
