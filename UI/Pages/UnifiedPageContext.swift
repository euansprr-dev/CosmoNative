import SwiftUI
import Observation

/// The Page host owns the editor and persistence. This panel only reads context;
/// every tag change goes through the binding supplied by the shared session.
struct UnifiedPageContextPanel: View {
    let atom: Atom
    let document: RichDocument
    @Binding var tags: [String]
    var showsOutline = true
    var showsDetails = true
    var onNavigateBlock: (UUID) -> Void
    var onOpenAtom: (String) -> Void
    @State private var context = UnifiedPageContextModel()
    @State private var editingTags = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                header
                if showsOutline { UnifiedPageOutlineSection(document: document, onNavigate: onNavigateBlock) }
                if showsDetails {
                    tagSection
                    attachmentSection
                    relatedSections
                }
            }.padding(DS.space20)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        // The companion sits over this panel's tail — content ends above it.
        .contentMargins(.bottom, CompanionDockMetrics.shared.bottomClearance, for: .scrollContent)
        .background(DS.commandCenterRailStabilizingFill, in: .rect(cornerRadius: 22))
        .cosmoGlassPanel(role: .focusSidebar, cornerRadius: 22)
        .sheet(isPresented: $editingTags) { TagEditorSheet(tags: $tags) }
        .task(id: atom.uuid) { await context.load(atom) }
        .accessibilityLabel("Page context")
    }

    private var header: some View {
        HStack {
            Text(showsDetails ? "Context" : "Outline").font(DS.headline).foregroundStyle(DS.text)
            Spacer()
            Button { Task { await context.load(atom) } } label: {
                Image(systemName: "arrow.clockwise").font(DS.caption).frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(DS.textSecondary)
                .marginaliaLinkHover().help("Refresh page context")
                .accessibilityLabel("Refresh page context").disabled(context.loading)
        }
    }

    private var tagSection: some View {
        MarginaliaDisclosureSection("Tags", countText: "\(tags.count)", storageKey: "page.tags", defaultExpanded: true) {
            VStack(alignment: .leading, spacing: DS.space8) {
                if tags.isEmpty { UnifiedPageContextHint(text: "Add tags to find this Page by topic.") }
                else {
                    Text(tags.joined(separator: " · "))
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Button(tags.isEmpty ? "Add tags" : "Edit tags", systemImage: "tag") { editingTags = true }
                    .font(DS.subheadline).buttonStyle(.plain).foregroundStyle(DS.textSecondary)
                    .frame(minHeight: 44).marginaliaLinkHover().help("Edit this Page’s tags")
            }
        }
    }

    private var attachmentSection: some View {
        MarginaliaDisclosureSection("Attachments", countText: "\(atom.attachmentUUIDs.count)", storageKey: "page.attachments", defaultExpanded: true) {
            if atom.attachmentUUIDs.isEmpty { UnifiedPageContextHint(text: "Captured originals attached to this Page appear here.") }
            else { AttachmentRail(attachmentUUIDs: atom.attachmentUUIDs) }
        }
    }

    @ViewBuilder private var relatedSections: some View {
        if let error = context.error {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(error).font(DS.caption).foregroundStyle(DS.textSecondary)
                Button("Try again") { Task { await context.load(atom) } }
                    .buttonStyle(.plain).font(DS.subheadline).frame(minHeight: 44)
                    .marginaliaLinkHover().help("Reload links to this Page")
            }
        } else if context.loading && !context.loaded {
            VStack(alignment: .leading, spacing: DS.space12) {
                ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 4).fill(DS.glassSectionFill).frame(height: 32) }
            }.accessibilityLabel("Loading page links")
        }
        UnifiedPageRelatedSection(title: "Backlinks", items: context.backlinks,
            emptyText: "Pages and sources that link here appear in this list.", onOpen: onOpenAtom)
        UnifiedPageRelatedSection(title: "Linked materials", items: context.materials,
            emptyText: "Linked sources and material saved around this Page remain available here.", onOpen: onOpenAtom)
    }
}

