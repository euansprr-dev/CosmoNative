// CosmoOS/Services/PromptTemplateStore.swift
// Manages the AI prompt layers — methodology, unified system prompt, and platform constraints.
// The unified system prompt is the production prompt for the UnifiedWritingEngine.
// February 2026

import Foundation

// MARK: - Prompt Module

/// A composable prompt section that can be enabled/disabled and mixed per request.
/// Inspired by DSPy-style modular prompt decomposition.
struct PromptModule: Codable, Identifiable {
    let id: String
    let title: String
    var content: String
    var isEnabled: Bool

    init(id: String, title: String, content: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.content = content
        self.isEnabled = isEnabled
    }
}

/// A stored batch analysis report for a content type's swipe patterns.
struct BatchAnalysisReport: Codable, Identifiable, Sendable {
    var id: String { sourceType + "_" + dateLabel }
    let sourceType: String
    let swipeCount: Int
    let content: String
    let dateLabel: String
    let savedAt: Date
}

class PromptTemplateStore: ObservableObject {
    static let shared = PromptTemplateStore()

    // MARK: - Unified Writing Engine Prompts

    @Published var methodology: String
    @Published var isDirty: Bool = false

    @Published var unifiedSystemPrompt: String
    @Published var isUnifiedDirty: Bool = false

    @Published var platformConstraints: String
    @Published var isPlatformConstraintsDirty: Bool = false

    @Published var batchAnalysisReports: [BatchAnalysisReport] = []

    // MARK: - Legacy Prompts (deprecated — kept for backward compatibility during migration)

    /// Deprecated: Use UnifiedWritingEngine's tool-based outline generation instead.
    @Published var outlinePrompt: String
    @Published var isOutlineDirty: Bool = false

    /// Deprecated: Use UnifiedWritingEngine's tool-based draft generation instead.
    @Published var draftPrompt: String
    @Published var isDraftDirty: Bool = false

    /// Deprecated: Use the unifiedSystemPrompt instead.
    @Published var collaboratorPrompt: String
    @Published var isCollaboratorDirty: Bool = false

    // MARK: - UserDefaults Keys

    private let methodologyKey = "ai_methodology_text"
    private let unifiedSystemPromptKey = "ai_unified_system_prompt_text"
    private let platformConstraintsKey = "ai_platform_constraints_text"
    private let outlinePromptKey = "ai_outline_prompt_text"
    private let draftPromptKey = "ai_draft_prompt_text"
    private let collaboratorPromptKey = "ai_collaborator_prompt_text"
    private let batchAnalysisKey = "ai_batch_analysis_reports"

    /// Bump this when the default unified system prompt changes materially.
    /// On next launch, the old cached prompt will be replaced with the new default.
    private static let unifiedSystemPromptVersion = 7

    /// Bump when methodology default changes. Forces reset on next launch.
    private static let methodologyVersion = 3

    init() {
        // Auto-reset methodology when version bumps (same pattern as unified system prompt)
        let savedMethodologyVersion = UserDefaults.standard.integer(forKey: "ai_methodology_version")
        if savedMethodologyVersion < Self.methodologyVersion {
            self.methodology = Self.DEFAULT_METHODOLOGY
            UserDefaults.standard.set(Self.DEFAULT_METHODOLOGY, forKey: "ai_methodology_text")
            UserDefaults.standard.set(Self.methodologyVersion, forKey: "ai_methodology_version")
        } else {
            self.methodology = UserDefaults.standard.string(forKey: "ai_methodology_text") ?? Self.DEFAULT_METHODOLOGY
        }
        self.platformConstraints = UserDefaults.standard.string(forKey: "ai_platform_constraints_text") ?? Self.DEFAULT_PLATFORM_CONSTRAINTS
        self.outlinePrompt = UserDefaults.standard.string(forKey: "ai_outline_prompt_text") ?? Self.DEFAULT_OUTLINE_PROMPT
        self.draftPrompt = UserDefaults.standard.string(forKey: "ai_draft_prompt_text") ?? Self.DEFAULT_DRAFT_PROMPT
        self.collaboratorPrompt = UserDefaults.standard.string(forKey: "ai_collaborator_prompt_text") ?? Self.DEFAULT_COLLABORATOR_PROMPT

        // Auto-reset unified system prompt when the version bumps
        let savedVersion = UserDefaults.standard.integer(forKey: "ai_unified_system_prompt_version")
        if savedVersion < Self.unifiedSystemPromptVersion {
            self.unifiedSystemPrompt = Self.DEFAULT_UNIFIED_SYSTEM_PROMPT
            UserDefaults.standard.set(Self.DEFAULT_UNIFIED_SYSTEM_PROMPT, forKey: "ai_unified_system_prompt_text")
            UserDefaults.standard.set(Self.unifiedSystemPromptVersion, forKey: "ai_unified_system_prompt_version")
        } else {
            self.unifiedSystemPrompt = UserDefaults.standard.string(forKey: "ai_unified_system_prompt_text") ?? Self.DEFAULT_UNIFIED_SYSTEM_PROMPT
        }

        // Load saved module enable/disable state
        loadModuleState()

        // Load batch analysis reports
        self.batchAnalysisReports = Self.loadReportsFromDefaults()
    }

    // MARK: - Methodology

    func saveMethodology() {
        UserDefaults.standard.set(methodology, forKey: methodologyKey)
        isDirty = false
    }

