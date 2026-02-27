// CosmoOS/AI/SynthesisResult.swift
// Data model for lasso AI synthesis output

import Foundation

struct LassoSynthesisResult: Codable, Identifiable {
    let id: String
    var themes: [String]
    var synthesizedArgument: String
    var openQuestions: [String]
    var suggestedTitle: String
    var evidenceSpans: [LassoEvidenceSpan]
    var sourceAtomUUIDs: [String]

    init(
        id: String = UUID().uuidString,
        themes: [String] = [],
        synthesizedArgument: String = "",
        openQuestions: [String] = [],
        suggestedTitle: String = "",
        evidenceSpans: [LassoEvidenceSpan] = [],
        sourceAtomUUIDs: [String] = []
    ) {
        self.id = id
        self.themes = themes
        self.synthesizedArgument = synthesizedArgument
        self.openQuestions = openQuestions
        self.suggestedTitle = suggestedTitle
        self.evidenceSpans = evidenceSpans
        self.sourceAtomUUIDs = sourceAtomUUIDs
    }
}

struct LassoEvidenceSpan: Codable, Identifiable {
    let id: String
    let sourceAtomUUID: String
    let excerpt: String
    let claim: String

    init(
        id: String = UUID().uuidString,
        sourceAtomUUID: String,
        excerpt: String,
        claim: String
    ) {
        self.id = id
        self.sourceAtomUUID = sourceAtomUUID
        self.excerpt = excerpt
        self.claim = claim
    }
}
