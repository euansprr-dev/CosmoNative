// CosmoOS/Core/CosmoNotifications.swift
// Unified notification system for CosmoOS
// All notification names in one place with type-safe payloads

import Foundation
import AppKit
import SwiftUI

// MARK: - CosmoNotification Namespace
/// Centralized notification definitions organized by domain.
/// This eliminates scattered `extension Notification.Name` blocks across the codebase.
///
/// ## Usage
/// ```swift
/// // Post
/// NotificationCenter.default.post(name: CosmoNotification.Canvas.blockExpanded, object: nil,
///     userInfo: CosmoNotification.Canvas.BlockExpandedPayload(blockId: "123").userInfo)
///
/// // Observe
/// .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockExpanded)) { notification in
///     if let payload = CosmoNotification.Canvas.BlockExpandedPayload(from: notification) {
///         // Use payload.blockId
///     }
/// }
/// ```
enum CosmoNotification {

    // MARK: - Theme Notifications
    enum Theme {
        /// Posted when the active theme changes. Triggers root view re-render.
        static let changed = Notification.Name("com.cosmo.theme.changed")
    }

    // MARK: - Canvas Notifications
    enum Canvas {
        /// Posted when the thinkspace surface flips between canvas and library
        /// (userInfo: ["isLibrary": Bool]). MainView hides its floating trail
        /// island while the library's own toolbar embeds one.
        static let thinkspaceModeChanged = Notification.Name("com.cosmo.canvas.thinkspaceModeChanged")

        // Block lifecycle
        static let blockExpanded = Notification.Name("com.cosmo.canvas.blockExpanded")
        static let blockCollapsed = Notification.Name("com.cosmo.canvas.blockCollapsed")
        static let blockSelected = Notification.Name("com.cosmo.canvas.blockSelected")
        static let blockDeselected = Notification.Name("com.cosmo.canvas.blockDeselected")

        /// Fly the canvas camera to frame a block (userInfo: ["atomUUID": String]).
        /// The agent's "show me where" primitive — answers spatial questions by
        /// gliding to the block instead of describing coordinates.
        static let focusBlock = Notification.Name("com.cosmo.canvas.focusBlock")

        // Block manipulation
        static let removeBlock = Notification.Name("com.cosmo.canvas.removeBlock")
        static let duplicateBlock = Notification.Name("com.cosmo.canvas.duplicateBlock")
        static let toggleBlockPin = Notification.Name("com.cosmo.canvas.toggleBlockPin")
        static let changeStickyColor = Notification.Name("com.cosmo.canvas.changeStickyColor")
        static let blurAllBlocks = Notification.Name("com.cosmo.canvas.blurAllBlocks")
        // Block position/size
        static let updateBlockPosition = Notification.Name("com.cosmo.canvas.updateBlockPosition")
        static let updateBlockSize = Notification.Name("com.cosmo.canvas.updateBlockSize")
        static let saveBlockSize = Notification.Name("com.cosmo.canvas.saveBlockSize")
        static let blockRenderedSizeChanged = Notification.Name("com.cosmo.canvas.blockRenderedSizeChanged")
        static let updateBlockContent = Notification.Name("com.cosmo.canvas.updateBlockContent")
        static let updateBlockMetadata = Notification.Name("com.cosmo.canvas.updateBlockMetadata")

        // Canvas state
        static let blocksChanged = Notification.Name("com.cosmo.canvas.blocksChanged")
        static let arrangeBlocks = Notification.Name("com.cosmo.canvas.arrangeBlocks")
        static let placeBlocksOnCanvas = Notification.Name("com.cosmo.canvas.placeBlocksOnCanvas")
        static let placeEntityOnCanvas = Notification.Name("com.cosmo.canvas.placeEntityOnCanvas")
        static let moveCanvasBlocks = Notification.Name("com.cosmo.canvas.moveBlocks")
        /// Ask the canvas to warm the snapshot cache for a thinkspace the
        /// user is likely to enter next (hovered sidebar row, recent
        /// spaces). userInfo: ["thinkspaceId": String].
        static let prewarmThinkspace = Notification.Name("com.cosmo.canvas.prewarmThinkspace")

        // Block creation
        static let createNoteBlock = Notification.Name("com.cosmo.canvas.createNoteBlock")
        static let createResearchBlock = Notification.Name("com.cosmo.canvas.createResearchBlock")
        static let createCosmoAIBlock = Notification.Name("com.cosmo.canvas.createCosmoAIBlock")
        static let createEntityAtPosition = Notification.Name("com.cosmo.canvas.createEntityAtPosition")

        // Approved canvas-plan cluster operations (thinkspace copilot)
        static let createClusterFromPlan = Notification.Name("com.cosmo.canvas.createClusterFromPlan")
        static let moveBlocksToCluster = Notification.Name("com.cosmo.canvas.moveBlocksToCluster")
        /// Posted once after ALL of an approved canvas plan's operations — the
        /// canvas runs its deterministic cluster-overlap resolution on it.
        static let canvasPlanDidApply = Notification.Name("com.cosmo.canvas.canvasPlanDidApply")

        // Smart actions (content-based)
        static let moveBlockByContentToTime = Notification.Name("com.cosmo.canvas.moveBlockByContentToTime")
        static let deleteBlockByContent = Notification.Name("com.cosmo.canvas.deleteBlockByContent")
        static let duplicateBlockByContent = Notification.Name("com.cosmo.canvas.duplicateBlockByContent")

        // Smart actions (by ID)
        static let moveBlockToTime = Notification.Name("com.cosmo.canvas.moveBlockToTime")
        static let deleteSpecificBlock = Notification.Name("com.cosmo.canvas.deleteSpecificBlock")
        static let resizeSelectedBlock = Notification.Name("com.cosmo.canvas.resizeSelectedBlock")
        static let duplicateSelectedBlock = Notification.Name("com.cosmo.canvas.duplicateSelectedBlock")
        static let closeSelectedBlock = Notification.Name("com.cosmo.canvas.closeSelectedBlock")

