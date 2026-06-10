// CosmoOS/Agent/Learning/TasteProfileBuilder.swift
// Aggregates outcome tracking into a dynamic taste profile

import Foundation

@MainActor
class TasteProfileBuilder {
    static let shared = TasteProfileBuilder()

    private let atomRepo = AtomRepository.shared
    private let outcomeTracker = AgentOutcomeTracker.shared

    /// Scope key used to store and retrieve the taste profile atom.
    private let profileScope = "taste_profile"

    /// Maximum age before a profile is considered stale (24 hours).
    private let staleThreshold: TimeInterval = 86400

    private init() {}

    // MARK: - Build Profile

    /// Build a full taste profile from all learning events + content data.
    func buildProfile() async -> CreatorTasteProfile {
        let events = await outcomeTracker.getRecentEvents(limit: 200)

        // Hook preferences
        let hookPrefs = aggregateHookPreferences(events: events)

        // Framework preferences
        let frameworkPrefs = aggregateFrameworkPreferences(events: events)

        // Topic affinities from ideas and content
        let topicAffinities = await extractTopicAffinities()

        // Platform strengths from SocialSyncService
        let platformStrengths = extractPlatformStrengths()

        // Peak creative hours from content creation timestamps
        let peakHours = await extractPeakCreativeHours()

        // Average session duration from deep work blocks
        let avgSession = await extractAverageSessionMinutes()

        // Voice tone (from preference if available, else default)
        let voiceTone = await loadVoiceTone()

        // Editing patterns from draft feedback events
        let editingPatterns = extractEditingPatterns(events: events)

        let profile = CreatorTasteProfile(
            preferredHookTypes: hookPrefs,
            preferredFrameworks: frameworkPrefs,
            topicAffinities: topicAffinities,
            platformStrengths: platformStrengths,
            peakCreativeHours: peakHours,
            averageSessionMinutes: avgSession,
            voiceTone: voiceTone,
            editingPatterns: editingPatterns,
            lastUpdated: Date()
        )

        await saveProfile(profile)
        return profile
    }

    // MARK: - Load Profile

