// CosmoOS/Data/Models/Codex/CodexElement.swift
// Individual element from the Content Physics periodic table.
// Stored in the `structured` JSON field of a `.codexElement` Atom.

import Foundation

struct CodexElement: Codable, Sendable, Equatable, Identifiable {
    var id: String { canonicalName }

    let canonicalName: String
    let category: CodexElementCategory
    let definition: String
    let frequency: String?
    let examples: [CodexExample]
    let applicationRules: [String]
    let antiPatterns: [String]
    let readerEffect: String?
    let whereActive: [String]
    let whyItWorks: String?
    let patterns: [String]
    let variants: [String]

    // Pass 2 training-data fields
    var operationalRecipe: String? = nil
    var generationRecipe: CodexGenerationRecipe? = nil
    var formatConstraints: CodexFormatConstraints? = nil
    var reelExamples: [CodexExample]? = nil
    var carouselExamples: [CodexExample]? = nil
    var antiExampleFix: CodexAntiExampleFix? = nil
}

struct CodexGenerationRecipe: Codable, Sendable, Equatable {
    let steps: [String]
    let commonMistakes: [String]
}

struct CodexFormatConstraints: Codable, Sendable, Equatable {
    let reel: String
    let carousel: String
}

struct CodexAntiExampleFix: Codable, Sendable, Equatable {
    let bad: String
    let whyItFails: String
    let fixed: String
    let whyTheFixWorks: String
}

struct CodexExample: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(postReference)-\(slideNumber ?? 0)" }

    let slideText: String
    let postReference: String
    let slideNumber: Int?
    let mechanism: String?
    var replicationTemplate: String? = nil
}
