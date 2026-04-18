// CosmoOS/UI/FocusMode/Connection/TheAtelierView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The right zone: 320pt of partner surfaces. Four stacked rows, top→bottom:
//   1. Concept Collaborator — dedicated Cosmo scoped to this one framework.
//   2. Live Insights — rolling AI observations (tension/gap/echo/strength/contradiction).
//   3. Maturity Crystal — the orb + threshold label.
//   4. Usage & Profiles — chips for where this framework lives downstream.
//
// The zone is deliberately calm: small caps labels, sepia hairlines, and
// proportional allocation that survives window resizing without compressing
// the collaborator into uselessness.

import SwiftUI

struct TheAtelierView: View {

    // MARK: - Collaborator

    @Binding var collaboratorMessages: [CollaboratorMessage]
    let isCollaboratorThinking: Bool
    let onSendMessage: (String) -> Void
    let onCrystallizeMessage: (CollaboratorMessage) -> Void

    // MARK: - Live Insights

    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let onRefreshInsights: () -> Void
    let onDismissInsight: (UUID) -> Void

    // MARK: - Crystal

    let filledSectionCount: Int
    let thresholdLabel: String
    let maturityDetail: String

    // MARK: - Usage & Profiles

    let contentUsages: [AtelierContentUsage]
    let profiles: [AtelierProfileChip]
    let onOpenContent: (String) -> Void
    let onAddProfile: () -> Void
    let onOpenProfile: (String) -> Void

    // MARK: - Framework identity (for collaborator panel)

    let frameworkTitle: String
    let conceptType: ConceptFrameworkType

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            collaboratorSection
            hairline
            insightsSection
            hairline
            crystalSection
            hairline
            usageSection
        }
        .frame(width: 320)
        .background(DS.vellum)
        .overlay(alignment: .leading) { verticalHairline }
    }

    // MARK: - Sections

    private var collaboratorSection: some View {
        ConceptCollaboratorPanel(
            messages: $collaboratorMessages,
            frameworkTitle: frameworkTitle,
            conceptType: conceptType,
            isThinking: isCollaboratorThinking,
            onSend: onSendMessage,
            onCrystallize: onCrystallizeMessage
        )
        .frame(maxHeight: .infinity)
    }

    private var insightsSection: some View {
        LiveInsightsPanel(
            insights: insights,
            isRefreshing: isRefreshingInsights,
            onRefresh: onRefreshInsights,
            onDismiss: onDismissInsight
        )
        .frame(height: 200)
    }

    private var crystalSection: some View {
        AtelierCrystalSection(
            filledSectionCount: filledSectionCount,
            thresholdLabel: thresholdLabel,
            detail: maturityDetail
        )
        .frame(height: 172)
    }

    private var usageSection: some View {
        AtelierUsageSection(
            usages: contentUsages,
            profiles: profiles,
            onOpenContent: onOpenContent,
            onOpenProfile: onOpenProfile,
            onAddProfile: onAddProfile
        )
        .frame(height: 112)
    }

    // MARK: - Ornaments

    private var hairline: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
    }

    private var verticalHairline: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(width: 0.5)
    }
}

// MARK: - Data shapes

struct AtelierContentUsage: Identifiable, Equatable {
    let id: String            // atom uuid
    let title: String
    let formatGlyph: String   // "film", "square.grid.2x2", etc.
}

struct AtelierProfileChip: Identifiable, Equatable {
    let id: String            // atom uuid
    let initial: String       // one-letter badge
    let title: String
}

// MARK: - Crystal Section

private struct AtelierCrystalSection: View {

    let filledSectionCount: Int
    let thresholdLabel: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            header
            MaturityCrystalView(filledCount: filledSectionCount, diameter: 84)
            thresholdRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond")
                .font(.system(size: 10))
                .foregroundStyle(DS.gilt.opacity(0.7))
                .accessibilityHidden(true)
            Text("MATURITY")
                .font(DS.smallCaps)
                .tracking(1.8)
                .foregroundStyle(DS.giltMuted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var thresholdRow: some View {
        VStack(spacing: 2) {
            Text(thresholdLabel)
                .font(DS.smallCaps)
                .tracking(2.0)
                .foregroundStyle(DS.inkWash)
            Text(detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DS.inkFaded)
        }
    }
}

// MARK: - Usage Section

/// Visible at file scope (was `private`) so V3's `ConnectionCanvasLayer` can
/// instantiate it directly as a canvas block.
struct AtelierUsageSection: View {

    let usages: [AtelierContentUsage]
    let profiles: [AtelierProfileChip]
    let onOpenContent: (String) -> Void
    let onOpenProfile: (String) -> Void
    let onAddProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            usageRow
            profileRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var usageRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("USED IN")
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)
            if usages.isEmpty {
                Text("No content references yet.")
                    .font(.system(size: 10, weight: .regular))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(usages) { usage in
                            contentChip(usage)
                        }
                    }
                }
            }
        }
    }

    private func contentChip(_ usage: AtelierContentUsage) -> some View {
        Button { onOpenContent(usage.id) } label: {
            HStack(spacing: 4) {
                Image(systemName: usage.formatGlyph)
                    .font(.system(size: 8))
                Text(usage.title)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .lineLimit(1)
            }
            .foregroundStyle(DS.inkWash.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().stroke(DS.sepiaBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var profileRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PROFILES")
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)
            HStack(spacing: 5) {
                ForEach(profiles) { profile in
                    profileChip(profile)
                }
                addProfileChip
                Spacer()
            }
        }
    }

    private func profileChip(_ profile: AtelierProfileChip) -> some View {
        Button { onOpenProfile(profile.id) } label: {
            Text(profile.initial.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .foregroundStyle(DS.entityConnection)
                .frame(width: 20, height: 20)
                .background(
                    Circle().stroke(DS.entityConnection.opacity(0.4), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile: \(profile.title)")
    }

    private var addProfileChip: some View {
        Button(action: onAddProfile) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 20, height: 20)
                .background(
                    Circle().stroke(DS.gilt.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add profile")
    }
}
