import Foundation

enum CommandKQuicklinkRoute: Codable, Equatable {
    case commandCenter
    case commandKDomain(String)
    case atom(String)
    case thinkspace(String)
    case savedSearch(String)
}

struct CommandKQuicklink: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var route: CommandKQuicklinkRoute
    var query: String?
    var createdAt: Date
    var updatedAt: Date
}

struct CommandKMemoryClip: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var text: String
    var sourceAtomUUID: String?
    var createdAt: Date
    var lastUsedAt: Date
}

struct CommandKSnippet: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    func expanded(with values: [String: String]) -> String {
        values.reduce(body) { result, pair in
            result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
        }
    }
}

struct CommandKActionRecipe: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var actionIDs: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct CommandKUserCommandState: Codable, Equatable {
    var quicklinks: [CommandKQuicklink] = []
    var clips: [CommandKMemoryClip] = []
    var snippets: [CommandKSnippet] = []
    var recipes: [CommandKActionRecipe] = []
}
