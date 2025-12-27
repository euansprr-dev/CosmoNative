// CosmoOS/Data/Models/Atom.swift
// Unified Atom model - the single foundational entity for all CosmoOS data
// Replaces fragmented tables (ideas, tasks, content, etc.) with one normalized structure

import GRDB
import Foundation

// MARK: - Atom Type Enum
/// All entity types that can be stored as Atoms
/// Extended for full Cognitive OS support (Leveling, Health, Content Pipeline, etc.)
public enum AtomType: String, Codable, CaseIterable, Sendable {
    // MARK: - Core Entity Types (Original)
    case idea
    case task
    case project
    case content
    case research
    case connection
    case journalEntry = "journal_entry"
    case calendarEvent = "calendar_event"
    case scheduleBlock = "schedule_block"
    case uncommittedItem = "uncommitted_item"

    // MARK: - Leveling & Gamification
    case xpEvent = "xp_event"                     // Every XP gain is an atom
    case levelUpdate = "level_update"             // CI or NELO level changes
    case streakEvent = "streak_event"             // Streak milestones
    case badgeUnlocked = "badge_unlocked"         // Achievement unlocks
    case badge                                    // Shorthand for badges
    case dimensionSnapshot = "dimension_snapshot" // Daily dimension scores

    // MARK: - Physiology (Apple Watch Ultra 3)
    case hrvMeasurement = "hrv_measurement"       // Heart Rate Variability readings
    case hrvReading = "hrv_reading"               // Alias for HRV readings
    case restingHR = "resting_hr"                 // Resting heart rate
    case sleepCycle = "sleep_cycle"               // Sleep stage data
    case sleepRecord = "sleep_record"             // Sleep data
    case sleepConsistency = "sleep_consistency"   // Sleep schedule adherence
    case readinessScore = "readiness_score"       // Daily readiness composite
    case recoveryScore = "recovery_score"         // Recovery metrics
    case workoutSession = "workout_session"       // Exercise data
    case workout                                  // Shorthand for workout
    case activityRing = "activity_ring"           // Activity ring data
    case mealLog = "meal_log"                     // Nutrition tracking
    case breathingSession = "breathing_session"   // Mindfulness/breathing
    case bloodOxygen = "blood_oxygen"             // SpO2 measurements
    case bodyTemperature = "body_temperature"     // Wrist temperature deviation

    // MARK: - Cognitive Output
    case deepWorkBlock = "deep_work_block"        // Focused work sessions
    case writingSession = "writing_session"       // Words written in session
    case wordCountEntry = "word_count_entry"      // Daily word aggregates
    case focusScore = "focus_score"               // Attention quality metrics
    case distractionEvent = "distraction_event"   // Context switches tracked

    // MARK: - Content Pipeline
    case contentDraft = "content_draft"           // Draft versions
    case contentPhase = "content_phase"           // Phase transitions
    case contentPerformance = "content_performance" // Analytics data
    case contentPublish = "content_publish"       // Publish events
    case clientProfile = "client_profile"         // Ghostwriting clients

    // MARK: - Knowledge Graph
    case semanticCluster = "semantic_cluster"     // Auto-grouped concepts
    case connectionLink = "connection_link"       // Explicit atom relationships
    case autoLinkSuggestion = "auto_link_suggestion" // AI-suggested links
    case insightExtraction = "insight_extraction" // AI-extracted insights

    // MARK: - Reflection
    case journalInsight = "journal_insight"       // Extracted from journals
    case analysisChunk = "analysis_chunk"         // LLM analysis segments
    case emotionalState = "emotional_state"       // Sentiment snapshots
    case clarityScore = "clarity_score"           // Journal quality metrics

    // MARK: - System
    case dailySummary = "daily_summary"           // End-of-day rollup
    case weeklySummary = "weekly_summary"         // Weekly analysis
    case syncEvent = "sync_event"                 // Sync operations
    case systemEvent = "system_event"             // App lifecycle events
    case userPreference = "user_preference"       // Settings as atoms
    case routineDefinition = "routine_definition" // Behavioral patterns

    // MARK: - Sanctuary / Causality Engine
    case correlationInsight = "correlation_insight"     // Discovered cross-metric correlations
    case causalityComputation = "causality_computation" // Computation run metadata
    case semanticExtraction = "semantic_extraction"     // Extracted topics/emotions from journals
    case sanctuarySnapshot = "sanctuary_snapshot"       // Daily Sanctuary state cache
    case livingInsight = "living_insight"               // Living Intelligence insights
    case syncState = "sync_state"                       // Sync state tracking

    // MARK: - Thinkspace (Infinite Canvas)
    case note                                           // Floating note blocks (orange)
    case thinkspace                                     // Saved Thinkspace configurations

    // MARK: - Planning & Objectives
    case objective                                      // Quarter/annual objectives (goals)

    // MARK: - Category Classification

    /// Category for grouping atom types
    var category: AtomCategory {
        switch self {
        case .idea, .task, .project, .content, .research, .connection,
             .journalEntry, .calendarEvent, .scheduleBlock, .uncommittedItem,
             .note, .objective:
            return .core
        case .xpEvent, .levelUpdate, .streakEvent, .badgeUnlocked, .badge, .dimensionSnapshot:
            return .leveling
        case .hrvMeasurement, .hrvReading, .restingHR, .sleepCycle, .sleepRecord, .sleepConsistency,
             .readinessScore, .recoveryScore, .workoutSession, .workout, .activityRing,
             .mealLog, .breathingSession, .bloodOxygen, .bodyTemperature:
            return .physiology
        case .deepWorkBlock, .writingSession, .wordCountEntry, .focusScore, .distractionEvent:
            return .cognitive
        case .contentDraft, .contentPhase, .contentPerformance, .contentPublish, .clientProfile:
            return .contentPipeline
        case .semanticCluster, .connectionLink, .autoLinkSuggestion, .insightExtraction:
            return .knowledge
        case .journalInsight, .analysisChunk, .emotionalState, .clarityScore:
            return .reflection
        case .dailySummary, .weeklySummary, .syncEvent, .systemEvent, .userPreference, .routineDefinition,
             .thinkspace:
            return .system
        case .correlationInsight, .causalityComputation, .semanticExtraction, .sanctuarySnapshot,
             .livingInsight, .syncState:
            return .sanctuary
        }
    }

