// CosmoOS/AI/IdeaInsight.swift
// Data models for the IdeaForge intelligence system
// Stores analysis results in idea atom's structured JSON

import Foundation
import SwiftUI

// MARK: - IdeaInsight (Primary Model)

/// Complete intelligence analysis of an idea, stored in idea atom's structured JSON
public struct IdeaInsight: Codable, Sendable, Equatable {
    /// Matching swipe files found via semantic + structural similarity
    public var matchingSwipes: [SwipeMatch]?

    /// Recommended content frameworks based on swipe analysis
    public var frameworkRecommendations: [FrameworkRecommendation]?

    /// AI-generated hook suggestions inspired by matching swipes
    public var hookSuggestions: [HookSuggestion]?

    /// Format suitability scores (IdeaContentFormat rawValue -> 0-1 score)
    public var formatScores: [String: Double]?

    /// Data source descriptions for format scores (IdeaContentFormat rawValue -> description)
    public var formatDataSources: [String: String]?

    /// Top recommended format
    public var recommendedFormat: String?

    /// Why this format was recommended
    public var formatRationale: String?

    /// Generated content blueprint (after framework selection)
    public var blueprint: ContentBlueprint?

    /// Suggested emotional arc for the content
    public var suggestedEmotionalArc: [EmotionDataPoint]?

    /// Suggested persuasion techniques
    public var suggestedPersuasionTechniques: [String]?

    /// Analysis schema version
    public var insightVersion: Int

    /// When the insight was generated
    public var generatedAt: String?

    /// Whether all analysis stages completed
    public var isFullyAnalyzed: Bool

    public init(
        matchingSwipes: [SwipeMatch]? = nil,
        frameworkRecommendations: [FrameworkRecommendation]? = nil,
        hookSuggestions: [HookSuggestion]? = nil,
        formatScores: [String: Double]? = nil,
        formatDataSources: [String: String]? = nil,
        recommendedFormat: String? = nil,
        formatRationale: String? = nil,
        blueprint: ContentBlueprint? = nil,
        suggestedEmotionalArc: [EmotionDataPoint]? = nil,
        suggestedPersuasionTechniques: [String]? = nil,
        insightVersion: Int = 1,
        generatedAt: String? = nil,
        isFullyAnalyzed: Bool = false
    ) {
        self.matchingSwipes = matchingSwipes
        self.frameworkRecommendations = frameworkRecommendations
        self.hookSuggestions = hookSuggestions
        self.formatScores = formatScores
        self.formatDataSources = formatDataSources
        self.recommendedFormat = recommendedFormat
        self.formatRationale = formatRationale
        self.blueprint = blueprint
        self.suggestedEmotionalArc = suggestedEmotionalArc
        self.suggestedPersuasionTechniques = suggestedPersuasionTechniques
        self.insightVersion = insightVersion
        self.generatedAt = generatedAt
        self.isFullyAnalyzed = isFullyAnalyzed
    }
}

// MARK: - SwipeMatch

/// A swipe file that matches an idea via semantic/structural similarity
public struct SwipeMatch: Codable, Sendable, Equatable, Identifiable {
    public var id: String { swipeAtomUUID }

    public let swipeAtomUUID: String
    public let title: String
    public let similarityScore: Double      // 0-1 combined score
    public let matchReason: String?
    public let hookType: SwipeHookType?
    public let frameworkType: SwipeFrameworkType?
    public let hookText: String?
    public let platform: String?

    public init(
        swipeAtomUUID: String,
        title: String,
        similarityScore: Double,
        matchReason: String? = nil,
        hookType: SwipeHookType? = nil,
        frameworkType: SwipeFrameworkType? = nil,
        hookText: String? = nil,
        platform: String? = nil
    ) {
        self.swipeAtomUUID = swipeAtomUUID
        self.title = title
        self.similarityScore = similarityScore
        self.matchReason = matchReason
        self.hookType = hookType
        self.frameworkType = frameworkType
        self.hookText = hookText
        self.platform = platform
    }
}

