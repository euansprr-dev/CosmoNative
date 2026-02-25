// CosmoOS/Agent/Intelligence/CreatorStyleProfiler.swift
// Builds a living profile of the user's creative DNA
// Analyzes published content, swipe library, and creation patterns
// to produce a CreatorTasteProfile used across the Agent system.

import Foundation

@MainActor
class CreatorStyleProfiler {
    static let shared = CreatorStyleProfiler()

    private let atomRepo = AtomRepository.shared
    private let profileScope = "creator_profile"

    private init() {}

    // MARK: - Build Profile

    /// Analyze ALL published content + swipe library to build a comprehensive creator profile.
    /// Stores the result as a `.userPreference` atom for future retrieval.
    func buildProfile() async -> CreatorTasteProfile {
        do {
            // Fetch published content atoms
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let publishedContent = contentAtoms.filter { atom in
                guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { return false }
                return meta.phase == .published || meta.phase == .analyzing || meta.phase == .archived
            }

            // Fetch all research atoms that are swipe files
            let researchAtoms = try await atomRepo.fetchAll(type: .research)
            let swipeAtoms = researchAtoms.filter { $0.isSwipeFileAtom }

            // Fetch idea atoms for topic extraction
            let ideaAtoms = try await atomRepo.fetchAll(type: .idea)

            // 1. Voice fingerprint from published content
            let publishedTexts = publishedContent.compactMap { $0.body }.filter { !$0.isEmpty }
            let voice = analyzeVoice(texts: publishedTexts)

            // 2. Hook DNA: user's own usage vs saved swipes
            let hookDNA = buildHookDNA(contentAtoms: publishedContent, swipeAtoms: swipeAtoms)

            // Compute weighted preference scores (own usage weighted 2x vs saves)
            var preferredHookTypes: [String: Double] = [:]
            let totalHookSignals = hookDNA.values.reduce(0) { $0 + $1.used * 2 + $1.saved }
            if totalHookSignals > 0 {
                for (hookType, counts) in hookDNA {
                    let weighted = Double(counts.used * 2 + counts.saved)
                    preferredHookTypes[hookType] = weighted / Double(totalHookSignals)
                }
            }

            // 3. Framework preferences from published content
            var frameworkCounts: [String: Int] = [:]
            for atom in publishedContent {
                if let analysis = atom.swipeAnalysis, let fw = analysis.frameworkType {
                    frameworkCounts[fw.rawValue, default: 0] += 1
                }
                // Also check metadata for inherited frameworks
                if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
                   let inherited = meta.inheritedFramework {
                    frameworkCounts[inherited, default: 0] += 1
                }
            }
            // Also count frameworks from swipe library
            for atom in swipeAtoms {
                if let analysis = atom.swipeAnalysis, let fw = analysis.frameworkType {
                    frameworkCounts[fw.rawValue, default: 0] += 1
                }
            }
            let totalFrameworks = frameworkCounts.values.reduce(0, +)
            var preferredFrameworks: [String: Double] = [:]
            if totalFrameworks > 0 {
                for (fw, count) in frameworkCounts {
                    preferredFrameworks[fw] = Double(count) / Double(totalFrameworks)
                }
            }

            // 4. Topic affinities from idea titles and content titles
            let allTitles = ideaAtoms.compactMap { $0.title } + contentAtoms.compactMap { $0.title }
            let topicAffinities = extractTopics(titles: allTitles)

            // 5. Platform strengths from SocialSyncService
            var platformStrengths: [String: Double] = [:]
            let syncService = SocialSyncService.shared
            for platform in SocialSyncPlatform.allCases {
                if let result = syncService.lastSyncResults[platform] {
                    platformStrengths[platform.rawValue] = result.engagementRate
                }
            }

            // 6. Peak creative hours from content creation timestamps
            let peakHours = analyzePeakHours(atoms: contentAtoms + ideaAtoms)

            // 7. Voice tone classification
            let voiceTone = classifyVoiceTone(
                avgSentenceLength: voice.avgSentenceLength,
                vocabularyRichness: voice.vocabularyRichness
            )

            // 8. Average session length (from deep work blocks)
            let deepWorkAtoms = try await atomRepo.fetchAll(type: .deepWorkBlock)
            let avgSessionMinutes = computeAverageSessionMinutes(atoms: deepWorkAtoms)

            // Assemble the profile
            let profile = CreatorTasteProfile(
                preferredHookTypes: preferredHookTypes,
                preferredFrameworks: preferredFrameworks,
                topicAffinities: topicAffinities,
                platformStrengths: platformStrengths,
                peakCreativeHours: peakHours,
                averageSessionMinutes: avgSessionMinutes,
                voiceTone: voiceTone,
                editingPatterns: extractEditingPatterns(contentAtoms: publishedContent),
                lastUpdated: Date()
            )

            // Persist the profile as a userPreference atom
            await saveProfile(profile)

            return profile
        } catch {
            print("CreatorStyleProfiler: Failed to build profile: \(error.localizedDescription)")
            return CreatorTasteProfile.empty
        }
    }