        // Ambient knowledge
        static let pullAmbientToCanvas = Notification.Name("com.cosmo.canvas.pullAmbientToCanvas")

        /// File an atom into a thinkspace without visiting it (⌘K drop-on-result).
        /// userInfo: "atomUUID" (String), "targetThinkspaceId" (String).
        static let moveAtomToThinkspace = Notification.Name("com.cosmo.canvas.moveAtomToThinkspace")

        // Lasso synthesis
        static let lassoEnclosedBlocks = Notification.Name("com.cosmo.canvas.lassoEnclosedBlocks")

        // Zone creation (empty cluster via zone tool)
        static let zoneDrawn = Notification.Name("com.cosmo.canvas.zoneDrawn")

        // Inbox blocks
        static let createInboxBlock = Notification.Name("com.cosmo.canvas.createInboxBlock")
        static let closeInboxBlock = Notification.Name("com.cosmo.canvas.closeInboxBlock")
        static let enterInboxFocusMode = Notification.Name("com.cosmo.canvas.enterInboxFocusMode")
        static let updateInboxBlockPosition = Notification.Name("com.cosmo.canvas.updateInboxBlockPosition")
        static let updateInboxBlockSize = Notification.Name("com.cosmo.canvas.updateInboxBlockSize")
        static let refreshThinkspacePlacements = Notification.Name("com.cosmo.canvas.refreshThinkspacePlacements")
        /// Switch the mounted canvas between its view modes (canvas/library).
        /// userInfo: ["mode": ThinkspaceCanvasMode.rawValue]
        static let setThinkspaceMode = Notification.Name("com.cosmo.canvas.setThinkspaceMode")
    }

    // MARK: - Inbox Notifications
    enum Inbox {
        static let itemAdded = Notification.Name("com.cosmo.inbox.itemAdded")
        static let itemClassified = Notification.Name("com.cosmo.inbox.itemClassified")
        static let itemActioned = Notification.Name("com.cosmo.inbox.itemActioned")
        static let focusInboxItem = Notification.Name("com.cosmo.inbox.focusInboxItem")
        static let focusDatabaseItem = Notification.Name("com.cosmo.inbox.focusDatabaseItem")
        /// ⌥⌘N — navigate to the inbox and put the cursor in the capture field.
        static let focusCaptureField = Notification.Name("com.cosmo.inbox.focusCaptureField")
        static let captureLaneChanged = Notification.Name("com.cosmo.inbox.captureLaneChanged")
        /// Navigate to the inbox queue (Command Center chip, deep links).
        static let open = Notification.Name("com.cosmo.inbox.open")
    }

    // MARK: - Navigation Notifications
    enum Navigation {
        static let navigateToSection = Notification.Name("com.cosmo.nav.navigateToSection")
        static let openEntity = Notification.Name("com.cosmo.nav.openEntity")
        static let openEntityOnCanvas = Notification.Name("com.cosmo.nav.openEntityOnCanvas")
        static let openBlockInFocusMode = Notification.Name("com.cosmo.nav.openBlockInFocusMode")
        /// Step back through the navigation trail (Esc/back from study surfaces).
        static let trailStepBack = Notification.Name("com.cosmo.nav.trailStepBack")
        /// Step forward through the navigation trail.
        static let trailStepForward = Notification.Name("com.cosmo.nav.trailStepForward")
        /// Jump to a trail moment. userInfo: ["momentId": String (UUID)]
        static let trailJump = Notification.Name("com.cosmo.nav.trailJump")
        /// Toggle the unified sidebar from chrome that can't reach MainView's
        /// state directly (the trail-island sidebar button in focus headers).
        static let toggleSidebar = Notification.Name("com.cosmo.nav.toggleSidebar")

        // Focus mode
        static let enterFocusMode = Notification.Name("com.cosmo.nav.enterFocusMode")
        static let exitFocusMode = Notification.Name("com.cosmo.nav.exitFocusMode")
        static let createEntityInFocusMode = Notification.Name("com.cosmo.nav.createEntityInFocusMode")
        static let bringRelatedBlocks = Notification.Name("com.cosmo.nav.bringRelatedBlocks")

        // Thinkspace
        static let switchToThinkspace = Notification.Name("com.cosmo.nav.switchToThinkspace")
        static let navigateToThinkspaceById = Notification.Name("com.cosmo.nav.navigateToThinkspaceById")

        // Command Center
        static let navigateToCommandCenter = Notification.Name("com.cosmo.navigation.commandCenter")
        static let exitDrillIn = Notification.Name("com.cosmo.navigation.exitDrillIn")
        static let openSwipeGallery = Notification.Name("com.cosmo.navigation.openSwipeGallery")
        /// Jump to the Ideas destination. userInfo: ["clientUUID": String] optional —
        /// lands on that client's board when present.
        static let openIdeas = Notification.Name("com.cosmo.navigation.openIdeas")

        // Dimensions
        static let navigateToDimension = Notification.Name("com.cosmo.navigation.dimension")
        static let openDimensionAsPane = Notification.Name("com.cosmo.navigation.dimensionPane")

        // Panes
        static let openAsPane = Notification.Name("com.cosmo.nav.openAsPane")
        /// Peek an entity in the floating Quick Look-style overlay.
        /// userInfo: ["type": EntityType, "id": Int64, "anchor": NSValue(rect:) optional]
        static let peekEntity = Notification.Name("com.cosmo.nav.peekEntity")

        /// Open the Spokes Compiler staging board for a content pillar.
        /// userInfo: ["id": Int64]
        static let compileSpokes = Notification.Name("com.cosmo.nav.compileSpokes")

        /// Fly the current canvas to a saved Place. userInfo: ["placeUUID": String]
        static let jumpToPlace = Notification.Name("com.cosmo.nav.jumpToPlace")

        /// Show a library folder inside the current thinkspace's library mode
        /// (posted when a trail jump lands on a folder moment).
        /// userInfo: ["folderID": UUID] — absent means show the library root.
        static let showLibraryFolder = Notification.Name("com.cosmo.nav.showLibraryFolder")

