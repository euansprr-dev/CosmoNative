// CosmoOS/Scheduler/SchedulerEngine.swift
// Central state management and business logic for the Cosmo Scheduler
//
// Design Philosophy:
// - Single source of truth for all schedule data
// - Optimistic UI updates with background persistence
// - Voice command integration via NotificationCenter
// - Seamless mode switching without data reload
// - Efficient week/day filtering with caching

import Foundation
import GRDB
import Combine
import SwiftUI

// MARK: - Scheduler Mode

/// The two primary viewing modes
public enum SchedulerMode: String, CaseIterable, Identifiable {
    case plan   // Visual weekly planner
    case today  // Action-focused list

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plan: return "Plan"
        case .today: return "Today"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "calendar"
        case .today: return "checkmark.circle"
        }
    }
}

// MARK: - Editor State

/// State for inline block editor
public struct SchedulerEditorState: Equatable {
    public enum Mode: Equatable {
        case create(proposedStart: Date?, proposedEnd: Date?)
        case edit(block: ScheduleBlock)
    }

    public enum Style: Equatable {
        case modal      // Full overlay with dimming (for editing, click-to-create)
        case popover    // Lightweight popover near button (for quick add)
    }

    let mode: Mode
    let anchorPoint: CGPoint?  // Screen position for editor placement
    let style: Style           // How the editor should appear

    init(mode: Mode, anchorPoint: CGPoint?, style: Style = .modal) {
        self.mode = mode
        self.anchorPoint = anchorPoint
        self.style = style
    }

    var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    var existingBlock: ScheduleBlock? {
        if case .edit(let block) = mode { return block }
        return nil
    }

    var isPopover: Bool {
        style == .popover
    }
}

// MARK: - Time Period

/// Time period for filtering
public enum SchedulerTimePeriod: Equatable {
    case today
    case tomorrow
    case thisWeek
    case custom(start: Date, end: Date)

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let start = calendar.startOfDay(for: tomorrow)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .thisWeek:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            return (weekStart, weekEnd)

        case .custom(let start, let end):
            return (start, end)
        }
    }
}

// MARK: - Scheduler Engine

/// The brain of the Cosmo Scheduler - manages all state and operations
@MainActor
public final class SchedulerEngine: ObservableObject {

    // MARK: - Shared Instance

    /// Shared instance for voice commands and global access
    public static let shared = SchedulerEngine()

    // MARK: - Published State

    /// Current viewing mode (plan/today)
    @Published public var mode: SchedulerMode = .today

    /// All blocks for the currently visible period (unfiltered cache)
    @Published public private(set) var allBlocks: [ScheduleBlock] = []

    /// Currently selected date (affects visible week/day)
    @Published public var selectedDate: Date = Date()

    /// Currently selected block (for editing, context drawer)
    @Published public var selectedBlock: ScheduleBlock?

    /// Editor state (nil when editor closed)
    @Published public var editorState: SchedulerEditorState?

    /// Whether context drawer is visible
    @Published public var isDrawerOpen: Bool = false

    /// Loading state
    @Published public var isLoading: Bool = false

    /// Error state
    @Published public var error: String?

    // MARK: - Computed Properties

    /// Blocks for the currently selected week (for Plan Mode)
    public var weekBlocks: [ScheduleBlock] {
        let weekRange = weekDateRange
        return allBlocks.filter { block in
            guard let start = block.startTime else { return false }
            return start >= weekRange.start && start < weekRange.end
        }
    }

    /// Blocks grouped by day of week (0 = Sunday through 6 = Saturday)
    public var blocksByDayOfWeek: [Int: [ScheduleBlock]] {
        var grouped: [Int: [ScheduleBlock]] = [:]
        for block in weekBlocks {
            guard let dayIndex = block.dayOfWeek else { continue }
            if grouped[dayIndex] == nil { grouped[dayIndex] = [] }
            grouped[dayIndex]?.append(block)
        }
        return grouped
    }

