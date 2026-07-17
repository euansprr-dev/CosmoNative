// CosmoOS/Navigation/Workbenches.swift
// Workbenches — named, restorable working contexts: main destination + the
// whole pane deck + focus/pin. One keystroke rebuilds the room exactly as
// you left it. (Arc Spaces, applied to knowledge work.)

import SwiftUI
import GRDB

// MARK: - Workspace Snapshot

/// A serializable capture of the current workspace arrangement.
/// Thinkspace cameras are not captured — each thinkspace already remembers
/// and restores its own camera, so benches stay in sync with reality.
struct WorkspaceSnapshot: Codable, Equatable {

    enum Destination: Codable, Equatable {
        case commandCenter
        case inbox
        // Retired surface — kept so persisted snapshots that reference it keep
        // decoding; restore maps it to Command Center (decode law).
        case codex
        case discover
        case swipeFile
        case ideas
        case thinkspace(id: String)
    }

    struct PaneDescriptor: Codable, Equatable {
        enum Kind: String, Codable {
            case entity, thinkspace, commandCenter, swipeGallery, webBrowser, cosmoWindow, inlineAssistant
        }

        var kind: Kind
        var entityTypeRaw: String?
        var entityId: Int64?
        var thinkspaceId: String?
        var urlString: String?
        var title: String?

        @MainActor
        init?(from content: PaneContent) {
            switch content {
            case .entity(let selection):
                kind = .entity
                entityTypeRaw = selection.type.rawValue
                entityId = selection.id
            case .thinkspace(let id):
                kind = .thinkspace
                thinkspaceId = id
            case .commandCenter:
                kind = .commandCenter
            case .swipeGallery:
                kind = .swipeGallery
            case .webBrowser(_, let url, let webTitle):
                kind = .webBrowser
                // Capture what the pane is showing NOW, not its launch URL —
                // a bench should restore the page you were actually reading.
                let liveURL = BrowserPaneRegistry.shared.currentURL(for: content.id)
                let liveTitle = BrowserPaneRegistry.shared.displayTitle(for: content.id)
                urlString = (liveURL ?? url).absoluteString
                title = liveTitle ?? webTitle
            case .cosmoWindow:
                kind = .cosmoWindow
            case .inlineAssistant:
                kind = .inlineAssistant
            case .collaborator:
                // Collaborator panes are transient — not bench material.
                return nil
            }
        }

        var paneContent: PaneContent? {
            switch kind {
            case .entity:
                guard let raw = entityTypeRaw,
                      let type = EntityType(rawValue: raw),
                      let id = entityId else { return nil }
                return .entity(EntitySelection(id: id, type: type))
            case .thinkspace:
                guard let thinkspaceId else { return nil }
                return .thinkspace(thinkspaceId: thinkspaceId)
            case .commandCenter:
                return .commandCenter
            case .swipeGallery:
                return .swipeGallery
            case .webBrowser:
                guard let urlString, let url = URL(string: urlString) else { return nil }
                return .webBrowser(url: url, title: title)
            case .cosmoWindow:
                return .cosmoWindow
            case .inlineAssistant:
                return .inlineAssistant
            }
        }
    }

    var destination: Destination
    var panes: [PaneDescriptor]
    var focusedPaneIndex: Int?
    var pinnedPaneIndex: Int?

    // MARK: Capture / Restore

    @MainActor
    static func capture(destination: SidebarDestination, paneManager: PaneManager) -> WorkspaceSnapshot {
        let descriptors = paneManager.panes.compactMap(PaneDescriptor.init(from:))

        // Indices must refer to the descriptor list (collaborator panes drop out).
        let descriptorIds = paneManager.panes.filter { PaneDescriptor(from: $0) != nil }.map(\.id)
        let focusedIndex = paneManager.focusedPaneId.flatMap { descriptorIds.firstIndex(of: $0) }
        let pinnedIndex = paneManager.pinnedPaneId.flatMap { descriptorIds.firstIndex(of: $0) }

        return WorkspaceSnapshot(
            destination: Destination(from: destination),
            panes: descriptors,
            focusedPaneIndex: focusedIndex,
            pinnedPaneIndex: pinnedIndex
        )
    }

