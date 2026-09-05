import SwiftUI

extension Notification.Name {
    static let spaceStartInquiry = Notification.Name("com.cosmo.space.startInquiry")
}

@MainActor enum SpaceInquiryRequest {
    static var pending: [String: [String]] = [:]
    static func start(spaceID: String, sources: [String] = []) {
        pending[spaceID] = sources
        SpaceViewStore.shared.select(.deepDive, for: spaceID)
        NotificationCenter.default.post(name: .spaceStartInquiry, object: nil, userInfo: ["spaceID": spaceID])
    }
}

/// Questions are the durable work. Visits resume the same investigation.
struct SpaceInquiriesView: View {
    let spaceID: String
    @State private var sessions: [Atom] = []
    @State private var questions: [Atom] = []
    @State private var query = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var showingComposer = false
    @State private var question = ""
    @State private var sourceIDs: [String] = []
    @State private var starting = false
    @State private var showingArchived = false
    @State private var refresh = CoalescingRefresh()

    private var visible: [Atom] {
        sessions.filter {
            ($0.inquirySessionMetadata?.status == .archived) == showingArchived &&
            (query.isEmpty || ($0.title ?? "").localizedStandardContains(query))
        }
    }
    private var unstarted: [Atom] {
        let used = Set(sessions.compactMap { $0.inquirySessionMetadata?.mainQuestionUUID })
        return questions.filter { !used.contains($0.uuid) && $0.questionMetadata?.status != .archived &&
            (query.isEmpty || ($0.title ?? "").localizedStandardContains(query)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        Text("Inquiries").font(DS.pageTitle).foregroundStyle(DS.text)
                        Text("Questions you’re exploring. Pick up where you left off.")
                            .font(DS.body).foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    Menu {
                        Toggle("Archived inquiries", isOn: $showingArchived)
                    } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).help("Filter inquiries")
                }
                TextField("Find a question", text: $query)
                    .textFieldStyle(.plain).font(DS.body).padding(DS.space12)
                    .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
                if let error {
                    HStack { Text(error); Spacer(); Button("Retry") { Task { await load() } } }
                        .font(DS.callout).foregroundStyle(DS.textSecondary)
                }
                if !loaded && error == nil {
                    VStack(spacing: DS.space16) {
                        ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 12).fill(DS.glassSectionFill).frame(height: 72) }
                    }.accessibilityLabel("Loading inquiries")
                } else if visible.isEmpty && (unstarted.isEmpty || showingArchived) {
                    VStack(alignment: .leading, spacing: DS.space12) {
                        Text(query.isEmpty ? (showingArchived ? "No archived inquiries" : "Start with a question") : "No matching inquiries")
                            .font(DS.title2).foregroundStyle(DS.text)
                        Text(query.isEmpty ? "Choose something you want to understand. Bring sources, capture evidence, and develop your thinking here." : "Try another phrase or clear the filter.")
                            .font(DS.body).foregroundStyle(DS.textSecondary)
                        if !showingArchived && query.isEmpty {
                            Button("Start inquiry", systemImage: "plus") {
                                sourceIDs = []; question = ""; showingComposer = true
                            }
                                .buttonStyle(.plain).foregroundStyle(DS.accent).frame(minHeight: 44)
                        }
                    }.padding(DS.space24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
                } else {
                    VStack(spacing: 0) {
                        ForEach(visible, id: \.uuid) { session in
                            inquiryRow(session, isSession: true)
                            if session.uuid != visible.last?.uuid { Divider().padding(.horizontal, DS.space20) }
                        }
                    }.background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
                    if !unstarted.isEmpty && !showingArchived {
                        CosmoSectionHeader(label: "READY TO EXPLORE", detail: "\(unstarted.count)")
                        VStack(spacing: 0) {
                            ForEach(unstarted, id: \.uuid) { inquiryRow($0, isSession: false) }
                        }.background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
                    }
                }
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(.horizontal, DS.space32)
            .padding(.top, SpaceChromeMetrics.contentTopInset + DS.space24)
            .padding(.bottom, DS.space48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(DS.bg)
        .task(id: spaceID) { await load(); consumeRequest() }
        .onReceive(NotificationCenter.default.publisher(for: .spaceStartInquiry)) { notification in
            if notification.userInfo?["spaceID"] as? String == spaceID { consumeRequest() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.sessionEnded)) { _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.sessionCrystallized)) { _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)) { _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Entity.updated)) { _ in Task { await load() } }
        .sheet(isPresented: $showingComposer) { composer }
    }

    private func inquiryRow(_ atom: Atom, isSession: Bool) -> some View {
        Button { Task { await open(atom, isSession: isSession) } } label: {
            HStack(spacing: DS.space16) {
                Image(systemName: "questionmark.bubble").font(DS.title2).foregroundStyle(DS.textMuted)
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(atom.title ?? "Untitled question").font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                    Text(isSession ? sessionSummary(atom) : "Begin exploring this question")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(DS.textMuted)
            }.padding(DS.space20).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).contentShape(.rect)
        }
        .buttonStyle(.plain).help(isSession ? "Resume this inquiry" : "Start an inquiry with this question")
        .contextMenu {
            if isSession {
                Button(showingArchived ? "Restore inquiry" : "Archive inquiry") {
                    Task {
                        do {
                            guard var fresh = try await AtomRepository.shared.fetch(uuid: atom.uuid) else { return }
                            var meta = fresh.inquirySessionMetadata; meta?.status = showingArchived ? .paused : .archived
                            if let meta { _ = try await InquiryRepository.shared.saveSession(fresh, metadata: meta, structured: nil) }
                            await load()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
    private func sessionSummary(_ atom: Atom) -> String {
        let structured = (try? SpaceResearchSchema.object(atom.structured)) ?? [:]
        let count = SpaceResearchSchema.sourceIDs(structured).count
        return "\(count) \(count == 1 ? "source" : "sources") · \(atom.inquirySessionMetadata?.status == .crystallized ? "Findings saved" : "Continue exploring")"
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text("What do you want to understand?").font(DS.title2).foregroundStyle(DS.text)
            TextField("A question worth exploring", text: $question, axis: .vertical)
                .textFieldStyle(.plain).font(DS.body).lineLimit(2...5).padding(DS.space16)
                .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
            if !sourceIDs.isEmpty { Text("\(sourceIDs.count) selected materials will come with you.").font(DS.callout).foregroundStyle(DS.textSecondary) }
            if let error { Text(error).font(DS.callout).foregroundStyle(DS.textSecondary) }
            HStack {
                Button("Cancel") { showingComposer = false }.keyboardShortcut(.cancelAction).disabled(starting)
                Spacer()
                Button(starting ? "Opening…" : "Start inquiry") { Task { await start() } }
                    .keyboardShortcut(.defaultAction).disabled(starting || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(DS.space24).frame(width: 480).background(DS.bg).interactiveDismissDisabled(starting)
    }
    private func consumeRequest() {
        guard let sources = SpaceInquiryRequest.pending.removeValue(forKey: spaceID) else { return }
        sourceIDs = sources; question = ""; showingComposer = true
    }
    private func load() async { await refresh.run { await loadSnapshot() } }
    private func loadSnapshot() async {
        do {
            let profiles = try await InquiryRepository.shared.fetchDeepDives(in: spaceID)
            var allSessions: [Atom] = [], allQuestions: [Atom] = []
            for profile in profiles {
                allSessions += try await InquiryRepository.shared.fetchSessions(forDeepDive: profile.uuid)
                allQuestions += try await InquiryRepository.shared.fetchQuestions(forDeepDive: profile.uuid)
            }
            for session in allSessions where session.inquirySessionMetadata?.status == .crystallized {
                if let summary = session.body { try await SpaceResearchService.saveFindings(from: session, summary: summary) }
            }
            sessions = allSessions.sorted { $0.updatedAt > $1.updatedAt }; questions = allQuestions
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func open(_ atom: Atom, isSession: Bool) async {
        guard let parent = isSession ? atom.inquirySessionMetadata?.parentDeepDiveUUID : atom.questionMetadata?.parentDeepDiveUUID else { return }
        await InquirySessionLauncher.shared.launch(anchorUUID: parent, anchorType: "deep_dive", resumeSessionUUID: isSession ? atom.uuid : nil,
            mainQuestionTitle: atom.title, rootQuestionUUID: isSession ? atom.inquirySessionMetadata?.mainQuestionUUID : atom.uuid, appState: nil)
    }
    private func start() async {
        starting = true; defer { starting = false }
        do {
            let session = try await SpaceResearchService.start(spaceID: spaceID, question: question, sourceIDs: sourceIDs)
            showingComposer = false; await open(session, isSession: true); await load()
        } catch { self.error = error.localizedDescription }
    }
}
