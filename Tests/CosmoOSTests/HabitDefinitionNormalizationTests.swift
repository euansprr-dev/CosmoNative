import XCTest
@testable import CosmoOS

/// `CommandCenterHabitEngine.normalized` runs on every habit load AND before
/// every habit write, so anything it drops is dropped twice over: once in
/// memory (wrong ring, wrong history, wrong completion routing) and once on
/// disk (the atom is rewritten from the normalized value).
///
/// It used to rebuild the definition field by field. `goalType` and
/// `dailyTargetMinutes` carry `= nil` defaults in the memberwise init, so
/// leaving them out compiled silently: a minutes habit loaded back as a count
/// habit, and the first edit erased its goal from the atom for good. These
/// tests pin the whole value through, not just the two fields that went
/// missing — the next field added to `HabitDefinition` gets the same guarantee.
///
/// Pure value transforms: no repository, no database. (Mac suites share the
/// real application database — nothing here may touch it.)
@MainActor
final class HabitDefinitionNormalizationTests: XCTestCase {

    private func makeHabit(
        id: String = "habit-deep-work",
        title: String = "Deep work",
        icon: String = "brain.head.profile",
        accentColor: String = "7B7EC0",
        dailyTargetCount: Int = 1,
        keywordTriggers: [String] = ["deep work"],
        mappedIntents: [String] = ["writeContent"],
        goalType: String? = nil,
        dailyTargetMinutes: Int? = nil
    ) -> HabitDefinition {
        HabitDefinition(
            id: id,
            title: title,
            icon: icon,
            accentColor: accentColor,
            dailyTargetCount: dailyTargetCount,
            keywordTriggers: keywordTriggers,
            mappedIntents: mappedIntents,
            defaultIntentUUID: "intent-writing",
            allowManualCompletion: true,
            sortOrder: 6,
            isBuiltIn: false,
            isArchived: false,
            goalType: goalType,
            dailyTargetMinutes: dailyTargetMinutes
        )
    }

    // MARK: - The minutes goal

    func testMinutesGoalSurvivesNormalization() {
        let habit = makeHabit(goalType: "minutes", dailyTargetMinutes: 60)

        let normalized = CommandCenterHabitEngine.normalized(habit, fallbackId: "atom-uuid")

        XCTAssertEqual(normalized.goalType, "minutes")
        XCTAssertEqual(normalized.dailyTargetMinutes, 60)
        XCTAssertTrue(normalized.isTimeBased, "A minutes habit must not come back as a count habit")
    }

    func testMinutesGoalTakesTheFiveMinuteFloor() {
        let habit = makeHabit(goalType: "minutes", dailyTargetMinutes: 2)

        let normalized = CommandCenterHabitEngine.normalized(habit, fallbackId: "atom-uuid")

        XCTAssertEqual(normalized.dailyTargetMinutes, 5, "createHabit's floor, re-applied on every pass")
    }

    func testCountHabitDropsAnyStrayMinutes() {
        // A habit switched back to counting must not keep the minutes it had —
        // isTimeBased reads goalType, but a stale target would resurface if the
        // goal type were ever flipped back.
        let stale = makeHabit(goalType: nil, dailyTargetMinutes: 90)
        let explicitCount = makeHabit(goalType: "count", dailyTargetMinutes: 90)

        XCTAssertNil(CommandCenterHabitEngine.normalized(stale, fallbackId: "atom-uuid").dailyTargetMinutes)
        XCTAssertNil(CommandCenterHabitEngine.normalized(explicitCount, fallbackId: "atom-uuid").dailyTargetMinutes)
        XCTAssertFalse(CommandCenterHabitEngine.normalized(explicitCount, fallbackId: "atom-uuid").isTimeBased)
    }

    // MARK: - The load → edit → save round trip

    func testMinutesHabitSurvivesLoadAndSaveRoundTrip() throws {
        // The shape refreshDefinitions + updateHabit put a habit through: stored
        // JSON → decode → normalize (load) → user edits an unrelated field →
        // normalize again → re-encode (save) → decode (next load).
        let stored = Atom.new(type: .routineDefinition, title: "Deep work")
            .withStructured(makeHabit(goalType: "minutes", dailyTargetMinutes: 45))

        let loaded = CommandCenterHabitEngine.normalized(
            try XCTUnwrap(stored.structuredData(as: HabitDefinition.self)),
            fallbackId: stored.uuid
        )
        XCTAssertTrue(loaded.isTimeBased, "load stripped the minutes goal")

        var edited = loaded
        edited.title = "Deep work (mornings)"
        let saved = stored.withStructured(
            CommandCenterHabitEngine.normalized(edited, fallbackId: stored.uuid)
        )

        let reloaded = try XCTUnwrap(saved.structuredData(as: HabitDefinition.self))
        XCTAssertEqual(reloaded.goalType, "minutes", "an unrelated edit erased the goal type")
        XCTAssertEqual(reloaded.dailyTargetMinutes, 45, "an unrelated edit erased the minutes target")
        XCTAssertEqual(reloaded.title, "Deep work (mornings)")
    }

    // MARK: - Everything the cleanup is actually for

    func testCleanupsStillApply() {
        var habit = makeHabit(
            title: "  Deep work  ",
            icon: "",
            accentColor: "#7B7EC0",
            dailyTargetCount: 0,
            keywordTriggers: ["Deep Work, Focus ", "  WRITING  "],
            mappedIntents: ["writeContent", "notAnIntent"]
        )
        habit.id = ""

        let normalized = CommandCenterHabitEngine.normalized(habit, fallbackId: "atom-uuid")

        XCTAssertEqual(normalized.id, "atom-uuid", "an empty stored id falls back to the carrying atom")
        XCTAssertEqual(normalized.title, "Deep work")
        XCTAssertEqual(normalized.icon, "repeat")
        XCTAssertEqual(normalized.accentColor, "7B7EC0")
        XCTAssertEqual(normalized.dailyTargetCount, 1)
        XCTAssertEqual(normalized.keywordTriggers, ["deep work", "focus", "writing"])
        XCTAssertEqual(normalized.mappedIntents, ["writeContent"], "unknown intent raws drop out")
    }

    func testEveryOtherFieldRidesThroughUntouched() {
        // The regression in one assertion: normalization may only change the
        // fields it cleans. Anything else it touches is a field it can lose.
        let habit = makeHabit(
            title: "Deep work",
            accentColor: "7B7EC0",
            keywordTriggers: ["deep work"],
            goalType: "minutes",
            dailyTargetMinutes: 60
        )

        XCTAssertEqual(CommandCenterHabitEngine.normalized(habit, fallbackId: "atom-uuid"), habit)
    }
}
