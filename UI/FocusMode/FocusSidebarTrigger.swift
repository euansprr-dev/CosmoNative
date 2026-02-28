// CosmoOS/UI/FocusMode/FocusSidebarTrigger.swift
// Invisible hover zone at left edge to trigger focus mode sidebar

import SwiftUI

struct FocusSidebarTrigger: View {
    @Binding var isVisible: Bool

    @Environment(\.isPaneContext) private var isPaneContext

    /// In pane context the trigger zone is much narrower so the sidebar
    /// only appears when the cursor is right at the edge.
    private var triggerWidth: CGFloat { isPaneContext ? 6 : 20 }

    var body: some View {
        Color.clear
            .frame(width: triggerWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    withAnimation(ProMotionSprings.snappy) {
                        isVisible = true
                    }
                }
            }
    }
}
