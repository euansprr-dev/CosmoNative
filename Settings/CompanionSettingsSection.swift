// Settings/CompanionSettingsSection.swift
// The Greenhouse Companion in Mac Settings — who you are across both devices.
// An identity card wearing the live streak ring, and the grid of twelve to
// choose from. The choice writes the same user_preference atom the iPhone
// reads (scope "cosmo.companion"), so both mastheads move together.

import SwiftUI

struct CompanionSettingsSection: View {
    private var store: CompanionStore { CompanionStore.shared }

    @State private var hoveredCompanion: Companion?
    @State private var vitality: CompanionVitality = .resting
    @State private var streakLine: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.space12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            identityCard
            grid
        }
        .task {
            await store.hydrate()
            await loadVitality()
        }
    }

    // MARK: - Identity card (mark + name + the live ring)

    private var identityCard: some View {
        HStack(spacing: DS.space16) {
            CompanionMark(companion: store.companion, size: 48, vitality: vitality)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.companion.name) — \(store.companion.species)")
                    .font(DS.title3)
                    .foregroundStyle(DS.text)
                Text(streakLine ?? store.companion.bio)
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.opacity)
            }

            Spacer()

            Text("Syncs with your iPhone")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(DS.space16)
        .background(DS.glassCardFill)
        .clipShape(.rect(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - The grid of twelve

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: DS.space12) {
            ForEach(Companion.allCases) { companion in
                tile(companion)
            }
        }
    }

    private func tile(_ companion: Companion) -> some View {
        let isSelected = store.companion == companion
        let isHovered = hoveredCompanion == companion
        return Button {
            withAnimation(ProMotionSprings.bouncy) {
                store.select(companion)
            }
        } label: {
            VStack(spacing: DS.space6) {
                CompanionMark(companion: companion, size: 44)
                Text(companion.name)
                    .font(DS.caption)
                    .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, DS.space10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .fill(isSelected ? DS.accentSoft : (isHovered ? DS.surfaceHover : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .stroke(isSelected ? DS.accent : .clear, lineWidth: 1)
            )
            .scaleEffect(isHovered && !isSelected ? 1.03 : 1)
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredCompanion = hovering ? companion : nil
            }
        }
        .help("\(companion.name) \(companion.species) — \(companion.bio)")
        .accessibilityLabel("\(companion.name) \(companion.species). \(companion.bio)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Vitality (the same rules as the iPhone masthead)


    private func loadVitality() async {
        let engine = FocusStreakEngine()
        let goal = ((try? await engine.dailyFocusGoalMinutes()) ?? nil)
            ?? FocusStreakEngine.defaultGoalMinutes
        guard let streaks = try? await engine.focusStreaks(goal: goal),
              let byDay = try? await engine.focusSecondsByDay() else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let todayMet = (byDay[today] ?? 0) >= goal * 60

        let next: CompanionVitality
        if streaks.current >= 30 { next = .luminous }
        else if streaks.current >= 7 { next = .radiant }
        else if todayMet { next = .thriving }
        else { next = .resting }

        withAnimation(ProMotionSprings.gentle) {
            vitality = next
            switch next {
            case .resting: streakLine = nil
            case .thriving: streakLine = "Today's focus goal met."
            case .radiant: streakLine = "On a \(streaks.current)-day focus streak."
            case .luminous: streakLine = "A \(streaks.current)-day streak — wearing the star."
            }
        }
    }
}

// MARK: - Sidebar popover (the fast path — no Settings round-trip)

/// The compact picker anchored to the sidebar footer mark. Hovering a tile
/// introduces the companion in the caption line; clicking commits instantly.
struct CompanionPickerPopover: View {
    private var store: CompanionStore { CompanionStore.shared }

    @State private var hoveredCompanion: Companion?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.space8), count: 4)

    /// The companion the caption speaks about: hovered wins, else selected.
    private var spotlight: Companion { hoveredCompanion ?? store.companion }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("COMPANION")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)

            LazyVGrid(columns: columns, spacing: DS.space8) {
                ForEach(Companion.allCases) { companion in
                    tile(companion)
                }
            }

            // The introduction line — one companion at a time.
            VStack(alignment: .leading, spacing: 2) {
                Text("\(spotlight.name) — \(spotlight.species)")
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                Text(spotlight.bio)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(nil, value: spotlight)
        }
        .padding(DS.space16)
        .frame(width: 264)
        .task { await store.hydrate() }
    }

    private func tile(_ companion: Companion) -> some View {
        let isSelected = store.companion == companion
        let isHovered = hoveredCompanion == companion
        return Button {
            withAnimation(ProMotionSprings.bouncy) {
                store.select(companion)
            }
        } label: {
            CompanionMark(companion: companion, size: 38)
                .padding(DS.space6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous)
                        .fill(isSelected ? DS.accentSoft : (isHovered ? DS.surfaceHover : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous)
                        .stroke(isSelected ? DS.accent : .clear, lineWidth: 1)
                )
                .scaleEffect(isHovered && !isSelected ? 1.05 : 1)
                .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredCompanion = hovering ? companion : nil
            }
        }
        .accessibilityLabel("\(companion.name) \(companion.species). \(companion.bio)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
