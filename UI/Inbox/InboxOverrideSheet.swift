import SwiftUI

/// One destination, one visible effect, one commit. Selecting a row previews it.
///
/// September 2026: every place a capture can go lives here — capture lanes
/// (the capture stays a capture), inquiry Spaces (the capture becomes a
/// resumable research session, in an existing Space or a new one named for
/// the topic), growing concepts (the thought feeds a seedling, or names a
/// new one), and the filing destinations (Pages, Groups, clients, Swipe,
/// Today, the Library's research shelf). A link or scanned pages can be
/// saved to a Space, Group, Page, or Concept as a RESEARCH SOURCE instead
/// of a Page — the "Save as" control on the row. `focus` only decides
/// which family is listed first.
struct InboxOverrideSheet: View {
    let item: InboxItem
    @Bindable var viewModel: InboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var destinations: [InboxFilingDestination] = []
    @State private var selected: Choice?
    @State private var action: InboxFilingAction = .page
    @State private var newSpaceName = ""
    @State private var newConceptName = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    /// Everything the sheet can commit to.
    enum Choice: Identifiable, Equatable {
        case filing(InboxFilingDestination)
        case lane(CaptureDestination)
        case inquiry(InquirySpaceOption)
        case newSpaceInquiry
        case seedling(Seedling)
        case newSeedling

        var id: String {
            switch self {
            case .filing(let destination): return "filing:\(destination.id)"
            case .lane(let lane): return "lane:\(lane.uuid)"
            case .inquiry(let space): return "inquiry:\(space.id)"
            case .newSpaceInquiry: return "inquiry:new"
            case .seedling(let seedling): return "seedling:\(seedling.uuid)"
            case .newSeedling: return "seedling:new"
            }
        }

        var name: String {
            switch self {
            case .filing(let destination): return destination.name
            case .lane(let lane): return lane.name
            case .inquiry(let space): return space.name
            case .newSpaceInquiry: return "New Space…"
            case .seedling(let seedling): return seedling.name
            case .newSeedling: return "New concept…"
            }
        }

        var path: String {
            switch self {
            case .filing(let destination): return destination.path
            case .lane(let lane): return "Lanes › \(lane.name)"
            case .inquiry(let space): return "\(space.name) › Inquiries"
            case .newSpaceInquiry: return "A Space named for the topic, with the inquiry inside"
            case .seedling(let seedling): return "Growing · \(seedling.massSummary)"
            case .newSeedling: return "A seedling in the nursery, this thought its first seed"
            }
        }

        var symbol: String {
            switch self {
            case .filing(let destination): return destination.symbol
            case .lane(let lane): return lane.icon
            case .inquiry: return "text.magnifyingglass"
            case .newSpaceInquiry: return "plus.square.dashed"
            case .seedling: return "leaf"
            case .newSeedling: return "plus.circle.dashed"
            }
        }
    }

    private struct Family: Identifiable {
        let id: InboxOverrideFocus
        let title: String
        let choices: [Choice]
    }

    /// Families in focus order — the one the caller asked for leads.
    private var families: [Family] {
        let laneChoices = viewModel.lanes.filter { $0.uuid != item.restingLaneID }.map(Choice.lane)
        let inquiryChoices = viewModel.inquirySpaces.map(Choice.inquiry) + [.newSpaceInquiry]
        let conceptChoices = viewModel.seedlings.map(Choice.seedling) + [.newSeedling]
        let filingChoices = destinations.map(Choice.filing)
        let all: [Family] = [
            Family(id: .lanes, title: "Capture lanes", choices: laneChoices),
            Family(id: .inquiry, title: "Start an inquiry", choices: inquiryChoices),
            Family(id: .concepts, title: "Growing concepts", choices: conceptChoices),
            Family(id: .destinations, title: item.canBecomeResearch ? "Save to (as a Page or a Research source)" : "Save to", choices: filingChoices)
        ].filter { !$0.choices.isEmpty }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty ? all : all.compactMap { family in
            let matches = family.choices.filter {
                $0.name.localizedCaseInsensitiveContains(needle) || $0.path.localizedCaseInsensitiveContains(needle)
            }
            return matches.isEmpty ? nil : Family(id: family.id, title: family.title, choices: matches)
        }
        let leading: InboxOverrideFocus = viewModel.overrideFocus == .research ? .destinations : viewModel.overrideFocus
        return filtered.sorted { lhs, rhs in
            if lhs.id == leading { return true }
            if rhs.id == leading { return false }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            destinationList
            consequence
            footer
        }
        .frame(width: 540, height: 650)
        .background(DS.bg)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space16) {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("Choose destination").font(DS.title2).foregroundStyle(DS.text)
                Text(item.title ?? String(item.rawText.prefix(80)))
                    .font(DS.subheadline).foregroundStyle(DS.textSecondary).lineLimit(2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(DS.textSecondary)
            .help("Close destination picker (Esc)").accessibilityLabel("Close destination picker")
            .keyboardShortcut(.cancelAction)
        }
        .padding(DS.space24)
    }

