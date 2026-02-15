// CosmoOS/AI/ObjectiveEngine.swift
// Quarter Objectives Engine — computes real progress from data sources
// Part of Plannerum WP6

import SwiftUI
import Combine

// MARK: - Objective State

struct ObjectiveState: Identifiable, Equatable {
    let id: String
    let title: String
    let targetValue: Double
    var currentValue: Double
    let unit: String
    let dataSource: ObjectiveDataSource
    var progress: Double          // 0.0-1.0
    var paceStatus: PaceStatus
    var totalHoursInvested: Double
    let quarter: Int
    let year: Int
    let createdAt: Date
}

// MARK: - Pace Status

enum PaceStatus: String, CaseIterable {
    case onTrack = "On Track"
    case atRisk = "At Risk"
    case behind = "Behind"
    case completed = "Completed"
    case justStarted = "Just Started"

    var color: Color {
        switch self {
        case .onTrack: return Color(red: 34/255, green: 197/255, blue: 94/255)
        case .atRisk: return Color(red: 234/255, green: 179/255, blue: 8/255)
        case .behind: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case .completed: return Color(red: 59/255, green: 130/255, blue: 246/255)
        case .justStarted: return PlannerumColors.primary
        }
    }

    var iconName: String {
        switch self {
        case .onTrack: return "checkmark.circle"
        case .atRisk: return "exclamationmark.triangle"
        case .behind: return "xmark.circle"
        case .completed: return "star.fill"
        case .justStarted: return "sparkles"
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - Objective Engine

@MainActor
class ObjectiveEngine: ObservableObject {

    @Published var objectives: [ObjectiveState] = []

    private let atomRepository: AtomRepository
    private var refreshTimer: Timer?

    init(atomRepository: AtomRepository? = nil) {
        self.atomRepository = atomRepository ?? AtomRepository.shared
    }

    // MARK: - Lifecycle

    func startTracking() {
        stopTracking()
        Task { await recalculate() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.recalculate()
            }
        }
    }

    func stopTracking() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Recalculate

    func recalculate() async {
        do {
            let objectiveAtoms = try await atomRepository.fetchAll(type: .objective)
            var newStates: [ObjectiveState] = []

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            for atom in objectiveAtoms {
                guard let meta = atom.metadataValue(as: ObjectiveMetadata.self),
                      let source = ObjectiveDataSource(rawValue: meta.dataSource) else {
                    continue
                }

                let atomCreatedAt = isoFormatter.date(from: atom.createdAt)
                    ?? fallbackFormatter.date(from: atom.createdAt)
                    ?? Date()

                let currentValue = await computeValue(
                    for: source,
                    quarter: meta.quarter,
                    year: meta.year
                )

                let progress = meta.targetValue > 0
                    ? min(currentValue / meta.targetValue, 1.0)
                    : 0

                let state = ObjectiveState(
                    id: atom.uuid,
                    title: meta.title,
                    targetValue: meta.targetValue,
                    currentValue: currentValue,
                    unit: meta.unit,
                    dataSource: source,
                    progress: progress,
                    paceStatus: computePaceStatus(
                        currentValue: currentValue,
                        targetValue: meta.targetValue,
                        quarter: meta.quarter,
                        year: meta.year,
                        createdAt: atomCreatedAt
                    ),
                    totalHoursInvested: meta.totalHoursInvested ?? 0,
                    quarter: meta.quarter,
                    year: meta.year,
                    createdAt: atomCreatedAt
                )
                newStates.append(state)

                // Persist updated currentValue back to atom
                var updatedMeta = meta
                updatedMeta.currentValue = currentValue
                var updatedAtom = atom
                if let encoded = try? JSONEncoder().encode(updatedMeta),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    updatedAtom.metadata = jsonString
                    _ = try? await atomRepository.update(updatedAtom)
                }
            }

            withAnimation(PlannerumSprings.select) {
                self.objectives = newStates
            }
        } catch {
            print("ObjectiveEngine: recalculate failed - \(error)")
        }
    }

    // MARK: - Create Objective

    func createObjective(
        title: String,
        targetValue: Double,
        unit: String,
        dataSource: ObjectiveDataSource,
        quarter: Int? = nil,
        year: Int? = nil
    ) async throws {
        let cal = Calendar.current
        let now = Date()
        let q = quarter ?? currentQuarter()
        let y = year ?? cal.component(.year, from: now)

        let meta = ObjectiveMetadata(
            title: title,
            targetValue: targetValue,
            currentValue: 0,
            unit: unit,
            dataSource: dataSource.rawValue,
            quarter: q,
            year: y,
            totalBlocksInvested: 0,
            totalHoursInvested: 0
        )

        guard let encoded = try? JSONEncoder().encode(meta),
              let metaString = String(data: encoded, encoding: .utf8) else { return }

        try await atomRepository.create(
            type: .objective,
            title: title,
            metadata: metaString
        )

        await recalculate()
    }

    // MARK: - Update Objective

    func updateObjective(
        id: String,
        title: String,
        targetValue: Double,
        unit: String,
        dataSource: ObjectiveDataSource
    ) async throws {
        guard var atom = try? await atomRepository.fetch(uuid: id),
              var meta = atom.metadataValue(as: ObjectiveMetadata.self) else { return }

        meta.title = title
        meta.targetValue = targetValue
        meta.unit = unit
        meta.dataSource = dataSource.rawValue

        if let encoded = try? JSONEncoder().encode(meta),
           let metaString = String(data: encoded, encoding: .utf8) {
            atom.metadata = metaString
            atom.title = title
            _ = try? await atomRepository.update(atom)
        }

        await recalculate()
    }

    // MARK: - Delete Objective

    func deleteObjective(id: String) async throws {
        try await atomRepository.delete(uuid: id)
        objectives.removeAll { $0.id == id }
    }

    // MARK: - Data Source Computation

    private func computeValue(
        for dataSource: ObjectiveDataSource,
        quarter: Int,
        year: Int
    ) async -> Double {
        let (startDate, endDate) = quarterDateRange(quarter: quarter, year: year)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        func parseDate(_ str: String) -> Date? {
            isoFormatter.date(from: str) ?? fallbackFormatter.date(from: str)
        }

        func isInQuarter(_ dateString: String) -> Bool {
            guard let date = parseDate(dateString) else { return false }
            return date >= startDate && date <= endDate
        }

        switch dataSource {
        case .deepWorkSessionCount:
            let atoms = (try? await atomRepository.fetchAll(type: .deepWorkBlock)) ?? []
            return Double(atoms.filter { isInQuarter($0.createdAt) }.count)

        case .contentPublishedCount:
            let atoms = (try? await atomRepository.fetchAll(type: .contentPublish)) ?? []
            return Double(atoms.filter { isInQuarter($0.createdAt) }.count)

        case .totalXP:
            let events = (try? await atomRepository.fetchAll(type: .xpEvent)) ?? []
            var total = 0
            for event in events where isInQuarter(event.createdAt) {
                if let dict = event.metadataDict,
                   let amount = dict["xpAmount"] as? Int {
                    total += amount
                } else if let dict = event.metadataDict,
                          let amount = dict["xpAmount"] as? Double {
                    total += Int(amount)
                }
            }
            return Double(total)

        case .currentLevel:
            let atoms = (try? await atomRepository.fetchAll(type: .levelUpdate)) ?? []
            // Find most recent level update
            var latestLevel: Double = 0
            for atom in atoms {
                if let dict = atom.metadataDict,
                   let level = dict["level"] as? Int {
                    latestLevel = max(latestLevel, Double(level))
                } else if let dict = atom.metadataDict,
                          let level = dict["level"] as? Double {
                    latestLevel = max(latestLevel, level)
                }
            }
            return latestLevel

        case .tasksCompleted:
            let tasks = (try? await atomRepository.fetchAll(type: .task)) ?? []
            return Double(tasks.filter { atom in
                guard let meta = atom.metadataValue(as: TaskMetadata.self),
                      meta.isCompleted == true,
                      let completedAt = meta.completedAt else { return false }
                return isInQuarter(completedAt)
            }.count)

        case .customQuery:
            return 0
        }
    }

    // MARK: - Pace Status

    func paceStatus(for objective: ObjectiveState) -> PaceStatus {
        computePaceStatus(
            currentValue: objective.currentValue,
            targetValue: objective.targetValue,
            quarter: objective.quarter,
            year: objective.year,
            createdAt: objective.createdAt
        )
    }

    private func computePaceStatus(
        currentValue: Double,
        targetValue: Double,
        quarter: Int,
        year: Int,
        createdAt: Date
    ) -> PaceStatus {
        guard targetValue > 0 else { return .completed }
        if currentValue >= targetValue { return .completed }

        // New objectives: show "Just Started" instead of "Behind"
        let daysSinceCreation = Date().timeIntervalSince(createdAt) / 86400
        if daysSinceCreation < 3 || (currentValue == 0 && daysSinceCreation < 3) {
            return .justStarted
        }

        let (startDate, endDate) = quarterDateRange(quarter: quarter, year: year)
        let totalDays = max(endDate.timeIntervalSince(startDate) / 86400, 1)
        let daysElapsed = max(Date().timeIntervalSince(startDate) / 86400, 1)

        let projectedFinal = currentValue / daysElapsed * totalDays

        if projectedFinal >= targetValue {
            return .onTrack
        } else if projectedFinal >= targetValue * 0.8 {
            return .atRisk
        } else {
            return .behind
        }
    }

    // MARK: - Quarter Helpers

    func currentQuarter() -> Int {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 1...3: return 1
        case 4...6: return 2
        case 7...9: return 3
        default: return 4
        }
    }

    func currentYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func quarterDateRange(quarter: Int, year: Int) -> (Date, Date) {
        let cal = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0

        var endComponents = DateComponents()
        endComponents.year = year
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59

        switch quarter {
        case 1:
            startComponents.month = 1; startComponents.day = 1
            endComponents.month = 3; endComponents.day = 31
        case 2:
            startComponents.month = 4; startComponents.day = 1
            endComponents.month = 6; endComponents.day = 30
        case 3:
            startComponents.month = 7; startComponents.day = 1
            endComponents.month = 9; endComponents.day = 30
        default:
            startComponents.month = 10; startComponents.day = 1
            endComponents.month = 12; endComponents.day = 31
        }

        let start = cal.date(from: startComponents) ?? Date()
        let end = cal.date(from: endComponents) ?? Date()
        return (start, end)
    }

    /// Objectives for a specific quarter/year
    func objectives(for quarter: Int, year: Int) -> [ObjectiveState] {
        objectives.filter { $0.quarter == quarter && $0.year == year }
    }

    /// Compute current value preview for a data source (used in creation form)
    func previewValue(for dataSource: ObjectiveDataSource) async -> Double {
        await computeValue(for: dataSource, quarter: currentQuarter(), year: currentYear())
    }
}
