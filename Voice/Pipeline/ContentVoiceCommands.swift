// CosmoOS/Voice/Pipeline/ContentVoiceCommands.swift
// Tier 0 voice patterns for Content Pipeline queries and actions
// Enables fast voice control for content creation and performance tracking

import Foundation
import GRDB

// MARK: - Content Voice Patterns

/// Extension to PatternMatcher for Content Pipeline voice commands.
/// These patterns enable fast (<50ms) voice control for:
/// - Content performance queries
/// - Content creation commands
/// - Publishing actions
/// - Client queries
extension PatternMatcher {

    /// Content Pipeline patterns to be registered
    static var contentPipelinePatterns: [CommandPattern] {
        [
            // ===== PERFORMANCE QUERIES =====
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?(content\s+)?(performance|reach|impressions)\s*(today|this\s+week|this\s+month)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[6].lowercased()
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "content_performance",
                        confidence: 0.95,
                        queryType: .contentPerformance,
                        timePeriod: extractTimePeriod(from: period).rawValue
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how\s+much|what('?s| is))\s+(my\s+)?(total\s+)?reach\s*(today|this\s+week|this\s+month)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[5].lowercased()
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "total_reach",
                        confidence: 0.95,
                        queryType: .totalReach,
                        timePeriod: extractTimePeriod(from: period).rawValue
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?(engagement\s*rate|avg\s+engagement)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "engagement_rate",
                        confidence: 0.95,
                        queryType: .engagementRate
                    )
                }
            ),

