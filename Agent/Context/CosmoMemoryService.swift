import Foundation

actor CosmoMemoryService {
    static let shared = CosmoMemoryService()

    private var coreByKey: [String: String] = [:]
    private var workingByConversationID: [String: [String]] = [:]
    private var archival: [String] = []

    static func inMemoryForTests() -> CosmoMemoryService {
        CosmoMemoryService()
    }

    func upsertCoreMemory(_ value: String, key: String) async throws {
        coreByKey[key] = value
    }

    func coreMemory() async throws -> [String] {
        coreByKey.keys.sorted().compactMap { coreByKey[$0] }
    }

    func upsertWorkingMemory(_ conversationID: String, value: String) async throws {
        var values = workingByConversationID[conversationID] ?? []
        if !values.contains(value) {
            values.append(value)
        }
        workingByConversationID[conversationID] = values
    }

    func workingMemory(conversationID: String) async throws -> [String] {
        workingByConversationID[conversationID] ?? []
    }

    func addArchivalMemory(_ value: String) async throws {
        archival.append(value)
    }

    func searchArchivalMemory(query: String, limit: Int = 5) async throws -> [String] {
        let terms = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        guard !terms.isEmpty else { return Array(archival.prefix(limit)) }

        return archival
            .filter { memory in
                let lower = memory.lowercased()
                return terms.contains { lower.contains($0) }
            }
            .prefix(limit)
            .map { $0 }
    }
}
