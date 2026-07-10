// CosmoOS/Agent/Intelligence/ContentStrategyEngine.swift
// Proactive content strategy recommendations from swipe patterns + performance data

import Foundation

// MARK: - ContentStrategyEngine

/// Generates data-driven content strategy recommendations by cross-referencing
/// the user's swipe file library, published content performance, and idea pipeline.
/// All data sourced from GRDB via AtomRepository — no mocks or stubs.
@MainActor
class ContentStrategyEngine {

    // MARK: - Singleton

    static let shared = ContentStrategyEngine()

    // MARK: - Constants

    /// Days of the week labels for weekly plan slots
    private let weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Minimum swipes needed to consider a hook/framework combo statistically meaningful
    private let minimumSampleSize = 3

    /// Maximum recommendations per weekly plan
    private let maxWeeklyRecommendations = 7

    // MARK: - Init

    private init() {}

    // MARK: - 1. Generate Weekly Plan

    /// Creates 5-7 content recommendations for the upcoming week.
    /// Cross-references swipe patterns, published content performance, and ready ideas
    /// to recommend optimal hook+framework combos matched to specific ideas.
    func generateWeeklyPlan() async -> [ContentRecommendation] {
        // Gather all source data in parallel
        let swipes = await fetchSwipeLibrary()
        let published = await fetchPublishedContent()
        let readyIdeas = await fetchReadyIdeas()
        let performanceAtoms = await fetchPerformanceAtoms()
        let swipesByUUID = await inheritedSwipeLookup(for: published)

        // Build performance maps from published content
        let hookPerf = buildHookPerformanceMap(published: published, performanceAtoms: performanceAtoms, swipesByUUID: swipesByUUID)
        let frameworkPerf = buildFrameworkPerformanceMap(published: published, performanceAtoms: performanceAtoms)

        // Analyze swipe library distribution
        let swipeHookCounts = countSwipesByHookType(swipes)
        let swipeFrameworkCounts = countSwipesByFramework(swipes)

        // Track platform distribution to avoid monotony
        let publishedPlatformCounts = countPublishedByPlatform(published)

        // Score hook+framework combos
        let rankedCombos = rankHookFrameworkCombos(
            hookPerf: hookPerf,
            frameworkPerf: frameworkPerf,
            swipeHookCounts: swipeHookCounts,
            swipeFrameworkCounts: swipeFrameworkCounts
        )

        // Build recommendations by matching ideas to winning combos
        var recommendations: [ContentRecommendation] = []
        var usedIdeaUUIDs: Set<String> = []
        var usedPlatforms: [String: Int] = [:]

        for (dayIndex, combo) in rankedCombos.prefix(maxWeeklyRecommendations).enumerated() {
            let dayLabel = weekDays[dayIndex % weekDays.count]

            // Find the best matching idea for this combo
            let matchedIdea = findBestIdeaForCombo(
                hookType: combo.hookType,
                framework: combo.framework,
                ideas: readyIdeas,
                usedIdeaUUIDs: usedIdeaUUIDs
            )

            // Find matching swipes that demonstrate this combo
            let matchingSwipeUUIDs = findSwipesForCombo(
                hookType: combo.hookType,
                framework: combo.framework,
                swipes: swipes
            )

            // Determine platform — diversify across what the user publishes on
            let platform = selectPlatform(
                ideaPlatform: matchedIdea?.platformHint,
                currentDistribution: usedPlatforms,
                historicalDistribution: publishedPlatformCounts
            )

            // Estimate engagement based on historical performance
            let estimatedEngagement = estimateEngagement(
                hookPerf: hookPerf,
                frameworkPerf: frameworkPerf,
                hookType: combo.hookType,
                framework: combo.framework
            )

            // Build reasoning
            let reasoning = buildRecommendationReasoning(
                hookType: combo.hookType,
                framework: combo.framework,
                hookPerf: hookPerf[combo.hookType],
                frameworkPerf: frameworkPerf[combo.framework],
                matchedIdea: matchedIdea,
                swipeCount: matchingSwipeUUIDs.count
            )

            let topic = matchedIdea?.title ?? "Open slot — \(combo.hookType) + \(combo.framework)"

            let recommendation = ContentRecommendation(
                dayOfWeek: dayLabel,
                topic: topic,
                format: platform,
                hookType: combo.hookType,
                framework: combo.framework,
                reasoning: reasoning,
                matchingSwipeUUIDs: Array(matchingSwipeUUIDs.prefix(3)),
                matchingIdeaUUIDs: matchedIdea.map { [$0.uuid] } ?? [],
                estimatedEngagement: estimatedEngagement
            )

            recommendations.append(recommendation)

            if let idea = matchedIdea {
                usedIdeaUUIDs.insert(idea.uuid)
            }
            usedPlatforms[platform, default: 0] += 1
        }

        // If we have fewer than 5 recommendations, pad with open slots
        while recommendations.count < 5 {
            let dayLabel = weekDays[recommendations.count % weekDays.count]
            let topHook = hookPerf.max(by: { $0.value < $1.value })?.key ?? "curiosityGap"
            let topFramework = frameworkPerf.max(by: { $0.value < $1.value })?.key ?? "aida"

            recommendations.append(ContentRecommendation(
                dayOfWeek: dayLabel,
                topic: "Open slot — explore new angle",
                format: "twitter",
                hookType: topHook,
                framework: topFramework,
                reasoning: "Open slot to fill with fresh ideas. Your best-performing combo is \(topHook) + \(topFramework).",
                matchingSwipeUUIDs: [],
                matchingIdeaUUIDs: [],
                estimatedEngagement: 0.5
            ))
        }

        return recommendations
    }