    /// Load the saved profile from a .userPreference atom, or build fresh if none exists.
    func loadProfile() async -> CreatorTasteProfile {
        do {
            let prefAtoms = try await atomRepo.fetchAll(type: .userPreference)
            let profileAtom = prefAtoms.first { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["scope"] as? String == profileScope
            }

            guard let atom = profileAtom,
                  let structuredStr = atom.structured,
                  let data = structuredStr.data(using: .utf8) else {
                return await buildProfile()
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let profile = try? decoder.decode(CreatorTasteProfile.self, from: data) {
                return profile
            }
        } catch {
            // Fall through to build fresh
        }

        return await buildProfile()
    }

    // MARK: - Refresh If Stale

    /// Rebuild if the saved profile is older than 24 hours.
    func refreshIfStale() async -> CreatorTasteProfile {
        let existing = await loadProfile()

        if Date().timeIntervalSince(existing.lastUpdated) > staleThreshold {
            return await buildProfile()
        }

        return existing
    }

    // MARK: - Profile Summary

    /// Human-readable summary suitable for injection into AI system prompts.
    func getProfileSummary() async -> String {
        let profile = await refreshIfStale()

        var summary = "Creator Taste Profile:\n"

        // Top hooks
        let topHooks = profile.preferredHookTypes
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { hookDisplayName($0.key) }

        if !topHooks.isEmpty {
            summary += "- Preferred hooks: \(topHooks.joined(separator: ", "))\n"
        }

        // Top frameworks
        let topFrameworks = profile.preferredFrameworks
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { frameworkDisplayName($0.key) }

        if !topFrameworks.isEmpty {
            summary += "- Preferred frameworks: \(topFrameworks.joined(separator: ", "))\n"
        }

        // Topics
        let topTopics = profile.topicAffinities
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        if !topTopics.isEmpty {
            summary += "- Top topics: \(topTopics.joined(separator: ", "))\n"
        }

        // Voice
        summary += "- Voice tone: \(profile.voiceTone)\n"

        // Peak hours
        if !profile.peakCreativeHours.isEmpty {
            let hourStrings = profile.peakCreativeHours.prefix(3).map { "\($0):00" }
            summary += "- Peak creative hours: \(hourStrings.joined(separator: ", "))\n"
        }

        // Editing patterns
        if !profile.editingPatterns.isEmpty {
            summary += "- Common editing feedback: \(profile.editingPatterns.prefix(3).joined(separator: ", "))\n"
        }

        return summary
    }

    // MARK: - Aggregation Helpers

    /// Weight hook selections by frequency, giving more weight to explicit selections.
    private func aggregateHookPreferences(events: [AgentLearningEvent]) -> [String: Double] {
        var scores: [String: Double] = [:]

        let hookEvents = events.filter { $0.category == .hookSelection }
        for event in hookEvents {
            if let selected = event.selected {
                scores[selected, default: 0] += 2.0
            }
            // Also track what was offered but not selected (negative signal)
            if let allOffered = event.context["allOffered"] {
                let offered = allOffered.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                for hook in offered where hook != event.selected {
                    scores[hook, default: 0] += 0.1 // Small positive for being considered
                }
            }
        }

        // Normalize to 0-1 range
        let maxScore = scores.values.max() ?? 1.0
        guard maxScore > 0 else { return scores }

        return scores.mapValues { $0 / maxScore }
    }

    /// Weight framework selections by usage frequency.
    private func aggregateFrameworkPreferences(events: [AgentLearningEvent]) -> [String: Double] {
        var scores: [String: Double] = [:]

        let frameworkEvents = events.filter { $0.category == .frameworkSelection }
        for event in frameworkEvents {
            if let selected = event.selected {
                scores[selected, default: 0] += 2.0
            }
            if let allOffered = event.context["allOffered"] {
                let offered = allOffered.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                for fw in offered where fw != event.selected {
                    scores[fw, default: 0] += 0.1
                }
            }
        }

        let maxScore = scores.values.max() ?? 1.0
        guard maxScore > 0 else { return scores }

        return scores.mapValues { $0 / maxScore }
    }

    /// Extract common editing feedback themes from draft feedback events.
    private func extractEditingPatterns(events: [AgentLearningEvent]) -> [String] {
        let feedbackEvents = events.filter { $0.category == .draftFeedback }

        // Count operation types
        var operationCounts: [String: Int] = [:]
        for event in feedbackEvents {
            if let operation = event.context["operation"] {
                operationCounts[operation, default: 0] += 1
            }
        }

        // Return the most common operations as patterns
        return operationCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    // MARK: - Data Extraction Helpers

    /// Extract topic affinities from idea titles and content topics.
    private func extractTopicAffinities() async -> [String: Double] {
        do {
            let ideas = try await atomRepo.fetchAll(type: .idea)
            let content = try await atomRepo.fetchAll(type: .content)

            // Simple word-frequency approach on titles
            var wordCounts: [String: Int] = [:]
            let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
                                           "of", "with", "by", "from", "is", "it", "that", "this", "my", "how",
                                           "what", "why", "when", "i", "you", "we", "they", "about", "your"]

            let allAtoms = ideas + content
            for atom in allAtoms.prefix(100) {
                guard let title = atom.title else { continue }
                let words = title.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 2 && !stopWords.contains($0) }

                for word in words {
                    wordCounts[word, default: 0] += 1
                }
            }

            // Keep only words that appear 2+ times
            let significantWords = wordCounts.filter { $0.value >= 2 }
            let maxCount = Double(significantWords.values.max() ?? 1)
            guard maxCount > 0 else { return [:] }

            return significantWords
                .sorted { $0.value > $1.value }
                .prefix(20)
                .reduce(into: [String: Double]()) { result, pair in
                    result[pair.key] = Double(pair.value) / maxCount
                }
        } catch {
            return [:]
        }
    }

