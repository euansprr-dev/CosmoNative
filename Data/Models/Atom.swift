// CosmoOS/Data/Models/Atom.swift
// Unified Atom model - the single foundational entity for all CosmoOS data
// Replaces fragmented tables (ideas, tasks, content, etc.) with one normalized structure

import GRDB
import Foundation
import SwiftUI

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

    // MARK: - Swipe Intelligence Taxonomy
    case creator                                        // Content creator profiles (for attribution)
    case taxonomyValue = "taxonomy_value"               // User-defined taxonomy dimension values

    // MARK: - Category Classification

    /// Category for grouping atom types
    var category: AtomCategory {
        switch self {
        case .idea, .task, .project, .content, .research, .connection,
             .journalEntry, .calendarEvent, .scheduleBlock, .uncommittedItem,
             .note, .objective, .creator, .taxonomyValue:
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
        // Swipe Intelligence Taxonomy
        case .creator: return "Creator"
        case .taxonomyValue: return "Taxonomy Value"
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
        // Swipe Intelligence Taxonomy
        case .creator: return "Creators"
        case .taxonomyValue: return "Taxonomy Values"
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
        // Swipe Intelligence Taxonomy
        case .creator: return "person.crop.rectangle.fill"
        case .taxonomyValue: return "tag.fill"
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

    // MARK: - IdeaForge Links
    case ideaToSwipe = "idea_to_swipe"                     // Idea matched/inspired by a swipe
    case swipeToIdea = "swipe_to_idea"                     // Swipe linked to an idea
    case ideaToContent = "idea_to_content"                 // Idea promoted to content
    case contentToIdea = "content_to_idea"                 // Content originated from idea
    case ideaToClient = "idea_to_client"                   // Idea assigned to client
    case clientToIdea = "client_to_idea"                   // Client's assigned ideas

    // MARK: - Swipe Intelligence Links
    case swipeToCreator = "swipe_to_creator"               // Swipe attributed to a creator
    case creatorToSwipe = "creator_to_swipe"               // Creator's swipe files

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
        case .ideaToSwipe: return .swipeToIdea
        case .swipeToIdea: return .ideaToSwipe
        case .ideaToContent: return .contentToIdea
        case .contentToIdea: return .ideaToContent
        case .ideaToClient: return .clientToIdea
        case .clientToIdea: return .ideaToClient
        case .swipeToCreator: return .creatorToSwipe
        case .creatorToSwipe: return .swipeToCreator
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
        // IdeaForge
        case .ideaToSwipe: return "Idea to Swipe"
        case .swipeToIdea: return "Swipe to Idea"
        case .ideaToContent: return "Idea to Content"
        case .contentToIdea: return "Content to Idea"
        case .ideaToClient: return "Idea to Client"
        case .clientToIdea: return "Client to Idea"
        // Swipe Intelligence
        case .swipeToCreator: return "Swipe to Creator"
        case .creatorToSwipe: return "Creator to Swipe"
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

    // MARK: - IdeaForge Link Factories

    static func ideaToSwipe(_ swipeUUID: String) -> AtomLink {
        AtomLink(linkType: .ideaToSwipe, uuid: swipeUUID, entityType: .research)
    }

    static func swipeToIdea(_ ideaUUID: String) -> AtomLink {
        AtomLink(linkType: .swipeToIdea, uuid: ideaUUID, entityType: .idea)
    }

    static func ideaToContent(_ contentUUID: String) -> AtomLink {
        AtomLink(linkType: .ideaToContent, uuid: contentUUID, entityType: .content)
    }

    static func contentToIdea(_ ideaUUID: String) -> AtomLink {
        AtomLink(linkType: .contentToIdea, uuid: ideaUUID, entityType: .idea)
    }

    static func ideaToClient(_ clientUUID: String) -> AtomLink {
        AtomLink(linkType: .ideaToClient, uuid: clientUUID, entityType: .clientProfile)
    }

    static func clientToIdea(_ ideaUUID: String) -> AtomLink {
        AtomLink(linkType: .clientToIdea, uuid: ideaUUID, entityType: .idea)
    }

    // MARK: - Swipe Intelligence Link Factories

    static func swipeToCreator(_ creatorUUID: String) -> AtomLink {
        AtomLink(linkType: .swipeToCreator, uuid: creatorUUID, entityType: .creator)
    }

    static func creatorToSwipe(_ swipeUUID: String) -> AtomLink {
        AtomLink(linkType: .creatorToSwipe, uuid: swipeUUID, entityType: .research)
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

// MARK: - Focus Floating Block

/// A floating block stored in an atom's metadata, so it travels with the atom
struct FocusFloatingBlock: Codable, Sendable, Identifiable, Equatable {
    var id: String  // UUID string
    var linkedAtomUUID: String  // The atom being displayed
    var linkedAtomType: String  // AtomType raw value
    var title: String  // Cached title for display
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var zIndex: Int
    var displayState: String  // "collapsed", "standard", "expanded"
    var addedAt: String  // ISO8601 date string

    init(
        id: String = UUID().uuidString,
        linkedAtomUUID: String,
        linkedAtomType: String,
        title: String = "Untitled",
        positionX: Double = 200,
        positionY: Double = 200,
        width: Double = 280,
        height: Double = 140,
        zIndex: Int = 0,
        displayState: String = "standard",
        addedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.linkedAtomUUID = linkedAtomUUID
        self.linkedAtomType = linkedAtomType
        self.title = title
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.zIndex = zIndex
        self.displayState = displayState
        self.addedAt = addedAt
    }

    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    var atomType: AtomType? {
        AtomType(rawValue: linkedAtomType)
    }
}

/// Metadata wrapper for storing floating blocks in an atom
struct FocusFloatingBlocksMetadata: Codable, Sendable {
    var floatingBlocks: [FocusFloatingBlock]

    init(floatingBlocks: [FocusFloatingBlock] = []) {
        self.floatingBlocks = floatingBlocks
    }
}

// MARK: - Atom Focus Floating Blocks Helpers

extension Atom {
    /// Get floating blocks from metadata
    var focusFloatingBlocks: [FocusFloatingBlock] {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocksJSON = dict["focusFloatingBlocks"],
              let blocksData = try? JSONSerialization.data(withJSONObject: blocksJSON) else {
            return []
        }
        return (try? JSONDecoder().decode([FocusFloatingBlock].self, from: blocksData)) ?? []
    }

    /// Create a copy with updated floating blocks in metadata
    func withFocusFloatingBlocks(_ blocks: [FocusFloatingBlock]) -> Atom {
        var copy = self

        // Parse existing metadata or create new
        var dict: [String: Any] = [:]
        if let existingMetadata = copy.metadata,
           let data = existingMetadata.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        // Encode floating blocks
        if let blocksData = try? JSONEncoder().encode(blocks),
           let blocksJSON = try? JSONSerialization.jsonObject(with: blocksData) {
            dict["focusFloatingBlocks"] = blocksJSON
        }

        // Serialize back
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            copy.metadata = jsonString
        }

        return copy
    }
}

// MARK: - IdeaForge Enums (must precede IdeaMetadata)

/// Status pipeline for ideas
enum IdeaStatus: String, Codable, Sendable, CaseIterable {
    case spark
    case developing
    case ready
    case inProduction
    case published
    case archived

    var displayName: String {
        switch self {
        case .spark: return "Spark"
        case .developing: return "Developing"
        case .ready: return "Ready"
        case .inProduction: return "In Production"
        case .published: return "Published"
        case .archived: return "Archived"
        }
    }

    var iconName: String {
        switch self {
        case .spark: return "sparkles"
        case .developing: return "hammer.fill"
        case .ready: return "checkmark.seal.fill"
        case .inProduction: return "gearshape.fill"
        case .published: return "paperplane.fill"
        case .archived: return "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .spark: return Color(hex: "#FBBF24")
        case .developing: return Color(hex: "#818CF8")
        case .ready: return Color(hex: "#34D399")
        case .inProduction: return Color(hex: "#F97316")
        case .published: return Color(hex: "#38BDF8")
        case .archived: return Color(hex: "#6B7280")
        }
    }

    var sortOrder: Int {
        switch self {
        case .spark: return 0
        case .developing: return 1
        case .ready: return 2
        case .inProduction: return 3
        case .published: return 4
        case .archived: return 5
        }
    }
}

/// Content format for ideas
enum IdeaContentFormat: String, Codable, Sendable, CaseIterable {
    case thread
    case reel
    case carousel
    case post
    case longForm
    case youtube
    case newsletter

    var displayName: String {
        switch self {
        case .thread: return "Thread"
        case .reel: return "Reel"
        case .carousel: return "Carousel"
        case .post: return "Post"
        case .longForm: return "Long Form"
        case .youtube: return "YouTube"
        case .newsletter: return "Newsletter"
        }
    }

    var iconName: String {
        switch self {
        case .thread: return "text.line.first.and.arrowtriangle.forward"
        case .reel: return "play.rectangle.fill"
        case .carousel: return "rectangle.split.3x1.fill"
        case .post: return "square.text.square.fill"
        case .longForm: return "doc.richtext.fill"
        case .youtube: return "play.rectangle.fill"
        case .newsletter: return "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .thread: return Color(hex: "#38BDF8")
        case .reel: return Color(hex: "#F472B6")
        case .carousel: return Color(hex: "#A78BFA")
        case .post: return Color(hex: "#34D399")
        case .longForm: return Color(hex: "#818CF8")
        case .youtube: return Color(hex: "#EF4444")
        case .newsletter: return Color(hex: "#FBBF24")
        }
    }

    var idealSectionCount: ClosedRange<Int> {
        switch self {
        case .thread: return 5...15
        case .reel: return 3...7
        case .carousel: return 5...10
        case .post: return 1...3
        case .longForm: return 5...20
        case .youtube: return 5...15
        case .newsletter: return 3...8
        }
    }
}

/// Platform for idea distribution
enum IdeaPlatform: String, Codable, Sendable, CaseIterable {
    case youtube
    case instagram
    case x
    case threads
    case linkedin
    case tiktok
    case newsletter

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .x: return "X"
        case .threads: return "Threads"
        case .linkedin: return "LinkedIn"
        case .tiktok: return "TikTok"
        case .newsletter: return "Newsletter"
        }
    }

    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .x: return "bubble.left.fill"
        case .threads: return "at"
        case .linkedin: return "briefcase.fill"
        case .tiktok: return "music.note"
        case .newsletter: return "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .youtube: return Color(hex: "#EF4444")
        case .instagram: return Color(hex: "#E879F9")
        case .x: return Color(hex: "#FFFFFF")
        case .threads: return Color(hex: "#FFFFFF")
        case .linkedin: return Color(hex: "#0A66C2")
        case .tiktok: return Color(hex: "#00F2EA")
        case .newsletter: return Color(hex: "#FBBF24")
        }
    }

    var supportedFormats: [ContentFormat] {
        switch self {
        case .youtube: return [.youtube, .longForm]
        case .instagram: return [.voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA, .carousel, .post]
        case .x: return [.tweet, .thread, .post]
        case .threads: return [.thread, .post]
        case .linkedin: return [.post, .carousel, .longForm]
        case .tiktok: return [.voiceoverReel, .oneSliderReel, .multiSliderReel]
        case .newsletter: return [.newsletter, .longForm]
        }
    }
}

