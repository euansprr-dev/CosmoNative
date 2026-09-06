import SwiftUI

extension Atom {
    var spaceMapRecord: SpaceMapRecord {
        SpaceMapRecord(id: uuid, type: type.rawValue, title: title ?? "Untitled", metadata: metadata, structured: structured,
                       links: linksList.map { SpaceMapRelation(type: $0.type, targetID: $0.uuid) })
    }
}

@MainActor @Observable
final class SpaceResearchMapModel {
    var title = "Space"
    var profiles: [Atom] = []
    var atoms: [String: Atom] = [:]
    var memberIDs = Set<String>()
    var graph: SpaceMapGraph?
    var root: MindMapNode?
    var links: [MindMapConceptLink] = []
    var loaded = false
    var error: String?
    @ObservationIgnored private var loadToken = UUID()
    @ObservationIgnored private var buildToken = UUID()
    @ObservationIgnored private var loadingSpaceID: String?

    func load(spaceID: String) async {
        if loadingSpaceID != spaceID {
            loadingSpaceID = spaceID; buildToken = UUID()
            profiles = []; atoms = [:]; memberIDs = []; graph = nil; root = nil; links = []; loaded = false; error = nil
        }
        let token = UUID(); loadToken = token
        do {
            async let composition = SpaceCompositionService.load(in: spaceID)
            async let profileLoad = InquiryRepository.shared.fetchDeepDives(in: spaceID)
            guard let space = try await AtomRepository.shared.fetch(uuid: spaceID), !space.isDeleted else { throw SpaceCompositionError.notFound }
            let snapshot = try await composition, topics = try await profileLoad
            var records = Array(snapshot.atomsByUUID.values) + topics
            for topic in topics {
                try Task.checkCancellation()
                async let questions = InquiryRepository.shared.fetchQuestions(forDeepDive: topic.uuid)
                async let extracts = InquiryRepository.shared.fetchExtracts(forDeepDive: topic.uuid)
                async let sessions = InquiryRepository.shared.fetchSessions(forDeepDive: topic.uuid)
                records += try await questions + extracts + sessions
            }
            let referenced = SpaceMapGraphBuilder.referencedIDs(in: records.map(\.spaceMapRecord))
                .subtracting(records.map(\.uuid))
            let references = referenced.sorted()
            for start in stride(from: 0, to: references.count, by: 400) {
                try Task.checkCancellation()
                records += try await AtomRepository.shared.fetchBatch(uuids: Array(references[start..<min(start + 400, references.count)]))
            }
            guard !Task.isCancelled, loadToken == token else { return }
            title = space.title ?? "Space"; profiles = topics
            atoms = Dictionary(records.filter { !$0.isDeleted }.map { ($0.uuid, $0) }, uniquingKeysWith: { _, last in last })
            memberIDs = Set(snapshot.atomsByUUID.keys)
            loaded = true; error = nil
        } catch is CancellationError { }
        catch { if loadToken == token { self.error = error.localizedDescription } }
    }

    func rebuild(spaceID: String, topicID: String, showMaterials: Bool, query: String) async {
        guard loaded else { return }
        let token = UUID(); buildToken = token
        let records = atoms.values.map(\.spaceMapRecord), ids = memberIDs, title = self.title
        let graph = await Task.detached(priority: .userInitiated) {
            SpaceMapGraphBuilder.build(spaceID: spaceID, title: title, records: records, memberIDs: ids,
                topicID: topicID.isEmpty ? nil : topicID, showMaterials: showMaterials, query: query)
        }.value
        guard !Task.isCancelled, buildToken == token else { return }
        self.graph = graph
        root = Self.legacyNode(graph.root)
        links = graph.links.map { MindMapConceptLink(fromNodeId: $0.fromID, toNodeId: $0.toID) }
    }

    private static func legacyNode(_ node: SpaceMapNode, conceptDepth: Int = 0) -> MindMapNode {
        let kind: MindMapNode.Kind
        switch node.kind {
        case .root: kind = .root
        case .concept: kind = conceptDepth == 0 ? .coreConcept : .childConcept
        case .page: kind = .page
        case .question: kind = .question
        case .material: kind = .material
        case .group: kind = .questionGroup
        }
        return MindMapNode(id: node.id, kind: kind, title: node.title, subtitle: node.subtitle,
            isActive: node.isMatch, isSection: node.isSection, atomUUID: node.atomID,
            children: node.children.map { legacyNode($0, conceptDepth: conceptDepth + (node.kind == .concept ? 1 : 0)) })
    }
}

/// The same mature inquiry renderer, supplied with a read-only Space graph.
struct SpaceResearchMapView: View {
    let spaceID: String
    @State private var model = SpaceResearchMapModel()
    @State private var query = ""
    @State private var refresh = CoalescingRefresh()
    @State private var revision = 0
    private var preferences: SpaceMapPreferences { .shared }
    private var topicID: String { preferences.topic(in: spaceID) }
    private var showMaterials: Bool { preferences.showsMaterials(in: spaceID) }

