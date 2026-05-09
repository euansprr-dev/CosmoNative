import Foundation

struct SensemakingSummary: Codable, Sendable, Equatable {
    let id: String
    let scopeID: String
    let summaryType: String
    let title: String
    let body: String
    let sourceIDs: [String]
    let createdAt: Date
}

actor CosmoSensemakingIndex {
    static let shared = CosmoSensemakingIndex()

    private var summaries: [SensemakingSummary] = []

    func upsert(_ summary: SensemakingSummary) async {
        summaries.removeAll { $0.id == summary.id }
        summaries.append(summary)
    }

    func summaries(scopeID: String) async -> [SensemakingSummary] {
        summaries.filter { $0.scopeID == scopeID }
    }
}