// MARK: - Narrative Style (Swipe Intelligence Taxonomy)

/// Narrative approach used in a piece of content
public enum NarrativeStyle: String, Codable, CaseIterable, Sendable {
    case studentSuccess
    case noValue
    case lessonsLearned
    case authorityHacking
    case businessBreakdown
    case storytelling
    case fearMongering

    public var displayName: String {
        switch self {
        case .studentSuccess: return "Student Success"
        case .noValue: return "No Value"
        case .lessonsLearned: return "Lessons Learned"
        case .authorityHacking: return "Authority Hacking"
        case .businessBreakdown: return "Business Breakdown"
        case .storytelling: return "Storytelling"
        case .fearMongering: return "Fear Mongering"
        }
    }

    public var icon: String {
        switch self {
        case .studentSuccess: return "graduationcap.fill"
        case .noValue: return "xmark.circle.fill"
        case .lessonsLearned: return "book.closed.fill"
        case .authorityHacking: return "checkmark.seal.fill"
        case .businessBreakdown: return "chart.bar.doc.horizontal.fill"
        case .storytelling: return "text.book.closed.fill"
        case .fearMongering: return "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .studentSuccess: return Color(hex: "#34D399")   // Emerald
        case .noValue: return Color(hex: "#6B7280")          // Gray
        case .lessonsLearned: return Color(hex: "#FBBF24")   // Amber
        case .authorityHacking: return Color(hex: "#818CF8") // Indigo
        case .businessBreakdown: return Color(hex: "#38BDF8") // Sky
        case .storytelling: return Color(hex: "#A78BFA")     // Violet
        case .fearMongering: return Color(hex: "#EF4444")    // Red
        }
    }
}

