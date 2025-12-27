// CosmoOS/Data/Models/LegacyTypeStubs.swift
// Stub types for legacy code compatibility
// These allow the codebase to compile while migrating to pure Atom architecture

import SwiftUI

// MARK: - PromotionAction

enum PromotionAction: Equatable {
    case expandIdea
    case turnIntoContent
    case turnIntoTask
    case dismiss
    case assignToProject(projectId: Int64)
}

// MARK: - InboxViewsMode (Stub View)

struct InboxViewsMode: View {
    @Binding var selectedIndex: Int
    let onSelect: (InboxViewSelection) -> Void

    var body: some View {
        // Stub - legacy inbox view replaced by Plannerium
        EmptyView()
    }
}

// MARK: - KeyboardKey (Stub View)

struct KeyboardKey: View {
    let symbol: String

    init(symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
            )
    }
}

// MARK: - PromotionAnimationPhase
// Note: AssignmentStatus is defined in Atom.swift

enum PromotionAnimationPhase {
    case idle
    case promoting
    case complete
}
