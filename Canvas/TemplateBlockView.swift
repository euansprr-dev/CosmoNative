// CosmoOS/Canvas/TemplateBlockView.swift
// Template instance block for Thinkspace canvas
// Matches ConnectionBlockView: bold title, dot+label+chevron rows, compact sections

import SwiftUI

struct TemplateBlockView: View {
    let block: CanvasBlock

    @State private var instanceAtom: Atom?
    @State private var templateMeta: BlockTemplateMetadata?
    @State private var instanceData: TemplateInstanceStructured?
    @State private var isLoading = true
    @State private var expandedField: String?

    private static let fieldColors: [Color] = [
        Color(hex: "#6366F1") ?? .indigo,
        Color(hex: "#22C55E") ?? .green,
        Color(hex: "#F59E0B") ?? .orange,
        Color(hex: "#EF4444") ?? .red,
        Color(hex: "#8B5CF6") ?? .purple,
        Color(hex: "#06B6D4") ?? .cyan,
        Color(hex: "#EC4899") ?? .pink,
        Color(hex: "#14B8A6") ?? .teal,
    ]

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: templateMeta?.icon ?? "rectangle.3.group.fill",
            title: displayTitle,
            autoHeight: true,
            onFocusMode: openFocusMode
        ) {
            templateContent
        }
        .onAppear { loadInstance() }
    }

    private var displayTitle: String {
        // Show template name, not instance title (which has date suffix)
        if let name = instanceAtom?.title {
            // Strip the " — Apr 7, 2026" suffix if present
            if let dashRange = name.range(of: " — ") {
                return String(name[name.startIndex..<dashRange.lowerBound])
            }
            return name
        }
        return block.title
    }

    // MARK: - Content

    @ViewBuilder
    private var templateContent: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else if let templateMeta, let instanceData {
            VStack(spacing: 0) {
                compactHeader(template: templateMeta, instance: instanceData)
                sectionList(template: templateMeta, instance: instanceData)
                if !templateMeta.buttons.isEmpty {
                    footerButtons(template: templateMeta, instance: instanceData)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            emptyView
        }
    }

    // MARK: - Header (title + stats)

    private func compactHeader(template: BlockTemplateMetadata, instance: TemplateInstanceStructured) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Bold title
            Text(displayTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.text)
                .lineLimit(2)

            // Stats
            Text("\(filledCount(instance))/\(template.fields.count) fields · \(template.buttons.count) buttons")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Section List (dot + label + chevron rows)

    private func sectionList(template: BlockTemplateMetadata, instance: TemplateInstanceStructured) -> some View {
        VStack(spacing: 0) {
            let sorted = template.fields.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, field in
                fieldRow(
                    field: field,
                    value: instance.fieldValues[field.key],
                    color: Self.fieldColors[index % Self.fieldColors.count]
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func fieldRow(field: TemplateFieldDefinition, value: ConditionValue?, color: Color) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2)) {
                    expandedField = expandedField == field.id ? nil : field.id
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(field.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: expandedField == field.id ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if expandedField == field.id {
                expandedContent(field: field, value: value, color: color)
            }
        }
    }

    @ViewBuilder
    private func expandedContent(field: TemplateFieldDefinition, value: ConditionValue?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value {
                Text(value.stringValue ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            } else {
                Text(field.placeholder ?? "Not set")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                    .italic()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Footer Buttons

    private func footerButtons(template: BlockTemplateMetadata, instance: TemplateInstanceStructured) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.border).frame(height: 1)
            HStack(spacing: 6) {
                let sorted = template.buttons.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(sorted) { button in
                    actionButton(button, instance: instance)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func actionButton(_ button: TemplateButtonDefinition, instance: TemplateInstanceStructured) -> some View {
        let done = instance.completedButtons.contains(button.id)
        Button {
            guard !done else { return }
            executeButton(button)
        } label: {
            HStack(spacing: 3) {
                if let icon = button.icon {
                    Image(systemName: done ? "checkmark" : icon)
                        .font(.system(size: 9))
                }
                Text(button.label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(btnBg(button.style, done: done))
            .foregroundStyle(btnFg(button.style, done: done))
            .clipShape(.rect(cornerRadius: 6))
            .opacity(done ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.textMuted)
            Text("Template not found")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        if let hex = templateMeta?.accentColorHex {
            return Color(hex: hex) ?? DS.accent
        }
        return DS.accent
    }

    private func filledCount(_ instance: TemplateInstanceStructured) -> Int {
        instance.fieldValues.filter { $0.value != nil }.count
    }

    private func btnBg(_ style: TemplateButtonStyle, done: Bool) -> Color {
        if done { return DS.surfaceElevated }
        switch style {
        case .primary: return accentColor
        case .secondary: return DS.surfaceElevated
        case .destructive: return Color.red.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        }
    }

    private func btnFg(_ style: TemplateButtonStyle, done: Bool) -> Color {
        if done { return DS.textMuted }
        switch style {
        case .primary: return .white
        case .secondary: return DS.text
        case .destructive: return .red
        case .success: return .green
        }
    }

    // MARK: - Actions

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.template, "id": block.entityId]
        )
    }

    private func executeButton(_ button: TemplateButtonDefinition) {
        guard let uuid = instanceAtom?.uuid else { return }
        Task {
            try? await TemplateEngine.shared.executeButton(buttonId: button.id, instanceUUID: uuid)
            loadInstance()
        }
    }

    private func loadInstance() {
        Task {
            defer { isLoading = false }
            // Warm store only for the initial mount — post-action reloads
            // (template buttons just wrote the instance row) need fresh data.
            var loaded: Atom? = instanceAtom == nil
                ? CanvasAtomWarmStore.shared.atom(uuid: block.entityUuid)
                : nil
            if loaded == nil {
                loaded = try? await AtomRepository.shared.fetch(uuid: block.entityUuid)
            }
            guard let atom = loaded else { return }
            instanceAtom = atom
            instanceData = atom.templateInstanceData
            let templateUUID = instanceData?.templateUUID ?? atom.templateDefinitionUUID
            if let templateUUID {
                templateMeta = await TemplateEngine.shared.cachedTemplateMetadata(for: templateUUID)
            }
        }
    }
}