// MARK: - Unified Content Format (Swipe Intelligence Taxonomy)

/// Unified content format used by both swipes and ideas
public enum ContentFormat: String, Codable, CaseIterable, Sendable {
    // Short-form video
    case voiceoverReel
    case oneSliderReel
    case multiSliderReel
    case twoStepCTA
    // Static/carousel
    case carousel
    // Text
    case tweet
    case thread
    // Long-form (existing, kept for compat)
    case longForm
    case youtube
    case newsletter
    // Legacy compat
    case post
    case reel

    public var displayName: String {
        switch self {
        case .voiceoverReel: return "Voiceover Reel"
        case .oneSliderReel: return "One-Slider Reel"
        case .multiSliderReel: return "Multi-Slider Reel"
        case .twoStepCTA: return "Two-Step CTA"
        case .carousel: return "Carousel"
        case .tweet: return "Tweet"
        case .thread: return "Thread"
        case .longForm: return "Long Form"
        case .youtube: return "YouTube"
        case .newsletter: return "Newsletter"
        case .post: return "Post"
        case .reel: return "Reel"
        }
    }

    public var icon: String {
        switch self {
        case .voiceoverReel: return "waveform"
        case .oneSliderReel: return "play.rectangle.fill"
        case .multiSliderReel: return "rectangle.split.2x1.fill"
        case .twoStepCTA: return "arrow.right.circle.fill"
        case .carousel: return "rectangle.split.3x1.fill"
        case .tweet: return "bubble.left.fill"
        case .thread: return "text.line.first.and.arrowtriangle.forward"
        case .longForm: return "doc.richtext.fill"
        case .youtube: return "play.rectangle.fill"
        case .newsletter: return "envelope.fill"
        case .post: return "square.text.square.fill"
        case .reel: return "play.rectangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .voiceoverReel: return Color(hex: "#F472B6")   // Pink
        case .oneSliderReel: return Color(hex: "#FB923C")   // Soft orange
        case .multiSliderReel: return Color(hex: "#F97316") // Orange
        case .twoStepCTA: return Color(hex: "#34D399")      // Emerald
        case .carousel: return Color(hex: "#A78BFA")        // Violet
        case .tweet: return Color(hex: "#38BDF8")           // Sky
        case .thread: return Color(hex: "#60A5FA")          // Blue
        case .longForm: return Color(hex: "#818CF8")        // Indigo
        case .youtube: return Color(hex: "#EF4444")         // Red
        case .newsletter: return Color(hex: "#FBBF24")      // Amber
        case .post: return Color(hex: "#34D399")            // Emerald
        case .reel: return Color(hex: "#F472B6")            // Pink
        }
    }