    /// Whether this atom type contributes to XP
    var contributesToXP: Bool {
        switch category {
        case .core, .physiology, .cognitive, .contentPipeline, .knowledge, .reflection, .sanctuary:
            return true
        case .leveling, .system:
            return false
        }
    }

    /// The dimension this atom type primarily affects (if any)
    var primaryDimension: LevelDimension? {
        switch self {
        case .task, .deepWorkBlock, .writingSession, .wordCountEntry, .focusScore, .distractionEvent:
            return .cognitive
        case .content, .contentDraft, .contentPhase, .contentPerformance, .contentPublish, .clientProfile:
            return .creative
        case .hrvMeasurement, .restingHR, .sleepCycle, .sleepConsistency,
             .readinessScore, .workoutSession, .mealLog, .breathingSession,
             .bloodOxygen, .bodyTemperature:
            return .physiological
        case .scheduleBlock, .routineDefinition:
            return .behavioral
        case .research, .connection, .semanticCluster, .connectionLink, .autoLinkSuggestion, .insightExtraction:
            return .knowledge
        case .journalEntry, .journalInsight, .analysisChunk, .emotionalState, .clarityScore:
            return .reflection
        default:
            return nil
        }
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        // Core
        case .idea: return "Idea"
        case .task: return "Task"
        case .project: return "Project"
        case .content: return "Content"
        case .research: return "Research"
        case .connection: return "Connection"
        case .journalEntry: return "Journal Entry"
        case .calendarEvent: return "Calendar Event"
        case .scheduleBlock: return "Schedule Block"
        case .uncommittedItem: return "Uncommitted Item"
        // Leveling
        case .xpEvent: return "XP Event"
        case .levelUpdate: return "Level Update"
        case .streakEvent: return "Streak Event"
        case .badgeUnlocked: return "Badge Unlocked"
        case .dimensionSnapshot: return "Dimension Snapshot"
        // Physiology
        case .hrvMeasurement, .hrvReading: return "HRV Measurement"
        case .restingHR: return "Resting Heart Rate"
        case .sleepCycle, .sleepRecord: return "Sleep Cycle"
        case .sleepConsistency: return "Sleep Consistency"
        case .readinessScore, .recoveryScore: return "Readiness Score"
        case .workoutSession, .workout: return "Workout Session"
        case .mealLog: return "Meal Log"
        case .breathingSession: return "Breathing Session"
        case .bloodOxygen: return "Blood Oxygen"
        case .bodyTemperature: return "Body Temperature"
        case .activityRing: return "Activity Ring"
        // Leveling aliases
        case .badge: return "Badge"
        // Cognitive
        case .deepWorkBlock: return "Deep Work Block"
        case .writingSession: return "Writing Session"
        case .wordCountEntry: return "Word Count Entry"
        case .focusScore: return "Focus Score"
        case .distractionEvent: return "Distraction Event"
        // Content Pipeline
        case .contentDraft: return "Content Draft"
        case .contentPhase: return "Content Phase"
        case .contentPerformance: return "Content Performance"
        case .contentPublish: return "Content Publish"
        case .clientProfile: return "Client Profile"
        // Knowledge
        case .semanticCluster: return "Semantic Cluster"
        case .connectionLink: return "Connection Link"
        case .autoLinkSuggestion: return "Auto Link Suggestion"
        case .insightExtraction: return "Insight Extraction"
        // Reflection
        case .journalInsight: return "Journal Insight"
        case .analysisChunk: return "Analysis Chunk"
        case .emotionalState: return "Emotional State"
        case .clarityScore: return "Clarity Score"
        // System
        case .dailySummary: return "Daily Summary"
        case .weeklySummary: return "Weekly Summary"
        case .syncEvent: return "Sync Event"
        case .systemEvent: return "System Event"
        case .userPreference: return "User Preference"
        case .routineDefinition: return "Routine Definition"
        // Sanctuary
        case .correlationInsight: return "Correlation Insight"
        case .causalityComputation: return "Causality Computation"
        case .semanticExtraction: return "Semantic Extraction"
        case .sanctuarySnapshot: return "Sanctuary Snapshot"
        case .livingInsight: return "Living Insight"
        case .syncState: return "Sync State"
        // Thinkspace
        case .note: return "Note"
        case .thinkspace: return "Thinkspace"
        // Planning
        case .objective: return "Objective"
        }
    }

    /// Plural display name for UI
    var pluralDisplayName: String {
        switch self {
        // Core
        case .idea: return "Ideas"
        case .task: return "Tasks"
        case .project: return "Projects"
        case .content: return "Content"
        case .research: return "Research"
        case .connection: return "Connections"
        case .journalEntry: return "Journal Entries"
        case .calendarEvent: return "Calendar Events"
        case .scheduleBlock: return "Schedule Blocks"
        case .uncommittedItem: return "Uncommitted Items"
        // Leveling
        case .xpEvent: return "XP Events"
        case .levelUpdate: return "Level Updates"
        case .streakEvent: return "Streak Events"
        case .badgeUnlocked: return "Badges Unlocked"
        case .dimensionSnapshot: return "Dimension Snapshots"
        // Physiology
        case .hrvMeasurement, .hrvReading: return "HRV Measurements"
        case .restingHR: return "Resting Heart Rates"
        case .sleepCycle, .sleepRecord: return "Sleep Cycles"
        case .sleepConsistency: return "Sleep Consistency Records"
        case .readinessScore, .recoveryScore: return "Readiness Scores"
        case .workoutSession, .workout: return "Workout Sessions"
        case .mealLog: return "Meal Logs"
        case .breathingSession: return "Breathing Sessions"
        case .bloodOxygen: return "Blood Oxygen Readings"
        case .bodyTemperature: return "Body Temperature Readings"
        case .activityRing: return "Activity Rings"
        // Leveling aliases
        case .badge: return "Badges"
        // Cognitive
        case .deepWorkBlock: return "Deep Work Blocks"
        case .writingSession: return "Writing Sessions"
        case .wordCountEntry: return "Word Count Entries"
        case .focusScore: return "Focus Scores"
        case .distractionEvent: return "Distraction Events"
        // Content Pipeline
        case .contentDraft: return "Content Drafts"
        case .contentPhase: return "Content Phases"
        case .contentPerformance: return "Content Performance"
        case .contentPublish: return "Content Publishes"
        case .clientProfile: return "Client Profiles"
        // Knowledge
        case .semanticCluster: return "Semantic Clusters"
        case .connectionLink: return "Connection Links"
        case .autoLinkSuggestion: return "Auto Link Suggestions"
        case .insightExtraction: return "Insight Extractions"
        // Reflection
        case .journalInsight: return "Journal Insights"
        case .analysisChunk: return "Analysis Chunks"
        case .emotionalState: return "Emotional States"
        case .clarityScore: return "Clarity Scores"
        // System
        case .dailySummary: return "Daily Summaries"
        case .weeklySummary: return "Weekly Summaries"
        case .syncEvent: return "Sync Events"
        case .systemEvent: return "System Events"
        case .userPreference: return "User Preferences"
        case .routineDefinition: return "Routine Definitions"
        // Sanctuary
        case .correlationInsight: return "Correlation Insights"
        case .causalityComputation: return "Causality Computations"
        case .semanticExtraction: return "Semantic Extractions"
        case .sanctuarySnapshot: return "Sanctuary Snapshots"
        case .livingInsight: return "Living Insights"
        case .syncState: return "Sync States"
        // Thinkspace
        case .note: return "Notes"
        case .thinkspace: return "Thinkspaces"
        // Planning
        case .objective: return "Objectives"
        }
    }

    /// SF Symbol icon for the atom type
    var iconName: String {
        switch self {
        // Core
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .project: return "folder.fill"
        case .content: return "doc.text.fill"
        case .research: return "magnifyingglass"
        case .connection: return "link"
        case .journalEntry: return "book.fill"
        case .calendarEvent: return "calendar"
        case .scheduleBlock: return "clock.fill"
        case .uncommittedItem: return "tray.fill"
        // Leveling
        case .xpEvent: return "sparkles"
        case .levelUpdate: return "arrow.up.circle.fill"
        case .streakEvent: return "flame.fill"
        case .badgeUnlocked: return "medal.fill"
        case .dimensionSnapshot: return "chart.bar.fill"
        // Physiology
        case .hrvMeasurement, .hrvReading: return "heart.text.square.fill"
        case .restingHR: return "heart.fill"
        case .sleepCycle, .sleepRecord: return "moon.zzz.fill"
        case .sleepConsistency: return "bed.double.fill"
        case .readinessScore, .recoveryScore: return "gauge.with.dots.needle.33percent"
        case .workoutSession, .workout: return "figure.run"
        case .mealLog: return "fork.knife"
        case .breathingSession: return "wind"
        case .bloodOxygen: return "drop.fill"
        case .bodyTemperature: return "thermometer"
        case .activityRing: return "circle.circle.fill"
        // Leveling alias
        case .badge: return "medal.fill"
        // Cognitive
        case .deepWorkBlock: return "brain.head.profile"
        case .writingSession: return "pencil.line"
        case .wordCountEntry: return "character.cursor.ibeam"
        case .focusScore: return "eye.fill"
        case .distractionEvent: return "exclamationmark.triangle.fill"
        // Content Pipeline
        case .contentDraft: return "doc.badge.ellipsis"
        case .contentPhase: return "arrow.right.circle.fill"
        case .contentPerformance: return "chart.line.uptrend.xyaxis"
        case .contentPublish: return "paperplane.fill"
        case .clientProfile: return "person.crop.circle.fill"
        // Knowledge
        case .semanticCluster: return "circle.hexagongrid.fill"
        case .connectionLink: return "arrow.triangle.branch"
        case .autoLinkSuggestion: return "wand.and.stars"
        case .insightExtraction: return "lightbulb.max.fill"
        // Reflection
        case .journalInsight: return "text.magnifyingglass"
        case .analysisChunk: return "doc.text.magnifyingglass"
        case .emotionalState: return "face.smiling.fill"
        case .clarityScore: return "checkmark.seal.fill"
        // System
        case .dailySummary: return "calendar.day.timeline.left"
        case .weeklySummary: return "calendar.badge.clock"
        case .syncEvent: return "arrow.triangle.2.circlepath"
        case .systemEvent: return "gear"
        case .userPreference: return "slider.horizontal.3"
        case .routineDefinition: return "repeat"
        // Sanctuary
        case .correlationInsight: return "arrow.triangle.branch"
        case .causalityComputation: return "function"
        case .semanticExtraction: return "text.viewfinder"
        case .sanctuarySnapshot: return "sparkles.rectangle.stack.fill"
        case .livingInsight: return "sparkle"
        case .syncState: return "arrow.triangle.2.circlepath.circle"
        // Thinkspace
        case .note: return "note.text"
        case .thinkspace: return "rectangle.3.group"
        // Planning
        case .objective: return "target"
        }
    }
}

