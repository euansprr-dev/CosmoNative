// CosmoOS/UI/FocusMode/DeepDive/DeepDiveOverviewView.swift
// Deep Dive Overview — the home page for a topic mastery environment.
// Three-tab layout (Overview / Research / Map) per plan §19.
// Sanctuary feel: serif title, generous spacing, progressive disclosure by maturity.

import SwiftUI

@MainActor
struct DeepDiveOverviewView: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var viewModel: DeepDiveOverviewViewModel
    @State private var selectedTab: DeepDiveOverviewTab = .overview
    @State private var showingRootQuestionComposer = false
    @State private var rootQuestionDraft = ""
    @State private var showArchivedSessions = false
    @State private var renamingSessionUUID: String?
    @State private var sessionRenameDraft = ""
    @State private var deletingSessionUUID: String?
    @State private var lexiconPopoverUUID: String?
    @AppStorage("deepDiveMapShowsQuestions") private var mapShowsQuestions = true
    @State private var hasAppeared = false
    @State private var mastheadVisible = true
    @State private var scrollHomeTick = 0
    @State private var questionsExpanded = false
    @State private var inboxExpanded = false

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = State(initialValue: DeepDiveOverviewViewModel(atom: atom))
    }

    var body: some View {
        ZStack {
            DS.bg
                .ignoresSafeArea()
            tabContent
        }
        .overlay(alignment: .top) { studyBar }
        .overlay(alignment: .bottomTrailing) {
            // The thinkspace's mode switcher lives here too — Canvas, Library,
            // and Deep Dive stay siblings of one place.
            StudyThinkspaceModeSwitcher(
                thinkspaceUUID: viewModel.atom.deepDiveMetadata?.primaryThinkspaceUUID
                    ?? viewModel.atom.deepDiveMetadata?.parentThinkspaceUUIDs?.first
            )
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .task {
            await viewModel.load()
            // One-frame rule: flip the cascade flag after data lands so the
            // dossier assembles on arrival instead of mounting pre-visible.
            try? await Task.sleep(for: .milliseconds(16))
            hasAppeared = true
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.sessionEnded)) { _ in
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.sessionCrystallized)) { _ in
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $showingRootQuestionComposer) {
            RootQuestionComposerSheet(
                deepDive: atom,
                questions: viewModel.questions,
                draft: $rootQuestionDraft,
                onStart: { question in
                    showingRootQuestionComposer = false
                    launchInquiry(mainQuestionTitle: question)
                },
                onStartWithoutQuestion: {
                    showingRootQuestionComposer = false
                    launchInquiry(mainQuestionTitle: nil)
                },
                onContinueQuestion: { question in
                    showingRootQuestionComposer = false
                    launchInquiry(mainQuestionTitle: question.title, rootQuestionUUID: question.uuid)
                }
            )
        }
        .sheet(isPresented: sessionRenameSheetBinding) {
            if let sessionUUID = renamingSessionUUID {
                sessionRenameSheet(sessionUUID)
            }
        }
        .confirmationDialog("Delete session?", isPresented: deleteSessionDialogBinding, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                Task { await viewModel.deleteSession(deletingSessionUUID ?? "") }
                deletingSessionUUID = nil
            }
            Button("Cancel", role: .cancel) {
                deletingSessionUUID = nil
            }
        } message: {
            Text("The session atom will move to Recently Deleted. Questions and extracts remain as atoms.")
        }
    }

    // MARK: - Study Bar (the one piece of chrome)

    private var studyBar: some View {
        DeepDiveStudyBar(
            title: viewModel.atom.title ?? "Deep Dive",
            maturityLabel: (viewModel.atom.deepDiveMetadata?.maturity ?? .spark).displayName,
            selectedTab: $selectedTab,
            showsTitle: selectedTab != .overview || !mastheadVisible,
            recede: selectedTab == .overview && !mastheadVisible,
            mapShowsQuestions: $mapShowsQuestions,
            onTitleTap: { scrollHomeTick += 1 },
            onStartInquiry: { startInquiry() }
        )
        .background {
            // Esc retraces the trail (routed through onClose → trailStepBack).
            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .sessions: sessionsTab
        case .map: mapTab
        }
    }

    // MARK: - Overview: the Dossier

    private var overviewTab: some View {
        GeometryReader { proxy in
            // Wide = room for ghost flank + column + rail (280+680+280 + gaps),
            // so the reading column can center on the TRUE page axis.
            let isWide = proxy.size.width >= 1280
            ScrollViewReader { scrollProxy in
                ScrollView {
                    dossierLayout(isWide: isWide)
                        .padding(.horizontal, DS.space40)
                        .padding(.top, 76)   // Breathing room under the floating bar
                        .padding(.bottom, DS.space40)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y < 96
                } action: { _, isAtTop in
                    mastheadVisible = isAtTop
                }
                .onChange(of: scrollHomeTick) {
                    withAnimation(ProMotionSprings.gentle) {
                        scrollProxy.scrollTo("dossier-top", anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dossierLayout(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: DS.space32) {
                // Ghost flank mirrors the rail's width so the reading column
                // sits on the page's true center axis, like the other tabs.
                Color.clear
                    .frame(width: 280, height: 1)
                    .accessibilityHidden(true)
                readingColumn
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity, alignment: .center)
                knowledgeRail
                    .frame(width: 280)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.space24) {
                readingColumn
                knowledgeRail
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// The working column: hero masthead, the understanding you're building,
    /// the one call to action, then the questions driving the work.
    private var readingColumn: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            titleBlock
                .id("dossier-top")
            currentUnderstandingBlock
                .studyCascade(hasAppeared, index: 1)
            continueStrip
                .studyCascade(hasAppeared, index: 2)
            questionsSection
                .studyCascade(hasAppeared, index: 3)
            if shouldShowTopicInbox {
                inboxSection
                    .studyCascade(hasAppeared, index: 4)
            }
        }
    }

    /// The knowledge shelf: what this study has crystallized so far.
    private var knowledgeRail: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            conceptsSection
                .studyCascade(hasAppeared, index: 2)
            if shouldShowLexicon {
                lexiconSection
                    .studyCascade(hasAppeared, index: 3)
            }
            if shouldShowSources {
                sourcesSection
                    .studyCascade(hasAppeared, index: 4)
            }
            if shouldShowOutputs {
                outputsSection
                    .studyCascade(hasAppeared, index: 5)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(viewModel.atom.title ?? "Untitled Deep Dive")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Text(metadataRowText)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
            // Only a short, human-written "about" line earns hero space —
            // long bodies were legacy session appends, now migrated into history.
            if let about = viewModel.atom.body?.trimmingCharacters(in: .whitespacesAndNewlines),
               !about.isEmpty, about.count < 280 {
                Text(about)
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .padding(.top, DS.space4)
            }
        }
    }

    private var metadataRowText: String {
        var parts: [String] = []
        let maturity = viewModel.atom.deepDiveMetadata?.maturity ?? .spark
        parts.append(maturity.displayName)
        if let updatedString = viewModel.atom.deepDiveMetadata?.lastInquiryAt ?? Optional(viewModel.atom.updatedAt),
           let date = ISO8601.date(from: updatedString) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append("Updated \(formatter.localizedString(for: date, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    /// The editorial heart of the dossier: the understanding you're building,
    /// read as a manuscript. Edit reveals on hover; history stays quiet below.
    private var currentUnderstandingBlock: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack {
                StudySectionHeader(
                    label: "UNDERSTANDING",
                    count: viewModel.understandingRevisions.count + viewModel.understanding.recentUpdates.count
                )
                Button {
                    viewModel.isEditingUnderstanding.toggle()
                } label: {
                    Text(viewModel.isEditingUnderstanding ? "Done" : "Edit")
                        .font(CosmoTypography.label)
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("u", modifiers: [.command])
                .help("Edit understanding (⌘U)")
            }

            if viewModel.isEditingUnderstanding {
                CurrentUnderstandingEditorView(viewModel: viewModel)
            } else {
                CurrentUnderstandingDisplayView(understanding: viewModel.understanding)
            }

            if !viewModel.understandingRevisions.isEmpty || !viewModel.understanding.recentUpdates.isEmpty {
                UnderstandingHistoryList(
                    revisions: viewModel.understandingRevisions,
                    updates: viewModel.understanding.recentUpdates.reversed()
                )
            }
        }
    }

    /// The one call to action on the page: pick the thread back up.
    private var continueStrip: some View {
        Button {
            if let question = viewModel.currentQuestionTitle {
                launchInquiry(mainQuestionTitle: question)
            } else {
                startInquiry()
            }
        } label: {
            HStack(spacing: DS.space12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let question = viewModel.currentQuestionTitle {
                        Text(question)
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(CosmoColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("Pick the thread back up")
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                    } else {
                        Text("Ask your first question to open the study.")
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(CosmoColors.textSecondary)
                    }
                }
                Spacer(minLength: DS.space12)
                HStack(spacing: DS.space4) {
                    Text(viewModel.currentQuestionTitle == nil ? "Start inquiry" : "Continue inquiry")
                        .font(CosmoTypography.label)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
            .background(DS.accentSoft.opacity(0.55), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DS.accent.opacity(0.22), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help("Resume the inquiry on this question")
        .accessibilityLabel(viewModel.currentQuestionTitle.map { "Continue inquiry: \($0)" } ?? "Start your first inquiry")
    }

    private var inboxSection: some View {
        StudySection(label: "INBOX", count: viewModel.topicInboxItems.count) {
            let visible = inboxExpanded ? viewModel.topicInboxItems : Array(viewModel.topicInboxItems.prefix(4))
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                if index > 0 { StudyPaneDivider() }
                topicInboxRow(item)
            }
            if viewModel.topicInboxItems.count > 4 {
                StudyPaneDivider()
                StudyOverflowRow(
                    hiddenCount: viewModel.topicInboxItems.count - 4,
                    isExpanded: $inboxExpanded
                )
            }
        }
    }

    private func topicInboxRow(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Circle()
                .fill(DS.accent.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(item.rawText.prefix(120)))
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(2)
                if let suggested = item.primaryRecommendationValue?.suggestedAtomType {
                    Text(suggested.capitalized)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var questionsSection: some View {
        let deduped = viewModel.dedupedQuestions
        let visible = questionsExpanded ? deduped : Array(deduped.prefix(6))
        return StudySection(label: "QUESTIONS", count: deduped.count) {
            if deduped.isEmpty {
                StudyTeachingRow(text: "Start an inquiry to spark your first question.")
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.uuid) { index, q in
                    if index > 0 { StudyPaneDivider() }
                    questionRow(q)
                }
                if deduped.count > 6 {
                    StudyPaneDivider()
                    StudyOverflowRow(hiddenCount: deduped.count - 6, isExpanded: $questionsExpanded)
                }
            }
        }
    }

    private func questionRow(_ q: Atom) -> some View {
        let status = q.questionMetadata?.status ?? .open
        let counts = viewModel.questionCounts(q)
        return StudyPaneRow(
            leading: {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            },
            title: q.title ?? "Untitled question",
            trailing: {
                if counts.extracts > 0 {
                    Text("\(counts.extracts) notes")
                        .font(CosmoTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(CosmoColors.textTertiary)
                }
                Text(status.displayName.lowercased())
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            },
            action: { launchInquiry(mainQuestionTitle: q.title, rootQuestionUUID: q.uuid) }
        )
        .accessibilityLabel("Open inquiry for \(q.title ?? "question")")
    }

    private var sourcesSection: some View {
        StudySection(label: "SOURCES", count: viewModel.sources.count) {
            ForEach(Array(viewModel.sources.prefix(6).enumerated()), id: \.element.uuid) { index, source in
                if index > 0 { StudyPaneDivider() }
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: Atom) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title ?? "Untitled source")
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
                if let host = source.researchMetadata?.url.flatMap({ URL(string: $0)?.host }) {
                    Text(host)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var lexiconSection: some View {
        StudySection(label: "LEXICON", count: viewModel.lexicon.count) {
            FlowLayout(spacing: DS.space8) {
                ForEach(viewModel.conceptEntries, id: \.lexicon.uuid) { entry in
                    lexiconChip(entry.lexicon, connection: entry.connection)
                }
            }
            .padding(DS.space12)
        }
    }

    private func lexiconChip(_ entry: Atom, connection: Atom?) -> some View {
        Button {
            if let connection {
                openConceptPage(connection)
            } else {
                lexiconPopoverUUID = entry.uuid
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(entry.title ?? "·")
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
                if connection != nil {
                    Image(systemName: "arrow.up.right")
                        .font(CosmoTypography.labelSmall)
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 4)
            .background(connection != nil ? DS.accentSoft : DS.surface, in: Capsule())
            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: connection == nil ? 1 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(connection != nil ? "Open concept page \(entry.title ?? "")" : "Show definition of \(entry.title ?? "")")
        .popover(isPresented: lexiconPopoverBinding(entry.uuid)) {
            lexiconDefinitionPopover(entry)
        }
    }

    private func lexiconDefinitionPopover(_ entry: Atom) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(entry.title ?? "Term")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text((entry.body?.isEmpty == false ? entry.body! : "No definition captured yet."))
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .padding(DS.space16)
        .frame(width: 320, alignment: .leading)
    }

    private func lexiconPopoverBinding(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: { lexiconPopoverUUID == uuid },
            set: { if !$0 { lexiconPopoverUUID = nil } }
        )
    }

    private func openConceptPage(_ connection: Atom) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": connection.uuid]
        )
    }

    private var conceptsSection: some View {
        StudySection(label: "CONCEPTS", count: viewModel.connections.count) {
            if viewModel.connections.isEmpty {
                StudyTeachingRow(text: "Crystallize a session to grow concepts.")
            } else {
                ForEach(Array(viewModel.connections.prefix(8).enumerated()), id: \.element.uuid) { index, connection in
                    if index > 0 { StudyPaneDivider() }
                    conceptRow(connection)
                }
            }
        }
    }

    private func conceptRow(_ connection: Atom) -> some View {
        let notes = viewModel.extracts.filter { $0.extractMetadata?.promotedToUUID == connection.uuid }.count
        return StudyPaneRow(
            leading: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CosmoMentionColors.connection)
                    .accessibilityHidden(true)
            },
            title: connection.title ?? "Untitled concept",
            subtitle: notes > 0 ? "\(notes) notes" : nil,
            trailing: { EmptyView() },
            action: { openConceptPage(connection) }
        )
        .accessibilityLabel("Open concept page \(connection.title ?? "")")
    }

    private var outputsSection: some View {
        StudySection(label: "OUTPUTS", count: viewModel.outputAngles.count) {
            ForEach(Array(viewModel.outputAngles.enumerated()), id: \.element.id) { index, angle in
                if index > 0 { StudyPaneDivider() }
                HStack(spacing: DS.space8) {
                    Text(angle.title)
                        .font(CosmoTypography.bodySmall)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: DS.space8)
                    if let format = angle.format {
                        Text(format)
                            .font(CosmoTypography.labelSmall)
                            .foregroundStyle(CosmoColors.textTertiary)
                            .padding(.horizontal, DS.space6)
                            .padding(.vertical, 2)
                            .background(DS.surface, in: Capsule())
                    }
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
            }
        }
    }

    // MARK: - Sessions Tab

    private var sessionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack(spacing: DS.space8) {
                    StudySectionHeader(label: "SESSIONS", count: visibleSessions.count)
                    Toggle("Show archived", isOn: $showArchivedSessions)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                        .toggleStyle(.checkbox)
                }
                StudyPane {
                    if visibleSessions.isEmpty {
                        StudyTeachingRow(text: "Start an inquiry to begin your first session.")
                    } else {
                        ForEach(Array(visibleSessions.enumerated()), id: \.element.uuid) { index, session in
                            if index > 0 { StudyPaneDivider() }
                            sessionRow(session)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.space40)
            .padding(.top, 76)
            .padding(.bottom, DS.space40)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func sessionRow(_ session: Atom) -> some View {
        let meta = session.inquirySessionMetadata
        let status = meta?.status ?? .paused
        let updated = ISO8601.date(from: meta?.lastActiveAt ?? session.updatedAt)
            .map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) }
        return StudyPaneRow(
            leading: {
                Circle()
                    .fill(sessionStatusColor(status))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            },
            title: session.title ?? "Untitled session",
            subtitle: updated,
            trailing: {
                Text(status.rawValue)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(sessionStatusColor(status))
            },
            action: { resumeSession(session) }
        )
        .contextMenu { sessionContextMenu(session) }
        .accessibilityLabel("Resume session \(session.title ?? "")")
    }

    // MARK: - Map Tab

    @ViewBuilder
    private var mapTab: some View {
        let graph = MindMapBuilder.buildDeepDive(
            deepDive: viewModel.atom,
            questions: viewModel.questions,
            connections: viewModel.connections,
            extracts: viewModel.extracts,
            includeQuestions: mapShowsQuestions
        )
        if graph.root.children.isEmpty {
            mapEmptyState
        } else {
            InquiryMindMapView(
                root: graph.root,
                conceptLinks: graph.conceptLinks,
                reparentTargets: mapReparentTargets,
                onReparent: { child, parent in
                    Task { await reparentConnection(child, under: parent) }
                }
            ) { node in
                handleMapSelection(node)
            }
            .filmGrain()
        }
    }

    private var mapReparentTargets: [(uuid: String, title: String)] {
        viewModel.connections.compactMap { connection in
            guard let title = connection.title, !title.isEmpty else { return nil }
            return (connection.uuid, title)
        }
    }

    /// User-pinned reparent: writes the hierarchy metadata (pinned, so
    /// crystallization never overrides it) and reloads the map.
    private func reparentConnection(_ childUUID: String, under parentUUID: String?) async {
        guard var atom = try? await AtomRepository.shared.fetch(uuid: childUUID) else { return }
        atom = atom.mergingMetadataKeys(ConnectionHierarchyMetadata(
            parentConnectionUUID: parentUUID,
            parentPinnedByUser: true
        ))
        _ = try? await AtomRepository.shared.update(atom)
        await viewModel.load()
    }

    private var mapEmptyState: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 36))
                .foregroundStyle(DS.accent.opacity(0.5))
                .accessibilityHidden(true)
            Text("The map grows as knowledge crystallizes")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Crystallized concepts become branches; questions hang beneath the concept they explore.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleMapSelection(_ node: MindMapNode) {
        switch node.kind {
        case .question, .subQuestion:
            guard let uuid = node.atomUUID,
                  let question = viewModel.questions.first(where: { $0.uuid == uuid }) else { return }
            launchInquiry(mainQuestionTitle: question.title, rootQuestionUUID: question.uuid)
        case .coreConcept, .childConcept:
            guard let uuid = node.atomUUID,
                  let connection = viewModel.connections.first(where: { $0.uuid == uuid }) else { return }
            openConceptPage(connection)
        case .root, .questionGroup:
            break
        }
    }

    // MARK: - Helpers

    private var shouldShowQuestion: Bool { viewModel.currentQuestionTitle != nil }
    private var shouldShowTopicInbox: Bool { !viewModel.topicInboxItems.isEmpty }
    private var shouldShowQuestions: Bool {
        let m = atom.deepDiveMetadata?.maturity ?? .spark
        return m != .spark || !viewModel.questions.isEmpty
    }
    private var shouldShowSources: Bool { !viewModel.sources.isEmpty }
    private var shouldShowLexicon: Bool { !viewModel.lexicon.isEmpty }
    private var shouldShowConnections: Bool { !viewModel.connections.isEmpty }
    private var shouldShowOutputs: Bool { !viewModel.outputAngles.isEmpty }
    private var shouldShowSessions: Bool { !viewModel.sessions.isEmpty }
    private var visibleSessions: [Atom] {
        viewModel.sessions.filter { session in
            showArchivedSessions || session.inquirySessionMetadata?.status != .archived
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .tracking(2)
            .foregroundStyle(CosmoColors.textSecondary.opacity(0.78))
    }

    @ViewBuilder
    private func sectionContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionLabel(title)
            content()
        }
    }

    private func statusColor(_ status: QuestionStatus) -> Color {
        switch status {
        case .open: return CosmoColors.textTertiary
        case .researching: return DS.accent
        case .partiallyAnswered: return DS.orange
        case .answered: return DS.green
        case .promoted: return CosmoMentionColors.color(for: .deepDive)
        case .archived: return CosmoColors.textTertiary.opacity(0.6)
        }
    }

    private func sessionStatusColor(_ status: InquirySessionStatus) -> Color {
        switch status {
        case .active: return DS.accent
        case .paused: return DS.orange
        case .crystallized: return DS.green
        case .archived: return CosmoColors.textTertiary
        }
    }

    private func startInquiry() {
        rootQuestionDraft = ""
        showingRootQuestionComposer = true
    }

    private func launchInquiry(mainQuestionTitle: String?, rootQuestionUUID: String? = nil) {
        var userInfo: [String: Any] = [
            "anchorUUID": atom.uuid,
            "anchorType": AtomType.deepDive.rawValue
        ]
        if let mainQuestionTitle, !mainQuestionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userInfo["mainQuestionTitle"] = mainQuestionTitle
        }
        if let rootQuestionUUID {
            userInfo["rootQuestionUUID"] = rootQuestionUUID
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            userInfo: userInfo
        )
    }

    private func resumeSession(_ session: Atom) {
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            userInfo: [
                "anchorUUID": atom.uuid,
                "anchorType": AtomType.deepDive.rawValue,
                "resumeSessionUUID": session.uuid
            ]
        )
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Atom) -> some View {
        Button("Resume") { resumeSession(session) }
        Button("Rename") {
            renamingSessionUUID = session.uuid
            sessionRenameDraft = session.title ?? "Untitled session"
        }
        Button("Archive") {
            Task { await viewModel.archiveSession(session.uuid) }
        }
        Button("Delete", role: .destructive) {
            deletingSessionUUID = session.uuid
        }
    }

    private var sessionRenameSheetBinding: Binding<Bool> {
        Binding(
            get: { renamingSessionUUID != nil },
            set: { if !$0 { renamingSessionUUID = nil } }
        )
    }

    private var deleteSessionDialogBinding: Binding<Bool> {
        Binding(
            get: { deletingSessionUUID != nil },
            set: { if !$0 { deletingSessionUUID = nil } }
        )
    }

    private func sessionRenameSheet(_ sessionUUID: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("Rename Session")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            TextField("Session title", text: $sessionRenameDraft)
                .textFieldStyle(.plain)
                .font(CosmoTypography.body)
                .padding(DS.space12)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderActive, lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel") {
                    renamingSessionUUID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(CosmoColors.textSecondary)
                Button("Save") {
                    Task { await viewModel.renameSession(sessionUUID, title: sessionRenameDraft) }
                    renamingSessionUUID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
            }
        }
        .padding(DS.space20)
        .frame(width: 420)
        .background(DS.bg)
    }
}