// MARK: - FrameworkRecommendation

/// A recommended content framework with confidence and rationale
public struct FrameworkRecommendation: Codable, Sendable, Equatable, Identifiable {
    public var id: String { framework.rawValue }

    public let framework: SwipeFrameworkType
    public let confidence: Double           // 0-1
    public let rationale: String
    public let exampleSwipeUUIDs: [String]?
    /// Evidence-based reasoning explaining why this framework was recommended
    public let reasoning: String?

    public init(
        framework: SwipeFrameworkType,
        confidence: Double,
        rationale: String,
        exampleSwipeUUIDs: [String]? = nil,
        reasoning: String? = nil
    ) {
        self.framework = framework
        self.confidence = confidence
        self.rationale = rationale
        self.exampleSwipeUUIDs = exampleSwipeUUIDs
        self.reasoning = reasoning
    }
}

// MARK: - HookSuggestion

/// An AI-generated hook suggestion for an idea
public struct HookSuggestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let hookText: String
    public let hookType: SwipeHookType?
    public let inspiredBySwipeUUID: String?
    public var isSelected: Bool

    public init(
        id: String = UUID().uuidString,
        hookText: String,
        hookType: SwipeHookType? = nil,
        inspiredBySwipeUUID: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.hookText = hookText
        self.hookType = hookType
        self.inspiredBySwipeUUID = inspiredBySwipeUUID
        self.isSelected = isSelected
    }
}

// MARK: - ContentBlueprint

/// A production-ready content blueprint generated from idea + framework + swipes
public struct ContentBlueprint: Codable, Sendable, Equatable {
    public let format: String               // IdeaContentFormat rawValue
    public let framework: String            // SwipeFrameworkType rawValue
    public var sections: [BlueprintSection]
    public let estimatedWordCount: Int?
    public let suggestedHook: String?
    public let suggestedCTA: String?

    public init(
        format: String,
        framework: String,
        sections: [BlueprintSection] = [],
        estimatedWordCount: Int? = nil,
        suggestedHook: String? = nil,
        suggestedCTA: String? = nil
    ) {
        self.format = format
        self.framework = framework
        self.sections = sections
        self.estimatedWordCount = estimatedWordCount
        self.suggestedHook = suggestedHook
        self.suggestedCTA = suggestedCTA
    }
}

// MARK: - BlueprintSection

/// A single section of a content blueprint
public struct BlueprintSection: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let purpose: String
    public var suggestedContent: String?
    public let referenceSwipeUUID: String?
    public let targetWordCount: Int?
    public let emotion: String?             // SwipeEmotion rawValue
    public let sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        label: String,
        purpose: String,
        suggestedContent: String? = nil,
        referenceSwipeUUID: String? = nil,
        targetWordCount: Int? = nil,
        emotion: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.label = label
        self.purpose = purpose
        self.suggestedContent = suggestedContent
        self.referenceSwipeUUID = referenceSwipeUUID
        self.targetWordCount = targetWordCount
        self.emotion = emotion
        self.sortOrder = sortOrder
    }
}

// MARK: - QuickInsightResult

/// Lightweight on-device analysis result (no API call)
public struct QuickInsightResult: Sendable {
    public let suggestedHookType: SwipeHookType?
    public let suggestedFramework: SwipeFrameworkType?
    public let topicKeywords: [String]
    public let sentimentScore: Double?

    public init(
        suggestedHookType: SwipeHookType? = nil,
        suggestedFramework: SwipeFrameworkType? = nil,
        topicKeywords: [String] = [],
        sentimentScore: Double? = nil
    ) {
        self.suggestedHookType = suggestedHookType
        self.suggestedFramework = suggestedFramework
        self.topicKeywords = topicKeywords
        self.sentimentScore = sentimentScore
    }
}