            // ===== VIRAL CONTENT QUERIES =====
            CommandPattern(
                regex: #"^(how\s+many|what)\s+(viral\s+)?(posts?|content)\s+(did\s+i\s+have|went\s+viral)\s*(today|this\s+week|this\s+month)?\s*\??$"#,
                action: .query,
                extractor: { match in
                    let period = match[5].lowercased()
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "viral_count",
                        confidence: 0.9,
                        queryType: .viralCount,
                        timePeriod: extractTimePeriod(from: period).rawValue
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|list)\s+(my\s+)?viral\s+(content|posts?)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "viral_list",
                        confidence: 0.95,
                        queryType: .viralContent
                    )
                }
            ),
            CommandPattern(
                regex: #"^(what('?s| was)|show\s+me)\s+(my\s+)?best\s+(performing\s+)?(content|post)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "best_content",
                        confidence: 0.95,
                        queryType: .topContent
                    )
                }
            ),

            // ===== CONTENT CREATION =====
            CommandPattern(
                regex: #"^(create|start|new)\s+(a\s+)?(content\s*)?(piece|draft|post)\s*(for\s+)?(twitter|linkedin|instagram|tiktok|youtube|substack|medium)?\s*(.*)$"#,
                action: .create,
                atomType: .content,
                extractor: { match in
                    let title = match[7].trimmingCharacters(in: .whitespaces)

                    return PatternMatchResult(
                        action: .create,
                        atomType: .content,
                        title: title.isEmpty ? "New Content" : title,
                        matchedPattern: "create_content",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    var metadata: [String: VoiceAnyCodable] = [
                        "phase": VoiceAnyCodable("ideation"),
                        "source": VoiceAnyCodable("voice")
                    ]

                    let platform = match[6].lowercased()
                    if !platform.isEmpty {
                        metadata["platform"] = VoiceAnyCodable(platform)
                    }

                    return metadata
                }
            ),

            // ===== CONTENT PHASE COMMANDS =====
            CommandPattern(
                regex: #"^(move|advance|progress)\s+(this\s+)?(content|draft)\s+(to\s+)?(outline|draft|polish|scheduled|published)\s*$"#,
                action: .update,
                extractor: { _ in
                    PatternMatchResult(
                        action: .update,
                        matchedPattern: "advance_phase",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let targetPhase = match[5].lowercased()
                    return [
                        "advanceToPhase": VoiceAnyCodable(targetPhase)
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(mark\s+this\s+)?(as\s+)?(ready\s+to\s+publish|scheduled|done)\s*$"#,
                action: .update,
                extractor: { _ in
                    PatternMatchResult(
                        action: .update,
                        matchedPattern: "mark_phase",
                        confidence: 0.85
                    )
                },
                metadataExtractor: { match in
                    let status = match[3].lowercased()
                    let targetPhase = status.contains("publish") ? "scheduled" : "published"
                    return [
                        "advanceToPhase": VoiceAnyCodable(targetPhase)
                    ]
                }
            ),

            // ===== PUBLISHING COMMANDS =====
            CommandPattern(
                regex: #"^publish\s+(this\s+)?(content\s+)?(to|on)\s+(twitter|linkedin|instagram|tiktok|youtube|substack|medium)\s*$"#,
                action: .update,
                extractor: { _ in
                    return PatternMatchResult(
                        action: .update,
                        matchedPattern: "publish_content",
                        confidence: 0.95
                    )
                },
                metadataExtractor: { match in
                    let platform = match[4].lowercased()
                    return [
                        "publishTo": VoiceAnyCodable(platform),
                        "publishNow": VoiceAnyCodable(true)
                    ]
                }
            ),
            CommandPattern(
                regex: #"^(i\s+)?(just\s+)?published\s+(a\s+)?(post|thread|article|video)\s+(to|on)\s+(twitter|linkedin|instagram|tiktok|youtube|substack|medium)\s*$"#,
                action: .create,
                atomType: .contentPublish,
                extractor: { match in
                    let contentType = match[4]
                    let platform = match[6].lowercased()

                    return PatternMatchResult(
                        action: .create,
                        atomType: .contentPublish,
                        title: "Published \(contentType) to \(platform.capitalized)",
                        matchedPattern: "record_publish",
                        confidence: 0.9
                    )
                },
                metadataExtractor: { match in
                    let contentType = match[4].lowercased()
                    let platform = match[6].lowercased()

                    return [
                        "platform": VoiceAnyCodable(platform),
                        "mediaType": VoiceAnyCodable(contentType),
                        "publishedAt": VoiceAnyCodable(ISO8601DateFormatter().string(from: Date())),
                        "source": VoiceAnyCodable("voice")
                    ]
                }
            ),

            // ===== PERFORMANCE UPDATE =====
            CommandPattern(
                regex: #"^(my|the)\s+(last\s+)?(post|thread|content)\s+(got|has|reached)\s+(\d+)\s*(k|m)?\s*(impressions|views|reach)\s*$"#,
                action: .create,
                atomType: .contentPerformance,
                extractor: { match in
                    let amount = match[5]
                    let multiplier = match[6].lowercased()
                    let metricType = match[7]

                    var impressions = Int(amount) ?? 0
                    if multiplier == "k" { impressions *= 1000 }
                    if multiplier == "m" { impressions *= 1_000_000 }

                    return PatternMatchResult(
                        action: .create,
                        atomType: .contentPerformance,
                        title: "\(impressions.formatted()) \(metricType)",
                        matchedPattern: "record_performance",
                        confidence: 0.85
                    )
                },
                metadataExtractor: { match in
                    let amount = match[5]
                    let multiplier = match[6].lowercased()

                    var impressions = Int(amount) ?? 0
                    if multiplier == "k" { impressions *= 1000 }
                    if multiplier == "m" { impressions *= 1_000_000 }

                    return [
                        "impressions": VoiceAnyCodable(impressions),
                        "source": VoiceAnyCodable("voice")
                    ]
                }
            ),

            // ===== CLIENT QUERIES =====
            CommandPattern(
                regex: #"^(how('?s| is)|what('?s| is))\s+(my\s+)?client\s+(.+)\s+(doing|performing)\s*\??$"#,
                action: .query,
                extractor: { match in
                    let clientName = match[5].trimmingCharacters(in: .whitespaces)
                    return PatternMatchResult(
                        action: .query,
                        matchedPattern: "client_performance",
                        confidence: 0.85,
                        queryType: .clientPerformance,
                        entityName: clientName
                    )
                }
            ),
            CommandPattern(
                regex: #"^(show|list)\s+(my\s+)?(all\s+)?clients?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "list_clients",
                        confidence: 0.95,
                        queryType: .clientList
                    )
                }
            ),

            // ===== CONTENT PIPELINE STATUS =====
            CommandPattern(
                regex: #"^(what('?s| is)|show\s+me)\s+(in\s+)?(my\s+)?(content\s+)?pipeline\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "pipeline_status",
                        confidence: 0.95,
                        queryType: .pipelineStatus
                    )
                }
            ),
            CommandPattern(
                regex: #"^(how\s+many|what)\s+(content\s+)?(pieces|posts|drafts)\s+(do\s+i\s+have\s+)?(in\s+progress|active|in\s+draft)\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "active_content",
                        confidence: 0.9,
                        queryType: .activeContent
                    )
                }
            ),

            // ===== CREATIVE DIMENSION QUERY =====
            CommandPattern(
                regex: #"^(what('?s| is)|how('?s| is))\s+(my\s+)?creative\s*(dimension|level|score)?\s*\??$"#,
                action: .query,
                extractor: { _ in
                    PatternMatchResult(
                        action: .query,
                        matchedPattern: "creative_dimension",
                        confidence: 0.95,
                        queryType: .creativeDimension
                    )
                }
            ),
        ]
    }

    // MARK: - Helper Functions

    private static func extractTimePeriod(from text: String) -> TimePeriod {
        if text.contains("week") { return .week }
        if text.contains("month") { return .month }
        return .today
    }
}