    /// Backward-compatible decoder: old ".reel" decodes as .reel (maps to oneSliderReel conceptually)
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let value = ContentFormat(rawValue: rawValue) {
            self = value
        } else {
            // Fallback for unknown future values
            self = .post
        }
    }

    /// Convert from legacy IdeaContentFormat
    init(from legacy: IdeaContentFormat) {
        switch legacy {
        case .thread: self = .thread
        case .reel: self = .reel
        case .carousel: self = .carousel
        case .post: self = .post
        case .longForm: self = .longForm
        case .youtube: self = .youtube
        case .newsletter: self = .newsletter
        }
    }

    /// Ideal section count range for content blueprint generation
    public var idealSectionCount: ClosedRange<Int> {
        switch self {
        case .voiceoverReel: return 3...6
        case .oneSliderReel: return 3...6
        case .multiSliderReel: return 4...8
        case .twoStepCTA: return 2...5
        case .carousel: return 5...10
        case .tweet: return 1...2
        case .thread: return 5...15
        case .longForm: return 5...20
        case .youtube: return 5...15
        case .newsletter: return 3...8
        case .post: return 1...3
        case .reel: return 3...7
        }
    }

    /// Grouped format categories for UI display
    public static var shortFormVideo: [ContentFormat] {
        [.voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA]
    }

    public static var staticFormats: [ContentFormat] {
        [.carousel]
    }

    public static var textFormats: [ContentFormat] {
        [.tweet, .thread, .post]
    }

    public static var longFormFormats: [ContentFormat] {
        [.longForm, .youtube, .newsletter]
    }
}

