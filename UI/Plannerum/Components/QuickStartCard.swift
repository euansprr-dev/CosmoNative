//
//  QuickStartCard.swift
//  CosmoOS
//
//  Replaces the "All caught up!" empty state with an actionable quick-start
//  card. Users can name a timer, pick a duration preset, and start immediately.
//

import SwiftUI

// MARK: - QuickStartCard

struct QuickStartCard: View {

    // MARK: - Properties

    let onStartSession: (_ title: String, _ targetMinutes: Int) -> Void

    @State private var sessionTitle: String = ""
    @State private var selectedMinutes: Int = 25
    @State private var isHovering = false
    @State private var isStartHovering = false
    @FocusState private var isTitleFocused: Bool

    private let durationPresets: [(label: String, minutes: Int)] = [
        ("15m", 15),
        ("25m", 25),
        ("45m", 45),
        ("60m", 60)
    ]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header badge
            headerSection

            Spacer(minLength: FocusNowTokens.padding)

            // Title input
            titleField

            Spacer(minLength: 12)

            // Duration presets
            durationRow

            Spacer(minLength: FocusNowTokens.padding)

            // Start button
            startButton
        }
        .padding(FocusNowTokens.padding)
        .frame(minHeight: FocusNowTokens.cardMinHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.cornerRadius, style: .continuous))
        .overlay(cardBorder)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(FocusNowTokens.pressAnimation, value: isHovering)
        .onHover { isHovering = $0 }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: PlannerumLayout.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PlannerumColors.primary)

                Text("Quick Start")
                    .font(FocusNowTokens.contextFont)
                    .foregroundColor(PlannerumColors.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(PlannerumColors.primary.opacity(0.12))
            .clipShape(Capsule())

            Spacer()

            Text("What will you focus on?")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        TextField("What are you working on?", text: $sessionTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundColor(PlannerumColors.textPrimary)
            .focused($isTitleFocused)
            .onSubmit {
                if canStart {
                    onStartSession(sessionTitle, selectedMinutes)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isTitleFocused ? PlannerumColors.primary.opacity(0.5) : DS.borderSubtle,
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Duration Presets

    private var durationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)

            ForEach(durationPresets, id: \.minutes) { preset in
                durationCapsule(preset.label, minutes: preset.minutes)
            }

            Spacer()
        }
    }

    private func durationCapsule(_ label: String, minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes

        return Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedMinutes = minutes
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? DS.textOnAccent : PlannerumColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? PlannerumColors.primary : DS.surfaceHover)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start Button

    private var canStart: Bool {
        !sessionTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var startButton: some View {
        Button {
            onStartSession(sessionTitle, selectedMinutes)
        } label: {
            startButtonLabel
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .onHover { isStartHovering = $0 }
        .animation(FocusNowTokens.pressAnimation, value: isStartHovering)
        .keyboardShortcut(.return, modifiers: [])
    }

    @ViewBuilder
    private var startButtonLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Start · \(selectedMinutes)m")
                .font(FocusNowTokens.buttonFont)
        }
        .foregroundColor(canStart ? DS.textOnAccent : PlannerumColors.textTertiary)
        .frame(maxWidth: .infinity)
        .frame(height: FocusNowTokens.buttonHeight)
        .background(
            LinearGradient(
                colors: canStart
                    ? [PlannerumColors.primary, PlannerumColors.primary.opacity(0.8)]
                    : [DS.surfaceHover, DS.surfaceHover],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: FocusNowTokens.buttonCornerRadius, style: .continuous))
        .shadow(
            color: canStart ? PlannerumColors.primary.opacity(isStartHovering ? 0.5 : 0.3) : .clear,
            radius: isStartHovering ? 16 : 8,
            y: 4
        )
        .scaleEffect(isStartHovering && canStart ? 1.02 : 1.0)
    }

    // MARK: - Background & Border

    private var cardBackground: some View {
        LinearGradient(
            colors: [FocusNowTokens.gradientStart, FocusNowTokens.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: FocusNowTokens.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        isHovering ? DS.borderActive : DS.border,
                        isHovering ? DS.border : DS.borderSubtle
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
