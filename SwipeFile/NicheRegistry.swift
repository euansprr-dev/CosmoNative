// CosmoOS/SwipeFile/NicheRegistry.swift
// The canonical niche vocabulary for swipe classification. Backed by
// taxonomy_value atoms (dimension "niche") so Mac, iPhone, and the Railway
// worker converge on one list through normal atom sync — the same store the
// worker already reads for creators. Matching mirrors BeatPatternService
// (exact → known alias → fuzzy) with a niche-specific combo-segment pre-pass
// so "Tax Strategy & Vending Machines" folds into an existing "Tax Strategy &
// Vending Machine Business" instead of spawning a twin.
// July 2026

import Foundation
import GRDB

// MARK: - CanonicalNiche

/// A canonical niche loaded from a taxonomy_value atom.
struct CanonicalNiche: Identifiable, Equatable, Sendable {
    let atomUUID: String
    var value: String
    var aliases: [String]
    var usageCount: Int
    var sortOrder: Int

    var id: String { atomUUID }
}

// MARK: - NicheMatcher (pure, testable)

/// Deterministic label matching — no actors, no DB, directly unit-testable.
/// The three-tier contract (exact → alias → fuzzy ≥ threshold) is shared 1:1
/// with the Railway worker port in cosmo-cloud-agent/src/swipes/niche.ts —
/// change both together.
enum NicheMatcher {

    /// Minimum fuzzy similarity for folding a raw label into a canonical niche.
    static let fuzzyThreshold = 0.60

    enum Match: Equatable {
        case exact(index: Int)
        case alias(index: Int)
        case fuzzy(index: Int, score: Double)
        case none
    }