// MARK: - Classification Source

/// How a taxonomy classification was assigned
public enum ClassificationSource: String, Codable, Sendable {
    case ai
    case manual
    case aiOverridden
}

/// Metadata for client profile atoms
struct ClientMetadata: Codable, Sendable {
    var handles: [String: String]?
    var niche: String?
    var preferredFormats: [String]?
    var preferredPlatforms: [String]?
    var brandVoice: String?
    var color: String?
    var isActive: Bool?
}

/// Metadata for content creator atoms (.creator type)
struct CreatorMetadata: Codable, Sendable {
    var handle: String?               // Primary handle (e.g., "@creator")
    var platform: String?             // Primary platform (e.g., "instagram", "youtube")
    var niche: String?                // Creator's niche/vertical
    var followerCount: Int?           // Approximate follower count
    var swipeCount: Int?              // Number of swipes saved from this creator
    var averageHookScore: Double?     // Average hook score across their swipes
    var topNarratives: [String]?      // Most common narrative styles (raw values)
    var topFormats: [String]?         // Most common content formats (raw values)
    var notes: String?                // User's notes about this creator
    var profileUrl: String?           // URL to creator's profile
    var thumbnailUrl: String?         // Cached avatar/thumbnail URL
    var isActive: Bool?               // Whether creator is still tracked
}

/// Metadata for user-defined taxonomy values (.taxonomyValue type)
struct TaxonomyValueMetadata: Codable, Sendable {
    var dimension: String             // e.g., "niche", "narrative", "format"
    var value: String                 // The actual value string
    var sortOrder: Int                // Display ordering
    var isDefault: Bool               // Whether this is a system default vs user-created
    var parentValue: String?          // For hierarchical taxonomies
    var usageCount: Int?              // How many swipes use this value
    var color: String?                // Optional display color hex
    var icon: String?                 // Optional SF Symbol name
}

// MARK: - Common Metadata Types

/// Metadata for idea atoms
struct IdeaMetadata: Codable, Sendable {
    var tags: [String]?
    var priority: String?
    var isPinned: Bool?
    var pinnedAt: String?
    // IdeaForge fields
    var ideaStatus: IdeaStatus?
    var contentFormat: ContentFormat?
    var platform: IdeaPlatform?
    var clientUUID: String?
    var accountHandle: String?
    var statusChangedAt: String?
    var captureSource: String?
    var originSwipeUUID: String?
    var suggestedFramework: String?
    var suggestedHookType: String?
    var insightScore: Double?
    var matchingSwipeCount: Int?
    var lastAnalyzedAt: String?
    var contentUUIDs: [String]?
}

// MARK: - Task Recommendation Types

/// Task type for energy/focus matching in recommendation engine
public enum TaskCategoryType: String, Codable, CaseIterable, Sendable {
    case deepWork = "deepWork"
    case creative = "creative"
    case communication = "communication"
    case administrative = "administrative"
    case physical = "physical"
    case learning = "learning"

    /// Ideal energy range for this task type (0-100)
    public var idealEnergyRange: ClosedRange<Int> {
        switch self {
        case .deepWork: return 60...100
        case .creative: return 65...100
        case .communication: return 50...100
        case .administrative: return 30...100
        case .physical: return 50...100
        case .learning: return 55...100
        }
    }

