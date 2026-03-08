// CosmoOS/Settings/SkillsAndPromptsSettingsTab.swift
// Unified settings tab for AI skills, prompts, and learned patterns
// February 2026

import SwiftUI

struct SkillsAndPromptsSettingsTab: View {
    @StateObject private var promptStore = PromptTemplateStore.shared

    // Collapsible sections
    @State private var isUnifiedPromptExpanded = false
    @State private var isMethodologyExpanded = false
    @State private var isPlatformExpanded = false
    @State private var isSkillModulesExpanded = false
    @State private var isLearnedSkillsExpanded = false
    @State private var isBatchAnalysisExpanded = false

    // Skill modules editing
    @State private var editingModuleId: String? = nil
    @State private var isAddModulePresented = false
    @State private var newModuleTitle = ""
    @State private var newModuleContent = ""

    // Learned skills
    @State private var learnedSkills: [InferredLesson] = []
    @State private var selectedIntentFilter: String = "all"
    @State private var selectedEnforcementFilter: String = "all"
    @State private var editingSkillId: UUID? = nil
    @State private var editingSkillRule: String = ""
    @State private var editingSkillIntent: String = "universal"

    // Batch analysis
    @State private var editingReportId: String? = nil
    @State private var editingReportContent: String = ""

    private let intentFilters = ["all", "universal", "draft", "plan", "strategy", "brainstorm", "analyze", "reflect"]