        // Workbenches
        /// Apply a saved workbench. userInfo: ["uuid": String]
        static let applyWorkbench = Notification.Name("com.cosmo.nav.applyWorkbench")
        /// Open the workbench composer to save the current layout.
        static let composeWorkbench = Notification.Name("com.cosmo.nav.composeWorkbench")
        static let openWebBrowserPane = Notification.Name("com.cosmo.nav.openWebBrowserPane")
        static let openCosmoWindowPane = Notification.Name("com.cosmo.nav.openCosmoWindowPane")
        static let openCollaboratorPane = Notification.Name("com.cosmo.nav.openCollaboratorPane")
        static let openInlineAssistant = Notification.Name("com.cosmo.navigation.openInlineAssistant")
        static let openInlineAssistantPane = Notification.Name("com.cosmo.navigation.openInlineAssistantPane")

        // UI
        static let showSettings = Notification.Name("com.cosmo.nav.showSettings")
        static let showCommandPalette = Notification.Name("com.cosmo.nav.showCommandPalette")
        static let openCalendarWindow = Notification.Name("com.cosmo.nav.openCalendarWindow")
        static let toggleCalendarWindow = Notification.Name("com.cosmo.nav.toggleCalendarWindow")

        struct DimensionPayload {
            let dimension: LevelDimension

            init(dimension: LevelDimension) {
                self.dimension = dimension
            }

            init?(from notification: Notification) {
                guard
                    let rawValue = notification.userInfo?["dimensionId"] as? String,
                    let dimension = LevelDimension(rawValue: rawValue)
                else {
                    return nil
                }
                self.dimension = dimension
            }

            var userInfo: [AnyHashable: Any] {
                ["dimensionId": dimension.rawValue]
            }
        }

        struct ThinkspacePayload {
            let thinkspaceId: String

            init(thinkspaceId: String) {
                self.thinkspaceId = thinkspaceId
            }

            init?(from notification: Notification) {
                guard let thinkspaceId = notification.userInfo?["thinkspaceId"] as? String else {
                    return nil
                }
                self.thinkspaceId = thinkspaceId
            }

            var userInfo: [AnyHashable: Any] {
                ["thinkspaceId": thinkspaceId]
            }
        }

        struct CollaboratorPanePayload {
            let atomUUID: String
            let presetId: String?

            init(atomUUID: String, presetId: String? = nil) {
                self.atomUUID = atomUUID
                self.presetId = presetId
            }

            init?(from notification: Notification) {
                guard let atomUUID = notification.userInfo?["atomUUID"] as? String else {
                    return nil
                }
                self.atomUUID = atomUUID
                self.presetId = notification.userInfo?["presetId"] as? String
            }

            var userInfo: [AnyHashable: Any] {
                var info: [AnyHashable: Any] = ["atomUUID": atomUUID]
                if let presetId {
                    info["presetId"] = presetId
                }
                return info
            }
        }
    }

    // MARK: - Voice Notifications
    enum Voice {
        static let recordingStateChanged = Notification.Name("com.cosmo.voice.recordingStateChanged")
        static let transcription = Notification.Name("com.cosmo.voice.transcription")

        // L1 ASR (Apple Speech)
        static let l1PartialTranscript = Notification.Name("com.cosmo.voice.l1PartialTranscript")
        static let l1FinalTranscript = Notification.Name("com.cosmo.voice.l1FinalTranscript")
        static let l1SpeechStarted = Notification.Name("com.cosmo.voice.l1SpeechStarted")
        static let l1SpeechEnded = Notification.Name("com.cosmo.voice.l1SpeechEnded")

        // L2 ASR (Whisper)
        static let l2ModelLoaded = Notification.Name("com.cosmo.voice.l2ModelLoaded")
        static let l2ModelUnloaded = Notification.Name("com.cosmo.voice.l2ModelUnloaded")
        static let l2TranscriptionProgress = Notification.Name("com.cosmo.voice.l2TranscriptionProgress")
        static let l2TranscriptionComplete = Notification.Name("com.cosmo.voice.l2TranscriptionComplete")

        // Intent detection
        static let asrIntentDetected = Notification.Name("com.cosmo.voice.asrIntentDetected")
        static let dictationProgress = Notification.Name("com.cosmo.voice.dictationProgress")
        static let dictationCommit = Notification.Name("com.cosmo.voice.dictationCommit")
        static let dictationPreview = Notification.Name("com.cosmo.voice.dictationPreview")

        // Hotkey
        static let hotkeyPermissionNeeded = Notification.Name("com.cosmo.voice.hotkeyPermissionNeeded")

        // Ghost cards
        static let ghostCardSpawned = Notification.Name("com.cosmo.voice.ghostCardSpawned")
        static let commitGhostCard = Notification.Name("com.cosmo.voice.commitGhostCard")
        static let ghostCardDismissed = Notification.Name("com.cosmo.voice.ghostCardDismissed")
    }

    // MARK: - Editor Notifications
    enum Editor {
        static let insertTextInEditor = Notification.Name("com.cosmo.editor.insertText")
        static let toggleEditorFormatting = Notification.Name("com.cosmo.editor.toggleFormatting")
        static let insertMentionInEditor = Notification.Name("com.cosmo.editor.insertMention")
        static let performSlashCommand = Notification.Name("com.cosmo.editor.performSlashCommand")
        static let setTypingAttributes = Notification.Name("com.cosmo.editor.setTypingAttributes")
        static let dismissOverlays = Notification.Name("com.cosmo.editor.dismissOverlays")
        static let openMentionAsFloatingBlock = Notification.Name("com.cosmo.editor.openMentionAsFloatingBlock")

        // Undo/Redo
        static let performUndo = Notification.Name("com.cosmo.editor.performUndo")
        static let performRedo = Notification.Name("com.cosmo.editor.performRedo")
    }

