// CosmoOS/UI/Shared/BlueprintPhysicsToggle.swift
// Toggle between text and physics display modes for blueprint views.

import SwiftUI

enum BlueprintDisplayMode: String, CaseIterable, Codable, Sendable {
    case text
    case physics

    var label: String {
        switch self {
        case .text: return "Text"
        case .physics: return "Physics"
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .physics: return "atom"
        }
    }
}

struct BlueprintPhysicsToggle: View {
    @Binding var mode: BlueprintDisplayMode

    var body: some View {
        Picker("Display", selection: $mode) {
            ForEach(BlueprintDisplayMode.allCases, id: \.self) { m in
                Label(m.label, systemImage: m.icon).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
    }
}