    var body: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.lg) {
            Text("Skills & Prompts")
                .font(SanctuaryTypography.titleMedium)
                .foregroundColor(SanctuaryColors.Text.primary)

            Text("Configure AI behavior, writing methodology, and learned skills")
                .font(SanctuaryTypography.bodyMedium)
                .foregroundColor(SanctuaryColors.Text.tertiary)

            // Section 1: Master Prompt
            unifiedPromptSection

            // Section 2: Content Methodology
            methodologySection

            // Section 3: Platform Constraints
            platformConstraintsSection

            // Section 4: Skill Modules
            skillModulesSection

            // Section 5: Learned Skills
            learnedSkillsSection

            // Section 6: Batch Analysis Reports
            batchAnalysisSection

            Spacer(minLength: SanctuaryLayout.Spacing.lg)
        }
        .task {
            await loadLearnedSkills()
        }
    }

    // MARK: - Section 1: Unified System Prompt

    private var unifiedPromptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "System Prompt",
                subtitle: promptStore.isUnifiedDirty ? "Modified" : "\(promptStore.unifiedTokenCount()) tokens",
                icon: "text.alignleft",
                isExpanded: $isUnifiedPromptExpanded,
                statusColor: promptStore.isUnifiedDirty ? .orange : nil
            )

            if isUnifiedPromptExpanded {
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    Text("The unified system prompt that defines the AI writing partner's behavior. Includes {METHODOLOGY_TEXT} and {PLATFORM_CONSTRAINTS} placeholders.")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    WritingEngineTextEditor(text: $promptStore.unifiedSystemPrompt)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(SanctuaryColors.Glass.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                        .stroke(promptStore.isUnifiedDirty ? CosmoColors.cosmoAI.opacity(0.4) : SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))
                        .onChange(of: promptStore.unifiedSystemPrompt) { newValue in
                            promptStore.isUnifiedDirty = newValue != PromptTemplateStore.DEFAULT_UNIFIED_SYSTEM_PROMPT
                        }

                    Text("\(promptStore.unifiedTokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.muted)

                    sanctuaryButtons(
                        onSave: { promptStore.saveUnifiedSystemPrompt() },
                        onReset: { promptStore.resetUnifiedToDefault() },
                        isDirty: promptStore.isUnifiedDirty
                    )
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    // MARK: - Section 2: Content Methodology

    private var methodologySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Content Methodology",
                subtitle: promptStore.isDirty ? "Modified" : "\(promptStore.tokenCount()) tokens",
                icon: "book.closed",
                isExpanded: $isMethodologyExpanded,
                statusColor: promptStore.isDirty ? .orange : nil
            )

            if isMethodologyExpanded {
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    Text("The foundational content playbook injected as context for all AI generation.")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    WritingEngineTextEditor(text: $promptStore.methodology)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(SanctuaryColors.Glass.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                        .stroke(promptStore.isDirty ? CosmoColors.cosmoAI.opacity(0.4) : SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))
                        .onChange(of: promptStore.methodology) { newValue in
                            promptStore.isDirty = newValue != PromptTemplateStore.DEFAULT_METHODOLOGY
                        }

                    Text("\(promptStore.tokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.muted)

                    sanctuaryButtons(
                        onSave: { promptStore.saveMethodology() },
                        onReset: { promptStore.resetToDefault() },
                        isDirty: promptStore.isDirty
                    )
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    // MARK: - Section 3: Platform Constraints

    private var platformConstraintsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Platform Constraints",
                subtitle: promptStore.isPlatformConstraintsDirty ? "Modified" : "\(promptStore.platformConstraintsTokenCount()) tokens",
                icon: "rectangle.3.group",
                isExpanded: $isPlatformExpanded,
                statusColor: promptStore.isPlatformConstraintsDirty ? .orange : nil
            )

            if isPlatformExpanded {
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    Text("Hard format rules for each platform (character limits, slide counts, durations).")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    WritingEngineTextEditor(text: $promptStore.platformConstraints)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(SanctuaryColors.Glass.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                        .stroke(promptStore.isPlatformConstraintsDirty ? CosmoColors.cosmoAI.opacity(0.4) : SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))
                        .onChange(of: promptStore.platformConstraints) { newValue in
                            promptStore.isPlatformConstraintsDirty = newValue != PromptTemplateStore.DEFAULT_PLATFORM_CONSTRAINTS
                        }

                    Text("\(promptStore.platformConstraintsTokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.muted)

                    sanctuaryButtons(
                        onSave: { promptStore.savePlatformConstraints() },
                        onReset: { promptStore.resetPlatformConstraintsToDefault() },
                        isDirty: promptStore.isPlatformConstraintsDirty
                    )
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    // MARK: - Section 4: Skill Modules

    private var skillModulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let enabledCount = promptStore.modules.filter(\.isEnabled).count
            let totalCount = promptStore.modules.count
            sectionHeader(
                title: "Skill Modules",
                subtitle: "\(enabledCount)/\(totalCount) active",
                icon: "text.badge.star",
                isExpanded: $isSkillModulesExpanded
            )

            if isSkillModulesExpanded {
                VStack(spacing: SanctuaryLayout.Spacing.sm) {
                    ForEach(promptStore.modules) { module in
                        skillModuleRow(module: module)
                    }

                    // Add Module inline form
                    if isAddModulePresented {
                        addModuleForm
                    }

                    HStack(spacing: SanctuaryLayout.Spacing.sm) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isAddModulePresented.toggle()
                                newModuleTitle = ""
                                newModuleContent = ""
                            }
                        }) {
                            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                                Image(systemName: isAddModulePresented ? "xmark" : "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text(isAddModulePresented ? "Cancel" : "Add Module")
                                    .font(SanctuaryTypography.label)
                            }
                            .foregroundColor(CosmoColors.cosmoAI)
                            .padding(.horizontal, SanctuaryLayout.Spacing.md)
                            .padding(.vertical, SanctuaryLayout.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                    .fill(CosmoColors.cosmoAI.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: {
                            promptStore.resetAllModulesToDefaults()
                            editingModuleId = nil
                        }) {
                            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("Reset All to Defaults")
                                    .font(SanctuaryTypography.label)
                            }
                            .foregroundColor(SanctuaryColors.Text.secondary)
                            .padding(.horizontal, SanctuaryLayout.Spacing.md)
                            .padding(.vertical, SanctuaryLayout.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                    .fill(SanctuaryColors.Glass.secondary)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, SanctuaryLayout.Spacing.xs)
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    @ViewBuilder
    private func skillModuleRow(module: PromptModule) -> some View {
        let isEditing = editingModuleId == module.id
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Toggle("", isOn: Binding(
                    get: { module.isEnabled },
                    set: { newValue in
                        if let idx = promptStore.modules.firstIndex(where: { $0.id == module.id }) {
                            promptStore.modules[idx].isEnabled = newValue
                            promptStore.saveModuleState()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SanctuaryLayout.Spacing.xs) {
                        Text(module.title)
                            .font(SanctuaryTypography.label)
                            .foregroundColor(module.isEnabled ? SanctuaryColors.Text.primary : SanctuaryColors.Text.muted)

                        if promptStore.isCustomModule(id: module.id) {
                            Text("Custom")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange.opacity(0.1))
                                )
                        } else {
                            Text("Core")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.teal.opacity(0.1))
                                )
                        }

                        let linkedCount = learnedSkills.filter { lesson in
                            (lesson.targetModuleId == module.id) ||
                            (lesson.targetModuleId == nil && PromptTemplateStore.categoryToModuleMap[lesson.category] == module.id)
                        }.count
                        if linkedCount > 0 {
                            Text("\(linkedCount) rules")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green.opacity(0.1))
                                )
                        }
                    }

                    Text("~\(promptStore.moduleTokenCount(module)) tokens")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.muted)
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        editingModuleId = isEditing ? nil : module.id
                    }
                }) {
                    Image(systemName: isEditing ? "chevron.up" : "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(CosmoColors.cosmoAI)
                        .padding(6)
                        .background(Circle().fill(CosmoColors.cosmoAI.opacity(0.15)))
                }
                .buttonStyle(.plain)

                if isModuleEdited(module) {
                    Button(action: {
                        promptStore.resetModuleToDefault(moduleId: module.id)
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.muted)
                            .padding(5)
                            .background(Circle().fill(SanctuaryColors.Glass.secondary))
                    }
                    .buttonStyle(.plain)
                }

                if promptStore.isCustomModule(id: module.id) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            promptStore.removeCustomModule(id: module.id)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Semantic.error)
                            .padding(5)
                            .background(Circle().fill(SanctuaryColors.Semantic.error.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditing {
                skillModuleEditor(moduleId: module.id)
            }
        }
        .padding(.horizontal, SanctuaryLayout.Spacing.sm)
        .padding(.vertical, SanctuaryLayout.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(
            module.isEnabled ? SanctuaryColors.Glass.secondary : Color.clear
        ))
    }

    @ViewBuilder
    private func skillModuleEditor(moduleId: String) -> some View {
        if let idx = promptStore.modules.firstIndex(where: { $0.id == moduleId }) {
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                WritingEngineTextEditor(text: $promptStore.modules[idx].content)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .fill(SanctuaryColors.Glass.secondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                    .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

                HStack(spacing: SanctuaryLayout.Spacing.sm) {
                    Button(action: {
                        promptStore.saveModuleState()
                        editingModuleId = nil
                    }) {
                        HStack(spacing: SanctuaryLayout.Spacing.xs) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10))
                            Text("Save")
                                .font(SanctuaryTypography.label)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                        .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                        .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(CosmoColors.cosmoAI))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        promptStore.resetModuleToDefault(moduleId: moduleId)
                        editingModuleId = nil
                    }) {
                        Text("Cancel")
                            .font(SanctuaryTypography.label)
                            .foregroundColor(SanctuaryColors.Text.muted)
                            .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                            .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            .padding(.top, SanctuaryLayout.Spacing.xs)
        }
    }

    private func isModuleEdited(_ module: PromptModule) -> Bool {
        guard let defaultModule = PromptTemplateStore.defaultModules.first(where: { $0.id == module.id }) else {
            return false
        }
        return module.content != defaultModule.content
    }

    @ViewBuilder
    private var addModuleForm: some View {
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
            Text("New Skill Module")
                .font(SanctuaryTypography.label)
                .foregroundColor(SanctuaryColors.Text.primary)

            TextField("Module title", text: $newModuleTitle)
                .textFieldStyle(.plain)
                .font(SanctuaryTypography.bodySmall)
                .foregroundColor(SanctuaryColors.Text.primary)
                .padding(SanctuaryLayout.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.secondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                        )
                )

            addModuleIdLabel

            WritingEngineTextEditor(text: $newModuleContent)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.secondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))

            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Button(action: createCustomModule) {
                    HStack(spacing: SanctuaryLayout.Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                        Text("Create Module")
                            .font(SanctuaryTypography.label)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                    .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                    .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(
                        canCreateModule ? CosmoColors.cosmoAI : CosmoColors.cosmoAI.opacity(0.3)
                    ))
                }
                .buttonStyle(.plain)
                .disabled(!canCreateModule)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAddModulePresented = false
                    }
                }) {
                    Text("Cancel")
                        .font(SanctuaryTypography.label)
                        .foregroundColor(SanctuaryColors.Text.muted)
                        .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                        .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(SanctuaryLayout.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                .fill(CosmoColors.cosmoAI.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .stroke(CosmoColors.cosmoAI.opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var addModuleIdLabel: some View {
        let generatedId = newModuleTitle.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        Text("ID: \(generatedId.isEmpty ? "..." : generatedId)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(SanctuaryColors.Text.muted)
    }

    private var canCreateModule: Bool {
        !newModuleTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newModuleContent.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createCustomModule() {
        let title = newModuleTitle.trimmingCharacters(in: .whitespaces)
        let content = newModuleContent.trimmingCharacters(in: .whitespaces)
        let id = title.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)

        guard !id.isEmpty, !title.isEmpty, !content.isEmpty else { return }

        promptStore.addCustomModule(id: id, title: title, content: content)
        withAnimation(.easeInOut(duration: 0.15)) {
            isAddModulePresented = false
            newModuleTitle = ""
            newModuleContent = ""
        }
    }

    // MARK: - Section 5: Learned Skills

    private var learnedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Learned Skills",
                subtitle: "\(learnedSkills.count) skills",
                icon: "brain",
                isExpanded: $isLearnedSkillsExpanded
            )

            if isLearnedSkillsExpanded {
                VStack(spacing: SanctuaryLayout.Spacing.md) {
                    // Filter chips
                    VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                                ForEach(intentFilters, id: \.self) { filter in
                                    intentFilterChip(filter)
                                }
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                                ForEach(["all", "hard", "advisory"], id: \.self) { filter in
                                    enforcementFilterChip(filter)
                                }
                            }
                        }
                    }

                    if filteredSkills.isEmpty {
                        VStack(spacing: SanctuaryLayout.Spacing.sm) {
                            Image(systemName: "brain")
                                .font(.system(size: 24))
                                .foregroundColor(SanctuaryColors.Text.muted)
                            Text("No skills learned yet. As you work with Cosmo, skills will appear here.")
                                .font(SanctuaryTypography.bodySmall)
                                .foregroundColor(SanctuaryColors.Text.muted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, SanctuaryLayout.Spacing.lg)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(filteredSkills) { skill in
                            learnedSkillRow(skill)
                        }
                    }
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    private var filteredSkills: [InferredLesson] {
        var result = learnedSkills

        // Intent filter
        switch selectedIntentFilter {
        case "all": break
        case "universal":
            result = result.filter { $0.intent == nil }
        default:
            result = result.filter { $0.intent == selectedIntentFilter }
        }

        // Enforcement filter
        switch selectedEnforcementFilter {
        case "hard":
            result = result.filter { $0.effectiveEnforcement == .hard }
        case "advisory":
            result = result.filter { $0.effectiveEnforcement == .advisory }
        default: break
        }

        return result
    }

    @ViewBuilder
    private func intentFilterChip(_ filter: String) -> some View {
        let isSelected = selectedIntentFilter == filter
        Button(action: { selectedIntentFilter = filter }) {
            Text(filter.capitalized)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : SanctuaryColors.Text.secondary)
                .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                .background(
                    Capsule().fill(isSelected ? CosmoColors.cosmoAI : SanctuaryColors.Glass.secondary)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func enforcementFilterChip(_ filter: String) -> some View {
        let isSelected = selectedEnforcementFilter == filter
        let chipColor: Color = filter == "hard" ? .red : filter == "advisory" ? .orange : CosmoColors.cosmoAI
        Button(action: { selectedEnforcementFilter = filter }) {
            Text(filter.capitalized)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : SanctuaryColors.Text.secondary)
                .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                .padding(.vertical, SanctuaryLayout.Spacing.xs + 1)
                .background(
                    Capsule().fill(isSelected ? chipColor : SanctuaryColors.Glass.secondary)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func learnedSkillRow(_ skill: InferredLesson) -> some View {
        let isEditing = editingSkillId == skill.id
        VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
            HStack(alignment: .top, spacing: SanctuaryLayout.Spacing.sm) {
                Circle()
                    .fill(confidenceColor(skill.confidence))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.xs) {
                    if isEditing {
                        TextField("Rule text", text: $editingSkillRule, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(SanctuaryTypography.bodySmall)
                            .foregroundColor(SanctuaryColors.Text.primary)
                            .lineLimit(3...6)
                            .padding(SanctuaryLayout.Spacing.sm)
                            .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(SanctuaryColors.Glass.secondary))
                    } else {
                        Text(skill.rule)
                            .font(SanctuaryTypography.bodySmall)
                            .foregroundColor(SanctuaryColors.Text.primary)
                            .lineLimit(2)
                    }

                    HStack(spacing: SanctuaryLayout.Spacing.xs) {
                        enforcementBadge(skill.effectiveEnforcement)
                        categoryBadge(skill.category)
                        intentBadge(skill.intent ?? "universal")
                        confidenceBar(skill.confidence)

                        if let moduleId = skill.targetModuleId ?? PromptTemplateStore.categoryToModuleMap[skill.category],
                           let module = promptStore.modules.first(where: { $0.id == moduleId }) {
                            Text(module.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green.opacity(0.1))
                                )
                        }

                        if skill.clientUUID != nil {
                            Text("client-specific")
                                .font(.system(size: 9))
                                .foregroundColor(SanctuaryColors.Text.muted)
                        }
                    }

                    if isEditing {
                        HStack(spacing: SanctuaryLayout.Spacing.xs) {
                            Text("Scope:")
                                .font(.system(size: 11))
                                .foregroundColor(SanctuaryColors.Text.muted)
                            Picker("", selection: $editingSkillIntent) {
                                Text("Universal").tag("universal")
                                Text("Draft").tag("draft")
                                Text("Plan").tag("plan")
                                Text("Strategy").tag("strategy")
                                Text("Brainstorm").tag("brainstorm")
                                Text("Analyze").tag("analyze")
                                Text("Reflect").tag("reflect")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }

                        HStack(spacing: SanctuaryLayout.Spacing.sm) {
                            Button(action: { saveEditedSkill(skill) }) {
                                Text("Save")
                                    .font(SanctuaryTypography.label)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, SanctuaryLayout.Spacing.sm + 2)
                                    .padding(.vertical, SanctuaryLayout.Spacing.xs)
                                    .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(CosmoColors.cosmoAI))
                            }
                            .buttonStyle(.plain)

                            Button(action: { editingSkillId = nil }) {
                                Text("Cancel")
                                    .font(SanctuaryTypography.label)
                                    .foregroundColor(SanctuaryColors.Text.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                if !isEditing {
                    Button(action: {
                        editingSkillId = skill.id
                        editingSkillRule = skill.rule
                        editingSkillIntent = skill.intent ?? "universal"
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.muted)
                    }
                    .buttonStyle(.plain)

                    Button(action: { deleteLearnedSkill(skill) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(SanctuaryColors.Text.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, SanctuaryLayout.Spacing.xs)
    }

    // MARK: - Section 6: Batch Analysis Reports

    private var batchAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Batch Analysis Reports",
                subtitle: promptStore.batchAnalysisReports.isEmpty ? "No reports" : "\(promptStore.batchAnalysisReports.count) reports",
                icon: "chart.bar.doc.horizontal",
                isExpanded: $isBatchAnalysisExpanded
            )

            if isBatchAnalysisExpanded {
                VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.md) {
                    Text("Pattern analysis reports generated from your swipe library.")
                        .font(SanctuaryTypography.bodySmall)
                        .foregroundColor(SanctuaryColors.Text.tertiary)

                    if promptStore.batchAnalysisReports.isEmpty {
                        HStack(spacing: SanctuaryLayout.Spacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundColor(SanctuaryColors.Text.muted)
                            Text("Reports are generated automatically every 30 swipes per content type.")
                                .font(SanctuaryTypography.bodySmall)
                                .foregroundColor(SanctuaryColors.Text.muted)
                        }
                        .padding(SanctuaryLayout.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(SanctuaryColors.Glass.secondary))
                    } else {
                        batchReportsList
                    }

                    addReportButton
                }
                .padding(SanctuaryLayout.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    @ViewBuilder
    private var batchReportsList: some View {
        ForEach(promptStore.batchAnalysisReports) { report in
            VStack(alignment: .leading, spacing: SanctuaryLayout.Spacing.sm) {
                HStack {
                    Text(report.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text("\(report.swipeCount) swipes")
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CosmoColors.cosmoAI.opacity(0.15)))
                        .foregroundColor(CosmoColors.cosmoAI)

                    Spacer()

                    Text(report.dateLabel)
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.muted)

                    Button(action: {
                        if editingReportId == report.id {
                            promptStore.updateBatchAnalysisReport(report, newContent: editingReportContent)
                            editingReportId = nil
                        } else {
                            editingReportId = report.id
                            editingReportContent = report.content
                        }
                    }) {
                        Image(systemName: editingReportId == report.id ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(SanctuaryColors.Text.muted)
                    }
                    .buttonStyle(.plain)

                    Button(action: { promptStore.deleteBatchAnalysisReport(report) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(SanctuaryColors.Text.muted)
                    }
                    .buttonStyle(.plain)
                }

                if editingReportId == report.id {
                    WritingEngineTextEditor(text: $editingReportContent)
                        .frame(height: 180)
                        .background(
                            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                .fill(SanctuaryColors.Glass.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                                        .stroke(CosmoColors.cosmoAI.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm))
                } else {
                    Text(report.content.prefix(300) + (report.content.count > 300 ? "..." : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                        .lineLimit(6)
                }
            }
            .padding(SanctuaryLayout.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm).fill(SanctuaryColors.Glass.secondary))
        }
    }

    @ViewBuilder
    private var addReportButton: some View {
        Button(action: {
            promptStore.saveBatchAnalysisReport(
                sourceType: "instagram_carousel",
                swipeCount: 0,
                content: "Paste your batch analysis here..."
            )
            if let newReport = promptStore.batchAnalysisReports.first {
                editingReportId = newReport.id
                editingReportContent = newReport.content
            }
        }) {
            HStack(spacing: SanctuaryLayout.Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                Text("Add Report Manually")
                    .font(SanctuaryTypography.label)
            }
            .foregroundColor(SanctuaryColors.Text.secondary)
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                    .fill(SanctuaryColors.Glass.secondary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - UI Components

    @ViewBuilder
    private func categoryBadge(_ category: String) -> some View {
        Text(category.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(CosmoColors.cosmoAI)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(CosmoColors.cosmoAI.opacity(0.1))
            )
    }

    @ViewBuilder
    private func intentBadge(_ intent: String) -> some View {
        let color = intentColor(intent)
        Text(intent)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.1))
            )
    }

    @ViewBuilder
    private func confidenceBar(_ confidence: Double) -> some View {
        GeometryReader { _ in
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) / 5.0 < confidence ? confidenceColor(confidence) : SanctuaryColors.Glass.borderSubtle)
                        .frame(width: 6, height: 4)
                }
            }
        }
        .frame(width: 34, height: 4)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return SanctuaryColors.Semantic.success }
        if confidence >= 0.5 { return .orange }
        return SanctuaryColors.Semantic.error
    }

    @ViewBuilder
    private func enforcementBadge(_ enforcement: LessonEnforcement) -> some View {
        let isHard = enforcement == .hard
        let color: Color = isHard ? .red : SanctuaryColors.Text.muted
        Text(isHard ? "Hard" : "Advisory")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.1))
            )
    }

    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "draft": return .purple
        case "plan": return .blue
        case "strategy": return .orange
        case "brainstorm": return .green
        case "analyze": return .cyan
        case "reflect": return .pink
        default: return SanctuaryColors.Text.muted
        }
    }

    // MARK: - Actions

    private func loadLearnedSkills() async {
        learnedSkills = await LessonExtractor.shared.loadLessons(minConfidence: 0.0)
    }

    private func saveEditedSkill(_ skill: InferredLesson) {
        Task {
            let newIntent = editingSkillIntent == "universal" ? nil : editingSkillIntent
            var updated = InferredLesson(
                id: skill.id,
                clientUUID: skill.clientUUID,
                rule: editingSkillRule,
                evidence: skill.evidence,
                category: skill.category,
                confidence: skill.confidence,
                createdAt: skill.createdAt,
                lastConfirmedAt: Date(),
                optimizedInstruction: skill.optimizedInstruction,
                intent: newIntent
            )
            updated.source = skill.source
            updated.enforcement = skill.enforcement
            updated.targetModuleId = skill.targetModuleId

            let repo = AtomRepository.shared
            let atoms = try? await repo.fetchAll(type: .agentLearning)
            if var atom = atoms?.first(where: { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonID"] as? String == skill.id.uuidString
            }) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(updated) {
                    atom.structured = String(data: data, encoding: .utf8)
                    atom.body = editingSkillRule

                    var meta = atom.metadataDict ?? [:]
                    meta["intent"] = newIntent ?? ""
                    if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                       let metaStr = String(data: metaData, encoding: .utf8) {
                        atom.metadata = metaStr
                    }

                    _ = try? await repo.update(atom)
                }
            }

            editingSkillId = nil
            await loadLearnedSkills()
        }
    }

    private func deleteLearnedSkill(_ skill: InferredLesson) {
        Task {
            let repo = AtomRepository.shared
            let atoms = try? await repo.fetchAll(type: .agentLearning)
            if var atom = atoms?.first(where: { atom in
                guard let meta = atom.metadataDict else { return false }
                return meta["lessonID"] as? String == skill.id.uuidString
            }) {
                atom.isDeleted = true
                _ = try? await repo.update(atom)
            }
            await loadLearnedSkills()
        }
    }

    // MARK: - Shared Helpers

    @ViewBuilder
    private func sanctuaryButtons(onSave: @escaping () -> Void, onReset: @escaping () -> Void, isDirty: Bool) -> some View {
        HStack(spacing: SanctuaryLayout.Spacing.md) {
            Button(action: onSave) {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Save Changes")
                        .font(SanctuaryTypography.label)
                }
                .foregroundColor(.white)
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(isDirty ? CosmoColors.cosmoAI : CosmoColors.cosmoAI.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isDirty)

            Button(action: onReset) {
                HStack(spacing: SanctuaryLayout.Spacing.xs) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Reset to Default")
                        .font(SanctuaryTypography.label)
                }
                .foregroundColor(SanctuaryColors.Text.secondary)
                .padding(.horizontal, SanctuaryLayout.Spacing.md)
                .padding(.vertical, SanctuaryLayout.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                        .fill(SanctuaryColors.Glass.secondary)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    @ViewBuilder
    private func sectionHeader(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Binding<Bool>,
        statusColor: Color? = nil
    ) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: SanctuaryLayout.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.cosmoAI)
                    .frame(width: 20)

                Text(title)
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                if let color = statusColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SanctuaryColors.Text.muted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SanctuaryColors.Text.muted)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, SanctuaryLayout.Spacing.md)
            .padding(.vertical, SanctuaryLayout.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
            .fill(SanctuaryColors.Glass.primary)
            .overlay(
                RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                    .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
            )
    }
}
