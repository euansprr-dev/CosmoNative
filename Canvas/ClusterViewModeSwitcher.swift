// CosmoOS/Canvas/ClusterViewModeSwitcher.swift
// Floating inspector panel for cluster settings — color, view mode, delete
// Appears to the right of a selected user cluster

import SwiftUI

/// Floating inspector panel positioned to the right of a selected cluster.
/// Modeled after Muse/Figma "Section" inspector: name header, color swatches, view mode pills.
struct ClusterInspectorPanel: View {

    let cluster: CanvasCluster
    let onChangeColor: (Int) -> Void
    let onChangeViewMode: (ClusterViewMode) -> Void
    let onChangeBoardGrouping: (ClusterBoardGrouping) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showRecipePopover = false
    @State private var clusterRules: [AutomationRule] = []
    @State private var appeared = false
    private let panelWidth: CGFloat = 360

    var body: some View {
        panelBody
            .offset(x: appeared ? 0 : 24)
            .opacity(appeared ? 1 : 0)
            .compositingGroup()
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.gentle) {
                    appeared = true
                }
            }
    }

    @ViewBuilder
    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            hairlineDivider
            intentSection
            hairlineDivider
            colorSection
            hairlineDivider
            viewModeSection
            hairlineDivider
            automationSection
            hairlineDivider
            deleteSection
        }
        .frame(width: panelWidth)
        .cortexInspectorPanel(cornerRadius: 24)
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(cluster.color)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(cluster.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text("CLUSTER")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DS.giltMuted)
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.text.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(DS.glassInputFill, in: Circle())
                    .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Intent Section

    private var intentSection: some View {
        ClusterIntentField(
            clusterId: cluster.id,
            clusterColor: cluster.color,
            intent: Binding(
                get: { cluster.intent ?? "" },
                set: { _ in } // Read-only binding — changes go through onIntentChanged
            ),
            onIntentChanged: { newIntent in
                // Persist intent via cluster engine (requires wiring from CanvasView)
                NotificationCenter.default.post(
                    name: CosmoNotification.Automation.ruleUpdated,
                    object: nil,
                    userInfo: [
                        "clusterId": cluster.id.uuidString,
                        "intent": newIntent
                    ]
                )
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Section Color")
                .dsSmallCapsLabel()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<8, id: \.self) { index in
                    colorSwatch(index: index)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func colorSwatch(index: Int) -> some View {
        let isActive = cluster.colorIndex == index

        Button {
            onChangeColor(index)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(isActive ? 0.75 : 0), lineWidth: 1)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(CanvasCluster.palette[index])
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: - View Mode Section

    private var viewModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("View Mode")
                .dsSmallCapsLabel()

            HStack(spacing: 6) {
                ForEach(ClusterViewMode.allCases, id: \.self) { mode in
                    modePill(mode)
                }
                Spacer(minLength: 0)
            }

            if cluster.viewMode == .board {
                boardGroupingSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func modePill(_ mode: ClusterViewMode) -> some View {
        let isActive = cluster.viewMode == mode

        Button {
            if reduceMotion {
                onChangeViewMode(mode)
            } else {
                withAnimation(ProMotionSprings.snappy) {
                    onChangeViewMode(mode)
                }
            }
        } label: {
            Text(mode.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.text : DS.text.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? DS.glassInputFillFocused : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isActive ? DS.glassBorderFocused : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var boardGroupingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Board Grouping")
                .dsSmallCapsLabel()

            HStack(spacing: 6) {
                ForEach(ClusterBoardGrouping.allCases, id: \.self) { grouping in
                    groupingPill(grouping)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func groupingPill(_ grouping: ClusterBoardGrouping) -> some View {
        let isActive = cluster.boardGrouping == grouping

        Button {
            if reduceMotion {
                onChangeBoardGrouping(grouping)
            } else {
                withAnimation(ProMotionSprings.snappy) {
                    onChangeBoardGrouping(grouping)
                }
            }
        } label: {
            Text(grouping.displayName)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? DS.text : DS.text.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? DS.glassInputFillFocused : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isActive ? DS.glassBorderFocused : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Automation Section

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            automationSectionHeader
            automationSectionContent
            createFlowButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear { loadClusterRules() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleCreated)) { _ in
            loadClusterRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleDeleted)) { _ in
            loadClusterRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Automation.ruleUpdated)) { _ in
            loadClusterRules()
        }
    }

    /// Entry point for Living Workflows — draws a flow line from this cluster.
    private var createFlowButton: some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Automation.createFlow,
                object: nil,
                userInfo: ["clusterId": cluster.id.uuidString]
            )
            onDismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.trianglehead.turn.up.right.diamond")
                    .font(DS.caption)
                Text("Create Flow…")
                    .font(DS.caption.weight(.semibold))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(DS.accentSoft))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Draw a flow from this cluster — distill or draft its contents")
        .accessibilityLabel("Create flow from cluster")
    }

    private var automationSectionHeader: some View {
        HStack(spacing: 6) {
            Text("Automations")
                .dsSmallCapsLabel()

            // Active count pill — matches the existing UI density
            if !clusterRules.isEmpty {
                Text("\(clusterRules.filter(\.isEnabled).count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(cluster.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(cluster.color.opacity(0.12))
                    )
            }

            Spacer(minLength: 0)

            Button("Add Rule", systemImage: "plus") {
                showRecipePopover = true
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DS.accent)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.accentSoft)
            )
            .accessibilityLabel("Add automation rule to \(cluster.name)")
            .popover(isPresented: $showRecipePopover) {
                AutomationRecipePopover(
                    clusterId: cluster.id.uuidString,
                    clusterName: cluster.name,
                    clusterColor: cluster.color,
                    onDismiss: {
                        showRecipePopover = false
                        loadClusterRules()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var automationSectionContent: some View {
        if clusterRules.isEmpty {
            automationEmptyState
        } else {
            VStack(spacing: 4) {
                ForEach(clusterRules, id: \.uuid) { rule in
                    InspectorRuleRow(
                        rule: rule,
                        accentColor: cluster.color,
                        onToggle: {
                            Task {
                                try? await AutomationDispatcher.shared.toggleRule(uuid: rule.uuid)
                                loadClusterRules()
                            }
                        },
                        onDelete: {
                            Task {
                                try? await AutomationDispatcher.shared.deleteRule(uuid: rule.uuid)
                                loadClusterRules()
                            }
                        }
                    )
                }
            }
        }
    }

    private var automationEmptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(DS.textMuted.opacity(0.4))

            Text("No rules yet")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.textMuted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func loadClusterRules() {
        clusterRules = AutomationDispatcher.shared.rules(for: cluster.id.uuidString)
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button {
            onDelete()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                Text("Delete Cluster")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(DS.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inspector Rule Row (extracted subview for performance)

/// Compact rule row for the cluster inspector panel.
/// Uses Button for all interactive elements (VoiceOver-friendly).
/// Matches the visual density of color swatches and view mode pills.
private struct InspectorRuleRow: View {

    let rule: AutomationRule
    let accentColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            // Left accent — 3px bar matching block pattern
            RoundedRectangle(cornerRadius: 1)
                .fill(rule.isEnabled ? accentColor : DS.textMuted.opacity(0.2))
                .frame(width: 3, height: 20)

            // Rule info
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? DS.text : DS.textMuted)
                    .lineLimit(1)

                Text(rule.naturalLanguageDescription)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Fire count — subtle, right-aligned
            if rule.fireCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6))
                    Text("\(rule.fireCount)")
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(DS.textMuted.opacity(0.6))
            }

            // Toggle — matches the scale of color swatches (22px)
            Button {
                if reduceMotion {
                    onToggle()
                } else {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        onToggle()
                    }
                }
            } label: {
                ZStack {
                    Capsule()
                        .fill(rule.isEnabled ? DS.accent : DS.surfaceHover)
                        .frame(width: 26, height: 15)

                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        .offset(x: rule.isEnabled ? 5 : -5)

                    Capsule()
                        .stroke(rule.isEnabled ? DS.accent : DS.border, lineWidth: 0.5)
                        .frame(width: 26, height: 15)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rule.isEnabled ? "Disable \(rule.name)" : "Enable \(rule.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? DS.surfaceHover : DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? DS.border : DS.borderSubtle, lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(
                    rule.isEnabled ? "Disable" : "Enable",
                    systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                )
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Rule", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), \(rule.isEnabled ? "enabled" : "disabled")")
        .accessibilityHint("Right-click for options")
    }
}

// MARK: - View Mode Display Names & Icons

extension ClusterViewMode {
    var iconName: String {
        switch self {
        case .canvas: return "square.grid.2x2"
        case .list:   return "list.bullet"
        case .board:  return "rectangle.split.3x1"
        case .grid:   return "square.grid.3x3"
        }
    }

    var displayName: String {
        switch self {
        case .canvas: return "Canvas"
        case .list:   return "List"
        case .board:  return "Board"
        case .grid:   return "Grid"
        }
    }
}

extension ClusterBoardGrouping {
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .type: return "Type"
        case .pipeline: return "Pipeline"
        }
    }
}
