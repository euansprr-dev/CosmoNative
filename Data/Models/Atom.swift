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
    case stickyNote = "sticky_note"                     // Square sticky note blocks (yellow)
    case thinkspace                                     // Saved Thinkspace configurations
    case image                                          // Native image blocks on canvas

    // MARK: - Planning & Objectives
    case objective                                      // Quarter/annual objectives (goals)

    // MARK: - Swipe Intelligence Taxonomy
    case creator                                        // Content creator profiles (for attribution)
    case taxonomyValue = "taxonomy_value"               // User-defined taxonomy dimension values

    // MARK: - Agent Learning
    case agentLearning = "agent_learning"               // Agent outcome tracking & taste profile data

    // MARK: - Areas (Things 3-inspired hierarchy)
    case area                                           // Permanent life category container for projects

    // MARK: - Automation
    case automation                                     // Automation rules (reactive canvas behaviors)

    // MARK: - Smart Templates
    case blockTemplate = "block_template"               // Template definition (reusable block blueprint)
    case templateInstance = "template_instance"          // Instantiated block from a template

    // MARK: - Content Physics Codex
    case codexElement = "codex_element"
    case codexWalkthrough = "codex_walkthrough"

    // MARK: - Inquiry Workspace (Mastery Engine)
    case deepDive = "deep_dive"                         // Long-term topic mastery home
    case inquirySession = "inquiry_session"             // Episode of focused exploration
    case question                                       // Branchable learning driver
    case extract                                        // Captured unit of meaning with provenance
    case lexiconEntry = "lexicon_entry"                 // Lightweight term/concept (matures into Connection/Deep Dive)

    // MARK: - Category Classification

    /// Category for grouping atom types
    var category: AtomCategory {
        switch self {
        case .idea, .task, .project, .content, .research, .connection,
             .journalEntry, .calendarEvent, .scheduleBlock, .uncommittedItem,
             .note, .stickyNote, .objective, .creator, .taxonomyValue, .image, .area,
             .deepDive, .inquirySession, .question, .extract, .lexiconEntry:
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
        case .semanticCluster, .connectionLink, .autoLinkSuggestion, .insightExtraction,
             .codexElement, .codexWalkthrough:
            return .knowledge
        case .journalInsight, .analysisChunk, .emotionalState, .clarityScore:
            return .reflection
        case .dailySummary, .weeklySummary, .syncEvent, .systemEvent, .userPreference, .routineDefinition,
             .thinkspace, .agentLearning, .automation, .blockTemplate, .templateInstance:
            return .system
        case .correlationInsight, .causalityComputation, .semanticExtraction, .sanctuarySnapshot,
             .livingInsight, .syncState:
            return .sanctuary
        }
    }

    /// Internal bookkeeping atoms (agent conversation logs, sync events, XP
    /// events, sanctuary snapshots…) must never surface in user-facing search.
    /// Thinkspaces are searched by name through ThinkspaceManager, not FTS.
    var isExcludedFromSearch: Bool {
        switch category {
        case .system, .leveling, .sanctuary:
            return true
        default:
            return false
        }
    }

    /// Raw values of search-excluded types, for SQL `NOT IN` clauses.
    static let searchExcludedRawValues: [String] =
        allCases.filter(\.isExcludedFromSearch).map(\.rawValue)

    /// User-facing types eligible for recents and broad keyword search.
    /// Single source of truth for the allowlist previously duplicated across
    /// AtomRepository fetch methods.
    static let userSearchableTypes: [AtomType] = [
        .idea, .note, .task, .research, .content, .connection,
        .project, .journalEntry, .image
    ]

    /// Whether this atom type contributes to XP
    var contributesToXP: Bool {
        switch self {
        case .codexElement, .codexWalkthrough, .blockTemplate:
            return false
        default:
            break
        }
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
        case .connection: return "Concept"
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
        case .stickyNote: return "Sticky Note"
        case .thinkspace: return "Thinkspace"
        // Planning
        case .objective: return "Objective"
        // Swipe Intelligence Taxonomy
        case .creator: return "Creator"
        case .taxonomyValue: return "Taxonomy Value"
        // Agent Learning
        case .agentLearning: return "Agent Learning"
        // Image
        case .image: return "Image"
        // Areas
        case .area: return "Area"
        // Automation
        case .automation: return "Automation"
        // Smart Templates
        case .blockTemplate: return "Template"
        case .templateInstance: return "Template Block"
        // Codex
        case .codexElement: return "Codex Element"
        case .codexWalkthrough: return "Walkthrough"
        // Inquiry Workspace
        case .deepDive: return "Deep Dive"
        case .inquirySession: return "Inquiry Session"
        case .question: return "Question"
        case .extract: return "Extract"
        case .lexiconEntry: return "Lexicon Entry"
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
        case .connection: return "Concepts"
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
        case .stickyNote: return "Sticky Notes"
        case .thinkspace: return "Thinkspaces"
        // Planning
        case .objective: return "Objectives"
        // Swipe Intelligence Taxonomy
        case .creator: return "Creators"
        case .taxonomyValue: return "Taxonomy Values"
        // Agent Learning
        case .agentLearning: return "Agent Learning"
        // Image
        case .image: return "Images"
        // Areas
        case .area: return "Areas"
        // Automation
        case .automation: return "Automations"
        // Smart Templates
        case .blockTemplate: return "Templates"
        case .templateInstance: return "Template Blocks"
        // Codex
        case .codexElement: return "Codex Elements"
        case .codexWalkthrough: return "Walkthroughs"
        // Inquiry Workspace
        case .deepDive: return "Deep Dives"
        case .inquirySession: return "Inquiry Sessions"
        case .question: return "Questions"
        case .extract: return "Extracts"
        case .lexiconEntry: return "Lexicon Entries"
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
        case .stickyNote: return "square.and.pencil"
        case .thinkspace: return "rectangle.3.group"
        // Planning
        case .objective: return "target"
        // Swipe Intelligence Taxonomy
        case .creator: return "person.crop.rectangle.fill"
        case .taxonomyValue: return "tag.fill"
        // Agent Learning
        case .agentLearning: return "brain"
        // Image
        case .image: return "photo.fill"
        // Areas
        case .area: return "square.stack.fill"
        // Automation
        case .automation: return "bolt.fill"
        // Smart Templates
        case .blockTemplate: return "rectangle.3.group.fill"
        case .templateInstance: return "rectangle.on.rectangle.fill"
        // Codex
        case .codexElement: return "atom"
        case .codexWalkthrough: return "text.book.closed"
        // Inquiry Workspace
        case .deepDive: return "circle.hexagongrid.circle.fill"
        case .inquirySession: return "rectangle.split.3x1.fill"
        case .question: return "questionmark.bubble.fill"
        case .extract: return "highlighter"
        case .lexiconEntry: return "character.book.closed.fill"
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
    case thinkspace = "thinkspace"
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
    case swipeToClient = "swipe_to_client"                 // Swipe tagged for a client
    case clientToSwipe = "client_to_swipe"                 // Client's tagged swipes

    // MARK: - Automation Links
    case automationScope = "automation_scope"              // Automation rule → scoped thinkspace/cluster

    // MARK: - Smart Template Links
    case templateDefinition = "template_definition"        // Instance → its template definition
    case templateInstance = "template_instance"             // Template → one of its instances
    case templateAutomation = "template_automation"         // Template → bound automation rule

    // MARK: - Codex Links
    case codexElementToWalkthrough = "codex_element_to_walkthrough"
    case walkthroughToCodexElement = "walkthrough_to_codex_element"
    case ideaToBlueprint = "idea_to_blueprint"
    case blueprintToIdea = "blueprint_to_idea"

    // MARK: - Bidirectional Links (for knowledge graph traversal)
    case linksTo = "links_to"                              // Generic forward link
    case linkedFrom = "linked_from"                        // Generic back link

    // MARK: - Sanctuary / Causality Links
    case correlationSource = "correlation_source"          // Insight -> source metric atoms
    case correlationTarget = "correlation_target"          // Insight -> target metric atoms
    case semanticSource = "semantic_source"                // Semantic extraction -> source journal
    case computationResult = "computation_result"          // Computation -> resulting insights
    case snapshotData = "snapshot_data"                    // Snapshot -> included data atoms

    // MARK: - Inquiry Workspace Links
    // Deep Dive ↔ children
    case deepDiveParent = "deep_dive_parent"               // Deep Dive -> parent Thinkspace UUID(s)
    case deepDiveQuestion = "deep_dive_question"           // Deep Dive -> owned Question
    case deepDiveLexicon = "deep_dive_lexicon"             // Deep Dive -> owned Lexicon Entry
    case deepDiveConnection = "deep_dive_connection"       // Deep Dive -> Connection crystallized within
    case deepDiveSource = "deep_dive_source"               // Deep Dive -> Source used (denormalized)
    case deepDiveExtract = "deep_dive_extract"             // Deep Dive -> Extract captured (denormalized)
    case deepDiveSession = "deep_dive_session"             // Deep Dive -> Inquiry Session
    case relatedDeepDive = "related_deep_dive"             // Deep Dive ↔ Deep Dive (bidirectional)
    case contentFromDeepDive = "content_from_deep_dive"    // Deep Dive -> Content/Idea atom produced
    // Inquiry Session ↔ artifacts
    case inquiryParentDeepDive = "inquiry_parent_deep_dive"     // Inquiry Session -> Deep Dive (single)
    case inquiryParentObject = "inquiry_parent_object"           // Inquiry Session -> Connection/cluster/etc.
    case inquiryRootQuestion = "inquiry_root_question"           // Inquiry Session -> root Question (single)
    case sessionExtract = "session_extract"                       // Inquiry Session -> Extract captured
    case sessionCreatedQuestion = "session_created_question"      // Inquiry Session -> Question birthed
    case sessionCreatedLexicon = "session_created_lexicon"        // Inquiry Session -> Lexicon birthed
    case sessionUsedSource = "session_used_source"                // Inquiry Session -> Source used
    case sessionSplitFrom = "session_split_from"                  // Inquiry Session -> origin Inquiry Session (split)
    // Question
    case questionParentDeepDive = "question_parent_deep_dive"     // Question -> Deep Dive (single)
    case questionBranch = "question_branch"                        // Parent Question -> child branch Question
    case questionExtract = "question_extract"                      // Question -> Extract attached
    case questionSource = "question_source"                        // Question -> Source answering it
    case questionLinkedConnection = "question_linked_connection"   // Question -> related Connection
    // Extract
    case extractFromSource = "extract_from_source"                // Extract -> origin Source (single)
    case extractInQuestion = "extract_in_question"                // Extract -> Question (single)
    case extractInSession = "extract_in_session"                  // Extract -> Inquiry Session (single)
    case extractPromotedTo = "extract_promoted_to"                // Extract -> destination atom (single)
    // Lexicon
    case lexiconParentDeepDive = "lexicon_parent_deep_dive"       // Lexicon -> Deep Dive (single)
    case lexiconRelatedQuestion = "lexicon_related_question"      // Lexicon -> Question
    case lexiconPromotedTo = "lexicon_promoted_to"                // Lexicon -> Connection/Deep Dive (single)
    case lexiconRelated = "lexicon_related"                       // Lexicon ↔ Lexicon (bidirectional)
    // Output integration
    case outputFromInquiry = "output_from_inquiry"                // Idea/Content -> Inquiry Session
    case outputFromDeepDive = "output_from_deep_dive"             // Idea/Content -> Deep Dive

    /// Whether this is a single-value relationship (only one link of this type allowed)
    var isSingleValue: Bool {
        switch self {
        case .project, .thinkspace, .parentIdea, .originIdea, .connection, .recurrenceParent,
             .draftToContent, .publishSource, .clarityOf, .journalSource,
             .sleepToReadiness, .deepWorkProject, .routineInstance,
             .templateDefinition,
             // Inquiry Workspace single-value links
             .inquiryParentDeepDive, .inquiryRootQuestion,
             .questionParentDeepDive,
             .extractFromSource, .extractInQuestion, .extractInSession, .extractPromotedTo,
             .lexiconParentDeepDive, .lexiconPromotedTo:
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
        case .swipeToClient: return .clientToSwipe
        case .clientToSwipe: return .swipeToClient
        case .codexElementToWalkthrough: return .walkthroughToCodexElement
        case .walkthroughToCodexElement: return .codexElementToWalkthrough
        case .ideaToBlueprint: return .blueprintToIdea
        case .blueprintToIdea: return .ideaToBlueprint
        case .templateDefinition: return .templateInstance
        case .templateInstance: return .templateDefinition
        // Inquiry Workspace bidirectional pairs
        case .relatedDeepDive: return .relatedDeepDive
        case .lexiconRelated: return .lexiconRelated
        default: return nil
        }
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .project: return "Project"
        case .thinkspace: return "Thinkspace"
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
        case .swipeToClient: return "Swipe to Client"
        case .clientToSwipe: return "Client to Swipe"
        // Automation
        case .automationScope: return "Automation Scope"
        // Smart Templates
        case .templateDefinition: return "Template Definition"
        case .templateInstance: return "Template Instance"
        case .templateAutomation: return "Template Automation"
        // Codex
        case .codexElementToWalkthrough: return "Element to Walkthrough"
        case .walkthroughToCodexElement: return "Walkthrough to Element"
        case .ideaToBlueprint: return "Idea to Blueprint"
        case .blueprintToIdea: return "Blueprint to Idea"
        // Inquiry Workspace
        case .deepDiveParent: return "Deep Dive Parent"
        case .deepDiveQuestion: return "Deep Dive Question"
        case .deepDiveLexicon: return "Deep Dive Lexicon"
        case .deepDiveConnection: return "Deep Dive Connection"
        case .deepDiveSource: return "Deep Dive Source"
        case .deepDiveExtract: return "Deep Dive Extract"
        case .deepDiveSession: return "Deep Dive Session"
        case .relatedDeepDive: return "Related Deep Dive"
        case .contentFromDeepDive: return "Content from Deep Dive"
        case .inquiryParentDeepDive: return "Inquiry Parent Deep Dive"
        case .inquiryParentObject: return "Inquiry Parent Object"
        case .inquiryRootQuestion: return "Inquiry Root Question"
        case .sessionExtract: return "Session Extract"
        case .sessionCreatedQuestion: return "Session Created Question"
        case .sessionCreatedLexicon: return "Session Created Lexicon"
        case .sessionUsedSource: return "Session Used Source"
        case .sessionSplitFrom: return "Session Split From"
        case .questionParentDeepDive: return "Question Parent Deep Dive"
        case .questionBranch: return "Question Branch"
        case .questionExtract: return "Question Extract"
        case .questionSource: return "Question Source"
        case .questionLinkedConnection: return "Question Linked Connection"
        case .extractFromSource: return "Extract from Source"
        case .extractInQuestion: return "Extract in Question"
        case .extractInSession: return "Extract in Session"
        case .extractPromotedTo: return "Extract Promoted To"
        case .lexiconParentDeepDive: return "Lexicon Parent Deep Dive"
        case .lexiconRelatedQuestion: return "Lexicon Related Question"
        case .lexiconPromotedTo: return "Lexicon Promoted To"
        case .lexiconRelated: return "Lexicon Related"
        case .outputFromInquiry: return "Output from Inquiry"
        case .outputFromDeepDive: return "Output from Deep Dive"
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

    static func thinkspace(_ uuid: String) -> AtomLink {
        AtomLink(linkType: .thinkspace, uuid: uuid, entityType: .thinkspace)
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

    // MARK: - Swipe-to-Client Link Factories

    static func swipeToClient(_ clientUUID: String) -> AtomLink {
        AtomLink(linkType: .swipeToClient, uuid: clientUUID, entityType: .clientProfile)
    }

    static func clientToSwipe(_ swipeUUID: String) -> AtomLink {
        AtomLink(linkType: .clientToSwipe, uuid: swipeUUID, entityType: .research)
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
        let now = ISO8601.string(from: Date())
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
              let data = links.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([AtomLink].self, from: data)
        } catch {
            print("Atom[\(uuid.prefix(8))]: Failed to decode links JSON: \(error.localizedDescription)")
            return []
        }
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

    /// True when the links column holds data that fails to decode.
    /// `linksList` returns [] in this state — mutating links from that empty list
    /// would erase every relationship on the atom, so link writers must check this.
    var linksAreCorrupt: Bool {
        guard let links = links, !links.isEmpty else { return false }
        guard let data = links.data(using: .utf8) else { return true }
        return (try? JSONDecoder().decode([AtomLink].self, from: data)) == nil
    }

    /// Create a copy with updated links
    func withLinks(_ links: [AtomLink]) -> Atom {
        var copy = self
        if links.isEmpty {
            copy.links = nil
        } else if let encoded = try? String(data: JSONEncoder().encode(links), encoding: .utf8) {
            copy.links = encoded
        } else {
            // Encode failure must never wipe the column — keep what's there.
            PersistenceHealth.note(.writeFailure, context: "Atom.withLinks(\(uuid.prefix(8)))", detail: "links encode failed; keeping existing column")
        }
        return copy
    }

    /// Add a link (uses typed system to determine if single-value)
    func addingLink(_ link: AtomLink) -> Atom {
        guard !linksAreCorrupt else {
            PersistenceHealth.note(.decodeFailure, context: "Atom.addingLink(\(uuid.prefix(8)))", detail: "links column undecodable; refusing rewrite that would drop existing links")
            return self
        }
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
        guard !linksAreCorrupt else {
            PersistenceHealth.note(.decodeFailure, context: "Atom.addingLinks(\(uuid.prefix(8)))", detail: "links column undecodable; refusing rewrite that would drop existing links")
            return self
        }
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
        guard !linksAreCorrupt else { return self }
        let filtered = linksList.filter { $0.type != type }
        return withLinks(filtered)
    }

    /// Remove links of a typed link type
    func removingLinks(ofType type: AtomLinkType) -> Atom {
        guard !linksAreCorrupt else { return self }
        let filtered = linksList.filter { $0.type != type.rawValue }
        return withLinks(filtered)
    }

    /// Remove a specific link by UUID
    func removingLink(toUUID uuid: String) -> Atom {
        guard !linksAreCorrupt else { return self }
        let filtered = linksList.filter { $0.uuid != uuid }
        return withLinks(filtered)
    }

    /// Remove a specific link by type and UUID
    func removingLink(ofType type: AtomLinkType, toUUID uuid: String) -> Atom {
        guard !linksAreCorrupt else { return self }
        let filtered = linksList.filter { !($0.type == type.rawValue && $0.uuid == uuid) }
        return withLinks(filtered)
    }

    /// Replace a link of a specific type with a new one
    func replacingLink(ofType type: AtomLinkType, with newLink: AtomLink) -> Atom {
        guard !linksAreCorrupt else { return self }
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

    // MARK: - JSON Decode State

    /// Result of decoding a JSON column into a typed value, distinguishing
    /// "the column is empty" from "the column holds data we failed to decode".
    /// The distinction matters: callers that fall back to a default on `.corrupt`
    /// and re-save will silently erase the real data.
    enum JSONDecodeState<T> {
        case absent
        case value(T)
        case corrupt(Error)

        var value: T? {
            if case .value(let v) = self { return v }
            return nil
        }

        var isCorrupt: Bool {
            if case .corrupt = self { return true }
            return false
        }
    }

    // MARK: - Structured Data

    /// Decode structured data with explicit corrupt-vs-absent state.
    /// Mutating writers should refuse to overwrite when `.corrupt`.
    func decodedStructured<T: Decodable>(as type: T.Type) -> JSONDecodeState<T> {
        guard let structured = structured, !structured.isEmpty,
              let data = structured.data(using: .utf8) else {
            return .absent
        }
        do {
            return .value(try JSONDecoder().decode(type, from: data))
        } catch {
            return .corrupt(error)
        }
    }

    /// Get structured data as decoded type.
    /// Returns nil BOTH when the column is empty and when decode fails —
    /// prefer `decodedStructured(as:)` in write paths so corruption is never
    /// papered over with a default that then gets saved back.
    func structuredData<T: Decodable>(as type: T.Type) -> T? {
        switch decodedStructured(as: type) {
        case .absent:
            return nil
        case .value(let value):
            return value
        case .corrupt(let error):
            PersistenceHealth.note(.decodeFailure, context: "Atom.structuredData(\(uuid.prefix(8)), \(T.self))", detail: error.localizedDescription)
            return nil
        }
    }

    /// Create a copy with encoded structured data.
    /// Encode failure never wipes the column.
    func withStructured<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        if let encoded = try? String(data: JSONEncoder().encode(value), encoding: .utf8) {
            copy.structured = encoded
        } else {
            PersistenceHealth.note(.writeFailure, context: "Atom.withStructured(\(uuid.prefix(8)))", detail: "structured encode failed; keeping existing column")
        }
        return copy
    }

    /// Create a copy whose structured column merges `value`'s keys over the existing
    /// JSON object, preserving sibling keys owned by other writers (e.g. swipeAnalysis
    /// next to autoMetadata). Use this instead of `withStructured` whenever the typed
    /// struct does not model the whole column.
    func mergingStructuredKeys<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        guard let merged = Atom.mergedJSONObjectString(existing: structured, overlay: value, context: "structured(\(uuid.prefix(8)))") else {
            return copy
        }
        copy.structured = merged
        return copy
    }

    // MARK: - Metadata

    /// Decode metadata with explicit corrupt-vs-absent state.
    /// Mutating writers should refuse to overwrite when `.corrupt`.
    func decodedMetadata<T: Decodable>(as type: T.Type) -> JSONDecodeState<T> {
        guard let metadata = metadata, !metadata.isEmpty,
              let data = metadata.data(using: .utf8) else {
            return .absent
        }
        do {
            return .value(try JSONDecoder().decode(type, from: data))
        } catch {
            return .corrupt(error)
        }
    }

    /// Get metadata as decoded type.
    /// Returns nil BOTH when the column is empty and when decode fails —
    /// prefer `decodedMetadata(as:)` in write paths so corruption is never
    /// papered over with a default that then gets saved back.
    func metadataValue<T: Decodable>(as type: T.Type) -> T? {
        switch decodedMetadata(as: type) {
        case .absent:
            return nil
        case .value(let value):
            return value
        case .corrupt(let error):
            PersistenceHealth.note(.decodeFailure, context: "Atom.metadataValue(\(uuid.prefix(8)), \(T.self))", detail: error.localizedDescription)
            return nil
        }
    }

    /// Create a copy with encoded metadata.
    /// Encode failure never wipes the column.
    func withMetadata<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        if let encoded = try? String(data: JSONEncoder().encode(value), encoding: .utf8) {
            copy.metadata = encoded
        } else {
            PersistenceHealth.note(.writeFailure, context: "Atom.withMetadata(\(uuid.prefix(8)))", detail: "metadata encode failed; keeping existing column")
        }
        return copy
    }

    /// Create a copy whose metadata column merges `value`'s keys over the existing
    /// JSON object, preserving sibling keys owned by other writers (e.g. rich-document
    /// storage next to typed metadata). Use this instead of `withMetadata` whenever
    /// the typed struct does not model the whole column.
    func mergingMetadataKeys<T: Encodable>(_ value: T) -> Atom {
        var copy = self
        guard let merged = Atom.mergedJSONObjectString(existing: metadata, overlay: value, context: "metadata(\(uuid.prefix(8)))") else {
            return copy
        }
        copy.metadata = merged
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

    var isGeneratedCodexCorpus: Bool {
        let metadataFlags = [
            "isCodexSynthesis",
            "isExemplarCodex",
            "isCodex"
        ]
        if let metadataDict,
           metadataFlags.contains(where: { metadataDict[$0] as? Bool == true }) {
            return true
        }

        return ContextSourcePolicy.isGeneratedCodexCorpusTitle(title ?? "")
    }

    /// Merge an encodable value's keys over an existing JSON-object string.
    /// Returns nil (refuse to write) when the existing column is non-empty but
    /// unparseable, or when encoding fails — never destroys data it can't read.
    static func mergedJSONObjectString<T: Encodable>(existing: String?, overlay: T, context: String) -> String? {
        guard let overlayData = try? JSONEncoder().encode(overlay),
              let overlayObject = try? JSONSerialization.jsonObject(with: overlayData) as? [String: Any] else {
            PersistenceHealth.note(.writeFailure, context: "Atom.mergedJSONObjectString(\(context))", detail: "overlay encode failed; keeping existing column")
            return nil
        }

        guard let existing = existing, !existing.isEmpty else {
            return String(data: overlayData, encoding: .utf8)
        }

        guard let existingData = existing.data(using: .utf8),
              var merged = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
            PersistenceHealth.note(.decodeFailure, context: "Atom.mergedJSONObjectString(\(context))", detail: "existing column unparseable; refusing overwrite that would drop its data")
            return nil
        }

        for (key, value) in overlayObject {
            merged[key] = value
        }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let mergedString = String(data: mergedData, encoding: .utf8) else {
            PersistenceHealth.note(.writeFailure, context: "Atom.mergedJSONObjectString(\(context))", detail: "merged encode failed; keeping existing column")
            return nil
        }
        return mergedString
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
        addedAt: String = ISO8601.string(from: Date())
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

    /// Past Begin Writing: the idea lives on as a content source but leaves
    /// every idea gallery/board. Keep in sync with the iOS IdeaStatus twin.
    var isActivated: Bool {
        switch self {
        case .inProduction, .published, .archived: return true
        case .spark, .developing, .ready: return false
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

    public var isVideoFormat: Bool {
        switch self {
        case .reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA, .youtube:
            return true
        default: return false
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

    // Aggregate engagement stats (computed from imported posts)
    var totalPostsImported: Int?      // Total posts fetched from API
    var averageLikes: Double?         // Avg likes across imported posts
    var averageViews: Double?         // Avg views across imported posts
    var averageComments: Double?      // Avg comments across imported posts
    var medianEngagementRate: Double?  // Median engagement rate
    var lastImportedAt: String?       // ISO8601 timestamp of last import
    var bio: String?                  // Creator bio from profile
    var postsCount: Int?              // Total public posts count
    var followingCount: Int?          // Following count

    // Catalog persistence
    var catalogPostCount: Int?        // Number of posts in cached catalog file
    var catalogFetchedAt: String?     // ISO8601 timestamp of last Apify catalog fetch
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
    var clientName: String?
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
    // Linked context (Idea Page Redesign)
    var linkedSwipeIds: [String]?
    var linkedConnectionIds: [String]?
    var mentionedAtomUUIDs: [String]?
    // Hook + Description fields (Content Pipeline integration)
    var hooks: [String]?
    var ideaDescription: String?
    // Codex-era fields
    var context: String?
    var contentProfileUUID: String?
    var blueprintUUID: String?
    var supportingSwipeUUIDs: [String]?
    var ideaContentType: String?
    var codexOutline: String?
    var arcType: String?
    var creativeDirection: String?
    var researchResults: String?
    var chatHistory: String?
    var arcRecommendations: String?
    var lastModifiedUnix: Double?
}

// MARK: - Image Metadata

struct ImageMetadata: Codable, Sendable {
    var imagePath: String
    var originalFilename: String?
    var width: CGFloat?
    var height: CGFloat?
    var fileSize: Int?
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

/// Task energy requirement (formerly defined beside the retired voice journal router).
public enum EnergyLevel: String, Codable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"
}

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

public enum IntentBehaviorTemplate: String, Codable, CaseIterable, Sendable {
    case writeContent
    case research
    case studySwipes
    case deepThink
    case review

    var taskIntent: TaskIntent {
        switch self {
        case .writeContent: return .writeContent
        case .research: return .research
        case .studySwipes: return .studySwipes
        case .deepThink: return .deepThink
        case .review: return .review
        }
    }

    init?(_ taskIntent: TaskIntent) {
        switch taskIntent {
        case .writeContent: self = .writeContent
        case .research: self = .research
        case .studySwipes: self = .studySwipes
        case .deepThink: self = .deepThink
        case .review: self = .review
        case .general, .custom: return nil
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

    /// Primary user-facing custom intent definition UUID.
    var intentUUID: String?

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

    /// UUID of the schedule_block atom this task nests inside (iOS contract,
    /// July 2026). The block owns the time; the task just belongs to it — the
    /// link never time-boxes the task. For repeating blocks the task's own day
    /// picks the occurrence. Dangling pointers (block deleted/converted)
    /// resolve to nothing at read time, fail-soft.
    var scheduleBlockUUID: String?

    // MARK: - Session Tracking (WP2)

    /// Time goal in minutes. Presence makes this a "timed task": tracked focus time
    /// counts toward the goal (per occurrence day for recurring tasks, lifetime for
    /// one-offs) and the user is prompted when the goal is reached. Distinct from
    /// `durationMinutes`, which stays a scheduling estimate.
    var timeGoalMinutes: Int?

    /// Accumulated focus minutes across all sessions
    var totalFocusMinutes: Int?

    /// Number of deep work sessions spent on this task
    var sessionCount: Int?

    /// ISO8601 timestamp of last session
    var lastSessionAt: String?

    /// Explicit or derived habit attribution for the task
    var habitUUID: String?

    /// HabitAssignmentSource raw value. `manual` with a nil habitUUID means explicit "no habit".
    var habitAssignmentSource: String?

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

    /// Manual sort order for drag-to-reorder in today view (lower = higher)
    var manualSortOrder: Int?

    // MARK: - Things 3 Scheduling Model

    /// "When" date — when the user plans to work on this (distinct from deadline/dueDate)
    var whenDate: String?

    /// Time of day preference: "morning", "evening", or nil
    var timeOfDay: String?

    /// Scheduling bucket: "anytime", "someday", or nil (nil = has a whenDate, so it's scheduled)
    var schedulingState: String?

    // MARK: - Project Hierarchy

    /// UUID of the heading this task belongs to within a project
    var headingUUID: String?

    /// Sort position within a heading/section
    var sectionSortOrder: Int?

    // MARK: - Linked Atoms (max 3)

    /// JSON array of TaskLinkedAtom — replaces single linkedIdeaUUID/linkedContentUUID/linkedAtomUUID
    var linkedAtoms: String?

    /// JSON array of RichMention — @ mentions embedded in the task title
    var titleMentions: String?

    // MARK: - Recurring Series Log (virtual-occurrence model)

    /// Completed occurrences of this recurring series. **Template-only** (the series owner).
    /// The source of recurring history: each entry pins an occurrence day to when it was
    /// actually checked off. Day keys are "yyyy-MM-dd".
    var completedOccurrences: [TaskOccurrenceCompletion]?

    /// Occurrence day-keys ("yyyy-MM-dd") explicitly skipped, or backfilled as "missed"
    /// when an overdue occurrence is collapsed on completion. **Template-only**.
    var skippedOccurrences: [String]?

    /// Per-day overrides for individual occurrences (rare per-day edits), keyed by
    /// day-key ("yyyy-MM-dd"). **Template-only**.
    var occurrenceOverrides: [String: TaskOccurrenceOverride]?

    /// Timezone-safe series anchor: the day the series starts, as a date-only
    /// "yyyy-MM-dd" key. Written whenever the anchor is set/re-anchored; projection
    /// prefers it over instant-derived day keys (which shift when the timezone
    /// changes). **Template-only**; nil for legacy rows.
    var seriesAnchorDay: String?
}

// MARK: - Recurring Series Log Entries

/// A completed occurrence of a recurring series, stored on the series template's
/// `completedOccurrences`. `day` is the occurrence day-key ("yyyy-MM-dd"); `completedAt`
/// is the wall-clock time the user actually checked it off (may differ from `day` when an
/// overdue occurrence is collapsed). `trackedMinutes` carries focus time for that occurrence.
public struct TaskOccurrenceCompletion: Codable, Equatable, Sendable {
    public var day: String
    public var completedAt: String
    public var trackedMinutes: Int?
    /// Day-keys backfilled into `skippedOccurrences` when this completion collapsed an
    /// overdue occurrence. Recorded so uncomplete can reverse exactly those days.
    /// Optional so completion entries logged before this field still decode.
    public var backfilledDays: [String]?

    public init(day: String, completedAt: String, trackedMinutes: Int? = nil, backfilledDays: [String]? = nil) {
        self.day = day
        self.completedAt = completedAt
        self.trackedMinutes = trackedMinutes
        self.backfilledDays = backfilledDays
    }
}

/// A per-occurrence override on a recurring series (rare per-day edits), keyed by day-key
/// in `occurrenceOverrides`. Lets a single occurrence diverge from the template without
/// materializing a separate atom.
public struct TaskOccurrenceOverride: Codable, Equatable, Sendable {
    /// Custom title for this one occurrence.
    public var title: String?
    /// ISO8601 start that shifts this occurrence's time-of-day.
    public var startTime: String?
    /// Day-key this occurrence was moved to (reschedule a single occurrence).
    public var rescheduledTo: String?
    /// This single occurrence was removed from the series (skip without "missed" semantics).
    public var isCanceled: Bool?

    public init(title: String? = nil, startTime: String? = nil, rescheduledTo: String? = nil, isCanceled: Bool? = nil) {
        self.title = title
        self.startTime = startTime
        self.rescheduledTo = rescheduledTo
        self.isCanceled = isCanceled
    }
}

// MARK: - Task Linked Atom

/// An atom linked to a task for contextual work sessions (max 3 per task)
public struct TaskLinkedAtom: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var atomUUID: String
    public var atomType: String       // AtomType raw value
    public var titleSnapshot: String  // Title at link time (display without DB query)
    public var isPrimary: Bool        // Primary = opens as main view on play

    public init(id: String = UUID().uuidString, atomUUID: String, atomType: String, titleSnapshot: String, isPrimary: Bool = false) {
        self.id = id
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.titleSnapshot = titleSnapshot
        self.isPrimary = isPrimary
    }
}

// MARK: - Checklist Item (Things 3-style subtasks)

/// A lightweight checklist item within a task, stored as JSON in TaskMetadata.checklist
public struct ChecklistItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var isCompleted: Bool
    public var sortOrder: Int

    public init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}

// MARK: - Project Heading (Things 3-style section dividers)

/// A lightweight section heading within a project, stored as JSON in ProjectMetadata.headings
struct ProjectHeading: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var sortOrder: Int
    var isCollapsed: Bool

    init(id: String = UUID().uuidString, title: String, sortOrder: Int = 0, isCollapsed: Bool = false) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.isCollapsed = isCollapsed
    }
}

// MARK: - Area Metadata (Things 3-style life categories)

/// Metadata for area atoms — permanent containers that group projects
struct AreaMetadata: Codable, Sendable {
    var icon: String?
    var color: String?
    var sortOrder: Int?
    var isCollapsed: Bool?
}

// MARK: - Synthesis Metadata (WP5 Lasso Synthesis)

/// Metadata for connection atoms created via lasso synthesis
struct SynthesisMetadata: Codable, Sendable {
    var sourceAtomUUIDs: [String]
    var themes: [String]
    var openQuestions: [String]
    var evidenceSpans: [LassoEvidenceSpan]?
    var synthesizedAt: String  // ISO8601
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
    var intentUUID: String?
    var intentTitleSnapshot: String?
    var habitUUID: String?
    var habitTitleSnapshot: String?
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

    // MARK: - Things 3 Project Features

    /// Parent area UUID (life category container)
    var areaUUID: String?

    /// Rich description / purpose notes for the project
    var projectNotes: String?

    /// When to start working on the project (ISO8601)
    var whenDate: String?

    /// Hard deadline for the entire project (ISO8601)
    var deadline: String?

    /// Whether the project is completed
    var isCompleted: Bool?

    /// ISO8601 completion timestamp
    var completedAt: String?

    /// JSON array of ProjectHeading — section dividers within the project
    var headings: String?

    /// JSON array of task UUIDs in display order
    var taskSortOrder: String?

    /// Whether this is a temporary (task-list-only) project with no ThinkSpace
    var isTemporary: Bool?
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
    var swipeBoardIDs: [String]?
}

// MARK: - Knowledge Crystallization

/// Represents how deeply a piece of knowledge has been processed/internalized
/// Progresses from raw capture through annotation, distillation, connection, and full crystallization
enum CrystallizationLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case raw = 0
    case highlighted = 1
    case distilled = 2
    case connected = 3
    case crystallized = 4

    var description: String {
        switch self {
        case .raw: return "Raw"
        case .highlighted: return "Highlighted"
        case .distilled: return "Distilled"
        case .connected: return "Connected"
        case .crystallized: return "Crystallized"
        }
    }

    var color: Color {
        switch self {
        case .raw: return Color(hex: "#6B7280")
        case .highlighted: return Color(hex: "#FBBF24")
        case .distilled: return Color(hex: "#818CF8")
        case .connected: return Color(hex: "#34D399")
        case .crystallized: return Color(hex: "#38BDF8")
        }
    }

    static func < (lhs: CrystallizationLevel, rhs: CrystallizationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Metadata tracking crystallization state for an atom, stored in the `metadata` JSON field
struct CrystallizationMetadata: Codable, Sendable {
    var level: CrystallizationLevel
    var annotationCount: Int
    var linkCount: Int
    var edgeCount: Int
    var downstreamCount: Int
    var lastComputedAt: String?
    var userOverride: Int?
}

/// Metadata for journal entry atoms
struct JournalEntryMetadata: Codable, Sendable {
    var source: String? = nil
    var status: String? = nil
    var errorMessage: String? = nil
    var topics: [String]? = nil
    var sentiment: Double? = nil
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

    /// Update idea metadata in-place, preserving existing fields.
    /// Refuses to write when the existing metadata is corrupt — mutating a
    /// default-constructed IdeaMetadata and saving it back would erase the
    /// real (still-recoverable) metadata. Key-merges so sibling JSON keys
    /// (rich documents, analysis fields) survive.
    func withUpdatedIdeaMetadata(_ update: (inout IdeaMetadata) -> Void) -> Atom {
        var meta: IdeaMetadata
        switch decodedMetadata(as: IdeaMetadata.self) {
        case .value(let existing):
            meta = existing
        case .absent:
            meta = IdeaMetadata()
        case .corrupt(let error):
            PersistenceHealth.note(.decodeFailure, context: "Atom.withUpdatedIdeaMetadata(\(uuid.prefix(8)))", detail: "metadata undecodable (\(error.localizedDescription)); refusing default-overwrite")
            return self
        }
        update(&meta)
        return mergingMetadataKeys(meta)
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
    let context: String?
    let hooks: [String]
    let outline: [String]

    init(
        id: String,
        atomUUID: String,
        entityId: Int64,
        title: String,
        body: String?,
        status: IdeaStatus,
        contentFormat: ContentFormat?,
        platform: IdeaPlatform?,
        clientName: String?,
        clientUUID: String?,
        tags: [String],
        insightScore: Double?,
        matchingSwipeCount: Int?,
        suggestedFramework: SwipeFrameworkType?,
        isPinned: Bool,
        contentCount: Int,
        createdAt: String,
        updatedAt: String,
        context: String? = nil,
        hooks: [String] = [],
        outline: [String] = []
    ) {
        self.id = id
        self.atomUUID = atomUUID
        self.entityId = entityId
        self.title = title
        self.body = body
        self.status = status
        self.contentFormat = contentFormat
        self.platform = platform
        self.clientName = clientName
        self.clientUUID = clientUUID
        self.tags = tags
        self.insightScore = insightScore
        self.matchingSwipeCount = matchingSwipeCount
        self.suggestedFramework = suggestedFramework
        self.isPinned = isPinned
        self.contentCount = contentCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.context = context
        self.hooks = hooks
        self.outline = outline
    }
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
            clientName: clientName ?? meta?.clientName,
            clientUUID: meta?.clientUUID,
            tags: meta?.tags ?? [],
            insightScore: meta?.insightScore,
            matchingSwipeCount: meta?.matchingSwipeCount,
            suggestedFramework: ideaSuggestedFramework,
            isPinned: meta?.isPinned ?? false,
            contentCount: ideaToContentCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            context: Self.normalizedIdeaContext(meta?.context, fallbackBody: body),
            hooks: meta?.hooks ?? [],
            outline: Self.ideaOutlineItems(from: meta?.codexOutline)
        )
    }

    private static func normalizedIdeaContext(_ context: String?, fallbackBody: String?) -> String? {
        for candidate in [context, fallbackBody] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func ideaOutlineItems(from rawOutline: String?) -> [String] {
        guard let rawOutline, let data = rawOutline.data(using: .utf8),
              let outline = try? JSONDecoder().decode(CodexOutlineModel.self, from: data) else {
            return []
        }

        return outline.slides
            .sorted { $0.position < $1.position }
            .compactMap { slide in
                [
                    slide.note,
                    slide.speechAct,
                    slide.frame,
                    slide.transition
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            }
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

// MARK: - Smart Template Types

/// Layout mode for template block rendering
enum TemplateLayoutMode: String, Codable, Sendable, CaseIterable {
    case form       // Vertical field list (default)
    case card       // Compact card with key fields only
    case freeform   // User-arranged field positions
}

/// Visual style for template action buttons
enum TemplateButtonStyle: String, Codable, Sendable, CaseIterable {
    case primary
    case secondary
    case destructive
    case success
}

/// Field type for template field definitions
enum TemplateFieldType: String, Codable, Sendable, CaseIterable {
    case text           // Single line
    case longText       // Multi-line
    case number
    case currency
    case date
    case dateTime
    case select         // Single choice from options
    case multiSelect    // Multiple choices
    case toggle         // Boolean
    case atomReference  // Link to another atom (renders as chip)
    case url
    case rating         // 1-5 stars
    case progress       // 0-100 slider
    case computed       // Formula field (references other fields)

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .longText: return "Long Text"
        case .number: return "Number"
        case .currency: return "Currency"
        case .date: return "Date"
        case .dateTime: return "Date & Time"
        case .select: return "Select"
        case .multiSelect: return "Multi-Select"
        case .toggle: return "Toggle"
        case .atomReference: return "Atom Reference"
        case .url: return "URL"
        case .rating: return "Rating"
        case .progress: return "Progress"
        case .computed: return "Computed"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "textformat"
        case .longText: return "text.alignleft"
        case .number: return "number"
        case .currency: return "dollarsign.circle"
        case .date: return "calendar"
        case .dateTime: return "calendar.badge.clock"
        case .select: return "list.bullet"
        case .multiSelect: return "checklist"
        case .toggle: return "switch.2"
        case .atomReference: return "link"
        case .url: return "globe"
        case .rating: return "star.fill"
        case .progress: return "chart.bar.fill"
        case .computed: return "function"
        }
    }
}

/// Definition of a single field in a block template
struct TemplateFieldDefinition: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var key: String                     // Machine key (snake_case)
    var label: String                   // Display label
    var fieldType: TemplateFieldType
    var isRequired: Bool
    var defaultValue: String?           // JSON-encoded default
    var placeholder: String?
    var options: [String]?              // For .select, .multiSelect
    var sortOrder: Int
    var aiExtractionHint: String?       // e.g. "Extract the deal size from the body"
    var autoPopulateFrom: String?       // e.g. "atom.title", "date.today"

    static func new(key: String, label: String, fieldType: TemplateFieldType, sortOrder: Int) -> TemplateFieldDefinition {
        TemplateFieldDefinition(
            id: UUID().uuidString,
            key: key,
            label: label,
            fieldType: fieldType,
            isRequired: false,
            sortOrder: sortOrder
        )
    }
}

/// Definition of an action button in a block template
struct TemplateButtonDefinition: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var label: String
    var icon: String?                   // SF Symbol
    var style: TemplateButtonStyle
    var actions: [AutomationAction]     // Reuses existing automation action type
    var confirmationMessage: String?    // Optional "Are you sure?" prompt
    var sortOrder: Int

    static func new(label: String, style: TemplateButtonStyle, actions: [AutomationAction], sortOrder: Int) -> TemplateButtonDefinition {
        TemplateButtonDefinition(
            id: UUID().uuidString,
            label: label,
            style: style,
            actions: actions,
            sortOrder: sortOrder
        )
    }
}

/// Spawn trigger binding for a block template
struct TemplateSpawnTrigger: Codable, Sendable, Equatable {
    var triggerType: AutomationTriggerType
    var triggerConfig: [String: String]
    var conditions: [AutomationCondition]
    var targetThinkspaceId: String?
    var targetClusterId: String?
    var autoFill: Bool
    var boundRuleUUID: String?          // UUID of the created AutomationRule (set after binding)
}

/// Metadata for a block template definition (stored in atom.metadata)
struct BlockTemplateMetadata: Codable, Sendable, Equatable {
    var icon: String                    // SF Symbol
    var accentColorHex: String          // Block chrome color
    var category: String?               // User grouping ("Reviews", "Deals")
    var description: String?
    var fields: [TemplateFieldDefinition]
    var buttons: [TemplateButtonDefinition]
    var defaultWidth: Double?
    var defaultHeight: Double?
    var layoutMode: TemplateLayoutMode
    var spawnTriggers: [TemplateSpawnTrigger]
    var aiPromptContext: String?         // Context for AI field filling
    var autoFillEnabled: Bool
    var schemaVersion: Int
    var isArchived: Bool
    var instanceCount: Int              // Denormalized for display
    var lastInstantiatedAt: String?

    /// Create a new empty template metadata
    static func new(icon: String = "rectangle.3.group.fill", accentColorHex: String = "#6366F1") -> BlockTemplateMetadata {
        BlockTemplateMetadata(
            icon: icon,
            accentColorHex: accentColorHex,
            fields: [],
            buttons: [],
            layoutMode: .form,
            spawnTriggers: [],
            autoFillEnabled: false,
            schemaVersion: 1,
            isArchived: false,
            instanceCount: 0
        )
    }
}

/// Structured data for a template instance (stored in atom.structured)
struct TemplateInstanceStructured: Codable, Sendable, Equatable {
    var templateUUID: String
    var templateSchemaVersion: Int
    var fieldValues: [String: ConditionValue]
    var completedButtons: [String]       // Button IDs already pressed
    var instanceStatus: String?          // "active", "completed", "archived"
    var spawnContext: String?             // What triggered the spawn

    static func new(templateUUID: String, schemaVersion: Int) -> TemplateInstanceStructured {
        TemplateInstanceStructured(
            templateUUID: templateUUID,
            templateSchemaVersion: schemaVersion,
            fieldValues: [:],
            completedButtons: [],
            instanceStatus: "active"
        )
    }
}
