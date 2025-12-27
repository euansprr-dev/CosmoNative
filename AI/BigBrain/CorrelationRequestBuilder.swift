// CosmoOS/AI/BigBrain/CorrelationRequestBuilder.swift
// Builds prompts for Claude API correlation analysis
// Part of the Big Brain architecture

import Foundation

// MARK: - Correlation Request Builder

/// Builds structured prompts for Claude API correlation analysis.
///
/// This struct transforms raw CosmoOS data into well-structured prompts
/// that Claude can analyze for cross-dimensional correlations.
///
/// Example usage:
/// ```swift
/// let context = CorrelationDataContext(...)
/// let prompt = CorrelationRequestBuilder.build(
///     dimensions: ["cognitive", "physiological"],
///     context: context
/// )
/// ```
public struct CorrelationRequestBuilder {

    // MARK: - Main Builder

    /// Build a correlation analysis prompt
    public static func build(
        dimensions: [String],
        context: CorrelationDataContext
    ) -> String {
        var prompt = baseSystemPrompt()
        prompt += "\n\n"
        prompt += buildDataSection(context: context, dimensions: dimensions)
        prompt += "\n\n"
        prompt += buildAnalysisInstructions(dimensions: dimensions)
        prompt += "\n\n"
        prompt += outputFormatInstructions()

        return prompt
    }

    /// Build an enhanced prompt with raw journal entries and pre-computed correlations
    public static func buildEnhanced(
        dimensions: [String],
        context: EnhancedCorrelationContext,
        preComputedCorrelations: [PreComputedCorrelation]? = nil
    ) -> String {
        var prompt = baseSystemPrompt()
        prompt += "\n\n"
        prompt += buildDataSection(context: context.baseContext, dimensions: dimensions)

        // Add raw journal entries for deeper semantic analysis
        if !context.recentJournalEntries.isEmpty {
            prompt += "\n\n"
            prompt += buildJournalSection(entries: context.recentJournalEntries)
        }

        // Add pre-computed correlations as hints
        if let correlations = preComputedCorrelations, !correlations.isEmpty {
            prompt += "\n\n"
            prompt += buildPreComputedSection(correlations: correlations)
        }

        prompt += "\n\n"
        prompt += buildAnalysisInstructions(dimensions: dimensions)
        prompt += "\n\n"
        prompt += outputFormatInstructions()

        return prompt
    }

    // MARK: - Raw Journal Section

    private static func buildJournalSection(entries: [JournalEntrySummary]) -> String {
        var section = "### Recent Journal Entries (Raw Text)\n\n"
        section += "Analyze these entries for emotional patterns, recurring themes, and behavioral indicators:\n\n"

        for entry in entries {
            let truncatedContent = entry.content.prefix(500)
            section += "**[\(entry.date)] (\(entry.type))**\n"
            section += "\(truncatedContent)\n\n"
        }

        return section
    }

    // MARK: - Pre-Computed Correlations Section

    private static func buildPreComputedSection(correlations: [PreComputedCorrelation]) -> String {
        var section = "### Pre-Computed Statistical Correlations\n\n"
        section += "The CausalityEngine has computed these correlations. Validate and explain them:\n\n"

        for corr in correlations {
            section += "- **\(corr.metric1) ↔ \(corr.metric2)**: r=\(String(format: "%.2f", corr.pearsonR)), "
            section += "p=\(String(format: "%.3f", corr.pValue)), n=\(corr.sampleSize)\n"
        }

        section += "\nProvide human-readable explanations for significant correlations (r > 0.3)."

        return section
    }

    // MARK: - System Prompt

