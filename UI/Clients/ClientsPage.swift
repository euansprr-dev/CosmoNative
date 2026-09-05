// CosmoOS/UI/Clients/ClientsPage.swift
// Clients — the index of hubs. One grouped ledger (the Files grammar): a
// colour dot, the name, niche and platforms, and the numbers that decide
// the week — in pipeline, next ship, cadence quota. Click a row for the hub.

import SwiftUI

struct ClientsPage: View {
    let model: ClientsPageModel
    let onOpen: (String) -> Void

    @State private var hasAppeared = false
    @State private var cursorID: String?
    @FocusState private var pageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipePageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space20) {
                    SwipeMasthead(title: "Clients", detail: mastheadDetail)
                    ledger
                }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 72)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 6)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .focusable()
            .focusEffectDisabled()
            .focused($pageFocused)
            .onMoveCommand(perform: moveCursor)
            .onKeyPress(.return) { openCursor() ? .handled : .ignored }
        }
        .task {
            await model.start()
            if !hasAppeared {
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { hasAppeared = true }
            }
            pageFocused = true
        }
        .onDisappear { model.stop() }
        .background(keyboardLayer)
    }

    private var mastheadDetail: String {
        let inMotion = model.rows.reduce(0) { $0 + $1.inPipeline }
        return "\(model.rows.count) clients · \(inMotion) pieces in motion"
    }

    @ViewBuilder
    private var ledger: some View {
        if model.rows.isEmpty {
            IdeasEmptyState(
                icon: "person.crop.circle",
                headline: "No clients yet",
                teachingLine: "Add a client profile (⌘N) and their ideas, pipeline and calendar gather here."
            )
        } else {
            VStack(alignment: .leading, spacing: DS.space8) {
                CosmoSectionHeader(label: "CLIENTS", detail: "\(model.rows.count)") { EmptyView() }
                container
            }
        }
    }

    private var container: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                ClientIndexRowView(
                    row: row,
                    isCursor: cursorID == row.id,
                    isLast: index == model.rows.count - 1,
                    onOpen: { onOpen(row.uuid) },
                    onOpenPipeline: { openPipeline(row.uuid) },
                    onEditDossier: { openDossier(row.uuid) }
                )
                .onTapGesture { cursorID = row.id }
            }
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
        .clipShape(.rect(cornerRadius: 12))
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { newClient() }.keyboardShortcut("n", modifiers: .command)
            Button("") { Task { await model.load() } }.keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moveCursor(_ direction: MoveCommandDirection) {
        let ids = model.rows.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = cursorID, let index = ids.firstIndex(of: current) else {
            cursorID = ids[0]
            return
        }
        switch direction {
        case .down: cursorID = ids[min(index + 1, ids.count - 1)]
        case .up: cursorID = ids[max(index - 1, 0)]
        default: break
        }
    }

    private func openCursor() -> Bool {
        guard let cursorID else { return false }
        onOpen(cursorID)
        return true
    }

    private func openPipeline(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openPipeline,
            object: nil,
            userInfo: ["clientUUID": uuid]
        )
    }

    private func openDossier(_ uuid: String) {
        NotificationCenter.default.post(name: .showSettings, object: nil, userInfo: ["clientUUID": uuid])
    }

    private func newClient() {
        NotificationCenter.default.post(name: .showSettings, object: nil, userInfo: ["newClient": true])
    }
}

// MARK: - Row

private struct ClientIndexRowView: View {
    let row: ClientIndexRow
    let isCursor: Bool
    let isLast: Bool
    let onOpen: () -> Void
    let onOpenPipeline: () -> Void
    let onEditDossier: () -> Void

    @State private var isHovered = false

    private var tint: Color { DS.clientColor(for: row.uuid) }

    var body: some View {
        HStack(spacing: DS.space12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.space8)
            platformMarks
            ZStack(alignment: .trailing) {
                numbers.opacity(isHovered ? 0 : 1)
                hoverVerbs.opacity(isHovered ? 1 : 0)
            }
            .animation(ProMotionSprings.hover, value: isHovered)
        }
        .padding(.horizontal, DS.space12)
        .frame(height: 52)
        .contentShape(.rect)
        .background(rowWash)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.palette.sepiaBorder.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.leading, 34)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .contextMenu {
            Button { onOpen() } label: { Label("Open hub", systemImage: "person.crop.circle") }
            Button { onOpenPipeline() } label: { Label("Open in Pipeline", systemImage: "rectangle.split.3x1") }
            Button { onEditDossier() } label: { Label("Edit dossier…", systemImage: "doc.text") }
            SwipeLabLaunchButton(scope: .client(row.uuid, name: row.name), clientID: row.uuid, title: "Study published posts")
        }
        .help("\(row.name) — double-click opens the hub")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.inPipeline) in pipeline")
        .accessibilityAddTraits(isCursor ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onOpen() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let handle = row.handle, !handle.isEmpty { parts.append(handle.hasPrefix("@") ? handle : "@\(handle)") }
        if let niche = row.niche, !niche.isEmpty { parts.append(niche) }
        if let frequency = row.postingFrequency, !frequency.isEmpty { parts.append(frequency) }
        return parts.isEmpty ? "No dossier yet" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var rowWash: some View {
        if isCursor {
            DS.glassSectionFill
        } else if isHovered {
            DS.glassSectionFill.opacity(0.5)
        } else {
            Color.clear
        }
    }

    private var platformMarks: some View {
        HStack(spacing: DS.space4) {
            ForEach(row.platforms.prefix(4), id: \.self) { platform in
                PlatformBrandMark(platform: platform.rawValue, size: 11)
            }
        }
    }

    private var numbers: some View {
        HStack(spacing: DS.space12) {
            stat("\(row.inPipeline)", "in motion")
            if let next = row.nextShip {
                stat(PipelinePageModel.dayLabel(next), "next")
            }
            if let quota = row.quota {
                stat("\(quota.met)/\(quota.target)", "this week", tint: quota.met >= quota.target ? DS.accent : nil)
            }
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color? = nil) -> some View {
        HStack(spacing: DS.space4) {
            Text(value)
                .font(DS.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? DS.textSecondary)
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var hoverVerbs: some View {
        HStack(spacing: DS.space6) {
            verb("rectangle.split.3x1", "Open in Pipeline") { onOpenPipeline() }
            verb("doc.text", "Edit dossier") { onEditDossier() }
            verb("arrow.up.right.square", "Open hub") { onOpen() }
        }
    }

    private func verb(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 22)
                .background(DS.glassSectionFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