    /// Case/whitespace-insensitive comparison key.
    static func normalizeKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleaned display label for a brand-new canonical niche: trim, strip
    /// wrapping quotes, collapse whitespace, hard-cap length. Capitalization
    /// is kept as the model wrote it ("SaaS Marketing" must not become
    /// "Saas Marketing").
    static func cleanedCanonicalLabel(from raw: String) -> String {
        var label = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while label.count >= 2,
              let first = label.first, let last = label.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            label = String(label.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if label.count > 48 {
            let cut = String(label.prefix(48))
            label = cut.contains(" ")
                ? cut.split(separator: " ").dropLast().joined(separator: " ")
                : cut
        }
        return label
    }

    /// Split a combo label ("X & Y", "X / Y", "X - Y", "X: Y") into candidate
    /// segments, full label first. Historical fragmentation is dominated by
    /// these mashups, so each segment gets its own shot at a canonical match.
    static func candidateKeys(for raw: String) -> [String] {
        let full = normalizeKey(raw)
        guard !full.isEmpty else { return [] }
        var keys = [full]
        let separators = [" & ", " / ", "/", " - ", " – ", " — ", ": ", ", "]
        var segments = [full]
        for separator in separators {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 3, !keys.contains(trimmed) {
                keys.append(trimmed)
            }
        }
        return keys
    }

    /// Similarity between two normalized keys: token-subsequence containment
    /// (word-boundary-aware, unlike raw substring checks — "AI" must not match
    /// inside "Air Travel") with a length-ratio bonus, else bigram Jaccard.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let tokensA = a.split(separator: " ").map(String.init)
        let tokensB = b.split(separator: " ").map(String.init)
        let (shorter, longer) = tokensA.count <= tokensB.count ? (tokensA, tokensB) : (tokensB, tokensA)
        if shorter.joined().count >= 3, isTokenSubsequence(shorter, of: longer) {
            let shortLen = shorter.joined(separator: " ").count
            let longLen = longer.joined(separator: " ").count
            return 0.6 + 0.4 * (Double(shortLen) / Double(longLen))
        }

        let bigramsA = Set(bigrams(a))
        let bigramsB = Set(bigrams(b))
        guard !bigramsA.isEmpty, !bigramsB.isEmpty else { return 0 }
        let intersection = bigramsA.intersection(bigramsB).count
        let union = bigramsA.union(bigramsB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// Whether `needle`'s tokens appear in order (not necessarily contiguous)
    /// inside `haystack`'s tokens.
    static func isTokenSubsequence(_ needle: [String], of haystack: [String]) -> Bool {
        guard !needle.isEmpty else { return false }
        var index = 0
        for token in haystack where token == needle[index] {
            index += 1
            if index == needle.count { return true }
        }
        return false
    }

    private static func bigrams(_ s: String) -> [String] {
        let chars = Array(s)
        guard chars.count >= 2 else { return [s] }
        return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    }

    /// Three-tier match of a raw label against the canonical list.
    static func bestMatch(raw: String, in niches: [CanonicalNiche]) -> Match {
        let keys = candidateKeys(for: raw)
        guard !keys.isEmpty, !niches.isEmpty else { return .none }

        // Tier 1: exact value match — full label first, then combo segments.
        for key in keys {
            if let index = niches.firstIndex(where: { normalizeKey($0.value) == key }) {
                return .exact(index: index)
            }
        }

        // Tier 2: known alias match.
        for key in keys {
            if let index = niches.firstIndex(where: { niche in
                niche.aliases.contains { normalizeKey($0) == key }
            }) {
                return .alias(index: index)
            }
        }

        // Tier 3: fuzzy — best score over every (key × value/alias) pair.
        var bestScore = 0.0
        var bestIndex: Int?
        for (index, niche) in niches.enumerated() {
            let candidates = [normalizeKey(niche.value)] + niche.aliases.map(normalizeKey)
            for key in keys {
                for candidate in candidates {
                    let score = similarity(key, candidate)
                    if score > bestScore {
                        bestScore = score
                        bestIndex = index
                    }
                }
            }
        }
        if bestScore >= fuzzyThreshold, let index = bestIndex {
            return .fuzzy(index: index, score: bestScore)
        }
        return .none
    }
}

// MARK: - NicheRegistry

@MainActor
final class NicheRegistry {
    static let shared = NicheRegistry()

    static let dimension = "niche"

    /// 60s list cache — batch classification must not refetch the registry
    /// once per swipe (same budget as the creator cache).
    private static let cacheTTL: TimeInterval = 60
    private var cache: (niches: [CanonicalNiche], fetchedAt: Date)?
    private var hasReconciledThisLaunch = false

    private init() {}

    // MARK: - Loading

    func currentNiches() async -> [CanonicalNiche] {
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < Self.cacheTTL {
            return cache.niches
        }
        let fresh = await fetchNiches()
        cache = (fresh, Date())
        if !hasReconciledThisLaunch {
            hasReconciledThisLaunch = true
            await reconcileDuplicates(in: fresh)
        }
        return cache?.niches ?? fresh
    }

    func invalidate() {
        cache = nil
    }

    private func fetchNiches() async -> [CanonicalNiche] {
        let atoms = (try? await AtomRepository.shared.fetchTaxonomyValues(dimension: Self.dimension)) ?? []
        return atoms.compactMap { atom in
            guard let meta = atom.metadataValue(as: TaxonomyValueMetadata.self),
                  meta.dimension == Self.dimension,
                  !meta.value.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return CanonicalNiche(
                atomUUID: atom.uuid,
                value: meta.value,
                aliases: meta.aliases ?? [],
                usageCount: meta.usageCount ?? 0,
                sortOrder: meta.sortOrder
            )
        }
    }

    // MARK: - Prompt vocabulary

    /// Usage-ordered canonical values for classification prompts. Empty string
    /// when the registry is empty (callers render the section conditionally).
    func canonicalListForPrompt() async -> String {
        let niches = await currentNiches()
        return niches
            .sorted { $0.usageCount > $1.usageCount }
            .map(\.value)
            .joined(separator: ", ")
    }

    /// The niche instruction block for classification prompts. One source of
    /// truth for both Mac engines; the Railway worker's buildUnifiedPrompt
    /// renders the same text (keep the wording in sync with
    /// cosmo-cloud-agent/src/swipes/niche.ts nichePromptInstruction).
    nonisolated static func promptInstruction(canonicalList: String) -> String {
        var lines = ["niche — the content's core vertical."]
        if !canonicalList.isEmpty {
            lines.append("EXISTING NICHES (choose one of these whenever it fits — matching an existing niche is strongly preferred): \(canonicalList)")
            lines.append("Only introduce a NEW niche when the content genuinely belongs to a vertical not represented above.")
        }
        lines.append("A niche is a CORE CATEGORY someone builds an audience in (\"Fitness\", \"Content Creation\", \"Real Estate Wholesaling\") — never a sub-topic, a combo (\"X & Y\", \"X / Y\"), or a hook-level description. If the content spans two verticals, pick the one the creator's audience follows them for.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Resolution

    /// Resolve a raw label from any classifier into a canonical niche value,
    /// creating a new canonical niche only when nothing matches. Never throws,
    /// never blocks classification — on any storage failure the cleaned raw
    /// label passes through (the worker port has the same fallback contract).
    func resolve(_ raw: String) async -> String {
        let cleaned = NicheMatcher.cleanedCanonicalLabel(from: raw)
        guard !cleaned.isEmpty else { return raw }

        let niches = await currentNiches()
        switch NicheMatcher.bestMatch(raw: cleaned, in: niches) {
        case .exact(let index):
            await recordUsage(of: niches[index], variant: nil)
            return niches[index].value
        case .alias(let index):
            await recordUsage(of: niches[index], variant: nil)
            return niches[index].value
        case .fuzzy(let index, _):
            await recordUsage(of: niches[index], variant: cleaned)
            return niches[index].value
        case .none:
            return await createNiche(value: cleaned, aliases: []) ?? cleaned
        }
    }

    // MARK: - Mutations

    /// Bump usage and (for fuzzy folds) record the raw variant as an alias so
    /// the next resolution of the same label is a tier-2 hit.
    private func recordUsage(of niche: CanonicalNiche, variant: String?) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: niche.atomUUID),
              var meta = atom.metadataValue(as: TaxonomyValueMetadata.self)
        else { return }

        meta.usageCount = (meta.usageCount ?? 0) + 1
        if let variant {
            let key = NicheMatcher.normalizeKey(variant)
            var aliases = meta.aliases ?? []
            let known = aliases.contains { NicheMatcher.normalizeKey($0) == key }
                || NicheMatcher.normalizeKey(meta.value) == key
            if !known {
                aliases.append(variant)
                meta.aliases = aliases
            }
        }
        atom = atom.withMetadata(meta)
        _ = try? await AtomRepository.shared.update(atom)

        // Patch the cache in place — a usage bump must not force a refetch.
        if var cached = cache {
            if let index = cached.niches.firstIndex(where: { $0.atomUUID == niche.atomUUID }) {
                cached.niches[index].usageCount += 1
                if let variant, !cached.niches[index].aliases
                    .contains(where: { NicheMatcher.normalizeKey($0) == NicheMatcher.normalizeKey(variant) }) {
                    cached.niches[index].aliases.append(variant)
                }
                cache = cached
            }
        }
    }

    /// Create a new canonical niche atom. Refetches and re-matches first —
    /// the 60s cache may hide a niche another device or the worker just
    /// created (same accepted race profile as creator resolution).
    private func createNiche(value: String, aliases: [String]) async -> String? {
        invalidate()
        let fresh = await currentNiches()
        switch NicheMatcher.bestMatch(raw: value, in: fresh) {
        case .exact(let i), .alias(let i), .fuzzy(let i, _):
            await recordUsage(of: fresh[i], variant: value)
            return fresh[i].value
        case .none:
            break
        }

        do {
            let atom = try await AtomRepository.shared.createTaxonomyValue(
                dimension: Self.dimension,
                value: value,
                sortOrder: fresh.count
            )
            if !aliases.isEmpty,
               var created = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
               var meta = created.metadataValue(as: TaxonomyValueMetadata.self) {
                meta.aliases = aliases
                meta.usageCount = 1
                created = created.withMetadata(meta)
                _ = try? await AtomRepository.shared.update(created)
            }
            invalidate()
            return value
        } catch {
            print("NicheRegistry: create failed for \"\(value)\": \(error)")
            return nil
        }
    }

    /// Seed a canonical niche with a known alias set + usage count (backfill
    /// consolidation). Folds into an existing canonical when one matches.
    @discardableResult
    func seed(value: String, aliases: [String], usageCount: Int) async -> String? {
        let cleaned = NicheMatcher.cleanedCanonicalLabel(from: value)
        guard !cleaned.isEmpty else { return nil }

        let niches = await currentNiches()
        switch NicheMatcher.bestMatch(raw: cleaned, in: niches) {
        case .exact(let i), .alias(let i), .fuzzy(let i, _):
            await absorb(aliases: aliases + [cleaned], usage: usageCount, into: niches[i])
            return niches[i].value
        case .none:
            break
        }

        do {
            let atom = try await AtomRepository.shared.createTaxonomyValue(
                dimension: Self.dimension,
                value: cleaned,
                sortOrder: niches.count
            )
            if var created = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
               var meta = created.metadataValue(as: TaxonomyValueMetadata.self) {
                meta.aliases = dedupedAliases(aliases, excludingValue: cleaned)
                meta.usageCount = usageCount
                created = created.withMetadata(meta)
                _ = try? await AtomRepository.shared.update(created)
            }
            invalidate()
            return cleaned
        } catch {
            print("NicheRegistry: seed failed for \"\(cleaned)\": \(error)")
            return nil
        }
    }

    /// Fold a batch of aliases + usage into an existing canonical niche
    /// (backfill seeding path — recordUsage's bulk sibling).
    private func absorb(aliases: [String], usage: Int, into niche: CanonicalNiche) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: niche.atomUUID),
              var meta = atom.metadataValue(as: TaxonomyValueMetadata.self)
        else { return }

        var merged = meta.aliases ?? []
        merged.append(contentsOf: aliases)
        meta.aliases = dedupedAliases(merged, excludingValue: meta.value)
        meta.usageCount = (meta.usageCount ?? 0) + usage
        atom = atom.withMetadata(meta)
        _ = try? await AtomRepository.shared.update(atom)
        invalidate()
    }

