// CosmoOS/UI/FocusMode/Connection/ChalkboardModeOverlay.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Chalkboard is a MOOD, not a persisted mode. It dims the vellum room toward
// slate-black, swaps gilt for chalk-white, and invites loose thinking. The
// underlying state is untouched — this is just an atmospheric filter laid on
// top of the workshop for informal exploration.

import SwiftUI

struct ChalkboardModeOverlay: View {

    let isActive: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isActive {
                slate
                    .transition(.opacity)
                chalkHint
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                dismissButton
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(isActive)
        .animation(ProMotionSprings.focusTransition, value: isActive)
    }

    // MARK: - Slate

    private var slate: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
            // A faint chalk-dust vignette to keep the center luminous.
            RadialGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
        }
    }

    // MARK: - Chalk hint

    private var chalkHint: some View {
        VStack(spacing: 8) {
            Text("CHALKBOARD")
                .font(DS.smallCaps)
                .tracking(3.0)
                .foregroundStyle(Color.white.opacity(0.72))
            Text("Think loosely. Nothing is being saved.")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.35))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                Text("EXIT")
                    .font(DS.smallCaps)
                    .tracking(1.8)
            }
            .foregroundStyle(Color.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44, alignment: .center)
            .background(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(24)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Exit chalkboard mode")
    }
}