    // MARK: - Calendar Notifications
    enum Calendar {
        static let eventCreated = Notification.Name("com.cosmo.calendar.eventCreated")
        static let eventsCreated = Notification.Name("com.cosmo.calendar.eventsCreated")
        static let eventAnimating = Notification.Name("com.cosmo.calendar.eventAnimating")
        static let createEventFromVoice = Notification.Name("com.cosmo.calendar.createEventFromVoice")

        // Event manipulation
        static let expandEvent = Notification.Name("com.cosmo.calendar.expandEvent")
        static let shrinkEvent = Notification.Name("com.cosmo.calendar.shrinkEvent")
        static let moveEvent = Notification.Name("com.cosmo.calendar.moveEvent")
        static let deleteEvent = Notification.Name("com.cosmo.calendar.deleteEvent")
        static let resizeEvent = Notification.Name("com.cosmo.calendar.resizeEvent")
        static let restoreEvent = Notification.Name("com.cosmo.calendar.restoreEvent")
    }

    // MARK: - Entity Notifications
    enum Entity {
        static let created = Notification.Name("com.cosmo.entity.created")
        static let updated = Notification.Name("com.cosmo.entity.updated")
        static let deleted = Notification.Name("com.cosmo.entity.deleted")
        static let modified = Notification.Name("com.cosmo.entity.modified")

        // Entity linking
        static let linkEntities = Notification.Name("com.cosmo.entity.linkEntities")
        static let triggerAutoLink = Notification.Name("com.cosmo.entity.triggerAutoLink")
    }

    // MARK: - Gamification Notifications
    enum Gamification {
        static let taskCompleted = Notification.Name("com.cosmo.gamification.taskCompleted")
    }

    // MARK: - Project Notifications
    enum Project {
        static let created = Notification.Name("com.cosmo.project.created")
        static let updated = Notification.Name("com.cosmo.project.updated")
        static let deleted = Notification.Name("com.cosmo.project.deleted")
        static let restored = Notification.Name("com.cosmo.project.restored")
    }

    // MARK: - Research Notifications
    enum Research {
        static let created = Notification.Name("com.cosmo.research.created")
        static let processingStarted = Notification.Name("com.cosmo.research.processingStarted")
        static let processingProgress = Notification.Name("com.cosmo.research.processingProgress")
        static let processingComplete = Notification.Name("com.cosmo.research.processingComplete")
        static let processingFailed = Notification.Name("com.cosmo.research.processingFailed")
        static let startResearch = Notification.Name("com.cosmo.research.startResearch")
    }

    // MARK: - AI Notifications
    enum AI {
        static let liveFlashTriggered = Notification.Name("com.cosmo.ai.liveFlashTriggered")
        static let liveFlashResults = Notification.Name("com.cosmo.ai.liveFlashResults")

        // Gemini generative synthesis
        static let geminiSynthesisComplete = Notification.Name("com.cosmo.ai.geminiSynthesisComplete")
        static let geminiStreamChunk = Notification.Name("com.cosmo.ai.geminiStreamChunk")
        static let geminiProcessingStarted = Notification.Name("com.cosmo.ai.geminiProcessingStarted")
        static let geminiProcessingCompleted = Notification.Name("com.cosmo.ai.geminiProcessingCompleted")
        static let geminiProcessingFailed = Notification.Name("com.cosmo.ai.geminiProcessingFailed")

        // Retrieval
        static let retrievalRequested = Notification.Name("com.cosmo.ai.retrievalRequested")

        // Ghost text / autocomplete
        static let ghostTextSuggestion = Notification.Name("com.cosmo.ai.ghostTextSuggestion")
        static let ghostTextAccepted = Notification.Name("com.cosmo.ai.ghostTextAccepted")
        static let ghostTextDismissed = Notification.Name("com.cosmo.ai.ghostTextDismissed")

        // Memory management
        static let memoryPressureChanged = Notification.Name("com.cosmo.ai.memoryPressureChanged")
        static let emergencyMemoryUnload = Notification.Name("com.cosmo.ai.emergencyMemoryUnload")
    }

    // MARK: - Intelligence Notifications
    enum Intelligence {
        static let crossReferencesUpdated = Notification.Name("com.cosmo.intelligence.crossReferencesUpdated")
        static let connectionSuggestionsAvailable = Notification.Name("com.cosmo.intelligence.connectionSuggestionsAvailable")
    }

    // MARK: - Glass Overlay Notifications
    enum Glass {
        static let clarificationSelected = Notification.Name("com.cosmo.glass.clarificationSelected")
        static let cardPresented = Notification.Name("com.cosmo.glass.cardPresented")
        static let cardDismissed = Notification.Name("com.cosmo.glass.cardDismissed")
    }

    // MARK: - Sync Notifications
    enum Sync {
        static let uncommittedItemCreated = Notification.Name("com.cosmo.sync.uncommittedItemCreated")
        static let uncommittedItemPromoted = Notification.Name("com.cosmo.sync.uncommittedItemPromoted")
        static let uncommittedItemRestored = Notification.Name("com.cosmo.sync.uncommittedItemRestored")
        /// Posted after cloud atoms are pulled and applied locally.
        /// userInfo: ["atomUUIDs": [String]] — UUIDs of newly created/updated atoms from cloud
        static let atomsPulled = Notification.Name("com.cosmo.sync.atomsPulled")
    }

    // MARK: - NodeGraph Notifications
    enum NodeGraph {
        /// Graph update notifications
        static let graphNodeUpdated = Notification.Name("com.cosmo.nodegraph.nodeUpdated")
        static let graphEdgeUpdated = Notification.Name("com.cosmo.nodegraph.edgeUpdated")
        static let graphRebuilt = Notification.Name("com.cosmo.nodegraph.rebuilt")

        /// Focus context notifications
        static let focusContextChanged = Notification.Name("com.cosmo.nodegraph.focusContextChanged")