private struct UnifiedPageOutlineSection: View {
    let document: RichDocument
    var onNavigate: (UUID) -> Void
    private var headings: [RichHeadingOutlineEntry] { RichDocumentHeadings.outline(in: document) }
    var body: some View {
        let entries = headings
        MarginaliaDisclosureSection("On this page", countText: "\(entries.count)", storageKey: "page.outline", defaultExpanded: true) {
            if entries.isEmpty { UnifiedPageContextHint(text: "Add headings to navigate longer Pages.") }
            else {
                LazyVStack(alignment: .leading, spacing: DS.space4) {
                    ForEach(entries) { entry in
                        Button { onNavigate(entry.id) } label: {
                            Text(entry.title).font(entry.level == 1 ? DS.subheadline : DS.caption)
                                .foregroundStyle(entry.level == 1 ? DS.textSecondary : DS.textMuted)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(max(0, entry.level - 1)) * DS.space8)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }.buttonStyle(.plain).marginaliaLinkHover().help("Go to \(entry.title)")
                    }
                }
            }
        }
    }
}

private struct UnifiedPageContextHint: View {
    let text: String
    var body: some View {
        Text(text).font(DS.caption).foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UnifiedPageRelatedSection: View {
    let title: String
    let items: [UnifiedPageRelatedItem]
    let emptyText: String
    var onOpen: (String) -> Void
    var body: some View {
        MarginaliaDisclosureSection(title, countText: "\(items.count)", storageKey: "page." + title, defaultExpanded: true) {
            if items.isEmpty { UnifiedPageContextHint(text: emptyText) }
            else {
                LazyVStack(spacing: DS.space4) {
                    ForEach(items) { item in
                        Button { onOpen(item.id) } label: {
                            HStack(alignment: .top, spacing: DS.space8) {
                                Image(cosmo: item.type.cosmoIcon).font(DS.caption).foregroundStyle(DS.textMuted).frame(width: 20)
                                VStack(alignment: .leading, spacing: DS.space4) {
                                    Text(item.title).font(DS.subheadline).foregroundStyle(DS.textSecondary).lineLimit(2)
                                    if !item.excerpt.isEmpty { Text(item.excerpt).font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(3) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.plain).marginaliaLinkHover().help("Open \(item.title)")
                            .accessibilityLabel("Open \(item.title)")
                    }
                }
            }
        }
    }
}

private struct UnifiedPageRelatedItem: Identifiable {
    let id: String
    let title: String
    let type: AtomType
    let excerpt: String
    init(_ atom: Atom) {
        id = atom.uuid; title = atom.title ?? "Untitled"; type = atom.type
        excerpt = String((atom.body ?? "").prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }
    init(_ saved: FocusFloatingBlock) {
        id = saved.linkedAtomUUID; title = saved.title; type = saved.atomType ?? .note
        excerpt = "Saved material — original unavailable"
    }
}

@Observable @MainActor
private final class UnifiedPageContextModel {
    private(set) var backlinks: [UnifiedPageRelatedItem] = []
    private(set) var materials: [UnifiedPageRelatedItem] = []
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var error: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var owner: String?

    func load(_ atom: Atom) async {
        generation += 1
        let version = generation
        if owner != atom.uuid { backlinks = []; materials = []; loaded = false; owner = atom.uuid }
        loading = true
        defer { if version == generation { loading = false } }
        do {
            async let edgeRead = GraphQueryEngine().getEdges(for: atom.uuid)
            async let outlineRead = AtomRepository.shared.fetchOutlineBacklinks(to: atom.uuid)
            let edges = try await edgeRead, outline = try await outlineRead
            let incoming = Set(edges.filter { $0.targetUUID == atom.uuid }.map(\.sourceUUID)).union(outline.map(\.uuid)).subtracting([atom.uuid])
            let floating = atom.focusFloatingBlocks
            let outgoing = Set(edges.filter { $0.sourceUUID == atom.uuid }.map(\.targetUUID)).union(floating.map(\.linkedAtomUUID)).subtracting([atom.uuid])
            let ids = incoming.union(outgoing).sorted()
            var fetched: [Atom] = []
            for start in stride(from: 0, to: ids.count, by: 400) {
                fetched += try await AtomRepository.shared.fetchBatch(uuids: Array(ids[start..<min(start + 400, ids.count)]))
            }
            try Task.checkCancellation()
            guard version == generation else { return }
            let live = fetched.filter { !$0.isDeleted }
            let byID = Dictionary(live.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            backlinks = incoming.sorted().compactMap { byID[$0] }.map(UnifiedPageRelatedItem.init)
            var result = outgoing.sorted().compactMap { byID[$0] }.map(UnifiedPageRelatedItem.init)
            var seen = Set(result.map(\.id))
            result += floating.filter { seen.insert($0.linkedAtomUUID).inserted }.map(UnifiedPageRelatedItem.init)
            materials = result; error = nil; loaded = true
        } catch is CancellationError { }
        catch { if version == generation { self.error = "Page links could not load. " + error.localizedDescription } }
    }
}
