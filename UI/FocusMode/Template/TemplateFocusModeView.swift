// CosmoOS/UI/FocusMode/Template/TemplateFocusModeView.swift
// Template Focus Mode — structural clone of ConnectionFocusModeView
// InfiniteCanvasView with dotted grid, anchored card, section cards at 420px

import SwiftUI

struct TemplateFocusModeView: View {
    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @State private var viewportState = CanvasViewportState()
    @State private var templateMeta: BlockTemplateMetadata?
    @State private var instanceData: TemplateInstanceStructured?
    @State private var isLoading = true
    @State private var expandedFields: Set<String> = []

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false

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

    private var accentColor: Color {
        if let hex = templateMeta?.accentColorHex {
            return Color(hex: hex) ?? DS.accent
        }
        return DS.accent
    }

    // MARK: - Body (mirrors ConnectionFocusModeView exactly)

    var body: some View {
        ZStack {
            ZStack {
                InfiniteCanvasView(
                    viewportState: $viewportState,
                    showGrid: true,
                    anchoredContent: { anchoredTemplateCard },
                    floatingContent: { EmptyView() }
                )

                VStack {
                    topBar
                    Spacer()
                }
            }
        }
        .background(DS.focusImmersiveBackground.ignoresSafeArea())
        .focusImmersiveEntryTransition()
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            loadData()
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
        }
    }

    // MARK: - Top Bar (clone of ConnectionFocusModeView.topBar)

    private var topBar: some View {
        HStack(spacing: 10) {
            sidebarToggle
            backButton
            typeBadge
            Spacer()
            editTemplateButton
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(ProMotionSprings.sidebar) {
                isSidebarHidden.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSidebarHidden ? DS.textMuted : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(DS.border, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var backButton: some View {
        Button(action: onClose) {
            HStack(spacing: DS.space6) {
                Image(systemName: "chevron.left")
                    .font(DS.buttonText)
                Text("Back")
                    .font(DS.callout)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(DS.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var typeBadge: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: templateMeta?.icon ?? "rectangle.3.group.fill")
                .font(DS.caption2)
            Text("Template")
                .font(DS.smallCaps)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(accentColor.opacity(DS.opacitySubtle), in: Capsule())
    }

    private var editTemplateButton: some View {
        Button {
            // Open template builder for the template definition
            if let templateUUID = instanceData?.templateUUID {
                NotificationCenter.default.post(
                    name: CosmoNotification.Template.editTemplate,
                    object: nil,
                    userInfo: ["templateUUID": templateUUID]
                )
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: "pencil")
                    .font(DS.caption2)
                Text("Edit Template")
                    .font(DS.caption2)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(DS.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Anchored Card (mirrors ConnectionFocusModeView.anchoredConnectionCard)

    @ViewBuilder
    private var anchoredTemplateCard: some View {
        if isLoading {
            ProgressView("Loading...")
                .tint(.white)
        } else if let templateMeta, let instanceData {
            VStack(spacing: 16) {
                templateTitleHeader
                    .frame(width: 420)
                    .padding(.bottom, 8)

                let sorted = templateMeta.fields.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, field in
                    templateFieldSection(
                        field: field,
                        value: instanceData.fieldValues[field.key],
                        color: Self.fieldColors[index % Self.fieldColors.count]
                    )
                    .frame(width: 420)
                }

                if !templateMeta.buttons.isEmpty {
                    templateButtonBar(template: templateMeta, instance: instanceData)
                        .frame(width: 420)
                }
            }
        }
    }

    // MARK: - Title Header (floating, no background — like Connection)

    private var templateTitleHeader: some View {
        VStack(spacing: 8) {
            Text(atom.title ?? "Template")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DS.text)
                .multilineTextAlignment(.center)

            statsLine
        }
    }

    private var statsLine: some View {
        let filled = instanceData?.fieldValues.filter({ $0.value != nil }).count ?? 0
        let total = templateMeta?.fields.count ?? 0
        let buttons = templateMeta?.buttons.count ?? 0
        return Text("\(filled)/\(total) fields filled · \(buttons) buttons")
            .font(.system(size: 13))
            .foregroundStyle(DS.textSecondary)
    }

    // MARK: - Field Section (clone of ConnectionSectionView visual identity)

    private func templateFieldSection(field: TemplateFieldDefinition, value: ConditionValue?, color: Color) -> some View {
        let isExpanded = expandedFields.contains(field.id)

        return VStack(alignment: .leading, spacing: 0) {
            fieldSectionHeader(field: field, value: value, color: color, isExpanded: isExpanded)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    TemplateFieldRenderer(
                        field: field,
                        value: fieldBinding(for: field.key),
                        compact: false
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(fieldSectionBackground(color: color, isExpanded: isExpanded))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dsGradientBorder(cornerRadius: 12)
        .dsTopHighlight(cornerRadius: 12, height: 40)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.clear, lineWidth: 0.5)
        )
    }

    // MARK: - Section Header (clone of ConnectionSectionView.sectionHeader)

    private func fieldSectionHeader(field: TemplateFieldDefinition, value: ConditionValue?, color: Color, isExpanded: Bool) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                if expandedFields.contains(field.id) {
                    expandedFields.remove(field.id)
                } else {
                    expandedFields.insert(field.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: field.fieldType.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Text(field.fieldType.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                }

                Spacer()

                if !isExpanded, let value {
                    Text(value.stringValue ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .trailing)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Background (clone of ConnectionSectionView.sectionBackground)

    private func fieldSectionBackground(color: Color, isExpanded: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)

            if isExpanded {
                LinearGradient(
                    colors: [color.opacity(0.02), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Field Display (read-only mode)

    @ViewBuilder
    private func fieldDisplayView(field: TemplateFieldDefinition, value: ConditionValue, color: Color) -> some View {
        switch field.fieldType {
        case .rating:
            if case .number(let n) = value {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= Int(n) ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(star <= Int(n) ? .orange : DS.textMuted)
                    }
                }
            }
        case .progress:
            if case .number(let n) = value {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: n, total: 100).progressViewStyle(.linear).tint(color)
                    Text("\(Int(n))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textSecondary)
                }
            }
        case .toggle:
            if case .bool(let b) = value {
                HStack(spacing: 6) {
                    Image(systemName: b ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(b ? .green : DS.textMuted)
                    Text(b ? "Yes" : "No").font(.system(size: 13)).foregroundStyle(DS.text)
                }
            }
        default:
            Text(value.stringValue ?? "—")
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
                .textSelection(.enabled)
        }
    }

    // MARK: - Button Bar

    private func templateButtonBar(template: BlockTemplateMetadata, instance: TemplateInstanceStructured) -> some View {
        HStack(spacing: 10) {
            let sorted = template.buttons.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(sorted) { button in
                focusModeButton(button, instance: instance)
            }
            Spacer()
        }
        .padding(16)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dsGradientBorder(cornerRadius: 12)
    }

    @ViewBuilder
    private func focusModeButton(_ button: TemplateButtonDefinition, instance: TemplateInstanceStructured) -> some View {
        let done = instance.completedButtons.contains(button.id)
        Button {
            guard !done else { return }
            executeButton(button)
        } label: {
            HStack(spacing: 5) {
                if let icon = button.icon {
                    Image(systemName: done ? "checkmark" : icon)
                        .font(.system(size: 12))
                }
                Text(button.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(btnBg(button.style, done: done))
            .foregroundStyle(btnFg(button.style, done: done))
            .clipShape(.rect(cornerRadius: 8))
            .opacity(done ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private func btnBg(_ style: TemplateButtonStyle, done: Bool) -> Color {
        if done { return DS.surfaceHover }
        switch style {
        case .primary: return accentColor
        case .secondary: return DS.surfaceHover
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

    // MARK: - Data

    private func fieldBinding(for key: String) -> Binding<ConditionValue?> {
        Binding(
            get: { instanceData?.fieldValues[key] },
            set: { newValue in
                instanceData?.fieldValues[key] = newValue
                if let newValue {
                    Task {
                        try? await TemplateEngine.shared.updateFieldValue(
                            instanceUUID: atom.uuid, fieldKey: key, value: newValue
                        )
                    }
                }
            }
        )
    }

    private func loadData() {
        Task {
            defer { isLoading = false }
            instanceData = atom.templateInstanceData
            let templateUUID = instanceData?.templateUUID ?? atom.templateDefinitionUUID
            if let templateUUID {
                templateMeta = await TemplateEngine.shared.cachedTemplateMetadata(for: templateUUID)
            }
            if let fields = templateMeta?.fields {
                expandedFields = Set(fields.map(\.id))
            }
        }
    }

    private func executeButton(_ button: TemplateButtonDefinition) {
        Task {
            try? await TemplateEngine.shared.executeButton(buttonId: button.id, instanceUUID: atom.uuid)
            if let updated = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
                instanceData = updated.templateInstanceData
            }
        }
    }
}