    private static func baseSystemPrompt() -> String {
        return """
        You are the CosmoOS Correlation Engine, an advanced pattern recognition system for personal optimization.

        # About CosmoOS

        CosmoOS is a "Cognitive Operating System" - a unified life management platform that tracks 6 dimensions of human performance:

        1. **Physiological**: HRV (heart rate variability), resting heart rate, sleep quality/duration, readiness scores, recovery patterns. Higher HRV = better parasympathetic function = more cognitive capacity.

        2. **Cognitive**: Deep work sessions, writing output (words written), idea creation, task completion. Measures focused intellectual output.

        3. **Behavioral**: Consistency patterns, streaks (daily habits), routine adherence, schedule block completion. Measures follow-through.

        4. **Creative**: Content published, social reach, viral posts (>10K impressions), engagement rates. Measures creative output and impact.

        5. **Reflection**: Journal entries (gratitude, challenges, learnings), sentiment analysis, clarity scores. Measures self-awareness depth.

        6. **Knowledge**: Research saved, mental model connections made, topics explored, semantic clusters. Measures learning integration.

        # Your Task

        Analyze cross-dimensional correlations. The most valuable insights connect different dimensions:
        - Physiology → Cognitive (e.g., sleep quality affects deep work capacity)
        - Reflection → Behavioral (e.g., journaling consistency affects task completion)
        - Creative → Physiological (e.g., content creation on high-HRV days performs better)

        # Correlation Criteria

        - Minimum association strength: 0.3 (Pearson r or equivalent)
        - Minimum effect size: 10% difference
        - Must be actionable (user can change behavior)
        - Avoid obvious correlations (e.g., "more sleep = less tired")
        - Prioritize non-obvious, cross-dimensional insights

        # Few-Shot Examples

        **Good Correlation:**
        "HRV above 50ms correlates with 40% more deep work output. On days when morning HRV exceeded 50ms, user averaged 95 minutes of deep work vs 55 minutes on low-HRV days. Action: Check HRV before scheduling cognitively demanding work."

        **Good Correlation:**
        "Evening journaling correlates with next-day task completion (+25%). Days following a journal entry had 78% task completion vs 53% on days without prior journaling. The reflection process appears to prime executive function. Action: Journal before sleep to boost next-day productivity."

        **Bad Correlation (avoid):**
        "Sleeping more leads to feeling more rested" - Too obvious, not actionable.

        **Bad Correlation (avoid):**
        "User is productive on weekdays" - No cross-dimensional insight.

        Be specific. Cite actual data points. Focus on insights the user wouldn't discover themselves.
        """
    }

    // MARK: - Data Sections