    // MARK: - Profile Summary

    /// Return a human-readable summary of the creator's style profile.
    func getProfileSummary() async -> String {
        let profile = await loadOrBuildProfile()

        var lines: [String] = []

        // Voice
        let voiceInfo = await getVoiceFingerprint()
        lines.append("Your voice is \(profile.voiceTone) (avg \(String(format: "%.0f", voiceInfo.avgSentenceLength)) words/sentence, vocabulary richness: \(String(format: "%.0f%%", voiceInfo.vocabularyRichness * 100))).")

        // Top hook type
        if let topHook = profile.preferredHookTypes.max(by: { $0.value < $1.value }) {
            let pct = String(format: "%.0f%%", topHook.value * 100)
            let hookName = formatHookName(topHook.key)
            lines.append("You favor \(hookName) hooks (\(pct) of your work).")
        }

        // Top framework
        if let topFw = profile.preferredFrameworks.max(by: { $0.value < $1.value }) {
            let fwName = formatFrameworkName(topFw.key)
            lines.append("Your go-to framework is \(fwName).")
        }

        // Peak hours
        if !profile.peakCreativeHours.isEmpty {
            let hourStrings = profile.peakCreativeHours.prefix(3).map { formatHour($0) }
            lines.append("Peak creative hours: \(hourStrings.joined(separator: ", ")).")
        }

        // Top platform
        if let topPlatform = profile.platformStrengths.max(by: { $0.value < $1.value }) {
            lines.append("Strongest platform: \(topPlatform.key.capitalized) (\(String(format: "%.1f%%", topPlatform.value * 100)) engagement).")
        }

        // Top topics
        let topTopics = profile.topicAffinities
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
        if !topTopics.isEmpty {
            lines.append("Core topics: \(topTopics.joined(separator: ", ")).")
        }

        return lines.joined(separator: " ")
    }

    // MARK: - Voice Fingerprint