// MARK: - Atom Category
/// Categories for grouping atom types
enum AtomCategory: String, Codable, CaseIterable, Sendable {
    case core           // Original entity types
    case leveling       // XP, levels, badges, streaks
    case physiology     // Health data from Apple Watch
    case cognitive      // Deep work, writing, focus
    case contentPipeline // Content creation workflow
    case knowledge      // Knowledge graph, connections
    case reflection     // Journaling, insights, emotions
    case system         // System events, sync, preferences
    case sanctuary      // Causality engine, correlations, insights

    var displayName: String {
        switch self {
        case .core: return "Core"
        case .leveling: return "Leveling"
        case .physiology: return "Physiology"
        case .cognitive: return "Cognitive"
        case .contentPipeline: return "Content Pipeline"
        case .knowledge: return "Knowledge"
        case .reflection: return "Reflection"
        case .system: return "System"
        case .sanctuary: return "Sanctuary"
        }
    }
}

// MARK: - Level Dimension
/// The six dimensions of the Cosmo Level System
public enum LevelDimension: String, Codable, CaseIterable, Sendable {
    case cognitive      // Writing, deep work, task completion
    case creative       // Content performance, reach, virality
    case physiological  // HRV, sleep, recovery
    case behavioral     // Consistency, routine adherence
    case knowledge      // Research, connections, semantic density
    case reflection     // Journaling, insights, self-awareness

