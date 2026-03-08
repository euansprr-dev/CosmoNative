// CosmoOS/AI/LessonExtractor.swift
// Extracts generalizable writing rules from generation->edit cycles.
// Stores inferred lessons as .agentLearning atoms with confidence scores.
// February 2026

import Foundation

// MARK: - Lesson Enums

/// How a lesson was created
enum LessonSource: String, Codable {
    case explicitUser = "explicit_user"       // User explicitly said "remember this" / "save this lesson"
    case inferredEdit = "inferred_edit"        // Extracted from generation→edit comparison
    case legacyModuleImport = "legacy_module_import"  // Imported from module LEARNED RULES section during migration
}

/// How strictly a lesson is enforced during writing
enum LessonEnforcement: String, Codable {
    case hard = "hard"         // Violations block/force rewrite — deterministic validators + scorecard check
    case advisory = "advisory" // Included in prompt but not mechanically enforced
}

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
    /// How this lesson was created. nil for pre-migration lessons (treated as inferredEdit).
    var source: LessonSource?
    /// How strictly this lesson is enforced. nil for pre-migration lessons (treated as advisory).
    var enforcement: LessonEnforcement?
    /// Which module this lesson conceptually belongs to (for UI grouping). Derived from categoryToModuleMap.
    var targetModuleId: String?

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
        intent: String? = nil,
        source: LessonSource? = nil,
        enforcement: LessonEnforcement? = nil,
        targetModuleId: String? = nil
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
        self.source = source
        self.enforcement = enforcement
        self.targetModuleId = targetModuleId
    }

    /// Effective enforcement level: explicit user + confirmed inferred = hard, else advisory
    var effectiveEnforcement: LessonEnforcement {
        if let enforcement = enforcement { return enforcement }
        // Pre-migration fallback: explicit saves (0.9+) or confirmed (0.8+) = hard
        if source == .explicitUser { return .hard }
        if confidence >= 0.8 { return .hard }
        return .advisory
    }

    /// Effective source: defaults to inferredEdit for pre-migration lessons
    var effectiveSource: LessonSource {
        return source ?? .inferredEdit
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a lesson's confidence, enforcement, or rule text changes.
    /// Observers (e.g. UnifiedWritingEngine) should invalidate cached lesson blocks.
    static let cosmoLessonChanged = Notification.Name("cosmoLessonChanged")
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
                intent: lesson.intent,
                source: .explicitUser,  // User-corrected = explicit
                enforcement: .hard,     // User corrections are always hard rules
                targetModuleId: lesson.targetModuleId ?? PromptTemplateStore.categoryToModuleMap[lesson.category]
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let updatedData = try encoder.encode(updatedLesson)
            atom.structured = String(data: updatedData, encoding: .utf8)
            atom.body = correctedRule

            _ = try await atomRepo.update(atom)
            NotificationCenter.default.post(name: .cosmoLessonChanged, object: nil)
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

            // Re-create with updated confidence (preserve all fields)
            // Confirmed inferred lessons become hard enforcement
            let updatedEnforcement: LessonEnforcement? = confirmed && fastConfirm
                ? .hard
                : (confirmed ? .hard : lesson.enforcement)

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
                intent: lesson.intent,
                source: lesson.source,
                enforcement: updatedEnforcement,
                targetModuleId: lesson.targetModuleId
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let updatedData = try encoder.encode(updatedLesson)
            atom.structured = String(data: updatedData, encoding: .utf8)

            _ = try await atomRepo.update(atom)
            NotificationCenter.default.post(name: .cosmoLessonChanged, object: nil)
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
                intent: intent,
                source: .inferredEdit,
                enforcement: .advisory,  // Inferred lessons start advisory until confirmed
                targetModuleId: PromptTemplateStore.categoryToModuleMap[category]
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
                        intent: lesson.intent,
                        source: lesson.source,
                        enforcement: lesson.enforcement,
                        targetModuleId: lesson.targetModuleId
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
                "intent": lesson.intent ?? "",
                "source": lesson.effectiveSource.rawValue,
                "enforcement": lesson.effectiveEnforcement.rawValue,
                "targetModuleId": lesson.targetModuleId ?? ""
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

    // MARK: - Enforcement Migration

    /// Migrate existing lessons to add source, enforcement, and targetModuleId fields.
    /// - Explicit saves (confidence >= 0.9) → source=explicit_user, enforcement=hard
    /// - Confirmed inferred (confidence >= 0.8) → source=inferred_edit, enforcement=hard
    /// - Everything else → source=inferred_edit, enforcement=advisory
    /// Also populates targetModuleId from categoryToModuleMap.
    func migrateEnforcementLevels() async {
        let migrationKey = "lessons_enforcement_migration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

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
                      let lesson = try? decoder.decode(InferredLesson.self, from: data) else {
                    continue
                }

                // Skip if already has enforcement set
                guard lesson.enforcement == nil else { continue }

                // Determine source and enforcement from confidence
                let source: LessonSource = lesson.confidence >= 0.9 ? .explicitUser : .inferredEdit
                let enforcement: LessonEnforcement = lesson.confidence >= 0.8 ? .hard : .advisory
                let targetModuleId = PromptTemplateStore.categoryToModuleMap[lesson.category]

                let updatedLesson = InferredLesson(
                    id: lesson.id,
                    clientUUID: lesson.clientUUID,
                    rule: lesson.rule,
                    evidence: lesson.evidence,
                    category: lesson.category,
                    confidence: lesson.confidence,
                    createdAt: lesson.createdAt,
                    lastConfirmedAt: lesson.lastConfirmedAt,
                    optimizedInstruction: lesson.optimizedInstruction,
                    intent: lesson.intent,
                    source: source,
                    enforcement: enforcement,
                    targetModuleId: targetModuleId
                )

                let updatedData = try encoder.encode(updatedLesson)
                atom.structured = String(data: updatedData, encoding: .utf8)

                // Update metadata
                var updatedMeta = meta
                updatedMeta["source"] = source.rawValue
                updatedMeta["enforcement"] = enforcement.rawValue
                updatedMeta["targetModuleId"] = targetModuleId ?? ""
                if let metaData = try? JSONSerialization.data(withJSONObject: updatedMeta),
                   let metaStr = String(data: metaData, encoding: .utf8) {
                    atom.metadata = metaStr
                }

                _ = try await atomRepo.update(atom)
                migratedCount += 1
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            if migratedCount > 0 {
                print("[LessonExtractor] Migrated \(migratedCount) lessons with source/enforcement/targetModuleId")
            }
        } catch {
            print("[LessonExtractor] Enforcement migration failed: \(error.localizedDescription)")
        }
    }

    /// Import lessons from module LEARNED RULES sections into canonical atom storage,
    /// then strip the LEARNED RULES sections from module content.
    /// Reconciles against existing lesson atoms by text similarity to avoid duplicates.
    func migrateModuleLessonsToAtoms() async {
        let migrationKey = "lessons_strip_module_dups_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let store = PromptTemplateStore.shared
        let existingLessons = await loadLessons(minConfidence: 0.0)
        var importedCount = 0

        for module in store.modules {
            guard let headerRange = module.content.range(of: PromptTemplateStore.LEARNED_RULES_HEADER) else {
                continue
            }

            let rulesSection = String(module.content[headerRange.upperBound...])
            let ruleLines = rulesSection.components(separatedBy: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }

            for line in ruleLines {
                let ruleText = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^- ", with: "", options: .regularExpression)
                    // Strip [#shortId] marker
                    .replacingOccurrences(of: "\\s*\\[#[a-fA-F0-9]+\\]$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                guard !ruleText.isEmpty else { continue }

                // Check if a similar lesson already exists as an atom
                let isDuplicate = existingLessons.contains { existing in
                    computeWordSimilarity(ruleText, existing.rule) > 0.7
                        || (existing.optimizedInstruction != nil && computeWordSimilarity(ruleText, existing.optimizedInstruction!) > 0.7)
                }

                guard !isDuplicate else { continue }

                // Infer category from module ID (reverse lookup)
                let category = PromptTemplateStore.categoryToModuleMap.first(where: { $0.value == module.id })?.key ?? "general"

                let lesson = InferredLesson(
                    rule: ruleText,
                    evidence: "Imported from module '\(module.title)' LEARNED RULES section",
                    category: category,
                    confidence: 0.8,  // High confidence — was already in production
                    source: .legacyModuleImport,
                    enforcement: .hard,  // Was in production, treat as hard
                    targetModuleId: module.id
                )

                await storeLesson(lesson)
                importedCount += 1
            }
        }

        // Strip LEARNED RULES sections from all modules
        store.stripLearnedRulesFromAllModules()

        UserDefaults.standard.set(true, forKey: migrationKey)
        if importedCount > 0 {
            print("[LessonExtractor] Imported \(importedCount) lessons from module LEARNED RULES sections")
        }
        print("[LessonExtractor] Stripped LEARNED RULES sections from all modules")
        NotificationCenter.default.post(name: .cosmoLessonChanged, object: nil)
    }

    // MARK: - Intent Migration

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

    // MARK: - Module Migration (Legacy — superseded by migrateModuleLessonsToAtoms)

    /// Legacy migration: no longer writes to modules. Kept for guard flag compatibility.
    func migrateExistingLessonsToModules() async {
        // No-op: superseded by migrateModuleLessonsToAtoms() which imports FROM modules into atoms.
        // Guard flag "lessons_module_migration_v1" already set on older installs.
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
