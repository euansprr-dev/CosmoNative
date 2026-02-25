// CosmoOS/Agent/Intelligence/PersuasionCoachEngine.swift
// Coaches the user on persuasion techniques based on swipe analysis data
// Compares drafts against the user's swipe library to suggest improvements.

import Foundation

@MainActor
class PersuasionCoachEngine {
    static let shared = PersuasionCoachEngine()

    private let atomRepo = AtomRepository.shared

    /// Keyword indicators for each persuasion type, used for draft analysis.
    private let persuasionKeywords: [PersuasionType: [String]] = [
        .socialProof: [
            "everyone", "thousands", "millions", "most people", "trending",
            "followers", "subscribers", "reviews", "testimonial", "clients",
            "customers", "users", "community", "joined", "popular"
        ],
        .curiosityGap: [
            "secret", "hidden", "surprising", "unexpected", "you won't believe",
            "little-known", "most people don't know", "the truth about",
            "what nobody tells you", "here's why", "the real reason"
        ],
        .contrastEffect: [
            "but", "however", "instead", "while most", "on the other hand",
            "compared to", "unlike", "the difference", "versus", "vs"
        ],
        .authority: [
            "expert", "research shows", "according to", "study", "harvard",
            "scientist", "proven", "data shows", "evidence", "published",
            "years of experience", "PhD", "professor", "certified"
        ],
        .scarcity: [
            "limited", "only", "exclusive", "rare", "few spots", "running out",
            "last chance", "while supplies last", "one-time", "never again"
        ],
        .urgency: [
            "now", "today", "immediately", "hurry", "don't wait", "deadline",
            "time-sensitive", "act fast", "before it's too late", "right now",
            "this week only", "expires"
        ],
        .reciprocity: [
            "free", "gift", "bonus", "complimentary", "no cost", "my treat",
            "here's a", "I'll share", "giving away", "take this"
        ],
        .storytelling: [
            "once upon", "I remember", "let me tell you", "picture this",
            "imagine", "here's what happened", "true story", "back when",
            "the day I", "years ago", "growing up"
        ],
        .lossAversion: [
            "miss out", "lose", "risk", "cost you", "don't make this mistake",
            "failing to", "without this", "the problem is", "what you're missing"
        ],
        .exclusivity: [
            "insider", "behind the scenes", "vip", "members only", "private",
            "invitation only", "select few", "inner circle", "not for everyone"
        ],
        .anchoring: [
            "originally", "was $", "normally", "compare that to", "worth",
            "valued at", "retail price", "for just", "only $", "fraction"
        ],
        .framing: [
            "think of it this way", "in other words", "what this means",
            "the way I see it", "perspective", "reframe", "look at it",
            "consider this", "another way to think about"
        ]
    ]

    private init() {}

    // MARK: - Review Draft

