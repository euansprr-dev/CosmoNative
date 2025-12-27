// CosmoOS/Voice/Pipeline/LevelSystemVoicePatterns.swift
// Tier 0 voice patterns for Level System queries

import Foundation

// MARK: - Level System Voice Patterns

/// Extension to PatternMatcher for Level System query patterns.
/// These patterns enable fast (<50ms) voice queries for:
/// - Level status ("What's my level?")
/// - Streak queries ("What's my streak?")
/// - Badge queries ("What badges do I have?")
/// - XP queries ("How much XP today?")
/// - Health queries ("What's my readiness?")
extension PatternMatcher {

    /// Level System query patterns to be registered.
    /// Returns patterns that match common level system voice queries.
    nonisolated static var levelSystemPatterns: [CommandPattern] {
        [
            // ===== LEVEL STATUS QUERIES =====
            CommandPattern(
                regex: #"^(what('?s| is)|tell me|show me)\s+(my\s+)?(level|cosmo\s*index|ci)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "level_status",
                        confidence: 0.95,
                        queryType: .levelStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what\s+level\s+am\s+i|my\s+level)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "level_status_alt",
                        confidence: 0.95,
                        queryType: .levelStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^how\s+(am\s+i\s+doing|is\s+my\s+progress)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "level_progress",
                        confidence: 0.85,
                        queryType: .levelStatus
                    )
                }
            ),

            // ===== DIMENSION-SPECIFIC QUERIES =====
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?(cognitive|creative|physiological|behavioral|knowledge|reflection)\s*(dimension|level|status)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let dimension = extractDimension(from: match)
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "dimension_status",
                        confidence: 0.95,
                        queryType: .dimensionStatus,
                        dimension: dimension
                    )
                }
            ),

            // ===== XP QUERIES =====
            CommandPattern(
                regex: #"^(how\s+much|what('?s| is))\s+(my\s+)?(xp|experience\s*points?)\s*(today|this\s+week)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[5].lowercased()
                    let queryType: ParsedAction.QueryType = period.contains("week") ? .xpBreakdown : .xpToday
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "xp_query",
                        confidence: 0.95,
                        queryType: queryType
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|give)\s+(me\s+)?(my\s+)?xp\s*(breakdown|summary)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "xp_breakdown",
                        confidence: 0.95,
                        queryType: .xpBreakdown
                    )
                }
            ),
            CommandPattern(
                regex: #"^how\s+much\s+did\s+i\s+(earn|get|gain)\s*(today)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "xp_earned_today",
                        confidence: 0.9,
                        queryType: .xpToday
                    )
                }
            ),

            // ===== STREAK QUERIES =====
            CommandPattern(
                regex: #"^(what('?s| is)|how\s+long\s+is)\s+(my\s+)?(current\s+)?streak\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "streak_status",
                        confidence: 0.95,
                        queryType: .streakStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what('?s| is)|how\s+long\s+is)\s+(my\s+)?(writing|focus|deep\s*work|workout|journal)\s*streak\s*\??$"#,
                action: .query,
                extractor: { match in
                    let streakType = extractStreakType(from: match)
                    return PatternMatchResult(
                        action: .query,
                        title: streakType,
                        matchedPattern: "streak_specific",
                        confidence: 0.95,
                        queryType: .streakStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|list)\s+(me\s+)?(all\s+)?(my\s+)?streaks\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "all_streaks",
                        confidence: 0.95,
                        queryType: .allStreaks
                    )
                }
            ),
            CommandPattern(
                regex: #"^(am\s+i|is\s+my\s+streak)\s+(on\s+track|safe|at\s+risk)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "streak_risk",
                        confidence: 0.9,
                        queryType: .streakStatus
                    )
                }
            ),

            // ===== BADGE QUERIES =====
            CommandPattern(
                regex: #"^(what|which)\s+badges?\s+(do\s+i\s+have|have\s+i\s+(earned|unlocked))\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "badges_earned",
                        confidence: 0.95,
                        queryType: .badgesEarned
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|list)\s+(me\s+)?(my\s+)?badges?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "badges_list",
                        confidence: 0.95,
                        queryType: .badgesEarned
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what|which)\s+badge\s+(am\s+i\s+close\s+to|is\s+next)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "badge_progress",
                        confidence: 0.95,
                        queryType: .badgeProgress
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how\s+close\s+am\s+i\s+to|progress\s+on)\s+(the\s+)?(\w+)\s*badge\s*\??$"#,
                action: .query,
                extractor: { match in
                    let badgeName = match[3].capitalized
                    return PatternMatchResult(
                        action: .query,
                        title: badgeName,
                        matchedPattern: "badge_specific_progress",
                        confidence: 0.9,
                        queryType: .badgeProgress
                    )
                }
            ),

            // ===== QUEST QUERIES =====
            CommandPattern(
                regex: #"^(what|which)\s+quests?\s+(are\s+active|do\s+i\s+have)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "active_quests",
                        confidence: 0.95,
                        queryType: .activeQuests
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|list)\s+(me\s+)?(my\s+)?(active\s+)?quests?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "quests_list",
                        confidence: 0.95,
                        queryType: .activeQuests
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how('?s| is)|what('?s| is))\s+(my\s+)?quest\s*progress\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "quest_progress",
                        confidence: 0.95,
                        queryType: .questProgress
                    )
                }
            ),

            // ===== HEALTH QUERIES =====
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?readiness\s*(score)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "readiness_score",
                        confidence: 0.95,
                        queryType: .readinessScore
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?(hrv|heart\s*rate\s*variability)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "hrv_status",
                        confidence: 0.95,
                        queryType: .hrvStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how\s+did\s+i|what('?s| is)\s+my)\s+sleep\s*(score|last\s+night)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "sleep_score",
                        confidence: 0.95,
                        queryType: .sleepScore
                    )
                }
            ),
            CommandPattern(
                regex: #"^(am\s+i|how\s+am\s+i)\s+(ready|prepared|rested)\s*(today|for\s+today)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "readiness_natural",
                        confidence: 0.9,
                        queryType: .readinessScore
                    )
                }
            ),
            CommandPattern(
                regex: #"^(give\s+me|show\s+me)\s+(a\s+)?health\s*(summary|overview)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "health_summary",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),

            // ===== WORKOUT QUERIES =====
            CommandPattern(
                regex: #"^(how\s+many|what)\s+workouts?\s+(today|this\s+week|did\s+i\s+do)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "workout_count",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what\s+was|show\s+me)\s+(my\s+)?(last|recent)\s+workout\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "last_workout",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how\s+many|what('?s| is))\s+(my\s+)?(calories|steps|active\s+calories)\s*(today|burned)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let metric = match[4].lowercased()
                    return PatternMatchResult(
                        action: .query,
                        title: metric,
                        matchedPattern: "activity_metric",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),
            CommandPattern(
                regex: #"^(did\s+i|have\s+i)\s+(close|closed)\s+(my\s+)?(rings?|activity\s+rings?)\s*(today)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "rings_status",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?(activity|move|exercise|stand)\s*(ring|progress)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let ring = match[5].lowercased()
                    return PatternMatchResult(
                        action: .query,
                        title: ring,
                        matchedPattern: "ring_progress",
                        confidence: 0.95,
                        queryType: .todayHealth
                    )
                }
            ),

            // ===== SUMMARY QUERIES =====
            CommandPattern(
                regex: #"^(give\s+me|what('?s| is)|show\s+me)\s+(my\s+)?(today('?s)?|daily)\s*summary\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "daily_summary",
                        confidence: 0.95,
                        queryType: .dailySummary
                    )
                }
            ),
            CommandPattern(
                regex: #"^(give\s+me|what('?s| is)|show\s+me)\s+(my\s+)?weekly\s*summary\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "weekly_summary",
                        confidence: 0.95,
                        queryType: .weeklySummary
                    )
                }
            ),
            CommandPattern(
                regex: #"^how\s+(did\s+i\s+do|was\s+my)\s+(this\s+week|today)\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[2].lowercased()
                    let queryType: ParsedAction.QueryType = period.contains("week") ? .weeklySummary : .dailySummary
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "performance_query",
                        confidence: 0.9,
                        queryType: queryType
                    )
                }
            ),
            CommandPattern(
                regex: #"^(give\s+me\s+)?a?\s*recap\s*(of\s+today|of\s+this\s+week)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[2].lowercased()
                    let queryType: ParsedAction.QueryType = period.contains("week") ? .weeklySummary : .dailySummary
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "recap_query",
                        confidence: 0.85,
                        queryType: queryType
                    )
                }
            ),
        ]
    }
}