    /// Blocks for today only (for Today Mode)
    public var todayBlocks: [ScheduleBlock] {
        let today = Calendar.current.startOfDay(for: selectedDate)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        return allBlocks.filter { block in
            // Include unscheduled tasks with focusDate = today
            if !block.isScheduled {
                if let focusDateString = block.notes, focusDateString.contains("focusDate") {
                    // Parse focusDate from notes (simplified)
                    return true
                }
                // Include unscheduled tasks in today mode
                return block.blockType == .task && !block.isCompleted
            }

            guard let start = block.startTime else { return false }
            return start >= today && start < tomorrow
        }.sorted { a, b in
            // Sort: scheduled first, then by time, then by priority
            if a.isScheduled != b.isScheduled {
                return a.isScheduled
            }
            if let aStart = a.startTime, let bStart = b.startTime, aStart != bStart {
                return aStart < bStart
            }
            return a.priority.sortOrder < b.priority.sortOrder
        }
    }

    /// Today's blocks grouped by time period
    public var todayBlocksByPeriod: (morning: [ScheduleBlock], afternoon: [ScheduleBlock], evening: [ScheduleBlock], unscheduled: [ScheduleBlock]) {
        var morning: [ScheduleBlock] = []
        var afternoon: [ScheduleBlock] = []
        var evening: [ScheduleBlock] = []
        var unscheduled: [ScheduleBlock] = []

        for block in todayBlocks {
            guard let hour = block.hourOfDay else {
                unscheduled.append(block)
                continue
            }

            if hour < 12 {
                morning.append(block)
            } else if hour < 17 {
                afternoon.append(block)
            } else {
                evening.append(block)
            }
        }

        return (morning, afternoon, evening, unscheduled)
    }

