import SwiftUI

struct InboxSpatialInspector: View {
    @Bindable var viewModel: InboxViewModel

    var body: some View {
        Group {
            if let item = viewModel.selectedInboxItem() {
                InboxTriageInspector(item: item, viewModel: viewModel)
            } else if let item = viewModel.selectedDatabaseItem() {
                databaseInspector(item)
            }
        }
    }

    private func databaseInspector(_ item: InboxDatabaseCandidate) -> some View {
        CanvasSelectionInspector(
            block: CanvasBlock.fromAtom(item.atom, position: .zero),
            currentThinkspaceId: nil,
            onClose: { viewModel.closeSpatialInspector() },
            onFocusMode: {
                if let entityType = EntityType(rawValue: item.atomType.rawValue), item.entityId > 0 {
                    NotificationCenter.default.post(
                        name: .enterFocusMode,
                        object: nil,
                        userInfo: ["type": entityType, "id": item.entityId]
                    )
                }
            },
            onOpenAsPane: {
                if let entityType = EntityType(rawValue: item.atomType.rawValue), item.entityId > 0 {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openAsPane,
                        object: nil,
                        userInfo: ["type": entityType, "id": item.entityId]
                    )
                }
            },
            onAskCosmo: nil,
            onConnectTo: nil,
            onAIAssist: nil,
            onSave: nil,
            onDuplicate: nil,
            onDelete: nil
        )
    }
}

private struct InboxTriageInspector: View {
    let item: InboxItem
    @Bindable var viewModel: InboxViewModel
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                essenceSection
                recommendationSection
                InboxDestinationPreview(item: item)
                nearbySection
                actionGrid
            }
            .padding(18)
        }
        .frame(width: 340)
        .frame(maxHeight: 650)
        .cortexInspectorPanel(cornerRadius: 24)
        .offset(x: appeared ? 0 : 24)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.gentle) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.12), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title ?? String(item.rawText.prefix(48)))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)

                Text("\(sourceLabel) · \(relativeTime)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.closeSpatialInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(DS.glassInputFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var essenceSection: some View {
        inspectorSection(title: "Essence", icon: "quote.opening") {
            Text(item.rawText)
                .font(.system(size: 13))
                .foregroundStyle(DS.text.opacity(0.76))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recommendationSection: some View {
        inspectorSection(title: "Recommended Action", icon: "sparkles") {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Spacer()
                    Text(item.confidenceLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }

                Text(item.spatialDestinationTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)

                if let rationale = item.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let summary = item.placementPlanSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var nearbySection: some View {
        inspectorSection(title: "Nearby Objects", icon: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: DS.space6) {
                let alternatives = item.alternativeRecommendationValues.prefix(3)
                if alternatives.isEmpty {
                    Text("No nearby objects were surfaced for this recommendation yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textMuted)
                } else {
                    ForEach(Array(alternatives), id: \.id) { recommendation in
                        Label(recommendation.destinationPath, systemImage: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
    }

    private var actionGrid: some View {
        VStack(spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                primaryButton(label: primaryActionLabel, icon: "checkmark") {
                    Task { await viewModel.acceptSuggestion(for: item) }
                }
                secondaryButton(label: "Change", icon: "slider.horizontal.3") {
                    viewModel.showOverride(for: item)
                }
            }
            HStack(spacing: DS.space8) {
                secondaryButton(label: "Place & Go", icon: "arrowshape.turn.up.right") {
                    Task { await viewModel.placeAndGo(item) }
                }
                destructiveButton(label: "Archive", icon: "archivebox") {
                    Task { await viewModel.dismiss(item: item) }
                }
            }
        }
    }

    private func inspectorSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Label(title.uppercased(), systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.textMuted)
            content()
        }
        .cortexSectionPane(cornerRadius: 16, padding: 14)
    }

    private func primaryButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(accent, in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(DS.glassInputFill, in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func destructiveButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(DS.red.opacity(0.08), in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var actionTitle: String {
        switch item.classification {
        case .merge: return "Merge with existing object"
        case .place: return "Place in thinkspace"
        case .new: return "Create new object"
        case .none: return "Review manually"
        }
    }

    private var primaryActionLabel: String {
        switch item.classification {
        case .merge: return "Merge"
        case .place: return "Place"
        case .new: return "Create"
        case .none: return "Confirm"
        }
    }

    private var icon: String {
        switch item.classification {
        case .merge: return "arrow.triangle.merge"
        case .place: return "rectangle.3.group"
        case .new: return "plus.circle"
        case .none: return "sparkle.magnifyingglass"
        }
    }

    private var accent: Color {
        switch item.classification {
        case .merge: return DS.orange
        case .place: return DS.accent
        case .new: return DS.entityIdea
        case .none: return DS.textMuted
        }
    }

    private var sourceLabel: String {
        switch item.source {
        case .telegramVoice: return "Telegram voice"
        case .telegramText: return "Telegram"
        case .quickCapture: return "Capture"
        }
    }

    private var relativeTime: String {
        guard let date = ISO8601.date(from: item.createdAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

private struct InboxDestinationPreview: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Label("DESTINATION PREVIEW", systemImage: "map")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.textMuted)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.bg.opacity(0.75))
                previewDrawing
            }
            .frame(height: 150)

            Text(suggestedLanding)
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
        }
        .cortexSectionPane(cornerRadius: 16, padding: 14)
    }

    private var previewDrawing: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                clusterBubble(label: targetThinkspaceName, x: size.width * 0.26, y: size.height * 0.28, width: 96, height: 36)
                clusterBubble(label: targetClusterName, x: size.width * 0.55, y: size.height * 0.56, width: 124, height: 58)
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .position(x: size.width * 0.58, y: size.height * 0.56)
                    .shadow(color: accent.opacity(0.5), radius: 8)
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .position(x: size.width * 0.65, y: size.height * 0.46)
            }
        }
    }

    private func clusterBubble(label: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .overlay(
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            )
            .position(x: x, y: y)
    }

    private var targetThinkspaceName: String {
        item.primaryRecommendationValue?.thinkspaceName
            ?? item.primaryRecommendationValue?.placementPlan?.targetThinkspaceName
            ?? item.placeThinkspaceName
            ?? "Inbox"
    }

    private var targetClusterName: String {
        item.primaryRecommendationValue?.clusterName
            ?? item.primaryRecommendationValue?.placementPlan?.targetClusterName
            ?? item.destinationPath
            ?? "Landing area"
    }

    private var suggestedLanding: String {
        if let summary = item.placementPlanSummary, !summary.isEmpty {
            return summary
        }
        return "Suggested landing near the strongest matching region in \(targetThinkspaceName)."
    }

    private var accent: Color {
        item.classification == .merge ? DS.orange : DS.accent
    }
}
