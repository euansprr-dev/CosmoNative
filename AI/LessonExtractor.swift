// CosmoOS/AI/LessonExtractor.swift
// Extracts generalizable writing rules from generation->edit cycles.
// Stores inferred lessons as .agentLearning atoms with confidence scores.
// February 2026

import Foundation

// MARK: - Inferred Lesson Model

struct InferredLesson: Codable, Identifiable {
    let id: UUID
    let clientUUID: String?  // nil for universal lessons
    let rule: String
    let evidence: String
    let category: String  // hook_style, voice, structure, format, cta, scheduling, productivity, etc.
    let confidence: Double
    let createdAt: Date
    var lastConfirmedAt: Date
    /// LLM-optimized prompt instruction with before/after example.
    /// Generated at storage time for better prompt injection.
    var optimizedInstruction: String?
    /// Intent scope: nil = universal, "draft" = writing, "plan" = planning, etc.
    /// Lessons only activate when the agent's current intent matches (or when nil/universal).
    var intent: String?

    init(
        id: UUID = UUID(),
        clientUUID: String? = nil,
        rule: String,
        evidence: String,
        category: String,
        confidence: Double = 0.6,
        createdAt: Date = Date(),
        lastConfirmedAt: Date = Date(),
        optimizedInstruction: String? = nil,
        intent: String? = nil
    ) {
        self.id = id
        self.clientUUID = clientUUID
        self.rule = rule
        self.evidence = evidence
        self.category = category
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
        self.optimizedInstruction = optimizedInstruction
        self.intent = intent
    }
}

// MARK: - Lesson Extractor

@MainActor
class LessonExtractor {
    static let shared = LessonExtractor()

    private let atomRepo = AtomRepository.shared

    /// Lessons awaiting user confirmation via Telegram
    private var pendingConfirmations: [InferredLesson] = []

    private init() {}

    // MARK: - Confirmation Queue

    /// Add a lesson to the pending confirmation queue
    func queueForConfirmation(_ lesson: InferredLesson) {
        pendingConfirmations.append(lesson)
    }

    /// Return and clear all pending lessons awaiting confirmation
    func drainPendingConfirmations() -> [InferredLesson] {
        let drained = pendingConfirmations
        pendingConfirmations = []
        return drained
    }

    /// Replace a lesson's rule text and set high confidence after user correction
    func correctLesson(lessonID: UUID, correctedRule: String) async {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            guard var atom = atoms.first(where: { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonType"] as? String == "inferred_lesson"
                    && meta["lessonID"] as? String == lessonID.uuidString
            }) else { return }

            guard let structuredStr = atom.structured,
                  let data = structuredStr.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let lesson = try decoder.decode(InferredLesson.self, from: data)

            // Build corrected optimized instruction
            let correctedInstruction = "RULE: \(correctedRule)\nEVIDENCE: \(lesson.evidence)\nWHY: User-corrected rule"

            let updatedLesson = InferredLesson(
                id: lesson.id,
                clientUUID: lesson.clientUUID,
                rule: correctedRule,
                evidence: lesson.evidence,
                category: lesson.category,
                confidence: 0.95,
                createdAt: lesson.createdAt,
                lastConfirmedAt: Date(),
                optimizedInstruction: correctedInstruction,
                intent: lesson.intent
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let updatedData = try encoder.encode(updatedLesson)
            atom.structured = String(data: updatedData, encoding: .utf8)
            atom.body = correctedRule

            _ = try await atomRepo.update(atom)
        } catch {
            print("[LessonExtractor] Failed to correct lesson: \(error.localizedDescription)")
        }
    }

    // MARK: - Extract Lessons