// MARK: - Helper Functions

/// Extract dimension name from regex match groups
private func extractDimension(from groups: [String]) -> String {
    let dimensions = ["cognitive", "creative", "physiological", "behavioral", "knowledge", "reflection"]
    for group in groups {
        let lowered = group.lowercased()
        for dimension in dimensions {
            if lowered.contains(dimension) {
                return dimension
            }
        }
    }
    return "cognitive" // Default
}

/// Extract streak type from regex match groups
private func extractStreakType(from groups: [String]) -> String {
    let streakTypes = ["writing", "focus", "deep work", "workout", "journal"]
    for group in groups {
        let lowered = group.lowercased()
        for streakType in streakTypes {
            if lowered.contains(streakType) {
                return streakType.replacingOccurrences(of: " ", with: "_")
            }
        }
    }
    return "writing" // Default
}

// MARK: - Pattern Registration

extension PatternMatcher {

    /// Register Level System patterns with the pattern matcher.
    /// Call this during app initialization.
    func registerLevelSystemPatterns() {
        // In production, this would append to the patterns array
        // For now, the patterns are defined but integration happens
        // through the patterns computed property in PatternMatcher
    }
}

// MARK: - Command Pattern (Extended)

/// Extended command pattern definition for queries.
/// Note: The actual CommandPattern struct is defined in PatternMatcher.swift
/// This extension provides convenience initializers for query patterns.
extension CommandPattern {

    /// Convenience initializer for query patterns
    static func query(
        regex: String,
        queryType: ParsedAction.QueryType,
        matchedPattern: String,
        confidence: Double = 0.95
    ) -> CommandPattern {
        CommandPattern(
            regex: regex,
            action: .query,
            extractor: { _ in
                PatternMatchResult(
                    action: .query,
                    matchedPattern: matchedPattern,
                    confidence: confidence,
                    queryType: queryType
                )
            }
        )
    }
}
