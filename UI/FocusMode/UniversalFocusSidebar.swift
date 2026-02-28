// CosmoOS/UI/FocusMode/UniversalFocusSidebar.swift
// Generic sidebar component for all focus modes
// Follows ThinkspaceSidebar hover/lock/close-delay patterns

import SwiftUI

struct UniversalFocusSidebar<Content: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    @Binding var isVisible: Bool
    @ViewBuilder let content: () -> Content

    // Lock state - persisted across sessions
    @AppStorage("focusSidebarLocked") private var isLocked: Bool = false

    // Internal hover tracking for close behavior
    @State private var isHovering: Bool = false
    @State private var closeTimer: Timer?

    private let sidebarWidth: CGFloat = 280

    /// Whether sidebar should be visible
    /// Stays open if locked, visible via trigger, or being hovered
    var shouldShow: Bool {
        isLocked || isVisible || isHovering
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(DS.borderActive)

            ScrollView {
                content()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: sidebarWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 5)
        .offset(x: shouldShow ? 0 : -300)
        .animation(ProMotionSprings.snappy, value: shouldShow)
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accentColor)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(DS.textSecondary)
                .tracking(1.2)

            Spacer()

            // Lock button
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isLocked.toggle()
                }
            } label: {
                Image(systemName: isLocked ? "pin.fill" : "pin.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isLocked ? DS.text : DS.textMuted)
                    .padding(6)
                    .background(
                        isLocked
                            ? accentColor.opacity(0.12)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isLocked ? 1.0 : 0.95)
            .animation(ProMotionSprings.snappy, value: isLocked)
            .help(isLocked ? "Unlock sidebar (auto-hide)" : "Lock sidebar open")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Hover / Close Logic

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Cancel any pending close
            closeTimer?.invalidate()
            closeTimer = nil
            isHovering = true
        } else {
            // Don't close if locked
            guard !isLocked else {
                isHovering = false
                return
            }

            // Delay close to prevent flicker when moving between trigger and sidebar
            closeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(ProMotionSprings.snappy) {
                        self.isHovering = false
                        self.isVisible = false
                    }
                }
            }
        }
    }
}
