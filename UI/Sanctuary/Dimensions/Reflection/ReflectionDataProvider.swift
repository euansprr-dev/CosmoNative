// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionDataProvider.swift
// Data provider that queries GRDB to build real ReflectionDimensionData
// WP6: Reflection Dimension — Journal, Mood, Meditation

import Foundation
import SwiftUI
import GRDB
import NaturalLanguage

// Shared ISO8601 formatter — avoids recreating per call
private let _reflectionISOFormatter = ISO8601DateFormatter()

@MainActor
class ReflectionDataProvider: ObservableObject, DimensionScoring {
    nonisolated var dimensionId: String { "reflection" }

    @Published var data: ReflectionDimensionData = .empty
    @Published var isLoading = false
    @Published var reflectionIndex: DimensionIndex = .empty

    // Cache NLTagger results — only recompute when journal count changes
    private var cachedThemes: [ReflectionTheme] = []
    private var cachedThemeJournalCount: Int = -1

    private let database: any DatabaseWriter

    init(database: (any DatabaseWriter)? = nil) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
    }

    // MARK: - DimensionScoring

    func computeIndex() async -> DimensionIndex {
        let journalConsistency = await computeJournalConsistency()
        let journalDepth = await computeJournalDepth()
        let meditationScore = await computeMeditationScore()
        let emotionalAwareness = await computeEmotionalAwareness()
        let themeProgression = await computeThemeProgression()

        let score = journalConsistency * 0.30
                  + journalDepth * 0.20
                  + meditationScore * 0.20
                  + emotionalAwareness * 0.15
                  + themeProgression * 0.15

        let subScores: [String: Double] = [
            "journalConsistency": journalConsistency,
            "journalDepth": journalDepth,
            "meditation": meditationScore,
            "emotionalAwareness": emotionalAwareness,
            "themeProgression": themeProgression
        ]

        let hasData = journalConsistency > 0 || meditationScore > 0 || emotionalAwareness > 0
        let confidence = hasData ? 0.8 : 0.2
        let trend = await computeReflectionTrend()

        let index = DimensionIndex(
            score: min(100, max(0, score)),
            confidence: confidence,
            trend: trend,
            subScores: subScores,
            dataAge: 0
        )
        reflectionIndex = index
        return index
    }

    // MARK: - Refresh Data

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        let journalAtoms = await fetchAtoms(type: .journalEntry)
        let moodAtoms = await fetchAtoms(type: .emotionalState)
        let meditationAtoms = await fetchAtoms(type: .breathingSession)
        let insightAtoms = await fetchAtoms(type: .journalInsight)

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        // -- Journal --
        let journalStreak = computeStreak(atoms: journalAtoms)
        let journalPersonalBest = computePersonalBestStreak(atoms: journalAtoms)

        let todayJournals = journalAtoms.filter { atomDate($0) >= todayStart }
        let wordsToday = todayJournals.reduce(0) { $0 + wordCount(for: $1) }
        let todayEntryPreview: String = {
            guard let body = todayJournals.first?.body else { return "" }
            if body.count <= 100 { return body }
            return String(body.prefix(100)) + "..."
        }()

        let allWordCounts = journalAtoms.map { wordCount(for: $0) }
        let wordsAverage = allWordCounts.isEmpty ? 0 : allWordCounts.reduce(0, +) / allWordCounts.count

        let depthScore = computeDepthScore(journals: todayJournals)

        // -- Mood --
        let emotionalDataPoints = moodAtoms.compactMap { atom -> EmotionalDataPoint? in
            let date = atomDate(atom)
            let dict = atom.metadataDict
            let valence = dict?["valence"] as? Double ?? 0
            let energy = dict?["energy"] as? Double ?? (dict?["arousal"] as? Double ?? 0)
            let note = dict?["note"] as? String ?? dict?["contextNotes"] as? String
            let sourceRaw = dict?["source"] as? String ?? "manual"
            let source: MoodSource = sourceRaw == "journal" ? .journal : sourceRaw == "inferred" ? .inferred : .manual
            let emoji = emojiForMood(valence: valence, energy: energy)
            return EmotionalDataPoint(
                timestamp: date,
                valence: valence,
                energy: energy,
                emoji: emoji,
                note: note,
                source: source
            )
        }

        let todayMoodPoints = emotionalDataPoints.filter { $0.timestamp >= todayStart }
        let todayMood: EmotionalState = {
            guard let latest = todayMoodPoints.last else {
                return EmotionalState(valence: 0, energy: 0, description: "No mood data today", emoji: "🔘", comparedToAverage: "N/A")
            }
            let label = moodLabel(valence: latest.valence, energy: latest.energy)
            return EmotionalState(
                valence: latest.valence,
                energy: latest.energy,
                description: label,
                emoji: latest.emoji,
                comparedToAverage: "Current"
            )
        }()

        let weekMoodPoints = emotionalDataPoints.filter { $0.timestamp >= weekAgo }
        let avgValence = weekMoodPoints.isEmpty ? 0 : weekMoodPoints.map(\.valence).reduce(0, +) / Double(weekMoodPoints.count)
        let avgEnergy = weekMoodPoints.isEmpty ? 0 : weekMoodPoints.map(\.energy).reduce(0, +) / Double(weekMoodPoints.count)

        let valenceTrend = computeValenceTrend(points: emotionalDataPoints)

        let moodTimeline = buildMoodTimeline(points: todayMoodPoints)

        let weeklyMoodData = buildWeeklyMoodData(points: emotionalDataPoints)

        // -- Meditation --
        let todayMeditations = meditationAtoms.filter { atomDate($0) >= todayStart }
        let meditationToday = todayMeditations.reduce(0) { $0 + meditationMinutes(for: $1) }

        let weekMeditations = meditationAtoms.filter { atomDate($0) >= weekAgo }
        let meditationThisWeek = weekMeditations.reduce(0) { $0 + meditationMinutes(for: $1) }

        let meditationStreak = computeMeditationStreak(atoms: meditationAtoms)

        let allMeditationMinutes = meditationAtoms.map { meditationMinutes(for: $0) }
        let averageSessionLength = allMeditationMinutes.isEmpty ? 0 : allMeditationMinutes.reduce(0, +) / allMeditationMinutes.count

        let meditationWeekData = buildMeditationWeekData(atoms: meditationAtoms)

        // -- Themes (cached — NLTagger is expensive) --
        let recurringThemes: [ReflectionTheme]
        if journalAtoms.count != cachedThemeJournalCount {
            cachedThemes = extractThemes(from: journalAtoms)
            cachedThemeJournalCount = journalAtoms.count
        }
        recurringThemes = cachedThemes
        let emergingThemes = recurringThemes.filter { $0.weeklyChange > 0 }.prefix(3).map { theme in
            EmergingTheme(name: theme.name, mentionsThisWeek: theme.weeklyChange, description: "Emerging pattern")
        }

        // -- Grail Insights --
        let grailInsights = insightAtoms.compactMap { atom -> GrailInsight? in
            guard let body = atom.body, !body.isEmpty else { return nil }
            let date = atomDate(atom)
            let dict = atom.metadataDict
            let journalUUID = dict?["journalAtomUUID"] as? String
            let tags = dict?["keywords"] as? [String] ?? []
            return GrailInsight(
                content: body,
                discoveredDate: date,
                sourceEntryID: journalUUID.flatMap { UUID(uuidString: $0) } ?? UUID(),
                sourceEntryTitle: atom.title ?? "Journal Entry",
                sourceWordCount: body.split(separator: " ").count,
                journey: [],
                crossDimensionLinks: [],
                tags: tags
            )
        }

        let monthInsights = grailInsights.filter { $0.discoveredDate >= monthAgo }

        data = ReflectionDimensionData(
            emotionalDataPoints: emotionalDataPoints,
            todayMood: todayMood,
            averageValence: avgValence,
            averageEnergy: avgEnergy,
            valenceTrend: valenceTrend,
            moodTimeline: moodTimeline,
            weeklyMoodData: weeklyMoodData,
            journalStreak: journalStreak,
            journalPersonalBest: journalPersonalBest,
            wordsToday: wordsToday,
            wordsAverage: wordsAverage,
            depthScore: depthScore,
            todayEntryPreview: todayEntryPreview,
            todayEntryWordCount: wordsToday,
            meditationToday: meditationToday,
            meditationGoal: 15,
            meditationThisWeek: meditationThisWeek,
            meditationWeekData: meditationWeekData,
            meditationStreak: meditationStreak,
            averageSessionLength: averageSessionLength,
            recurringThemes: recurringThemes,
            themeEvolution: [],
            emergingThemes: emergingThemes,
            grailInsights: grailInsights,
            totalGrails: grailInsights.count,
            grailsThisMonth: monthInsights.count,
            pinnedGrails: [],
            predictions: [],
            insightPatterns: []
        )
    }

    // MARK: - Create Journal Entry

    func createJournalEntry(text: String, prompt: String? = nil) async {
        let wordCount = text.split(separator: " ").count
        let reflectionMarkers = countReflectionMarkers(text)

        var metadataDict: [String: Any] = [
            "wordCount": wordCount,
            "reflectionMarkers": reflectionMarkers
        ]
        if let prompt = prompt {
            metadataDict["prompt"] = prompt
        }

        let metadataString = encodeMetadata(metadataDict)

        do {
            _ = try await AtomRepository.shared.create(
                type: .journalEntry,
                title: "Journal Entry",
                body: text,
                metadata: metadataString
            )
        } catch {
            print("[ReflectionDataProvider] Failed to create journal entry: \(error)")
        }

        await refreshData()
    }

    // MARK: - Record Mood

    func recordMood(valence: Double, energy: Double, note: String? = nil) async {
        var metadataDict: [String: Any] = [
            "valence": valence,
            "energy": energy,
            "source": "manual",
            "timestamp": _reflectionISOFormatter.string(from: Date())
        ]
        if let note = note {
            metadataDict["note"] = note
        }

        let metadataString = encodeMetadata(metadataDict)

        do {
            _ = try await AtomRepository.shared.create(
                type: .emotionalState,
                title: "Mood Check-In",
                metadata: metadataString
            )
        } catch {
            print("[ReflectionDataProvider] Failed to record mood: \(error)")
        }

        await refreshData()
    }

    // MARK: - Record Meditation

    func recordMeditation(durationMinutes: Int) async {
        let metadataDict: [String: Any] = [
            "durationMinutes": durationMinutes,
            "timestamp": _reflectionISOFormatter.string(from: Date())
        ]

        let metadataString = encodeMetadata(metadataDict)

        do {
            _ = try await AtomRepository.shared.create(
                type: .breathingSession,
                title: "Meditation",
                metadata: metadataString
            )
        } catch {
            print("[ReflectionDataProvider] Failed to record meditation: \(error)")
        }

        await refreshData()
    }

    // MARK: - Private Helpers

    private func fetchAtoms(type: AtomType) async -> [Atom] {
        (try? await AtomRepository.shared.fetchAll(type: type)) ?? []
    }

    private func atomDate(_ atom: Atom) -> Date {
        _reflectionISOFormatter.date(from: atom.createdAt) ?? Date()
    }

    private func wordCount(for atom: Atom) -> Int {
        if let wc = atom.metadataDict?["wordCount"] as? Int { return wc }
        return atom.body?.split(separator: " ").count ?? 0
    }

    private func meditationMinutes(for atom: Atom) -> Int {
        atom.metadataDict?["durationMinutes"] as? Int ?? 0
    }

    private func encodeMetadata(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Streak Computation

    private func computeStreak(atoms: [Atom]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var daysWithEntries = Set<Date>()
        for atom in atoms {
            let date = calendar.startOfDay(for: atomDate(atom))
            daysWithEntries.insert(date)
        }

        var streak = 0
        var checkDate = today

        // Allow starting from today or yesterday
        if !daysWithEntries.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while daysWithEntries.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return streak
    }

    private func computePersonalBestStreak(atoms: [Atom]) -> Int {
        let calendar = Calendar.current
        var daysWithEntries = Set<Date>()
        for atom in atoms {
            let date = calendar.startOfDay(for: atomDate(atom))
            daysWithEntries.insert(date)
        }

        guard !daysWithEntries.isEmpty else { return 0 }

        let sortedDays = daysWithEntries.sorted()
        var best = 1
        var current = 1

        for i in 1..<sortedDays.count {
            let prevDay = sortedDays[i - 1]
            let nextExpected = calendar.date(byAdding: .day, value: 1, to: prevDay) ?? prevDay
            if sortedDays[i] == nextExpected {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }

        return best
    }

    private func computeMeditationStreak(atoms: [Atom]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var daysWithMeditation = Set<Date>()
        for atom in atoms {
            let date = calendar.startOfDay(for: atomDate(atom))
            daysWithMeditation.insert(date)
        }

        var streak = 0
        var checkDate = today

        if !daysWithMeditation.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while daysWithMeditation.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return streak
    }

    // MARK: - Depth Score

    private func computeDepthScore(journals: [Atom]) -> Double {
        guard !journals.isEmpty else { return 0 }

        var totalScore = 0.0
        for journal in journals {
            let wc = Double(wordCount(for: journal))
            let markers = Double(countReflectionMarkers(journal.body ?? ""))

            // Depth heuristic: word count weight + reflection marker density
            let wcScore = min(5.0, wc / 100.0)
            let markerScore = min(5.0, markers * 1.5)
            totalScore += wcScore + markerScore
        }

        return min(10.0, totalScore / Double(journals.count))
    }

    private func countReflectionMarkers(_ text: String) -> Int {
        let markers = ["realize", "understand", "feel", "notice", "wonder", "believe",
                       "grateful", "afraid", "hope", "dream", "insight", "pattern",
                       "because", "therefore", "however", "although", "reflects"]
        let lowered = text.lowercased()
        return markers.reduce(0) { count, marker in
            count + (lowered.components(separatedBy: marker).count - 1)
        }
    }

    // MARK: - Mood Helpers

    private func emojiForMood(valence: Double, energy: Double) -> String {
        if valence > 0.3 && energy > 0.3 { return "😊" }
        if valence > 0.3 && energy <= -0.3 { return "😌" }
        if valence <= -0.3 && energy > 0.3 { return "😰" }
        if valence <= -0.3 && energy <= -0.3 { return "😔" }
        return "😐"
    }

    private func moodLabel(valence: Double, energy: Double) -> String {
        if valence > 0.3 && energy > 0.3 { return "Excited" }
        if valence > 0.3 && energy <= -0.3 { return "Calm" }
        if valence <= -0.3 && energy > 0.3 { return "Anxious" }
        if valence <= -0.3 && energy <= -0.3 { return "Low" }
        return "Balanced"
    }

    private func computeValenceTrend(points: [EmotionalDataPoint]) -> TrendDirection {
        let calendar = Calendar.current
        let now = Date()
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let recentPoints = points.filter { $0.timestamp >= threeDaysAgo }
        let olderPoints = points.filter { $0.timestamp >= sevenDaysAgo && $0.timestamp < threeDaysAgo }

        guard !recentPoints.isEmpty, !olderPoints.isEmpty else { return .stable }

        let recentAvg = recentPoints.map(\.valence).reduce(0, +) / Double(recentPoints.count)
        let olderAvg = olderPoints.map(\.valence).reduce(0, +) / Double(olderPoints.count)

        let diff = recentAvg - olderAvg
        if diff > 0.15 { return .improving }
        if diff < -0.15 { return .declining }
        return .stable
    }

    private func buildMoodTimeline(points: [EmotionalDataPoint]) -> [HourlyMood] {
        let calendar = Calendar.current
        var hourMap: [Int: (valence: Double, energy: Double, count: Int)] = [:]

        for point in points {
            let hour = calendar.component(.hour, from: point.timestamp)
            let existing = hourMap[hour] ?? (0, 0, 0)
            hourMap[hour] = (
                valence: existing.valence + point.valence,
                energy: existing.energy + point.energy,
                count: existing.count + 1
            )
        }

        return hourMap.sorted { $0.key < $1.key }.map { hour, values in
            let avgVal = values.valence / Double(values.count)
            let avgEn = values.energy / Double(values.count)
            return HourlyMood(
                hour: hour,
                valence: avgVal,
                energy: avgEn,
                emoji: emojiForMood(valence: avgVal, energy: avgEn),
                label: moodLabel(valence: avgVal, energy: avgEn)
            )
        }
    }

    private func buildWeeklyMoodData(points: [EmotionalDataPoint]) -> [DailyMood] {
        let calendar = Calendar.current
        let now = Date()

        return (0..<7).compactMap { offset -> DailyMood? in
            guard let date = calendar.date(byAdding: .day, value: -(6 - offset), to: now) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

            let dayPoints = points.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            guard !dayPoints.isEmpty else { return nil }

            let avgVal = dayPoints.map(\.valence).reduce(0, +) / Double(dayPoints.count)
            let avgEn = dayPoints.map(\.energy).reduce(0, +) / Double(dayPoints.count)

            return DailyMood(
                date: dayStart,
                averageValence: avgVal,
                averageEnergy: avgEn,
                dominantEmoji: emojiForMood(valence: avgVal, energy: avgEn)
            )
        }
    }

    // MARK: - Meditation Week Data

    private func buildMeditationWeekData(atoms: [Atom]) -> [DailyMeditation] {
        let calendar = Calendar.current
        let now = Date()
        let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: -(6 - offset), to: now) ?? now
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dayAtoms = atoms.filter {
                let d = atomDate($0)
                return d >= dayStart && d < dayEnd
            }
            let totalMinutes = dayAtoms.reduce(0) { $0 + meditationMinutes(for: $1) }

            let isToday = calendar.isDateInToday(dayStart)

            return DailyMeditation(
                dayOfWeek: dayLabels[offset],
                minutes: totalMinutes,
                date: dayStart,
                goalMinutes: 15,
                isToday: isToday
            )
        }
    }

    // MARK: - Theme Extraction (NaturalLanguage)

    private func extractThemes(from journals: [Atom]) -> [ReflectionTheme] {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        // Combine all journal text
        var allKeywords: [String: (total: Int, thisWeek: Int, lastSeen: Date)] = [:]

        let tagger = NLTagger(tagSchemes: [.nameType, .lemma])

        for atom in journals {
            guard let body = atom.body, !body.isEmpty else { continue }
            let date = atomDate(atom)
            let isThisWeek = date >= weekAgo

            tagger.string = body
            let range = body.startIndex..<body.endIndex

            tagger.enumerateTags(in: range, unit: .word, scheme: .lemma) { tag, tokenRange in
                if let lemma = tag?.rawValue {
                    let word = lemma.lowercased()
                    guard word.count > 3, !stopWords.contains(word) else { return true }

                    var entry = allKeywords[word] ?? (total: 0, thisWeek: 0, lastSeen: Date.distantPast)
                    entry.total += 1
                    if isThisWeek { entry.thisWeek += 1 }
                    if date > entry.lastSeen { entry.lastSeen = date }
                    allKeywords[word] = entry
                }
                return true
            }
        }

        // Filter to themes with 3+ mentions, sort by frequency
        let themeColors = ["#EC4899", "#10B981", "#3B82F6", "#F59E0B", "#8B5CF6",
                           "#EF4444", "#06B6D4", "#F97316", "#14B8A6", "#A855F7"]

        let sorted = allKeywords
            .filter { $0.value.total >= 3 }
            .sorted { $0.value.total > $1.value.total }
            .prefix(10)

        return Array(sorted.enumerated().map { index, entry in
            let weeklyChange = entry.value.thisWeek
            let trend: TrendDirection = weeklyChange > 2 ? .improving : weeklyChange == 0 ? .declining : .stable

            return ReflectionTheme(
                name: entry.key.uppercased(),
                mentionCount: entry.value.total,
                weeklyChange: weeklyChange,
                trend: trend,
                colorHex: themeColors[index % themeColors.count],
                relatedKeywords: [],
                lastMentioned: entry.value.lastSeen
            )
        })
    }

    private let stopWords: Set<String> = [
        "that", "this", "with", "from", "have", "been", "were", "they",
        "will", "would", "could", "should", "about", "which", "their",
        "there", "then", "than", "them", "what", "when", "where", "some",
        "each", "just", "also", "very", "much", "more", "most", "into",
        "over", "such", "only", "other", "after", "before", "like", "being",
        "make", "does", "doing", "made", "said", "didn", "wasn", "aren"
    ]

    // MARK: - Index Sub-Score Computations

    /// Journal Consistency (30%): days with entries in last 30 / 30 * 100
    private func computeJournalConsistency() async -> Double {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoff = _reflectionISOFormatter.string(from: monthAgo)

        do {
            return try await database.read { db -> Double in
                let rows = try Atom
                    .filter(Column("type") == AtomType.journalEntry.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchAll(db)

                let calendar = Calendar.current
                var uniqueDays = Set<Date>()
                let isoFormatter = _reflectionISOFormatter
                for atom in rows {
                    if let date = isoFormatter.date(from: atom.createdAt) {
                        uniqueDays.insert(calendar.startOfDay(for: date))
                    }
                }

                return min(100, (Double(uniqueDays.count) / 30.0) * 100)
            }
        } catch {
            return 0
        }
    }

    /// Journal Depth (20%): avg word count / 500 * 100, capped at 100
    private func computeJournalDepth() async -> Double {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoff = _reflectionISOFormatter.string(from: monthAgo)

        do {
            return try await database.read { db -> Double in
                let rows = try Atom
                    .filter(Column("type") == AtomType.journalEntry.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchAll(db)

                guard !rows.isEmpty else { return 0 }

                var totalWords = 0
                for atom in rows {
                    if let wc = atom.metadataDict?["wordCount"] as? Int {
                        totalWords += wc
                    } else {
                        totalWords += atom.body?.split(separator: " ").count ?? 0
                    }
                }

                let avg = Double(totalWords) / Double(rows.count)
                return min(100, (avg / 500.0) * 100)
            }
        } catch {
            return 0
        }
    }

    /// Meditation (20%): meditation minutes this week / 105 * 100 (15 min/day target)
    private func computeMeditationScore() async -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoff = _reflectionISOFormatter.string(from: weekAgo)

        do {
            return try await database.read { db -> Double in
                let rows = try Atom
                    .filter(Column("type") == AtomType.breathingSession.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchAll(db)

                var totalMinutes = 0
                for atom in rows {
                    totalMinutes += atom.metadataDict?["durationMinutes"] as? Int ?? 0
                }

                return min(100, (Double(totalMinutes) / 105.0) * 100)
            }
        } catch {
            return 0
        }
    }

    /// Emotional Awareness (15%): mood check-ins this week / 14 * 100 (2/day target)
    private func computeEmotionalAwareness() async -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoff = _reflectionISOFormatter.string(from: weekAgo)

        do {
            return try await database.read { db -> Double in
                let count = try Atom
                    .filter(Column("type") == AtomType.emotionalState.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(Column("created_at") >= cutoff)
                    .fetchCount(db)

                return min(100, (Double(count) / 14.0) * 100)
            }
        } catch {
            return 0
        }
    }

    /// Theme Progression (15%): placeholder until enough journal data
    private func computeThemeProgression() async -> Double {
        let insights = await fetchAtoms(type: .journalInsight)
        guard !insights.isEmpty else { return 0 }
        return min(100, Double(insights.count) * 10)
    }

    /// Trend computation
    private func computeReflectionTrend() async -> DimensionTrend {
        let consistency = await computeJournalConsistency()
        if consistency >= 60 { return .rising }
        if consistency <= 20 { return .falling }
        return .stable
    }
}