    /// Ideal focus range for this task type (0-100)
    public var idealFocusRange: ClosedRange<Int> {
        switch self {
        case .deepWork: return 65...100
        case .creative: return 60...100
        case .communication: return 40...100
        case .administrative: return 30...100
        case .physical: return 20...100
        case .learning: return 55...100
        }
    }

    /// SF Symbol icon name
    public var iconName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .creative: return "paintbrush"
        case .communication: return "message"
        case .administrative: return "folder"
        case .physical: return "figure.walk"
        case .learning: return "book"
        }
    }

    /// Display name
    public var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .creative: return "Creative"
        case .communication: return "Communication"
        case .administrative: return "Administrative"
        case .physical: return "Physical"
        case .learning: return "Learning"
        }
    }
}

/// Extension to add numeric range to existing EnergyLevel
extension EnergyLevel: CaseIterable {
    public static var allCases: [EnergyLevel] { [.low, .medium, .high] }

    public var numericRange: ClosedRange<Int> {
        switch self {
        case .low: return 0...40
        case .medium: return 41...70
        case .high: return 71...100
        }
    }
}

/// Cognitive load for task requirements
public enum CognitiveLoad: String, Codable, CaseIterable, Sendable {
    case light = "light"
    case medium = "medium"
    case deep = "deep"

    public var focusRequirement: ClosedRange<Int> {
        switch self {
        case .light: return 0...40
        case .medium: return 41...65
        case .deep: return 66...100
        }
    }
}

// MARK: - Task Intent

/// Smart task intent — determines what CosmoOS opens when a task session starts
public enum TaskIntent: String, Codable, CaseIterable, Sendable {
    case writeContent = "writeContent"    // Opens idea picker → activation → content focus mode
    case research = "research"            // Opens CosmoAI Research mode
    case studySwipes = "studySwipes"      // Opens Swipe Gallery
    case deepThink = "deepThink"          // Opens Connection focus mode
    case review = "review"                // Opens specific atom in read mode
    case general = "general"              // No special action (standard task)
    case custom = "custom"                // User-defined action chain

    public var displayName: String {
        switch self {
        case .writeContent: return "Write Content"
        case .research: return "Research"
        case .studySwipes: return "Study Swipes"
        case .deepThink: return "Deep Think"
        case .review: return "Review"
        case .general: return "General"
        case .custom: return "Custom"
        }
    }

    public var iconName: String {
        switch self {
        case .writeContent: return "pencil.line"
        case .research: return "magnifyingglass"
        case .studySwipes: return "bolt.fill"
        case .deepThink: return "brain.head.profile"
        case .review: return "eye"
        case .general: return "checkmark.circle"
        case .custom: return "gear"
        }
    }

    public var color: Color {
        switch self {
        case .writeContent: return Color(red: 129/255, green: 140/255, blue: 248/255) // Indigo
        case .research: return Color(red: 56/255, green: 189/255, blue: 248/255)      // Cyan
        case .studySwipes: return Color(red: 255/255, green: 215/255, blue: 0/255)    // Gold
        case .deepThink: return Color(red: 168/255, green: 85/255, blue: 247/255)     // Purple
        case .review: return Color(red: 74/255, green: 222/255, blue: 128/255)        // Green
        case .general: return Color(red: 148/255, green: 163/255, blue: 184/255)      // Slate
        case .custom: return Color(red: 251/255, green: 146/255, blue: 60/255)        // Orange
        }
    }

    /// Primary Sanctuary dimension that receives XP for this intent
    public var dimension: String {
        switch self {
        case .writeContent: return "creative"
        case .research: return "cognitive"
        case .studySwipes: return "creative"
        case .deepThink: return "reflection"
        case .review: return "creative"
        case .general: return "behavioral"
        case .custom: return "behavioral"
        }
    }

    /// Display name for the dimension(s) receiving XP
    public var dimensionDisplayName: String {
        switch self {
        case .writeContent: return "Creative"
        case .research: return "Cognitive & Knowledge"
        case .studySwipes: return "Creative & Cognitive"
        case .deepThink: return "Reflection & Cognitive"
        case .review: return "Creative & Behavioral"
        case .general: return "Behavioral"
        case .custom: return "Behavioral"
        }
    }