        /// Command-K notifications
        static let openCommandK = Notification.Name("com.cosmo.nodegraph.openCommandK")
        static let closeCommandK = Notification.Name("com.cosmo.nodegraph.closeCommandK")
        static let hideCommandK = Notification.Name("com.cosmo.nodegraph.hideCommandK")
        static let openAtomFromCommandK = Notification.Name("com.cosmo.nodegraph.openAtomFromCommandK")
        static let goToObjectFromCommandK = Notification.Name("com.cosmo.nodegraph.goToObjectFromCommandK")

        /// Canvas item management
        static let addToCanvas = Notification.Name("com.cosmo.nodegraph.addToCanvas")

        /// Add item as floating block to the currently active canvas/focus mode
        static let addItemToCurrentCanvas = Notification.Name("com.cosmo.nodegraph.addItemToCurrentCanvas")

        /// A ⌘K result card was dragged out of the palette and released over the
        /// canvas. Posted by the window-level drop catcher (which sits above all
        /// chrome so the drop never gets swallowed by an intervening overlay).
        /// userInfo: `uuids: [String]`, `x: CGFloat`, `y: CGFloat` — the release
        /// point in window space, converted to canvas space by the receiver.
        static let commandKAtomDropOnCanvas = Notification.Name("com.cosmo.nodegraph.commandKAtomDropOnCanvas")
    }

    // MARK: - Telegram Notifications
    enum Telegram {
        /// Content was created or committed via Telegram writing session
        static let contentCreated = Notification.Name("com.cosmo.telegram.contentCreated")
    }

    // MARK: - SwipeFile Notifications
    enum SwipeFile {
        /// Fired when a source type accumulates a multiple of 30 swipes globally.
        /// userInfo: ["sourceType": String, "swipeCount": Int]
        static let batchSwipeAnalysisTriggered = Notification.Name("com.cosmo.swipefile.batchSwipeAnalysisTriggered")

        /// Fired when creator data changes (new creator saved, posts saved, stats updated).
        /// userInfo: ["creatorUUID": String] (optional — nil means reload all)
        static let creatorDataChanged = Notification.Name("com.cosmo.swipefile.creatorDataChanged")

        /// Fired after any swipe library mutation (board membership, saves) so every
        /// library instance and the sidebar counts stay consistent.
        static let libraryDidChange = Notification.Name("com.cosmo.swipefile.libraryDidChange")
    }

    // MARK: - Automation Notifications
    enum Automation {
        /// An automation rule was fired
        static let ruleFired = Notification.Name("com.cosmo.automation.ruleFired")
        /// Begin creating a Flow from a cluster. userInfo: ["clusterId": String]
        static let createFlow = Notification.Name("com.cosmo.automation.createFlow")
        /// An autonomous flow run completed and staged a proposal.
        /// userInfo: ["flowUUID": String, "thinkspaceId": String, "outputAtomUUID": String]
        static let flowDidRun = Notification.Name("com.cosmo.automation.flowDidRun")
        /// An automation rule was created
        static let ruleCreated = Notification.Name("com.cosmo.automation.ruleCreated")
        /// An automation rule was updated (enabled/disabled, edited)
        static let ruleUpdated = Notification.Name("com.cosmo.automation.ruleUpdated")
        /// An automation rule was deleted
        static let ruleDeleted = Notification.Name("com.cosmo.automation.ruleDeleted")
        /// Deferred spatial actions are ready to execute on a thinkspace
        static let deferredActionsReady = Notification.Name("com.cosmo.automation.deferredActionsReady")
    }

    // MARK: - Smart Template Notifications
    enum Template {
        /// A template instance was created (spawned)
        static let instantiated = Notification.Name("com.cosmo.template.instantiated")
        /// A template button was pressed
        static let buttonPressed = Notification.Name("com.cosmo.template.buttonPressed")
        /// A template instance field value was updated
        static let fieldUpdated = Notification.Name("com.cosmo.template.fieldUpdated")
        /// Open template builder to edit a template definition
        static let editTemplate = Notification.Name("com.cosmo.template.editTemplate")
    }

    // MARK: - Daemon Notifications
    enum Daemon {
        static let connected = Notification.Name("com.cosmo.daemon.connected")
        static let disconnected = Notification.Name("com.cosmo.daemon.disconnected")
        static let statusUpdated = Notification.Name("com.cosmo.daemon.statusUpdated")
        static let setupFailed = Notification.Name("com.cosmo.daemon.setupFailed")
        static let setupComplete = Notification.Name("com.cosmo.daemon.setupComplete")
    }

    // MARK: - Scheduler Notifications (Plan/Today Mode)
    enum Scheduler {
        // Block lifecycle
        static let blockCreated = Notification.Name("com.cosmo.scheduler.blockCreated")
        static let blockUpdated = Notification.Name("com.cosmo.scheduler.blockUpdated")
        static let blockDeleted = Notification.Name("com.cosmo.scheduler.blockDeleted")
        static let blockCompleted = Notification.Name("com.cosmo.scheduler.blockCompleted")
        static let blockSelected = Notification.Name("com.cosmo.scheduler.blockSelected")

        // Mode switching
        static let modeChanged = Notification.Name("com.cosmo.scheduler.modeChanged")
        static let dateChanged = Notification.Name("com.cosmo.scheduler.dateChanged")

        // Drawer state
        static let drawerOpened = Notification.Name("com.cosmo.scheduler.drawerOpened")
        static let drawerClosed = Notification.Name("com.cosmo.scheduler.drawerClosed")

        // Voice command notifications (received from ActionRegistry)
        static let voiceCreateBlock = Notification.Name("com.cosmo.scheduler.voiceCreateBlock")
        static let voiceSwitchMode = Notification.Name("com.cosmo.scheduler.voiceSwitchMode")
        static let voiceNavigateDate = Notification.Name("com.cosmo.scheduler.voiceNavigateDate")
        static let voiceResizeBlock = Notification.Name("com.cosmo.scheduler.voiceResizeBlock")
        static let voiceMoveBlock = Notification.Name("com.cosmo.scheduler.voiceMoveBlock")
        static let voiceDeleteBlock = Notification.Name("com.cosmo.scheduler.voiceDeleteBlock")
        static let voiceCompleteBlock = Notification.Name("com.cosmo.scheduler.voiceCompleteBlock")

