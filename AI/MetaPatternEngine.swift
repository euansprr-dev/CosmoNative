// CosmoOS/AI/MetaPatternEngine.swift
// Groups swipes by platform x format x niche and generates structured MetaPattern reports
// February 2026

import Foundation

// MARK: - Data Structures

/// A complete meta-pattern report for a platform x format x niche grouping
struct MetaPatternReport: Codable, Sendable {
    let platform: String
    let format: String
    let niche: String
    let sampleSize: Int
    let generatedAt: Date

    let dominantHooks: [HookPattern]
    let winningStructures: [StructurePattern]
    let emotionalArcPattern: String
    let persuasionTechniques: [PersuasionPattern]
    let trendingTopics: [String]
    let decliningPatterns: [String]
}

/// Frequency and score data for a hook type within a grouping
struct HookPattern: Codable, Sendable {
    let hookType: String
    let frequency: Double
    let avgScore: Double
    let exampleCount: Int
}

/// Frequency data for a framework type within a grouping
struct StructurePattern: Codable, Sendable {
    let framework: String
    let frequency: Double
    let avgSectionCount: Int
    let description: String
}

/// Frequency and co-occurrence data for a persuasion technique within a grouping
struct PersuasionPattern: Codable, Sendable {
    let technique: String
    let frequency: Double
    let commonPairings: [String]
}

// MARK: - MetaPatternEngine

/// Groups swipes by platform x format x niche and generates aggregate reports
/// showing what content patterns are working right now.
///
/// Distinct from SwipePatternMiner (which analyzes the whole library without grouping)
/// — this engine segments by platform/format/niche to answer "what works on Instagram reels
/// in the finance niche?" type questions.
@MainActor
class MetaPatternEngine {

    // MARK: - Singleton

    static let shared = MetaPatternEngine()

    // MARK: - Constants

    private let minimumGroupSize = 5
    private let cacheMaxAgeSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    private let recentWindowDays = 14
    private let scopePrefix = "meta_pattern_"

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Generate a report for a specific platform x format x niche grouping.
    /// If any dimension is nil, uses the largest available group for that dimension.
    func generateReport(platform: String?, format: String?, niche: String?) async -> MetaPatternReport? {
        let grouped = await loadGroupedSwipes()
        guard !grouped.isEmpty else { return nil }

        // Find the best matching group
        let matchingEntries = findBestGroup(in: grouped, platform: platform, format: format, niche: niche)

        guard matchingEntries.count >= minimumGroupSize else { return nil }

        // Determine actual platform/format/niche from the matched group
        let resolvedPlatform = platform ?? inferDimension(from: matchingEntries, extractor: { $0.platform }) ?? "all"
        let resolvedFormat = format ?? inferDimension(from: matchingEntries, extractor: { $0.format }) ?? "all"
        let resolvedNiche = niche ?? inferDimension(from: matchingEntries, extractor: { $0.niche }) ?? "general"

        let report = buildReport(
            entries: matchingEntries,
            platform: resolvedPlatform,
            format: resolvedFormat,
            niche: resolvedNiche
        )

        // Cache the report
        await cacheReport(report)

        return report
    }

    /// Retrieve a cached report, regenerating if stale.
    func getReport(platform: String, format: String, niche: String) async -> MetaPatternReport? {
        if let cached = await loadCachedReport(platform: platform, format: format, niche: niche) {
            let age = Date().timeIntervalSince(cached.generatedAt)
            if age < cacheMaxAgeSeconds {
                return cached
            }
        }
        return await generateReport(platform: platform, format: format, niche: niche)
    }

    /// Return all cached meta-pattern reports.
    func getAllReports() async -> [MetaPatternReport] {
        do {
            let prefAtoms = try await AtomRepository.shared.fetchAll(type: .userPreference)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return prefAtoms.compactMap { atom -> MetaPatternReport? in
                guard let dict = atom.metadataDict,
                      let scope = dict["scope"] as? String,
                      scope.hasPrefix(scopePrefix) else { return nil }
                guard let str = atom.structured,
                      let data = str.data(using: .utf8) else { return nil }
                return try? decoder.decode(MetaPatternReport.self, from: data)
            }
        } catch {
            return []
        }
    }