    private static func buildDataSection(
        context: CorrelationDataContext,
        dimensions: [String]
    ) -> String {
        var sections: [String] = []

        sections.append("## User Data (Last \(context.timeframeDays) Days)")
        sections.append("")

        // Physiological data
        if dimensions.contains("physiological") || dimensions.contains("all") {
            if let phys = context.physiological {
                sections.append("### Physiological")
                sections.append("- HRV Trend: \(phys.hrvTrend)")
                sections.append("- Average Resting HR: \(phys.avgRestingHR) bpm")
                sections.append("- Sleep Quality Trend: \(phys.sleepQualityTrend)")
                sections.append("- Average Sleep Duration: \(String(format: "%.1f", phys.avgSleepHours)) hours")
                sections.append("- Readiness Scores: \(phys.readinessScoreSummary)")
                sections.append("- Recovery Pattern: \(phys.recoveryPattern)")
                sections.append("")
            }
        }

        // Behavioral data
        if dimensions.contains("behavioral") || dimensions.contains("all") {
            if let behav = context.behavioral {
                sections.append("### Behavioral")
                sections.append("- Deep Work Minutes/Day: \(behav.avgDeepWorkMinutes)")
                sections.append("- Focus Session Count: \(behav.focusSessionCount)")
                sections.append("- Task Completion Rate: \(String(format: "%.0f", behav.taskCompletionRate * 100))%")
                sections.append("- Active Streaks: \(behav.activeStreaks.joined(separator: ", "))")
                sections.append("- Streak Breaks: \(behav.streakBreaks)")
                sections.append("- Most Productive Hours: \(behav.mostProductiveHours)")
                sections.append("")
            }
        }

        // Cognitive data
        if dimensions.contains("cognitive") || dimensions.contains("all") {
            if let cog = context.cognitive {
                sections.append("### Cognitive")
                sections.append("- Ideas Created: \(cog.ideasCreated)")
                sections.append("- Tasks Created: \(cog.tasksCreated)")
                sections.append("- Writing Sessions: \(cog.writingSessions)")
                sections.append("- Total Words Written: \(cog.totalWordsWritten)")
                sections.append("- XP Earned: \(cog.xpEarned)")
                sections.append("- Cognitive Dimension Level: \(cog.dimensionLevel)")
                sections.append("")
            }
        }

        // Creative data
        if dimensions.contains("creative") || dimensions.contains("all") {
            if let creative = context.creative {
                sections.append("### Creative")
                sections.append("- Content Published: \(creative.contentPublished)")
                sections.append("- Total Reach: \(creative.totalReach)")
                sections.append("- Viral Posts (>10K reach): \(creative.viralPosts)")
                sections.append("- Engagement Rate: \(String(format: "%.1f", creative.engagementRate * 100))%")
                sections.append("- Best Performing Topics: \(creative.bestTopics.joined(separator: ", "))")
                sections.append("- Pipeline Status: \(creative.pipelineStatus)")
                sections.append("")
            }
        }

        // Reflection data
        if dimensions.contains("reflection") || dimensions.contains("all") {
            if let refl = context.reflection {
                sections.append("### Reflection")
                sections.append("- Journal Entries: \(refl.journalEntryCount)")
                sections.append("- Sentiment Trend: \(refl.sentimentTrend)")
                sections.append("- Key Themes: \(refl.keyThemes.joined(separator: ", "))")
                sections.append("- Gratitude Entries: \(refl.gratitudeCount)")
                sections.append("- Challenge Entries: \(refl.challengeCount)")
                sections.append("- Clarity Score Trend: \(refl.clarityScoreTrend)")
                sections.append("")
            }
        }

        // Knowledge data
        if dimensions.contains("knowledge") || dimensions.contains("all") {
            if let know = context.knowledge {
                sections.append("### Knowledge")
                sections.append("- Research Items Saved: \(know.researchItemsSaved)")
                sections.append("- Connections Made: \(know.connectionsMade)")
                sections.append("- Learning Sessions: \(know.learningSessions)")
                sections.append("- Topics Explored: \(know.topicsExplored.joined(separator: ", "))")
                sections.append("- Knowledge Dimension Level: \(know.dimensionLevel)")
                sections.append("")
            }
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Analysis Instructions

    private static func buildAnalysisInstructions(dimensions: [String]) -> String {
        let dimensionList = dimensions.isEmpty ? "all dimensions" : dimensions.joined(separator: " and ")

        return """
        ## Analysis Task

        Analyze the data above focusing on \(dimensionList).

        Identify the TOP 3 most significant correlations. For each correlation:

        1. **Variables**: Which two (or more) metrics are correlated?
        2. **Direction**: Positive or negative correlation?
        3. **Strength**: Estimated correlation strength (weak/moderate/strong)
        4. **Effect Size**: How much impact does one variable have on the other?
        5. **Insight**: What does this mean for the user?
        6. **Action**: What specific action should the user take?
        7. **Confidence**: How confident are you in this correlation? (low/medium/high)

        Focus on:
        - Non-obvious connections (avoid stating the obvious)
        - Actionable insights (user can change behavior)
        - Evidence-based conclusions (cite specific data points)
        - Practical recommendations
        """
    }

    // MARK: - Output Format

    private static func outputFormatInstructions() -> String {
        return """
        ## Output Format

        Return your analysis as a JSON array with this structure:

        ```json
        [
          {
            "id": "corr_001",
            "type": "cross_dimensional",
            "dimensions": ["physiological", "cognitive"],
            "variables": ["hrv_trend", "deep_work_minutes"],
            "direction": "positive",
            "strength": "moderate",
            "pearsonR": 0.42,
            "effectSize": 0.25,
            "insight": "Higher HRV days correlate with 40% more deep work output. On days when morning HRV exceeded 50ms, user averaged 95 minutes of deep work vs 55 minutes on low-HRV days.",
            "mechanism": "Higher HRV indicates better parasympathetic recovery, providing more cognitive resources for sustained focus.",
            "action": "Check HRV before scheduling cognitively demanding work. On low-HRV days (<40ms), prioritize administrative tasks.",
            "confidence": "high",
            "supportingData": [
              "HRV >50ms: 95min avg deep work (n=23 days)",
              "HRV <40ms: 55min avg deep work (n=18 days)",
              "Effect persists after controlling for sleep duration"
            ],
            "atomTypes": ["hrvMeasurement", "deepWorkBlock"]
          }
        ]
        ```

        Required fields:
        - `id`: Unique identifier (corr_001, corr_002, etc.)
        - `type`: "cross_dimensional", "intra_dimensional", or "temporal"
        - `dimensions`: Which CosmoOS dimensions are involved
        - `variables`: Specific metrics correlated
        - `insight`: Human-readable finding with specific numbers
        - `mechanism`: WHY this correlation exists (causal hypothesis)
        - `action`: Specific, actionable recommendation
        - `confidence`: "low", "medium", or "high"
        - `supportingData`: Array of specific data points supporting the correlation
        - `atomTypes`: Which Atom types in CosmoOS contain this data

        Return ONLY the JSON array. No markdown, no explanation, just valid JSON.
        """
    }

    // MARK: - Synthesis Prompts

    /// Build a synthesis prompt for generative requests
    public static func buildSynthesisPrompt(
        transcript: String,
        context: SynthesisContext
    ) -> String {
        return """
        You are the CosmoOS Big Brain, helping the user with a generative request.

        User request: "\(transcript)"

        Context:
        - Current section: \(context.currentSection)
        - Current project: \(context.currentProject ?? "none")
        - Time of day: \(context.timeOfDay)
        - Recent activity: \(context.recentActivitySummary)

        Provide a helpful, concise response. Be specific and actionable.
        If the user is asking for ideas, provide 3-5 concrete suggestions.
        If the user is asking for analysis, be data-driven and insightful.
        """
    }

    /// Build a journal insight prompt
    public static func buildJournalInsightPrompt(
        entries: [JournalEntrySummary],
        focus: String?
    ) -> String {
        let entriesText = entries.map { "- [\($0.date)] (\($0.type)): \($0.content)" }.joined(separator: "\n")
        let focusInstruction = focus.map { "Focus especially on: \($0)" } ?? ""

        return """
        Analyze these recent journal entries and provide insights:

        \(entriesText)

        \(focusInstruction)

        Provide:
        1. Key themes emerging from these entries
        2. Emotional patterns you notice
        3. Any concerns or areas needing attention
        4. Specific suggestions for the user

        Be compassionate but honest. Focus on growth opportunities.
        """
    }
}

// MARK: - Data Context Types

/// Complete context for correlation analysis
public struct CorrelationDataContext: Codable, Sendable {
    public let timeframeDays: Int
    public let physiological: PhysiologicalData?
    public let behavioral: BehavioralData?
    public let cognitive: CognitiveData?
    public let creative: CreativeData?
    public let reflection: ReflectionData?
    public let knowledge: KnowledgeData?

    public init(
        timeframeDays: Int = 90,
        physiological: PhysiologicalData? = nil,
        behavioral: BehavioralData? = nil,
        cognitive: CognitiveData? = nil,
        creative: CreativeData? = nil,
        reflection: ReflectionData? = nil,
        knowledge: KnowledgeData? = nil
    ) {
        self.timeframeDays = timeframeDays
        self.physiological = physiological
        self.behavioral = behavioral
        self.cognitive = cognitive
        self.creative = creative
        self.reflection = reflection
        self.knowledge = knowledge
    }
}

/// Physiological dimension data
public struct PhysiologicalData: Codable, Sendable {
    public let hrvTrend: String
    public let avgRestingHR: Int
    public let sleepQualityTrend: String
    public let avgSleepHours: Double
    public let readinessScoreSummary: String
    public let recoveryPattern: String

    public init(hrvTrend: String, avgRestingHR: Int, sleepQualityTrend: String, avgSleepHours: Double, readinessScoreSummary: String, recoveryPattern: String) {
        self.hrvTrend = hrvTrend
        self.avgRestingHR = avgRestingHR
        self.sleepQualityTrend = sleepQualityTrend
        self.avgSleepHours = avgSleepHours
        self.readinessScoreSummary = readinessScoreSummary
        self.recoveryPattern = recoveryPattern
    }
}

/// Behavioral dimension data
public struct BehavioralData: Codable, Sendable {
    public let avgDeepWorkMinutes: Int
    public let focusSessionCount: Int
    public let taskCompletionRate: Double
    public let activeStreaks: [String]
    public let streakBreaks: Int
    public let mostProductiveHours: String

    public init(avgDeepWorkMinutes: Int, focusSessionCount: Int, taskCompletionRate: Double, activeStreaks: [String], streakBreaks: Int, mostProductiveHours: String) {
        self.avgDeepWorkMinutes = avgDeepWorkMinutes
        self.focusSessionCount = focusSessionCount
        self.taskCompletionRate = taskCompletionRate
        self.activeStreaks = activeStreaks
        self.streakBreaks = streakBreaks
        self.mostProductiveHours = mostProductiveHours
    }
}

/// Cognitive dimension data
public struct CognitiveData: Codable, Sendable {
    public let ideasCreated: Int
    public let tasksCreated: Int
    public let writingSessions: Int
    public let totalWordsWritten: Int
    public let xpEarned: Int
    public let dimensionLevel: Int

    public init(ideasCreated: Int, tasksCreated: Int, writingSessions: Int, totalWordsWritten: Int, xpEarned: Int, dimensionLevel: Int) {
        self.ideasCreated = ideasCreated
        self.tasksCreated = tasksCreated
        self.writingSessions = writingSessions
        self.totalWordsWritten = totalWordsWritten
        self.xpEarned = xpEarned
        self.dimensionLevel = dimensionLevel
    }
}

/// Creative dimension data
public struct CreativeData: Codable, Sendable {
    public let contentPublished: Int
    public let totalReach: Int
    public let viralPosts: Int
    public let engagementRate: Double
    public let bestTopics: [String]
    public let pipelineStatus: String

    public init(contentPublished: Int, totalReach: Int, viralPosts: Int, engagementRate: Double, bestTopics: [String], pipelineStatus: String) {
        self.contentPublished = contentPublished
        self.totalReach = totalReach
        self.viralPosts = viralPosts
        self.engagementRate = engagementRate
        self.bestTopics = bestTopics
        self.pipelineStatus = pipelineStatus
    }
}

/// Reflection dimension data
public struct ReflectionData: Codable, Sendable {
    public let journalEntryCount: Int
    public let sentimentTrend: String
    public let keyThemes: [String]
    public let gratitudeCount: Int
    public let challengeCount: Int
    public let clarityScoreTrend: String

    public init(journalEntryCount: Int, sentimentTrend: String, keyThemes: [String], gratitudeCount: Int, challengeCount: Int, clarityScoreTrend: String) {
        self.journalEntryCount = journalEntryCount
        self.sentimentTrend = sentimentTrend
        self.keyThemes = keyThemes
        self.gratitudeCount = gratitudeCount
        self.challengeCount = challengeCount
        self.clarityScoreTrend = clarityScoreTrend
    }
}

/// Knowledge dimension data
public struct KnowledgeData: Codable, Sendable {
    public let researchItemsSaved: Int
    public let connectionsMade: Int
    public let learningSessions: Int
    public let topicsExplored: [String]
    public let dimensionLevel: Int

    public init(researchItemsSaved: Int, connectionsMade: Int, learningSessions: Int, topicsExplored: [String], dimensionLevel: Int) {
        self.researchItemsSaved = researchItemsSaved
        self.connectionsMade = connectionsMade
        self.learningSessions = learningSessions
        self.topicsExplored = topicsExplored
        self.dimensionLevel = dimensionLevel
    }
}

/// Context for synthesis requests
public struct SynthesisContext: Codable, Sendable {
    public let currentSection: String
    public let currentProject: String?
    public let timeOfDay: String
    public let recentActivitySummary: String

    public init(currentSection: String, currentProject: String?, timeOfDay: String, recentActivitySummary: String) {
        self.currentSection = currentSection
        self.currentProject = currentProject
        self.timeOfDay = timeOfDay
        self.recentActivitySummary = recentActivitySummary
    }
}

// MARK: - Correlation Triggers

/// Reasons that trigger correlation analysis
public enum CorrelationTrigger: String, Codable, Sendable {
    case scheduled = "scheduled"          // Nightly at midnight
    case newJournal = "new_journal"       // After 3+ journal entries
    case sleepData = "sleep_data"         // New sleep data from HealthKit
    case hrvShift = "hrv_shift"           // HRV changes >15% from baseline
    case contentPerformance = "content"   // New content performance data
    case streakChange = "streak_change"   // Streak milestone or break
    case manual = "manual"                // User-triggered
}

// MARK: - Pre-Computed Correlation

/// A correlation computed by the CausalityEngine to be validated by Claude
public struct PreComputedCorrelation: Codable, Sendable {
    public let metric1: String
    public let metric2: String
    public let pearsonR: Double
    public let pValue: Double
    public let sampleSize: Int
    public let dimension1: String?
    public let dimension2: String?

    public init(
        metric1: String,
        metric2: String,
        pearsonR: Double,
        pValue: Double,
        sampleSize: Int,
        dimension1: String? = nil,
        dimension2: String? = nil
    ) {
        self.metric1 = metric1
        self.metric2 = metric2
        self.pearsonR = pearsonR
        self.pValue = pValue
        self.sampleSize = sampleSize
        self.dimension1 = dimension1
        self.dimension2 = dimension2
    }
}

// MARK: - Claude Correlation Output

/// The expected structure of Claude's correlation analysis output
public struct ClaudeCorrelationOutput: Codable, Sendable {
    public let id: String
    public let type: String
    public let dimensions: [String]
    public let variables: [String]
    public let direction: String
    public let strength: String
    public let pearsonR: Double?
    public let effectSize: Double
    public let insight: String
    public let mechanism: String
    public let action: String
    public let confidence: String
    public let supportingData: [String]
    public let atomTypes: [String]
}

// MARK: - Correlation Analysis Result

/// Complete result from a correlation analysis session
public struct CorrelationAnalysisResult: Codable, Sendable {
    public let correlations: [ClaudeCorrelationOutput]
    public let trigger: CorrelationTrigger
    public let analyzedAt: String
    public let dimensionsAnalyzed: [String]
    public let dataPointsConsidered: Int

    public init(
        correlations: [ClaudeCorrelationOutput],
        trigger: CorrelationTrigger,
        analyzedAt: String,
        dimensionsAnalyzed: [String],
        dataPointsConsidered: Int
    ) {
        self.correlations = correlations
        self.trigger = trigger
        self.analyzedAt = analyzedAt
        self.dimensionsAnalyzed = dimensionsAnalyzed
        self.dataPointsConsidered = dataPointsConsidered
    }
}