private struct RootQuestionComposerSheet: View {
    let deepDive: Atom
    let questions: [Atom]
    @Binding var draft: String
    let onStart: (String) -> Void
    let onStartWithoutQuestion: () -> Void
    let onContinueQuestion: (Atom) -> Void

    private var suggestions: [String] {
        let topic = deepDive.title ?? "this"
        return [
            "What am I trying to understand about \(topic) today?",
            "What is the actual mechanism behind this?",
            "What evidence would change my mind?",
            "Is this source credible?"
        ]
    }

    private var unresolvedQuestions: [Atom] {
        questions.filter { question in
            let status = question.questionMetadata?.status ?? .open
            return status == .open || status == .researching || status == .partiallyAnswered
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Deep Dive: \(deepDive.title ?? "Untitled")")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                Text("What are you trying to understand?")
                    .font(CosmoTypography.titleSmall)
                    .foregroundStyle(CosmoColors.textPrimary)
            }

            TextField("How does breathwork affect HRV?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CosmoTypography.body)
                .padding(DS.space12)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.borderActive, lineWidth: 1))
                .onSubmit { startWithDraft() }

            VStack(alignment: .leading, spacing: DS.space8) {
                sectionLabel("SUGGESTED PATHS")
                ForEach(suggestions, id: \.self) { suggestion in
                    composerRow(suggestion, icon: "sparkles") {
                        onStart(suggestion)
                    }
                }
            }

