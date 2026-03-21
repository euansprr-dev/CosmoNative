// CosmoOS/UI/FocusMode/FocusSidebarTrigger.swift
// Sidebar trigger — invisible hover zone in standalone, visible button in panes

import SwiftUI

struct FocusSidebarTrigger: View {
    @Binding var isVisible: Bool

    @Environment(\.isPaneContext) private var isPaneContext

    @State private var isHovering = false
    @State private var dwellTimer: Timer?

    var body: some View {
        if isPaneContext {
            // Visible toggle button for pane contexts
            paneToggleButton
        }
        // Standalone mode: sidebar toggle lives in the focus mode's top bar
    }

    // MARK: - Pane Toggle Button

    private var paneToggleButton: some View {
        VStack {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isVisible ? DS.text : DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DS.glassCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.glassBorder, lineWidth: 0.5)
                    )
                    .shadow(
                        color: .black.opacity(isHovering ? 0.08 : 0.03),
                        radius: isHovering ? 8 : 4,
                        y: isHovering ? 2 : 1
                    )
                    .animation(ProMotionSprings.snappy, value: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help(isVisible ? "Hide sidebar" : "Show sidebar")
            .padding(.leading, 8)
            .padding(.top, 52) // Below the topBar back button

            Spacer()
        }
    }
}
