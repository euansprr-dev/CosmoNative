// CosmoOS/Data/Import/CodexImporter.swift
// Parses the Exemplar Codex text into individual addressable atoms.
// Idempotent: skips elements that already exist as atoms.

import Foundation
import os

// MARK: - Import Result

struct CodexImportResult: Sendable {
    let elementsCreated: Int
    let walkthroughsCreated: Int
    let skipped: Int
    let cleaned: Int
    let errors: [String]
}

// MARK: - Import Errors

enum CodexImportError: Error, LocalizedError {
    case codexNotFound
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "No research atom with isCodexSynthesis metadata found"
        case .encodingFailed(let name):
            return "Failed to encode CodexElement for \(name)"
        }
    }
}

// MARK: - Codex Importer

@MainActor
final class CodexImporter {

    private let logger = Logger(subsystem: "com.cosmo.codex", category: "CodexImporter")

    // MARK: - Main Import

    // MARK: - Junk Detection

    /// Names that are section headers, not real codex elements
    private func isJunkName(_ name: String) -> Bool {
        let key = name.lowercased()
        let junkPrefixes = [
            "walkthrough", "law ", "pass ", "reel examples", "carousel examples",
            "hypothesis", "deep structure", "interactions", "conversational dna",
            "detailed reference", "foundation", "curation", "state change through",
        ]
        return name.contains(":") // Section headers have colons
            || name.count > 50    // Real element names are short
            || junkPrefixes.contains(where: { key.hasPrefix($0) })
    }

    // MARK: - Cleanup

    /// Nuclear cleanup: delete ALL codex element and walkthrough atoms for a fresh reimport.
    /// Previous imports left the DB in a dirty state with partial/duplicated data.
    func cleanupJunkAtoms() async throws -> Int {
        let allElements = try await AtomRepository.shared.fetchAll(type: .codexElement)
        let allWalkthroughs = try await AtomRepository.shared.fetchAll(type: .codexWalkthrough)
        var deleted = 0

        // Delete ALL codex elements — fresh start
        for atom in allElements {
            try await AtomRepository.shared.hardDelete(uuid: atom.uuid, confirmed: true)
            deleted += 1
        }

        // Delete ALL codex walkthroughs — fresh start
        for atom in allWalkthroughs {
            try await AtomRepository.shared.hardDelete(uuid: atom.uuid, confirmed: true)
            deleted += 1
        }

        logger.info("Nuclear cleanup: deleted \(deleted) codex atoms (all elements + walkthroughs)")
        return deleted
    }

    // MARK: - Main Import

