// CosmoOS/UI/Automation/TemplateGalleryView.swift
// Compact popover for picking a template to spawn — matches CanvasDatabasePicker style

import SwiftUI

struct TemplateGalleryView: View {
    let position: CGPoint
    let onSelect: (Atom) -> Void
    let onDismiss: () -> Void

    @State private var templates: [Atom] = []
    @State private var isLoading = true
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @State private var appearedRows: Set<String> = []
    @FocusState private var isFocused: Bool

    private let menuWidth: CGFloat = 300
    private let menuHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            content
            CosmoKeyboardFooter()
        }
        .frame(width: menuWidth, height: menuHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 18)
        .position(x: clampedPosition.x, y: clampedPosition.y)
        .onAppear {
            isFocused = true
            loadTemplates()
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            CosmicHaptics.shared.play(.threshold)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(max(0, templates.count - 1), selectedIndex + 1)
            CosmicHaptics.shared.play(.threshold)
            return .handled
        }
        .onKeyPress(.return) {
            CosmicHaptics.shared.play(.selection)
            selectCurrent()
            return .handled
        }
        .onKeyPress(.escape) {
            CosmicHaptics.shared.play(.selection)
            onDismiss()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.giltSoft)
                    .frame(width: 30, height: 30)
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.gilt)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Templates")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text("\(templates.count) available")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        CosmoGradientDivider()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if templates.isEmpty {
            emptyState
        } else {
            templateList
        }
    }

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(templates.enumerated()), id: \.element.uuid) { index, template in
                    templateRow(template, index: index)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func templateRow(_ template: Atom, index: Int) -> some View {
        let meta = template.blockTemplateMetadata
        let isSelected = index == selectedIndex
        let isHovered = hoveredIndex == index

        Button {
            instantiate(template)
        } label: {
            rowContent(template, meta: meta, highlighted: isSelected || isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredIndex = index }
            else if hoveredIndex == index { hoveredIndex = nil }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.03) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    _ = appearedRows.insert(template.uuid)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ template: Atom, meta: BlockTemplateMetadata?, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: meta?.icon ?? "rectangle.3.group.fill")
                .font(.system(size: 14))
                .foregroundStyle(cardAccent(meta))
                .frame(width: 28, height: 28)
                .background(cardAccent(meta).opacity(0.1))
                .clipShape(.rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(template.title ?? "Template")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label("\(meta?.fields.count ?? 0) fields", systemImage: "list.bullet")
                    if let buttonCount = meta?.buttons.count, buttonCount > 0 {
                        Label("\(buttonCount) buttons", systemImage: "hand.tap")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)

            if highlighted {
                Text("↵")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? DS.accent.opacity(0.08) : Color.clear)
        )
        .opacity(appearedRows.contains(template.uuid) ? 1 : 0)
        .offset(x: appearedRows.contains(template.uuid) ? 0 : -12)
        .blur(radius: appearedRows.contains(template.uuid) ? 0 : 2)
        .scaleEffect(x: appearedRows.contains(template.uuid) ? 1 : 0.98, y: 1, anchor: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 24))
                .foregroundStyle(DS.textMuted)
            Text("No templates yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)
            Text("Create one in the Template Builder")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func cardAccent(_ meta: BlockTemplateMetadata?) -> Color {
        if let hex = meta?.accentColorHex {
            return Color(hex: hex) ?? DS.accent
        }
        return DS.accent
    }

    private var clampedPosition: CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: position.x + menuWidth / 2, y: position.y - menuHeight / 2)
        }
        let bounds = screen.visibleFrame
        let x = min(max(position.x + menuWidth / 2, menuWidth / 2 + 20), bounds.width - menuWidth / 2 - 20)
        let y = min(max(position.y - menuHeight / 2, menuHeight / 2 + 20), bounds.height - menuHeight / 2 - 20)
        return CGPoint(x: x, y: y)
    }

    private func loadTemplates() {
        Task {
            defer { isLoading = false }
            templates = (try? await TemplateEngine.shared.allTemplates()) ?? []
        }
    }

    private func selectCurrent() {
        guard selectedIndex < templates.count else { return }
        instantiate(templates[selectedIndex])
    }

    private func instantiate(_ template: Atom) {
        Task {
            guard let instance = try? await TemplateEngine.shared.instantiate(
                templateUUID: template.uuid
            ) else { return }
            onSelect(instance)
        }
    }
}
