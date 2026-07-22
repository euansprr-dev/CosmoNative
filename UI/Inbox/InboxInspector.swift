// CosmoOS/UI/Inbox/InboxInspector.swift
// The focused capture's detail panel — essence, the suggestion with its one-line
// why, a live minimap of the destination thinkspace (drag the ghost block to
// adjust the landing spot), alternates, and the closed-loop verb grid.
// Floats over the queue as warm glass, like the Connection workspace inspector.
// June 2026 — Inbox Revamp (INBOX_REVAMP_PLAN.md §3–4)

import SwiftUI
import GRDB

struct InboxInspector: View {
    let item: InboxItem
    /// The surface behind the panel — the triage queue or a capture lane;
    /// both speak the same verb grammar (InboxInspectorHost).
    let viewModel: any InboxInspectorHost
    /// Set when opened from a capture lane — reframes the suggestion
    /// fallback copy, since a lane capture is already home.
    let laneName: String?

    init(item: InboxItem, viewModel: any InboxInspectorHost, laneName: String? = nil) {
        self.item = item
        self.viewModel = viewModel
        self.laneName = laneName
        _displayText = State(initialValue: item.rawText)
    }

    @State private var appeared = false
    @State private var adjustedPosition: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Inline edit
    /// The capture's current text — seeded from `item.rawText`, replaced with
    /// the saved value the moment an edit commits (the repo observation that
    /// would refresh `item` is debounced, so a local echo keeps it instant).
    @State private var displayText: String
    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHoveringEssence = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.space16) {
                header
                essenceSection
                originalsSection
                suggestionSection
                minimapSection
                alternatesSection
                verbGrid
            }
            .padding(DS.space18)
        }
        .frame(width: 340)
        .cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)
        .offset(x: appeared ? 0 : 24)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.gentle) {
                appeared = true
            }
        }
        .onChange(of: item.uuid) {
            adjustedPosition = nil
            // A different capture took focus — drop any half-typed edit and
            // reseed from the new item.
            isEditing = false
            editorFocused = false
            displayText = item.rawText
        }
        .onChange(of: item.rawText) { _, newValue in
            // Sync landed (this device's save, or the phone's edit) — adopt it
            // unless the user is mid-edit on this row.
            if !isEditing { displayText = newValue }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(item.title ?? String(item.rawText.prefix(48)))
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)

                Text("\(sourceLabel) · \(relativeTime)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.closeInspector()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DS.glassSectionFill, in: .circle)
            }
            .buttonStyle(.plain)
            .help("Close inspector (esc)")
            .accessibilityLabel("Close inspector")
        }
    }

    // MARK: - Essence

    /// The capture text, correctable in place: a hover-revealed pencil (macOS
    /// manners) blurs the essence into an editor with Save / Cancel — ⌘↵ to
    /// commit, Esc to abandon.
    private var essenceSection: some View {
        Group {
            if isEditing {
                essenceEditor
            } else {
                essenceReader
            }
        }
        .transition(.blurReplace)
        .padding(DS.space12)
        .background(DS.glassSectionFill, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.focusRing, lineWidth: isEditing ? 1.5 : 0)
        )
        .animation(ProMotionSprings.gentle, value: isEditing)
    }

    private var essenceReader: some View {
        ZStack(alignment: .topTrailing) {
            Text(displayText)
                .font(DS.body)
                .foregroundStyle(DS.text.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if isHoveringEssence {
                Button {
                    beginEditing()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(DS.glassCardFill, in: .circle)
                }
                .buttonStyle(.plain)
                .help("Edit capture text")
                .accessibilityLabel("Edit capture text")
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHoveringEssence = hovering }
        }
    }

    private var essenceEditor: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TextEditor(text: $draft)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 220)
                .focused($editorFocused)
                .tint(DS.accent)
                .accessibilityLabel("Capture text")

            HStack(spacing: DS.space8) {
                Spacer()
                Button("Cancel") { cancelEditing() }
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Discard changes (esc)")

                Button("Save") { saveEdit() }
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(canSave ? DS.accent : DS.textMuted)
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Save (⌘↩)")
            }
        }
    }

    /// A blank field or an unchanged one has nothing to commit.
    private var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != displayText
    }

    private func beginEditing() {
        draft = displayText
        withAnimation(ProMotionSprings.gentle) { isEditing = true }
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        withAnimation(ProMotionSprings.gentle) { isEditing = false }
    }

    private func saveEdit() {
        guard canSave else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editorFocused = false
        displayText = text
        withAnimation(ProMotionSprings.gentle) { isEditing = false }
        Task { await viewModel.editCaptureText(item, to: text) }
    }

    // MARK: - Originals (captured pages)

    /// The physical pages behind a scanned capture — click to see the ink
    /// the transcript came from.
    @ViewBuilder
    private var originalsSection: some View {
        if !item.attachmentUUIDs.isEmpty {
            AttachmentRail(attachmentUUIDs: item.attachmentUUIDs, thumbSize: CGSize(width: 64, height: 84))
        }
    }

    // MARK: - Suggestion

    @ViewBuilder
    private var suggestionSection: some View {
        if item.hasActionableSuggestion {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space6) {
                    Image(systemName: suggestionIcon)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(suggestionTint)
                    Text(item.spatialDestinationTitle)
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(suggestionTint)
                        .lineLimit(2)
                }

                if let why = suggestionWhy {
                    Text(why)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.space12)
            .background(suggestionTint.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(suggestionTint.opacity(0.18), lineWidth: 0.5)
            )
        } else {
            Text(suggestionFallbackCopy)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suggestionFallbackCopy: String {
        if let laneName {
            return "Filed in \(laneName) — it stays here unless a verb below moves it onward."
        }
        return item.status == .pending
            ? "Cosmo is still reading this capture."
            : "Nothing in your system matched confidently — file it with a verb below, or leave it for the next taxonomy pass."
    }

    private var suggestionWhy: String? {
        if let rationale = item.rationale, !rationale.isEmpty { return rationale }
        if let summary = item.placementPlanSummary, !summary.isEmpty { return summary }
        return nil
    }

    // MARK: - Minimap

    @ViewBuilder
    private var minimapSection: some View {
        if let thinkspaceId = targetThinkspaceId, item.classification == .place {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Landing spot")
                    .dsSmallCapsLabel()

                InboxPlacementMinimap(
                    thinkspaceId: thinkspaceId,
                    proposedPosition: proposedPosition,
                    adjustedPosition: $adjustedPosition
                )
                .frame(height: 160)

                Text(adjustedPosition == nil
                     ? "Drag the glowing block to choose a different spot."
                     : "Adjusted — Place uses your spot.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private var targetThinkspaceId: String? {
        item.primaryRecommendationValue?.thinkspaceId
            ?? item.primaryRecommendationValue?.placementPlan?.targetThinkspaceId
            ?? item.placeThinkspaceId
    }

    private var proposedPosition: CGPoint? {
        guard let plan = item.primaryRecommendationValue?.placementPlan,
              let x = plan.blockPositionX,
              let y = plan.blockPositionY else { return nil }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Alternates

    @ViewBuilder
    private var alternatesSection: some View {
        let alternates = item.alternativeRecommendationValues
            .filter { $0.kind != .createStandaloneAtom }
            .prefix(2)
        if !alternates.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text("Also possible")
                    .dsSmallCapsLabel()

                ForEach(Array(alternates), id: \.id) { alternate in
                    Button {
                        Task { await applyAlternate(alternate) }
                    } label: {
                        HStack(spacing: DS.space6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(DS.caption2)
                            Text(alternate.destinationPath)
                                .font(DS.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(DS.textSecondary)
                        .padding(.vertical, DS.space6)
                        .padding(.horizontal, DS.space8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(DS.glassSectionFill, in: .rect(cornerRadius: 8))
                    .help("Place here instead")
                }
            }
        }
    }

    private func applyAlternate(_ recommendation: InboxRecommendation) async {
        await viewModel.applyAlternate(item, recommendation: recommendation)
    }

    // MARK: - Verbs

    private var verbGrid: some View {
        VStack(spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                primaryVerb
                secondaryVerb(label: "Place & Go", icon: "arrowshape.turn.up.right", shortcut: "⌘⏎") {
                    Task { await viewModel.placeAndGo(item) }
                }
            }
            HStack(spacing: DS.space8) {
                secondaryVerb(label: "Task", icon: "checkmark.circle", shortcut: "T") {
                    Task { await viewModel.makeTask(item) }
                }
                secondaryVerb(label: "Ask", icon: "questionmark.bubble", shortcut: "A") {
                    Task { await viewModel.askInDeepDive(item) }
                }
                secondaryVerb(label: "Idea", icon: "lightbulb", shortcut: "I") {
                    Task { await viewModel.fileAsIdea(item) }
                }
                // A link capture can become a swipe — the command bar's own
                // capture pipeline, offered right where the user is triaging.
                if item.detectedSwipeURL != nil {
                    secondaryVerb(label: "Swipe", icon: "rectangle.stack", shortcut: "S") {
                        Task { await viewModel.fileAsSwipe(item) }
                    }
                }
            }
            HStack(spacing: DS.space8) {
                // Manual grow — a thought becomes (or feeds) a seedling in
                // the nursery, no canvas object, no premature page.
                secondaryVerb(label: "Grow", icon: "leaf", shortcut: "G") {
                    Task { await viewModel.growSeedling(item) }
                }
                if !item.relatedAtomUUIDsValue.isEmpty {
                    secondaryVerb(label: "Connect", icon: "point.3.connected.trianglepath.dotted", shortcut: "C") {
                        Task { await viewModel.connectCapture(item) }
                    }
                }
                secondaryVerb(label: "Change", icon: "slider.horizontal.3", shortcut: nil) {
                    viewModel.showOverride(for: item)
                }
                dismissVerb
            }
        }
    }

    @ViewBuilder
    private var primaryVerb: some View {
        // The button says what accepting DOES: a seedling suggestion grows
        // mass in the nursery; a page feed stages a ✓/✗ ghost row; only
        // spatial suggestions actually "place".
        let label: String = {
            if item.classification == .merge { return "Merge" }
            if isSeedlingSuggestion { return "Grow" }
            if item.primaryRouteKind == InboxRouteKind.feedConnection.rawValue { return "Stage" }
            return "Place"
        }()
        Button {
            Task { await viewModel.place(item, adjustedPosition: adjustedPosition) }
        } label: {
            Label(label, systemImage: isSeedlingSuggestion ? "leaf" : "checkmark")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(item.classification == .merge ? DS.orange : DS.accent, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("\(label) (⏎)")
        .disabled(!item.hasActionableSuggestion)
        .opacity(item.hasActionableSuggestion ? 1 : 0.4)
    }

    private var isSeedlingSuggestion: Bool {
        item.primaryRouteKind == InboxRouteKind.feedSeedling.rawValue
            || item.primaryRouteKind == InboxRouteKind.startSeedling.rawValue
            || item.primaryRouteKind == InboxRouteKind.germinateConnection.rawValue
    }

    private func secondaryVerb(label: String, icon: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(label) (\($0))" } ?? label)
    }

    private var dismissVerb: some View {
        Button {
            Task { await viewModel.dismiss(item: item) }
        } label: {
            Label("Dismiss", systemImage: "xmark")
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.red)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(DS.redSoft, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Dismiss (⌫)")
    }

    // MARK: - Metadata

    private var suggestionIcon: String {
        item.classification == .merge ? "arrow.triangle.merge" : "arrow.turn.down.right"
    }

    private var suggestionTint: Color {
        item.classification == .merge ? DS.orange : DS.accent
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

// MARK: - Live placement minimap

/// A miniature of the destination thinkspace: real block footprints, the
/// proposed landing spot glowing, and a draggable ghost to adjust it.
private struct InboxPlacementMinimap: View {
    let thinkspaceId: String
    let proposedPosition: CGPoint?
    @Binding var adjustedPosition: CGPoint?

    @State private var blocks: [MiniBlock] = []
    @State private var dragLocation: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    struct MiniBlock: Identifiable {
        let id: String
        let rect: CGRect
    }

    var body: some View {
        GeometryReader { proxy in
            let transform = canvasTransform(in: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.bg.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DS.borderSubtle, lineWidth: 0.5)
                    )

                ForEach(blocks) { block in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DS.textMuted.opacity(0.22))
                        .frame(
                            width: max(4, block.rect.width * transform.scale),
                            height: max(3, block.rect.height * transform.scale)
                        )
                        .position(transform.apply(CGPoint(x: block.rect.midX, y: block.rect.midY)))
                }

                if let ghostCenter = ghostCenter(transform: transform) {
                    ghostBlock(at: ghostCenter)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(transform: transform))
        }
        .task(id: thinkspaceId) { await loadBlocks() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Destination minimap — drag to adjust the landing spot")
    }

    private func ghostBlock(at center: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DS.accent.opacity(0.85))
            .frame(width: 16, height: 11)
            .shadow(color: DS.accent.opacity(pulse ? 0.55 : 0.25), radius: pulse ? 9 : 5)
            .position(center)
    }

    private func ghostCenter(transform: CanvasTransform) -> CGPoint? {
        if let dragLocation { return dragLocation }
        if let adjustedPosition { return transform.apply(adjustedPosition) }
        if let proposedPosition { return transform.apply(proposedPosition) }
        return nil
    }

    private func dragGesture(transform: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragLocation = value.location
            }
            .onEnded { value in
                dragLocation = nil
                adjustedPosition = transform.invert(value.location)
            }
    }

    // MARK: - Data

    private func loadBlocks() async {
        let id = thinkspaceId
        let records = (try? await CosmoDatabase.shared.asyncRead { db in
            try CanvasBlockRecord
                .filter(Column("thinkspace_id") == id)
                .filter(Column("is_deleted") == false)
                .limit(80)
                .fetchAll(db)
        }) ?? []

        blocks = records.map { record in
            MiniBlock(
                id: record.id,
                rect: CGRect(
                    x: Double(record.positionX),
                    y: Double(record.positionY),
                    width: Double(record.width ?? 320),
                    height: Double(record.height ?? 200)
                )
            )
        }
    }

    // MARK: - Transform

    private struct CanvasTransform {
        let scale: CGFloat
        let offset: CGPoint

        func apply(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
        }

        func invert(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
        }
    }

    private func canvasTransform(in size: CGSize) -> CanvasTransform {
        var bounds = blocks.reduce(CGRect.null) { $0.union($1.rect) }
        if let proposedPosition {
            bounds = bounds.union(CGRect(origin: proposedPosition, size: CGSize(width: 320, height: 200)))
        }
        if bounds.isNull || bounds.isEmpty {
            bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        }
        bounds = bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.08)

        let inset: CGFloat = 10
        let availableWidth = max(size.width - inset * 2, 1)
        let availableHeight = max(size.height - inset * 2, 1)
        let scale = min(availableWidth / bounds.width, availableHeight / bounds.height)
        let offset = CGPoint(
            x: inset + (availableWidth - bounds.width * scale) / 2 - bounds.minX * scale,
            y: inset + (availableHeight - bounds.height * scale) / 2 - bounds.minY * scale
        )
        return CanvasTransform(scale: scale, offset: offset)
    }
}