    /// Quick voice analysis from recent published content.
    func getVoiceFingerprint() async -> (avgSentenceLength: Double, vocabularyRichness: Double, formalityLevel: String) {
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let publishedTexts = contentAtoms
                .filter { atom in
                    guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { return false }
                    return meta.phase == .published || meta.phase == .analyzing || meta.phase == .archived
                }
                .compactMap { $0.body }
                .filter { !$0.isEmpty }

            let voice = analyzeVoice(texts: publishedTexts)
            let formality = classifyVoiceTone(
                avgSentenceLength: voice.avgSentenceLength,
                vocabularyRichness: voice.vocabularyRichness
            )
            return (voice.avgSentenceLength, voice.vocabularyRichness, formality)
        } catch {
            return (0, 0, "unknown")
        }
    }

    // MARK: - Hook DNA

    /// Compare the user's own hook usage vs their swipe library saves.
    /// Returns a dictionary mapping hook type names to (used, saved) counts.
    func getHookDNA() async -> [String: (used: Int, saved: Int)] {
        do {
            let contentAtoms = try await atomRepo.fetchAll(type: .content)
            let researchAtoms = try await atomRepo.fetchAll(type: .research)
            let swipeAtoms = researchAtoms.filter { $0.isSwipeFileAtom }

            return buildHookDNA(contentAtoms: contentAtoms, swipeAtoms: swipeAtoms)
        } catch {
            return [:]
        }
    }

    // MARK: - Refresh Profile

    /// Force rebuild the profile and save it.
    func refreshProfile() async {
        _ = await buildProfile()
    }

    // MARK: - Private Helpers

    /// Analyze voice characteristics from a collection of texts.
    private func analyzeVoice(texts: [String]) -> (avgSentenceLength: Double, vocabularyRichness: Double) {
        guard !texts.isEmpty else { return (0, 0) }

        var totalSentences = 0
        var totalWords = 0
        var allWords: [String] = []

        for text in texts {
            let analysis = WritingAnalyzer.shared.analyze(text: text)
            totalSentences += analysis.sentenceCount
            totalWords += analysis.wordCount

            // Collect lowercase words for vocabulary richness
            let words = text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            allWords.append(contentsOf: words)
        }

        let avgSentenceLength: Double = totalSentences > 0
            ? Double(totalWords) / Double(totalSentences)
            : 0

        let uniqueWords = Set(allWords)
        let vocabularyRichness: Double = allWords.isEmpty
            ? 0
            : Double(uniqueWords.count) / Double(allWords.count)

        return (avgSentenceLength, vocabularyRichness)
    }

    /// Extract common topics/words from titles using simple word frequency analysis.
    private func extractTopics(titles: [String]) -> [String: Double] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "being", "have", "has", "had", "do", "does", "did", "will",
            "would", "could", "should", "may", "might", "shall", "can",
            "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "as", "into", "through", "during", "before", "after", "above",
            "below", "between", "out", "off", "over", "under", "again",
            "further", "then", "once", "here", "there", "when", "where",
            "why", "how", "all", "each", "every", "both", "few", "more",
            "most", "other", "some", "such", "no", "nor", "not", "only",
            "own", "same", "so", "than", "too", "very", "just", "because",
            "but", "and", "or", "if", "while", "about", "up", "this",
            "that", "these", "those", "it", "its", "i", "my", "me",
            "we", "our", "you", "your", "he", "she", "they", "them",
            "what", "which", "who", "whom"
        ]

        var wordFreq: [String: Int] = [:]

        for title in titles {
            let words = title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }

            for word in words {
                wordFreq[word, default: 0] += 1
            }
        }

        // Normalize to 0-1 scores and keep top 20
        let maxFreq = Double(wordFreq.values.max() ?? 1)
        let sorted = wordFreq
            .sorted { $0.value > $1.value }
            .prefix(20)

        var result: [String: Double] = [:]
        for (word, count) in sorted {
            result[word] = Double(count) / maxFreq
        }
        return result
    }

    /// Build the hook DNA mapping: hook type -> (used in own content, saved as swipes).
    private func buildHookDNA(contentAtoms: [Atom], swipeAtoms: [Atom]) -> [String: (used: Int, saved: Int)] {
        var dna: [String: (used: Int, saved: Int)] = [:]

        // Initialize all hook types
        for hookType in SwipeHookType.allCases {
            dna[hookType.rawValue] = (used: 0, saved: 0)
        }

        // Count hook types used in own published content
        for atom in contentAtoms {
            if let analysis = atom.swipeAnalysis, let hookType = analysis.hookType {
                var current = dna[hookType.rawValue] ?? (used: 0, saved: 0)
                current.used += 1
                dna[hookType.rawValue] = current
            }
            // Also check metadata for inherited hook info
            if let meta = atom.metadataValue(as: ContentAtomMetadata.self),
               let hooks = meta.inheritedHooks {
                for hookStr in hooks {
                    // Try matching to a known hook type
                    if let hookType = SwipeHookType(rawValue: hookStr) {
                        var current = dna[hookType.rawValue] ?? (used: 0, saved: 0)
                        current.used += 1
                        dna[hookType.rawValue] = current
                    }
                }
            }
        }

        // Count hook types saved as swipes
        for atom in swipeAtoms {
            if let analysis = atom.swipeAnalysis, let hookType = analysis.hookType {
                var current = dna[hookType.rawValue] ?? (used: 0, saved: 0)
                current.saved += 1
                dna[hookType.rawValue] = current
            }
        }

        // Filter out types with zero signals
        return dna.filter { $0.value.used > 0 || $0.value.saved > 0 }
    }

    /// Analyze creation timestamps to find peak productive hours.
    private func analyzePeakHours(atoms: [Atom]) -> [Int] {
        let calendar = Calendar.current
        let isoFormatter = ISO8601DateFormatter()
        var hourCounts: [Int: Int] = [:]

        for atom in atoms {
            if let date = isoFormatter.date(from: atom.createdAt) {
                let hour = calendar.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1
            }
        }

        // Return top 3 hours by creation count
        let sorted = hourCounts.sorted { $0.value > $1.value }
        return Array(sorted.prefix(3).map { $0.key })
    }

    /// Classify voice tone based on sentence length and vocabulary richness.
    private func classifyVoiceTone(avgSentenceLength: Double, vocabularyRichness: Double) -> String {
        if avgSentenceLength < 10 && vocabularyRichness < 0.5 {
            return "punchy"
        } else if avgSentenceLength < 15 && vocabularyRichness < 0.6 {
            return "conversational"
        } else if avgSentenceLength < 20 {
            return "balanced"
        } else if vocabularyRichness > 0.7 {
            return "academic"
        } else {
            return "formal"
        }
    }

    /// Compute average deep work session length in minutes.
    private func computeAverageSessionMinutes(atoms: [Atom]) -> Double {
        guard !atoms.isEmpty else { return 0 }

        var totalMinutes: Double = 0
        var count = 0

        for atom in atoms {
            if let dict = atom.metadataDict,
               let duration = dict["durationMinutes"] as? Double {
                totalMinutes += duration
                count += 1
            } else if let dict = atom.metadataDict,
                      let duration = dict["duration"] as? Double {
                totalMinutes += duration / 60.0
                count += 1
            }
        }

        return count > 0 ? totalMinutes / Double(count) : 0
    }

    /// Extract editing pattern keywords from content revision history.
    private func extractEditingPatterns(contentAtoms: [Atom]) -> [String] {
        var patterns: [String] = []

        // Analyze how content evolves: short drafts that expand, long drafts that condense, etc.
        var expandCount = 0
        var condenseCount = 0
        var totalAtoms = 0

        for atom in contentAtoms {
            guard let meta = atom.metadataValue(as: ContentAtomMetadata.self) else { continue }
            let bodyWords = (atom.body ?? "").split(separator: " ").count
            totalAtoms += 1

            if bodyWords > meta.wordCount {
                expandCount += 1
            } else if bodyWords < meta.wordCount {
                condenseCount += 1
            }
        }

        if expandCount > condenseCount && totalAtoms > 2 {
            patterns.append("tends to expand drafts")
        } else if condenseCount > expandCount && totalAtoms > 2 {
            patterns.append("tends to condense drafts")
        }

        return patterns
    }

    /// Load existing profile from persistence or build a new one.
    private func loadOrBuildProfile() async -> CreatorTasteProfile {
        // Try loading from persisted userPreference atom
        if let profile = await loadSavedProfile() {
            return profile
        }
        return await buildProfile()
    }

    /// Load a previously saved profile from the atom repository.
    private func loadSavedProfile() async -> CreatorTasteProfile? {
        do {
            let prefs = try await atomRepo.fetchAll(type: .userPreference)
            let profileAtom = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == profileScope
            }

            guard let atom = profileAtom else { return nil }
            return atom.structuredData(as: CreatorTasteProfile.self)
        } catch {
            return nil
        }
    }

    /// Save the profile as a `.userPreference` atom.
    private func saveProfile(_ profile: CreatorTasteProfile) async {
        do {
            let prefs = try await atomRepo.fetchAll(type: .userPreference)
            let existing = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == profileScope
            }

            if var atom = existing {
                // Update existing profile atom
                atom = atom.withStructured(profile)
                try await atomRepo.update(atom)
            } else {
                // Create new profile atom
                let metadataJSON = "{\"scope\":\"\(profileScope)\"}"
                var newAtom = Atom.new(
                    type: .userPreference,
                    title: "Creator Style Profile",
                    metadata: metadataJSON
                )
                newAtom = newAtom.withStructured(profile)
                try await atomRepo.create(newAtom)
            }
        } catch {
            print("CreatorStyleProfiler: Failed to save profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting Helpers

    private func formatHookName(_ rawValue: String) -> String {
        if let hookType = SwipeHookType(rawValue: rawValue) {
            return hookType.displayName
        }
        // Fallback: convert camelCase to Title Case
        return rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    private func formatFrameworkName(_ rawValue: String) -> String {
        if let fwType = SwipeFrameworkType(rawValue: rawValue) {
            return fwType.displayName
        }
        return rawValue.uppercased()
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hour):00"
    }
}