        // Data refresh
        static let dataRefreshed = Notification.Name("com.cosmo.scheduler.dataRefreshed")
        static let requestRefresh = Notification.Name("com.cosmo.scheduler.requestRefresh")
    }

    // MARK: - Cosmo Window Notifications
    enum CosmoWindow {
        static let toggle = Notification.Name("com.cosmo.window.toggle")
        static let contextChanged = Notification.Name("com.cosmo.window.contextChanged")
    }

    // MARK: - Atom Window Notifications (Floating Atom Viewer)
    enum AtomWindow {
        /// Toggle the floating atom viewer panel
        static let toggle = Notification.Name("com.cosmo.atomWindow.toggle")
        /// Open a specific atom in the floating viewer — userInfo: ["uuid": String]
        static let openAtom = Notification.Name("com.cosmo.atomWindow.openAtom")
    }

    // MARK: - Inquiry Workspace Notifications
    /// Mastery engine: Deep Dive + Inquiry Session lifecycle, captures, branches, crystallization.
    enum Inquiry {
        /// Open a Deep Dive Overview for the given atom UUID — userInfo: ["uuid": String]
        static let openDeepDive = Notification.Name("com.cosmo.inquiry.openDeepDive")
        /// Start an Inquiry Session anchored to an object — userInfo: ["anchorUUID": String, "anchorType": String]
        static let startInquiry = Notification.Name("com.cosmo.inquiry.startInquiry")
        /// Inquiry Session became active — userInfo: ["sessionUUID": String, "deepDiveUUID": String?]
        static let sessionStarted = Notification.Name("com.cosmo.inquiry.sessionStarted")
        /// Inquiry Session paused/closed — userInfo: ["sessionUUID": String]
        static let sessionEnded = Notification.Name("com.cosmo.inquiry.sessionEnded")
        /// Inquiry Session was crystallized — userInfo: ["sessionUUID": String]
        static let sessionCrystallized = Notification.Name("com.cosmo.inquiry.sessionCrystallized")
        /// A Telegram/voice capture was routed to an active inquiry — userInfo: ["sessionUUID": String, "captureId": String]
        static let captureRoutedToSession = Notification.Name("com.cosmo.inquiry.captureRoutedToSession")
        /// The Deep Dive's concept seedbed changed (accrual/tidy/pin/develop) — userInfo: ["deepDiveUUID": String]
        static let seedbedChanged = Notification.Name("com.cosmo.inquiry.seedbedChanged")
        /// Background cartographer detected a breakthrough — userInfo: ["sessionUUID": String, "summary": String]
        static let breakthroughDetected = Notification.Name("com.cosmo.inquiry.breakthroughDetected")
        /// Background cartographer detected a candidate term — userInfo: ["sessionUUID": String, "term": String]
        static let extractedQuestion = Notification.Name("com.cosmo.inquiry.extractedQuestion")
        /// Add an extract to the active Inquiry Workspace — userInfo: ["extractUUID": String]
        static let addExtractToInquiry = Notification.Name("com.cosmo.inquiry.addExtractToInquiry")
        /// Lexicon entry maturity changed — userInfo: ["lexiconUUID": String, "newMaturity": String]
        static let maturityProgressed = Notification.Name("com.cosmo.inquiry.maturityProgressed")
        /// Crystallize the active session — no payload
        static let crystallizeActive = Notification.Name("com.cosmo.inquiry.crystallizeActive")
        /// Switch the active Inquiry Workspace layout — userInfo: LayoutPayload
        static let layoutRequested = Notification.Name("com.cosmo.inquiry.layoutRequested")
        /// Focus the active Inquiry Workspace thinking dock — no payload
        static let focusThinkingDock = Notification.Name("com.cosmo.inquiry.focusThinkingDock")
        /// Refresh Source Radar for the active Inquiry Workspace — no payload
        static let refreshSources = Notification.Name("com.cosmo.inquiry.refreshSources")
    }

    // MARK: - Connection (concept page) Notifications
    enum Connection {
        /// A concept was minted or linked from within another concept — open
        /// hosts refresh their link targets so mentions light up immediately.
        /// userInfo: ["originUUID": String, "connectionUUID": String]
        static let referencesChanged = Notification.Name("com.cosmo.connection.referencesChanged")
        /// A staged insert was added to / removed from a page's pending
        /// material (inbox feed, seedling develop-into-existing) — open
        /// workspaces refresh their ghost rows.
        /// userInfo: ["connectionUUID": String]
        static let stagedInsertsChanged = Notification.Name("com.cosmo.connection.stagedInsertsChanged")
    }
}

// MARK: - Type-Safe Payloads

extension CosmoNotification.Inquiry {
    struct LayoutPayload {
        let mode: InquiryLayoutMode

        var userInfo: [AnyHashable: Any] {
            ["mode": mode.rawValue]
        }

        init(mode: InquiryLayoutMode) {
            self.mode = mode
        }

        init?(from notification: Notification) {
            guard let rawMode = notification.userInfo?["mode"] as? String,
                  let mode = InquiryLayoutMode(rawValue: rawMode) else { return nil }
            self.mode = mode
        }
    }
}

extension CosmoNotification.Canvas {

    struct BlockExpandedPayload {
        let blockId: String

        var userInfo: [AnyHashable: Any] {
            ["blockId": blockId]
        }

        init(blockId: String) {
            self.blockId = blockId
        }

        init?(from notification: Notification) {
            guard let blockId = notification.userInfo?["blockId"] as? String else { return nil }
            self.blockId = blockId
        }
    }

    struct BlockPositionPayload {
        let blockId: String
        let position: CGPoint

        var userInfo: [AnyHashable: Any] {
            ["blockId": blockId, "position": position]
        }

        init(blockId: String, position: CGPoint) {
            self.blockId = blockId
            self.position = position
        }

