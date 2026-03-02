// CosmoOS/Settings/CosmoAISettingsTab.swift
// Unified AI settings — merges Agent config + Writing & Skills into one tab
// March 2026

import SwiftUI

struct CosmoAISettingsTab: View {
    enum AISection: String, CaseIterable {
        case agent = "Agent"
        case writing = "Writing & Skills"

        var icon: String {
            switch self {
            case .agent: return "sparkles.rectangle.stack"
            case .writing: return "brain.head.profile"
            }
        }
    }

    @State private var selectedSection: AISection = .agent

    var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            // Header
            Text("Cosmo AI")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Configure AI provider, agent behavior, writing prompts, and skills")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Section picker
            HStack(spacing: 0) {
                ForEach(AISection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: SanctuaryLayout.Spacing.xs) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                        }
                        .foregroundColor(selectedSection == section ? SanctuaryColors.Text.primary : SanctuaryColors.Text.tertiary)
                        .padding(.horizontal, SanctuaryLayout.Spacing.md)
                        .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(selectedSection == section ? CosmoColors.lavender.opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm + 2)
                    .fill(SanctuaryColors.Glass.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm + 2)
                            .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                    )
            )

            // Section content
            switch selectedSection {
            case .agent:
                CosmoAgentSettingsTab()
            case .writing:
                SkillsAndPromptsSettingsTab()
            }
        }
    }
}