// MARK: - Time Period

enum TimePeriod: String, Sendable {
    case today
    case week
    case month
    case quarter
    case year
}

// MARK: - Extended Query Types for Content

extension ParsedAction {
    enum ContentQueryType: String, Codable, Sendable {
        case contentPerformance
        case totalReach
        case engagementRate
        case viralCount
        case viralContent
        case topContent
        case clientPerformance
        case clientList
        case pipelineStatus
        case activeContent
        case creativeDimension
    }
}

// MARK: - Content Query Handler

/// Handles content-related voice queries
actor ContentQueryHandler {
    @MainActor static let shared = ContentQueryHandler()

    private let pipelineService: ContentPipelineService
    private let analyticsEngine: ContentAnalyticsEngine
    private let database: any DatabaseWriter

    @MainActor
    init(
        database: (any DatabaseWriter)? = nil
    ) {
        self.database = database ?? (CosmoDatabase.shared.dbQueue! as any DatabaseWriter)
        self.pipelineService = ContentPipelineService(database: self.database)
        self.analyticsEngine = ContentAnalyticsEngine(database: self.database)
    }

    /// Execute a content query and return a voice-ready response
    func executeQuery(queryType: ParsedAction.QueryType, timePeriod: TimePeriod = .today) async throws -> QueryResponse {
        switch queryType {
        case .contentPerformance, .totalReach:
            return try await handleReachQuery(period: timePeriod)
        case .engagementRate:
            return try await handleEngagementQuery()
        case .viralCount:
            return try await handleViralCountQuery(period: timePeriod)
        case .viralContent, .topContent:
            return try await handleTopContentQuery()
        case .pipelineStatus, .activeContent:
            return try await handlePipelineStatusQuery()
        case .creativeDimension:
            return try await handleCreativeDimensionQuery()
        default:
            throw ContentQueryError.unsupportedQuery
        }
    }

    // MARK: - Query Handlers

    private func handleReachQuery(period: TimePeriod) async throws -> QueryResponse {
        let reach = try await analyticsEngine.calculateWeeklyReach()

        let periodText = period == .today ? "today" : (period == .week ? "this week" : "this month")

        return QueryResponse(
            queryType: .totalReach,
            spokenText: "Your total reach \(periodText) is \(formatNumber(reach)) impressions.",
            displayTitle: formatNumber(reach),
            displaySubtitle: "Total reach \(periodText)",
            metrics: [
                QueryMetric(label: "Reach", value: formatNumber(reach), icon: "eye.fill", color: "blue", trend: nil)
            ],
            action: QueryAction(title: "View Details", destination: "content_performance")
        )
    }

    private func handleEngagementQuery() async throws -> QueryResponse {
        let engagement = try await analyticsEngine.calculateAverageEngagementRate()
        let engagementPercent = String(format: "%.2f%%", engagement * 100)

        return QueryResponse(
            queryType: .engagementRate,
            spokenText: "Your average engagement rate is \(engagementPercent).",
            displayTitle: engagementPercent,
            displaySubtitle: "Average engagement rate",
            metrics: [
                QueryMetric(label: "Engagement", value: engagementPercent, icon: "hand.thumbsup.fill", color: "green", trend: nil)
            ],
            action: QueryAction(title: "View Details", destination: "content_performance")
        )
    }

    private func handleViralCountQuery(period: TimePeriod) async throws -> QueryResponse {
        let viralCount = try await analyticsEngine.calculateMonthlyViralCount()

        let periodText = period == .month ? "this month" : "recently"

        return QueryResponse(
            queryType: .viralCount,
            spokenText: viralCount > 0
                ? "You've had \(viralCount) viral post\(viralCount == 1 ? "" : "s") \(periodText)."
                : "No viral posts \(periodText) yet. Keep creating!",
            displayTitle: "\(viralCount)",
            displaySubtitle: "Viral posts \(periodText)",
            metrics: [
                QueryMetric(label: "Viral Posts", value: "\(viralCount)", icon: "flame.fill", color: "orange", trend: nil)
            ],
            action: viralCount > 0 ? QueryAction(title: "View Viral Content", destination: "viral_content") : nil
        )
    }

    private func handleTopContentQuery() async throws -> QueryResponse {
        let topContent = try await analyticsEngine.getTopContent(limit: 3)

        guard let best = topContent.first else {
            return QueryResponse(
                queryType: .topContent,
                spokenText: "No performance data available yet.",
                displayTitle: "No Data",
                displaySubtitle: "Start tracking content to see performance",
                metrics: [],
                action: nil
            )
        }

        return QueryResponse(
            queryType: .topContent,
            spokenText: "Your best performing content has \(formatNumber(best.impressions)) impressions with a \(String(format: "%.1f%%", best.engagementRate * 100)) engagement rate on \(best.platform.displayName).",
            displayTitle: formatNumber(best.impressions),
            displaySubtitle: "Top content impressions",
            metrics: [
                QueryMetric(label: "Platform", value: best.platform.displayName, icon: best.platform.iconName, color: nil, trend: nil),
                QueryMetric(label: "Impressions", value: formatNumber(best.impressions), icon: "eye.fill", color: "blue", trend: nil),
                QueryMetric(label: "Engagement", value: String(format: "%.1f%%", best.engagementRate * 100), icon: "hand.thumbsup.fill", color: "green", trend: nil)
            ],
            action: QueryAction(title: "View All", destination: "top_content")
        )
    }

    private func handlePipelineStatusQuery() async throws -> QueryResponse {
        let activeContent = try await database.read { db in
            try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .filter(sql: "json_extract(metadata, '$.phase') NOT IN (?, ?)",
                        arguments: [ContentPhase.archived.rawValue, ContentPhase.analyzing.rawValue])
                .fetchAll(db)
        }

        // Count by phase
        var phaseCounts: [ContentPhase: Int] = [:]
        for atom in activeContent {
            if let metadata = atom.metadataValue(as: ContentAtomMetadata.self) {
                phaseCounts[metadata.phase, default: 0] += 1
            }
        }

        let draftCount = phaseCounts[.draft, default: 0] + phaseCounts[.outline, default: 0]
        let polishCount = phaseCounts[.polish, default: 0]
        let scheduledCount = phaseCounts[.scheduled, default: 0]

        return QueryResponse(
            queryType: .pipelineStatus,
            spokenText: "You have \(activeContent.count) pieces in your content pipeline. \(draftCount) in draft, \(polishCount) being polished, and \(scheduledCount) scheduled.",
            displayTitle: "\(activeContent.count) Active",
            displaySubtitle: "Content in pipeline",
            metrics: [
                QueryMetric(label: "Drafts", value: "\(draftCount)", icon: "doc.text", color: "blue", trend: nil),
                QueryMetric(label: "Polishing", value: "\(polishCount)", icon: "sparkles", color: "purple", trend: nil),
                QueryMetric(label: "Scheduled", value: "\(scheduledCount)", icon: "calendar.badge.clock", color: "green", trend: nil)
            ],
            action: QueryAction(title: "View Pipeline", destination: "content_pipeline")
        )
    }

    private func handleCreativeDimensionQuery() async throws -> QueryResponse {
        let metrics = try await analyticsEngine.calculateCreativeDimensionMetrics()

        // Calculate dimension level from metrics
        let reachLevel = CreativeDimensionConfig.levelFor(metricValue: Double(metrics.weeklyReach), metric: "weeklyReach")
        let viralLevel = CreativeDimensionConfig.levelFor(metricValue: Double(metrics.viralPostsPerMonth), metric: "viralPosts")
        let engagementLevel = CreativeDimensionConfig.levelFor(metricValue: metrics.engagementRate, metric: "engagementRate")
        let publishedLevel = CreativeDimensionConfig.levelFor(metricValue: Double(metrics.publishedPerMonth), metric: "publishedPerMonth")

        let avgLevel = (reachLevel + viralLevel + engagementLevel + publishedLevel) / 4

        return QueryResponse(
            queryType: .dimensionStatus,
            spokenText: "Your Creative dimension is at level \(avgLevel). Weekly reach: \(formatNumber(metrics.weeklyReach)). Engagement: \(String(format: "%.1f%%", metrics.engagementRate)). \(metrics.viralPostsPerMonth) viral posts this month.",
            displayTitle: "Level \(avgLevel)",
            displaySubtitle: "Creative Dimension",
            metrics: [
                QueryMetric(label: "Weekly Reach", value: formatNumber(metrics.weeklyReach), icon: "eye.fill", color: "blue", trend: nil),
                QueryMetric(label: "Engagement", value: String(format: "%.1f%%", metrics.engagementRate), icon: "hand.thumbsup.fill", color: "green", trend: nil),
                QueryMetric(label: "Viral Posts", value: "\(metrics.viralPostsPerMonth)", icon: "flame.fill", color: "orange", trend: nil),
                QueryMetric(label: "Published", value: "\(metrics.publishedPerMonth)/mo", icon: "paperplane.fill", color: "purple", trend: nil)
            ],
            action: QueryAction(title: "View Details", destination: "creative_dimension")
        )
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

// MARK: - Errors

enum ContentQueryError: Error {
    case unsupportedQuery
    case noDataAvailable
}