    /// Rename a canonical niche. The old value becomes an alias and every
    /// swipe carrying the old string is rewritten to the new one.
    @discardableResult
    func rename(atomUUID: String, to newValue: String) async -> Bool {
        let cleaned = NicheMatcher.cleanedCanonicalLabel(from: newValue)
        guard !cleaned.isEmpty,
              var atom = try? await AtomRepository.shared.fetch(uuid: atomUUID),
              var meta = atom.metadataValue(as: TaxonomyValueMetadata.self)
        else { return false }

        let oldValue = meta.value
        guard NicheMatcher.normalizeKey(oldValue) != NicheMatcher.normalizeKey(cleaned) else {
            // Case-only rename still updates the display value.
            meta.value = cleaned
            atom = atom.withMetadata(meta)
            atom.title = cleaned
            _ = try? await AtomRepository.shared.update(atom)
            invalidate()
            await rewriteSwipes(from: oldValue, to: cleaned)
            return true
        }

        var aliases = meta.aliases ?? []
        if !aliases.contains(where: { NicheMatcher.normalizeKey($0) == NicheMatcher.normalizeKey(oldValue) }) {
            aliases.append(oldValue)
        }
        meta.value = cleaned
        meta.aliases = dedupedAliases(aliases, excludingValue: cleaned)
        atom = atom.withMetadata(meta)
        atom.title = cleaned
        guard (try? await AtomRepository.shared.update(atom)) != nil else { return false }
        invalidate()
        await rewriteSwipes(from: oldValue, to: cleaned)
        return true
    }