    // MARK: - 2. Suggest Next Content

    /// Determines what the user should create right now based on pipeline state,
    /// idea readiness, and available time blocks.
    func suggestNextContent() async -> String {
        let contentAtoms = await fetchAllContent()
        let readyIdeas = await fetchReadyIdeas()

        // Priority 1: Content in polish phase (closest to done)
        let polishPhase = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .polish
        }

        if let closest = polishPhase.first {
            let title = closest.title ?? "Untitled"
            let wordCount = closest.metadataValue(as: ContentAtomMetadata.self)?.wordCount ?? 0
            return """
            Finish polishing "\(title)" (\(wordCount) words).
            This piece is in the polish phase and closest to publication. \
            A final editing pass could get it scheduled today.
            """
        }

        // Priority 2: Content in draft phase
        let draftPhase = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .draft
        }

        if let draft = draftPhase.first {
            let title = draft.title ?? "Untitled"
            let wordCount = draft.metadataValue(as: ContentAtomMetadata.self)?.wordCount ?? 0
            return """
            Continue drafting "\(title)" (\(wordCount) words so far).
            This draft is in progress — push it to the polish phase.
            """
        }

        // Priority 3: Content in ideation phase
        let ideationPhase = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .ideation
        }

        if let ideation = ideationPhase.first {
            let title = ideation.title ?? "Untitled"
            return """
            Develop the outline for "\(title)".
            This piece is in the ideation phase — flesh out the structure and start drafting.
            """
        }

        // Priority 4: Ready ideas waiting for activation
        if let topIdea = readyIdeas.first {
            let title = topIdea.title
            return """
            Activate idea "\(title)" into the content pipeline.
            You have \(readyIdeas.count) idea(s) ready for production. \
            This one is the most recently updated — promote it to a content piece.
            """
        }

        // Priority 5: Check for scheduled content (maybe post)
        let scheduledCount = contentAtoms.filter { atom in
            let meta = atom.metadataValue(as: ContentAtomMetadata.self)
            return meta?.phase == .scheduled
        }.count

        if scheduledCount > 0 {
            return """
            You have \(scheduledCount) piece(s) scheduled and ready to publish.
            Review and publish your scheduled content, then start a new piece.
            """
        }

        // Fallback: Start fresh
        let swipeCount = (try? await AtomRepository.shared.fetchAll(type: .research))?.filter({ $0.isSwipeFileAtom }).count ?? 0

        return """
        Your pipeline is clear — time to create something new.
        You have \(swipeCount) swipes in your library for inspiration. \
        Open the Ideas tab in Cmd+K and capture a fresh idea, or browse your swipe library for patterns.
        """
    }

    // MARK: - 3. Analyze Content Gap

    /// Identifies gaps in the user's content strategy by comparing their swipe library
    /// against published content, and detecting cadence issues.
    func analyzeContentGap() async -> String {
        let swipes = await fetchSwipeLibrary()
        let published = await fetchPublishedContent()

        guard !swipes.isEmpty else {
            return "Your swipe library is empty. Start saving swipe files to build your reference library — then I can analyze patterns and gaps."
        }

        var sections: [String] = []

        // Gap 1: Hook types in swipes but not in published content
        let swipeHookCounts = countSwipesByHookType(swipes)
        let swipesByUUID = await inheritedSwipeLookup(for: published)
        let publishedHookCounts = countPublishedByHookType(published, swipesByUUID: swipesByUUID)

        let underusedHooks = swipeHookCounts.filter { hookType, swipeCount in
            swipeCount >= minimumSampleSize && (publishedHookCounts[hookType] ?? 0) == 0
        }.sorted { $0.value > $1.value }

        if !underusedHooks.isEmpty {
            let hookList = underusedHooks.prefix(3).map { "\($0.key) (\($0.value) swipes saved)" }.joined(separator: ", ")
            sections.append("""
            UNTAPPED HOOK TYPES: You have swipes studying \(hookList) \
            but have never published content using these hooks. These are high-potential formats to experiment with.
            """)
        }

        // Gap 2: Framework types in swipes but not in published content
        let swipeFrameworkCounts = countSwipesByFramework(swipes)
        let publishedFrameworkCounts = countPublishedByFramework(published)

        let underusedFrameworks = swipeFrameworkCounts.filter { framework, swipeCount in
            swipeCount >= minimumSampleSize && (publishedFrameworkCounts[framework] ?? 0) == 0
        }.sorted { $0.value > $1.value }

        if !underusedFrameworks.isEmpty {
            let fwList = underusedFrameworks.prefix(3).map { "\($0.key) (\($0.value) swipes)" }.joined(separator: ", ")
            sections.append("""
            UNTESTED FRAMEWORKS: You have studied \(fwList) \
            but have not published content using them. Consider testing these structures.
            """)
        }

        // Gap 3: Platform cadence gaps
        let platformGaps = detectPlatformCadenceGaps(published)
        if !platformGaps.isEmpty {
            sections.append("CADENCE GAPS: " + platformGaps.joined(separator: " "))
        }

        // Gap 4: Ratio analysis
        let publishedCount = published.count
        let swipeCount = swipes.count
        if swipeCount > 0 && publishedCount > 0 {
            let ratio = Double(swipeCount) / Double(publishedCount)
            if ratio > 10 {
                sections.append("""
                CONSUMPTION VS CREATION: You have \(swipeCount) swipes but only \(publishedCount) published pieces \
                (ratio \(String(format: "%.0f", ratio)):1). Consider converting more study into output.
                """)
            }
        }

        // Gap 5: Overreliance on one hook type
        if let topHook = swipeHookCounts.max(by: { $0.value < $1.value }),
           swipes.count > 10 {
            let percentage = Double(topHook.value) / Double(swipes.count) * 100
            if percentage > 40 {
                sections.append("""
                HOOK CONCENTRATION: \(String(format: "%.0f", percentage))% of your swipes are \(topHook.key). \
                Diversify your study to avoid creative blind spots.
                """)
            }
        }

        if sections.isEmpty {
            return "No significant gaps detected. Your content strategy appears well-balanced across hooks, frameworks, and platforms."
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - 4. Predict Performance

    /// Scores a draft by comparing its hook type and framework against the user's
    /// historical performance patterns, plus basic readability analysis.
    func predictPerformance(
        draftBody: String,
        hookType: String?,
        framework: String?
    ) async -> AgentPerformancePrediction {
        let published = await fetchPublishedContent()
        let performanceAtoms = await fetchPerformanceAtoms()
        let swipesByUUID = await inheritedSwipeLookup(for: published)
        let hookPerf = buildHookPerformanceMap(published: published, performanceAtoms: performanceAtoms, swipesByUUID: swipesByUUID)
        let frameworkPerf = buildFrameworkPerformanceMap(published: published, performanceAtoms: performanceAtoms)

        // Hook score: how well does this hook type perform for the user?
        let hookScore: Double
        if let ht = hookType, let perfScore = hookPerf[ht] {
            hookScore = min(perfScore * 10, 10.0)  // Normalize to 0-10
        } else {
            hookScore = 5.0  // Neutral if unknown
        }

        // Framework score
        let frameworkScore: Double
        if let fw = framework, let perfScore = frameworkPerf[fw] {
            frameworkScore = min(perfScore * 10, 10.0)
        } else {
            frameworkScore = 5.0
        }

        // Readability analysis
        let readabilityResult = analyzeReadability(draftBody)

        // Overall score: weighted average
        let overallScore = (hookScore * 0.3 + frameworkScore * 0.3 + readabilityResult.score * 0.4)

        // Compare to user's average published performance
        let avgPerformance = computeAveragePerformance(performanceAtoms)
        let comparedToAverage = avgPerformance > 0 ? overallScore / avgPerformance : 1.0

        // Generate actionable suggestions
        var suggestions: [String] = []

        if hookScore < 5.0, let ht = hookType {
            let bestHook = hookPerf.max(by: { $0.value < $1.value })?.key ?? "curiosityGap"
            suggestions.append("Your \(ht) hooks have underperformed. Consider switching to \(bestHook) which is your strongest.")
        }

        if frameworkScore < 5.0, let fw = framework {
            let bestFramework = frameworkPerf.max(by: { $0.value < $1.value })?.key ?? "aida"
            suggestions.append("The \(fw) framework has lower engagement for you. Try \(bestFramework) instead.")
        }

        suggestions.append(contentsOf: readabilityResult.suggestions)

        if hookType == nil {
            suggestions.append("No hook type detected. Add a strong opening hook to boost engagement.")
        }

        if framework == nil {
            suggestions.append("No framework identified. Structure your content around a proven framework (AIDA, PAS, etc.) for better retention.")
        }

        return AgentPerformancePrediction(
            overallScore: min(max(overallScore, 0), 10),
            hookScore: hookScore,
            frameworkScore: frameworkScore,
            readabilityScore: readabilityResult.score,
            suggestions: suggestions,
            comparedToAverage: comparedToAverage
        )
    }

    // MARK: - Private Data Fetchers

    /// Fetch all published content atoms (phase == .published or .analyzing or .archived)
    private func fetchPublishedContent() async -> [Atom] {
        do {
            let allContent = try await AtomRepository.shared.fetchAll(type: .content)
            return allContent.filter { atom in
                guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { return false }
                return meta.phase == .published || meta.phase == .analyzing || meta.phase == .archived
            }
        } catch {
            return []
        }
    }

    /// Fetch all content atoms regardless of phase
    private func fetchAllContent() async -> [Atom] {
        do {
            return try await AtomRepository.shared.fetchAll(type: .content)
        } catch {
            return []
        }
    }

    /// Fetch all research atoms that are swipe files
    private func fetchSwipeLibrary() async -> [Atom] {
        do {
            let allResearch = try await AtomRepository.shared.fetchAll(type: .research)
            return allResearch.filter { $0.isSwipeFileAtom }
        } catch {
            return []
        }
    }

    /// Fetch idea atoms in developing or ready status
    private func fetchReadyIdeas() async -> [(uuid: String, title: String, platformHint: String?)] {
        do {
            let allIdeas = try await AtomRepository.shared.fetchAll(type: .idea)
            return allIdeas.compactMap { atom in
                guard let meta = atom.metadataValue(as: IdeaMetadata.self) else { return nil }
                let status = meta.ideaStatus
                guard status == .developing || status == .ready else { return nil }
                let title = atom.title ?? (atom.body ?? "Untitled idea")
                let platform = meta.platform?.rawValue
                return (uuid: atom.uuid, title: title, platformHint: platform)
            }
        } catch {
            return []
        }
    }

    /// Fetch content performance atoms for engagement analysis
    private func fetchPerformanceAtoms() async -> [Atom] {
        do {
            return try await AtomRepository.shared.fetchAll(type: .contentPerformance)
        } catch {
            return []
        }
    }

    // MARK: - Private Hook/Framework Analysis

    /// Build a map of hook type -> average engagement rate from published content + performance atoms.
    /// Links performance atoms back to their parent content via metadata.
    private func buildHookPerformanceMap(
        published: [Atom],
        performanceAtoms: [Atom],
        swipesByUUID: [String: Atom]
    ) -> [String: Double] {
        // Build a map from content UUID -> engagement rate
        var contentEngagement: [String: [Double]] = [:]
        for perfAtom in performanceAtoms {
            if let meta = perfAtom.metadataValue(as: ContentPerformanceMetadata.self) {
                let parentUUID = perfAtom.metadataDict?["contentAtomUUID"] as? String ?? ""
                if !parentUUID.isEmpty {
                    contentEngagement[parentUUID, default: []].append(meta.engagementRate)
                }
            }
        }

        // Map content atoms to their hook type, then aggregate engagement
        var hookEngagements: [String: [Double]] = [:]
        for contentAtom in published {
            guard let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self) else { continue }

            // Try to determine hook type from inherited hooks or swipe analysis
            let hookType = resolveHookType(for: contentAtom, contentMeta: contentMeta, swipesByUUID: swipesByUUID)
            guard let hook = hookType else { continue }

            let engagements = contentEngagement[contentAtom.uuid] ?? []
            if !engagements.isEmpty {
                hookEngagements[hook, default: []].append(contentsOf: engagements)
            }
        }

        // Average engagement per hook type, normalized to 0-1
        var result: [String: Double] = [:]
        for (hook, rates) in hookEngagements where rates.count >= 1 {
            let avg = rates.reduce(0, +) / Double(rates.count)
            result[hook] = min(avg / 100.0, 1.0)  // Convert percentage to 0-1
        }
        return result
    }

    /// Build a map of framework type -> average engagement rate
    private func buildFrameworkPerformanceMap(
        published: [Atom],
        performanceAtoms: [Atom]
    ) -> [String: Double] {
        var contentEngagement: [String: [Double]] = [:]
        for perfAtom in performanceAtoms {
            if let meta = perfAtom.metadataValue(as: ContentPerformanceMetadata.self) {
                let parentUUID = perfAtom.metadataDict?["contentAtomUUID"] as? String ?? ""
                if !parentUUID.isEmpty {
                    contentEngagement[parentUUID, default: []].append(meta.engagementRate)
                }
            }
        }

        var frameworkEngagements: [String: [Double]] = [:]
        for contentAtom in published {
            guard let contentMeta = contentAtom.metadataValue(as: ContentAtomMetadata.self) else { continue }
            let framework = contentMeta.inheritedFramework
            guard let fw = framework, !fw.isEmpty else { continue }

            let engagements = contentEngagement[contentAtom.uuid] ?? []
            if !engagements.isEmpty {
                frameworkEngagements[fw, default: []].append(contentsOf: engagements)
            }
        }

        var result: [String: Double] = [:]
        for (fw, rates) in frameworkEngagements where rates.count >= 1 {
            let avg = rates.reduce(0, +) / Double(rates.count)
            result[fw] = min(avg / 100.0, 1.0)
        }
        return result
    }

    /// Attempt to resolve the hook type for a content atom by checking inherited hooks
    /// or linked swipe analyses. `swipesByUUID` is batch-fetched once per analysis pass
    /// via `inheritedSwipeLookup(for:)`.
    private func resolveHookType(
        for atom: Atom,
        contentMeta: ContentAtomMetadata,
        swipesByUUID: [String: Atom]
    ) -> String? {
        // Check inherited hooks from idea activation
        if let hooks = contentMeta.inheritedHooks, let first = hooks.first {
            return first
        }

        // Check linked swipe UUIDs and use their hook type
        if let swipeUUIDs = contentMeta.inheritedSwipeUUIDs, let firstUUID = swipeUUIDs.first {
            if let swipeAtom = swipesByUUID[firstUUID],
               let analysis = swipeAtom.swipeAnalysis {
                return analysis.hookType?.rawValue
            }
        }

        return nil
    }

    /// Batch-load every swipe atom referenced by the published atoms' inherited
    /// swipe UUIDs. One query per analysis pass instead of an in-memory mirror
    /// of the whole atoms table.
    private func inheritedSwipeLookup(for published: [Atom]) async -> [String: Atom] {
        var uuids: Set<String> = []
        for atom in published {
            if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
               let swipeUUIDs = meta.inheritedSwipeUUIDs,
               let first = swipeUUIDs.first {
                uuids.insert(first)
            }
        }
        guard !uuids.isEmpty else { return [:] }
        let atoms = (try? await AtomRepository.shared.fetchBatch(uuids: Array(uuids))) ?? []
        return Dictionary(atoms.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Private Counting Helpers

    private func countSwipesByHookType(_ swipes: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for swipe in swipes {
            if let analysis = swipe.swipeAnalysis, let hookType = analysis.hookType {
                counts[hookType.rawValue, default: 0] += 1
            }
        }
        return counts
    }

    private func countSwipesByFramework(_ swipes: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for swipe in swipes {
            if let analysis = swipe.swipeAnalysis, let framework = analysis.frameworkType {
                counts[framework.rawValue, default: 0] += 1
            }
        }
        return counts
    }

    private func countPublishedByPlatform(_ published: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for atom in published {
            if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
               let platform = meta.platform {
                counts[platform.rawValue, default: 0] += 1
            }
        }
        return counts
    }

    private func countPublishedByHookType(_ published: [Atom], swipesByUUID: [String: Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for atom in published {
            if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
               let hook = resolveHookType(for: atom, contentMeta: meta, swipesByUUID: swipesByUUID) {
                counts[hook, default: 0] += 1
            }
        }
        return counts
    }

    private func countPublishedByFramework(_ published: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for atom in published {
            if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
               let fw = meta.inheritedFramework, !fw.isEmpty {
                counts[fw, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Private Combo Ranking

    /// Represents a hook + framework combination with a combined score
    private struct HookFrameworkCombo {
        let hookType: String
        let framework: String
        let score: Double
    }

    /// Rank all hook+framework combos by combined performance score.
    /// Combos with both performance data and swipe references score highest.
    private func rankHookFrameworkCombos(
        hookPerf: [String: Double],
        frameworkPerf: [String: Double],
        swipeHookCounts: [String: Int],
        swipeFrameworkCounts: [String: Int]
    ) -> [HookFrameworkCombo] {
        var combos: [HookFrameworkCombo] = []

        let hookTypes = Array(Set(Array(hookPerf.keys) + Array(swipeHookCounts.keys)))
        let frameworks = Array(Set(Array(frameworkPerf.keys) + Array(swipeFrameworkCounts.keys)))

        for hook in hookTypes {
            for fw in frameworks {
                // Performance component (0-1): average of hook and framework performance
                let hookPerfScore = hookPerf[hook] ?? 0.3  // Default to 0.3 for untested hooks
                let fwPerfScore = frameworkPerf[fw] ?? 0.3
                let perfScore = (hookPerfScore + fwPerfScore) / 2.0

                // Reference component: do we have swipes to study?
                let hookRefScore = min(Double(swipeHookCounts[hook] ?? 0) / 10.0, 1.0)
                let fwRefScore = min(Double(swipeFrameworkCounts[fw] ?? 0) / 10.0, 1.0)
                let refScore = (hookRefScore + fwRefScore) / 2.0

                // Novelty bonus: slightly boost untested combos to encourage experimentation
                let noveltyBonus: Double = (hookPerf[hook] == nil || frameworkPerf[fw] == nil) ? 0.1 : 0.0

                let totalScore = perfScore * 0.6 + refScore * 0.3 + noveltyBonus

                combos.append(HookFrameworkCombo(
                    hookType: hook,
                    framework: fw,
                    score: totalScore
                ))
            }
        }

        // Sort descending by score, deduplicate by hook type (prefer diversity)
        let sorted = combos.sorted { $0.score > $1.score }
        var result: [HookFrameworkCombo] = []
        var usedHooks: Set<String> = []

        for combo in sorted {
            // Allow at most 2 recommendations per hook type
            let hookUsageCount = result.filter { $0.hookType == combo.hookType }.count
            if hookUsageCount < 2 {
                result.append(combo)
                usedHooks.insert(combo.hookType)
            }
            if result.count >= maxWeeklyRecommendations {
                break
            }
        }

        return result
    }

    // MARK: - Private Matching Helpers

    private func findBestIdeaForCombo(
        hookType: String,
        framework: String,
        ideas: [(uuid: String, title: String, platformHint: String?)],
        usedIdeaUUIDs: Set<String>
    ) -> (uuid: String, title: String, platformHint: String?)? {
        // Return the first available idea not yet used
        // In the future, this could use semantic similarity to match ideas to combos
        return ideas.first { !usedIdeaUUIDs.contains($0.uuid) }
    }

    private func findSwipesForCombo(
        hookType: String,
        framework: String,
        swipes: [Atom]
    ) -> [String] {
        return swipes.compactMap { atom in
            guard let analysis = atom.swipeAnalysis else { return nil }
            let matchesHook = analysis.hookType?.rawValue == hookType
            let matchesFramework = analysis.frameworkType?.rawValue == framework
            if matchesHook || matchesFramework {
                return atom.uuid
            }
            return nil
        }
    }

    private func selectPlatform(
        ideaPlatform: String?,
        currentDistribution: [String: Int],
        historicalDistribution: [String: Int]
    ) -> String {
        // If idea has a platform hint, prefer it
        if let platform = ideaPlatform, !platform.isEmpty {
            return platform
        }

        // Otherwise, pick from the user's historical platforms, preferring less-used in current plan
        let candidates = historicalDistribution.sorted { $0.value > $1.value }
        for (platform, _) in candidates {
            if (currentDistribution[platform] ?? 0) < 2 {
                return platform
            }
        }

        return "twitter"  // Fallback
    }

    private func estimateEngagement(
        hookPerf: [String: Double],
        frameworkPerf: [String: Double],
        hookType: String,
        framework: String
    ) -> Double {
        let hookEng = hookPerf[hookType] ?? 0.3
        let fwEng = frameworkPerf[framework] ?? 0.3
        return (hookEng + fwEng) / 2.0
    }

    private func buildRecommendationReasoning(
        hookType: String,
        framework: String,
        hookPerf: Double?,
        frameworkPerf: Double?,
        matchedIdea: (uuid: String, title: String, platformHint: String?)?,
        swipeCount: Int
    ) -> String {
        var parts: [String] = []

        if let hp = hookPerf {
            let pct = String(format: "%.0f", hp * 100)
            parts.append("\(hookType) hooks have a \(pct)% relative engagement score for you")
        } else {
            parts.append("\(hookType) is untested — good opportunity to experiment")
        }

        if let fp = frameworkPerf {
            let pct = String(format: "%.0f", fp * 100)
            parts.append("\(framework) framework scores \(pct)% engagement")
        }

        if swipeCount > 0 {
            parts.append("\(swipeCount) reference swipe(s) available for study")
        }

        if let idea = matchedIdea {
            parts.append("Matched to idea: \"\(idea.title)\"")
        }

        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Private Cadence Detection

    /// Detect platforms where the user has not published recently
    private func detectPlatformCadenceGaps(_ published: [Atom]) -> [String] {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        var gaps: [String] = []

        // Group published content by platform with most recent date
        var latestByPlatform: [String: Date] = [:]

        for atom in published {
            guard let meta = atom.metadataValue(as: ContentAtomMetadata.self),
                  let platform = meta.platform else { continue }

            // Use updatedAt as a proxy for publish date (both are non-optional String)
            let dateStr = atom.updatedAt
            if let date = dateFormatter.date(from: dateStr) {
                let key = platform.displayName
                if latestByPlatform[key] == nil || date > latestByPlatform[key]! {
                    latestByPlatform[key] = date
                }
            }
        }

        for (platform, lastDate) in latestByPlatform {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: now).day ?? 0
            if daysSince >= 5 {
                gaps.append("No \(platform) posts in \(daysSince) days.")
            }
        }

        return gaps
    }

    // MARK: - Private Readability Analysis

    private struct ReadabilityResult {
        let score: Double  // 0-10
        let suggestions: [String]
    }

    /// Basic on-device readability check: sentence length, word count, paragraph structure
    private func analyzeReadability(_ text: String) -> ReadabilityResult {
        guard !text.isEmpty else {
            return ReadabilityResult(score: 0, suggestions: ["Draft is empty. Start writing to get a readability score."])
        }

        var suggestions: [String] = []
        var score = 7.0  // Start at a good baseline

        let words = text.split(separator: " ")
        let wordCount = words.count

        // Sentence analysis
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sentenceCount = max(sentences.count, 1)
        let avgSentenceLength = Double(wordCount) / Double(sentenceCount)

        // Penalize very long average sentences
        if avgSentenceLength > 25 {
            score -= 1.5
            suggestions.append("Average sentence length is \(Int(avgSentenceLength)) words. Aim for under 20 for better readability.")
        } else if avgSentenceLength > 20 {
            score -= 0.5
            suggestions.append("Sentences average \(Int(avgSentenceLength)) words — consider tightening a few.")
        }

        // Penalize very short content (might be incomplete)
        if wordCount < 50 {
            score -= 1.0
            suggestions.append("Only \(wordCount) words. Most engaging posts are 100-300 words.")
        } else if wordCount > 500 {
            score -= 0.5
            suggestions.append("\(wordCount) words is on the longer side. Consider if all sections are essential.")
        }

        // Paragraph structure check (newline-separated)
        let paragraphs = text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if paragraphs.count <= 1 && wordCount > 100 {
            score -= 1.0
            suggestions.append("Content reads as a single block. Break it into paragraphs for better scannability.")
        }

        // Check for opening hook (first sentence length)
        if let firstSentence = sentences.first {
            let firstWords = firstSentence.split(separator: " ").count
            if firstWords > 15 {
                score -= 0.5
                suggestions.append("Opening line is \(firstWords) words. Shorter hooks (under 10 words) grab attention faster.")
            }
        }

        return ReadabilityResult(score: min(max(score, 0), 10), suggestions: suggestions)
    }

    /// Compute the average performance score across all performance atoms
    private func computeAveragePerformance(_ performanceAtoms: [Atom]) -> Double {
        var rates: [Double] = []
        for atom in performanceAtoms {
            if let meta = atom.metadataValue(as: ContentPerformanceMetadata.self) {
                rates.append(meta.engagementRate)
            }
        }
        guard !rates.isEmpty else { return 5.0 }
        let avg = rates.reduce(0, +) / Double(rates.count)
        return min(avg / 100.0 * 10, 10.0)  // Normalize percentage to 0-10 scale
    }
}