    var displayName: String {
        switch self {
        case .cognitive: return "Cognitive"
        case .creative: return "Creative"
        case .physiological: return "Physiological"
        case .behavioral: return "Behavioral"
        case .knowledge: return "Knowledge"
        case .reflection: return "Reflection"
        }
    }

    var iconName: String {
        switch self {
        case .cognitive: return "brain.head.profile"
        case .creative: return "paintbrush.fill"
        case .physiological: return "heart.fill"
        case .behavioral: return "flame.fill"
        case .knowledge: return "books.vertical.fill"
        case .reflection: return "person.fill.questionmark"
        }
    }

    /// Color for dimension visualization (hex)
    var colorHex: String {
        switch self {
        case .cognitive: return "#6366F1"      // Indigo
        case .creative: return "#EC4899"        // Pink
        case .physiological: return "#EF4444"   // Red
        case .behavioral: return "#F97316"      // Orange
        case .knowledge: return "#22C55E"       // Green
        case .reflection: return "#8B5CF6"      // Purple
        }
    }
}

// MARK: - Atom Link Type
/// Enumeration of all valid link types for type safety
enum AtomLinkType: String, Codable, CaseIterable, Sendable {
    // MARK: - Core Links (Original)
    case project = "project"
    case parentIdea = "parent_idea"
    case originIdea = "origin_idea"
    case connection = "connection"
    case promotedTo = "promoted_to"
    case recurrenceParent = "recurrence_parent"
    case related = "related"

    // MARK: - Leveling & XP Links
    case xpSource = "xp_source"                 // What generated this XP
    case badgeTrigger = "badge_trigger"         // What triggered badge unlock
    case streakSource = "streak_source"         // What activity counts for streak
    case levelTrigger = "level_trigger"         // What caused level up

    // MARK: - Physiology Links
    case sleepToReadiness = "sleep_to_readiness"           // Sleep cycle -> readiness
    case hrvToReadiness = "hrv_to_readiness"               // HRV -> readiness
    case workoutToRecovery = "workout_to_recovery"         // Workout -> HRV recovery
    case mealToEnergy = "meal_to_energy"                   // Meal -> focus score
    case breathingToHrv = "breathing_to_hrv"               // Breathing -> HRV
    case sleepToFocus = "sleep_to_focus"                   // Sleep -> focus score

    // MARK: - Cognitive Links
    case deepWorkTask = "deep_work_task"                   // Deep work -> task completed
    case deepWorkProject = "deep_work_project"             // Deep work -> project worked on
    case writingToContent = "writing_to_content"           // Writing session -> content
    case focusToDeepWork = "focus_to_deep_work"           // Focus score -> deep work block
    case distractionDuring = "distraction_during"          // Distraction -> what was interrupted

    // MARK: - Content Pipeline Links
    case draftToContent = "draft_to_content"               // Draft -> parent content
    case phaseTransition = "phase_transition"              // Phase -> previous phase
    case publishSource = "publish_source"                  // Publish -> content published
    case performanceOf = "performance_of"                  // Performance -> published content
    case clientContent = "client_content"                  // Client -> content for them
    case contentToClient = "content_to_client"             // Content -> client it's for

    // MARK: - Knowledge Graph Links
    case semanticMember = "semantic_member"                // Cluster -> member atoms
    case semanticCluster = "semantic_cluster"              // Atom -> cluster it belongs to
    case autoLinkSource = "auto_link_source"               // Link suggestion -> source
    case autoLinkTarget = "auto_link_target"               // Link suggestion -> target
    case insightSource = "insight_source"                  // Insight -> source atom
    case conceptLink = "concept_link"                      // Concept -> related concept

    // MARK: - Reflection Links
    case journalSource = "journal_source"                  // Insight -> source journal
    case analysisSource = "analysis_source"                // Analysis -> source atom
    case emotionalContext = "emotional_context"            // Emotional state -> context atom
    case clarityOf = "clarity_of"                          // Clarity score -> journal
    case reflectionSession = "reflection_session"          // Entry -> session it was part of

    // MARK: - System Links
    case summaryIncludes = "summary_includes"              // Daily/weekly summary -> included atoms
    case syncedWith = "synced_with"                        // Local atom -> cloud version
    case preferenceFor = "preference_for"                  // Preference -> what it configures
    case routineInstance = "routine_instance"              // Schedule block -> routine definition

    // MARK: - Bidirectional Links (for knowledge graph traversal)
    case linksTo = "links_to"                              // Generic forward link
    case linkedFrom = "linked_from"                        // Generic back link

    // MARK: - Sanctuary / Causality Links
    case correlationSource = "correlation_source"          // Insight -> source metric atoms
    case correlationTarget = "correlation_target"          // Insight -> target metric atoms
    case semanticSource = "semantic_source"                // Semantic extraction -> source journal
    case computationResult = "computation_result"          // Computation -> resulting insights
    case snapshotData = "snapshot_data"                    // Snapshot -> included data atoms

    /// Whether this is a single-value relationship (only one link of this type allowed)
    var isSingleValue: Bool {
        switch self {
        case .project, .parentIdea, .originIdea, .connection, .recurrenceParent,
             .draftToContent, .publishSource, .clarityOf, .journalSource,
             .sleepToReadiness, .deepWorkProject, .routineInstance:
            return true
        default:
            return false
        }
    }