    /// Human-readable summary for display in Intelligence Panel or Telegram.
    func getReportSummary(platform: String, format: String, niche: String) async -> String {
        guard let report = await getReport(platform: platform, format: format, niche: niche) else {
            return "Not enough data for \(platform) \(format) in \(niche) (need \(minimumGroupSize)+ swipes)."
        }
        return formatSummary(report)
    }

    /// Returns all platform x format x niche combos with enough swipes for analysis.
    func getAvailableGroupings() async -> [(platform: String, format: String, niche: String, count: Int)] {
        let grouped = await loadGroupedSwipes()
        return grouped
            .filter { $0.value.count >= minimumGroupSize }
            .map { (platform: $0.key.platform, format: $0.key.format, niche: $0.key.niche, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Structural Fingerprinting

    /// Compute a structural fingerprint for a swipe atom.
    /// Returns nil if the atom has no analysis data.
    func computeStructuralFingerprint(for atom: Atom) -> StructuralFingerprint? {
        guard let analysis = atom.swipeAnalysis else { return nil }
        return StructuralFingerprint.from(analysis: analysis)
    }

    /// Find swipes with similar structural fingerprints across the whole library.
    /// Cross-niche matching: same structure pattern, potentially different topics.
    func findSimilarStructures(to atom: Atom, limit: Int = 5) async -> [(atom: Atom, similarity: Double)] {
        guard let refFingerprint = computeStructuralFingerprint(for: atom) else { return [] }

        let allSwipes = await loadAllSwipeAtoms()
        var results: [(atom: Atom, similarity: Double)] = []

        for swipe in allSwipes {
            guard swipe.uuid != atom.uuid else { continue }
            guard let fp = computeStructuralFingerprint(for: swipe) else { continue }

            let sim = refFingerprint.similarity(to: fp)
            if sim > 0.3 {
                results.append((atom: swipe, similarity: sim))
            }
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    /// Get a relevant meta-pattern report for a content atom based on its metadata.
    /// Used by ContentContextPanel to show "What's Working Now".
    func getRelevantReport(for contentAtom: Atom) async -> MetaPatternReport? {
        // Extract platform/format/niche from content metadata
        let metadata = contentAtom.metadataValue(as: ContentAtomMetadata.self)

        var platform: String?
        var format: String?
        var niche: String?

        // Try IdeaMetadata on the content atom itself
        if let ideaMeta = contentAtom.ideaMetadata {
            platform = ideaMeta.platform?.rawValue
            if let cf = ideaMeta.contentFormat {
                format = cf.rawValue
            }
        }

        // Try source idea for more context
        if let sourceIdeaUUID = metadata?.sourceIdeaUUID,
           let sourceIdea = try? await AtomRepository.shared.fetch(uuid: sourceIdeaUUID) {
            let ideaMeta = sourceIdea.ideaMetadata
            if platform == nil { platform = ideaMeta?.platform?.rawValue }
            if format == nil, let cf = ideaMeta?.contentFormat { format = cf.rawValue }
        }

        // Try client profile for niche
        if let clientUUID = metadata?.clientProfileUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = client.metadataValue(as: ClientProfileMetadata.self) {
            niche = clientMeta.niche
        }

        // Need at least one dimension to be useful
        guard platform != nil || format != nil || niche != nil else { return nil }

        return await getReport(
            platform: platform ?? "all",
            format: format ?? "all",
            niche: niche ?? "general"
        )
    }

    // MARK: - Private: Data Loading

    /// A flattened swipe entry with extracted metadata for grouping.
    private struct SwipeEntry {
        let atom: Atom
        let analysis: SwipeAnalysis?
        let platform: String
        let format: String
        let niche: String
    }

    /// Grouping key for platform x format x niche.
    private struct GroupKey: Hashable {
        let platform: String
        let format: String
        let niche: String
    }

    /// Load all swipe atoms and extract their platform/format/niche for grouping.
    private func loadGroupedSwipes() async -> [GroupKey: [SwipeEntry]] {
        let swipes = await loadAllSwipeAtoms()
        var groups: [GroupKey: [SwipeEntry]] = [:]

        for atom in swipes {
            let analysis = atom.swipeAnalysis
            let entry = SwipeEntry(
                atom: atom,
                analysis: analysis,
                platform: extractPlatform(from: atom, analysis: analysis),
                format: extractFormat(from: atom, analysis: analysis),
                niche: extractNiche(from: atom, analysis: analysis)
            )

            let key = GroupKey(platform: entry.platform, format: entry.format, niche: entry.niche)
            groups[key, default: []].append(entry)
        }

        return groups
    }

    /// Fetch all research atoms that are swipe files.
    private func loadAllSwipeAtoms() async -> [Atom] {
        do {
            let allResearch = try await AtomRepository.shared.fetchAll(type: .research)
            return allResearch.filter { $0.isSwipeFileAtom }
        } catch {
            return []
        }
    }

    // MARK: - Private: Metadata Extraction

    private func extractPlatform(from atom: Atom, analysis: SwipeAnalysis?) -> String {
        // Try swipe gallery item platform (from structured richContent)
        if let item = atom.toSwipeGalleryItem(), let p = item.platform, !p.isEmpty {
            return normalizePlatform(p)
        }
        // Try research metadata
        if let meta = atom.metadataValue(as: ResearchMetadata.self),
           let source = meta.contentSource, !source.isEmpty {
            return normalizePlatform(source)
        }
        return "unknown"
    }

    private func extractFormat(from atom: Atom, analysis: SwipeAnalysis?) -> String {
        // Try swipe analysis contentFormat
        if let cf = analysis?.swipeContentFormat {
            return cf.rawValue
        }
        // Try framework type as a loose proxy
        if let fw = analysis?.frameworkType {
            return fw.rawValue
        }
        return "unknown"
    }

    private func extractNiche(from atom: Atom, analysis: SwipeAnalysis?) -> String {
        // Try swipe analysis niche field
        if let n = analysis?.niche, !n.isEmpty {
            return n.lowercased()
        }
        return "general"
    }

    private func normalizePlatform(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("instagram") { return "instagram" }
        if lowered.contains("youtube") || lowered == "yt" { return "youtube" }
        if lowered.contains("tiktok") { return "tiktok" }
        if lowered.contains("twitter") || lowered == "x" || lowered == "xpost" { return "x" }
        if lowered.contains("thread") { return "threads" }
        if lowered.contains("linkedin") { return "linkedin" }
        if lowered.contains("newsletter") { return "newsletter" }
        return lowered
    }

    // MARK: - Private: Group Matching

    private func findBestGroup(
        in grouped: [GroupKey: [SwipeEntry]],
        platform: String?,
        format: String?,
        niche: String?
    ) -> [SwipeEntry] {
        // Exact match first
        if let p = platform, let f = format, let n = niche {
            let key = GroupKey(platform: p, format: f, niche: n)
            if let entries = grouped[key], entries.count >= minimumGroupSize {
                return entries
            }
        }

        // Partial matching: collect all entries matching the non-nil dimensions
        var candidates: [SwipeEntry] = []
        for (key, entries) in grouped {
            let platformMatch = platform == nil || key.platform == platform
            let formatMatch = format == nil || key.format == format
            let nicheMatch = niche == nil || key.niche == niche
            if platformMatch && formatMatch && nicheMatch {
                candidates.append(contentsOf: entries)
            }
        }

        if candidates.count >= minimumGroupSize {
            return candidates
        }

        // Fallback: relax niche constraint
        if niche != nil {
            return findBestGroup(in: grouped, platform: platform, format: format, niche: nil)
        }

        // Fallback: relax format constraint
        if format != nil {
            return findBestGroup(in: grouped, platform: platform, format: nil, niche: nil)
        }

        // Last resort: return the largest group
        return grouped.values.max(by: { $0.count < $1.count }) ?? []
    }

    private func inferDimension(from entries: [SwipeEntry], extractor: (SwipeEntry) -> String) -> String? {
        var counts: [String: Int] = [:]
        for entry in entries {
            let val = extractor(entry)
            if val != "unknown" && val != "general" {
                counts[val, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Private: Report Building

    private func buildReport(entries: [SwipeEntry], platform: String, format: String, niche: String) -> MetaPatternReport {
        let total = Double(entries.count)

        // 1. Dominant hooks
        let dominantHooks = buildHookPatterns(entries: entries, total: total)

        // 2. Winning structures
        let winningStructures = buildStructurePatterns(entries: entries, total: total)

        // 3. Emotional arc pattern
        let emotionalArcPattern = analyzeEmotionalArc(entries: entries)

        // 4. Persuasion techniques
        let persuasionTechniques = buildPersuasionPatterns(entries: entries, total: total)

        // 5. Trending vs declining
        let (trending, declining) = analyzeTrends(entries: entries)

        return MetaPatternReport(
            platform: platform,
            format: format,
            niche: niche,
            sampleSize: entries.count,
            generatedAt: Date(),
            dominantHooks: dominantHooks,
            winningStructures: winningStructures,
            emotionalArcPattern: emotionalArcPattern,
            persuasionTechniques: persuasionTechniques,
            trendingTopics: trending,
            decliningPatterns: declining
        )
    }

    private func buildHookPatterns(entries: [SwipeEntry], total: Double) -> [HookPattern] {
        var hookCounts: [String: (count: Int, totalScore: Double)] = [:]

        for entry in entries {
            guard let hookType = entry.analysis?.hookType else { continue }
            let key = hookType.rawValue
            let score = entry.analysis?.effectiveHookScore ?? 0
            var current = hookCounts[key] ?? (count: 0, totalScore: 0)
            current.count += 1
            current.totalScore += score
            hookCounts[key] = current
        }

        return hookCounts
            .map { key, value in
                HookPattern(
                    hookType: SwipeHookType(rawValue: key)?.displayName ?? key,
                    frequency: Double(value.count) / total,
                    avgScore: value.count > 0 ? value.totalScore / Double(value.count) : 0,
                    exampleCount: value.count
                )
            }
            .sorted { $0.frequency > $1.frequency }
    }

    private func buildStructurePatterns(entries: [SwipeEntry], total: Double) -> [StructurePattern] {
        var fwCounts: [String: (count: Int, totalSections: Int)] = [:]

        for entry in entries {
            guard let fw = entry.analysis?.frameworkType else { continue }
            let key = fw.rawValue
            let sectionCount = entry.analysis?.sections?.count ?? 0
            var current = fwCounts[key] ?? (count: 0, totalSections: 0)
            current.count += 1
            current.totalSections += sectionCount
            fwCounts[key] = current
        }

        return fwCounts
            .map { key, value in
                let fwType = SwipeFrameworkType(rawValue: key)
                return StructurePattern(
                    framework: fwType?.displayName ?? key,
                    frequency: Double(value.count) / total,
                    avgSectionCount: value.count > 0 ? value.totalSections / value.count : 0,
                    description: fwType?.description ?? ""
                )
            }
            .sorted { $0.frequency > $1.frequency }
    }

    private func analyzeEmotionalArc(entries: [SwipeEntry]) -> String {
        // Count dominant emotions across the group
        var emotionCounts: [SwipeEmotion: Int] = [:]
        var avgSentiment = 0.0
        var sentimentCount = 0

        for entry in entries {
            if let emotion = entry.analysis?.dominantEmotion {
                emotionCounts[emotion, default: 0] += 1
            }
            if let sentiment = entry.analysis?.sentimentScore {
                avgSentiment += sentiment
                sentimentCount += 1
            }
        }

        let topEmotion = emotionCounts.max(by: { $0.value < $1.value })
        avgSentiment = sentimentCount > 0 ? avgSentiment / Double(sentimentCount) : 0

        // Analyze arc shapes from fingerprints
        var arcShapes: [String: Int] = [:]
        for entry in entries {
            if let fp = entry.analysis?.fingerprint {
                let shape = classifyArcShape(sentimentArc: fp.sentimentArc, intensityArc: fp.intensityArc)
                arcShapes[shape, default: 0] += 1
            }
        }

        let dominantShape = arcShapes.max(by: { $0.value < $1.value })?.key ?? "mixed"
        let emotionLabel = topEmotion?.key.displayName ?? "varied"
        let sentimentLabel = avgSentiment > 0.2 ? "positive" : avgSentiment < -0.2 ? "negative" : "balanced"

        return "\(dominantShape) arc, \(sentimentLabel) sentiment, driven by \(emotionLabel)"
    }

    private func classifyArcShape(sentimentArc: [Double], intensityArc: [Double]) -> String {
        guard sentimentArc.count >= 4, intensityArc.count >= 4 else { return "flat" }

        let earlyIntensity = (intensityArc[0] + intensityArc[1]) / 2
        let lateIntensity = (intensityArc[2] + intensityArc[3]) / 2
        let midDip = intensityArc[1] < intensityArc[0] && intensityArc[2] > intensityArc[1]

        if lateIntensity > earlyIntensity + 0.15 {
            return "steady-rise"
        } else if earlyIntensity > lateIntensity + 0.15 {
            return "front-loaded"
        } else if midDip {
            return "fall-rise"
        } else if abs(lateIntensity - earlyIntensity) < 0.1 {
            return "wave"
        }
        return "mixed"
    }

    private func buildPersuasionPatterns(entries: [SwipeEntry], total: Double) -> [PersuasionPattern] {
        var techniqueCounts: [String: Int] = [:]
        var techniquePairings: [String: [String: Int]] = [:]

        for entry in entries {
            guard let techniques = entry.analysis?.persuasionTechniques else { continue }
            let techNames = techniques.map { $0.type.rawValue }

            for tech in techNames {
                techniqueCounts[tech, default: 0] += 1
            }

            // Track co-occurrences
            for i in 0..<techNames.count {
                for j in (i + 1)..<techNames.count {
                    techniquePairings[techNames[i], default: [:]][techNames[j], default: 0] += 1
                    techniquePairings[techNames[j], default: [:]][techNames[i], default: 0] += 1
                }
            }
        }

        return techniqueCounts
            .map { key, count in
                let pairings = techniquePairings[key] ?? [:]
                let topPairings = pairings
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { PersuasionType(rawValue: $0.key)?.displayName ?? $0.key }

                return PersuasionPattern(
                    technique: PersuasionType(rawValue: key)?.displayName ?? key,
                    frequency: Double(count) / total,
                    commonPairings: topPairings
                )
            }
            .sorted { $0.frequency > $1.frequency }
    }

    private func analyzeTrends(entries: [SwipeEntry]) -> (trending: [String], declining: [String]) {
        let dateFormatter = ISO8601DateFormatter()
        let cutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: Date()) ?? Date()

        var recent: [SwipeEntry] = []
        var older: [SwipeEntry] = []

        for entry in entries {
            if let date = dateFormatter.date(from: entry.atom.createdAt) {
                if date >= cutoff {
                    recent.append(entry)
                } else {
                    older.append(entry)
                }
            }
        }

        guard !recent.isEmpty, !older.isEmpty else {
            return ([], [])
        }

        let recentTotal = Double(recent.count)
        let olderTotal = Double(older.count)

        // Compare hook type frequencies
        var trending: [String] = []
        var declining: [String] = []

        let recentHooks = countHookFrequencies(recent, total: recentTotal)
        let olderHooks = countHookFrequencies(older, total: olderTotal)

        for (hook, recentFreq) in recentHooks {
            let olderFreq = olderHooks[hook] ?? 0
            if recentFreq > olderFreq + 0.15 {
                trending.append(SwipeHookType(rawValue: hook)?.displayName ?? hook)
            }
        }

        for (hook, olderFreq) in olderHooks {
            let recentFreq = recentHooks[hook] ?? 0
            if olderFreq > recentFreq + 0.15 {
                declining.append(SwipeHookType(rawValue: hook)?.displayName ?? hook)
            }
        }

        // Compare framework frequencies
        let recentFw = countFrameworkFrequencies(recent, total: recentTotal)
        let olderFw = countFrameworkFrequencies(older, total: olderTotal)

        for (fw, recentFreq) in recentFw {
            let olderFreq = olderFw[fw] ?? 0
            if recentFreq > olderFreq + 0.15 {
                trending.append(SwipeFrameworkType(rawValue: fw)?.displayName ?? fw)
            }
        }

        for (fw, olderFreq) in olderFw {
            let recentFreq = recentFw[fw] ?? 0
            if olderFreq > recentFreq + 0.15 {
                declining.append(SwipeFrameworkType(rawValue: fw)?.displayName ?? fw)
            }
        }

        return (trending, declining)
    }

    private func countHookFrequencies(_ entries: [SwipeEntry], total: Double) -> [String: Double] {
        var counts: [String: Int] = [:]
        for entry in entries {
            if let hook = entry.analysis?.hookType {
                counts[hook.rawValue, default: 0] += 1
            }
        }
        return counts.mapValues { Double($0) / max(total, 1) }
    }

    private func countFrameworkFrequencies(_ entries: [SwipeEntry], total: Double) -> [String: Double] {
        var counts: [String: Int] = [:]
        for entry in entries {
            if let fw = entry.analysis?.frameworkType {
                counts[fw.rawValue, default: 0] += 1
            }
        }
        return counts.mapValues { Double($0) / max(total, 1) }
    }

    // MARK: - Private: Caching

    private func groupKey(platform: String, format: String, niche: String) -> String {
        return "\(scopePrefix)\(platform)_\(format)_\(niche)"
    }

    private func cacheReport(_ report: MetaPatternReport) async {
        let scope = groupKey(platform: report.platform, format: report.format, niche: report.niche)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let structuredData = try encoder.encode(report)
            let structuredStr = String(data: structuredData, encoding: .utf8)

            let metadataDict: [String: Any] = [
                "scope": scope,
                "key": "meta_pattern_report",
                "platform": report.platform,
                "format": report.format,
                "niche": report.niche,
                "lastUpdated": ISO8601.string(from: Date())
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadataDict)
            let metadataStr = String(data: metadataData, encoding: .utf8)

            let prefAtoms = try await AtomRepository.shared.fetchAll(type: .userPreference)
            let existing = prefAtoms.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == scope
            }

            if var atom = existing {
                atom.structured = structuredStr
                atom.metadata = metadataStr
                _ = try await AtomRepository.shared.update(atom)
            } else {
                let title = "Meta Pattern: \(report.platform) \(report.format) \(report.niche)"
                let atom = Atom.new(
                    type: .userPreference,
                    title: title,
                    structured: structuredStr,
                    metadata: metadataStr
                )
                _ = try await AtomRepository.shared.create(atom)
            }
        } catch {
            print("MetaPatternEngine: Failed to cache report: \(error.localizedDescription)")
        }
    }

    private func loadCachedReport(platform: String, format: String, niche: String) async -> MetaPatternReport? {
        let scope = groupKey(platform: platform, format: format, niche: niche)

        do {
            let prefAtoms = try await AtomRepository.shared.fetchAll(type: .userPreference)
            let atom = prefAtoms.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == scope
            }

            guard let atom = atom,
                  let structuredStr = atom.structured,
                  let data = structuredStr.data(using: .utf8) else { return nil }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MetaPatternReport.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Private: Formatting

    private func formatSummary(_ report: MetaPatternReport) -> String {
        var parts: [String] = []

        let header = "What's working for \(report.platform.capitalized) \(report.format) in \(report.niche) (\(report.sampleSize) swipes):"
        parts.append(header)

        // Dominant hook
        if let topHook = report.dominantHooks.first {
            let pct = String(format: "%.0f", topHook.frequency * 100)
            let scoreStr = String(format: "%.1f", topHook.avgScore)
            parts.append("\(topHook.hookType) hooks dominate (\(pct)%, avg score \(scoreStr)/10)")
        }

        // Winning framework
        if let topFw = report.winningStructures.first {
            let pct = String(format: "%.0f", topFw.frequency * 100)
            parts.append("\(topFw.framework) framework leads (\(pct)%)")
        }

        // Emotional arc
        parts.append("Arc: \(report.emotionalArcPattern)")

        // Persuasion
        if !report.persuasionTechniques.isEmpty {
            let techNames = report.persuasionTechniques.prefix(3).map { $0.technique }
            parts.append("Top persuasion: \(techNames.joined(separator: ", "))")
        }

        // Trends
        if !report.trendingTopics.isEmpty {
            parts.append("Rising: \(report.trendingTopics.joined(separator: ", "))")
        }
        if !report.decliningPatterns.isEmpty {
            parts.append("Declining: \(report.decliningPatterns.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }
}