    var body: some View {
        VStack(spacing: 0) {
            controls
            mapSurface
            legend
        }
        .task(id: spaceID) { await reload() }
        .task(id: BuildKey(topic: topicID, materials: showMaterials, query: query, revision: revision)) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(160)) }
            guard !Task.isCancelled else { return }
            await model.rebuild(spaceID: spaceID, topicID: topicID, showMaterials: showMaterials, query: query)
        }
        .onReceive(NotificationCenter.default.publisher(for: SpaceCompositionService.didChange)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Entity.updated)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Entity.created)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .atomsDidChange)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.canvasBlocksChanged"))) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)) { _ in Task { await reload() } }
    }

    private struct BuildKey: Hashable { var topic: String; var materials: Bool; var query: String; var revision: Int }

    private var controls: some View {
        HStack(spacing: DS.space16) {
            Picker("Map scope", selection: Binding(get: { topicID }, set: { preferences.selectTopic($0, in: spaceID) })) {
                Text("Whole Space").tag("")
                ForEach(model.profiles, id: \.uuid) { Text($0.title ?? "Research topic").tag($0.uuid) }
            }.pickerStyle(.menu).frame(maxWidth: 240).help("Show the whole Space or one research topic")
            HStack(spacing: DS.space8) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.textMuted).accessibilityHidden(true)
                TextField("Find in map", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.textMuted) }
                        .buttonStyle(.plain).help("Clear map search").accessibilityLabel("Clear map search")
                }
            }.font(DS.callout).padding(DS.space8).background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
            Toggle("Materials & work", isOn: Binding(get: { showMaterials }, set: { preferences.showMaterials($0, in: spaceID) }))
                .toggleStyle(.checkbox).font(DS.callout).help("Include sources and work connected to this Space")
        }.padding(.horizontal, DS.space32).padding(.vertical, DS.space12)
    }

    @ViewBuilder private var mapSurface: some View {
        if let error = model.error {
            VStack(spacing: DS.space12) {
                Text(error).font(DS.callout).foregroundStyle(DS.textSecondary)
                Button("Retry") { Task { await reload() } }.help("Reload the Space map")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let root = model.root {
            if root.children.isEmpty {
                VStack(spacing: DS.space12) {
                    Image(systemName: "circle.hexagongrid").font(DS.pageTitle).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                    Text(query.isEmpty ? "Give your thinking a shape" : "No matching items").font(DS.title2).foregroundStyle(DS.text)
                    Text(query.isEmpty ? "Add a Concept or Page to this Space. Saved relationships will connect them here." : "Try another phrase, or clear the search to see the whole map.")
                        .font(DS.body).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InquiryMindMapView(root: root, conceptLinks: model.links) { node in
                    Task { await open(node) }
                }.id(spaceID + ":" + topicID).filmGrain()
            }
        } else {
            HStack(spacing: DS.space48) {
                RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.glassSectionFill).frame(width: 230, height: 72)
                VStack(spacing: DS.space24) {
                    ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.glassSectionFill).frame(width: 220, height: 64) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel("Loading Space map")
        }
    }

    private var legend: some View {
        HStack(spacing: DS.space16) {
            Text("Branches show hierarchy · Dashed lines show references")
            Spacer()
            if let graph = model.graph {
                if !query.isEmpty { Text("\(graph.matchCount) matches").monospacedDigit() }
                if graph.omittedCount > 0 { Text("\(graph.omittedCount) more items · narrow the scope or search").monospacedDigit() }
                if graph.omittedLinkCount > 0 { Text("\(graph.omittedLinkCount) more references").monospacedDigit() }
            }
        }.font(DS.caption).foregroundStyle(DS.textMuted).padding(.horizontal, DS.space32).padding(.vertical, DS.space12)
    }

    private func reload() async {
        await refresh.run {
            await model.load(spaceID: spaceID)
            if !topicID.isEmpty && !model.profiles.contains(where: { $0.uuid == topicID }) { preferences.selectTopic("", in: spaceID) }
            revision += 1
        }
    }

    private func open(_ node: MindMapNode) async {
        guard let id = node.atomUUID, let atom = model.atoms[id] else { return }
        if atom.type == .question, let parent = atom.questionMetadata?.parentDeepDiveUUID {
            await InquirySessionLauncher.shared.launch(anchorUUID: parent, anchorType: "deep_dive", resumeSessionUUID: nil,
                mainQuestionTitle: atom.title, rootQuestionUUID: atom.uuid, appState: nil)
        } else if atom.spaceCompositionKind != nil {
            do { try await SpaceWorkspaceStore.shared.openOriginal(atom, from: spaceID) }
            catch { model.error = error.localizedDescription }
        } else {
            NotificationCenter.default.post(name: CosmoNotification.Navigation.openBlockInFocusMode, object: nil, userInfo: ["atomUUID": atom.uuid])
        }
    }
}