    /// The inverse link type for bidirectional relationships
    var inverseType: AtomLinkType? {
        switch self {
        case .linksTo: return .linkedFrom
        case .linkedFrom: return .linksTo
        case .autoLinkSource: return .autoLinkTarget
        case .autoLinkTarget: return .autoLinkSource
        case .semanticMember: return .semanticCluster
        case .semanticCluster: return .semanticMember
        case .clientContent: return .contentToClient
        case .contentToClient: return .clientContent
        default: return nil
        }
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .project: return "Project"
        case .parentIdea: return "Parent Idea"
        case .originIdea: return "Origin Idea"
        case .connection: return "Connection"
        case .promotedTo: return "Promoted To"
        case .recurrenceParent: return "Recurrence Parent"
        case .related: return "Related"
        case .xpSource: return "XP Source"
        case .badgeTrigger: return "Badge Trigger"
        case .streakSource: return "Streak Source"
        case .levelTrigger: return "Level Trigger"
        case .sleepToReadiness: return "Sleep to Readiness"
        case .hrvToReadiness: return "HRV to Readiness"
        case .workoutToRecovery: return "Workout to Recovery"
        case .mealToEnergy: return "Meal to Energy"
        case .breathingToHrv: return "Breathing to HRV"
        case .sleepToFocus: return "Sleep to Focus"
        case .deepWorkTask: return "Deep Work Task"
        case .deepWorkProject: return "Deep Work Project"
        case .writingToContent: return "Writing to Content"
        case .focusToDeepWork: return "Focus to Deep Work"
        case .distractionDuring: return "Distraction During"
        case .draftToContent: return "Draft to Content"
        case .phaseTransition: return "Phase Transition"
        case .publishSource: return "Publish Source"
        case .performanceOf: return "Performance Of"
        case .clientContent: return "Client Content"
        case .contentToClient: return "Content to Client"
        case .semanticMember: return "Semantic Member"
        case .semanticCluster: return "Semantic Cluster"
        case .autoLinkSource: return "Auto Link Source"
        case .autoLinkTarget: return "Auto Link Target"
        case .insightSource: return "Insight Source"
        case .conceptLink: return "Concept Link"
        case .journalSource: return "Journal Source"
        case .analysisSource: return "Analysis Source"
        case .emotionalContext: return "Emotional Context"
        case .clarityOf: return "Clarity Of"
        case .reflectionSession: return "Reflection Session"
        case .summaryIncludes: return "Summary Includes"
        case .syncedWith: return "Synced With"
        case .preferenceFor: return "Preference For"
        case .routineInstance: return "Routine Instance"
        case .linksTo: return "Links To"
        case .linkedFrom: return "Linked From"
        // Sanctuary
        case .correlationSource: return "Correlation Source"
        case .correlationTarget: return "Correlation Target"
        case .semanticSource: return "Semantic Source"
        case .computationResult: return "Computation Result"
        case .snapshotData: return "Snapshot Data"
        }
    }
}

// MARK: - Atom Link
/// Represents a relationship between atoms
public struct AtomLink: Codable, Equatable, Sendable, Hashable {
    public let type: String       // "project", "parent_idea", "origin_idea", "connection", etc.
    public let uuid: String       // Target atom UUID
    public let entityType: String? // Optional: the AtomType of the target (for polymorphic links)
    public let metadata: String?   // Optional: additional link metadata (JSON)

    public init(type: String, uuid: String, entityType: String? = nil, metadata: String? = nil) {
        self.type = type
        self.uuid = uuid
        self.entityType = entityType
        self.metadata = metadata
    }

    /// Initialize with typed link type
    init(linkType: AtomLinkType, uuid: String, entityType: AtomType? = nil, metadata: String? = nil) {
        self.type = linkType.rawValue
        self.uuid = uuid
        self.entityType = entityType?.rawValue
        self.metadata = metadata
    }

    /// Get the typed link type (if valid)
    var linkType: AtomLinkType? {
        AtomLinkType(rawValue: type)
    }

    // MARK: - Core Link Factories (Original)

