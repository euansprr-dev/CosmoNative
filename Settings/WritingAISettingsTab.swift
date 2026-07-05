// CosmoOS/Settings/WritingAISettingsTab.swift
// Writing & AI — one home for everything the agent writes with: agent
// configuration, skills & prompts, brand profiles, and reusable document
// elements. Replaces the separate Cosmo AI / Profiles / Elements tabs.

import SwiftUI

struct WritingAISettingsTab: View {
    enum Section: String, CaseIterable, Identifiable {
        case agent = "Agent"
        case writing = "Skills & Prompts"
        case profiles = "Profiles"
        case elements = "Elements"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .agent: return "sparkles.rectangle.stack"
            case .writing: return "brain.head.profile"
            case .profiles: return "person.2.fill"
            case .elements: return "square.stack.3d.up"
            }
        }
    }

    @State private var selectedSection: Section = .agent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            sectionSwitch

            switch selectedSection {
            case .agent:
                CosmoAgentSettingsTab()
            case .writing:
                SkillsAndPromptsSettingsTab()
            case .profiles:
                ProfileManagementTab()
            case .elements:
                ElementsSettingsTab()
            }
        }
    }

    private var sectionSwitch: some View {
        HStack(spacing: 3) {
            ForEach(Section.allCases) { section in
                let isSelected = selectedSection == section
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: DS.space4) {
                        Image(systemName: section.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(section.rawValue)
                            .font(DS.callout)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .foregroundStyle(isSelected ? DS.text : DS.textMuted)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space6)
                    .background(
                        isSelected ? AnyShapeStyle(DS.surfaceElevated) : AnyShapeStyle(Color.clear),
                        in: Capsule(style: .continuous)
                    )
                    .overlay {
                        if isSelected {
                            Capsule(style: .continuous)
                                .stroke(DS.border, lineWidth: 0.5)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(DS.glassSectionFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(DS.glassBorder, lineWidth: 1))
    }
}
