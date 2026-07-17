import XCTest
@testable import CosmoOS

final class CommandCenterComposerTests: XCTestCase {
    private var createdTaskUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = createdTaskUUIDs.reversed()
        createdTaskUUIDs.removeAll()

        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }

        try await super.tearDown()
    }

    func testParseDateInputHandlesTodayTomorrowAndNextWeekday() {
        let today = CommandCenterScheduleUtilities.parseDateInput("today")
        let tomorrow = CommandCenterScheduleUtilities.parseDateInput("tomorrow")
        let nextMonday = CommandCenterScheduleUtilities.parseDateInput("next monday")

        XCTAssertNotNil(today)
        XCTAssertNotNil(tomorrow)
        XCTAssertNotNil(nextMonday)

        if let today {
            XCTAssertTrue(Calendar.current.isDateInToday(today))
        }

        if let tomorrow {
            XCTAssertTrue(Calendar.current.isDateInTomorrow(tomorrow))
        }

        if let nextMonday {
            XCTAssertEqual(Calendar.current.component(.weekday, from: nextMonday), DayOfWeek.monday.rawValue)
            XCTAssertGreaterThan(nextMonday, Calendar.current.startOfDay(for: Date()))
        }
    }

    func testParseDateInputRollsPastMonthDayIntoNextYear() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let month = Calendar.current.component(.month, from: yesterday)
        let day = Calendar.current.component(.day, from: yesterday)
        let input = "\(month)/\(day)"

        let parsed = CommandCenterScheduleUtilities.parseDateInput(input)

        XCTAssertNotNil(parsed)

        if let parsed {
            XCTAssertEqual(Calendar.current.component(.month, from: parsed), month)
            XCTAssertEqual(Calendar.current.component(.day, from: parsed), day)
            XCTAssertGreaterThanOrEqual(parsed, Calendar.current.startOfDay(for: Date()))
        }
    }

    func testHabitDraftKeywordsTrimAndDropEmptyValues() {
        var draft = CommandCenterHabitEditorDraft()
        draft.keywordInput = " write,  draft ,, article  , "

        XCTAssertEqual(draft.keywords, ["write", "draft", "article"])
    }

    // MARK: - Leading-emoji identity contract

    func testCollectionEmojiApplyingRewritesLeadingMark() {
        XCTAssertEqual(CollectionEmoji.applying(mark: "🎬", to: "Personal content"), "🎬 Personal content")
        XCTAssertEqual(CollectionEmoji.applying(mark: "📚", to: "🎬 Personal content"), "📚 Personal content")
        XCTAssertEqual(CollectionEmoji.applying(mark: nil, to: "🎬 Personal content"), "Personal content")
        XCTAssertEqual(CollectionEmoji.applying(mark: nil, to: "Personal content"), "Personal content")
        XCTAssertEqual(CollectionEmoji.applying(mark: "🎬", to: ""), "🎬")
        // A mark-only name strips to empty — it never doubles into "🎬 🎬".
        XCTAssertEqual(CollectionEmoji.applying(mark: nil, to: "🎬"), "")
        XCTAssertEqual(CollectionEmoji.applying(mark: "📚", to: "🎬"), "📚")
    }

    func testHabitDraftMarkAccessorsFollowLeadingEmojiContract() {
        var draft = CommandCenterHabitEditorDraft()
        draft.title = "Personal content"

        // "content" resolves a keyword mark, but no explicit mark exists yet.
        XCTAssertNil(draft.explicitMark)
        XCTAssertNotNil(draft.effectiveMark)
        XCTAssertEqual(draft.effectiveMark, CollectionEmoji.resolve(name: "Personal content").emoji)
        XCTAssertEqual(draft.displayLabel, "Personal content")

        draft.applyMark("🧘")
        XCTAssertEqual(draft.title, "🧘 Personal content")
        XCTAssertEqual(draft.explicitMark, "🧘")
        XCTAssertEqual(draft.effectiveMark, "🧘")
        XCTAssertEqual(draft.displayLabel, "Personal content")

        draft.applyMark(nil)
        XCTAssertEqual(draft.title, "Personal content")
        XCTAssertNil(draft.explicitMark)
    }

    func testHabitAccentSwatchesAppendLegacyCurrentColor() {
        let curated = CommandCenterHabitComposer.accentSwatches(current: "2D6A4F")
        XCTAssertEqual(curated.map(\.hex), DS.collectionAccentPalette.map(\.hex))

        // Case-insensitive membership — stored hexes may differ in casing.
        let lowercased = CommandCenterHabitComposer.accentSwatches(current: "2d6a4f")
        XCTAssertEqual(lowercased.count, DS.collectionAccentPalette.count)

        let legacy = CommandCenterHabitComposer.accentSwatches(current: "DC3545")
        XCTAssertEqual(legacy.count, DS.collectionAccentPalette.count + 1)
        XCTAssertEqual(legacy.last?.hex, "DC3545")
    }

    func testIntentBehaviorTemplateMapsToLegacyIntent() {
        XCTAssertEqual(IntentBehaviorTemplate.writeContent.taskIntent, .writeContent)
        XCTAssertEqual(IntentBehaviorTemplate(.research), .research)
        XCTAssertNil(IntentBehaviorTemplate(.general))
    }

    // NOTE (July 2026): the TaskRecurrenceEngine tests that lived here were
    // removed with the engine itself — the materialized-instance model is gone
    // (replaced by RecurringSeriesEngine's virtual occurrences, tested in
    // RecurringSeriesEngineTests).





    @MainActor
    func testIntentEngineReturnsExplicitUnassignedPresentation() {
        let engine = CommandCenterIntentEngine()

        let presentation = engine.resolvedPresentation(intentUUID: nil, legacyIntentRaw: TaskIntent.general.rawValue)

        XCTAssertTrue(presentation.isUnassigned)
        XCTAssertEqual(presentation.title, "Unassigned")
        XCTAssertNil(presentation.behaviorTemplate)
    }

    @MainActor
    func testRecurringTitleFutureScopeUpdatesTemplateAndFutureMatchingInstancesOnly() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let occurrence = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9)))
        let previousOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: occurrence))
        let nextOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: occurrence))
        let customFutureOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: occurrence))
        let originalTitle = "Create reel/thread for Ben"
        let renamedTitle = "Create reel/thread for Josh"
        let viewModel = CommandCenterDashboardViewModel(startsRefreshing: false)

        let template = try await createRecurringTaskAtom(
            title: originalTitle,
            occurrenceDate: occurrence,
            recurrence: .weekly(on: [.tuesday])
        )
        let past = try await createRecurringTaskAtom(
            title: originalTitle,
            occurrenceDate: previousOccurrence,
            parentUUID: template.uuid,
            isCompleted: true
        )
        let current = try await createRecurringTaskAtom(
            title: originalTitle,
            occurrenceDate: occurrence,
            parentUUID: template.uuid
        )
        let matchingFuture = try await createRecurringTaskAtom(
            title: originalTitle,
            occurrenceDate: nextOccurrence,
            parentUUID: template.uuid
        )
        let customFuture = try await createRecurringTaskAtom(
            title: "Custom future title",
            occurrenceDate: customFutureOccurrence,
            parentUUID: template.uuid
        )

        await viewModel.updateRecurringTaskTitle(
            uuid: current.uuid,
            title: renamedTitle,
            scope: .currentAndFuture
        )

        let updatedTemplate = try await fetchTaskTitle(template.uuid)
        let updatedPast = try await fetchTaskTitle(past.uuid)
        let updatedCurrent = try await fetchTaskTitle(current.uuid)
        let updatedMatchingFuture = try await fetchTaskTitle(matchingFuture.uuid)
        let updatedCustomFuture = try await fetchTaskTitle(customFuture.uuid)

        XCTAssertEqual(updatedTemplate, renamedTitle)
        XCTAssertEqual(updatedCurrent, renamedTitle)
        XCTAssertEqual(updatedMatchingFuture, renamedTitle)
        XCTAssertEqual(updatedPast, originalTitle)
        XCTAssertEqual(updatedCustomFuture, "Custom future title")
    }


    @MainActor
    func testDeletingRecurringTaskDefaultsToCurrentAndFuture() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let occurrence = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9)))
        let previousOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: occurrence))
        let nextOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: occurrence))
        let viewModel = CommandCenterDashboardViewModel(startsRefreshing: false)

        let template = try await createRecurringTaskAtom(
            title: "Default future delete",
            occurrenceDate: occurrence,
            recurrence: .weekly(on: [.tuesday])
        )
        let past = try await createRecurringTaskAtom(
            title: "Default future delete",
            occurrenceDate: previousOccurrence,
            parentUUID: template.uuid
        )
        let current = try await createRecurringTaskAtom(
            title: "Default future delete",
            occurrenceDate: occurrence,
            parentUUID: template.uuid
        )
        let future = try await createRecurringTaskAtom(
            title: "Default future delete",
            occurrenceDate: nextOccurrence,
            parentUUID: template.uuid
        )

        await viewModel.deleteTask(uuid: current.uuid)

        let remainingPast = try await AtomRepository.shared.fetch(uuid: past.uuid)
        let remainingCurrent = try await AtomRepository.shared.fetch(uuid: current.uuid)
        let remainingFuture = try await AtomRepository.shared.fetch(uuid: future.uuid)

        XCTAssertNotNil(remainingPast)
        XCTAssertNil(remainingCurrent)
        XCTAssertNil(remainingFuture)

        let remainingTemplate = try await AtomRepository.shared.fetch(uuid: template.uuid)
        XCTAssertNotNil(remainingTemplate)
        let truncatedRule = try XCTUnwrap(
            remainingTemplate?
                .metadataValue(as: TaskMetadata.self)?
                .recurrence
                .flatMap(RecurrenceRule.fromJSON)
        )
        guard case .onDate(let endDate) = truncatedRule.endCondition else {
            XCTFail("Expected recurring template to be truncated before the deleted occurrence")
            return
        }
        XCTAssertLessThan(endDate, occurrence)
    }

    @MainActor
    func testDeletingRecurringTaskFutureScopeDeletesTemplateAndFutureInstancesOnly() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let occurrence = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 9)))
        let previousOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: occurrence))
        let nextOccurrence = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: occurrence))
        let viewModel = CommandCenterDashboardViewModel(startsRefreshing: false)

        let template = try await createRecurringTaskAtom(
            title: "Future delete",
            occurrenceDate: occurrence,
            recurrence: .weekly(on: [.tuesday])
        )
        let past = try await createRecurringTaskAtom(
            title: "Future delete",
            occurrenceDate: previousOccurrence,
            parentUUID: template.uuid
        )
        let current = try await createRecurringTaskAtom(
            title: "Future delete",
            occurrenceDate: occurrence,
            parentUUID: template.uuid
        )
        let future = try await createRecurringTaskAtom(
            title: "Future delete",
            occurrenceDate: nextOccurrence,
            parentUUID: template.uuid
        )

        await viewModel.deleteTask(uuid: current.uuid, recurrenceScope: .currentAndFuture)

        let remainingPast = try await AtomRepository.shared.fetch(uuid: past.uuid)
        let remainingCurrent = try await AtomRepository.shared.fetch(uuid: current.uuid)
        let remainingFuture = try await AtomRepository.shared.fetch(uuid: future.uuid)
        let remainingTemplate = try await AtomRepository.shared.fetch(uuid: template.uuid)

        XCTAssertNotNil(remainingPast)
        XCTAssertNil(remainingCurrent)
        XCTAssertNil(remainingFuture)
        XCTAssertNotNil(remainingTemplate)

        let truncatedRule = try XCTUnwrap(
            remainingTemplate?
                .metadataValue(as: TaskMetadata.self)?
                .recurrence
                .flatMap(RecurrenceRule.fromJSON)
        )
        guard case .onDate(let endDate) = truncatedRule.endCondition else {
            XCTFail("Expected recurring template to be truncated before the deleted occurrence")
            return
        }
        XCTAssertLessThan(endDate, occurrence)
    }

    private func createRecurringTaskAtom(
        title: String,
        occurrenceDate: Date,
        recurrence: RecurrenceRule? = nil,
        parentUUID: String? = nil,
        isCompleted: Bool = false
    ) async throws -> Atom {
        var metadata = TaskMetadata()
        metadata.focusDate = PlannerumFormatters.iso8601.string(from: occurrenceDate)
        metadata.dueDate = PlannerumFormatters.iso8601.string(from: occurrenceDate)
        metadata.whenDate = PlannerumFormatters.iso8601.string(from: occurrenceDate)
        metadata.recurrence = recurrence?.toJSON()
        metadata.recurrenceParentUUID = parentUUID
        metadata.isCompleted = isCompleted

        let atom = Atom.new(type: .task, title: title).withMetadata(metadata)
        let created = try await AtomRepository.shared.create(atom)
        createdTaskUUIDs.append(created.uuid)
        return created
    }

    private func fetchTaskTitle(_ uuid: String) async throws -> String? {
        try await AtomRepository.shared.fetch(uuid: uuid)?.title
    }
}