    static func project(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .project, uuid: uuid, entityType: .project)
    }

    static func parentIdea(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .parentIdea, uuid: uuid, entityType: .idea)
    }

    static func originIdea(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .originIdea, uuid: uuid, entityType: .idea)
    }

    static func connection(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .connection, uuid: uuid, entityType: .connection)
    }

    static func promotedTo(_ uuid: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .promotedTo, uuid: uuid, entityType: entityType)
    }

    /// Backward-compatible overload accepting String entityType
    static func promotedTo(_ uuid: String, entityType: String) -> AtomLink {
        AtomLink(type: AtomLinkType.promotedTo.rawValue, uuid: uuid, entityType: entityType)
    }

    static func recurrenceParent(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .recurrenceParent, uuid: uuid)
    }

    static func related(_ uuid: String, entityType: AtomType? = nil) -> AtomLink {
        AtomLink(linkType: .related, uuid: uuid, entityType: entityType)
    }

    // MARK: - Leveling & XP Link Factories

    static func xpSource(_ uuid: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .xpSource, uuid: uuid, entityType: entityType)
    }

    static func badgeTrigger(_ uuid: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .badgeTrigger, uuid: uuid, entityType: entityType)
    }

    static func streakSource(_ uuid: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .streakSource, uuid: uuid, entityType: entityType)
    }

    static func levelTrigger(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .levelTrigger, uuid: uuid, entityType: .xpEvent)
    }

    // MARK: - Physiology Link Factories

    static func sleepToReadiness(_ sleepUUID: String) -> AtomLink {
        AtomLink(linkType: .sleepToReadiness, uuid: sleepUUID, entityType: .sleepCycle)
    }

    static func hrvToReadiness(_ hrvUUID: String) -> AtomLink {
        AtomLink(linkType: .hrvToReadiness, uuid: hrvUUID, entityType: .hrvMeasurement)
    }

    static func workoutToRecovery(_ workoutUUID: String) -> AtomLink {
        AtomLink(linkType: .workoutToRecovery, uuid: workoutUUID, entityType: .workoutSession)
    }

    static func mealToEnergy(_ mealUUID: String) -> AtomLink {
        AtomLink(linkType: .mealToEnergy, uuid: mealUUID, entityType: .mealLog)
    }

    static func breathingToHrv(_ breathingUUID: String) -> AtomLink {
        AtomLink(linkType: .breathingToHrv, uuid: breathingUUID, entityType: .breathingSession)
    }

    static func sleepToFocus(_ sleepUUID: String) -> AtomLink {
        AtomLink(linkType: .sleepToFocus, uuid: sleepUUID, entityType: .sleepCycle)
    }

    // MARK: - Cognitive Link Factories

    static func deepWorkTask(_ taskUUID: String) -> AtomLink {
        AtomLink(linkType: .deepWorkTask, uuid: taskUUID, entityType: .task)
    }

    static func deepWorkProject(_ projectUUID: String) -> AtomLink {
        AtomLink(linkType: .deepWorkProject, uuid: projectUUID, entityType: .project)
    }

    static func writingToContent(_ contentUUID: String) -> AtomLink {
        AtomLink(linkType: .writingToContent, uuid: contentUUID, entityType: .content)
    }

    static func focusToDeepWork(_ deepWorkUUID: String) -> AtomLink {
        AtomLink(linkType: .focusToDeepWork, uuid: deepWorkUUID, entityType: .deepWorkBlock)
    }

    static func distractionDuring(_ activityUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .distractionDuring, uuid: activityUUID, entityType: entityType)
    }

    // MARK: - Content Pipeline Link Factories

    static func draftToContent(_ contentUUID: String) -> AtomLink {
        AtomLink(linkType: .draftToContent, uuid: contentUUID, entityType: .content)
    }

    static func phaseTransition(_ previousPhaseUUID: String) -> AtomLink {
        AtomLink(linkType: .phaseTransition, uuid: previousPhaseUUID, entityType: .contentPhase)
    }

    static func publishSource(_ contentUUID: String) -> AtomLink {
        AtomLink(linkType: .publishSource, uuid: contentUUID, entityType: .content)
    }

    static func performanceOf(_ publishUUID: String) -> AtomLink {
        AtomLink(linkType: .performanceOf, uuid: publishUUID, entityType: .contentPublish)
    }

    static func clientContent(_ contentUUID: String) -> AtomLink {
        AtomLink(linkType: .clientContent, uuid: contentUUID, entityType: .content)
    }

    static func contentToClient(_ clientUUID: String) -> AtomLink {
        AtomLink(linkType: .contentToClient, uuid: clientUUID, entityType: .clientProfile)
    }

    // MARK: - Knowledge Graph Link Factories

    static func semanticMember(_ atomUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .semanticMember, uuid: atomUUID, entityType: entityType)
    }

    static func semanticCluster(_ clusterUUID: String) -> AtomLink {
        AtomLink(linkType: .semanticCluster, uuid: clusterUUID, entityType: .semanticCluster)
    }

    static func autoLinkSource(_ sourceUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .autoLinkSource, uuid: sourceUUID, entityType: entityType)
    }

    static func autoLinkTarget(_ targetUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .autoLinkTarget, uuid: targetUUID, entityType: entityType)
    }

    static func insightSource(_ sourceUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .insightSource, uuid: sourceUUID, entityType: entityType)
    }

    static func conceptLink(_ conceptUUID: String) -> AtomLink {
        AtomLink(linkType: .conceptLink, uuid: conceptUUID, entityType: .connection)
    }

    // MARK: - Reflection Link Factories

    static func journalSource(_ journalUUID: String) -> AtomLink {
        AtomLink(linkType: .journalSource, uuid: journalUUID, entityType: .journalEntry)
    }

    static func analysisSource(_ sourceUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .analysisSource, uuid: sourceUUID, entityType: entityType)
    }

    static func emotionalContext(_ contextUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .emotionalContext, uuid: contextUUID, entityType: entityType)
    }

    static func clarityOf(_ journalUUID: String) -> AtomLink {
        AtomLink(linkType: .clarityOf, uuid: journalUUID, entityType: .journalEntry)
    }

    static func reflectionSession(_ sessionUUID: String) -> AtomLink {
        AtomLink(linkType: .reflectionSession, uuid: sessionUUID)
    }

    // MARK: - System Link Factories

    static func summaryIncludes(_ atomUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .summaryIncludes, uuid: atomUUID, entityType: entityType)
    }

    static func syncedWith(_ cloudUUID: String) -> AtomLink {
        AtomLink(linkType: .syncedWith, uuid: cloudUUID)
    }

    static func preferenceFor(_ configuredUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .preferenceFor, uuid: configuredUUID, entityType: entityType)
    }

    static func routineInstance(_ routineUUID: String) -> AtomLink {
        AtomLink(linkType: .routineInstance, uuid: routineUUID, entityType: .routineDefinition)
    }

    // MARK: - Bidirectional Link Factories

    static func linksTo(_ targetUUID: String, entityType: AtomType? = nil) -> AtomLink {
        AtomLink(linkType: .linksTo, uuid: targetUUID, entityType: entityType)
    }

    static func linkedFrom(_ sourceUUID: String, entityType: AtomType? = nil) -> AtomLink {
        AtomLink(linkType: .linkedFrom, uuid: sourceUUID, entityType: entityType)
    }

    // MARK: - Sanctuary / Causality Link Factories

    static func correlationSource(_ sourceUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .correlationSource, uuid: sourceUUID, entityType: entityType)
    }

    static func correlationTarget(_ targetUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .correlationTarget, uuid: targetUUID, entityType: entityType)
    }

    static func semanticSource(_ journalUUID: String) -> AtomLink {
        AtomLink(linkType: .semanticSource, uuid: journalUUID, entityType: .journalEntry)
    }

    static func computationResult(_ insightUUID: String) -> AtomLink {
        AtomLink(linkType: .computationResult, uuid: insightUUID, entityType: .correlationInsight)
    }

    static func snapshotData(_ atomUUID: String, entityType: AtomType) -> AtomLink {
        AtomLink(linkType: .snapshotData, uuid: atomUUID, entityType: entityType)
    }

    // MARK: - Utility Methods

    /// Create the inverse link for bidirectional relationships
    func inverseLink(forAtom atomUUID: String, entityType: AtomType) -> AtomLink? {
        guard let linkType = linkType,
              let inverseType = linkType.inverseType else {
            return nil
        }
        return AtomLink(linkType: inverseType, uuid: atomUUID, entityType: entityType)
    }

    /// Check if this is a single-value link type
    var isSingleValue: Bool {
        linkType?.isSingleValue ?? false
    }
}

// MARK: - Atom Model
/// The unified entity model for all CosmoOS data
public struct Atom: Codable, FetchableRecord, PersistableRecord, Syncable, Identifiable, Equatable, Sendable {
    // MARK: - Core Identity
    /// Database row ID (temporary, for legacy compatibility during migration)
    public var id: Int64?

    /// Canonical unique identifier - THE primary key moving forward
    public var uuid: String

    /// Entity type discriminator
    public var type: AtomType