    /// Merge one canonical niche into another: aliases + usage fold in, the
    /// source atom is tombstoned, and affected swipes are rewritten.
    @discardableResult
    func merge(sourceUUID: String, intoUUID targetUUID: String) async -> Bool {
        guard sourceUUID != targetUUID,
              var source = try? await AtomRepository.shared.fetch(uuid: sourceUUID),
              let sourceMeta = source.metadataValue(as: TaxonomyValueMetadata.self),
              var target = try? await AtomRepository.shared.fetch(uuid: targetUUID),
              var targetMeta = target.metadataValue(as: TaxonomyValueMetadata.self)
        else { return false }

        var aliases = targetMeta.aliases ?? []
        aliases.append(sourceMeta.value)
        aliases.append(contentsOf: sourceMeta.aliases ?? [])
        targetMeta.aliases = dedupedAliases(aliases, excludingValue: targetMeta.value)
        targetMeta.usageCount = (targetMeta.usageCount ?? 0) + (sourceMeta.usageCount ?? 0)
        target = target.withMetadata(targetMeta)
        guard (try? await AtomRepository.shared.update(target)) != nil else { return false }

        source.isDeleted = true
        _ = try? await AtomRepository.shared.update(source)
        invalidate()
        await rewriteSwipes(from: sourceMeta.value, to: targetMeta.value)
        return true
    }

