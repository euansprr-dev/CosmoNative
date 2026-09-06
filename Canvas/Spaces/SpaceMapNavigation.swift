import SwiftUI

enum SpaceInquiryMode: String, CaseIterable { case inquiries, map }

/// Local navigation preferences never mutate the shared Space or its documents.
@MainActor @Observable
final class SpaceMapPreferences {
    static let shared = SpaceMapPreferences()
    private var modes: [String: SpaceInquiryMode] = [:]
    private var topics: [String: String] = [:]
    private var materialVisibility: [String: Bool] = [:]

    func mode(in id: String) -> SpaceInquiryMode {
        modes[id] ?? SpaceInquiryMode(rawValue: UserDefaults.standard.string(forKey: key(id, "mode")) ?? "") ?? .inquiries
    }
    func select(_ mode: SpaceInquiryMode, in id: String) {
        modes[id] = mode; UserDefaults.standard.set(mode.rawValue, forKey: key(id, "mode"))
    }
    func topic(in id: String) -> String {
        topics[id] ?? UserDefaults.standard.string(forKey: key(id, "topic")) ?? ""
    }
    func selectTopic(_ topic: String, in id: String) {
        topics[id] = topic; UserDefaults.standard.set(topic, forKey: key(id, "topic"))
    }
    func showsMaterials(in id: String) -> Bool {
        materialVisibility[id] ?? UserDefaults.standard.bool(forKey: key(id, "materials"))
    }
    func showMaterials(_ value: Bool, in id: String) {
        materialVisibility[id] = value; UserDefaults.standard.set(value, forKey: key(id, "materials"))
    }
    private func key(_ id: String, _ field: String) -> String { "cosmo.space.map.mac.\(id).\(field)" }
}

@MainActor enum SpaceMapNavigation {
    static func open(in spaceID: String) {
        SpaceMapPreferences.shared.select(.map, in: spaceID)
        SpaceWorkspaceStore.shared.showRoot(.deepDive, in: spaceID)
    }
}