            if !unresolvedQuestions.isEmpty {
                VStack(alignment: .leading, spacing: DS.space8) {
                    sectionLabel("CONTINUE")
                    ForEach(unresolvedQuestions.prefix(3), id: \.uuid) { question in
                        composerRow(question.title ?? "Untitled question", icon: "arrow.clockwise") {
                            onContinueQuestion(question)
                        }
                    }
                }
            }

            HStack {
                Button("Begin with placeholder") {
                    onStartWithoutQuestion()
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)

                Spacer()

                Button("Start Inquiry") {
                    startWithDraft()
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 8)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
            }
        }
        .padding(DS.space24)
        .frame(width: 520)
        .background(DS.bg)
    }

    private func startWithDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onStartWithoutQuestion()
        } else {
            onStart(trimmed)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .tracking(1.6)
            .foregroundStyle(CosmoColors.textTertiary)
    }

    private func composerRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.accent)
                Text(title)
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 8)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tabs

enum DeepDiveOverviewTab: CaseIterable {
    case overview, sessions, map
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .sessions: return "Sessions"
        case .map: return "Map"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "doc.text"
        case .sessions: return "rectangle.stack"
        case .map: return "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: - Current Understanding Display

private struct CurrentUnderstandingDisplayView: View {
    let understanding: CurrentUnderstanding

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if let narrative = understanding.narrative?.trimmingCharacters(in: .whitespacesAndNewlines),
               !narrative.isEmpty {
                Text(narrative)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineSpacing(4)
                if !understanding.oneSentenceModel.isEmpty {
                    Text(understanding.oneSentenceModel)
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textSecondary)
                        .italic()
                }
            } else if !understanding.oneSentenceModel.isEmpty {
                Text(understanding.oneSentenceModel)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(CosmoColors.textPrimary)
            } else {
                Text("Your current model lives here. Edit to capture how you currently understand this topic.")
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .italic()
            }
            countSummary
        }
    }

    private var countSummary: some View {
        let cp = understanding.corePrinciples.count
        let beliefs = understanding.whatIBelieve.count
        let unsure = understanding.whatImUnsureAbout.count
        var parts: [String] = []
        if cp > 0 { parts.append("\(cp) core principle\(cp == 1 ? "" : "s")") }
        if beliefs > 0 { parts.append("\(beliefs) belief\(beliefs == 1 ? "" : "s")") }
        if unsure > 0 { parts.append("\(unsure) uncertainty") }
        return Text(parts.joined(separator: " · "))
            .font(CosmoTypography.caption)
            .foregroundStyle(CosmoColors.textTertiary)
    }
}

