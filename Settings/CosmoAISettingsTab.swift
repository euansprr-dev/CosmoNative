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
        VStack(alignment: .leading, spacing: DS.space24) {
            // Header
            Text("Cosmo AI")
                .font(DS.title2)
                .foregroundColor(DS.text)

            Text("Configure AI provider, agent behavior, writing prompts, and skills")
                .font(DS.callout)
                .foregroundColor(DS.textMuted)

            // Section picker
            HStack(spacing: 0) {
                ForEach(AISection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: DS.space4) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                        }
                        .foregroundColor(selectedSection == section ? DS.text : DS.textMuted)
                        .padding(.horizontal, DS.space12)
                        .padding(.vertical, DS.space8 + 2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(selectedSection == section ? CosmoColors.lavender.opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall + 2)
                    .fill(DS.surfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall + 2)
                            .stroke(DS.borderSubtle, lineWidth: 1)
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