    /// Start date of currently visible week
    public var weekStartDate: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
    }

    /// Date range for current week
    public var weekDateRange: (start: Date, end: Date) {
        let start = weekStartDate
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }

    /// Array of dates for current week (for header rendering)
    public var weekDates: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStartDate) }
    }

    /// Progress for today (completed / total)
    public var todayProgress: (completed: Int, total: Int) {
        let completable = todayBlocks.filter { $0.blockType.supportsCompletion }
        let completed = completable.filter { $0.isCompleted }.count
        return (completed, completable.count)
    }

    /// Progress percentage for today (0-1)
    public var todayProgressPercentage: Double {
        let (completed, total) = todayProgress
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    // MARK: - Private Properties

    private let database: CosmoDatabase
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    // Voice action history for undo/redo
    private var lastCreatedBlockUuid: String?

    // MARK: - Initialization

    init(database: CosmoDatabase? = nil) {
        self.database = database ?? CosmoDatabase.shared
        setupNotificationObservers()
        Task { await loadBlocks() }
    }

    // MARK: - Data Loading

    /// Load blocks for the extended date range (±3 months for smooth navigation)
    public func loadBlocks() async {
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            isLoading = true
            error = nil

            do {
                let calendar = Calendar.current
                let rangeStart = calendar.date(byAdding: .month, value: -1, to: selectedDate)!
                let rangeEnd = calendar.date(byAdding: .month, value: 2, to: selectedDate)!

                let startString = ISO8601DateFormatter().string(from: rangeStart)
                let endString = ISO8601DateFormatter().string(from: rangeEnd)

                let blocks: [ScheduleBlock] = try await database.asyncRead { db in
                    try ScheduleBlock
                        .filter(Column("is_deleted") == false)
                        .filter(
                            // Scheduled blocks in range
                            (Column("start_time") >= startString && Column("start_time") < endString) ||
                            // OR unscheduled incomplete tasks
                            (Column("start_time") == nil && Column("is_completed") == false && Column("block_type") == "task")
                        )
                        .order(Column("start_time").asc)
                        .fetchAll(db)
                }

                guard !Task.isCancelled else { return }

                withAnimation(SchedulerSprings.standard) {
                    self.allBlocks = blocks
                }

                isLoading = false

            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isLoading = false
                print("❌ SchedulerEngine load error: \(error)")
            }
        }
    }

    /// Refresh blocks (force reload)
    public func refresh() async {
        await loadBlocks()
    }

    // MARK: - CRUD Operations

    /// Create a new block
    @discardableResult
    public func createBlock(_ block: ScheduleBlock) async throws -> ScheduleBlock {
        var newBlock = block
        newBlock.createdAt = Date()
        newBlock.updatedAt = Date()
        newBlock.localVersion = 1

        // Optimistic UI update
        withAnimation(SchedulerSprings.blockCreate) {
            allBlocks.append(newBlock)
            allBlocks = ScheduleBlock.sortForDisplay(allBlocks)
        }

        // Persist to database
        do {
            // Capture by value for async context
            let blockToSave = newBlock
            let savedBlock = try await database.asyncWrite { db -> ScheduleBlock in
                var insertingBlock = blockToSave
                try insertingBlock.insert(db)
                insertingBlock.databaseId = db.lastInsertedRowID
                return insertingBlock
            }

            // Update with persisted ID
            if let index = allBlocks.firstIndex(where: { $0.uuid == newBlock.uuid }) {
                allBlocks[index] = savedBlock
            }

            // Track for undo
            lastCreatedBlockUuid = savedBlock.uuid

            // Post notification for voice system
            NotificationCenter.default.post(
                name: .scheduleBlockCreated,
                object: nil,
                userInfo: ["block": savedBlock, "uuid": savedBlock.uuid]
            )

            print("✅ Created schedule block: \(savedBlock.title)")
            return savedBlock

        } catch {
            // Rollback optimistic update
            withAnimation(SchedulerSprings.blockDelete) {
                allBlocks.removeAll { $0.uuid == newBlock.uuid }
            }
            throw error
        }
    }

    /// Update an existing block
    public func updateBlock(_ block: ScheduleBlock) async throws {
        var updatedBlock = block
        updatedBlock.updatedAt = Date()
        updatedBlock.localVersion += 1

        // Optimistic UI update
        if let index = allBlocks.firstIndex(where: { $0.uuid == block.uuid }) {
            withAnimation(SchedulerSprings.standard) {
                allBlocks[index] = updatedBlock
            }
        }

        // Update selected block if it's the one being edited
        if selectedBlock?.uuid == block.uuid {
            selectedBlock = updatedBlock
        }

        // Persist
        do {
            // Capture by value for async context
            let blockToUpdate = updatedBlock
            try await database.asyncWrite { db in
                try blockToUpdate.save(db)
            }

            NotificationCenter.default.post(
                name: .scheduleBlockUpdated,
                object: nil,
                userInfo: ["block": updatedBlock, "uuid": updatedBlock.uuid]
            )

            print("✅ Updated schedule block: \(updatedBlock.title)")

        } catch {
            // Reload to restore correct state
            await loadBlocks()
            throw error
        }
    }

    /// Delete a block (soft delete)
    public func deleteBlock(_ block: ScheduleBlock) async throws {
        var deletedBlock = block
        deletedBlock.softDelete()

        // Optimistic UI update with animation
        withAnimation(SchedulerSprings.blockDelete) {
            allBlocks.removeAll { $0.uuid == block.uuid }
        }

        // Clear selection if deleted
        if selectedBlock?.uuid == block.uuid {
            selectedBlock = nil
            isDrawerOpen = false
        }

        // Persist
        do {
            // Capture by value for async context
            let blockToDelete = deletedBlock
            try await database.asyncWrite { db in
                try blockToDelete.save(db)
            }

            NotificationCenter.default.post(
                name: .scheduleBlockDeleted,
                object: nil,
                userInfo: ["uuid": block.uuid]
            )

            SchedulerHaptics.strong()
            print("✅ Deleted schedule block: \(block.title)")

        } catch {
            // Restore on failure
            withAnimation(SchedulerSprings.blockCreate) {
                allBlocks.append(block)
                allBlocks = ScheduleBlock.sortForDisplay(allBlocks)
            }
            throw error
        }
    }

    /// Toggle completion state
    public func toggleCompletion(for block: ScheduleBlock) async throws {
        var updatedBlock = block
        updatedBlock.toggleCompletion()

        // Optimistic update with completion animation
        if let index = allBlocks.firstIndex(where: { $0.uuid == block.uuid }) {
            withAnimation(SchedulerSprings.blockComplete) {
                allBlocks[index] = updatedBlock
            }
        }

        // Haptic feedback
        if updatedBlock.isCompleted {
            SchedulerHaptics.success()
        } else {
            SchedulerHaptics.light()
        }

        // Capture by value for async context
        let blockToComplete = updatedBlock
        try await database.asyncWrite { db in
            try blockToComplete.save(db)
        }

        NotificationCenter.default.post(
            name: .scheduleBlockCompleted,
            object: nil,
            userInfo: ["block": updatedBlock, "isCompleted": updatedBlock.isCompleted]
        )

        print("✅ Toggled completion: \(updatedBlock.title) → \(updatedBlock.isCompleted ? "done" : "todo")")
    }

    /// Reschedule a block to a new time
    public func rescheduleBlock(_ block: ScheduleBlock, to newStart: Date, duration: Int? = nil) async throws {
        var updatedBlock = block
        updatedBlock.reschedule(to: newStart, duration: duration)

        try await updateBlock(updatedBlock)

        SchedulerHaptics.medium()
        print("✅ Rescheduled: \(block.title) → \(newStart)")
    }

    /// Resize a block (change duration)
    public func resizeBlock(_ block: ScheduleBlock, newDurationMinutes: Int) async throws {
        guard newDurationMinutes >= 15 else { return } // Minimum 15 minutes

        var updatedBlock = block
        updatedBlock.resize(to: newDurationMinutes)

        try await updateBlock(updatedBlock)

        print("✅ Resized: \(block.title) → \(newDurationMinutes) minutes")
    }

    // MARK: - Navigation

    /// Navigate to today
    public func goToToday() {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = Date()
        }
        SchedulerHaptics.light()
    }

    /// Navigate to previous week
    public func previousWeek() {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate)!
        }
        SchedulerHaptics.light()
    }

    /// Navigate to next week
    public func nextWeek() {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate)!
        }
        SchedulerHaptics.light()
    }

    /// Navigate to previous day
    public func previousDay() {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        }
        SchedulerHaptics.light()
    }

    /// Navigate to next day
    public func nextDay() {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
        }
        SchedulerHaptics.light()
    }

    /// Navigate to specific date
    public func goToDate(_ date: Date) {
        withAnimation(SchedulerSprings.modeSwitch) {
            selectedDate = date
        }
    }

    // MARK: - Mode Switching

    /// Switch between Plan and Today modes
    public func switchMode(to newMode: SchedulerMode) {
        guard mode != newMode else { return }

        withAnimation(SchedulerSprings.modeSwitch) {
            mode = newMode
        }

        SchedulerHaptics.medium()

        // Post notification for voice context update
        NotificationCenter.default.post(
            name: .schedulerModeChanged,
            object: nil,
            userInfo: ["mode": newMode.rawValue]
        )

        print("📅 Scheduler mode: \(newMode.displayName)")
    }

    /// Toggle between modes
    public func toggleMode() {
        switchMode(to: mode == .plan ? .today : .plan)
    }

    // MARK: - Selection & Editor

    /// Select a block (opens context drawer)
    public func selectBlock(_ block: ScheduleBlock?) {
        withAnimation(SchedulerSprings.standard) {
            selectedBlock = block
            isDrawerOpen = block != nil
        }

        if block != nil {
            SchedulerHaptics.light()

            NotificationCenter.default.post(
                name: .scheduleBlockSelected,
                object: nil,
                userInfo: ["uuid": block!.uuid]
            )
        }
    }

    /// Open editor for creating new block
    public func openEditor(
        proposedStart: Date? = nil,
        proposedEnd: Date? = nil,
        anchorPoint: CGPoint? = nil,
        style: SchedulerEditorState.Style = .modal
    ) {
        withAnimation(SchedulerSprings.expand) {
            editorState = SchedulerEditorState(
                mode: .create(proposedStart: proposedStart, proposedEnd: proposedEnd),
                anchorPoint: anchorPoint,
                style: style
            )
        }
        SchedulerHaptics.light()
    }

    /// Open editor for editing existing block
    public func openEditor(for block: ScheduleBlock, anchorPoint: CGPoint? = nil) {
        withAnimation(SchedulerSprings.expand) {
            editorState = SchedulerEditorState(
                mode: .edit(block: block),
                anchorPoint: anchorPoint,
                style: .modal  // Always modal for editing
            )
        }
        SchedulerHaptics.light()
    }

    /// Close the editor
    public func closeEditor() {
        withAnimation(SchedulerSprings.expand) {
            editorState = nil
        }
    }

    /// Close the context drawer
    public func closeDrawer() {
        withAnimation(SchedulerSprings.expand) {
            isDrawerOpen = false
            selectedBlock = nil
        }
    }

    // MARK: - Quick Actions

    /// Create a quick task for today
    public func createQuickTask(title: String) async throws {
        let block = ScheduleBlock.task(title: title)
        try await createBlock(block)
    }

    /// Create a scheduled block
    public func createTimeBlock(title: String, start: Date, end: Date, color: String? = nil) async throws {
        let block = ScheduleBlock.timeBlock(title: title, startTime: start, endTime: end, color: color)
        try await createBlock(block)
    }

    /// Create a focus session
    public func createFocusSession(title: String, start: Date, durationMinutes: Int = 25) async throws {
        let block = ScheduleBlock.focusSession(title: title, startTime: start, targetMinutes: durationMinutes)
        try await createBlock(block)
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Voice command: Create block
        NotificationCenter.default.addObserver(
            forName: .voiceCreateScheduleBlock,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable values before async context
            let info = VoiceCreateInfo(from: notification.userInfo)
            Task { @MainActor in
                await self?.handleVoiceCreate(info: info)
            }
        }

        // Voice command: Move/reschedule block
        NotificationCenter.default.addObserver(
            forName: .voiceMoveScheduleBlock,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = VoiceMoveInfo(from: notification.userInfo)
            Task { @MainActor in
                await self?.handleVoiceMove(info: info)
            }
        }

        // Voice command: Resize/expand/shrink block
        NotificationCenter.default.addObserver(
            forName: .voiceResizeScheduleBlock,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = VoiceResizeInfo(from: notification.userInfo)
            Task { @MainActor in
                await self?.handleVoiceResize(info: info)
            }
        }

        // Voice command: Delete block
        NotificationCenter.default.addObserver(
            forName: .voiceDeleteScheduleBlock,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let uuid = notification.userInfo?["uuid"] as? String
            Task { @MainActor in
                await self?.handleVoiceDelete(uuid: uuid)
            }
        }

        // Voice command: Complete block
        NotificationCenter.default.addObserver(
            forName: .voiceCompleteScheduleBlock,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let uuid = notification.userInfo?["uuid"] as? String
            Task { @MainActor in
                await self?.handleVoiceComplete(uuid: uuid)
            }
        }

        // Voice command: Switch mode
        NotificationCenter.default.addObserver(
            forName: .voiceSwitchSchedulerMode,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let modeString = notification.userInfo?["mode"] as? String
            Task { @MainActor in
                self?.handleVoiceModeSwitch(modeString: modeString)
            }
        }

        // Voice command: Navigate date
        NotificationCenter.default.addObserver(
            forName: .voiceNavigateSchedulerDate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let action = notification.userInfo?["action"] as? String
            let dateString = notification.userInfo?["date"] as? String
            Task { @MainActor in
                self?.handleVoiceNavigate(action: action, dateString: dateString)
            }
        }
    }

    // MARK: - Sendable Voice Info Structs

    private struct VoiceCreateInfo: Sendable {
        let title: String?
        let blockType: String?
        let startTime: String?
        let endTime: String?
        let duration: String?
        let linkedEntityUuid: String?

        init(from userInfo: [AnyHashable: Any]?) {
            title = userInfo?["title"] as? String
            blockType = userInfo?["blockType"] as? String
            startTime = userInfo?["startTime"] as? String
            endTime = userInfo?["endTime"] as? String
            duration = userInfo?["duration"] as? String
            linkedEntityUuid = userInfo?["linkedEntityUuid"] as? String
        }
    }

    private struct VoiceMoveInfo: Sendable {
        let uuid: String?
        let targetTime: String?
        let targetDay: String?

        init(from userInfo: [AnyHashable: Any]?) {
            uuid = userInfo?["uuid"] as? String
            targetTime = userInfo?["targetTime"] as? String
            targetDay = userInfo?["targetDay"] as? String
        }
    }

    private struct VoiceResizeInfo: Sendable {
        let uuid: String?
        let newDuration: String?
        let action: String?

        init(from userInfo: [AnyHashable: Any]?) {
            uuid = userInfo?["uuid"] as? String
            newDuration = userInfo?["newDuration"] as? String
            action = userInfo?["action"] as? String
        }
    }

    // MARK: - Voice Command Handlers

    private func handleVoiceCreate(info: VoiceCreateInfo) async {
        let title = info.title ?? "New Block"
        let blockTypeString = info.blockType ?? "task"
        let blockType = ScheduleBlockType(rawValue: blockTypeString) ?? .task

        // Parse time
        var startTime: Date?
        var endTime: Date?

        if let startString = info.startTime {
            startTime = parseTimeString(startString)
        }
        if let endString = info.endTime {
            endTime = parseTimeString(endString)
        }

        // Create block based on type
        var block: ScheduleBlock

        switch blockType {
        case .task:
            block = ScheduleBlock.task(title: title, startTime: startTime)
        case .timeBlock:
            let start = startTime ?? Date()
            let end = endTime ?? start.addingTimeInterval(3600)
            block = ScheduleBlock.timeBlock(title: title, startTime: start, endTime: end)
        case .focus:
            block = ScheduleBlock.focusSession(title: title, startTime: startTime ?? Date())
        default:
            block = ScheduleBlock(title: title, blockType: blockType, startTime: startTime, endTime: endTime)
        }

        block.originType = .voice

        do {
            try await createBlock(block)
            print("🎤 Voice created: \(title)")
        } catch {
            print("❌ Voice create failed: \(error)")
        }
    }

    private func handleVoiceMove(info: VoiceMoveInfo) async {
        guard let targetUuid = info.uuid ?? lastCreatedBlockUuid,
              let block = allBlocks.first(where: { $0.uuid == targetUuid }),
              let newStartString = info.targetTime,
              let newStart = parseTimeString(newStartString)
        else { return }

        do {
            try await rescheduleBlock(block, to: newStart)
            print("🎤 Voice moved: \(block.title) → \(newStart)")
        } catch {
            print("❌ Voice move failed: \(error)")
        }
    }

    private func handleVoiceResize(info: VoiceResizeInfo) async {
        guard let targetUuid = info.uuid ?? lastCreatedBlockUuid,
              let block = allBlocks.first(where: { $0.uuid == targetUuid })
        else { return }

        // Parse duration change
        var newDuration = block.effectiveDurationMinutes

        if let durationString = info.newDuration {
            newDuration = parseDurationString(durationString)
        } else if let action = info.action {
            switch action {
            case "expand":
                newDuration = min(newDuration + 30, 480) // Add 30 min, max 8 hours
            case "shrink":
                newDuration = max(newDuration - 30, 15) // Remove 30 min, min 15 min
            default:
                break
            }
        }

        do {
            try await resizeBlock(block, newDurationMinutes: newDuration)
            print("🎤 Voice resized: \(block.title) → \(newDuration) minutes")
        } catch {
            print("❌ Voice resize failed: \(error)")
        }
    }

    private func handleVoiceDelete(uuid: String?) async {
        guard let targetUuid = uuid ?? lastCreatedBlockUuid,
              let block = allBlocks.first(where: { $0.uuid == targetUuid })
        else { return }

        do {
            try await deleteBlock(block)
            print("🎤 Voice deleted: \(block.title)")
        } catch {
            print("❌ Voice delete failed: \(error)")
        }
    }

    private func handleVoiceComplete(uuid: String?) async {
        guard let targetUuid = uuid ?? lastCreatedBlockUuid,
              let block = allBlocks.first(where: { $0.uuid == targetUuid })
        else { return }

        do {
            try await toggleCompletion(for: block)
            print("🎤 Voice completed: \(block.title)")
        } catch {
            print("❌ Voice complete failed: \(error)")
        }
    }

    private func handleVoiceModeSwitch(modeString: String?) {
        guard let modeString = modeString,
              let newMode = SchedulerMode(rawValue: modeString)
        else {
            // If no mode specified, toggle
            toggleMode()
            return
        }

        switchMode(to: newMode)
        print("🎤 Voice mode switch: \(newMode.displayName)")
    }

    private func handleVoiceNavigate(action: String?, dateString: String?) {
        guard let action = action else { return }

        switch action {
        case "today":
            goToToday()
        case "nextWeek":
            nextWeek()
        case "previousWeek":
            previousWeek()
        case "nextDay", "tomorrow":
            nextDay()
        case "previousDay", "yesterday":
            previousDay()
        default:
            if let dateString = dateString,
               let date = ISO8601DateFormatter().date(from: dateString) {
                goToDate(date)
            }
        }

        print("🎤 Voice navigate: \(action)")
    }

    // MARK: - Time Parsing Helpers

    private func parseTimeString(_ string: String) -> Date? {
        let calendar = Calendar.current
        // Always use today as the base for voice commands, not selectedDate
        // User expects "at 5pm" to mean today at 5pm, regardless of what date they're viewing
        let today = Date()

        // Try ISO8601 first
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }

        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)

        // Parse common patterns
        let patterns = ["h:mm a", "h:mma", "ha", "h a", "HH:mm", "H:mm", "h"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")

        for pattern in patterns {
            formatter.dateFormat = pattern
            if let time = formatter.date(from: lower) {
                var components = calendar.dateComponents([.year, .month, .day], from: today)
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                return calendar.date(from: components)
            }
        }

        // Try regex for "3pm", "3:30pm"
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {

            if let hourRange = Range(match.range(at: 1), in: lower),
               var hour = Int(lower[hourRange]) {

                var minute = 0
                if match.range(at: 2).location != NSNotFound,
                   let minRange = Range(match.range(at: 2), in: lower) {
                    minute = Int(lower[minRange]) ?? 0
                }

                if match.range(at: 3).location != NSNotFound,
                   let periodRange = Range(match.range(at: 3), in: lower) {
                    let period = String(lower[periodRange]).lowercased()
                    if period.contains("p") && hour < 12 {
                        hour += 12
                    } else if period.contains("a") && hour == 12 {
                        hour = 0
                    }
                } else if hour < 8 {
                    // Assume PM for small numbers without period
                    hour += 12
                }

                var components = calendar.dateComponents([.year, .month, .day], from: today)
                components.hour = hour
                components.minute = minute
                return calendar.date(from: components)
            }
        }

        return nil
    }

    private func parseDurationString(_ string: String) -> Int {
        let lower = string.lowercased()
        var totalMinutes = 0

        // Hours
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*h"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let hours = Int(lower[range]) {
            totalMinutes += hours * 60
        }

        // Minutes
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*m"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let minutes = Int(lower[range]) {
            totalMinutes += minutes
        }

        // If just a number, assume minutes
        if totalMinutes == 0,
           let regex = try? NSRegularExpression(pattern: #"^(\d+)$"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let minutes = Int(lower[range]) {
            totalMinutes = minutes
        }

        return max(15, totalMinutes) // Minimum 15 minutes
    }
}

// Note: Notification.Name extensions are in VoiceNotifications.swift