    var sidebarDestination: SidebarDestination {
        switch destination {
        case .commandCenter: return .commandCenter
        case .inbox: return .inbox
        case .codex: return .commandCenter
        case .discover: return .discover(section: .discover)
        case .swipeFile: return .swipeFile(section: .home)
        case .ideas: return .ideas
        case .thinkspace(let id): return .thinkspace(id: id)
        }
    }

    /// Resolve descriptors to live pane contents, skipping entities that no
    /// longer exist. Returns the contents plus the resolved focus/pin ids.
    @MainActor
    func resolvedPanes() async -> (contents: [PaneContent], focusedId: String?, pinnedId: String?) {
        var contents: [PaneContent] = []
        var focusedId: String?
        var pinnedId: String?

        for (index, descriptor) in panes.enumerated() {
            if descriptor.kind == .entity, let id = descriptor.entityId {
                guard (try? await AtomRepository.shared.fetch(id: id)) != nil else { continue }
            }
            guard let content = descriptor.paneContent else { continue }
            contents.append(content)
            if index == focusedPaneIndex { focusedId = content.id }
            if index == pinnedPaneIndex { pinnedId = content.id }
        }
        return (contents, focusedId, pinnedId)
    }
}

extension WorkspaceSnapshot.Destination {
    init(from sidebar: SidebarDestination) {
        switch sidebar {
        case .commandCenter: self = .commandCenter
        case .inbox: self = .inbox
        case .discover: self = .discover
        case .swipeFile: self = .swipeFile
        case .ideas: self = .ideas
        case .thinkspace(let id): self = .thinkspace(id: id)
        }
    }

    var glyph: String {
        switch self {
        case .commandCenter: return "square.grid.2x2"
        case .inbox: return "tray"
        case .codex: return "square.grid.2x2"
        case .discover: return "safari"
        case .swipeFile: return "bookmark"
        case .ideas: return "lightbulb"
        case .thinkspace: return "rectangle.3.group"
        }
    }
}

// MARK: - Record

struct WorkbenchRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workbenches"

    var uuid: String
    var name: String
    var glyph: String
    var tintHex: String
    var snapshot: String
    var sortOrder: Int
    var lastUsedAt: String?
    var useCount: Int
    var createdAt: String
}

// MARK: - Model

struct Workbench: Identifiable, Equatable {
    let uuid: String
    var name: String
    var glyph: String
    var tintHex: String
    var snapshot: WorkspaceSnapshot
    var sortOrder: Int
    var useCount: Int

    var id: String { uuid }
    var tint: Color { Color(hex: tintHex) }
}

// MARK: - Store

@MainActor
@Observable
final class WorkbenchStore {

    static let shared = WorkbenchStore()

    private(set) var workbenches: [Workbench] = []
    private(set) var isLoaded = false

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    func load() async {
        do {
            let records = try await CosmoDatabase.shared.asyncRead { db in
                try WorkbenchRecord
                    .order(Column("sortOrder").asc, Column("createdAt").asc)
                    .fetchAll(db)
            }
            let decoder = JSONDecoder()
            workbenches = records.compactMap { record in
                guard let data = record.snapshot.data(using: .utf8),
                      let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else {
                    return nil
                }
                return Workbench(
                    uuid: record.uuid,
                    name: record.name,
                    glyph: record.glyph,
                    tintHex: record.tintHex,
                    snapshot: snapshot,
                    sortOrder: record.sortOrder,
                    useCount: record.useCount
                )
            }
            isLoaded = true
        } catch {
            print("❌ Failed to load workbenches: \(error)")
        }
    }