        init?(from notification: Notification) {
            guard let blockId = notification.userInfo?["blockId"] as? String,
                  let position = notification.userInfo?["position"] as? CGPoint else { return nil }
            self.blockId = blockId
            self.position = position
        }
    }

    struct BlockSizePayload {
        let blockId: String
        let size: CGSize

        var userInfo: [AnyHashable: Any] {
            ["blockId": blockId, "size": size]
        }

        init(blockId: String, size: CGSize) {
            self.blockId = blockId
            self.size = size
        }

        init?(from notification: Notification) {
            guard let blockId = notification.userInfo?["blockId"] as? String,
                  let size = notification.userInfo?["size"] as? CGSize else { return nil }
            self.blockId = blockId
            self.size = size
        }
    }

    struct PlaceBlocksPayload {
        let query: String
        let entityType: String
        let quantity: Int
        let layout: String

        var userInfo: [AnyHashable: Any] {
            ["query": query, "entityType": entityType, "quantity": quantity, "layout": layout]
        }

        init(query: String, entityType: String, quantity: Int, layout: String = "orbital") {
            self.query = query
            self.entityType = entityType
            self.quantity = quantity
            self.layout = layout
        }

        init?(from notification: Notification) {
            guard let query = notification.userInfo?["query"] as? String,
                  let entityType = notification.userInfo?["entityType"] as? String,
                  let quantity = notification.userInfo?["quantity"] as? Int else { return nil }
            self.query = query
            self.entityType = entityType
            self.quantity = quantity
            self.layout = notification.userInfo?["layout"] as? String ?? "orbital"
        }
    }

    /// Payload for toggling block pin state
    struct ToggleBlockPinPayload {
        let blockId: String
        /// Optional: explicitly set pin state (nil = toggle)
        let isPinned: Bool?

        var userInfo: [AnyHashable: Any] {
            var info: [AnyHashable: Any] = ["blockId": blockId]
            if let isPinned = isPinned { info["isPinned"] = isPinned }
            return info
        }

        init(blockId: String, isPinned: Bool? = nil) {
            self.blockId = blockId
            self.isPinned = isPinned
        }

        init?(from notification: Notification) {
            guard let blockId = notification.userInfo?["blockId"] as? String else { return nil }
            self.blockId = blockId
            self.isPinned = notification.userInfo?["isPinned"] as? Bool
        }
    }
}

extension CosmoNotification.Navigation {

    struct EntityPayload {
        let type: String
        let id: Int64

        var userInfo: [AnyHashable: Any] {
            ["type": type, "id": id]
        }

        init(type: String, id: Int64) {
            self.type = type
            self.id = id
        }

        init?(from notification: Notification) {
            guard let type = notification.userInfo?["type"] as? String,
                  let id = notification.userInfo?["id"] as? Int64 else { return nil }
            self.type = type
            self.id = id
        }
    }

    struct FocusModePayload {
        let type: String
        let id: Int64
        let position: CGPoint?
        let content: String?
        let title: String?

        var userInfo: [AnyHashable: Any] {
            var info: [AnyHashable: Any] = ["type": type, "id": id]
            if let position = position { info["position"] = position }
            if let content = content { info["content"] = content }
            if let title = title { info["title"] = title }
            return info
        }

        init(type: String, id: Int64, position: CGPoint? = nil, content: String? = nil, title: String? = nil) {
            self.type = type
            self.id = id
            self.position = position
            self.content = content
            self.title = title
        }

        init?(from notification: Notification) {
            guard let type = notification.userInfo?["type"] as? String,
                  let id = notification.userInfo?["id"] as? Int64 else { return nil }
            self.type = type
            self.id = id
            self.position = notification.userInfo?["position"] as? CGPoint
            self.content = notification.userInfo?["content"] as? String
            self.title = notification.userInfo?["title"] as? String
        }
    }
}

extension CosmoNotification.Voice {

    struct RecordingStatePayload {
        let isRecording: Bool

        var userInfo: [AnyHashable: Any] {
            ["isRecording": isRecording]
        }

        init(isRecording: Bool) {
            self.isRecording = isRecording
        }

        init?(from notification: Notification) {
            guard let isRecording = notification.userInfo?["isRecording"] as? Bool else { return nil }
            self.isRecording = isRecording
        }
    }

    struct TranscriptPayload {
        let text: String
        let isFinal: Bool

        var userInfo: [AnyHashable: Any] {
            ["text": text, "isFinal": isFinal]
        }

        init(text: String, isFinal: Bool = false) {
            self.text = text
            self.isFinal = isFinal
        }

        init?(from notification: Notification) {
            guard let text = notification.userInfo?["text"] as? String else { return nil }
            self.text = text
            self.isFinal = notification.userInfo?["isFinal"] as? Bool ?? false
        }
    }
}

// MARK: - Convenience Posting

extension NotificationCenter {
    /// Post a notification with a type-safe payload
    func post<T>(_ name: Notification.Name, payload: T) where T: NotificationPayload {
        post(name: name, object: nil, userInfo: payload.userInfo)
    }
}

/// Protocol for type-safe notification payloads
protocol NotificationPayload {
    var userInfo: [AnyHashable: Any] { get }
}

extension CosmoNotification.Canvas.BlockExpandedPayload: NotificationPayload {}
extension CosmoNotification.Canvas.BlockPositionPayload: NotificationPayload {}
extension CosmoNotification.Canvas.BlockSizePayload: NotificationPayload {}
extension CosmoNotification.Canvas.PlaceBlocksPayload: NotificationPayload {}
extension CosmoNotification.Canvas.ToggleBlockPinPayload: NotificationPayload {}
extension CosmoNotification.Navigation.EntityPayload: NotificationPayload {}
extension CosmoNotification.Navigation.FocusModePayload: NotificationPayload {}
extension CosmoNotification.Inquiry.LayoutPayload: NotificationPayload {}
extension CosmoNotification.Voice.RecordingStatePayload: NotificationPayload {}
extension CosmoNotification.Voice.TranscriptPayload: NotificationPayload {}