    /// Color for the primary dimension receiving XP
    public var dimensionColor: Color {
        switch self {
        case .writeContent: return Color(red: 245/255, green: 158/255, blue: 11/255)     // creative amber
        case .research: return Color(red: 99/255, green: 102/255, blue: 241/255)         // cognitive indigo
        case .studySwipes: return Color(red: 245/255, green: 158/255, blue: 11/255)      // creative amber
        case .deepThink: return Color(red: 168/255, green: 85/255, blue: 247/255)        // reflection purple
        case .review: return Color(red: 245/255, green: 158/255, blue: 11/255)           // creative amber
        case .general: return Color(red: 20/255, green: 184/255, blue: 166/255)          // behavioral teal
        case .custom: return Color(red: 20/255, green: 184/255, blue: 166/255)           // behavioral teal
        }
    }
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

    // MARK: - Smart Task Intent (WP1)

    /// Task intent determining what opens on session start
    var intent: String?

    /// Pre-linked idea UUID for .writeContent tasks
    var linkedIdeaUUID: String?

    /// Content UUID if idea already activated
    var linkedContentUUID: String?

    /// Generic link to any atom
    var linkedAtomUUID: String?

    // MARK: - Time Blocking (WP3)

    /// ISO8601 time block start
    var scheduledStart: String?

    /// ISO8601 time block end
    var scheduledEnd: String?

    /// Apple Calendar EKEvent identifier for sync
    var calendarEventId: String?

    // MARK: - Session Tracking (WP2)

    /// Accumulated focus minutes across all sessions
    var totalFocusMinutes: Int?

    /// Number of deep work sessions spent on this task
    var sessionCount: Int?

    /// ISO8601 timestamp of last session
    var lastSessionAt: String?

    // MARK: - Recurrence (WP4)

    /// UUID of the template task this instance was generated from
    var recurrenceParentUUID: String?

    // MARK: - Recommendation Engine Fields

    /// Estimated focus time in minutes for AI recommendations
    var estimatedFocusMinutes: Int?

    /// Required energy level: "low", "medium", "high"
    var energyLevel: String?

    /// Cognitive load requirement: "light", "medium", "deep"
    var cognitiveLoad: String?

    /// Task type for energy matching: "deepWork", "creative", "communication", "administrative", "physical", "learning"
    var taskType: String?

    /// Cached recommendation score for sorting (0.0 to 1.0)
    var recommendationScore: Double?

    /// Number of times user skipped this recommendation
    var skipCount: Int?

    /// Last time this task was scheduled/recommended
    var lastScheduledAt: String?
}

// MARK: - Deep Work Session Metadata (WP2)

/// Metadata for .deepWorkSession atoms — tracks individual focus sessions
struct DeepWorkSessionMetadata: Codable, Sendable {
    var taskUUID: String?
    var startedAt: String               // ISO8601
    var endedAt: String?                // ISO8601
    var plannedMinutes: Int
    var actualMinutes: Int?
    var focusScore: Double?             // 0-100
    var distractionCount: Int?
    var intent: String?                 // TaskIntent raw value
    var outputAtomUUIDs: [String]?      // Atoms created during session
    var xpEarned: Int?
    var notes: String?                  // Post-session reflection
}

// MARK: - Objective Metadata (WP6)

/// Metadata for .objective atoms — quarter objectives with computed progress
struct ObjectiveMetadata: Codable, Sendable {
    var title: String
    var targetValue: Double             // e.g., 100 for '100 sessions'
    var currentValue: Double            // Computed from dataSource
    var unit: String                    // 'sessions', 'posts', 'XP', 'level'
    var dataSource: String              // ObjectiveDataSource raw value
    var quarter: Int                    // 1-4
    var year: Int
    var totalBlocksInvested: Int?
    var totalHoursInvested: Double?
}

/// Data source for computing objective progress
public enum ObjectiveDataSource: String, Codable, CaseIterable, Sendable {
    case deepWorkSessionCount = "deepWorkSessionCount"
    case contentPublishedCount = "contentPublishedCount"
    case totalXP = "totalXP"
    case currentLevel = "currentLevel"
    case tasksCompleted = "tasksCompleted"
    case customQuery = "customQuery"