    /// Extract platform strengths from SocialSyncService connection data.
    private func extractPlatformStrengths() -> [String: Double] {
        let service = SocialSyncService.shared
        var strengths: [String: Double] = [:]

        for platform in service.connectedPlatforms {
            // Connected platforms get a base score
            strengths[platform.rawValue] = 1.0
        }

        return strengths
    }

    /// Analyze content creation timestamps to find peak creative hours.
    private func extractPeakCreativeHours() async -> [Int] {
        do {
            let content = try await atomRepo.fetchAll(type: .content)
            let ideas = try await atomRepo.fetchAll(type: .idea)

            let isoFormatter = ISO8601DateFormatter()
            var hourCounts: [Int: Int] = [:]

            let allAtoms = (content + ideas).prefix(200)
            for atom in allAtoms {
                if let date = isoFormatter.date(from: atom.createdAt) {
                    let hour = Calendar.current.component(.hour, from: date)
                    hourCounts[hour, default: 0] += 1
                }
            }

            // Return top 3 hours sorted by frequency
            return hourCounts
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }
                .sorted()
        } catch {
            return []
        }
    }

    /// Calculate average deep work session duration in minutes.
    private func extractAverageSessionMinutes() async -> Double {
        do {
            let blocks = try await atomRepo.fetchAll(type: .deepWorkBlock)
            guard !blocks.isEmpty else { return 25.0 } // Default Pomodoro

            var durations: [Double] = []
            for block in blocks.prefix(50) {
                if let meta = block.metadataDict,
                   let minutes = meta["durationMinutes"] as? Double {
                    durations.append(minutes)
                } else if let meta = block.metadataDict,
                          let minutes = meta["durationMinutes"] as? Int {
                    durations.append(Double(minutes))
                }
            }

            guard !durations.isEmpty else { return 25.0 }
            return durations.reduce(0, +) / Double(durations.count)
        } catch {
            return 25.0
        }
    }

    /// Load voice tone from user preferences, defaulting to "conversational".
    private func loadVoiceTone() async -> String {
        do {
            let prefAtoms = try await atomRepo.fetchAll(type: .userPreference)
            let voiceAtom = prefAtoms.first { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["key"] as? String == "voice_tone"
            }

            if let body = voiceAtom?.body, !body.isEmpty {
                return body
            }
        } catch {
            // Fall through
        }

        return "conversational"
    }

    // MARK: - Persistence

    /// Persist the profile as a .userPreference atom with scope "taste_profile".
    private func saveProfile(_ profile: CreatorTasteProfile) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let structuredData = try encoder.encode(profile)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataDict: [String: Any] = [
                "scope": profileScope,
                "key": "taste_profile",
                "lastUpdated": ISO8601.string(from: Date())
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            // Try to update existing profile atom
            let prefAtoms = try await atomRepo.fetchAll(type: .userPreference)
            let existingAtom = prefAtoms.first { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["scope"] as? String == profileScope
            }

            if var existing = existingAtom {
                existing.structured = structuredStr
                existing.metadata = metadataStr
                _ = try await atomRepo.update(existing)
            } else {
                let atom = Atom.new(
                    type: .userPreference,
                    title: "Creator Taste Profile",
                    structured: structuredStr,
                    metadata: metadataStr
                )
                _ = try await atomRepo.create(atom)
            }
        } catch {
            print("[TasteProfileBuilder] Failed to save profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Display Name Helpers

    private func hookDisplayName(_ rawValue: String) -> String {
        if let hookType = SwipeHookType(rawValue: rawValue) {
            return hookType.displayName
        }
        return rawValue
    }

    private func frameworkDisplayName(_ rawValue: String) -> String {
        if let framework = SwipeFrameworkType(rawValue: rawValue) {
            return framework.displayName
        }
        return rawValue
    }
}