// MARK: - Current Understanding Editor

private struct CurrentUnderstandingEditorView: View {
    @Bindable var viewModel: DeepDiveOverviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            TextField(
                "One-sentence model — your current grasp of this topic.",
                text: $viewModel.understandingDraftOneSentence,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .padding(DS.space12)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
            .lineLimit(3, reservesSpace: true)

            HStack {
                Spacer()
                Button("Save") {
                    Task { await viewModel.saveUnderstanding() }
                }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 6)
                .background(DS.accent, in: Capsule())
            }
        }
    }
}

// MARK: - Understanding History

private struct UnderstandingHistoryList: View {
    let revisions: [UnderstandingNarrativeRevision]
    let updates: [ModelUpdate]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DS.space12) {
                ForEach(updates, id: \.id) { update in
                    updateRow(update)
                }
                ForEach(revisions, id: \.id) { revision in
                    revisionRow(revision)
                }
            }
            .padding(.top, DS.space8)
        } label: {
            Text("History (\(revisions.count + updates.count))")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .tint(CosmoColors.textTertiary)
    }

    private func revisionRow(_ revision: UnderstandingNarrativeRevision) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                historyBadge(revision.kind?.rawValue ?? "revision")
                Text(relativeDate(revision.date))
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            Text(revision.text)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(4)
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private func updateRow(_ update: ModelUpdate) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                historyBadge(update.kind.rawValue)
                Text(relativeDate(update.date))
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            if !update.before.isEmpty {
                Text(update.before)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .strikethrough()
                    .lineLimit(2)
            }
            Text(update.after)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(3)
        }
        .padding(DS.space10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private func historyBadge(_ label: String) -> some View {
        Text(label.capitalized)
            .font(CosmoTypography.labelSmall)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 2)
            .background(DS.accentSoft, in: Capsule())
    }

    private func relativeDate(_ iso: String) -> String {
        guard let date = ISO8601.date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Simple FlowLayout (for lexicon pills)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