    public var displayName: String {
        switch self {
        case .deepWorkSessionCount: return "Deep work sessions completed"
        case .contentPublishedCount: return "Content pieces published"
        case .totalXP: return "Total XP earned"
        case .currentLevel: return "Current level reached"
        case .tasksCompleted: return "Tasks completed"
        case .customQuery: return "Custom metric"
        }
    }
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
    var recurrence: String?
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

// MARK: - Idea Accessors

extension Atom {
    /// Get/set IdeaInsight from structured JSON (mirrors swipeAnalysis pattern)
    var ideaInsight: IdeaInsight? {
        get { structuredData(as: IdeaInsight.self) }
    }

    func withIdeaInsight(_ insight: IdeaInsight) -> Atom {
        withStructured(insight)
    }

    /// Convenience: idea status
    var ideaStatus: IdeaStatus? {
        ideaMetadata?.ideaStatus
    }

    /// Convenience: content format
    var ideaContentFormat: ContentFormat? {
        ideaMetadata?.contentFormat
    }

    /// Convenience: platform
    var ideaPlatform: IdeaPlatform? {
        ideaMetadata?.platform
    }

    /// Convenience: client UUID
    var ideaClientUUID: String? {
        ideaMetadata?.clientUUID
    }

    /// Convenience: insight score
    var ideaInsightScore: Double? {
        ideaMetadata?.insightScore
    }

    /// Convenience: matching swipe count
    var ideaMatchingSwipeCount: Int? {
        ideaMetadata?.matchingSwipeCount
    }

    /// Convenience: suggested framework
    var ideaSuggestedFramework: SwipeFrameworkType? {
        guard let raw = ideaMetadata?.suggestedFramework else { return nil }
        return SwipeFrameworkType(rawValue: raw)
    }

    /// Convenience: suggested hook type
    var ideaSuggestedHookType: SwipeHookType? {
        guard let raw = ideaMetadata?.suggestedHookType else { return nil }
        return SwipeHookType(rawValue: raw)
    }

    /// Update idea metadata in-place, preserving existing fields
    func withUpdatedIdeaMetadata(_ update: (inout IdeaMetadata) -> Void) -> Atom {
        var meta = ideaMetadata ?? IdeaMetadata()
        update(&meta)
        return withMetadata(meta)
    }

    /// Get parsed ClientMetadata (for clientProfile atoms)
    var clientMetadata: ClientMetadata? {
        metadataValue(as: ClientMetadata.self)
    }

    func withClientMetadata(_ meta: ClientMetadata) -> Atom {
        withMetadata(meta)
    }
}

// MARK: - IdeaGalleryItem

/// Lightweight display struct for Command-K Ideas Tab
struct IdeaGalleryItem: Identifiable, Sendable {
    let id: String
    let atomUUID: String
    let entityId: Int64
    let title: String
    let body: String?
    let status: IdeaStatus
    let contentFormat: ContentFormat?
    let platform: IdeaPlatform?
    let clientName: String?
    let clientUUID: String?
    let tags: [String]
    let insightScore: Double?
    let matchingSwipeCount: Int?
    let suggestedFramework: SwipeFrameworkType?
    let isPinned: Bool
    let contentCount: Int
    let createdAt: String
    let updatedAt: String
}

extension Atom {
    /// Convert an idea atom to an IdeaGalleryItem
    func toIdeaGalleryItem(clientName: String? = nil) -> IdeaGalleryItem? {
        guard type == .idea else { return nil }
        let meta = ideaMetadata
        let ideaToContentCount = linksList.filter { $0.linkType == .ideaToContent }.count
        return IdeaGalleryItem(
            id: uuid,
            atomUUID: uuid,
            entityId: id ?? -1,
            title: title ?? "Untitled Idea",
            body: body,
            status: meta?.ideaStatus ?? .spark,
            contentFormat: meta?.contentFormat,
            platform: meta?.platform,
            clientName: clientName,
            clientUUID: meta?.clientUUID,
            tags: meta?.tags ?? [],
            insightScore: meta?.insightScore,
            matchingSwipeCount: meta?.matchingSwipeCount,
            suggestedFramework: ideaSuggestedFramework,
            isPinned: meta?.isPinned ?? false,
            contentCount: ideaToContentCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

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