    func create(name: String, glyph: String, tintHex: String, snapshot: WorkspaceSnapshot) async {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }

        let record = WorkbenchRecord(
            uuid: UUID().uuidString,
            name: name,
            glyph: glyph,
            tintHex: tintHex,
            snapshot: json,
            sortOrder: workbenches.count,
            lastUsedAt: nil,
            useCount: 0,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await CosmoDatabase.shared.asyncWrite { db in
                try record.insert(db)
            }
            await load()
        } catch {
            print("❌ Failed to save workbench: \(error)")
        }
    }

    func delete(uuid: String) async {
        do {
            _ = try await CosmoDatabase.shared.asyncWrite { db in
                try WorkbenchRecord.deleteOne(db, key: ["uuid": uuid])
            }
            await load()
        } catch {
            print("❌ Failed to delete workbench: \(error)")
        }
    }

    func markUsed(uuid: String) async {
        let now = ISO8601DateFormatter().string(from: Date())
        try? await CosmoDatabase.shared.asyncWrite { db in
            try db.execute(
                sql: "UPDATE workbenches SET useCount = useCount + 1, lastUsedAt = ? WHERE uuid = ?",
                arguments: [now, uuid]
            )
        }
    }
}

// MARK: - Layout Miniature

/// The live diagram of a workspace arrangement — the hero of the composer,
/// reused at micro scale in the sidebar strip tooltips.
struct WorkbenchMiniature: View {
    let snapshot: WorkspaceSnapshot
    let tint: Color
    var destinationName: String = ""

    var body: some View {
        HStack(spacing: 4) {
            mainRegion
            if !snapshot.panes.isEmpty {
                paneDeck
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.glassSectionFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
    }

    private var mainRegion: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(DS.surfaceElevated)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: snapshot.destination.glyph)
                        .font(DS.subheadline)
                        .foregroundStyle(tint)
                    if !destinationName.isEmpty {
                        Text(destinationName)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.borderSubtle, lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
    }

    private var paneDeck: some View {
        HStack(spacing: 3) {
            ForEach(Array(snapshot.panes.enumerated()), id: \.offset) { index, pane in
                paneSliver(pane, isFocused: index == snapshot.focusedPaneIndex)
            }
        }
    }

    @ViewBuilder
    private func paneSliver(_ pane: WorkspaceSnapshot.PaneDescriptor, isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isFocused ? tint.opacity(0.14) : DS.surfaceElevated)
            .overlay(
                Group {
                    if isFocused {
                        Image(systemName: sliverGlyph(for: pane))
                            .font(DS.caption2)
                            .foregroundStyle(tint)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isFocused ? tint.opacity(0.4) : DS.borderSubtle, lineWidth: 0.5)
            )
            .frame(width: isFocused ? 40 : 12)
    }

    private func sliverGlyph(for pane: WorkspaceSnapshot.PaneDescriptor) -> String {
        if pane.kind == .entity,
           let raw = pane.entityTypeRaw,
           let type = EntityType(rawValue: raw) {
            return type.icon
        }
        switch pane.kind {
        case .thinkspace: return "rectangle.3.group"
        case .commandCenter: return "square.grid.2x2"
        case .swipeGallery: return "bookmark"
        case .webBrowser: return "globe"
        case .cosmoWindow: return "brain.head.profile"
        case .inlineAssistant: return "sparkles"
        case .entity: return "doc.text"
        }
    }
}

// MARK: - Composer

/// The bench creation surface. Hero: the live miniature of what you're saving.
struct WorkbenchComposerView: View {
    let snapshot: WorkspaceSnapshot
    let destinationName: String
    let onSave: (_ name: String, _ glyph: String, _ tintHex: String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var glyph = "square.grid.2x2"
    @State private var tintHex: String = ThinkspaceManager.accentColorPalette.first ?? "2D6A4F"
    @FocusState private var nameFocused: Bool

    private static let glyphChoices: [String] = [
        "square.grid.2x2", "rectangle.3.group", "doc.text", "lightbulb",
        "tray", "books.vertical", "bookmark", "sparkles",
        "calendar", "checkmark.circle", "pencil.and.outline", "newspaper",
        "megaphone", "video", "music.note", "leaf",
        "flame", "moon.stars", "sun.max", "bolt",
        "map", "shippingbox", "scope", "graduationcap"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            WorkbenchMiniature(snapshot: snapshot, tint: Color(hex: tintHex), destinationName: destinationName)
                .frame(height: 120)
            nameField
            glyphPicker
            tintRow
            footer
        }
        .padding(24)
        .frame(width: 480)
        .background(DS.bg)
        .onAppear { nameFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Save Workbench")
                .font(DS.title2)
                .foregroundStyle(DS.text)
            Text("Rebuild this exact layout any time with one keystroke.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var nameField: some View {
        TextField("Workbench name", text: $name)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .focused($nameFocused)
            .onSubmit(save)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .dsGlassInput(isFocused: nameFocused, cornerRadius: 10)
            .accessibilityLabel("Workbench name")
    }

    private var glyphPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(Self.glyphChoices, id: \.self) { choice in
                glyphCell(choice)
            }
        }
    }

