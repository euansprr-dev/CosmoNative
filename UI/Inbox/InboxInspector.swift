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
    /// "New Space…" from the inquiry menu — names the Space before the
    /// inquiry starts inside it.
    @State private var newSpacePrompt = false
    @State private var newSpaceName = ""
    /// "New concept…" from the grow menu — names the seed first.
    @State private var newConceptPrompt = false
    @State private var newConceptName = ""
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
                lensRow
                suggestionSection
                alternatesSection
                verbGrid
            }
            .padding(DS.space18)
        }
        .frame(width: 390)
        .background(DS.bg)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(DS.borderSubtle, lineWidth: 0.5))
        .offset(x: appeared ? 0 : 24)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) {
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
        .alert("New Space", isPresented: $newSpacePrompt) {
            TextField("Space name", text: $newSpaceName)
            Button("Start inquiry") {
                let name = newSpaceName
                Task { await viewModel.startInquiry(item, in: .new(name: name)) }
            }
            .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A Space named for the topic, with this capture's inquiry started inside it.")
        }
        .alert("New concept", isPresented: $newConceptPrompt) {
            TextField("Concept name", text: $newConceptName)
            Button("Start concept") {
                let name = newConceptName
                Task { await viewModel.startSeedling(item, named: name) }
            }
            .disabled(newConceptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A seedling in the nursery with this thought as its first seed. No page until you develop it.")
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
                .opacity(isHoveringEssence ? 1 : 0.35)
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

    // MARK: - Lens

    /// The inferred lens with its reason, for a capture that carries a link.
    /// Only a link is genuinely ambiguous — a screenshot is craft by
    /// construction, and plain text has nothing to research.
    @ViewBuilder
    private var lensRow: some View {
        if let url = item.detectedSwipeURL {
            let verdict = SwipeLensRouter.inferLens(
                .init(url: url, prose: item.rawText)
            )
            SwipeLensPill(verdict: verdict) { chosen in
                SwipeLensRouter.recordDecision(lens: chosen, url: url)
                switch chosen {
                case .swipe:
                    Task { await viewModel.fileAsSwipe(item) }
                case .research:
                    // The flip files, both ways: research lands in the Library;
                    // "Save as Research ›" below names a Space or Concept.
                    Task { await viewModel.fileAsResearch(item, destination: .libraryResearch) }
                }
            }
        }
    }

    // MARK: - Suggestion

    @ViewBuilder
    private var suggestionSection: some View {
        if item.hasActionableSuggestion {
            VStack(alignment: .leading, spacing: DS.space6) {
                // What the capture BECOMES — never implicit. The destination
                // line below says where; this line says what.
                HStack(spacing: DS.space6) {
                    Image(systemName: suggestionIcon)
                        .font(DS.caption.weight(.semibold))
                    Text(outcomeNoun)
                        .font(DS.caption.weight(.semibold))
                }
                .foregroundStyle(suggestionTint)

                Text(item.spatialDestinationTitle)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(2)

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

    private var outcomeNoun: String {
        if let recommendation = item.primaryRecommendationValue, let action = recommendation.filingAction {
            return action.title
        }
        if let kind = item.primaryRouteKindValue {
            return kind.outcomeNoun(suggestedAtomType: item.placeAtomType)
        }
        if item.classification == .merge { return "Attach reference" }
        let atomNoun = item.placeAtomType
            .flatMap(AtomType.init(rawValue:))
            .map(\.displayName) ?? "Note"
        return "Save \(atomNoun)"
    }

    private var suggestionFallbackCopy: String {
        if let laneName {
            return "Filed in \(laneName) — it stays here unless a verb below moves it onward."
        }
        return item.status == .pending
            ? "Cosmo is still reading this capture."
            : "Choose where to save this capture, or leave it here until you are ready."
    }

    private var suggestionWhy: String? {
        if let recommendation = item.primaryRecommendationValue, let destination = recommendation.filingDestination {
            return (recommendation.filingAction ?? destination.defaultAction).consequence(in: destination)
        }
        if item.classification == .merge { return "Keeps the complete original and adds a reference for review. Existing writing stays as it is." }
        if item.primaryRouteKindValue == .placeInThinkspace || item.primaryRouteKindValue == .placeInExistingCluster {
            return "Adds the Page to this destination. The canvas arrangement stays as it is."
        }
        if item.primaryRouteKindValue == .startInquiry {
            return "Starts a resumable inquiry in this Space with the capture as its question. Anything beyond the question becomes its first note."
        }
        if item.primaryRouteKindValue == .germinateDeepDive {
            return "Creates a Space named for the topic and starts the inquiry inside it. Undo removes both."
        }
        if let rationale = item.rationale, !rationale.isEmpty { return rationale }
        if let summary = item.placementPlanSummary, !summary.isEmpty { return summary }
        return nil
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
                        viewModel.showOverride(for: item)
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
                    .help("Review another destination")
                }
            }
        }
    }

    private func applyAlternate(_ recommendation: InboxRecommendation) async {
        await viewModel.applyAlternate(item, recommendation: recommendation)
    }

    // MARK: - Verbs

    private var verbGrid: some View {
        VStack(spacing: DS.space12) {
            primaryVerb
            if item.hasActionableSuggestion {
                Button("Change destination…") { viewModel.showOverride(for: item) }
                    .buttonStyle(.plain).font(DS.callout).foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity, minHeight: 44).help("Choose where and how to save this capture")
            }
            HStack {
                Menu {
                    Button("Create task", systemImage: "checkmark.circle") { Task { await viewModel.makeTask(item) } }
                    // Research gets a room: the capture becomes an inquiry
                    // session inside a Space the user names — never a bare
                    // question under whichever topic was touched last.
                    Menu {
                        ForEach(viewModel.inquirySpaces) { space in
                            Button(space.name) { Task { await viewModel.startInquiry(item, in: .existing(space)) } }
                        }
                        if !viewModel.inquirySpaces.isEmpty { Divider() }
                        Button("New Space…", systemImage: "plus") {
                            newSpaceName = item.title ?? String(item.rawText.prefix(48))
                            newSpacePrompt = true
                        }
                    } label: {
                        Label("Start inquiry in", systemImage: "text.magnifyingglass")
                    }
                    if viewModel.lanes.contains(where: { $0.uuid != item.restingLaneID }) {
                        Menu {
                            ForEach(viewModel.lanes.filter { $0.uuid != item.restingLaneID }, id: \.uuid) { lane in
                                Button(lane.name, systemImage: lane.icon) { Task { await viewModel.moveToLane(item, lane: lane) } }
                            }
                        } label: {
                            Label("Move to lane", systemImage: "tray.2")
                        }
                    }
                    Button("Save Content idea…", systemImage: "lightbulb") { viewModel.showOverride(for: item) }
                    if item.canBecomeResearch {
                        // A source to READ lives with the research lens — a
                        // Space's materials, a Concept's References, the
                        // Library — never in the Swipe File.
                        Menu {
                            Button("Library", systemImage: "books.vertical") {
                                Task { await viewModel.fileAsResearch(item, destination: .libraryResearch) }
                            }
                            if !viewModel.inquirySpaces.isEmpty { Divider() }
                            ForEach(viewModel.inquirySpaces) { space in
                                Button(space.name, systemImage: "square.grid.2x2") {
                                    Task { await viewModel.fileAsResearch(item, destination: .init(kind: .space, uuid: space.id, spaceID: space.id, name: space.name, path: space.name)) }
                                }
                            }
                            Divider()
                            Button("Choose…", systemImage: "tray.and.arrow.down") { viewModel.showOverride(for: item, focus: .research) }
                        } label: {
                            Label("Save as Research in", systemImage: "books.vertical")
                        }
                    }
                    if item.canBecomeSwipe {
                        Button("Save in Swipe", systemImage: item.predictedSwipeKind.iconName) { Task { await viewModel.fileAsSwipe(item) } }
                    }
                    if viewModel.hasFlows {
                        Button("Add to Swipe flow…", systemImage: SwipeKind.flow.iconName) { Task { await viewModel.addCaptureToFlow(item) } }
                    }
                    Divider()
                    // Thoughts feed the concept they belong to — the seeds are
                    // listed, ripest first; a new one is a name away.
                    Menu {
                        ForEach(viewModel.seedlings, id: \.uuid) { seedling in
                            Button("\(seedling.name) · \(seedling.massSummary)", systemImage: "leaf") {
                                Task { await viewModel.growSeedling(item, seedling: seedling) }
                            }
                        }
                        if !viewModel.seedlings.isEmpty { Divider() }
                        Button("New concept…", systemImage: "plus") {
                            newConceptName = item.title ?? String(item.rawText.prefix(48))
                            newConceptPrompt = true
                        }
                    } label: {
                        Label("Grow a concept", systemImage: "leaf")
                    }
                    if !item.relatedAtomUUIDsValue.isEmpty {
                        Button("Save related Concept", systemImage: "point.3.connected.trianglepath.dotted") { Task { await viewModel.connectCapture(item) } }
                    }
                } label: {
                    Label("More actions", systemImage: "ellipsis").font(DS.callout).foregroundStyle(DS.textSecondary)
                }
                .menuStyle(.borderlessButton).fixedSize().help("Additional capture actions")
                Spacer()
                Button("Dismiss") { Task { await viewModel.dismiss(item: item) } }
                    .buttonStyle(.plain).font(DS.callout).foregroundStyle(DS.textSecondary)
                    .frame(minHeight: 44).help("Dismiss capture (Delete)")
            }
        }
    }

    @ViewBuilder
    private var primaryVerb: some View {
        // The button says what accepting DOES: start/grow a concept, stage a
        // ✓/✗ ghost row, answer a question — "Place" only for spatial kinds.
        let label: String = {
            if !item.hasActionableSuggestion { return "Choose destination…" }
            if let action = item.primaryRecommendationValue?.filingAction { return action.title }
            if let kind = item.primaryRouteKindValue { return kind.primaryVerbLabel }
            return item.classification == .merge ? "Attach reference" : "Save Page"
        }()
        Button {
            if item.hasActionableSuggestion { Task { await viewModel.place(item, adjustedPosition: nil) } }
            else { viewModel.showOverride(for: item) }
        } label: {
            Label(label, systemImage: isSeedlingSuggestion ? "leaf" : "checkmark")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(item.classification == .merge ? DS.orange : DS.accent, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("\(label) (⏎)")

    }

    private var isSeedlingSuggestion: Bool {
        item.primaryRouteKindValue?.isSeedlingKind == true
    }

    private func secondaryVerb(label: String, icon: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
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
                .frame(height: 44)
                .background(DS.redSoft, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Dismiss (⌫)")
    }

    // MARK: - Metadata

    private var suggestionIcon: String {
        if let kind = item.primaryRouteKindValue { return kind.outcomeIcon }
        return item.classification == .merge ? "arrow.triangle.merge" : "arrow.turn.down.right"
    }

    private var suggestionTint: Color {
        if let kind = item.primaryRouteKindValue { return kind.outcomeTint }
        return item.classification == .merge ? DS.orange : DS.accent
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
