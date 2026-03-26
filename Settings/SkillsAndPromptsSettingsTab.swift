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
        VStack(alignment: .leading, spacing: DS.space24) {
            Text("Skills & Prompts")
                .font(DS.title2)
                .foregroundStyle(DS.text)

            Text("Configure AI behavior, writing methodology, and learned skills")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)

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

            Spacer(minLength: DS.space24)
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
                VStack(spacing: DS.space12) {
                    Text("The unified system prompt that defines the AI writing partner's behavior. Includes {METHODOLOGY_TEXT} and {PLATFORM_CONSTRAINTS} placeholders.")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)

                    WritingEngineTextEditor(text: $promptStore.unifiedSystemPrompt)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(DS.surfaceHover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                                        .stroke(promptStore.isUnifiedDirty ? CosmoColors.cosmoAI.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .onChange(of: promptStore.unifiedSystemPrompt) { newValue in
                            promptStore.isUnifiedDirty = newValue != PromptTemplateStore.DEFAULT_UNIFIED_SYSTEM_PROMPT
                        }

                    Text("\(promptStore.unifiedTokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textMuted)

                    sanctuaryButtons(
                        onSave: { promptStore.saveUnifiedSystemPrompt() },
                        onReset: { promptStore.resetUnifiedToDefault() },
                        isDirty: promptStore.isUnifiedDirty
                    )
                }
                .padding(DS.space12)
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
                VStack(spacing: DS.space12) {
                    Text("The foundational content playbook injected as context for all AI generation.")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)

                    WritingEngineTextEditor(text: $promptStore.methodology)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(DS.surfaceHover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                                        .stroke(promptStore.isDirty ? CosmoColors.cosmoAI.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .onChange(of: promptStore.methodology) { newValue in
                            promptStore.isDirty = newValue != PromptTemplateStore.DEFAULT_METHODOLOGY
                        }

                    Text("\(promptStore.tokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textMuted)

                    sanctuaryButtons(
                        onSave: { promptStore.saveMethodology() },
                        onReset: { promptStore.resetToDefault() },
                        isDirty: promptStore.isDirty
                    )
                }
                .padding(DS.space12)
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
                VStack(spacing: DS.space12) {
                    Text("Hard format rules for each platform (character limits, slide counts, durations).")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)

                    WritingEngineTextEditor(text: $promptStore.platformConstraints)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(DS.surfaceHover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                                        .stroke(promptStore.isPlatformConstraintsDirty ? CosmoColors.cosmoAI.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .onChange(of: promptStore.platformConstraints) { newValue in
                            promptStore.isPlatformConstraintsDirty = newValue != PromptTemplateStore.DEFAULT_PLATFORM_CONSTRAINTS
                        }

                    Text("\(promptStore.platformConstraintsTokenCount()) estimated tokens")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textMuted)

                    sanctuaryButtons(
                        onSave: { promptStore.savePlatformConstraints() },
                        onReset: { promptStore.resetPlatformConstraintsToDefault() },
                        isDirty: promptStore.isPlatformConstraintsDirty
                    )
                }
                .padding(DS.space12)
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
                VStack(spacing: DS.space8) {
                    ForEach(promptStore.modules) { module in
                        skillModuleRow(module: module)
                    }

                    // Add Module inline form
                    if isAddModulePresented {
                        addModuleForm
                    }

                    HStack(spacing: DS.space8) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isAddModulePresented.toggle()
                                newModuleTitle = ""
                                newModuleContent = ""
                            }
                        }) {
                            HStack(spacing: DS.space4) {
                                Image(systemName: isAddModulePresented ? "xmark" : "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text(isAddModulePresented ? "Cancel" : "Add Module")
                                    .font(DS.caption)
                            }
                            .foregroundStyle(CosmoColors.cosmoAI)
                            .padding(.horizontal, DS.space12)
                            .padding(.vertical, DS.space8)
                            .background(
                                RoundedRectangle(cornerRadius: DS.radiusSmall)
                                    .fill(CosmoColors.cosmoAI.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: {
                            promptStore.resetAllModulesToDefaults()
                            editingModuleId = nil
                        }) {
                            HStack(spacing: DS.space4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("Reset All to Defaults")
                                    .font(DS.caption)
                            }
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, DS.space12)
                            .padding(.vertical, DS.space8)
                            .background(
                                RoundedRectangle(cornerRadius: DS.radiusSmall)
                                    .fill(DS.surfaceHover)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, DS.space4)
                }
                .padding(DS.space12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    @ViewBuilder
    private func skillModuleRow(module: PromptModule) -> some View {
        let isEditing = editingModuleId == module.id
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
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
                    HStack(spacing: DS.space4) {
                        Text(module.title)
                            .font(DS.caption)
                            .foregroundStyle(module.isEnabled ? DS.text : DS.textMuted)

                        if promptStore.isCustomModule(id: module.id) {
                            Text("Custom")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange.opacity(0.1))
                                )
                        } else {
                            Text("Core")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.teal)
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
                                .foregroundStyle(.green)
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
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        editingModuleId = isEditing ? nil : module.id
                    }
                }) {
                    Image(systemName: isEditing ? "chevron.up" : "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(CosmoColors.cosmoAI)
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
                            .foregroundStyle(DS.textMuted)
                            .padding(5)
                            .background(Circle().fill(DS.surfaceHover))
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
                            .foregroundStyle(DS.red)
                            .padding(5)
                            .background(Circle().fill(DS.red.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditing {
                skillModuleEditor(moduleId: module.id)
            }
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space8)
        .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(
            module.isEnabled ? DS.surfaceHover : Color.clear
        ))
    }

    @ViewBuilder
    private func skillModuleEditor(moduleId: String) -> some View {
        if let idx = promptStore.modules.firstIndex(where: { $0.id == moduleId }) {
            VStack(alignment: .leading, spacing: DS.space8) {
                WritingEngineTextEditor(text: $promptStore.modules[idx].content)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.surfaceHover)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radiusSmall)
                                    .stroke(DS.borderSubtle, lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))

                HStack(spacing: DS.space8) {
                    Button(action: {
                        promptStore.saveModuleState()
                        editingModuleId = nil
                    }) {
                        HStack(spacing: DS.space4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10))
                            Text("Save")
                                .font(DS.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.space8 + 2)
                        .padding(.vertical, DS.space4 + 1)
                        .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(CosmoColors.cosmoAI))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        promptStore.resetModuleToDefault(moduleId: moduleId)
                        editingModuleId = nil
                    }) {
                        Text("Cancel")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, DS.space8 + 2)
                            .padding(.vertical, DS.space4 + 1)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            .padding(.top, DS.space4)
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
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("New Skill Module")
                .font(DS.caption)
                .foregroundStyle(DS.text)

            TextField("Module title", text: $newModuleTitle)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.surfaceHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(DS.borderSubtle, lineWidth: 1)
                        )
                )

            addModuleIdLabel

            WritingEngineTextEditor(text: $newModuleContent)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.surfaceHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(DS.borderSubtle, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))

            HStack(spacing: DS.space8) {
                Button(action: createCustomModule) {
                    HStack(spacing: DS.space4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                        Text("Create Module")
                            .font(DS.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.space8 + 2)
                    .padding(.vertical, DS.space4 + 1)
                    .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(
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
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, DS.space8 + 2)
                        .padding(.vertical, DS.space4 + 1)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(CosmoColors.cosmoAI.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
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
            .foregroundStyle(DS.textMuted)
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
                VStack(spacing: DS.space12) {
                    // Filter chips
                    VStack(alignment: .leading, spacing: DS.space4) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.space4) {
                                ForEach(intentFilters, id: \.self) { filter in
                                    intentFilterChip(filter)
                                }
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.space4) {
                                ForEach(["all", "hard", "advisory"], id: \.self) { filter in
                                    enforcementFilterChip(filter)
                                }
                            }
                        }
                    }

                    if filteredSkills.isEmpty {
                        VStack(spacing: DS.space8) {
                            Image(systemName: "brain")
                                .font(.system(size: 24))
                                .foregroundStyle(DS.textMuted)
                            Text("No skills learned yet. As you work with Cosmo, skills will appear here.")
                                .font(DS.subheadline)
                                .foregroundStyle(DS.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, DS.space24)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(filteredSkills) { skill in
                            learnedSkillRow(skill)
                        }
                    }
                }
                .padding(DS.space12)
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
                .foregroundStyle(isSelected ? .white : DS.textSecondary)
                .padding(.horizontal, DS.space8 + 2)
                .padding(.vertical, DS.space4 + 1)
                .background(
                    Capsule().fill(isSelected ? CosmoColors.cosmoAI : DS.surfaceHover)
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
                .foregroundStyle(isSelected ? .white : DS.textSecondary)
                .padding(.horizontal, DS.space8 + 2)
                .padding(.vertical, DS.space4 + 1)
                .background(
                    Capsule().fill(isSelected ? chipColor : DS.surfaceHover)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func learnedSkillRow(_ skill: InferredLesson) -> some View {
        let isEditing = editingSkillId == skill.id
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(alignment: .top, spacing: DS.space8) {
                Circle()
                    .fill(confidenceColor(skill.confidence))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: DS.space4) {
                    if isEditing {
                        TextField("Rule text", text: $editingSkillRule, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.text)
                            .lineLimit(3...6)
                            .padding(DS.space8)
                            .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceHover))
                    } else {
                        Text(skill.rule)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.text)
                            .lineLimit(2)
                    }

                    HStack(spacing: DS.space4) {
                        enforcementBadge(skill.effectiveEnforcement)
                        categoryBadge(skill.category)
                        intentBadge(skill.intent ?? "universal")
                        confidenceBar(skill.confidence)

                        if let moduleId = skill.targetModuleId ?? PromptTemplateStore.categoryToModuleMap[skill.category],
                           let module = promptStore.modules.first(where: { $0.id == moduleId }) {
                            Text(module.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green)
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
                                .foregroundStyle(DS.textMuted)
                        }
                    }

                    if isEditing {
                        HStack(spacing: DS.space4) {
                            Text("Scope:")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textMuted)
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

                        HStack(spacing: DS.space8) {
                            Button(action: { saveEditedSkill(skill) }) {
                                Text("Save")
                                    .font(DS.caption)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, DS.space8 + 2)
                                    .padding(.vertical, DS.space4)
                                    .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(CosmoColors.cosmoAI))
                            }
                            .buttonStyle(.plain)

                            Button(action: { editingSkillId = nil }) {
                                Text("Cancel")
                                    .font(DS.caption)
                                    .foregroundStyle(DS.textMuted)
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
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)

                    Button(action: { deleteLearnedSkill(skill) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
        .padding(.vertical, DS.space4)
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
                VStack(alignment: .leading, spacing: DS.space12) {
                    Text("Pattern analysis reports generated from your swipe library.")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textMuted)

                    if promptStore.batchAnalysisReports.isEmpty {
                        HStack(spacing: DS.space8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(DS.textMuted)
                            Text("Reports are generated automatically every 30 swipes per content type.")
                                .font(DS.subheadline)
                                .foregroundStyle(DS.textMuted)
                        }
                        .padding(DS.space8)
                        .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceHover))
                    } else {
                        batchReportsList
                    }

                    addReportButton
                }
                .padding(DS.space12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(glassCard)
    }

    @ViewBuilder
    private var batchReportsList: some View {
        ForEach(promptStore.batchAnalysisReports) { report in
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack {
                    Text(report.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)

                    Text("\(report.swipeCount) swipes")
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CosmoColors.cosmoAI.opacity(0.15)))
                        .foregroundStyle(CosmoColors.cosmoAI)

                    Spacer()

                    Text(report.dateLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)

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
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)

                    Button(action: { promptStore.deleteBatchAnalysisReport(report) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                if editingReportId == report.id {
                    WritingEngineTextEditor(text: $editingReportContent)
                        .frame(height: 180)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(DS.surfaceHover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                                        .stroke(CosmoColors.cosmoAI.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
                } else {
                    Text(report.content.prefix(300) + (report.content.count > 300 ? "..." : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(6)
                }
            }
            .padding(DS.space8)
            .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceHover))
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
            HStack(spacing: DS.space4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                Text("Add Report Manually")
                    .font(DS.caption)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surfaceHover)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - UI Components

    @ViewBuilder
    private func categoryBadge(_ category: String) -> some View {
        Text(category.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CosmoColors.cosmoAI)
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
            .foregroundStyle(color)
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
                        .fill(Double(i) / 5.0 < confidence ? confidenceColor(confidence) : DS.borderSubtle)
                        .frame(width: 6, height: 4)
                }
            }
        }
        .frame(width: 34, height: 4)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return DS.green }
        if confidence >= 0.5 { return .orange }
        return DS.red
    }

    @ViewBuilder
    private func enforcementBadge(_ enforcement: LessonEnforcement) -> some View {
        let isHard = enforcement == .hard
        let color: Color = isHard ? .red : DS.textMuted
        Text(isHard ? "Hard" : "Advisory")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
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
        default: return DS.textMuted
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
            let skillIdStr = skill.id.uuidString
            // Match by metadata.lessonID (Mac-created) OR structured.id (cloud-created)
            if var atom = atoms?.first(where: { atom in
                let meta = atom.metadataDict
                // Parse structured JSON for cloud-created lessons
                var structuredId: String?
                if let s = atom.structured, let d = s.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    structuredId = dict["id"] as? String
                }
                return meta?["lessonID"] as? String == skillIdStr
                    || structuredId == skillIdStr
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
        HStack(spacing: DS.space12) {
            Button(action: onSave) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Save Changes")
                        .font(DS.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(isDirty ? CosmoColors.cosmoAI : CosmoColors.cosmoAI.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isDirty)

            Button(action: onReset) {
                HStack(spacing: DS.space4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Reset to Default")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.surfaceHover)
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
            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(CosmoColors.cosmoAI)
                    .frame(width: 20)

                Text(title)
                    .font(DS.title3)
                    .foregroundStyle(DS.text)

                if let color = statusColor {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8 + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium)
            .fill(DS.surfaceHover)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
    }
}