    /// Analyze a draft for persuasion techniques and compare against
    /// the user's top-performing persuasion stacks.
    func reviewDraft(text: String) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No draft text provided to review."
        }

        let detected = detectPersuasionInText(text)
        let topStacks = await getTopPerformingPersuasionStacks()

        var lines: [String] = ["## Persuasion Review"]

        // Report detected techniques
        if detected.isEmpty {
            lines.append("")
            lines.append("No clear persuasion techniques detected in this draft. Consider adding at least 2-3 techniques for stronger impact.")
        } else {
            lines.append("")
            lines.append("**Detected Techniques (\(detected.count)):**")
            for technique in detected {
                if let pType = PersuasionType(rawValue: technique) {
                    lines.append("- \(pType.displayName)")
                } else {
                    lines.append("- \(technique)")
                }
            }
        }

        // Compare against top-performing stacks
        if !topStacks.isEmpty {
            lines.append("")
            lines.append("**Your Best-Performing Persuasion Stacks:**")
            for (index, stack) in topStacks.prefix(3).enumerated() {
                let names = stack.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }
                lines.append("\(index + 1). \(names.joined(separator: " + "))")
            }

            // Find missing techniques from top stacks
            let detectedSet = Set(detected)
            let allTopTechniques = Set(topStacks.flatMap { $0 })
            let missing = allTopTechniques.subtracting(detectedSet)

            if !missing.isEmpty {
                let missingNames = missing.prefix(3).compactMap {
                    PersuasionType(rawValue: $0)?.displayName ?? $0
                }
                lines.append("")
                lines.append("**Suggestions:**")
                lines.append("This draft uses \(detected.isEmpty ? "no detected techniques" : detected.compactMap { PersuasionType(rawValue: $0)?.displayName }.joined(separator: ", ")).")
                lines.append("Your best content typically includes: \(missingNames.joined(separator: ", ")).")
                lines.append("Consider adding these for stronger engagement.")
            }
        }

        // Text-level suggestions
        let wordCount = text.split(separator: " ").count
        if wordCount < 50 {
            lines.append("")
            lines.append("**Note:** This draft is short (\(wordCount) words). Short-form content benefits from 2-3 concentrated techniques.")
        } else if wordCount > 500 {
            lines.append("")
            lines.append("**Note:** This is a longer piece (\(wordCount) words). Layer multiple techniques throughout, with the strongest at the hook and CTA.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Suggest Persuasion Stack

    /// Recommend persuasion techniques based on topic and platform,
    /// cross-referenced with similar swipes in the library.
    func suggestPersuasionStack(topic: String, platform: String) async -> String {
        var lines: [String] = ["## Recommended Persuasion Stack"]
        lines.append("**Topic:** \(topic)")
        lines.append("**Platform:** \(platform)")

        do {
            // Find swipes with matching topics
            let researchAtoms = try await atomRepo.fetchAll(type: .research)
            let swipeAtoms = researchAtoms.filter { $0.isSwipeFileAtom }

            let topicLower = topic.lowercased()
            let topicWords = Set(topicLower.components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 })

            // Find relevant swipes by title/body keyword overlap
            let relevantSwipes = swipeAtoms.filter { atom in
                let atomText = ((atom.title ?? "") + " " + (atom.body ?? "")).lowercased()
                return topicWords.contains(where: { atomText.contains($0) })
            }

            // Collect persuasion types from relevant swipes
            var persuasionCounts: [String: Int] = [:]
            for atom in relevantSwipes {
                if let analysis = atom.swipeAnalysis,
                   let techniques = analysis.persuasionTechniques {
                    for technique in techniques {
                        persuasionCounts[technique.type.rawValue, default: 0] += 1
                    }
                }
            }

            if !persuasionCounts.isEmpty {
                let sorted = persuasionCounts.sorted { $0.value > $1.value }
                let topTechniques = sorted.prefix(3).map { $0.key }
                let names = topTechniques.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }

                lines.append("")
                lines.append("Based on \(relevantSwipes.count) similar swipes in your library:")
                lines.append("")
                lines.append("**Recommended Stack:** \(names.joined(separator: " + "))")
                lines.append("")
                lines.append("**Breakdown:**")
                for (rawValue, count) in sorted.prefix(5) {
                    let name = PersuasionType(rawValue: rawValue)?.displayName ?? rawValue
                    lines.append("- \(name): used in \(count) similar swipes")
                }
            } else if !swipeAtoms.isEmpty {
                // No topic match, fall back to overall library stats
                lines.append("")
                lines.append("No swipes closely matching '\(topic)' found. Here's a general recommendation based on your full swipe library:")

                let allPersuasionCounts = countAllPersuasionTypes(swipeAtoms)
                let sorted = allPersuasionCounts.sorted { $0.value > $1.value }
                let topTechniques = sorted.prefix(3).map { $0.key }
                let names = topTechniques.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }

                lines.append("")
                lines.append("**Recommended Stack:** \(names.joined(separator: " + "))")
            } else {
                lines.append("")
                lines.append("Your swipe library is empty. Save some swipe files to get personalized recommendations.")
                lines.append("")
                lines.append("**General recommendation for \(platform):**")
                lines.append("Curiosity Gap + Social Proof + Storytelling")
            }

            // Platform-specific tips
            lines.append("")
            lines.append(platformTip(platform))

        } catch {
            lines.append("")
            lines.append("Could not access swipe library: \(error.localizedDescription)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Compare to Swipe

    /// Compare a draft against a reference swipe file.
    func compareToSwipe(draftText: String, swipeUUID: String) async -> String {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No draft text provided for comparison."
        }

        do {
            guard let swipeAtom = try await atomRepo.fetch(uuid: swipeUUID) else {
                return "Swipe file not found (UUID: \(swipeUUID))."
            }

            guard let swipeAnalysis = swipeAtom.swipeAnalysis else {
                return "This swipe file has no analysis data. Run analysis first."
            }

            let swipeTitle = swipeAtom.title ?? "Reference Swipe"
            var lines: [String] = ["## Draft vs \"\(swipeTitle)\""]

            // Hook comparison
            let draftHookText = extractHook(from: draftText)
            let draftHookWords = draftHookText.split(separator: " ").count
            let swipeHookWords = swipeAnalysis.hookWordCount ?? (swipeAnalysis.hookText?.split(separator: " ").count ?? 0)

            lines.append("")
            lines.append("**Hook Comparison:**")
            lines.append("- Your hook: \(draftHookWords) words")
            lines.append("- Reference hook: \(swipeHookWords) words")

            if swipeHookWords > 0 && draftHookWords > 0 {
                let ratio = Double(draftHookWords) / Double(swipeHookWords)
                if ratio > 1.3 {
                    lines.append("- Your hook is \(String(format: "%.0f%%", (ratio - 1) * 100)) longer. Consider tightening it.")
                } else if ratio < 0.7 {
                    lines.append("- Your hook is \(String(format: "%.0f%%", (1 - ratio) * 100)) shorter. It may benefit from more context.")
                } else {
                    lines.append("- Hook lengths are comparable.")
                }
            }

            if let hookType = swipeAnalysis.hookType {
                lines.append("- Reference uses a \(hookType.displayName) hook")
                if let hookScore = swipeAnalysis.hookScore {
                    lines.append("  (scored \(String(format: "%.1f", hookScore))/10)")
                }
            }

            // Data points comparison
            let draftDataPoints = countDataPoints(in: draftText)
            let swipeBody = swipeAtom.body ?? ""
            let swipeDataPoints = countDataPoints(in: swipeBody)

            lines.append("")
            lines.append("**Data Points:**")
            lines.append("- Your draft: \(draftDataPoints) data points")
            lines.append("- Reference: \(swipeDataPoints) data points")
            if swipeDataPoints > draftDataPoints {
                lines.append("- Consider adding \(swipeDataPoints - draftDataPoints) more specific numbers, stats, or examples.")
            }

            // Persuasion technique comparison
            let draftPersuasion = detectPersuasionInText(draftText)
            let swipePersuasion = swipeAnalysis.persuasionTechniques?.map { $0.type.rawValue } ?? []

            lines.append("")
            lines.append("**Persuasion Techniques:**")
            let draftNames = draftPersuasion.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }
            let swipeNames = swipePersuasion.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }
            lines.append("- Your draft: \(draftNames.isEmpty ? "none detected" : draftNames.joined(separator: ", "))")
            lines.append("- Reference: \(swipeNames.isEmpty ? "none analyzed" : swipeNames.joined(separator: ", "))")

            let missingPersuasion = Set(swipePersuasion).subtracting(Set(draftPersuasion))
            if !missingPersuasion.isEmpty {
                let missingNames = missingPersuasion.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }
                lines.append("- Missing from your draft: \(missingNames.joined(separator: ", "))")
            }

            // Structure comparison
            let draftWordCount = draftText.split(separator: " ").count
            let swipeWordCount = swipeBody.split(separator: " ").count

            lines.append("")
            lines.append("**Structure:**")
            lines.append("- Your draft: \(draftWordCount) words")
            lines.append("- Reference: \(swipeWordCount) words")

            if let sections = swipeAnalysis.sections, !sections.isEmpty {
                lines.append("- Reference has \(sections.count) sections: \(sections.map { $0.label }.joined(separator: " -> "))")
            }

            if let framework = swipeAnalysis.frameworkType {
                lines.append("- Reference framework: \(framework.displayName) (\(framework.description))")
            }

            return lines.joined(separator: "\n")
        } catch {
            return "Error comparing to swipe: \(error.localizedDescription)"
        }
    }

    // MARK: - Persuasion Library Stats

    /// Overview of persuasion types across the entire swipe library.
    func getPersuasionLibraryStats() async -> String {
        do {
            let researchAtoms = try await atomRepo.fetchAll(type: .research)
            let swipeAtoms = researchAtoms.filter { $0.isSwipeFileAtom }

            guard !swipeAtoms.isEmpty else {
                return "Your swipe library is empty. Save some swipe files to see persuasion stats."
            }

            let analyzedSwipes = swipeAtoms.filter { $0.swipeAnalysis?.isFullyAnalyzed == true }

            var lines: [String] = ["## Persuasion Library Stats"]
            lines.append("Total swipes: \(swipeAtoms.count)")
            lines.append("Fully analyzed: \(analyzedSwipes.count)")

            // Count persuasion types across all swipes
            let persuasionCounts = countAllPersuasionTypes(swipeAtoms)
            let totalTechniqueInstances = persuasionCounts.values.reduce(0, +)

            if persuasionCounts.isEmpty {
                lines.append("")
                lines.append("No persuasion techniques found in analyzed swipes. Run full analysis on your swipe files first.")
                return lines.joined(separator: "\n")
            }

            lines.append("Total technique instances: \(totalTechniqueInstances)")
            lines.append("")
            lines.append("**Technique Distribution:**")

            let sorted = persuasionCounts.sorted { $0.value > $1.value }
            for (rawValue, count) in sorted {
                let name = PersuasionType(rawValue: rawValue)?.displayName ?? rawValue
                let pct = String(format: "%.1f%%", Double(count) / Double(totalTechniqueInstances) * 100)
                let bar = String(repeating: "#", count: min(20, Int(Double(count) / Double(totalTechniqueInstances) * 20)))
                lines.append("  \(name): \(count) (\(pct)) \(bar)")
            }

            // Most common combinations
            let topStacks = await getTopPerformingPersuasionStacks()
            if !topStacks.isEmpty {
                lines.append("")
                lines.append("**Most Common Combinations:**")
                for (index, stack) in topStacks.prefix(5).enumerated() {
                    let names = stack.compactMap { PersuasionType(rawValue: $0)?.displayName ?? $0 }
                    lines.append("\(index + 1). \(names.joined(separator: " + "))")
                }
            }

            return lines.joined(separator: "\n")
        } catch {
            return "Error loading swipe library: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    /// Simple keyword-based persuasion detection in text.
    private func detectPersuasionInText(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var detected: [String] = []

        for (pType, keywords) in persuasionKeywords {
            let matchCount = keywords.filter { lowered.contains($0) }.count
            // Require at least 2 keyword matches for confidence, or 1 for a strong indicator
            let strongIndicators = keywords.filter { $0.split(separator: " ").count > 2 }
            let hasStrong = strongIndicators.contains { lowered.contains($0) }

            if matchCount >= 2 || hasStrong {
                detected.append(pType.rawValue)
            }
        }

        return detected
    }

    /// Find the most common persuasion technique combinations in top swipes.
    private func getTopPerformingPersuasionStacks() async -> [[String]] {
        do {
            let researchAtoms = try await atomRepo.fetchAll(type: .research)
            let swipeAtoms = researchAtoms.filter { $0.isSwipeFileAtom }

            // Get swipes sorted by hook score (proxy for quality)
            let scoredSwipes = swipeAtoms
                .compactMap { atom -> (score: Double, techniques: [String])? in
                    guard let analysis = atom.swipeAnalysis,
                          let techniques = analysis.persuasionTechniques,
                          !techniques.isEmpty else { return nil }
                    let score = analysis.effectiveHookScore
                    let techNames = techniques.map { $0.type.rawValue }
                    return (score: score, techniques: techNames)
                }
                .sorted { $0.score > $1.score }

            // Take stacks from top-scoring swipes
            let topStacks = scoredSwipes.prefix(10).map { $0.techniques }

            // Count combination frequency
            var stackCounts: [String: (count: Int, stack: [String])] = [:]
            for stack in topStacks {
                let sorted = stack.sorted()
                let key = sorted.joined(separator: "+")
                if stackCounts[key] != nil {
                    stackCounts[key]!.count += 1
                } else {
                    stackCounts[key] = (count: 1, stack: sorted)
                }
            }

            // Return by frequency
            return stackCounts.values
                .sorted { $0.count > $1.count }
                .map { $0.stack }
        } catch {
            return []
        }
    }

    /// Count all persuasion types across a set of swipe atoms.
    private func countAllPersuasionTypes(_ swipeAtoms: [Atom]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for atom in swipeAtoms {
            if let analysis = atom.swipeAnalysis,
               let techniques = analysis.persuasionTechniques {
                for technique in techniques {
                    counts[technique.type.rawValue, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// Extract the first sentence or line as the "hook" from a draft.
    private func extractHook(from text: String) -> String {
        // Try to get the first sentence (ending in . ! ?)
        let sentencePattern = "^[^.!?]+[.!?]"
        if let range = text.range(of: sentencePattern, options: .regularExpression) {
            return String(text[range])
        }
        // Fallback: first line
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        return String(firstLine.prefix(200))
    }

    /// Count data points (numbers, statistics, percentages) in text.
    private func countDataPoints(in text: String) -> Int {
        // Match patterns: "42%", "$100", "3x", "1,000", "10.5", standalone numbers
        let patterns = [
            "\\d+%",           // Percentages
            "\\$[\\d,]+",      // Dollar amounts
            "\\d+x\\b",       // Multipliers
            "\\d{1,3}(,\\d{3})+", // Comma-separated numbers
            "\\b\\d+\\.\\d+\\b",  // Decimal numbers
        ]

        var count = 0
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                count += regex.numberOfMatches(in: text, options: [], range: range)
            }
        }
        return count
    }

    /// Platform-specific persuasion tips.
    private func platformTip(_ platform: String) -> String {
        let platformLower = platform.lowercased()
        switch platformLower {
        case "instagram":
            return "**Instagram tip:** Lead with Curiosity Gap or Social Proof in the first line. Saves correlate with Storytelling + Authority stacks."
        case "youtube":
            return "**YouTube tip:** Thumbnails/titles need Curiosity Gap + Contrast Effect. Retention benefits from Storytelling + Loss Aversion."
        case "tiktok":
            return "**TikTok tip:** First 3 seconds are everything. Use Bold Claim or Contrast Effect. Urgency drives shares."
        case "x", "twitter":
            return "**X tip:** Authority + Specificity drives engagement. Threads benefit from Curiosity Gap hooks with Storytelling payoff."
        case "linkedin":
            return "**LinkedIn tip:** Authority + Social Proof performs best. Open with a personal story, close with a lesson."
        default:
            return "**General tip:** Combine 2-3 complementary techniques. Open with engagement-drivers (Curiosity, Social Proof) and close with action-drivers (Urgency, Loss Aversion)."
        }
    }
}
