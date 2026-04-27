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

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = State(initialValue: DeepDiveOverviewViewModel(atom: atom))
    }

    var body: some View {
        ZStack {
            CosmoColors.softWhite
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                tabBar
                Divider()
                    .background(DS.borderSubtle)
                tabContent
            }
        }
        .task { await viewModel.load() }
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space12) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)

            Spacer()

            Button(action: { startInquiry() }) {
                HStack(spacing: DS.space6) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Start Inquiry")
                        .font(CosmoTypography.label)
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 7)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        .padding(.horizontal, DS.space24)
        .padding(.top, DS.space20)
        .padding(.bottom, DS.space12)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: DS.space24) {
            ForEach(DeepDiveOverviewTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, DS.space24)
        .padding(.bottom, DS.space10)
    }

    @ViewBuilder
    private func tabButton(_ tab: DeepDiveOverviewTab) -> some View {
        let isActive = selectedTab == tab
        Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(CosmoTypography.label)
                    .foregroundStyle(isActive ? CosmoColors.textPrimary : CosmoColors.textSecondary)
                Rectangle()
                    .fill(isActive ? DS.accent : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .research: researchTab
        case .map: mapTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                titleBlock
                if shouldShowQuestion { currentQuestionBlock }
                currentUnderstandingBlock
                if shouldShowTopicInbox { topicInboxBlock }
                if shouldShowQuestions { questionsBlock }
                if shouldShowSources { sourcesBlock }
                if shouldShowLexicon { lexiconBlock }
                if shouldShowConnections { connectionsBlock }
                if shouldShowOutputs { outputsBlock }
                if shouldShowSessions { sessionsBlock }
                Spacer(minLength: DS.space40)
            }
            .padding(.horizontal, DS.space40)
            .padding(.vertical, DS.space24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(atom.title ?? "Untitled Deep Dive")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
            Text(metadataRowText)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
            if let about = atom.body, !about.isEmpty {
                Text(about)
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .padding(.top, DS.space4)
            }
        }
    }

    private var metadataRowText: String {
        var parts: [String] = []
        let maturity = atom.deepDiveMetadata?.maturity ?? .spark
        parts.append(maturity.displayName)
        if let updatedString = atom.deepDiveMetadata?.lastInquiryAt ?? Optional(atom.updatedAt),
           let date = ISO8601DateFormatter().date(from: updatedString) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append("Updated \(formatter.localizedString(for: date, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var currentQuestionBlock: some View {
        if let q = viewModel.currentQuestionTitle {
            VStack(alignment: .leading, spacing: DS.space6) {
                sectionLabel("CURRENT QUESTION")
                Text(q)
                    .font(.system(size: 18, weight: .regular, design: .serif).italic())
                    .foregroundStyle(CosmoColors.textPrimary)
            }
        }
    }

    private var currentUnderstandingBlock: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack {
                sectionLabel("CURRENT UNDERSTANDING")
                Spacer()
                Button {
                    viewModel.isEditingUnderstanding.toggle()
                } label: {
                    Text(viewModel.isEditingUnderstanding ? "Done" : "Edit")
                        .font(CosmoTypography.label)
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("u", modifiers: [.command])
            }

            if viewModel.isEditingUnderstanding {
                CurrentUnderstandingEditorView(viewModel: viewModel)
            } else {
                CurrentUnderstandingDisplayView(understanding: viewModel.understanding)
            }
        }
    }

    @ViewBuilder
    private var topicInboxBlock: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionLabel("TOPIC INBOX (\(viewModel.topicInboxItems.count))")
            ForEach(viewModel.topicInboxItems.prefix(5), id: \.id) { item in
                topicInboxRow(item)
            }
            if viewModel.topicInboxItems.count > 5 {
                Text("+ \(viewModel.topicInboxItems.count - 5) more")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
        }
    }

    private func topicInboxRow(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Circle()
                .fill(DS.accent.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 7)
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
        }
    }

    @ViewBuilder
    private var questionsBlock: some View {
        sectionContainer(title: "QUESTIONS (\(viewModel.questions.count))") {
            ForEach(viewModel.questions.prefix(8), id: \.uuid) { q in
                questionRow(q)
            }
            if viewModel.questions.isEmpty {
                Text("No questions yet — start an inquiry to spark some.")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
        }
    }

    private func questionRow(_ q: Atom) -> some View {
        let status = q.questionMetadata?.status ?? .open
        return HStack(spacing: DS.space8) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            Text(q.title ?? "Untitled question")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(status.displayName.lowercased())
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
    }

    @ViewBuilder
    private var sourcesBlock: some View {
        sectionContainer(title: "SOURCES (\(viewModel.sources.count))") {
            ForEach(viewModel.sources.prefix(6), id: \.uuid) { s in
                Text("· \(s.title ?? "Untitled source")")
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var lexiconBlock: some View {
        sectionContainer(title: "LEXICON (\(viewModel.lexicon.count))") {
            FlowLayout(spacing: DS.space8) {
                ForEach(viewModel.lexicon, id: \.uuid) { entry in
                    Text(entry.title ?? "·")
                        .font(CosmoTypography.label)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .padding(.horizontal, DS.space10)
                        .padding(.vertical, 4)
                        .background(DS.accentSoft, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var connectionsBlock: some View {
        sectionContainer(title: "CONNECTIONS (\(viewModel.connections.count))") {
            ForEach(viewModel.connections.prefix(6), id: \.uuid) { c in
                Text("· \(c.title ?? "Untitled connection")")
                    .font(CosmoTypography.body)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var outputsBlock: some View {
        sectionContainer(title: "OUTPUTS (\(viewModel.outputAngles.count))") {
            ForEach(viewModel.outputAngles, id: \.id) { angle in
                HStack {
                    Text("· \(angle.title)")
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let format = angle.format {
                        Text(format)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionsBlock: some View {
        sectionContainer(title: "RESEARCH SESSIONS (\(viewModel.sessions.count))") {
            ForEach(viewModel.sessions.prefix(8), id: \.uuid) { session in
                sessionRow(session)
            }
        }
    }

    private func sessionRow(_ session: Atom) -> some View {
        let meta = session.inquirySessionMetadata
        let status = meta?.status ?? .paused
        return HStack(spacing: DS.space8) {
            Circle()
                .fill(sessionStatusColor(status))
                .frame(width: 7, height: 7)
            Text(session.title ?? "Untitled session")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(status.rawValue)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            resumeSession(session)
        }
    }

    // MARK: - Research Tab (placeholder grid of sessions)

    private var researchTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("Inquiry Sessions")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(CosmoColors.textPrimary)
                if viewModel.sessions.isEmpty {
                    Text("No sessions yet. Click Start Inquiry to open the workspace.")
                        .font(CosmoTypography.body)
                        .foregroundStyle(CosmoColors.textSecondary)
                } else {
                    ForEach(viewModel.sessions, id: \.uuid) { session in
                        sessionCard(session)
                    }
                }
            }
            .padding(.horizontal, DS.space40)
            .padding(.vertical, DS.space24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func sessionCard(_ session: Atom) -> some View {
        let meta = session.inquirySessionMetadata
        let status = meta?.status ?? .paused
        return VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                Text(session.title ?? "Untitled session")
                    .font(CosmoTypography.titleSmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                Spacer()
                Text(status.rawValue)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(sessionStatusColor(status))
            }
            if let body = session.body, !body.isEmpty {
                Text(body)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: DS.space12) {
                Button("Resume") { resumeSession(session) }
                    .buttonStyle(.plain)
                    .font(CosmoTypography.label)
                    .foregroundStyle(DS.accent)
            }
        }
        .padding(DS.space16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .onTapGesture { resumeSession(session) }
    }

    // MARK: - Map Tab (placeholder)

    private var mapTab: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 36))
                .foregroundStyle(DS.accent.opacity(0.5))
            Text("Map view")
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Spatial map of concepts, sources, and connections forms after sessions crystallize.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    case overview, research, map
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .research: return "Research"
        case .map: return "Map"
        }
    }
}

// MARK: - Current Understanding Display

private struct CurrentUnderstandingDisplayView: View {
    let understanding: CurrentUnderstanding

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if !understanding.oneSentenceModel.isEmpty {
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