// MARK: - Migrated Notification Extensions
// (Moved from deleted XPTracerView.swift and ActiveFocusBar.swift)

extension Notification.Name {
    public static let focusSessionStarted = Notification.Name("focusSessionStarted")
    public static let focusSessionPaused = Notification.Name("focusSessionPaused")
    public static let focusSessionCompleted = Notification.Name("focusSessionCompleted")
    public static let atomsDidChange = Notification.Name("com.cosmo.atomsDidChange")

    /// Posted just before the app terminates so active focus modes can flush pending saves synchronously.
    public static let cosmoAppWillTerminate = Notification.Name("com.cosmo.appWillTerminate")
}

enum CosmoAssistantHotkeyRouter {
    @MainActor
    static func openFromOptionA(
        notificationCenter: NotificationCenter = .default,
        activateApp: Bool = true
    ) {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = NSApp.mainWindow {
                mainWindow.makeKeyAndOrderFront(nil)
            } else {
                let visibleWindow = NSApp.windows.first { $0.isVisible && !$0.isMiniaturized }
                visibleWindow?.makeKeyAndOrderFront(nil)
            }
        }

        notificationCenter.post(
            name: CosmoNotification.Navigation.openInlineAssistant,
            object: nil
        )
    }
}

// MARK: - Persistence Health

/// Central, app-wide channel for persistence failures, decode corruption, and write conflicts.
/// Write paths report here instead of swallowing errors with `try?`/print-only catches,
/// so the UI can surface "save failed" instead of silently losing data.
@MainActor
@Observable
final class PersistenceHealth {
    static let shared = PersistenceHealth()

    enum IncidentKind: String {
        case writeFailure
        case decodeFailure
        case conflict
        case syncFailure
        /// A self-healing pass SUCCEEDED (e.g. the orphaned-pending reconciler
        /// re-enqueued stranded rows). Logged for observability, but never a
        /// user-facing failure — the banner only surfaces write/sync failures.
        case recovery
    }

    struct Incident: Identifiable {
        let id = UUID()
        let kind: IncidentKind
        let context: String
        let detail: String
        let date = Date()
    }

    /// Posted whenever an incident is recorded. userInfo: ["kind": String, "context": String]
    static let incidentRecorded = Notification.Name("com.cosmo.persistence.incidentRecorded")

    private(set) var incidents: [Incident] = []
    private(set) var counts: [IncidentKind.RawValue: Int] = [:]

    /// Dedupe window: identical kind+context incidents within this interval are
    /// counted but not re-logged/re-notified, so a corrupt atom rendered in a
    /// list can't flood the log or the UI.
    private var lastSeen: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 10

    /// Most recent write failure — drives the save-failure banner.
    var latestWriteFailure: Incident? {
        incidents.last { $0.kind == .writeFailure || $0.kind == .syncFailure }
    }

    private init() {}

    func record(_ kind: IncidentKind, context: String, detail: String) {
        counts[kind.rawValue, default: 0] += 1

        let dedupeKey = "\(kind.rawValue)|\(context)"
        let now = Date()
        if let last = lastSeen[dedupeKey], now.timeIntervalSince(last) < dedupeWindow {
            return
        }
        lastSeen[dedupeKey] = now

        let incident = Incident(kind: kind, context: context, detail: detail)
        incidents.append(incident)
        if incidents.count > 200 { incidents.removeFirst(incidents.count - 200) }
        print("🛑 [PersistenceHealth] \(kind.rawValue) — \(context): \(detail)")
        NotificationCenter.default.post(
            name: Self.incidentRecorded,
            object: nil,
            userInfo: ["kind": kind.rawValue, "context": context]
        )
    }

    /// Report from any isolation context — hops to the main actor.
    nonisolated static func note(_ kind: IncidentKind, context: String, detail: String) {
        Task { @MainActor in
            PersistenceHealth.shared.record(kind, context: context, detail: detail)
        }
    }
}

// MARK: - Dirty Editor Registry

/// Registry of synchronous flush closures for surfaces holding unsaved (debounced) edits.
/// Each editing surface registers on appear and unregisters on disappear; the app's
/// willTerminate handler calls `flushAll()` synchronously so debounced edits are never
/// lost on quit. Flush closures must be synchronous and DB-only (no network).
@MainActor
final class DirtyEditorRegistry {
    static let shared = DirtyEditorRegistry()

    private var flushers: [String: () -> Void] = [:]

    private init() {}

    /// Register a synchronous flush closure for an editing surface.
    /// `id` should be stable per surface instance (e.g. "sticky-<blockId>", "note-<uuid>").
    func register(id: String, flush: @escaping () -> Void) {
        flushers[id] = flush
    }

    func unregister(id: String) {
        flushers.removeValue(forKey: id)
    }

    /// Flush every registered surface synchronously. Called at app termination
    /// (before `.cosmoAppWillTerminate` is posted) and safe to call at any time.
    func flushAll() {
        guard !flushers.isEmpty else { return }
        print("💾 [DirtyEditorRegistry] flushing \(flushers.count) surface(s)")
        for (_, flush) in flushers {
            flush()
        }
    }
}

// MARK: - Legacy Compatibility Note
// The CosmoNotification enum provides namespaced notification names (e.g., CosmoNotification.Canvas.blockExpanded).
// Legacy notification names are scattered across the codebase in various extension Notification.Name blocks.
// These include:
//   - VoiceNotifications.swift: voiceRecordingStateChanged, exitFocusMode, showSettings, showCommandPalette, etc.
//   - CanvasView.swift: enterFocusMode, toggleBlockPin, duplicateBlock, removeBlock, etc.
//   - CosmoApp.swift: performUndo, performRedo, toggleCalendarWindow
//   - MainView.swift: createEntityAtPosition, createCosmoAIBlock, createInboxBlock, etc.
//
// New code should prefer CosmoNotification.* namespaced names for better organization.
// Legacy names are kept for backwards compatibility - do not add duplicate declarations here.
