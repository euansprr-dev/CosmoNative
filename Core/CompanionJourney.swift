// Shared verbatim with iPhone. Growth is earned from saved activity, never a timer tick.
import Foundation

enum CompanionGrowth: Int, CaseIterable, Codable, Identifiable {
    case beginning, budding, flourishing, wondrous
    var id: Int { rawValue }
    var threshold: Int { [0, 3, 10, 30][rawValue] }
    var title: String { ["A small beginning", "Finding your rhythm", "Coming into your own", "A world of your own"][rawValue] }
    var shortTitle: String { ["Beginning", "Budding", "Flourishing", "Wondrous"][rawValue] }
    var next: Self? { Self(rawValue: rawValue + 1) }
    static func earned(days: Int) -> Self {
        allCases.last { days >= $0.threshold } ?? .beginning
    }
}

struct CompanionActivityRecord {
    let id: String
    let createdAt: String
    let metadata: String?
    var fields: [String: Any] {
        guard let metadata, let data = metadata.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

struct CompanionDay: Identifiable, Equatable {
    let date: Date
    var seconds = 0
    var tasks = 0
    var id: Date { date }
    var isActive: Bool { seconds >= 3 || tasks > 0 }
}

struct CompanionJourneySnapshot: Equatable {
    var days: [CompanionDay] = []
    var activeDays = 0
    var totalSeconds = 0
    var totalTasks = 0
    var today: CompanionDay? { days.last }

    static func make(
        focus: [CompanionActivityRecord], tasks: [CompanionActivityRecord],
        now: Date = Date(), calendar: Calendar = .current
    ) -> Self {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        func parse(_ value: String?) -> Date? {
            guard let value else { return nil }
            return fractional.date(from: value) ?? standard.date(from: value)
        }
        var history: [Date: CompanionDay] = [:]
        var seen = Set<String>()
        for record in focus where seen.insert(record.id).inserted {
            let fields = record.fields
            guard let start = parse(fields["startedAt"] as? String ?? record.createdAt), start <= now else { continue }
            // Planned time is not work. Legacy Mac blocks store actualMinutes.
            let seconds = (fields["actualSeconds"] as? Int)
                ?? min(86_400, max(0, fields["actualMinutes"] as? Int ?? 0)) * 60
            guard seconds >= 3 else { continue }
            let day = calendar.startOfDay(for: start)
            history[day, default: CompanionDay(date: day)].seconds += min(seconds, 86_400)
        }
        seen.removeAll()
        for record in tasks {
            let fields = record.fields
            if let occurrences = fields["completedOccurrences"] as? [[String: Any]], !occurrences.isEmpty {
                for occurrence in occurrences {
                    guard let stamp = parse(occurrence["completedAt"] as? String), stamp <= now else { continue }
                    let day = dayKey(occurrence["day"] as? String, calendar: calendar)
                        ?? calendar.startOfDay(for: stamp)
                    guard day <= now, seen.insert("\(record.id):\(day.timeIntervalSince1970)").inserted else { continue }
                    history[day, default: CompanionDay(date: day)].tasks += 1
                }
            } else if fields["isCompleted"] as? Bool == true,
                      let stamp = parse(fields["completedAt"] as? String), stamp <= now,
                      seen.insert(record.id).inserted {
                let day = calendar.startOfDay(for: stamp)
                history[day, default: CompanionDay(date: day)].tasks += 1
            }
        }
        let today = calendar.startOfDay(for: now)
        let days = (-13...0).compactMap { offset -> CompanionDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return history[day] ?? CompanionDay(date: day)
        }
        return Self(days: days, activeDays: history.values.filter(\.isActive).count,
                    totalSeconds: history.values.reduce(0) { $0 + $1.seconds },
                    totalTasks: history.values.reduce(0) { $0 + $1.tasks })
    }

    private static func dayKey(_ value: String?, calendar: Calendar) -> Date? {
        guard let parts = value?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

enum CompanionTrigger: String, CaseIterable, Codable, Identifiable {
    case taskCompleted, focusFinished
    var id: String { rawValue }
    var title: String { self == .taskCompleted ? "I finish a task" : "I save a focus session" }
    var icon: String { self == .taskCompleted ? "checkmark.circle" : "timer" }
}

enum CompanionResponse: String, CaseIterable, Codable, Identifiable {
    case celebrate, breathe, nextStep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .celebrate: "Celebrate the little win"
        case .breathe: "Invite a breathing break"
        case .nextStep: "Help me find my next step"
        }
    }
    var icon: String {
        switch self { case .celebrate: "sparkles"; case .breathe: "wind"; case .nextStep: "arrow.up.right" }
    }
    var message: String {
        switch self {
        case .celebrate: "Look at you growing. That little win belongs here."
        case .breathe: "A little room to breathe. Relax your shoulders, and take a slow breath."
        case .nextStep: "What is one small thing you could move forward? Pick it, then give it your attention."
        }
    }
}

struct CompanionRitual: Codable, Equatable, Identifiable {
    var trigger: CompanionTrigger
    var response: CompanionResponse
    var isEnabled: Bool
    var updatedAt: Date
    var id: CompanionTrigger { trigger }
    static let defaults: [Self] = [
        .init(trigger: .taskCompleted, response: .celebrate, isEnabled: false, updatedAt: .distantPast),
        .init(trigger: .focusFinished, response: .breathe, isEnabled: false, updatedAt: .distantPast)
    ]
}

struct CompanionJourneyPreferences: Codable, Equatable {
    var earnedDays = 0
    var tutorialComplete = false
    var rituals = CompanionRitual.defaults

    func merging(_ other: Self) -> Self {
        var result = self
        result.earnedDays = max(earnedDays, other.earnedDays)
        result.tutorialComplete = tutorialComplete || other.tutorialComplete
        result.rituals = CompanionTrigger.allCases.compactMap { trigger in
            let candidates = (rituals + other.rituals).filter { $0.trigger == trigger }
            return candidates.max {
                if $0.updatedAt == $1.updatedAt {
                    return "\($0.response.rawValue):\($0.isEnabled)" < "\($1.response.rawValue):\($1.isEnabled)"
                }
                return $0.updatedAt < $1.updatedAt
            }
        }
        return result
    }
}