    private var searchField: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.textMuted)
            TextField("Search Spaces, lanes, concepts, Pages, clients…", text: $query)
                .textFieldStyle(.plain).font(DS.body).focused($searchFocused)
                .accessibilityLabel("Search destinations")
        }
        .padding(DS.space12).dsGlassInput(cornerRadius: 14)
        .padding(.horizontal, DS.space24)
    }

    private var destinationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack { RoundedRectangle(cornerRadius: 4).fill(DS.surface).frame(width: 220, height: 16); Spacer() }
                            .padding(DS.space16).accessibilityHidden(true)
                    }
                } else if families.isEmpty {
                    Text("No destinations match. Try a Space, lane, concept, Page, Group, or client name.")
                        .font(DS.body).foregroundStyle(DS.textSecondary).padding(DS.space24)
                } else {
                    ForEach(families) { family in
                        Text(family.title)
                            .dsSmallCapsLabel()
                            .padding(.horizontal, DS.space12)
                            .padding(.top, DS.space12)
                            .padding(.bottom, DS.space4)
                        ForEach(family.choices) { choice in
                            InboxDestinationRow(choice: choice, isSelected: selected == choice) {
                                select(choice)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.space16).padding(.vertical, DS.space12)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder private var consequence: some View {
        if let selected {
            VStack(alignment: .leading, spacing: DS.space8) {
                switch selected {
                case .filing(let destination):
                    Text(destination.path).font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                    let options = actionOptions(for: destination)
                    if options.count > 1 {
                        Picker("Save as", selection: $action) {
                            ForEach(options, id: \.self) { option in
                                Text(saveAsLabel(option)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(action.consequence(in: destination)).font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .lane(let lane):
                    Text("Lanes › \(lane.name)").font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                    Text("Moves the capture into the \(lane.name) lane. It stays a capture there — nothing new is created, and its pages come along.")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .inquiry(let space):
                    Text("\(space.name) › Inquiries").font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                    Text(inquiryConsequence)
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .newSpaceInquiry:
                    TextField("Space name", text: $newSpaceName)
                        .textFieldStyle(.plain).font(DS.headline).foregroundStyle(DS.text)
                        .padding(DS.space10).dsGlassInput(cornerRadius: 10)
                        .accessibilityLabel("New Space name")
                    Text("Creates a Space named for the topic and starts the inquiry inside it. \(inquiryConsequence)")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .seedling(let seedling):
                    Text("Grows \u{201C}\(seedling.name)\u{201D}").font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                    Text("Adds this thought to the concept (\(seedling.massSummary)). No page and no canvas object — the concept ripens toward one development conversation.")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .newSeedling:
                    TextField("Concept name", text: $newConceptName)
                        .textFieldStyle(.plain).font(DS.headline).foregroundStyle(DS.text)
                        .padding(DS.space10).dsGlassInput(cornerRadius: 10)
                        .accessibilityLabel("New concept name")
                    Text("Names a new concept in the nursery with this thought as its first seed. A live concept with the same name is fed instead of forked.")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.space16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface).clipShape(.rect(cornerRadius: 14))
            .padding(.horizontal, DS.space24)
        }
    }

    private var inquiryConsequence: String {
        "This capture becomes the inquiry's question, ready to resume any time. Anything beyond the question becomes its first note."
    }

    /// The actions a destination can take for THIS capture. A link or scanned
    /// pages can become a Research source wherever the destination accepts
    /// one; plain prose keeps the page grammar.
    private func actionOptions(for destination: InboxFilingDestination) -> [InboxFilingAction] {
        let research = item.canBecomeResearch && destination.acceptsResearch
        switch destination.kind {
        case .page: return research ? [.reference, .childPage, .research] : [.reference, .childPage]
        case .connection: return research ? [.stageConnection, .research] : [.stageConnection]
        case .space, .group, .pages: return research ? [.page, .research] : [.page]
        case .research: return [.research]
        case .ideas: return [.idea]
        case .swipe: return [.swipe]
        case .today: return [.task]
        }
    }

    private func saveAsLabel(_ action: InboxFilingAction) -> String {
        switch action {
        case .page: return "Page"
        case .childPage: return "New child Page"
        case .reference: return "Reference"
        case .stageConnection: return "For review"
        case .research: return "Research source"
        case .idea: return "Idea"
        case .swipe: return "Swipe"
        case .task: return "Task"
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if let error { Text(error).font(DS.subheadline).foregroundStyle(DS.textSecondary) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(DS.textSecondary)
                Spacer()
                Button(isSaving ? "Saving…" : commitTitle) { Task { await save() } }
                    .buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(!canCommit || isSaving).keyboardShortcut(.defaultAction)
                    .help("\(commitTitle) (Return)")
            }
        }
        .padding(DS.space24)
    }

    private var commitTitle: String {
        switch selected {
        case .filing: return action.title
        case .lane: return "Move to lane"
        case .inquiry: return "Start inquiry"
        case .newSpaceInquiry: return "Create Space & start inquiry"
        case .seedling: return "Grow concept"
        case .newSeedling: return "Start concept"
        case nil: return "Save"
        }
    }

    private var canCommit: Bool {
        switch selected {
        case .newSpaceInquiry: return !newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .newSeedling: return !newConceptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case nil: return false
        default: return true
        }
    }

    private func select(_ choice: Choice) {
        selected = choice
        if case .filing(let destination) = choice {
            // Opened to save research: the research action leads wherever
            // the destination can take one.
            let wantsResearch = viewModel.overrideFocus == .research && item.canBecomeResearch && destination.acceptsResearch
            action = wantsResearch ? .research : destination.defaultAction
        }
        if case .newSpaceInquiry = choice, newSpaceName.isEmpty {
            newSpaceName = item.title ?? String(item.rawText.prefix(48))
        }
        if case .newSeedling = choice, newConceptName.isEmpty {
            newConceptName = item.title ?? String(item.rawText.prefix(48))
        }
        error = nil
    }

    private func load() async {
        do {
            destinations = try await InboxPlacementService.shared.destinations()
            isLoading = false
            if viewModel.overrideFocus == .research,
               let library = destinations.first(where: { $0.kind == .research }) {
                select(.filing(library))
            } else if let first = families.first?.choices.first {
                select(first)
            }
            searchFocused = true
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let selected, canCommit, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        switch selected {
        case .filing(let destination):
            if action == .research {
                await viewModel.fileAsResearch(item, destination: destination)
                dismiss()
            } else {
                error = await viewModel.fileCapture(item, destination: destination, action: action)
                if error == nil { dismiss() }
            }
        case .lane(let lane):
            await viewModel.moveToLane(item, lane: lane)
            dismiss()
        case .inquiry(let space):
            await viewModel.startInquiry(item, in: .existing(space))
            dismiss()
        case .newSpaceInquiry:
            await viewModel.startInquiry(item, in: .new(name: newSpaceName))
            dismiss()
        case .seedling(let seedling):
            await viewModel.growSeedling(item, seedling: seedling)
            dismiss()
        case .newSeedling:
            await viewModel.startSeedling(item, named: newConceptName)
            dismiss()
        }
    }
}

private struct InboxDestinationRow: View {
    let choice: InboxOverrideSheet.Choice
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: DS.space12) {
                Image(systemName: choice.symbol).frame(width: 24).foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(choice.name).font(DS.body.weight(.medium)).foregroundStyle(DS.text)
                    Text(choice.path).font(DS.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark").foregroundStyle(DS.accent).opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, DS.space12).padding(.vertical, DS.space12)
            .frame(minHeight: 52).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DS.accentSoft : isHovered ? DS.surface : Color.clear)
            .clipShape(.rect(cornerRadius: 12)).contentShape(.rect)
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
        .help("Choose \(choice.path)")
        .accessibilityElement(children: .combine).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
