// CosmoOS/UI/Automation/TemplateBuilderView.swift
// Template creation and editing — fields with expandable config, options editor, button builder

import SwiftUI

struct TemplateBuilderView: View {
    var editingTemplateUUID: String?
    var onDismiss: () -> Void
    var onSaved: ((Atom) -> Void)?

    @State private var templateName = ""
    @State private var templateDescription = ""
    @State private var selectedIcon = "rectangle.3.group.fill"
    @State private var accentColorHex = "#6366F1"
    @State private var fields: [TemplateFieldDefinition] = []
    @State private var buttons: [TemplateButtonDefinition] = []
    @State private var isSaving = false
    @State private var expandedFieldIndex: Int?
    @State private var newOptionText = ""
    @State private var activeSection: BuilderSection = .fields

    @FocusState private var isNameFocused: Bool

    private enum BuilderSection: String, CaseIterable {
        case fields = "Fields"
        case buttons = "Buttons"
        case preview = "Preview"
    }

    var body: some View {
        VStack(spacing: 0) {
            builderHeader
            Divider()
            sectionPicker
            Divider()
            activeSectionContent
            Divider()
            builderFooter
        }
        .frame(width: 520, height: 600)
        .background(DS.vellum)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.sepiaBorder, lineWidth: 0.5))
        .onAppear { loadExistingTemplate() }
    }

    // MARK: - Header

    @ViewBuilder
    private var builderHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                iconMenu
                TextField("Template Name", text: $templateName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .focused($isNameFocused)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            TextField("Description (optional)", text: $templateDescription)
                .textFieldStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var iconMenu: some View {
        let icons = [
            "rectangle.3.group.fill", "doc.text.fill", "chart.bar.fill",
            "checklist", "person.2.fill", "star.fill", "flag.fill",
            "bookmark.fill", "tag.fill", "lightbulb.fill", "brain",
            "target", "bolt.fill", "gearshape.fill", "calendar"
        ]
        Menu {
            ForEach(icons, id: \.self) { icon in
                Button { selectedIcon = icon } label: { Label(icon, systemImage: icon) }
            }
        } label: {
            Image(systemName: selectedIcon)
                .font(.system(size: 18))
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(accentColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(BuilderSection.allCases, id: \.self) { section in
                Button { activeSection = section } label: {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: activeSection == section ? .semibold : .regular))
                        .foregroundStyle(activeSection == section ? DS.accent : DS.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(activeSection == section ? DS.accent.opacity(0.1) : Color.clear)
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var activeSectionContent: some View {
        ScrollView {
            switch activeSection {
            case .fields: fieldsEditor
            case .buttons: buttonsEditor
            case .preview: previewSection
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Fields Editor

    @ViewBuilder
    private var fieldsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, _ in
                fieldEditorRow(index: index)
            }
            addFieldButton
        }
        .padding(16)
    }

    @ViewBuilder
    private func fieldEditorRow(index: Int) -> some View {
        let isExpanded = expandedFieldIndex == index
        VStack(spacing: 0) {
            // Header row: icon + name + type + remove
            fieldRowHeader(index: index, isExpanded: isExpanded)

            // Expandable config panel
            if isExpanded {
                fieldConfigPanel(index: index)
            }
        }
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? accentColor.opacity(0.3) : DS.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func fieldRowHeader(index: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fields[index].fieldType.iconName)
                .font(.system(size: 11))
                .foregroundStyle(accentColor)
                .frame(width: 20)

            TextField("Field name", text: fieldLabelBinding(index))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)

            fieldTypeMenu(index: index)

            Button {
                withAnimation(.spring(response: 0.2)) {
                    expandedFieldIndex = isExpanded ? nil : index
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)

            Button { fields.remove(at: index); expandedFieldIndex = nil } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    // MARK: - Field Config Panel (expandable)

    @ViewBuilder
    private func fieldConfigPanel(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            // Placeholder
            configRow(label: "Placeholder") {
                TextField("Enter placeholder text...", text: placeholderBinding(index))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }

            // Required toggle
            configRow(label: "Required") {
                Toggle("", isOn: requiredBinding(index))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            // Type-specific configuration
            typeSpecificConfig(index: index)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func configRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func typeSpecificConfig(index: Int) -> some View {
        switch fields[index].fieldType {
        case .select, .multiSelect:
            optionsEditor(index: index)
        default:
            EmptyView()
        }
    }

    // MARK: - Options Editor (for select/multiSelect)

    @ViewBuilder
    private func optionsEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Options")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textSecondary)

            // Existing options as removable chips
            if let options = fields[index].options, !options.isEmpty {
                TemplateFlowLayout(spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        optionChip(option, fieldIndex: index)
                    }
                }
            }

            // Add new option
            HStack(spacing: 6) {
                TextField("New option...", text: $newOptionText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: 4))
                    .onSubmit { addOption(fieldIndex: index) }

                Button {
                    addOption(fieldIndex: index)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newOptionText.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func optionChip(_ option: String, fieldIndex: Int) -> some View {
        HStack(spacing: 3) {
            Text(option)
                .font(.system(size: 11))
                .foregroundStyle(DS.text)
            Button {
                fields[fieldIndex].options?.removeAll { $0 == option }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.surfaceHover)
        .clipShape(.rect(cornerRadius: 5))
    }

    private func addOption(fieldIndex: Int) {
        guard !newOptionText.isEmpty else { return }
        if fields[fieldIndex].options == nil {
            fields[fieldIndex].options = []
        }
        fields[fieldIndex].options?.append(newOptionText)
        newOptionText = ""
    }

    // MARK: - Field Type Menu

    @ViewBuilder
    private func fieldTypeMenu(index: Int) -> some View {
        Menu {
            ForEach(TemplateFieldType.allCases, id: \.self) { type in
                Button {
                    fields[index].fieldType = type
                    // Clear options when switching away from select types
                    if type != .select && type != .multiSelect {
                        fields[index].options = nil
                    }
                    // Initialize options array for select types
                    if (type == .select || type == .multiSelect) && fields[index].options == nil {
                        fields[index].options = []
                    }
                } label: {
                    Label(type.displayName, systemImage: type.iconName)
                }
            }
        } label: {
            Text(fields[index].fieldType.displayName)
                .font(.system(size: 10))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.surfaceHover)
                .clipShape(.rect(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Add Field Button

    private var addFieldButton: some View {
        Button {
            let key = "field_\(fields.count + 1)"
            let newField = TemplateFieldDefinition.new(key: key, label: "", fieldType: .text, sortOrder: fields.count)
            fields.append(newField)
            expandedFieldIndex = fields.count - 1
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12))
                Text("Add Field").font(.system(size: 12))
            }
            .foregroundStyle(accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(accentColor.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Buttons Editor

    @ViewBuilder
    private var buttonsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.element.id) { index, button in
                buttonEditorRow(button, index: index)
            }
            addButtonButton
        }
        .padding(16)
    }

    @ViewBuilder
    private func buttonEditorRow(_ button: TemplateButtonDefinition, index: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(buttonStyleColor(button.style)).frame(width: 8, height: 8)
            TextField("Button label", text: buttonLabelBinding(index))
                .textFieldStyle(.plain)
                .font(DS.caption)
                .frame(maxWidth: .infinity)
            buttonStyleMenu(index: index)
            Button { buttons.remove(at: index) } label: {
                Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: 6))
    }

    @ViewBuilder
    private func buttonStyleMenu(index: Int) -> some View {
        Menu {
            ForEach(TemplateButtonStyle.allCases, id: \.self) { style in
                Button(style.rawValue.capitalized) { buttons[index].style = style }
            }
        } label: {
            Text(buttons[index].style.rawValue.capitalized)
                .font(.system(size: 10))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.surfaceHover)
                .clipShape(.rect(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
    }

    private var addButtonButton: some View {
        Button {
            buttons.append(TemplateButtonDefinition.new(label: "", style: .primary, actions: [], sortOrder: buttons.count))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12))
                Text("Add Button").font(.system(size: 12))
            }
            .foregroundStyle(accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(accentColor.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: 12) {
            Text("Live Preview").font(DS.caption).foregroundStyle(DS.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: selectedIcon).font(.system(size: 12)).foregroundStyle(accentColor)
                    Text(templateName.isEmpty ? "Template Name" : templateName)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.text)
                }
                ForEach(fields.sorted(by: { $0.sortOrder < $1.sortOrder })) { field in
                    HStack(spacing: 8) {
                        Circle().fill(accentColor).frame(width: 6, height: 6)
                        Text(field.label.isEmpty ? "Field" : field.label)
                            .font(.system(size: 12)).foregroundStyle(DS.text)
                        Spacer()
                        Text(field.fieldType.displayName)
                            .font(.system(size: 10)).foregroundStyle(DS.textMuted)
                        if let opts = field.options, !opts.isEmpty {
                            Text("(\(opts.count) options)")
                                .font(.system(size: 9)).foregroundStyle(DS.textMuted)
                        }
                    }
                }
                if !buttons.isEmpty {
                    Divider()
                    HStack(spacing: 4) {
                        ForEach(buttons.sorted(by: { $0.sortOrder < $1.sortOrder })) { button in
                            Text(button.label.isEmpty ? "Button" : button.label)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(buttonStyleColor(button.style).opacity(0.15))
                                .foregroundStyle(buttonStyleColor(button.style))
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                }
            }
            .padding(12)
            .background(DS.surfaceCard)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accentColor.opacity(0.3), lineWidth: 1))
            .frame(width: 300)
        }
        .padding(16)
    }

    // MARK: - Footer

    private var builderFooter: some View {
        HStack {
            Text("\(fields.count) fields, \(buttons.count) buttons")
                .font(DS.caption).foregroundStyle(DS.textSecondary)
            Spacer()
            Button("Cancel") { onDismiss() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DS.textSecondary)
            Button { saveTemplate() } label: {
                Text(editingTemplateUUID != nil ? "Update" : "Create")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(DS.accent)
                    .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(templateName.isEmpty || isSaving)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(16)
    }

    // MARK: - Bindings

    private var accentColor: Color { Color(hex: accentColorHex) ?? DS.accent }

    private func buttonStyleColor(_ style: TemplateButtonStyle) -> Color {
        switch style {
        case .primary: return DS.accent
        case .secondary: return DS.textSecondary
        case .destructive: return .red
        case .success: return .green
        }
    }

    private func fieldLabelBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { fields[index].label },
            set: {
                fields[index].label = $0
                fields[index].key = $0.lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "?", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }
        )
    }

    private func buttonLabelBinding(_ index: Int) -> Binding<String> {
        Binding(get: { buttons[index].label }, set: { buttons[index].label = $0 })
    }

    private func placeholderBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { fields[index].placeholder ?? "" },
            set: { fields[index].placeholder = $0.isEmpty ? nil : $0 }
        )
    }

    private func requiredBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { fields[index].isRequired },
            set: { fields[index].isRequired = $0 }
        )
    }

    // MARK: - Data

    private func loadExistingTemplate() {
        guard let uuid = editingTemplateUUID else { isNameFocused = true; return }
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                  let meta = atom.blockTemplateMetadata else { return }
            templateName = atom.title ?? ""
            templateDescription = meta.description ?? ""
            selectedIcon = meta.icon
            accentColorHex = meta.accentColorHex
            fields = meta.fields
            buttons = meta.buttons
        }
    }

    private func saveTemplate() {
        guard !templateName.isEmpty else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let savedAtom: Atom
            if let uuid = editingTemplateUUID {
                var meta = BlockTemplateMetadata.new(icon: selectedIcon, accentColorHex: accentColorHex)
                meta.description = templateDescription.isEmpty ? nil : templateDescription
                meta.fields = fields
                meta.buttons = buttons
                savedAtom = try await TemplateEngine.shared.updateTemplate(uuid, metadata: meta)
            } else {
                savedAtom = try await TemplateEngine.shared.createTemplate(
                    name: templateName, icon: selectedIcon, accentColor: accentColorHex,
                    fields: fields, buttons: buttons,
                    description: templateDescription.isEmpty ? nil : templateDescription
                )
            }
            onSaved?(savedAtom)
            onDismiss()
        }
    }
}