    func importCodex() async throws -> CodexImportResult {
        // Step 0: Cleanup junk from previous imports
        let cleaned = try await cleanupJunkAtoms()

        // Step 1: Find the codex research atom
        let allResearch = try await AtomRepository.shared.fetchAll(type: .research)
        guard let codexAtom = allResearch.first(where: {
            if let metaStr = $0.metadata,
               let data = metaStr.data(using: .utf8),
               let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               meta["isCodexSynthesis"] as? Bool == true {
                return true
            }
            return false
        }) else {
            throw CodexImportError.codexNotFound
        }

        guard let codexBody = codexAtom.body, !codexBody.isEmpty else {
            throw CodexImportError.codexNotFound
        }

        logger.info("Found codex atom: \(codexAtom.uuid), body length: \(codexBody.count)")

        // Step 2: Check which canonical names already exist (for idempotency)
        let existingElements = try await AtomRepository.shared.fetchAll(type: .codexElement)
        let existingNames = Set(existingElements.compactMap { $0.codexCanonicalName?.lowercased() })

        logger.info("Existing codex elements: \(existingNames.count)")

        var elementsCreated = 0
        var skipped = 0
        var errors: [String] = []

        // Step 3: Parse periodic table entries
        // Format: **NAME | CATEGORY | definition text | frequency**
        var parsedElements: [String: CodexElement] = [:]

        let periodicPattern = /\*\*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\*\*/
        for match in codexBody.matches(of: periodicPattern) {
            let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
            let categoryStr = String(match.output.2).trimmingCharacters(in: .whitespaces)
            let definition = String(match.output.3).trimmingCharacters(in: .whitespaces)
            let frequency = String(match.output.4).trimmingCharacters(in: .whitespaces)

            let key = name.lowercased()

            // Filter out junk matches (section headers, walkthrough titles, etc.)
            if isJunkName(name) {
                logger.info("Skipped junk periodic table match: \(name)")
                continue
            }

            // Skip if already exists
            if existingNames.contains(key) {
                skipped += 1
                continue
            }

            // Skip if already parsed in this run
            if parsedElements[key] != nil { continue }

            let category = mapCategory(categoryStr)

            parsedElements[key] = CodexElement(
                canonicalName: name,
                category: category,
                definition: definition,
                frequency: frequency,
                examples: [],
                applicationRules: [],
                antiPatterns: [],
                readerEffect: nil,
                whereActive: [],
                whyItWorks: nil,
                patterns: [],
                variants: []
            )
        }

        // Step 4: Parse deep concept entries (═══ headers) for richer data
        // Store FULL text as atom body + best-effort parsed fields
        let sections = codexBody.components(separatedBy: "═══")
        var deepEntryBodies: [String: String] = [:]  // key → full entry text
        var sectionIdx = 1
        while sectionIdx < sections.count {
            let header = sections[sectionIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = sectionIdx + 1 < sections.count ? sections[sectionIdx + 1] : ""

            // Must have parenthetical to be a concept header
            guard header.contains("("), header.contains(")") else {
                sectionIdx += 1
                continue
            }

            // Extract concept name (before the first parenthesis)
            guard let parenIdx = header.firstIndex(of: "(") else {
                sectionIdx += 1
                continue
            }
            let conceptName = String(header[header.startIndex..<parenIdx]).trimmingCharacters(in: .whitespaces)

            // Skip junk/non-concept headers
            let upperName = conceptName.uppercased()
            if conceptName.isEmpty || conceptName.count <= 1
                || upperName.hasPrefix("WALKTHROUGH")
                || upperName.hasPrefix("LAW")
                || upperName.contains("EXAMPLES:")
                || upperName.hasPrefix("DETAILED")
                || upperName.hasPrefix("PASS ")
                || isJunkName(conceptName) {
                sectionIdx += 1
                continue
            }

            // Store full entry text
            let fullEntryText = "═══ \(header) ═══\n\n\(body)"

            // Extract best-effort structured fields
            let enrichment = extractDeepEntryData(from: body)

            // Find matching key using multi-strategy matching
            let allKeys = Set(parsedElements.keys)
            let matchKey = findMatchingKey(conceptName, in: allKeys)

            if let matchKey, let existing = parsedElements[matchKey] {
                // Enrich in-memory element
                parsedElements[matchKey] = CodexElement(
                    canonicalName: existing.canonicalName,
                    category: existing.category,
                    definition: (existing.definition.isEmpty ? enrichment.definition : existing.definition) ?? existing.definition,
                    frequency: existing.frequency ?? enrichment.frequency,
                    examples: enrichment.examples.isEmpty ? existing.examples : enrichment.examples,
                    applicationRules: enrichment.applicationRules.isEmpty ? existing.applicationRules : enrichment.applicationRules,
                    antiPatterns: enrichment.antiPatterns.isEmpty ? existing.antiPatterns : enrichment.antiPatterns,
                    readerEffect: enrichment.readerEffect ?? existing.readerEffect,
                    whereActive: enrichment.whereActive.isEmpty ? existing.whereActive : enrichment.whereActive,
                    whyItWorks: enrichment.whyItWorks ?? existing.whyItWorks,
                    patterns: existing.patterns,
                    variants: existing.variants,
                    operationalRecipe: enrichment.operationalRecipe ?? existing.operationalRecipe,
                    generationRecipe: enrichment.generationRecipe ?? existing.generationRecipe,
                    formatConstraints: enrichment.formatConstraints ?? existing.formatConstraints,
                    reelExamples: enrichment.reelExamples.isEmpty ? existing.reelExamples : enrichment.reelExamples,
                    carouselExamples: enrichment.carouselExamples.isEmpty ? existing.carouselExamples : enrichment.carouselExamples,
                    antiExampleFix: enrichment.antiExampleFix ?? existing.antiExampleFix
                )
                deepEntryBodies[matchKey] = fullEntryText
            } else {
                // Try to find and update existing DB atom
                let dbMatchKey = findMatchingKey(conceptName, in: existingNames)
                if dbMatchKey != nil {
                    // Element exists in DB — update with enrichment + full body
                    let dbResult = try? await CodexRepository.shared.fetchElement(canonicalName: conceptName)
                    let fallbackResult: (Atom, CodexElement)? = dbResult == nil
                        ? (try? await CodexRepository.shared.searchElements(query: conceptName.components(separatedBy: " / ").first ?? conceptName))?.first
                        : nil
                    if let (dbAtom, dbElement) = dbResult ?? fallbackResult {
                        let enriched = CodexElement(
                            canonicalName: dbElement.canonicalName,
                            category: dbElement.category,
                            definition: (dbElement.definition.isEmpty ? enrichment.definition : dbElement.definition) ?? dbElement.definition,
                            frequency: dbElement.frequency ?? enrichment.frequency,
                            examples: enrichment.examples.isEmpty ? dbElement.examples : enrichment.examples,
                            applicationRules: enrichment.applicationRules.isEmpty ? dbElement.applicationRules : enrichment.applicationRules,
                            antiPatterns: enrichment.antiPatterns.isEmpty ? dbElement.antiPatterns : enrichment.antiPatterns,
                            readerEffect: enrichment.readerEffect ?? dbElement.readerEffect,
                            whereActive: enrichment.whereActive.isEmpty ? dbElement.whereActive : enrichment.whereActive,
                            whyItWorks: enrichment.whyItWorks ?? dbElement.whyItWorks,
                            patterns: dbElement.patterns,
                            variants: dbElement.variants,
                            operationalRecipe: enrichment.operationalRecipe ?? dbElement.operationalRecipe,
                            generationRecipe: enrichment.generationRecipe ?? dbElement.generationRecipe,
                            formatConstraints: enrichment.formatConstraints ?? dbElement.formatConstraints,
                            reelExamples: enrichment.reelExamples.isEmpty ? dbElement.reelExamples : enrichment.reelExamples,
                            carouselExamples: enrichment.carouselExamples.isEmpty ? dbElement.carouselExamples : enrichment.carouselExamples,
                            antiExampleFix: enrichment.antiExampleFix ?? dbElement.antiExampleFix
                        )
                        if let data = try? JSONEncoder().encode(enriched),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            var updatedAtom = dbAtom
                            updatedAtom.structured = jsonStr
                            updatedAtom.body = fullEntryText  // FULL deep entry text
                            _ = try? await AtomRepository.shared.update(updatedAtom)
                            logger.info("Enriched DB element with full text: \(conceptName)")
                        }
                    }
                } else if !existingNames.contains(conceptName.lowercased()) {
                    // New element from deep entry only (no periodic table match)
                    let catMatch = header.firstMatch(of: /\{?Category:\s*(.+?)\}?\)/)
                        ?? header.firstMatch(of: /\((.+?)\)/)
                    let catStr = catMatch.map { String($0.output.1) } ?? "Technique"
                    let category = mapCategory(catStr.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? catStr)

                    // Extract definition from DEFINITION: section or first paragraph
                    var definition = ""
                    if let defRange = body.range(of: "DEFINITION:", options: .caseInsensitive) {
                        let afterDef = body[defRange.upperBound...]
                        if let endIdx = afterDef.range(of: "\n\n")?.lowerBound {
                            definition = String(afterDef[..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            definition = String(afterDef.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else {
                        definition = body.components(separatedBy: "\n\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }

                    // Extract frequency
                    var frequency: String? = nil
                    if let freqRange = body.range(of: "FREQUENCY:", options: .caseInsensitive) {
                        let afterFreq = body[freqRange.upperBound...]
                        if let lineEnd = afterFreq.firstIndex(of: "\n") {
                            frequency = String(afterFreq[..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }

                    let newKey = conceptName.lowercased()
                    parsedElements[newKey] = CodexElement(
                        canonicalName: conceptName,
                        category: category,
                        definition: definition,
                        frequency: frequency,
                        examples: enrichment.examples,
                        applicationRules: enrichment.applicationRules,
                        antiPatterns: enrichment.antiPatterns,
                        readerEffect: enrichment.readerEffect,
                        whereActive: enrichment.whereActive,
                        whyItWorks: enrichment.whyItWorks,
                        patterns: [],
                        variants: [],
                        operationalRecipe: enrichment.operationalRecipe,
                        generationRecipe: enrichment.generationRecipe,
                        formatConstraints: enrichment.formatConstraints,
                        reelExamples: enrichment.reelExamples,
                        carouselExamples: enrichment.carouselExamples,
                        antiExampleFix: enrichment.antiExampleFix
                    )
                    deepEntryBodies[newKey] = fullEntryText
                }
            }

            sectionIdx += 2
        }

        // Also store standalone sections as elements
        let standaloneSections = ["INTERACTIONS", "DEEP STRUCTURE", "HYPOTHESIS TEST RESULTS", "CONVERSATIONAL DNA"]
        for name in standaloneSections {
            let searchPattern = "═══ \(name)"
            if let range = codexBody.range(of: searchPattern, options: .caseInsensitive) {
                let afterHeader = codexBody[range.upperBound...]
                let bodyEnd = afterHeader.range(of: "═══")?.lowerBound ?? afterHeader.endIndex
                let sectionBody = String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased().replacingOccurrences(of: " ", with: "_")

                if !existingNames.contains(key) && parsedElements[key] == nil {
                    parsedElements[key] = CodexElement(
                        canonicalName: name.replacingOccurrences(of: " ", with: "_"),
                        category: .technique,
                        definition: String(sectionBody.prefix(200)),
                        frequency: nil,
                        examples: [], applicationRules: [], antiPatterns: [],
                        readerEffect: nil, whereActive: [], whyItWorks: nil,
                        patterns: [], variants: []
                    )
                    deepEntryBodies[key] = "═══ \(name) ═══\n\n\(sectionBody)"
                }
            }
        }

        // Persist all parsed elements as atoms
        for (key, element) in parsedElements {
            do {
                guard let elementJSON = try? JSONEncoder().encode(element),
                      let structuredStr = String(data: elementJSON, encoding: .utf8) else {
                    errors.append("Failed to encode: \(element.canonicalName)")
                    continue
                }

                // Use full deep entry text as body if available, otherwise definition
                let bodyText = deepEntryBodies[key] ?? element.definition

                try await AtomRepository.shared.create(
                    type: .codexElement,
                    title: element.canonicalName,
                    body: bodyText,
                    structured: structuredStr
                )
                elementsCreated += 1
                logger.info("Created codex element: \(element.canonicalName)")
            } catch {
                errors.append("\(element.canonicalName): \(error.localizedDescription)")
                logger.error("Failed to create element \(element.canonicalName): \(error.localizedDescription)")
            }
        }

        // Step 5: Parse Laws section
        let lawsCreated = await parseLaws(codexBody: codexBody, existingNames: existingNames, errors: &errors)
        elementsCreated += lawsCreated

        // Step 6: Parse variant mappings and update existing elements
        await parseVariantMappings(codexBody: codexBody)

        // Step 7: Parse the 10 canonical walkthroughs from the codex text
        let codexWalkthroughsCreated = await parseCodexWalkthroughs(codexBody: codexBody, errors: &errors)

        // Step 8: Atomize walkthroughs from swipe atoms with codex profiles ONLY
        let swipeWalkthroughsCreated = try await importWalkthroughs()
        let walkthroughsCreated = codexWalkthroughsCreated + swipeWalkthroughsCreated

        // Reload the CodexRepository cache
        try? await CodexRepository.shared.reload()

        let result = CodexImportResult(
            elementsCreated: elementsCreated,
            walkthroughsCreated: walkthroughsCreated,
            skipped: skipped,
            cleaned: cleaned,
            errors: errors
        )

        logger.info("Codex import complete: \(elementsCreated) elements, \(walkthroughsCreated) walkthroughs, \(cleaned) cleaned, \(skipped) skipped")

        return result
    }

    // MARK: - Deep Entry Data Extraction

    private struct DeepEntryData {
        var definition: String?
        var frequency: String?
        var examples: [CodexExample] = []
        var applicationRules: [String] = []
        var antiPatterns: [String] = []
        var readerEffect: String?
        var whereActive: [String] = []
        var whyItWorks: String?
        // Pass 2 fields
        var operationalRecipe: String?
        var generationRecipe: CodexGenerationRecipe?
        var formatConstraints: CodexFormatConstraints?
        var reelExamples: [CodexExample] = []
        var carouselExamples: [CodexExample] = []
        var antiExampleFix: CodexAntiExampleFix?
    }

    private func extractDeepEntryData(from body: String) -> DeepEntryData {
        var result = DeepEntryData()
        let lines = body.components(separatedBy: "\n")

        // ---- EXAMPLES: block-based extraction (captures ALL multi-line examples) ----
        var inExamplesSection = false
        var currentExampleLines: [String] = []
        var lineIdx = 0

        while lineIdx < lines.count {
            let line = lines[lineIdx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect examples section start
            if !inExamplesSection {
                if trimmed.uppercased().hasPrefix("EXAMPLES") || trimmed.uppercased().hasPrefix("REAL EXAMPLES") || trimmed.uppercased().hasPrefix("### REAL EXAMPLES") || trimmed.uppercased().hasPrefix("### EXAMPLES") {
                    inExamplesSection = true
                    lineIdx += 1
                    continue
                }
                lineIdx += 1
                continue
            }

            // Detect section end (standalone section header)
            if isStandaloneSectionHeader(trimmed) {
                // Flush current example block
                if !currentExampleLines.isEmpty {
                    if let ex = parseExampleBlock(currentExampleLines) {
                        result.examples.append(ex)
                    }
                    currentExampleLines = []
                }
                inExamplesSection = false
                lineIdx += 1
                continue
            }

            // Detect new numbered example start: line starts with "N." or "N. "
            let isNewNumberedExample = isNumberedExampleStart(trimmed)

            if isNewNumberedExample && !currentExampleLines.isEmpty {
                // Flush previous example block
                if let ex = parseExampleBlock(currentExampleLines) {
                    result.examples.append(ex)
                }
                currentExampleLines = []
            }

            // Accumulate lines for current example
            if isNewNumberedExample || (!currentExampleLines.isEmpty && !trimmed.isEmpty) {
                currentExampleLines.append(trimmed)
            }

            lineIdx += 1
        }

        // Flush final example
        if !currentExampleLines.isEmpty {
            if let ex = parseExampleBlock(currentExampleLines) {
                result.examples.append(ex)
            }
        }

        // ---- STANDALONE SECTIONS (NOT per-example metadata) ----
        // These are sections that start at column 0 as their own header

        // Anti-patterns: find "### ANTI-PATTERNS" or "ANTI-PATTERNS" standalone header
        result.antiPatterns = extractStandaloneSection(from: body,
            headers: ["### ANTI-PATTERNS", "ANTI-PATTERNS"],
            lineFilter: { $0.hasPrefix("- ") || $0.hasPrefix("Bad:") || $0.hasPrefix("• ") })

        // Application rules: find "### HOW TO APPLY" or "HOW TO APPLY" standalone header
        // NOT per-example "How to apply:" lines (those are indented/inline)
        result.applicationRules = extractStandaloneSection(from: body,
            headers: ["### HOW TO APPLY", "HOW TO APPLY"],
            lineFilter: { $0.hasPrefix("- ") || $0.hasPrefix("• ") || $0.hasPrefix("Use ") || $0.hasPrefix("Best ") })

        // Patterns section
        let patterns = extractStandaloneSection(from: body,
            headers: ["### PATTERNS", "PATTERNS:"],
            lineFilter: { $0.hasPrefix("- ") || $0.hasPrefix("• ") })
        if !patterns.isEmpty { result.applicationRules += patterns }  // Merge patterns into rules

        // Reader effect — standalone header only
        if let effectLine = findStandaloneField(in: body, headers: ["### READER EFFECT", "READER EFFECT:"]) {
            result.readerEffect = effectLine
        }

        // Why it works — standalone section
        if let whyLine = findStandaloneField(in: body, headers: ["### WHY IT WORKS", "WHY IT WORKS"]) {
            result.whyItWorks = whyLine
        }

        // Where active — standalone header
        if let whereLine = findStandaloneField(in: body, headers: ["### WHERE ACTIVE", "WHERE ACTIVE:"]) {
            result.whereActive = whereLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        // Definition — look for "DEFINITION:" or "**DEFINITION:**" or first paragraph
        if let defLine = findStandaloneField(in: body, headers: ["DEFINITION:", "**DEFINITION:**", "**DEFINITION**"]) {
            result.definition = defLine
        } else {
            // First meaningful paragraph as definition
            let firstPara = body.components(separatedBy: "\n\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("FREQUENCY")
                    && !$0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("EXAMPLES")
                })?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let para = firstPara, para.count > 10 {
                result.definition = para
            }
        }

        // Frequency
        if let freqLine = findStandaloneField(in: body, headers: ["FREQUENCY:", "**FREQUENCY:**"]) {
            result.frequency = freqLine
        }

        // ---- Pass 2 fields ----

        // Operational recipe
        if let recipe = findStandaloneField(in: body, headers: ["OPERATIONAL RECIPE:"]) {
            result.operationalRecipe = recipe
        }

        // Generation recipe (steps + common mistakes)
        result.generationRecipe = parseGenerationRecipe(from: body)

        // Format constraints
        result.formatConstraints = parseFormatConstraints(from: body)

        // Reel examples
        result.reelExamples = parseFormatExamples(from: body, header: "REEL EXAMPLES")

        // Carousel examples
        result.carouselExamples = parseFormatExamples(from: body, header: "CAROUSEL EXAMPLES")

        // Anti-example with fix
        result.antiExampleFix = parseAntiExampleFix(from: body)

        return result
    }

    /// Check if a line starts a new numbered example (e.g., "1.", "2.", "15.")
    private func isNumberedExampleStart(_ line: String) -> Bool {
        let clean = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        guard let first = clean.first, first.isNumber else { return false }
        // Must have a period after the number(s)
        if let dotRange = clean.range(of: ".") {
            let beforeDot = clean[clean.startIndex..<dotRange.lowerBound]
            return beforeDot.allSatisfy(\.isNumber) && beforeDot.count <= 2
        }
        return false
    }

    /// Check if a line is a standalone section header (should end example capture)
    /// CRITICAL: per-example metadata like "Why it works:" is NOT a section header.
    /// Only ALL-CAPS headers or ### headers count as section boundaries.
    private func isStandaloneSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()

        // ### headers are always section boundaries
        if upper.hasPrefix("### ") || upper.hasPrefix("═══") { return true }

        // These are section headers ONLY when the line IS the header (all caps or very short)
        // Per-example "Why it works: ..." is NOT a section header
        let sectionHeaders = ["ANTI-PATTERNS", "PATTERNS:", "STRONG FORMS",
                               "REEL EXAMPLES", "CAROUSEL EXAMPLES",
                               "OPERATIONAL RECIPE", "GENERATION RECIPE",
                               "FORMAT-SPECIFIC CONSTRAINTS", "FORMAT CONSTRAINTS",
                               "ANTI-EXAMPLE WITH FIX", "ANTI-EXAMPLE:"]
        if sectionHeaders.contains(where: { upper.hasPrefix($0) }) { return true }

        // These keywords are section headers ONLY when they appear alone on a line
        // (not followed by a colon and immediate content, which indicates per-example metadata)
        let ambiguousHeaders = ["WHY IT WORKS", "HOW TO APPLY", "WHERE ACTIVE", "READER EFFECT"]
        for header in ambiguousHeaders {
            if upper.hasPrefix(header) {
                // If the line is JUST the header (maybe with trailing colon), it's a section header
                // If it has content after ":" on the same line, it's per-example metadata
                let afterHeader = String(trimmed.dropFirst(header.count)).trimmingCharacters(in: .whitespaces)
                if afterHeader.isEmpty || afterHeader == ":" { return true }
                // "WHY IT WORKS\n..." with no content = section header
                // "Why it works: The sequence..." = per-example metadata (NOT a header)
                return false
            }
        }

        return false
    }

    // MARK: - Pass 2 Parsers

    /// Parse GENERATION RECIPE section: numbered steps + common mistakes
    private func parseGenerationRecipe(from body: String) -> CodexGenerationRecipe? {
        let lines = body.components(separatedBy: "\n")
        var inRecipe = false
        var inMistakes = false
        var steps: [String] = []
        var mistakes: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if upper.hasPrefix("GENERATION RECIPE") {
                inRecipe = true
                inMistakes = false
                continue
            }

            if inRecipe && upper.hasPrefix("COMMON MISTAKES") {
                inMistakes = true
                continue
            }

            // End of section
            if inRecipe && isStandaloneSectionHeader(trimmed) && !upper.hasPrefix("COMMON MISTAKES") {
                break
            }

            guard inRecipe else { continue }

            if inMistakes {
                let cleaned = trimmed.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                if !cleaned.isEmpty { mistakes.append(cleaned) }
            } else if trimmed.hasPrefix("Step ") || trimmed.range(of: #"^\d+[.):]\s"#, options: .regularExpression) != nil {
                // Strip "Step N: " or "N. " prefix
                var step = trimmed
                if let colonRange = step.range(of: ": ") {
                    let prefix = step[step.startIndex..<colonRange.lowerBound]
                    if prefix.contains("Step") || prefix.allSatisfy({ $0.isNumber || $0 == "." }) {
                        step = String(step[colonRange.upperBound...])
                    }
                }
                if !step.isEmpty { steps.append(step) }
            }
        }

        guard !steps.isEmpty else { return nil }
        return CodexGenerationRecipe(steps: steps, commonMistakes: mistakes)
    }

    /// Parse FORMAT-SPECIFIC CONSTRAINTS or FORMAT CONSTRAINTS section
    private func parseFormatConstraints(from body: String) -> CodexFormatConstraints? {
        let lines = body.components(separatedBy: "\n")
        var inSection = false
        var reel = ""
        var carousel = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if upper.hasPrefix("FORMAT-SPECIFIC CONSTRAINTS") || upper.hasPrefix("FORMAT CONSTRAINTS") {
                inSection = true
                continue
            }

            if inSection && isStandaloneSectionHeader(trimmed)
                && !upper.hasPrefix("FORMAT") && !upper.hasPrefix("- REEL") && !upper.hasPrefix("- CAROUSEL") {
                break
            }

            guard inSection else { continue }

            if upper.hasPrefix("- REEL") || upper.hasPrefix("REEL (") || upper.hasPrefix("REEL:") {
                let content = trimmed.replacingOccurrences(of: #"^-?\s*REEL[^:]*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                reel = content
            } else if upper.hasPrefix("- CAROUSEL") || upper.hasPrefix("CAROUSEL (") || upper.hasPrefix("CAROUSEL:") {
                let content = trimmed.replacingOccurrences(of: #"^-?\s*CAROUSEL[^:]*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                carousel = content
            }
        }

        guard !reel.isEmpty || !carousel.isEmpty else { return nil }
        return CodexFormatConstraints(reel: reel, carousel: carousel)
    }

    /// Parse format-specific example sections (REEL EXAMPLES or CAROUSEL EXAMPLES)
    private func parseFormatExamples(from body: String, header: String) -> [CodexExample] {
        let lines = body.components(separatedBy: "\n")
        var inSection = false
        var currentExampleLines: [String] = []
        var examples: [CodexExample] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if upper.hasPrefix(header.uppercased()) {
                inSection = true
                continue
            }

            guard inSection else { continue }

            // End of section
            if isStandaloneSectionHeader(trimmed) && !upper.hasPrefix(header.uppercased()) {
                if !currentExampleLines.isEmpty {
                    if let ex = parseExampleBlock(currentExampleLines) { examples.append(ex) }
                    currentExampleLines = []
                }
                break
            }

            let isNewExample = isNumberedExampleStart(trimmed)
            if isNewExample && !currentExampleLines.isEmpty {
                if let ex = parseExampleBlock(currentExampleLines) { examples.append(ex) }
                currentExampleLines = []
            }

            if isNewExample || (!currentExampleLines.isEmpty && !trimmed.isEmpty) {
                currentExampleLines.append(trimmed)
            }
        }

        // Flush final
        if !currentExampleLines.isEmpty {
            if let ex = parseExampleBlock(currentExampleLines) { examples.append(ex) }
        }

        return examples
    }

    /// Parse ANTI-EXAMPLE WITH FIX section
    private func parseAntiExampleFix(from body: String) -> CodexAntiExampleFix? {
        let lines = body.components(separatedBy: "\n")
        var inSection = false
        var bad = ""
        var whyFails = ""
        var fixed = ""
        var whyWorks = ""
        var currentField = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if upper.hasPrefix("ANTI-EXAMPLE WITH FIX") || upper.hasPrefix("ANTI-EXAMPLE:") {
                inSection = true
                continue
            }

            guard inSection else { continue }

            // End of section
            if isStandaloneSectionHeader(trimmed)
                && !upper.hasPrefix("BAD:") && !upper.hasPrefix("WHY IT FAILS")
                && !upper.hasPrefix("FIXED:") && !upper.hasPrefix("WHY THE FIX WORKS") {
                break
            }

            if upper.hasPrefix("BAD:") {
                currentField = "bad"
                let content = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                bad = content
            } else if upper.hasPrefix("WHY IT FAILS:") {
                currentField = "whyFails"
                whyFails = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("FIXED:") {
                currentField = "fixed"
                let content = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                fixed = content
            } else if upper.hasPrefix("WHY THE FIX WORKS:") {
                currentField = "whyWorks"
                whyWorks = String(trimmed.dropFirst(18)).trimmingCharacters(in: .whitespaces)
            } else if !trimmed.isEmpty {
                // Continuation of current field
                switch currentField {
                case "bad": bad += " " + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                case "whyFails": whyFails += " " + trimmed
                case "fixed": fixed += " " + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                case "whyWorks": whyWorks += " " + trimmed
                default: break
                }
            }
        }

        guard !bad.isEmpty && !fixed.isEmpty else { return nil }
        return CodexAntiExampleFix(bad: bad, whyItFails: whyFails, fixed: fixed, whyTheFixWorks: whyWorks)
    }

    /// Parse a block of lines into a CodexExample
    private func parseExampleBlock(_ blockLines: [String]) -> CodexExample? {
        guard !blockLines.isEmpty else { return nil }

        var quotedTexts: [String] = []
        var postRef = ""
        var mechanism = ""

        for line in blockLines {
            let clean = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)

            // Post reference
            if clean.hasPrefix("—") || (clean.hasPrefix("[") && clean.contains("]")) {
                postRef = clean.replacingOccurrences(of: "—", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }

            // Mechanism metadata
            if clean.lowercased().hasPrefix("why it works:") || clean.lowercased().hasPrefix("how to apply:")
                || clean.lowercased().hasPrefix("reader effect:") || clean.lowercased().hasPrefix("where active:") {
                mechanism += (mechanism.isEmpty ? "" : "\n") + clean
                continue
            }

            // Quoted text (extract content between quotes)
            if clean.contains("\"") {
                // Extract ALL quoted segments from this line
                var remaining = clean
                // Strip leading number like "1. " or "15. "
                if let dotRange = remaining.range(of: ". ") {
                    let prefix = remaining[remaining.startIndex..<dotRange.lowerBound]
                    if prefix.allSatisfy(\.isNumber) {
                        remaining = String(remaining[dotRange.upperBound...])
                    }
                }
                // Strip surrounding quotes
                remaining = remaining.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !remaining.isEmpty {
                    quotedTexts.append(remaining)
                }
                continue
            }

            // Arrow continuation (part of multi-line example)
            if clean == "→" || clean == "..." {
                continue  // Skip arrow markers between quote blocks
            }

            // Other content (non-quoted, non-metadata) — might be continuation text
            if !clean.isEmpty, let first = clean.first, !first.isNumber {
                // Could be continuation of example text without quotes
                // Only add if we haven't collected any quotes yet (pure text examples)
                if quotedTexts.isEmpty {
                    // Strip leading "N. " if present
                    var text = clean
                    if let dotRange = text.range(of: ". ") {
                        let prefix = text[text.startIndex..<dotRange.lowerBound]
                        if prefix.allSatisfy(\.isNumber) {
                            text = String(text[dotRange.upperBound...])
                        }
                    }
                    if text.count > 5 { quotedTexts.append(text) }
                }
            }
        }

        let slideText = quotedTexts.joined(separator: "\n")
        guard slideText.count > 3 else { return nil }

        return CodexExample(
            slideText: slideText,
            postReference: postRef,
            slideNumber: nil,
            mechanism: mechanism.isEmpty ? nil : mechanism
        )
    }

    /// Extract lines from a standalone section (between header and next section header)
    private func extractStandaloneSection(from body: String, headers: [String], lineFilter: (String) -> Bool) -> [String] {
        let bodyLines = body.components(separatedBy: "\n")
        var capturing = false
        var results: [String] = []
        // ALL possible section headers that should stop capturing
        let sectionEnders = [
            "###", "═══", "EXAMPLES", "REAL EXAMPLES", "FREQUENCY:", "DEFINITION:",
            "HOW TO APPLY", "ANTI-PATTERNS", "PATTERNS:", "STRONG FORMS",
            "WHY IT WORKS", "WHERE ACTIVE", "READER EFFECT",
            "REEL EXAMPLES", "CAROUSEL EXAMPLES",
            "OPERATIONAL RECIPE", "GENERATION RECIPE", "FORMAT-SPECIFIC CONSTRAINTS",
            "FORMAT CONSTRAINTS", "ANTI-EXAMPLE WITH FIX", "ANTI-EXAMPLE:"
        ]

        for line in bodyLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let upper = trimmed.uppercased()

            // Check if this line starts one of our target sections
            if headers.contains(where: { upper.hasPrefix($0.uppercased()) }) {
                if capturing {
                    // We already found and captured one instance — don't restart
                    break
                }
                capturing = true
                continue
            }

            // Check if we've hit a DIFFERENT section header (stop capturing)
            if capturing {
                let isNewSection = sectionEnders.contains(where: { ender in
                    upper.hasPrefix(ender) && !headers.contains(where: { upper.hasPrefix($0.uppercased()) })
                })
                if isNewSection { break }
            }

            if capturing && lineFilter(trimmed) {
                results.append(trimmed)
            }
        }

        return results
    }

    /// Find a standalone field value (single line after header)
    private func findStandaloneField(in body: String, headers: [String]) -> String? {
        let bodyLines = body.components(separatedBy: "\n")
        for (i, line) in bodyLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for header in headers {
                if trimmed.uppercased().hasPrefix(header.uppercased()) {
                    // Value might be on same line or next line
                    let afterHeader = trimmed.dropFirst(header.count).trimmingCharacters(in: .whitespaces)
                    if !afterHeader.isEmpty { return String(afterHeader) }
                    if i + 1 < bodyLines.count {
                        let nextLine = bodyLines[i + 1].trimmingCharacters(in: .whitespaces)
                        if !nextLine.isEmpty { return nextLine }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Key Matching

    /// Multi-strategy key matching for deep entry concept names to periodic table entries
    private func findMatchingKey(_ conceptName: String, in keys: Set<String>) -> String? {
        let name = conceptName.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. Exact match
        if keys.contains(name) { return name }

        // 2. First token match (before " / ")
        let firstToken = name.components(separatedBy: " / ").first?
            .trimmingCharacters(in: .whitespaces) ?? name

        for key in keys {
            let keyFirstToken = key.components(separatedBy: " / ").first?
                .trimmingCharacters(in: .whitespaces) ?? key
            if keyFirstToken == firstToken { return key }
        }

        // 3. Prefix match
        for key in keys {
            if key.hasPrefix(firstToken) || firstToken.hasPrefix(key) { return key }
        }

        return nil
    }

    // MARK: - Category Mapping

    private func mapCategory(_ categoryString: String) -> CodexElementCategory {
        let lowered = categoryString.lowercased().trimmingCharacters(in: .whitespaces)

        switch lowered {
        case "speech act", "speechact":
            return .speechAct
        case "transition":
            return .transition
        case "reader delta", "readerdelta":
            return .readerDelta
        case "proof type", "prooftype", "proof":
            return .proofType
        case "motivation":
            return .motivation
        case "compression":
            return .compression
        case "frame":
            return .frame
        case "distance":
            return .distance
        case "technique":
            return .technique
        case "dominant frame", "dominantframe":
            return .dominantFrame
        case "arc shape", "arcshape", "arc":
            return .arcShape
        case "physics event", "physicsevent", "physics":
            return .physicsEvent
        case "long-range interaction", "longrangeinteraction", "long range interaction":
            return .longRangeInteraction
        case "rsv dimension", "rsvdimension", "rsv":
            return .rsvDimension
        case "compound pattern", "compoundpattern", "compound":
            return .compoundPattern
        case "antimatter", "anti-matter":
            return .antimatter
        case "force":
            return .force
        case "law":
            return .law
        default:
            return .technique
        }
    }

    // MARK: - Laws Parsing

    /// Parse Laws from the codex body. Laws appear as "═══ LAW N: NAME ═══" sections.
    private func parseLaws(codexBody: String, existingNames: Set<String>, errors: inout [String]) async -> Int {
        var created = 0

        let sections = codexBody.components(separatedBy: "═══")
        var i = 1
        while i < sections.count {
            let header = sections[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = i + 1 < sections.count ? sections[i + 1] : ""

            // Check if this is a LAW header
            guard header.uppercased().hasPrefix("LAW") else {
                i += 1
                continue
            }

            // Extract law name (after the colon)
            let lawName: String
            if let colonIdx = header.firstIndex(of: ":") {
                lawName = String(header[header.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                i += 1
                continue  // Skip malformed law headers
            }

            // Extract law number
            let lawNumber = header.firstMatch(of: /LAW\s+(\d+)/).map { String($0.output.1) } ?? "0"
            let canonicalName = "LAW_\(lawNumber)"
            let key = canonicalName.lowercased()

            guard !canonicalName.isEmpty else { i += 2; continue }

            // Extract FULL law body text — no truncation
            let bodyText = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = bodyText

            let element = CodexElement(
                canonicalName: canonicalName,
                category: .law,
                definition: definition.isEmpty ? lawName : definition,
                frequency: nil,
                examples: [],
                applicationRules: [],
                antiPatterns: [],
                readerEffect: nil,
                whereActive: [],
                whyItWorks: nil,
                patterns: [],
                variants: []
            )

            if existingNames.contains(key) {
                // Update existing law with body text if it was empty
                if let (dbAtom, dbElement) = try? await CodexRepository.shared.fetchElement(canonicalName: canonicalName),
                   dbElement.definition.isEmpty || dbElement.definition.count < 20 {
                    let updated = CodexElement(
                        canonicalName: dbElement.canonicalName, category: .law,
                        definition: definition.isEmpty ? lawName : definition,
                        frequency: dbElement.frequency, examples: dbElement.examples,
                        applicationRules: dbElement.applicationRules, antiPatterns: dbElement.antiPatterns,
                        readerEffect: dbElement.readerEffect, whereActive: dbElement.whereActive,
                        whyItWorks: dbElement.whyItWorks, patterns: dbElement.patterns, variants: dbElement.variants
                    )
                    if let data = try? JSONEncoder().encode(updated),
                       let jsonStr = String(data: data, encoding: .utf8) {
                        var updatedAtom = dbAtom
                        updatedAtom.structured = jsonStr
                        updatedAtom.body = definition
                        _ = try? await AtomRepository.shared.update(updatedAtom)
                        logger.info("Enriched existing law: \(canonicalName)")
                    }
                }
            } else {
                do {
                    let data = try JSONEncoder().encode(element)
                    guard let jsonStr = String(data: data, encoding: .utf8) else { i += 2; continue }
                    try await AtomRepository.shared.create(
                        type: .codexElement,
                        title: "\(canonicalName): \(lawName)",
                        body: definition,
                        structured: jsonStr
                    )
                    created += 1
                    logger.info("Created law: \(canonicalName): \(lawName)")
                } catch {
                    errors.append("Law \(canonicalName): \(error.localizedDescription)")
                }
            }

            i += 2  // Skip header + body
        }

        logger.info("Laws parsed: \(created) created")
        return created
    }

    // MARK: - Variant Mapping

    /// Parse variant mappings from codex and update existing element atoms.
    /// Pattern: **PARENT_NAME** → includes: variant1, variant2, variant3
    private func parseVariantMappings(codexBody: String) async {
        var mappingsFound = 0

        // Look for variant mapping patterns
        let lines = codexBody.components(separatedBy: "\n")
        for line in lines {
            // Pattern: **PARENT** → includes: v1, v2, v3
            // Or: **PARENT** → v1, v2, v3
            guard line.contains("→") || line.contains("->") else { continue }
            guard line.contains("**") else { continue }

            let separator = line.contains("→") ? "→" : "->"
            let parts = line.components(separatedBy: separator)
            guard parts.count == 2 else { continue }

            // Extract parent name from **NAME**
            let parentPart = parts[0]
            guard let starStart = parentPart.range(of: "**"),
                  let starEnd = parentPart.range(of: "**", range: starStart.upperBound..<parentPart.endIndex) else { continue }
            let parentName = String(parentPart[starStart.upperBound..<starEnd.lowerBound]).trimmingCharacters(in: .whitespaces)

            // Extract variant names
            var variantStr = parts[1].trimmingCharacters(in: .whitespaces)
            if variantStr.lowercased().hasPrefix("includes:") {
                variantStr = String(variantStr.dropFirst("includes:".count)).trimmingCharacters(in: .whitespaces)
            }
            let variants = variantStr.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "**", with: "")
            }.filter { !$0.isEmpty }

            guard !variants.isEmpty else { continue }

            // Find the parent element atom and update its variants
            if let (atom, element) = try? await CodexRepository.shared.fetchElement(canonicalName: parentName) {
                var updated = element
                let existingVariants = Set(updated.variants)
                let newVariants = variants.filter { !existingVariants.contains($0) }
                guard !newVariants.isEmpty else { continue }

                // Rebuild with merged variants
                let mergedElement = CodexElement(
                    canonicalName: element.canonicalName,
                    category: element.category,
                    definition: element.definition,
                    frequency: element.frequency,
                    examples: element.examples,
                    applicationRules: element.applicationRules,
                    antiPatterns: element.antiPatterns,
                    readerEffect: element.readerEffect,
                    whereActive: element.whereActive,
                    whyItWorks: element.whyItWorks,
                    patterns: element.patterns,
                    variants: element.variants + newVariants
                )

                if let data = try? JSONEncoder().encode(mergedElement),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    var updatedAtom = atom
                    updatedAtom.structured = jsonStr
                    _ = try? await AtomRepository.shared.update(updatedAtom)
                    mappingsFound += 1
                }
            }
        }

        logger.info("Variant mappings: \(mappingsFound) elements updated")
    }

    // MARK: - Codex Text Walkthrough Parsing

    /// Parse the 10 canonical walkthroughs from the Exemplar Codex body text.
    /// Format: ═══ WALKTHROUGH N: TITLE ═══ followed by full slide-by-slide analysis
    private func parseCodexWalkthroughs(codexBody: String, errors: inout [String]) async -> Int {
        let sections = codexBody.components(separatedBy: "═══")
        var created = 0

        // Check existing walkthrough titles to avoid duplicates
        let existingWalkthroughs = try? await AtomRepository.shared.fetchAll(type: .codexWalkthrough)
        let existingTitles = Set((existingWalkthroughs ?? []).compactMap { $0.title?.lowercased() })

        var i = 1
        while i < sections.count {
            let header = sections[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // Match "WALKTHROUGH N: TITLE" pattern
            guard header.uppercased().hasPrefix("WALKTHROUGH") else {
                i += 1
                continue
            }

            // Get the full body (everything until next ═══ section or end)
            let body = i + 1 < sections.count ? sections[i + 1] : ""

            // Extract title from header: "WALKTHROUGH N: TITLE"
            let title: String
            if let colonIdx = header.firstIndex(of: ":") {
                title = String(header[header.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                title = header.replacingOccurrences(of: "WALKTHROUGH", with: "")
                    .trimmingCharacters(in: .whitespaces.union(.decimalDigits))
            }

            // Extract walkthrough number
            let wtNumber = header.firstMatch(of: /WALKTHROUGH\s+(\d+)/).map { String($0.output.1) } ?? "0"

            let fullTitle = "Codex Walkthrough \(wtNumber): \(title)"

            // Skip if already exists
            if existingTitles.contains(fullTitle.lowercased()) {
                i += 2
                continue
            }

            // Parse structured fields from body
            let walkthrough = parseWalkthroughText(title: title, wtNumber: wtNumber, body: body)

            // Store FULL text as body + structured JSON
            let fullText = "═══ \(header) ═══\n\n\(body)"

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let jsonData = try encoder.encode(walkthrough)
                guard let jsonStr = String(data: jsonData, encoding: .utf8) else {
                    i += 2
                    continue
                }

                try await AtomRepository.shared.create(
                    type: .codexWalkthrough,
                    title: fullTitle,
                    body: fullText,  // FULL walkthrough text preserved
                    structured: jsonStr
                )
                created += 1
                logger.info("Created codex walkthrough: \(fullTitle)")
            } catch {
                errors.append("Walkthrough \(wtNumber): \(error.localizedDescription)")
            }

            i += 2
        }

        logger.info("Codex walkthroughs parsed: \(created) from text")
        return created
    }

    /// Parse a walkthrough body text into a CodexWalkthrough struct
    private func parseWalkthroughText(title: String, wtNumber: String, body: String) -> CodexWalkthrough {
        let lines = body.components(separatedBy: "\n")

        // Extract header fields
        var dominantFrame: String?
        var arcShape: String?
        var whySelected: String?
        var compositionLesson: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("dominant frame:") {
                dominantFrame = String(trimmed.dropFirst("Dominant frame:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("arc shape:") {
                arcShape = String(trimmed.dropFirst("Arc shape:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("why selected:") {
                whySelected = String(trimmed.dropFirst("Why selected:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Extract composition lesson
        if let lessonIdx = body.range(of: "COMPOSITION LESSON:", options: .caseInsensitive) {
            compositionLesson = String(body[lessonIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Parse slides
        var slides: [WalkthroughSlide] = []
        let slidePattern = /Slide\s+(\d+)\s*:\s*"(.+?)"/
        for match in body.matches(of: slidePattern) {
            let slideNum = Int(match.output.1) ?? 0
            let slideText = String(match.output.2)

            // Find the block after this slide header to get speech act, deltas, etc.
            let slideHeader = "Slide \(slideNum):"
            guard let headerRange = body.range(of: slideHeader) else { continue }
            let afterHeader = String(body[headerRange.upperBound...])

            // Find the end of this slide's metadata (next "Slide N:" or "TRANSITION:" or section header)
            let endPatterns = ["Slide \(slideNum) →", "Slide \(slideNum + 1):", "RSV TRAJECTORY", "PHYSICS EVENTS", "COMPOSITION LESSON"]
            var slideBlock = afterHeader
            for pattern in endPatterns {
                if let endRange = afterHeader.range(of: pattern) {
                    let candidate = String(afterHeader[..<endRange.lowerBound])
                    if candidate.count < slideBlock.count { slideBlock = candidate }
                }
            }

            // Extract fields from slide block
            var speechAct: String?
            var readerDeltas: [String] = []
            var frame: String?
            var distance: String?
            var techniques: [WalkthroughTechnique] = []
            var whyWorks: String?

            for blockLine in slideBlock.components(separatedBy: "\n") {
                let t = blockLine.trimmingCharacters(in: .whitespaces)
                if t.lowercased().hasPrefix("speech act:") {
                    speechAct = String(t.dropFirst("Speech act:".count)).trimmingCharacters(in: .whitespaces)
                } else if t.lowercased().hasPrefix("reader deltas:") {
                    readerDeltas = String(t.dropFirst("Reader deltas:".count))
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                } else if t.lowercased().hasPrefix("frame:") {
                    frame = String(t.dropFirst("Frame:".count)).trimmingCharacters(in: .whitespaces)
                } else if t.lowercased().hasPrefix("distance:") {
                    distance = String(t.dropFirst("Distance:".count)).trimmingCharacters(in: .whitespaces)
                } else if t.lowercased().hasPrefix("techniques active:") || t.lowercased().hasPrefix("techniques:") {
                    let techStr = t.contains("active:") ? String(t.dropFirst("Techniques active:".count)) : String(t.dropFirst("Techniques:".count))
                    techniques = techStr.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map { WalkthroughTechnique(canonicalName: $0, why: nil) }
                } else if t.lowercased().hasPrefix("why this slide works:") {
                    whyWorks = String(t.dropFirst("Why this slide works:".count)).trimmingCharacters(in: .whitespaces)
                }
            }

            slides.append(WalkthroughSlide(
                slideNumber: slideNum,
                text: slideText,
                speechAct: speechAct,
                readerDeltas: readerDeltas,
                frame: frame,
                distance: distance,
                techniques: techniques,
                proofTypes: [],
                motivations: [],
                compressions: [],
                whyThisSlideWorks: whyWorks
            ))
        }

        // Parse transitions
        var transitions: [WalkthroughTransition] = []
        let transPattern = /Slide\s+(\d+)\s*→\s*Slide\s+(\d+)\s+TRANSITION:\s*(.+)/
        for match in body.matches(of: transPattern) {
            let from = Int(match.output.1) ?? 0
            let to = Int(match.output.2) ?? 0
            let transType = String(match.output.3).trimmingCharacters(in: .whitespaces)

            // Get "Why this order:" from next lines
            var explanation: String?
            let marker = "Slide \(from) → Slide \(to) TRANSITION:"
            if let markerRange = body.range(of: marker) {
                let after = String(body[markerRange.upperBound...])
                for line in after.components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.lowercased().hasPrefix("why this order:") {
                        explanation = String(t.dropFirst("Why this order:".count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }

            transitions.append(WalkthroughTransition(
                fromSlide: from, toSlide: to,
                transitionType: transType,
                explanation: explanation
            ))
        }

        return CodexWalkthrough(
            postReference: "codex_walkthrough_\(wtNumber)",
            postTitle: title,
            creatorName: nil,
            dominantFrame: dominantFrame,
            arcShape: arcShape,
            whySelected: whySelected,
            slides: slides,
            transitions: transitions,
            rsvTrajectory: nil,
            physicsEvents: nil,
            compositionLesson: compositionLesson,
            readerJourney: nil,
            longRangeBonds: nil,
            echoPatterns: nil,
            deliberateAbsences: nil,
            callbackChains: nil,
            antimatter: nil,
            theFabric: nil,
            sourceSwipeUUID: nil
        )
    }

    // MARK: - Walkthrough Import (from swipe profiles)

    /// Scan all research atoms for physics profiles and create .codexWalkthrough atoms
    private func importWalkthroughs() async throws -> Int {
        let allResearch = try await AtomRepository.shared.fetchAll(type: .research)
        let existingWalkthroughs = try await AtomRepository.shared.fetchAll(type: .codexWalkthrough)
        let existingSourceUUIDs = Set(existingWalkthroughs.compactMap { atom -> String? in
            guard let structured = atom.structured,
                  let data = structured.data(using: .utf8),
                  let wt = try? JSONDecoder().decode(CodexWalkthrough.self, from: data) else { return nil }
            return wt.sourceSwipeUUID
        })

        var created = 0

        for swipe in allResearch {
            // Skip if already atomized
            if existingSourceUUIDs.contains(swipe.uuid) { continue }

            // Only process swipes with a CODEX profile (v2) — skip legacy 10-pass profiles
            guard let profile = swipe.codexProfile,
                  let slideQuarks = profile.slideQuarks, !slideQuarks.isEmpty else { continue }

            let walkthrough = convertProfileToWalkthrough(swipe: swipe, profile: profile)

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let jsonData = try encoder.encode(walkthrough)
                guard let jsonStr = String(data: jsonData, encoding: .utf8) else { continue }

                try await AtomRepository.shared.create(
                    type: .codexWalkthrough,
                    title: walkthrough.postTitle,
                    body: walkthrough.compositionLesson,
                    structured: jsonStr
                )

                // Create bidirectional links between walkthrough and referenced elements
                // (deferred — elements may not all exist yet)

                created += 1
                logger.info("Created walkthrough atom for: \(walkthrough.postTitle)")
            } catch {
                logger.error("Failed to create walkthrough for \(swipe.title ?? "?"): \(error.localizedDescription)")
            }
        }

        logger.info("Walkthrough import: \(created) created from \(allResearch.count) swipes")
        return created
    }

    /// Convert a ContentPhysicsProfile into a CodexWalkthrough
    private func convertProfileToWalkthrough(swipe: Atom, profile: ContentPhysicsProfile) -> CodexWalkthrough {
        let title = swipe.title ?? "Untitled"

        let slides: [WalkthroughSlide] = (profile.slideQuarks ?? []).map { sq in
            WalkthroughSlide(
                slideNumber: sq.slideNumber,
                text: sq.text,
                speechAct: sq.speechAct.type,
                readerDeltas: (sq.readerDeltas ?? []).compactMap(\.type),
                frame: sq.frame?.type,
                distance: sq.experientialDistance?.type,
                techniques: (sq.techniques ?? []).map {
                    WalkthroughTechnique(canonicalName: $0.technique, why: $0.usage)
                },
                proofTypes: [sq.proofType?.type].compactMap { $0 },
                motivations: [sq.motivation?.type].compactMap { $0 },
                compressions: [sq.compression].compactMap { $0?.type },
                whyThisSlideWorks: nil
            )
        }

        let transitions: [WalkthroughTransition] = (profile.transitions ?? []).map { t in
            WalkthroughTransition(
                fromSlide: t.from,
                toSlide: t.to,
                transitionType: t.type,
                explanation: t.mechanism
            )
        }

        let rsvTrajectory: [WalkthroughRSVPoint]? = profile.rsv?.trajectoryPoints?.map { pt in
            WalkthroughRSVPoint(
                afterSlide: pt.afterSlide,
                openLoopCount: pt.openLoops?.count,
                trustLevel: pt.trust,
                tensionLevel: pt.tension?.level,
                frame: pt.frame,
                energyBalance: pt.energyBalance
            )
        }

        let physicsEvents: WalkthroughPhysicsEvents? = {
            guard let pe = profile.physicsEvents else { return nil }
            return WalkthroughPhysicsEvents(
                symmetryBreak: pe.symmetryBreak.map {
                    PhysicsEventDetail(slideNumber: $0.slideNumber, description: $0.whatBreaks)
                },
                phaseTransition: pe.phaseTransition.map {
                    PhysicsEventDetail(slideNumber: $0.slideNumber, description: $0.recontextualization)
                },
                energyResolution: pe.energyResolution.map {
                    PhysicsEventDetail(slideNumber: nil, description: $0.assessment)
                },
                peakGravity: pe.peakGravity.map {
                    PhysicsEventDetail(slideNumber: $0.slideNumber, description: nil)
                }
            )
        }()

        let readerJourney: [WalkthroughReaderState]? = profile.readerSimulation?.map { rs in
            WalkthroughReaderState(
                afterSlide: rs.afterSlide,
                dominantEmotion: rs.dominantEmotion,
                investmentLevel: rs.investmentLevel,
                activeQuestions: rs.activeQuestions,
                prediction: rs.prediction
            )
        }

        let bonds: [WalkthroughBond]? = profile.longRangeInteractions?.setupPayoffBonds?.map {
            WalkthroughBond(
                setupSlide: $0.setupSlide,
                payoffSlide: $0.payoffSlide,
                planted: $0.planted,
                harvested: $0.harvested
            )
        }

        let echoes: [WalkthroughEcho]? = profile.longRangeInteractions?.echoPatterns?.map {
            WalkthroughEcho(
                element: $0.quarkType,
                positions: $0.positions,
                transformation: $0.transformation
            )
        }

        let absences: [WalkthroughAbsence]? = profile.longRangeInteractions?.deliberateAbsences?.map {
            WalkthroughAbsence(what: $0.what, effect: $0.effect)
        }

        let callbacks: [WalkthroughCallback]? = profile.longRangeInteractions?.callbackChains?.map { chain in
            WalkthroughCallback(
                element: chain.element,
                appearances: chain.appearances?.map {
                    WalkthroughCallbackAppearance(slide: $0.slide, meaning: $0.meaning)
                } ?? [],
                transformationArc: chain.transformationArc
            )
        }

        return CodexWalkthrough(
            postReference: swipe.uuid,
            postTitle: title,
            creatorName: nil,
            dominantFrame: profile.arcQuarks?.dominantFrame?.type,
            arcShape: profile.arcQuarks?.shape,
            whySelected: nil,
            slides: slides,
            transitions: transitions,
            rsvTrajectory: rsvTrajectory,
            physicsEvents: physicsEvents,
            compositionLesson: profile.deepFabric,
            readerJourney: readerJourney,
            longRangeBonds: bonds,
            echoPatterns: echoes,
            deliberateAbsences: absences,
            callbackChains: callbacks,
            antimatter: profile.antimatter,
            theFabric: profile.deepFabric,
            sourceSwipeUUID: swipe.uuid
        )
    }
}