    // MARK: - Common Fields (denormalized for query performance)
    /// Primary title/name
    public var title: String?

    /// Main body content (description, notes, etc.)
    public var body: String?

    // MARK: - Flexible Storage (JSON columns)
    /// Type-specific structured data (checklist, mental_model, theme, recurrence, etc.)
    public var structured: String?

    /// Auxiliary metadata (tags, priority, status, color, flags, etc.)
    public var metadata: String?

    /// Relationships to other atoms (JSON array of AtomLink)
    public var links: String?

    // MARK: - Timestamps
    public var createdAt: String
    public var updatedAt: String

    // MARK: - Soft Delete
    public var isDeleted: Bool

    // MARK: - Sync Tracking
    public var localVersion: Int64
    public var serverVersion: Int64
    public var syncVersion: Int64

    // MARK: - GRDB Table Configuration
    public static let databaseTableName = "atoms"

    enum CodingKeys: String, ColumnExpression, CodingKey {
        case id, uuid, type, title, body
        case structured, metadata, links
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case localVersion = "_local_version"
        case serverVersion = "_server_version"
        case syncVersion = "_sync_version"
    }

    // MARK: - Syncable Protocol
    func getUUID() -> String? {
        return uuid
    }
}

// MARK: - Atom Factory
extension Atom {
    /// Create a new Atom with sensible defaults
    static func new(
        type: AtomType,
        title: String? = nil,
        body: String? = nil,
        structured: String? = nil,
        metadata: String? = nil,
        links: [AtomLink]? = nil
    ) -> Atom {
        let now = ISO8601DateFormatter().string(from: Date())
        let linksJson: String?
        if let links = links, !links.isEmpty {
            linksJson = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
        } else {
            linksJson = nil
        }

        return Atom(
            id: nil,
            uuid: UUID().uuidString,
            type: type,
            title: title,
            body: body,
            structured: structured,
            metadata: metadata,
            links: linksJson,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0
        )
    }
}

// MARK: - JSON Field Accessors
extension Atom {
    // MARK: - Links

    /// Parsed links array
    var linksList: [AtomLink] {
        guard let links = links,
              let data = links.data(using: .utf8),
              let array = try? JSONDecoder().decode([AtomLink].self, from: data) else {
            return []
        }
        return array
    }

    /// Get links of a specific type (string-based)
    func links(ofType type: String) -> [AtomLink] {
        linksList.filter { $0.type == type }
    }

    /// Get links of a specific typed link type
    func links(ofType type: AtomLinkType) -> [AtomLink] {
        linksList.filter { $0.type == type.rawValue }
    }

    /// Get the first link of a type (for single-value relationships like project)
    func link(ofType type: String) -> AtomLink? {
        linksList.first { $0.type == type }
    }

    /// Get the first link of a typed link type
    func link(ofType type: AtomLinkType) -> AtomLink? {
        linksList.first { $0.type == type.rawValue }
    }

    /// Check if a link of a specific type exists
    func hasLink(ofType type: AtomLinkType) -> Bool {
        linksList.contains { $0.type == type.rawValue }
    }

    /// Get all links to atoms of a specific entity type
    func links(toEntityType entityType: AtomType) -> [AtomLink] {
        linksList.filter { $0.entityType == entityType.rawValue }
    }

    /// Create a copy with updated links
    func withLinks(_ links: [AtomLink]) -> Atom {
        var copy = self
        if links.isEmpty {
            copy.links = nil
        } else {
            copy.links = try? String(data: JSONEncoder().encode(links), encoding: .utf8)
        }
        return copy
    }

    /// Add a link (uses typed system to determine if single-value)
    func addingLink(_ link: AtomLink) -> Atom {
        var current = linksList
        // Remove existing link of same type if it's a single-value relationship
        if link.isSingleValue {
            current.removeAll { $0.type == link.type }
        }
        current.append(link)
        return withLinks(current)
    }

    /// Add multiple links at once
    func addingLinks(_ newLinks: [AtomLink]) -> Atom {
        var current = linksList
        for link in newLinks {
            if link.isSingleValue {
                current.removeAll { $0.type == link.type }
            }
            current.append(link)
        }
        return withLinks(current)
    }

    /// Add a link with automatic inverse link creation (for bidirectional relationships)
    /// Returns both this atom with the new link, and the inverse link to add to the target atom
    func addingBidirectionalLink(_ link: AtomLink) -> (atom: Atom, inverseLink: AtomLink?) {
        let updatedAtom = addingLink(link)
        let inverse = link.inverseLink(forAtom: self.uuid, entityType: self.type)
        return (updatedAtom, inverse)
    }

    /// Remove links of a type (string-based)
    func removingLinks(ofType type: String) -> Atom {
        let filtered = linksList.filter { $0.type != type }
        return withLinks(filtered)
    }

    /// Remove links of a typed link type
    func removingLinks(ofType type: AtomLinkType) -> Atom {
        let filtered = linksList.filter { $0.type != type.rawValue }
        return withLinks(filtered)
    }

    /// Remove a specific link by UUID
    func removingLink(toUUID uuid: String) -> Atom {
        let filtered = linksList.filter { $0.uuid != uuid }
        return withLinks(filtered)
    }

    /// Remove a specific link by type and UUID
    func removingLink(ofType type: AtomLinkType, toUUID uuid: String) -> Atom {
        let filtered = linksList.filter { !($0.type == type.rawValue && $0.uuid == uuid) }
        return withLinks(filtered)
    }

    /// Replace a link of a specific type with a new one
    func replacingLink(ofType type: AtomLinkType, with newLink: AtomLink) -> Atom {
        var current = linksList.filter { $0.type != type.rawValue }
        current.append(newLink)
        return withLinks(current)
    }

    /// Get all unique link types present on this atom
    var linkTypes: Set<AtomLinkType> {
        Set(linksList.compactMap { $0.linkType })
    }

    /// Get a dictionary of links grouped by type
    var linksByType: [AtomLinkType: [AtomLink]] {
        var result: [AtomLinkType: [AtomLink]] = [:]
        for link in linksList {
            if let linkType = link.linkType {
                result[linkType, default: []].append(link)
            }
        }
        return result
    }

    // MARK: - Structured Data