    // MARK: - Duplicate reconciliation

    /// Worker and Mac can race to create the same niche (find-or-create with
    /// no coordination — the creator-resolution trade-off). Once per launch,
    /// fold case-insensitive duplicate values into the oldest atom.
    private func reconcileDuplicates(in niches: [CanonicalNiche]) async {
        var byKey: [String: [CanonicalNiche]] = [:]
        for niche in niches {
            byKey[NicheMatcher.normalizeKey(niche.value), default: []].append(niche)
        }
        let duplicateGroups = byKey.values.filter { $0.count > 1 }
        guard !duplicateGroups.isEmpty else { return }

        for group in duplicateGroups {
            // Keep the highest-usage atom (ties: lowest sortOrder = oldest).
            let sorted = group.sorted {
                if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                return $0.sortOrder < $1.sortOrder
            }
            let winner = sorted[0]
            for loser in sorted.dropFirst() {
                await merge(sourceUUID: loser.atomUUID, intoUUID: winner.atomUUID)
            }
        }
        invalidate()
    }

    // MARK: - Swipe rewriting

    /// Rewrite every swipe whose analysis carries `oldValue` to `newValue`.
    func rewriteSwipes(from oldValue: String, to newValue: String) async {
        guard oldValue != newValue else { return }
        await rewriteSwipes(mapping: [NicheMatcher.normalizeKey(oldValue): newValue])
    }

    /// Batch form: one pass over the library applying a normalized-raw-key →
    /// canonical-value mapping (backfill consolidation rewrites ~140 labels;
    /// per-label table scans would be quadratic). Same write discipline as
    /// persistAnalysis: fresh fetch, skip open editors, field-level
    /// structured write only.
    func rewriteSwipes(mapping: [String: String]) async {
        guard !mapping.isEmpty else { return }

        let atoms = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(sql: "structured LIKE ?", arguments: ["%\"niche\":%"])
                .fetchAll(db)
        }) ?? []

        var rewritten = 0
        for atom in atoms {
            guard atom.isSwipeFileAtom,
                  let niche = atom.swipeAnalysis?.niche,
                  let newValue = mapping[NicheMatcher.normalizeKey(niche)],
                  niche != newValue,
                  !AtomRepository.shared.isBeingEdited(atom.uuid)
            else { continue }

            guard let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid),
                  var analysis = fresh.swipeAnalysis,
                  let freshNiche = analysis.niche,
                  let freshNewValue = mapping[NicheMatcher.normalizeKey(freshNiche)],
                  freshNiche != freshNewValue
            else { continue }

            analysis.niche = freshNewValue
            let updated = fresh.withSwipeAnalysis(analysis)
            do {
                _ = try await AtomRepository.shared.updateFields(uuid: atom.uuid, columns: [
                    "structured": updated.structured,
                ])
                rewritten += 1
            } catch {
                PersistenceHealth.note(
                    .writeFailure,
                    context: "NicheRegistry.rewriteSwipes(\(atom.uuid.prefix(8)))",
                    detail: error.localizedDescription
                )
            }
        }
        if rewritten > 0 {
            print("NicheRegistry: Rewrote \(rewritten) swipe niches (\(mapping.count) mapping(s))")
            NotificationCenter.default.post(
                name: CosmoNotification.SwipeFile.libraryDidChange, object: nil
            )
        }
    }

    // MARK: - Helpers

    private func dedupedAliases(_ aliases: [String], excludingValue value: String) -> [String] {
        let valueKey = NicheMatcher.normalizeKey(value)
        var seen = Set<String>()
        var result: [String] = []
        for alias in aliases {
            let key = NicheMatcher.normalizeKey(alias)
            guard !key.isEmpty, key != valueKey, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(alias)
        }
        return result
    }
}
