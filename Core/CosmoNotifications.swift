// CosmoOS/Core/CosmoNotifications.swift
// Unified notification system for CosmoOS
// All notification names in one place with type-safe payloads

import Foundation
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

    // MARK: - Canvas Notifications
    enum Canvas {
        // Block lifecycle
        static let blockExpanded = Notification.Name("com.cosmo.canvas.blockExpanded")
        static let blockCollapsed = Notification.Name("com.cosmo.canvas.blockCollapsed")
        static let blockSelected = Notification.Name("com.cosmo.canvas.blockSelected")
        static let blockDeselected = Notification.Name("com.cosmo.canvas.blockDeselected")

        // Block manipulation
        static let removeBlock = Notification.Name("com.cosmo.canvas.removeBlock")
        static let duplicateBlock = Notification.Name("com.cosmo.canvas.duplicateBlock")
        static let toggleBlockPin = Notification.Name("com.cosmo.canvas.toggleBlockPin")
        static let blurAllBlocks = Notification.Name("com.cosmo.canvas.blurAllBlocks")
        static let collapseExpandedBlock = Notification.Name("com.cosmo.canvas.collapseExpandedBlock")

        // Block position/size
        static let updateBlockPosition = Notification.Name("com.cosmo.canvas.updateBlockPosition")
        static let updateBlockSize = Notification.Name("com.cosmo.canvas.updateBlockSize")
        static let saveBlockSize = Notification.Name("com.cosmo.canvas.saveBlockSize")
        static let updateBlockContent = Notification.Name("com.cosmo.canvas.updateBlockContent")
        static let updateBlockMetadata = Notification.Name("com.cosmo.canvas.updateBlockMetadata")

        // Canvas state
        static let blocksChanged = Notification.Name("com.cosmo.canvas.blocksChanged")
        static let arrangeBlocks = Notification.Name("com.cosmo.canvas.arrangeBlocks")
        static let placeBlocksOnCanvas = Notification.Name("com.cosmo.canvas.placeBlocksOnCanvas")
        static let placeEntityOnCanvas = Notification.Name("com.cosmo.canvas.placeEntityOnCanvas")
        static let moveCanvasBlocks = Notification.Name("com.cosmo.canvas.moveBlocks")

        // Block creation
        static let createNoteBlock = Notification.Name("com.cosmo.canvas.createNoteBlock")
        static let createResearchBlock = Notification.Name("com.cosmo.canvas.createResearchBlock")
        static let createCosmoAIBlock = Notification.Name("com.cosmo.canvas.createCosmoAIBlock")
        static let createEntityAtPosition = Notification.Name("com.cosmo.canvas.createEntityAtPosition")

        // Smart actions (content-based)
        static let moveBlockByContentToTime = Notification.Name("com.cosmo.canvas.moveBlockByContentToTime")
        static let deleteBlockByContent = Notification.Name("com.cosmo.canvas.deleteBlockByContent")
        static let expandBlockByContent = Notification.Name("com.cosmo.canvas.expandBlockByContent")
        static let duplicateBlockByContent = Notification.Name("com.cosmo.canvas.duplicateBlockByContent")

        // Smart actions (by ID)
        static let moveBlockToTime = Notification.Name("com.cosmo.canvas.moveBlockToTime")
        static let deleteSpecificBlock = Notification.Name("com.cosmo.canvas.deleteSpecificBlock")
        static let resizeSelectedBlock = Notification.Name("com.cosmo.canvas.resizeSelectedBlock")
        static let expandSelectedBlock = Notification.Name("com.cosmo.canvas.expandSelectedBlock")
        static let collapseSelectedBlock = Notification.Name("com.cosmo.canvas.collapseSelectedBlock")
        static let duplicateSelectedBlock = Notification.Name("com.cosmo.canvas.duplicateSelectedBlock")
        static let closeSelectedBlock = Notification.Name("com.cosmo.canvas.closeSelectedBlock")

        // Inbox blocks
        static let createInboxBlock = Notification.Name("com.cosmo.canvas.createInboxBlock")
        static let closeInboxBlock = Notification.Name("com.cosmo.canvas.closeInboxBlock")
        static let enterInboxFocusMode = Notification.Name("com.cosmo.canvas.enterInboxFocusMode")
        static let updateInboxBlockPosition = Notification.Name("com.cosmo.canvas.updateInboxBlockPosition")
        static let updateInboxBlockSize = Notification.Name("com.cosmo.canvas.updateInboxBlockSize")
    }

    // MARK: - Navigation Notifications
    enum Navigation {
        static let navigateToSection = Notification.Name("com.cosmo.nav.navigateToSection")
        static let openEntity = Notification.Name("com.cosmo.nav.openEntity")
        static let openEntityOnCanvas = Notification.Name("com.cosmo.nav.openEntityOnCanvas")
        static let openBlockInFocusMode = Notification.Name("com.cosmo.nav.openBlockInFocusMode")

        // Focus mode
        static let enterFocusMode = Notification.Name("com.cosmo.nav.enterFocusMode")
        static let exitFocusMode = Notification.Name("com.cosmo.nav.exitFocusMode")
        static let createEntityInFocusMode = Notification.Name("com.cosmo.nav.createEntityInFocusMode")
        static let bringRelatedBlocks = Notification.Name("com.cosmo.nav.bringRelatedBlocks")

        // Thinkspace
        static let switchToThinkspace = Notification.Name("com.cosmo.nav.switchToThinkspace")

        // UI
        static let showSettings = Notification.Name("com.cosmo.nav.showSettings")
        static let showCommandPalette = Notification.Name("com.cosmo.nav.showCommandPalette")
        static let openCalendarWindow = Notification.Name("com.cosmo.nav.openCalendarWindow")
        static let toggleCalendarWindow = Notification.Name("com.cosmo.nav.toggleCalendarWindow")
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
        static let hotContextUpdated = Notification.Name("com.cosmo.ai.hotContextUpdated")
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
        static let openAtomFromCommandK = Notification.Name("com.cosmo.nodegraph.openAtomFromCommandK")
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
}

// MARK: - Type-Safe Payloads

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
extension CosmoNotification.Voice.RecordingStatePayload: NotificationPayload {}
extension CosmoNotification.Voice.TranscriptPayload: NotificationPayload {}

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