    /// Get structured data as decoded type
    func structuredData<T: Decodable>(as type: T.Type) -> T? {
        guard let structured = structured,
              let data = structured.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Create a copy with encoded structured data
    func withStructured<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        copy.structured = try? String(data: JSONEncoder().encode(value), encoding: .utf8)
        return copy
    }

    // MARK: - Metadata

    /// Get metadata as decoded type
    func metadataValue<T: Decodable>(as type: T.Type) -> T? {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Create a copy with encoded metadata
    func withMetadata<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        copy.metadata = try? String(data: JSONEncoder().encode(value), encoding: .utf8)
        return copy
    }

    /// Get metadata as dictionary for flexible access
    var metadataDict: [String: Any]? {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}

// MARK: - Common Metadata Types

/// Metadata for idea atoms
struct IdeaMetadata: Codable, Sendable {
    var tags: [String]?
    var priority: String?
    var isPinned: Bool?
    var pinnedAt: String?
}

/// Metadata for task atoms
struct TaskMetadata: Codable, Sendable {
    var status: String?
    var priority: String?
    var color: String?
    var dueDate: String?
    var startTime: String?
    var endTime: String?
    var durationMinutes: Int?
    var focusDate: String?
    var isUnscheduled: Bool?
    var isCompleted: Bool?
    var completedAt: String?
    var description: String?
    var checklist: String?
    var recurrence: String?
}

/// Metadata for project atoms
struct ProjectMetadata: Codable, Sendable {
    var color: String?
    var status: String?
    var priority: String?
    var tags: [String]?
    var rootThinkspaceUuid: String?  // UUID of auto-created root ThinkSpace
}

/// Metadata for content atoms
struct ContentMetadata: Codable, Sendable {
    var contentType: String?
    var status: String?
    var scheduledAt: String?
    var lastOpenedAt: String?
    var tags: [String]?
}

/// Metadata for research atoms
struct ResearchMetadata: Codable, Sendable {
    var url: String?
    var summary: String?
    var researchType: String?
    var processingStatus: String?
    var thumbnailUrl: String?
    var query: String?
    var findings: String?
    var tags: [String]?
    var personalNotes: String?
    // Swipe file fields
    var hook: String?
    var emotionTone: String?
    var structureType: String?
    var isSwipeFile: Bool?
    var contentSource: String?
}

/// Metadata for journal entry atoms
struct JournalEntryMetadata: Codable, Sendable {
    var source: String?
    var status: String?
    var errorMessage: String?
    var mood: MoodCategory?
    var topics: [String]?
    var sentiment: Double?
}

/// Metadata for schedule block atoms
struct ScheduleBlockMetadata: Codable, Sendable {
    var blockType: String?
    var status: String?
    var isCompleted: Bool?
    var completedAt: String?
    var startTime: String?
    var endTime: String?
    var durationMinutes: Int?
    var isAllDay: Bool?
    var priority: String?
    var color: String?
    var tags: [String]?
    var reminderMinutes: Int?
    var location: String?
    var originType: String?
    var originEntityType: String?
}

/// Metadata for uncommitted item atoms
struct UncommittedItemMetadata: Codable, Sendable {
    var captureMethod: String?
    var assignmentStatus: String?
    var inferredProject: String?
    var inferredProjectConfidence: Double?
    var inferredType: String?
    var isArchived: Bool?
    var expiresAt: String?
}

/// Metadata for calendar event atoms
struct CalendarEventMetadata: Codable, Sendable {
    var calendarType: String?
    var startTime: String?
    var endTime: String?
    var isAllDay: Bool?
    var location: String?
    var color: String?
    var reminderMinutes: Int?
    var isCompleted: Bool?
    var completedAt: String?
    var isUnscheduled: Bool?
    var reminderDueAt: String?
}

// MARK: - Common Structured Data Types

/// Structured data for ideas/content with focus blocks
struct FocusBlocksStructured: Codable, Sendable {
    var focusBlocks: String? // JSON string of focus blocks
}

/// Structured data for tasks
struct TaskStructured: Codable, Sendable {
    var checklist: String? // JSON array
    var recurrence: String? // JSON object
}

/// Structured data for content
struct ContentStructured: Codable, Sendable {
    var theme: String? // JSON object
    var focusBlocks: String? // JSON string
}

/// Structured data for research
struct ResearchStructured: Codable, Sendable {
    var autoMetadata: String? // ResearchRichContent JSON
    var focusBlocks: String? // JSON string
}

/// Structured data for connections (mental model)
struct ConnectionStructured: Codable, Sendable {
    var idea: String?
    var personalBelief: String?
    var goal: String?
    var problems: String?
    var benefit: String?
    var beliefsObjections: String?
    var example: String?
    var process: String?
    var notes: String?
    var referencesData: String? // JSON array
    var sourceText: String? // JSON
    var extractionConfidence: Double?
}

/// Structured data for journal entries
struct JournalEntryStructured: Codable, Sendable {
    var aiResponse: String?
    var linkedTasks: String? // JSON array
    var linkedIdeas: String? // JSON array
    var linkedContent: String? // JSON array
}

/// Structured data for schedule blocks
struct ScheduleBlockStructured: Codable, Sendable {
    var notes: String?
    var checklist: String? // JSON array
    var recurrence: String? // JSON object
    var focusSession: String? // JSON object
    var focusSessionData: String? // JSON object
    var semanticLinks: String? // JSON object
}

/// Structured data for calendar events
struct CalendarEventStructured: Codable, Sendable {
    var recurrence: String? // JSON object
    var linkedEntities: String? // JSON array
}

// MARK: - HasUUID Protocol Conformance
extension Atom: HasUUID {}

// MARK: - Assignment Status (for Uncommitted Items)

/// Assignment status for uncommitted items
enum AssignmentStatus: String, Codable, CaseIterable, Sendable {
    case assigned = "assigned"
    case suggested = "suggested"
    case unassigned = "unassigned"
}

// MARK: - Capture Method (for Uncommitted Items)

/// How an uncommitted item was captured
enum CaptureMethod: String, Codable, CaseIterable, Sendable {
    case keyboard = "keyboard"
    case voice = "voice"
    case paste = "paste"
    case quickCapture = "quick_capture"
    case api = "api"
}