    private func glyphCell(_ choice: String) -> some View {
        let isSelected = glyph == choice
        return Button {
            withAnimation(ProMotionSprings.snappy) { glyph = choice }
        } label: {
            Image(systemName: choice)
                .font(DS.subheadline)
                .foregroundStyle(isSelected ? Color(hex: tintHex) : DS.textSecondary)
                .frame(width: 38, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? DS.accentSoft : DS.glassCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color(hex: tintHex).opacity(0.5) : DS.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Glyph \(choice)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var tintRow: some View {
        HStack(spacing: 8) {
            ForEach(ThinkspaceManager.accentColorPalette.prefix(8), id: \.self) { hex in
                tintSwatch(hex)
            }
            Spacer(minLength: 0)
        }
    }

    private func tintSwatch(_ hex: String) -> some View {
        let isSelected = tintHex == hex
        return Button {
            withAnimation(ProMotionSprings.snappy) { tintHex = hex }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                )
                .overlay(
                    Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5)
                )
                .scaleEffect(isSelected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tint color")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .keyboardShortcut(.cancelAction)

            Button(action: save) {
                Text("Save Workbench")
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.5 : 1)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, glyph, tintHex)
    }
}

// MARK: - Sidebar Strip

/// The quiet bench strip at the top of the global sidebar — glyph-only
/// buttons (full names live in tooltips and the composer).
struct WorkbenchStripView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredId: String?

    private var store: WorkbenchStore { .shared }

    var body: some View {
        Group {
            if !store.workbenches.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(store.workbenches.prefix(9).enumerated()), id: \.element.uuid) { index, bench in
                        benchButton(bench, position: index + 1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.glassSectionFill)
                )
                .padding(.bottom, 10)
            }
        }
        .task { await store.loadIfNeeded() }
    }

    private func benchButton(_ bench: Workbench, position: Int) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.applyWorkbench,
                object: nil,
                userInfo: ["uuid": bench.uuid]
            )
        } label: {
            Image(systemName: bench.glyph)
                .font(DS.caption)
                .foregroundStyle(bench.tint)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hoveredId == bench.uuid ? DS.surfaceHover : .clear)
                )
                .scaleEffect(hoveredId == bench.uuid ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) {
                hoveredId = hovering ? bench.uuid : nil
            }
        }
        .help("\(bench.name) (⌃\(position))")
        .contextMenu {
            Button("Delete Workbench", role: .destructive) {
                Task { await store.delete(uuid: bench.uuid) }
            }
        }
        .accessibilityLabel("Apply workbench \(bench.name)")
    }
}