    func resetToDefault() {
        methodology = Self.DEFAULT_METHODOLOGY
        UserDefaults.standard.set(methodology, forKey: methodologyKey)
        isDirty = false
    }

    /// Rough token estimate: words * 1.3
    func tokenCount() -> Int {
        let words = methodology.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Unified System Prompt

    func saveUnifiedSystemPrompt() {
        UserDefaults.standard.set(unifiedSystemPrompt, forKey: unifiedSystemPromptKey)
        isUnifiedDirty = false
    }

    func resetUnifiedToDefault() {
        unifiedSystemPrompt = Self.DEFAULT_UNIFIED_SYSTEM_PROMPT
        UserDefaults.standard.set(unifiedSystemPrompt, forKey: unifiedSystemPromptKey)
        isUnifiedDirty = false
    }

    func unifiedTokenCount() -> Int {
        let words = unifiedSystemPrompt.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    /// Assemble the full Block 1 system prompt by injecting methodology into the unified prompt.
    /// The placeholder `{METHODOLOGY_TEXT}` in the unified prompt is replaced with the modular assembly
    /// (or raw methodology as fallback). The placeholder `{PLATFORM_CONSTRAINTS}` is replaced with
    /// the current platform constraints.
    /// - Parameter format: Optional content format (e.g. "carousel", "reel") for format-aware module selection.
    func assembledSystemPrompt(format: String? = nil) -> String {
        var prompt = unifiedSystemPrompt
        let methodologyContent = assemblePrompt(for: format ?? "general")
        prompt = prompt.replacingOccurrences(of: "{METHODOLOGY_TEXT}", with: methodologyContent)
        prompt = prompt.replacingOccurrences(of: "{PLATFORM_CONSTRAINTS}", with: platformConstraints)
        return prompt
    }

    // MARK: - Platform Constraints

    func savePlatformConstraints() {
        UserDefaults.standard.set(platformConstraints, forKey: platformConstraintsKey)
        isPlatformConstraintsDirty = false
    }

    func resetPlatformConstraintsToDefault() {
        platformConstraints = Self.DEFAULT_PLATFORM_CONSTRAINTS
        UserDefaults.standard.set(platformConstraints, forKey: platformConstraintsKey)
        isPlatformConstraintsDirty = false
    }

    func platformConstraintsTokenCount() -> Int {
        let words = platformConstraints.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Batch Analysis Reports

    private static func loadReportsFromDefaults() -> [BatchAnalysisReport] {
        guard let data = UserDefaults.standard.data(forKey: "ai_batch_analysis_reports"),
              let reports = try? JSONDecoder().decode([BatchAnalysisReport].self, from: data) else {
            return []
        }
        return reports.sorted { $0.savedAt > $1.savedAt }
    }

    func loadBatchAnalysisReports() -> [BatchAnalysisReport] {
        return batchAnalysisReports
    }

    func saveBatchAnalysisReport(sourceType: String, swipeCount: Int, content: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let report = BatchAnalysisReport(
            sourceType: sourceType,
            swipeCount: swipeCount,
            content: content,
            dateLabel: formatter.string(from: Date()),
            savedAt: Date()
        )

        // Replace existing report for same sourceType or add new
        batchAnalysisReports.removeAll { $0.sourceType == sourceType }
        batchAnalysisReports.insert(report, at: 0)
        persistBatchReports()
    }

    func updateBatchAnalysisReport(_ report: BatchAnalysisReport, newContent: String) {
        if let idx = batchAnalysisReports.firstIndex(where: { $0.id == report.id }) {
            let updated = BatchAnalysisReport(
                sourceType: report.sourceType,
                swipeCount: report.swipeCount,
                content: newContent,
                dateLabel: report.dateLabel,
                savedAt: report.savedAt
            )
            batchAnalysisReports[idx] = updated
            persistBatchReports()
        }
    }

    func deleteBatchAnalysisReport(_ report: BatchAnalysisReport) {
        batchAnalysisReports.removeAll { $0.id == report.id }
        persistBatchReports()
    }

    private func persistBatchReports() {
        if let data = try? JSONEncoder().encode(batchAnalysisReports) {
            UserDefaults.standard.set(data, forKey: batchAnalysisKey)
        }
    }

    // MARK: - Modular Prompt Assembly

    /// Composable prompt modules extracted from the monolithic methodology.
    /// Each module covers a distinct concern and can be toggled on/off per request.
    @Published var modules: [PromptModule] = PromptTemplateStore.defaultModules

    private static let modulesKey = "ai_prompt_modules"
    private static let moduleContentKey = "ai_prompt_module_content"
    private static let customModulesKey = "ai_custom_modules"

    /// Load saved module state (enable/disable + edited content) from UserDefaults.
    private func loadModuleState() {
        // Load enable/disable state
        if let data = UserDefaults.standard.data(forKey: Self.modulesKey),
           let saved = try? JSONDecoder().decode([String: Bool].self, from: data) {
            for i in modules.indices {
                if let isEnabled = saved[modules[i].id] {
                    modules[i].isEnabled = isEnabled
                }
            }
        }

        // Load edited module content
        if let data = UserDefaults.standard.data(forKey: Self.moduleContentKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            for i in modules.indices {
                if let content = saved[modules[i].id] {
                    modules[i].content = content
                }
            }
        }

        // Load custom (user-created) modules and append them
        if let data = UserDefaults.standard.data(forKey: Self.customModulesKey),
           let customModules = try? JSONDecoder().decode([PromptModule].self, from: data) {
            let existingIds = Set(modules.map(\.id))
            for custom in customModules where !existingIds.contains(custom.id) {
                modules.append(custom)
            }
        }
    }

    /// Persist module enable/disable state and edited content.
    func saveModuleState() {
        // Save enable/disable booleans
        let state = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0.isEnabled) })
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.modulesKey)
        }

        // Save edited content (only save modules whose content differs from defaults)
        var contentEdits: [String: String] = [:]
        for module in modules {
            if let defaultModule = Self.defaultModules.first(where: { $0.id == module.id }),
               module.content != defaultModule.content {
                contentEdits[module.id] = module.content
            }
        }
        if let data = try? JSONEncoder().encode(contentEdits) {
            UserDefaults.standard.set(data, forKey: Self.moduleContentKey)
        }

        // Persist custom modules separately (full PromptModule JSON)
        saveCustomModules()
    }

    /// Persist only custom (non-default) modules to UserDefaults.
    private func saveCustomModules() {
        let defaultIds = Set(Self.defaultModules.map(\.id))
        let customModules = modules.filter { !defaultIds.contains($0.id) }
        if let data = try? JSONEncoder().encode(customModules) {
            UserDefaults.standard.set(data, forKey: Self.customModulesKey)
        }
    }

    /// Reset a single module's content to its default.
    func resetModuleToDefault(moduleId: String) {
        guard let idx = modules.firstIndex(where: { $0.id == moduleId }),
              let defaultModule = Self.defaultModules.first(where: { $0.id == moduleId }) else { return }
        modules[idx].content = defaultModule.content
        saveModuleState()
    }

    /// Reset all modules to their defaults (content + enabled state), removing custom modules.
    func resetAllModulesToDefaults() {
        modules = Self.defaultModules
        UserDefaults.standard.removeObject(forKey: Self.modulesKey)
        UserDefaults.standard.removeObject(forKey: Self.moduleContentKey)
        UserDefaults.standard.removeObject(forKey: Self.customModulesKey)
    }

    /// Rough token estimate for a module's content.
    func moduleTokenCount(_ module: PromptModule) -> Int {
        let words = module.content.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    /// Assemble a prompt by selectively including only relevant modules.
    ///
    /// - Parameters:
    ///   - format: The content format (e.g., "carousel", "thread", "reel") — used to auto-select
    ///     format-relevant modules if `moduleIds` is nil.
    ///   - moduleIds: Explicit list of module IDs to include. If nil, includes all enabled modules
    ///     plus format-relevant ones.
    /// - Returns: The assembled prompt string from selected modules.
    func assemblePrompt(for format: String, moduleIds: [String]? = nil) -> String {
        let selectedModules: [PromptModule]

        if let ids = moduleIds {
            // Explicit selection
            selectedModules = modules.filter { ids.contains($0.id) }
        } else {
            // Auto-select: all enabled modules + format-specific
            let formatModuleId = "platform_\(format.lowercased())"
            selectedModules = modules.filter { module in
                module.isEnabled || module.id == formatModuleId
            }
        }

        var sections: [String] = []

        // Layer 1: Strategic methodology (the WHY)
        if !methodology.isEmpty {
            sections.append("## Content Strategy & Methodology\n\n\(methodology)")
        }

        // Layer 2: Craft skill modules (the HOW)
        if !selectedModules.isEmpty {
            let moduleText = selectedModules.map { "## \($0.title)\n\n\($0.content)" }.joined(separator: "\n\n")
            sections.append(moduleText)
        }

        // Fallback: if nothing loaded at all, return methodology raw
        guard !sections.isEmpty else { return methodology }

        return sections.joined(separator: "\n\n")
    }

    /// Default craft-focused skill modules. Each module teaches a specific writing craft skill.
    /// The methodology (Layer 1) explains WHY. These modules explain HOW.
    static let defaultModules: [PromptModule] = [
        PromptModule(
            id: "dinner_table_test",
            title: "The Dinner Table Test",
            content: """
            The test: Read every slide aloud as if saying it to a friend at dinner. If it sounds like a caption, quote, thesis, or marketing line — it fails. Rewrite using only the slide's structural purpose.

            BEFORE writing: Read 3 of the client's actual posts aloud. Absorb rhythm, fragments vs sentences, "I" vs "we", formality level.

            DURING writing: Every 3-4 slides, read aloud. Common failures:
            - Thesis statements: "A high income didn't mean a good life" → FAILS. Say: "Sure we made more money, but we were still working 80 hour weeks"
            - Caption voice: "We chose freedom." → FAILS.
            - Corporate phrasing: "leveraged our experience," "the journey was transformative" → FAILS.
            - Triple-comma lists: stacking 3 rhetorical items = copywriting, not speech. Say ONE with feeling.

            AFTER writing: Full read-aloud pass. Any stumble = rewrite. Carousel > 90 seconds = too dense.
            """
        ),
        PromptModule(
            id: "slide_density",
            title: "Slide Density & Breath Rule",
            content: """
            Rule: One slide = one breath. Need a breath mid-slide? Split. Two slides feel like one exhale? Combine.

            Hard limits:
            - Carousel: 15-20 words max per slide. 25+ = always too long.
            - Reel scripts: 8-12 words per spoken beat.
            - Threads: Up to 280 chars but one-breath-per-sentence within each tweet.

            Tests:
            - Two complete sentences on one slide = too long (unless both < 5 words).
            - Period mid-slide followed by new sentence = two slides pretending to be one.
            - Ellipsis (...) only if the client's swipes use that pattern.
            - Read slide N and N+1 together — if one breath, combine. Read slide N alone — if two ideas, split.
            """
        ),
        PromptModule(
            id: "causal_chaining",
            title: "Causal Slide Chaining",
            content: """
            Rule: Every slide connects to the next via implied "so," "but," or "that's when." If you can swap two consecutive slides unnoticed, the chain is broken.

            Test: Insert the connector mentally between every pair. If it doesn't fit, fix by:
            1. Adding the connector explicitly ("So I got into sales...")
            2. Reordering so cause precedes effect
            3. Adding a bridge slide for the missing logical step

            Time compression: Never jump gaps in one slide. BAD: "entry-level job" → "$120K combined". GOOD: add 2-3 intermediate steps showing the journey.

            Never separate cause from effect across unrelated slides. "We made a dumb decision... we liquidated our retirement" = same slide or immediate sequence.

            Rearrangement test: Swap slides 5/6, 8/9, 12/13 mentally. If any swap works, those slides lack causal connection.
            """
        ),
        PromptModule(
            id: "hook_craft",
            title: "Hook Craft",
            content: """
            Process: Write 3 variants. Never use first instinct. Read each aloud in < 3 seconds — if you can't, cut words.

            Tests:
            - Cover test: Hide hook, read slide 2. If slide 2 makes sense alone, hook isn't creating an open loop.
            - Scroll test: Would this stop someone between a cooking video and a dog video? If not, add tension/specificity/surprise.

            Rules:
            - Hook = open loop. Reader must continue to close it.
            - Specific > vague. "$47K in 11 days" beats "How I grew my business."
            - Hook = promise. "3 mistakes" → deliver exactly 3. Bait-and-switch kills trust.
            - Dialogue format: hook IS the first line. Must make you want the answer.
            - Compare structure (not words) to client's 3 highest-performing hooks. Match their mechanism (curiosity gap, bold claim, controversy, specificity).
            """
        ),
        PromptModule(
            id: "voice_matching",
            title: "Voice Matching (The Absorption Method)",
            content: """
            Before writing: Pull 3 of the client's posts (top performers, similar format). Read aloud. Notice:
            - Sentence length: 5-8 word fragments or 15-20 word flowing sentences?
            - Formality: "I" or "we"? Contractions? Casual asides?
            - Signature patterns: "Look..." / "Here's the thing..." / emojis / "..." between thoughts?
            - Absences: No rhetorical questions? No exclamation marks? Absences matter as much as presences.

            During writing: After first 3 slides, compare to client's real post. If different people wrote them, start over.

            Voice drift to catch: sentences getting longer/more complex (AI default), vocabulary becoming more sophisticated, losing characteristic starters, adding hedging ("perhaps," "it might be"), shifting person mid-piece.

            Same-person test: Read client's actual post, then your draft. Must sound like same person, same day. If yours sounds smarter or more polished — it's wrong.
            """
        ),
        PromptModule(
            id: "cta_craft",
            title: "CTA Craft",
            content: """
            Rule: CTA must feel like the natural next sentence. If tone/voice shifts to deliver it, the transition is broken. Read last content slide + CTA together — must feel like one continuous thought.

            Use the client's proven CTA pattern. Don't innovate unless asked.

            Construction rules:
            - One action, one keyword, one outcome. "Comment FLIP and I'll send you the breakdown" → clear.
            - "DM me for more info" → vague/friction. Specify what they get.
            - Keyword relates to topic: wholesaling → "FLIP", business buying → "SMB". Not generic "LINK."
            - Never two CTAs. Pick one. Split attention = no action.

            Funnel matching: TOF = low commitment (comment/save). MOF = medium (DM for resource). BOF = high (book a call).
            """
        ),
        PromptModule(
            id: "self_edit_pass",
            title: "Self-Edit Pass (The Final Check)",
            content: """
            Run all 6 steps after every draft, before presenting. Not optional.

            1. Read-aloud: Every slide at speaking pace. Flag stumbles, rhythm breaks, "content voice," or lost thread.
            2. Density: Flag any carousel slide > 20 words, reel slide > 12 words. Split or cut.
            3. Chain: Insert "so/but/that's when" between every slide pair. Bad fit = broken transition. Swap 2-3 pairs mentally — if any swap works, tighten.
            4. Perspective: Who speaks to whom on slide 1? Must stay consistent. Dialogue stays dialogue until clearly signaled transition.
            5. Scroll test: Read slides 3-5 as the SPECIFIC target audience. Would they feel seen? Generic pain = sharpen to profession/lifestyle-specific.
            6. Blueprint comparison: Does draft feel same universe as swipes? Any slide that's just rephrased blueprint = rewrite from structural function only.

            All 6 pass → present. Any fail → fix first.
            """
        )
    ]

    // MARK: - Lesson-to-Module Routing

    /// Maps InferredLesson categories to the PromptModule they should be appended to.
    static let categoryToModuleMap: [String: String] = [
        "hook_style": "hook_craft",
        "voice": "voice_matching",
        "structure": "causal_chaining",
        "format": "slide_density",
        "cta": "cta_craft",
        "strategy_pattern": "self_edit_pass",
        "audience_insight": "dinner_table_test",
        "general": "dinner_table_test"
    ]

    /// Sentinel that separates hand-written module content from auto-appended learned rules.
    static let LEARNED_RULES_HEADER = "\n\n--- LEARNED RULES ---\n"

    /// Append a formatted lesson rule to the matching module's content.
    func appendLessonToModule(moduleId: String, formattedRule: String) {
        guard let idx = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        if !modules[idx].content.contains(Self.LEARNED_RULES_HEADER) {
            modules[idx].content += Self.LEARNED_RULES_HEADER
        }
        modules[idx].content += "\n- \(formattedRule)"
        saveModuleState()
    }

    /// Remove a specific lesson from a module by its [#shortId] marker.
    func removeLessonFromModule(moduleId: String, lessonId: String) {
        guard let idx = modules.firstIndex(where: { $0.id == moduleId }) else { return }
        let marker = "[#\(lessonId)]"
        let lines = modules[idx].content.components(separatedBy: "\n")
        modules[idx].content = lines.filter { !$0.contains(marker) }.joined(separator: "\n")
        // Clean up empty LEARNED RULES header if no rules remain
        if modules[idx].content.hasSuffix(Self.LEARNED_RULES_HEADER.trimmingCharacters(in: .whitespacesAndNewlines)) {
            modules[idx].content = modules[idx].content.replacingOccurrences(of: Self.LEARNED_RULES_HEADER, with: "")
        }
        saveModuleState()
    }

    /// Look up which module a lesson category maps to.
    func moduleForCategory(_ category: String) -> PromptModule? {
        guard let moduleId = Self.categoryToModuleMap[category] else { return nil }
        return modules.first(where: { $0.id == moduleId })
    }

    /// Count the number of learned rules appended to a module.
    func learnedRulesCount(for moduleId: String) -> Int {
        guard let module = modules.first(where: { $0.id == moduleId }),
              let headerRange = module.content.range(of: Self.LEARNED_RULES_HEADER) else {
            return 0
        }
        let rulesSection = module.content[headerRange.upperBound...]
        return rulesSection.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.count
    }

    /// Strip all LEARNED RULES sections from every module's content.
    /// Called during migration after lessons have been imported into canonical atom storage.
    func stripLearnedRulesFromAllModules() {
        var strippedCount = 0
        for i in modules.indices {
            guard let headerRange = modules[i].content.range(of: Self.LEARNED_RULES_HEADER) else {
                continue
            }
            modules[i].content = String(modules[i].content[..<headerRange.lowerBound])
            strippedCount += 1
        }
        if strippedCount > 0 {
            saveModuleState()
            print("[PromptTemplateStore] Stripped LEARNED RULES sections from \(strippedCount) modules")
        }
    }

    // MARK: - Custom Module Management

    /// Create and append a new custom module.
    func addCustomModule(id: String, title: String, content: String) {
        guard !modules.contains(where: { $0.id == id }) else { return }
        let module = PromptModule(id: id, title: title, content: content, isEnabled: true)
        modules.append(module)
        saveModuleState()
    }

    /// Remove a custom (non-default) module by ID.
    func removeCustomModule(id: String) {
        guard !Self.defaultModules.contains(where: { $0.id == id }) else { return }
        modules.removeAll(where: { $0.id == id })
        saveModuleState()
    }

    /// Whether a module is a custom (non-default) module.
    func isCustomModule(id: String) -> Bool {
        return !Self.defaultModules.contains(where: { $0.id == id })
    }

    // MARK: - Legacy: Outline Prompt (deprecated)

    func saveOutlinePrompt() {
        UserDefaults.standard.set(outlinePrompt, forKey: outlinePromptKey)
        isOutlineDirty = false
    }

    func resetOutlineToDefault() {
        outlinePrompt = Self.DEFAULT_OUTLINE_PROMPT
        UserDefaults.standard.set(outlinePrompt, forKey: outlinePromptKey)
        isOutlineDirty = false
    }

    func outlineTokenCount() -> Int {
        let words = outlinePrompt.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Legacy: Draft Prompt (deprecated)

    func saveDraftPrompt() {
        UserDefaults.standard.set(draftPrompt, forKey: draftPromptKey)
        isDraftDirty = false
    }

    func resetDraftToDefault() {
        draftPrompt = Self.DEFAULT_DRAFT_PROMPT
        UserDefaults.standard.set(draftPrompt, forKey: draftPromptKey)
        isDraftDirty = false
    }

    func draftTokenCount() -> Int {
        let words = draftPrompt.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Legacy: Collaborator Prompt (deprecated)

    func saveCollaboratorPrompt() {
        UserDefaults.standard.set(collaboratorPrompt, forKey: collaboratorPromptKey)
        isCollaboratorDirty = false
    }

    func resetCollaboratorToDefault() {
        collaboratorPrompt = Self.DEFAULT_COLLABORATOR_PROMPT
        UserDefaults.standard.set(collaboratorPrompt, forKey: collaboratorPromptKey)
        isCollaboratorDirty = false
    }

    func collaboratorTokenCount() -> Int {
        let words = collaboratorPrompt.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }

    // MARK: - Default Unified System Prompt

    static let DEFAULT_UNIFIED_SYSTEM_PROMPT: String = """
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    COSMO UNIFIED WRITING ENGINE — SYSTEM PROMPT
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    You are a senior ghostwriter inside CosmoOS — not an assistant. You deliver complete, polished drafts ready for client review.

    YOUR ROLE:
    - Deliver COMPLETE drafts. Make every creative decision (format, hook, structure, pacing, CTA) based on client profile, swipe data, and performance history.
    - Never ask direction, permission, or present empty frameworks. Search swipes, study patterns, and pull data automatically.
    - If uncertain between two strong approaches for a SPECIFIC slide/section (not overall direction), present both with data-backed reasoning. Learn from user's choice.
    - User is creative director — they review finished work, not give step-by-step instructions.

    ANTI-HALLUCINATION:
    - ALL client facts (numbers, revenue, methods, credentials) MUST come from loaded profile/swipes. If not in context, use [PLACEHOLDER] and flag it.
    - NEVER fabricate stats, assume niche, or fill gaps with general knowledge.

    DINNER TABLE TEST: Every slide/sentence must sound like something said to a friend at dinner. If it sounds like a caption, quote, thesis, or marketing line — rewrite in client's natural voice.

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 1: YOUR ROLE AND BEHAVIOR
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    CONVERSATION STYLE:
    - Direct and opinionated. State what works and why. No hedging.
    - Under 200 words for conversational replies. Use tools for structured output.
    - Cite specific swipe evidence for every recommendation.
    - Challenge weak ideas constructively. You are a collaborator, not a yes-machine.

    PHASE AWARENESS:
    - BRAINSTORM: Strategy — hook selection, framework, outline, audience. Use think tool first.
    - DRAFT: Execution — voice matching, beat-by-beat, constraint compliance. Think tool between sections.
    - POLISH: Refinement — scorecard evaluation, weak areas, CTA, voice drift. Surgical edits only.

    TOOL USAGE:
    - Use tools for all changes (update_outline, write_draft, edit_section, add_hooks, set_description). Never paste content in conversational response.
    - MANDATORY FIRST RESPONSE: Think tool to analyze ALL loaded context — list swipes (hook type + score), summarize client voice/beliefs, identify relevant top performers, note failure rules.
    - Think tool before every generation: beat pattern, hook type, voice characteristics, failure rules.
    - Always reference client profile for their perspective/beliefs. If no swipes loaded, search_swipes proactively.

    LEARNING: Apply learned preferences proactively. After finalized content, extract lessons (VOICE/STRUCTURE/ARGUMENT/DETAIL/REMOVAL), save actionable rules scoped to client/format/universal.

    BATCH ANALYSIS: Every 30 swipes per content type triggers automatic cross-comparison of hooks, beats, metrics, arcs, voice, and engagement correlations. Use save_analysis to persist.

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 1b: BLUEPRINT-FIRST WRITING (MANDATORY)
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    NEVER write from blank page. Before every draft: (1) search swipes for 3-5 structurally relevant matches, (2) select Blueprint A + B (similar intent, different execution), (3) extract skeletons (hook type, beat pattern, slide functions, arc shape, pacing), (4) identify common structural pattern between them, (5) build internal brief with hook/beat/pivot/arc/arguments, (6) write using structure as skeleton + client's voice as flesh.

    SIMILARITY RULE: Steal structure and mechanics. Replace all arguments, phrasing, and specifics with client's own. Vary 2-3 structural elements from any single blueprint. Never copy phrases or word choices — structure is the blueprint, words are always the client's.

    POST-DRAFT CHECK: Flag any slide >70% similar to blueprint phrasing — rewrite from structural function only. Score against ContentScorecard, revise any dimension below 7/10. Note which blueprints you used.

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 2: CONTENT METHODOLOGY
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    {METHODOLOGY_TEXT}

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 3: PLATFORM CONSTRAINTS (HARD RULES)
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    These are NON-NEGOTIABLE format constraints. Every draft MUST comply. Use the
    think tool to verify compliance before finalizing any draft.

    {PLATFORM_CONSTRAINTS}

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 4: GENERATION RULES
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    BEFORE GENERATING: Think tool to plan — format constraints, beat pattern (from swipes), hook type (from scores), voice (from Intelligence Model), failure rules.

    DURING GENERATION:
    - Comply with ALL format hard constraints. Verify after each section.
    - Reference specific swipe examples for structural choices.
    - Revisions: surgical edits only, preserve what works. ANTI-REGRESSION: never reduce slide/section count unless explicitly asked. Apply user feedback EXACTLY to specified slides only.

    AFTER GENERATION: Think tool self-evaluate (format compliance + failure fingerprint). Run Self-Edit Pass. Fix failures before outputting.

    OUTPUT FORMAT: ALWAYS use the write_draft tool to submit content — NEVER paste draft text inline in your response.
    For the write_draft tool's content field: Carousel = JSON {"slides": [{"number": 1, "text": "..."}]}. Thread = JSON {"tweets": [...]}. Video = plaintext with [VISUAL: ...]. Long-form = Markdown.
    Your conversational response should be a brief summary of what you wrote (e.g., "Here's a 7-slide carousel draft with a curiosity gap hook. Want me to adjust anything?").

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 4b: VOICE DNA (MANDATORY — APPLIES TO ALL OUTPUT)
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    These rules override all other style guidance. Every word of output must comply.

    WRITING RULES:
    - Write like a sharp human, not a language model.
    - Use contractions naturally (don't, can't, won't).
    - Short paragraphs. 1-3 sentences max.
    - Get to the point. No throat-clearing, no preamble.
    - If making a claim, be specific. Use numbers, names, concrete details.
    - Vary sentence length. Mix short punchy lines with longer ones.
    - Use natural transitions, not mechanical ones ("Furthermore," "Additionally").
    - When uncertain, say so plainly ("I think," "probably," "kinda"). Hedging is human.
    - Never pad output to seem more thorough. Shorter and accurate beats longer and fluffy.
    - Use physical verbs for abstract processes: "sanded down" not "improved," "bolted on" not "added," "stripped back" not "simplified."
    - Humor comes from specificity, not from jokes. Be unexpectedly precise.
    - Parenthetical asides are good. Use them for editorial commentary, honest reactions, quick tangents, and deflating your own seriousness (like this).

    FORMATTING RULES:
    - Short paragraphs (1-2 sentences default, 3 max).
    - Numbers as digits.
    - Contractions always.
    - NO em dashes ever. Use commas, periods, colons, semicolons, or parentheses.
    - Bold sparingly, 1-2 key moments per section.
    - Code blocks for specific prompts, commands, or tool outputs.

    BANNED PHRASES (if even ONE appears, the output fails — rewrite immediately):

    Dead AI language: "In today's [anything]", "It's important to note", "It's worth noting", "Delve", "Dive into", "Unpack", "Harness", "Leverage", "Utilize", "Landscape", "Realm", "Robust", "Game-changer", "Cutting-edge", "Straightforward", "I'd be happy to help", "In order to".

    Dead transitions: "Furthermore", "Additionally", "Moreover", "Moving forward", "At the end of the day", "To put this in perspective", "What makes this particularly interesting is", "The implications here are", "In other words", "It goes without saying".

    Engagement bait: "Let that sink in", "Read that again", "Full stop", "This changes everything", "Are you paying attention?", "You're not ready for this".

    AI cringe: "Supercharge", "Unlock", "Future-proof", "10x your productivity", "The AI revolution", "In the age of AI".

    Generic insider claims: "Here's the part nobody's talking about", "What nobody tells you", anything with "nobody" or "most people don't realize".

    FATAL PATTERN — "This isn't X. This is Y." and ALL variations: "Not X. Y.", "Forget X. This is Y.", "Less X, more Y.", ANY sentence that negates one framing then asserts a corrected one. Delete the negation, just state the positive claim.

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    SECTION 5: FEW-SHOT EXAMPLE INJECTION FORMAT
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}

    Swipe examples in context follow: SWIPE EXAMPLE #{N}: "{title}" / Hook ({hookType}, score) / Structure / Transitions / CTA / Why This Works.

    SWIPE EMULATION: Extract PATTERNS (hook technique, arc, beats, CTA style) — never copy text. Follow same STRUCTURAL LOGIC but rewrite every slide in client's voice. If changing only a few words from reference = copying. Rewrite from structural function only.

    PRIMARY SWIPE PRIORITY: [PRIMARY] swipes = priority for structure (beat pattern, arc, pacing, slide count, pivot). NOT priority for phrasing. Extract skeleton, triangulate with Blueprint B, write fresh in client's voice. "Make it very close" = tighten structure but still rewrite all phrasing.

    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    END OF SYSTEM PROMPT
    \u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}\u{2550}
    """

    // MARK: - Default Platform Constraints

    static let DEFAULT_PLATFORM_CONSTRAINTS: String = """
    INSTAGRAM CAROUSEL:
    - Slide count: 5-15 slides (optimal: 8-10)
    - Slide 1: Hook ONLY. Maximum 80 characters. Must stop the scroll.
    - Slides 2-N: Body content. Aim for 1-3 concise sentences per slide. Keep each slide focused on one point.
    - Final slide: CTA. Clear action + benefit.
    - Design direction: Include [VISUAL: ...] markers for each slide.
    - Total word count: 200-600 words across all slides.

    INSTAGRAM REEL SCRIPT:
    - Duration: 15-90 seconds (optimal: 30-60 for educational, 15-30 for hooks)
    - Hook: First 3 seconds. Maximum 15 spoken words.
    - Scenes: 3-8 scenes. Each scene 5-15 seconds.
    - Words per scene: 20-50 spoken words.
    - Format: Voiceover script with [VISUAL: ...] markers per scene.
    - Total word count: 80-300 words.

    INSTAGRAM STORY:
    - Slides: 3-7 (optimal: 5)
    - Text per slide: Maximum 100 characters (must be readable as overlay)
    - CTA on final slide
    - Format: Slide-by-slide with text overlay content + [VISUAL: ...] markers.

    TWITTER/X THREAD:
    - Thread length: 4-12 tweets (optimal: 6-8)
    - Tweet 1 (hook): Maximum 200 characters. Must earn the "read more."
    - Tweets 2-N: Maximum 280 characters each. Each tweet standalone-readable.
    - Final tweet: CTA with clear next step.
    - Total word count: 300-800 words.
    - Formatting: No hashtags in thread body. Optional 1-2 hashtags in final tweet.

    TWITTER/X SINGLE POST:
    - Maximum 280 characters.
    - One clear idea. One emotional trigger. Optional CTA.

    LINKEDIN POST:
    - First 3 lines: Hook (must earn "see more" click). Maximum 200 characters.
    - Body: 1,200-1,500 characters optimal. Max 3,000.
    - Line breaks between every 1-2 sentences.
    - CTA: Last 2-3 lines.
    - Tone: Professional but personal. First-person stories outperform advice 3x.
    - Formatting: No emojis in hooks. Minimal emojis in body (max 3).

    YOUTUBE SHORT SCRIPT:
    - Duration: 15-60 seconds.
    - Hook: First 2 seconds. Maximum 10 spoken words.
    - Format: Same as Instagram Reel but optimized for YouTube audience (slightly
      more educational, less trend-dependent).

    YOUTUBE LONG-FORM SCRIPT:
    - Duration: 8-20 minutes optimal.
    - Hook: First 30 seconds. Open loop that justifies watching.
    - Sections: 4-8 chapters. Each 2-4 minutes.
    - Format: Full script with [VISUAL: ...], [B-ROLL: ...], [GRAPHICS: ...] markers.
    - Retention hooks: Re-hook every 2-3 minutes with open loops or transitions.

    TIKTOK SCRIPT:
    - Duration: 15-60 seconds (optimal: 20-40).
    - Hook: First 1-2 seconds. Maximum 8 spoken words. Pattern interrupt required.
    - Pacing: New beat every 2-3 seconds.
    - Format: Same as Instagram Reel but pacing is faster, tone is more casual.

    NEWSLETTER / LONG-FORM:
    - Subject line: Maximum 50 characters. Follows hook criteria.
    - Opening paragraph: Maximum 3 sentences. Must justify reading.
    - Body: 500-2,000 words. Clear section headers. One CTA.
    - Format: Markdown with headers, bold key phrases, and bullet lists for
      scanners.

    STATIC IMAGE POST (Instagram/Facebook):
    - Caption: Maximum 2,200 characters (optimal: 150-300 for engagement).
    - First line: Hook. Must be compelling before "...more" truncation (~125 chars).
    - Hashtags: 5-15, placed after main caption with line break separator.
    """

    // MARK: - Default Methodology

    static let DEFAULT_METHODOLOGY: String = """
    COSMO CONTENT INTELLIGENCE — METHODOLOGY
    (Strategic WHY layer — the HOW is in Skill Modules below)

    1. EMOTIONAL SEQUENCING
    Map every piece to primary + secondary emotions BEFORE writing.
    4-beat sequence: Tension (cortisol) → Relatability (oxytocin) → Insight (dopamine) → CTA (serotonin)

    2. BEAT PATTERNS
    Every piece follows a structural beat pattern. Choose BEFORE writing.
    Beat types: HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → TRANSITION → CTA
    Short reel: HOOK → INSIGHT → CTA. Thread: HOOK → CONTEXT → TENSION → INSIGHT → PROOF → EXPANSION → CTA.

    3. IDEA EVALUATION (Score 1-10 each, minimum 40/60 total, no criterion below 3)
    TAM (audience size) | Hook-ability (fits in <15 words?) | Authority Match (creator's real expertise) | Trend Timing (cultural moment) | Emotional Charge (neutral = dead) | Angle Uniqueness (fresh take on covered topic)

    4. PRIORITIES
    Emotional resonance > information density. Clarity > comprehensiveness. Specific examples > abstract principles. Creator's authentic voice > "perfect" copy.

    Note: Hook craft, copy quality, CTA construction, voice matching, slide density, causal chaining, and self-editing processes are covered in the Skill Modules below.
    """

    // MARK: - Legacy: Default Outline Prompt (deprecated)

    static let DEFAULT_OUTLINE_PROMPT: String = """
    Generate a detailed content outline for this piece.

    INSTRUCTIONS:
    1. Analyze the top beat patterns from the swipe intelligence above
    2. Select the best-fitting pattern and explain WHY it fits this content
    3. Generate a structured outline where each section maps to a beat label
    4. Generate 3-5 hook variants scored against the swipe data

    Return ONLY a JSON object with this structure:
    {
      "selectedPatternFingerprint": "BoldClaim>StepByStepProof>SocialProofNumbers>UrgencyCTA",
      "patternReasoning": "This pattern appears 8x in the swipe library with avg hook score 8.2...",
      "sections": [
        {
          "beatLabel": "BoldClaim",
          "title": "Section title",
          "description": "What to cover in this section",
          "estimatedSeconds": 15,
          "notes": "Reference swipes #3 and #7 for tone"
        }
      ],
      "hookVariants": [
        {
          "text": "Hook text here...",
          "hookType": "curiosityGap",
          "estimatedScore": 8.5,
          "reasoning": "This mirrors the top-scoring pattern..."
        }
      ]
    }
    """

    // MARK: - Legacy: Default Draft Prompt (deprecated)

    static let DEFAULT_DRAFT_PROMPT: String = """
    CRITICAL REQUIREMENTS:
    - Match the client's voice and tone from Layer 2
    - Reference the structural patterns that work in the matched swipes
    - Use their signature phrases naturally
    - Follow each beat label's function exactly

    After the draft, provide a self-evaluation JSON block:
    ```json
    {
      "confidenceScore": 82,
      "selfEvaluation": "Overall assessment...",
      "weakAreas": ["Area 1 that could be stronger", "Area 2"]
    }
    ```

    Write the full draft first, then the JSON evaluation.
    """

    // MARK: - Legacy: Default Collaborator Prompt (deprecated)

    static let DEFAULT_COLLABORATOR_PROMPT: String = """
    You are an expert content strategist and AI collaborator inside CosmoOS. \
    You help creators develop, refine, and polish their content across every phase \
    of the pipeline — from brainstorming to final draft.
    """
}