    /// Extract lessons from a generation->edit pair
    /// - Parameter initialConfidence: Starting confidence for new lessons (default 0.6, use 0.3 for unconfirmed)
    func extractLessons(
        generated: String,
        edited: String,
        clientUUID: UUID?,
        contentFormat: String,
        initialConfidence: Double = 0.6
    ) async -> [InferredLesson] {
        // Quick check: if texts are very similar (<15% different), no lesson to extract
        let editDistance = computeWordEditDistance(generated, edited)
        guard editDistance > 0.15 else { return [] }

        // Call ResearchService to extract rules
        let prompt = """
        Compare these two versions of content. The first was AI-generated, the second was edited by the user.

        AI Version:
        \(String(generated.prefix(1500)))

        User's Edit:
        \(String(edited.prefix(1500)))

        Content Format: \(contentFormat)

        Extract 1-3 generalizable writing rules that explain the key differences.
        For each rule, respond in this JSON format:
        [{"rule": "concise rule statement", "evidence": "what specific change demonstrates this", "category": "hook_style|voice|structure|format|cta"}]

        Only extract rules that would apply to FUTURE content, not one-time fixes.
        Respond with ONLY the JSON array.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            var lessons = parseLessonsFromResponse(
                response,
                clientUUID: clientUUID,
                contentFormat: contentFormat,
                initialConfidence: initialConfidence
            )

            // Optimize each lesson into a clear prompt instruction with before/after example
            lessons = await optimizeLessons(
                lessons,
                generated: generated,
                edited: edited,
                contentFormat: contentFormat
            )

            // Store each lesson as an .agentLearning atom
            for lesson in lessons {
                await storeLesson(lesson)
            }

            return lessons
        } catch {
            print("[LessonExtractor] Failed to extract lessons: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Confidence Management

    /// Update confidence of an existing lesson
    /// - Parameter fastConfirm: If true and confirmed, jump directly to 0.95 confidence
    func updateConfidence(lessonID: UUID, confirmed: Bool, fastConfirm: Bool = false) async {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            guard var atom = atoms.first(where: { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonType"] as? String == "inferred_lesson"
                    && meta["lessonID"] as? String == lessonID.uuidString
            }) else { return }

            // Decode existing lesson
            guard let structuredStr = atom.structured,
                  let data = structuredStr.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let lesson = try decoder.decode(InferredLesson.self, from: data)

            // Adjust confidence: fast-confirm → 0.95, confirmed +0.2, contradicted -0.1
            let newConfidence: Double
            if fastConfirm && confirmed {
                newConfidence = 0.95
            } else if confirmed {
                newConfidence = min(lesson.confidence + 0.2, 1.0)
            } else {
                newConfidence = max(lesson.confidence - 0.1, 0.0)
            }

            // Archive if confidence drops below 0.1
            if newConfidence < 0.1 {
                atom.isDeleted = true
                _ = try await atomRepo.update(atom)
                return
            }

            // Re-create with updated confidence (preserve optimizedInstruction + intent)
            let updatedLesson = InferredLesson(
                id: lesson.id,
                clientUUID: lesson.clientUUID,
                rule: lesson.rule,
                evidence: lesson.evidence,
                category: lesson.category,
                confidence: newConfidence,
                createdAt: lesson.createdAt,
                lastConfirmedAt: confirmed ? Date() : lesson.lastConfirmedAt,
                optimizedInstruction: lesson.optimizedInstruction,
                intent: lesson.intent
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let updatedData = try encoder.encode(updatedLesson)
            atom.structured = String(data: updatedData, encoding: .utf8)

            _ = try await atomRepo.update(atom)
        } catch {
            print("[LessonExtractor] Failed to update confidence: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Lessons

    /// Load active lessons for a client (or universal lessons)
    func loadLessons(clientUUID: UUID? = nil, minConfidence: Double = 0.3) async -> [InferredLesson] {
        return await loadLessons(clientUUID: clientUUID, intent: nil, minConfidence: minConfidence)
    }

    /// Load active lessons filtered by intent scope.
    /// Includes lessons where `lesson.intent == nil` (universal) OR `lesson.intent == intent`.
    func loadLessons(clientUUID: UUID? = nil, intent: String? = nil, minConfidence: Double = 0.3) async -> [InferredLesson] {
        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var lessons: [InferredLesson] = []

            for atom in atoms {
                guard let meta = atom.metadataDict,
                      meta["lessonType"] as? String == "inferred_lesson",
                      let structuredStr = atom.structured,
                      let data = structuredStr.data(using: .utf8),
                      let lesson = try? decoder.decode(InferredLesson.self, from: data) else {
                    continue
                }

                // Filter by confidence
                guard lesson.confidence >= minConfidence else { continue }

                // Filter by client: include universal lessons (nil) + client-specific
                if let clientUUID = clientUUID {
                    guard lesson.clientUUID == nil || lesson.clientUUID == clientUUID.uuidString else {
                        continue
                    }
                }

                // Filter by intent: include universal lessons (nil intent) + matching intent
                if let intent = intent {
                    guard lesson.intent == nil || lesson.intent == intent else {
                        continue
                    }
                }

                lessons.append(lesson)
            }

            return lessons
        } catch {
            print("[LessonExtractor] Failed to load lessons: \(error.localizedDescription)")
            return []
        }
    }

    /// Format a lesson as a concise directive optimized for embedding in a PromptModule.
    /// Includes a unique marker [#shortId] for later removal/tracking.
    func formatLessonForModule(_ lesson: InferredLesson) -> String {
        let shortId = String(lesson.id.uuidString.prefix(8))
        if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
            return "\(optimized) [#\(shortId)]"
        }
        return "RULE: \(lesson.rule) — EVIDENCE: \(lesson.evidence) [#\(shortId)]"
    }

    /// Load a single lesson by its UUID.
    func loadLesson(byID lessonID: UUID) async -> InferredLesson? {
        let allLessons = await loadLessons(minConfidence: 0.0)
        return allLessons.first(where: { $0.id == lessonID })
    }

    /// Format lessons as a prompt block for injection into AI generation context.
    /// Uses optimized instructions with before/after examples when available.
    /// Filters by intent when provided; includes universal lessons always.
    func formatLessonsForPrompt(clientUUID: UUID? = nil, intent: String? = nil) async -> String {
        let lessons = await loadLessons(clientUUID: clientUUID, intent: intent)
        guard !lessons.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("=== LEARNED SKILLS ===")
        lines.append("These rules were learned from the user's past patterns and explicit instructions.")
        lines.append("Follow them strictly — violating these is a guaranteed rejection.")
        lines.append("")

        // Cap at 15 lessons to respect token budget
        for (i, lesson) in lessons.prefix(15).enumerated() {
            let scope = lesson.clientUUID != nil ? "[client-specific]" : "[universal]"
            let intentLabel = lesson.intent != nil ? " [\(lesson.intent!)]" : ""
            if let optimized = lesson.optimizedInstruction, !optimized.isEmpty {
                lines.append("\(i + 1). \(scope)\(intentLabel) \(optimized)")
            } else {
                lines.append("\(i + 1). \(scope)\(intentLabel) RULE: \(lesson.rule)")
                lines.append("   EVIDENCE: \(lesson.evidence)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func parseLessonsFromResponse(
        _ response: String,
        clientUUID: UUID?,
        contentFormat: String,
        initialConfidence: Double = 0.6
    ) -> [InferredLesson] {
        // Extract JSON array from response
        let cleaned = extractJSONArray(from: response)
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let validCategories: Set<String> = [
            "hook_style", "voice", "structure", "format", "cta",
            "scheduling", "productivity", "time_management",
            "strategy_pattern", "audience_insight",
            "analysis_method", "reflection_prompt", "general"
        ]

        return array.compactMap { dict -> InferredLesson? in
            guard let rule = dict["rule"] as? String,
                  let evidence = dict["evidence"] as? String,
                  let category = dict["category"] as? String,
                  validCategories.contains(category) else {
                return nil
            }

            let intent = dict["intent"] as? String

            return InferredLesson(
                clientUUID: clientUUID?.uuidString,
                rule: rule,
                evidence: evidence,
                category: category,
                confidence: initialConfidence,
                intent: intent
            )
        }
    }

    // MARK: - Lesson Optimization

    /// Take raw extracted lessons and rewrite them as optimized prompt instructions
    /// with before/after examples from the actual generation→edit pair.
    private func optimizeLessons(
        _ lessons: [InferredLesson],
        generated: String,
        edited: String,
        contentFormat: String
    ) async -> [InferredLesson] {
        guard !lessons.isEmpty else { return [] }

        // Build a single LLM call to optimize all lessons at once
        let lessonsJSON = lessons.enumerated().map { i, lesson in
            "  \(i + 1). RULE: \(lesson.rule)\n     EVIDENCE: \(lesson.evidence)\n     CATEGORY: \(lesson.category)"
        }.joined(separator: "\n")

        let prompt = """
        You are optimizing writing rules for injection into an AI writing engine's system prompt.

        These rules were extracted from a user editing an AI-generated \(contentFormat):

        AI VERSION (excerpt):
        \(String(generated.prefix(800)))

        USER'S EDIT (excerpt):
        \(String(edited.prefix(800)))

        RAW RULES:
        \(lessonsJSON)

        For EACH rule, rewrite it as an optimized prompt instruction. Format:
        [
          {
            "index": 1,
            "instruction": "RULE: [Clear, actionable instruction in imperative form]\\nBAD: [Specific example from the AI version showing the mistake]\\nGOOD: [Corresponding example from the user's edit showing the fix]\\nWHY: [One sentence explaining why this matters for the audience]"
          }
        ]

        Guidelines for the instruction:
        - RULE should be a direct command ("Never use...", "Always write...", "Replace X with Y")
        - BAD/GOOD examples should be ACTUAL text from the versions above, not made up
        - Keep each instruction under 200 words total
        - If you can't find a clear BAD/GOOD pair, use the evidence description instead

        Respond with ONLY the JSON array.
        """

        do {
            let response = try await ResearchService.shared.analyzeContent(prompt: prompt)
            let optimized = parseOptimizedInstructions(from: response)

            return lessons.enumerated().map { i, lesson in
                var updated = lesson
                if let instruction = optimized[i + 1] {
                    updated = InferredLesson(
                        id: lesson.id,
                        clientUUID: lesson.clientUUID,
                        rule: lesson.rule,
                        evidence: lesson.evidence,
                        category: lesson.category,
                        confidence: lesson.confidence,
                        createdAt: lesson.createdAt,
                        lastConfirmedAt: lesson.lastConfirmedAt,
                        optimizedInstruction: instruction,
                        intent: lesson.intent
                    )
                }
                return updated
            }
        } catch {
            print("[LessonExtractor] Lesson optimization failed (non-fatal): \(error)")
            return lessons  // Return raw lessons if optimization fails
        }
    }

    /// Parse the optimization LLM response into a map of index → instruction
    private func parseOptimizedInstructions(from response: String) -> [Int: String] {
        let cleaned = extractJSONArray(from: response)
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var result: [Int: String] = [:]
        for item in array {
            guard let index = item["index"] as? Int,
                  let instruction = item["instruction"] as? String else {
                continue
            }
            result[index] = instruction
        }
        return result
    }

    // MARK: - Storage

    func storeLesson(_ lesson: InferredLesson) async {
        do {
            // Dedup: check if a very similar lesson already exists
            let existingLessons = await loadLessons(clientUUID: lesson.clientUUID.flatMap { UUID(uuidString: $0) }, minConfidence: 0.0)
            for existing in existingLessons {
                if computeWordSimilarity(lesson.rule, existing.rule) > 0.7 {
                    // Boost existing lesson instead of creating duplicate
                    await updateConfidence(lessonID: existing.id, confirmed: true)
                    print("[LessonExtractor] Dedup: boosted existing lesson \(existing.id) instead of creating duplicate")
                    return
                }
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let structuredData = try encoder.encode(lesson)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataDict: [String: Any] = [
                "lessonType": "inferred_lesson",
                "lessonID": lesson.id.uuidString,
                "category": lesson.category,
                "clientUUID": lesson.clientUUID ?? "",
                "confidence": lesson.confidence,
                "intent": lesson.intent ?? ""
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            let atom = Atom.new(
                type: .agentLearning,
                title: "Lesson: \(lesson.category) — \(String(lesson.rule.prefix(60)))",
                body: lesson.rule,
                structured: structuredStr,
                metadata: metadataStr
            )
            _ = try await atomRepo.create(atom)
        } catch {
            print("[LessonExtractor] Failed to store lesson: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    /// Migrate existing lessons to add intent scope based on category.
    /// Writing-related categories get intent="draft", others remain universal.
    func migrateExistingLessons() async {
        let migrationKey = "lessons_intent_migration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let writingCategories: Set<String> = ["hook_style", "voice", "structure", "format", "cta"]

        do {
            let atoms = try await atomRepo.fetchAll(type: .agentLearning)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var migratedCount = 0

            for var atom in atoms {
                guard let meta = atom.metadataDict,
                      meta["lessonType"] as? String == "inferred_lesson",
                      let structuredStr = atom.structured,
                      let data = structuredStr.data(using: .utf8),
                      var lesson = try? decoder.decode(InferredLesson.self, from: data) else {
                    continue
                }

                // Skip if already has an intent
                guard lesson.intent == nil else { continue }

                // Infer intent from category
                if writingCategories.contains(lesson.category) {
                    lesson = InferredLesson(
                        id: lesson.id,
                        clientUUID: lesson.clientUUID,
                        rule: lesson.rule,
                        evidence: lesson.evidence,
                        category: lesson.category,
                        confidence: lesson.confidence,
                        createdAt: lesson.createdAt,
                        lastConfirmedAt: lesson.lastConfirmedAt,
                        optimizedInstruction: lesson.optimizedInstruction,
                        intent: "draft"
                    )

                    // Re-encode structured JSON
                    let updatedData = try encoder.encode(lesson)
                    atom.structured = String(data: updatedData, encoding: .utf8)

                    // Update metadata
                    var updatedMeta = meta
                    updatedMeta["intent"] = "draft"
                    if let metaData = try? JSONSerialization.data(withJSONObject: updatedMeta),
                       let metaStr = String(data: metaData, encoding: .utf8) {
                        atom.metadata = metaStr
                    }

                    _ = try await atomRepo.update(atom)
                    migratedCount += 1
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            if migratedCount > 0 {
                print("[LessonExtractor] Migrated \(migratedCount) writing lessons with intent='draft'")
            }
        } catch {
            print("[LessonExtractor] Migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Module Migration

    /// Migrate all existing confirmed lessons into their matching skill modules.
    /// Runs once (guarded by UserDefaults flag).
    func migrateExistingLessonsToModules() async {
        let migrationKey = "lessons_module_migration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let lessons = await loadLessons(minConfidence: 0.3)
        var routedCount = 0

        for lesson in lessons {
            guard let moduleId = PromptTemplateStore.categoryToModuleMap[lesson.category] else { continue }
            let formatted = formatLessonForModule(lesson)
            PromptTemplateStore.shared.appendLessonToModule(moduleId: moduleId, formattedRule: formatted)
            routedCount += 1
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[LessonExtractor] Migrated \(routedCount) lessons into skill modules")
    }

    /// Jaccard word similarity between two strings (0.0 = no overlap, 1.0 = identical)
    func computeWordSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map(String.init))
        let wordsB = Set(b.lowercased().split(separator: " ").map(String.init))
        let union = wordsA.union(wordsB)
        guard !union.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB)
        return Double(intersection.count) / Double(union.count)
    }

    func computeWordEditDistance(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " "))
        let wordsB = Set(b.lowercased().split(separator: " "))
        let maxCount = max(wordsA.count, wordsB.count)
        guard maxCount > 0 else { return 0 }
        let diff = wordsA.symmetricDifference(wordsB).count
        return Double(diff) / Double(maxCount)
    }

    private func extractJSONArray(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fencing
        if let start = trimmed.range(of: "```json") {
            let after = trimmed[start.upperBound...]
            if let end = after.range(of: "```") {
                return String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let start = trimmed.range(of: "```") {
            let after = trimmed[start.upperBound...]
            if let end = after.range(of: "```") {
                return String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Find first [ and last ]
        if let arrStart = trimmed.firstIndex(of: "["),
           let arrEnd = trimmed.lastIndex(of: "]") {
            return String(trimmed[arrStart...arrEnd])
        }

        return trimmed
    }
}
