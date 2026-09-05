import SwiftUI

struct SwipeLabConversationPane: View {
    @Bindable var model: SwipeLabViewModel
    let isOverlay: Bool
    @State private var followsConversation = true
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack {
                    Text("Study partner").font(DS.headline)
                    Spacer()
                    Button { model.showConversation = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Hide conversation").accessibilityLabel("Hide conversation")
                }
                Picker("Look at", selection: $model.state.lens) {
                    ForEach(SwipeLabLens.allCases) { Text($0.rawValue).tag($0) }
                }.onChange(of: model.state.lens) { _, _ in model.scheduleSave() }
                Text("\(model.sources.filter { !$0.isComparison }.count) study posts · \(model.sources.filter(\.isComparison).count) comparison posts")
                    .font(DS.caption).foregroundStyle(DS.textMuted)
            }.padding(DS.space16)
            Divider().overlay(DS.borderSubtle)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.space24) {
                        if model.state.turns.isEmpty { startingQuestions }
                        ForEach(model.state.turns) { turn in turnView(turn).id(turn.id) }
                        if model.isRunning { activity }
                        Color.clear.frame(height: 1).id("conversation-end")
                            .onAppear { followsConversation = true }
                            .onDisappear { followsConversation = false }
                    }.padding(DS.space16)
                }
                .onChange(of: model.state.turns.count) { _, _ in
                    if followsConversation || model.state.turns.last?.role == .user { proxy.scrollTo("conversation-end", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsConversation {
                        Button { proxy.scrollTo("conversation-end", anchor: .bottom) } label: { Label("Latest", systemImage: "arrow.down") }
                            .font(DS.caption).buttonStyle(.bordered).padding(DS.space12)
                    }
                }
            }
            composer
        }
        .studyPanelSurface(edge: .trailing, isOverlay: isOverlay)
    }

    private var startingQuestions: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text("What is worth learning here?").font(DS.blockTitleSerif)
            Text("Start with a question. I’ll read the available originals, look for exceptions, and show the evidence.")
                .font(DS.subheadline).foregroundStyle(DS.textSecondary).lineSpacing(4)
            ForEach(["What do these posts have in common?", "Why might these be outperforming? What evidence is missing?", "Compare how these posts build and repay curiosity.", "Which technique could work for this client—and where would it fail?"], id: \.self) { question in
                Button { model.ask(question) } label: {
                    HStack(alignment: .top) {
                        Text(question).multilineTextAlignment(.leading)
                        Spacer(minLength: DS.space8)
                        Image(systemName: "arrow.up.left").foregroundStyle(DS.textMuted)
                    }.font(DS.subheadline).padding(.vertical, DS.space8).contentShape(.rect)
                }.buttonStyle(.plain).disabled(model.isRunning || model.sources.isEmpty)
            }
        }
    }

    private func turnView(_ turn: SwipeLabTurn) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text(turn.role == .user ? "YOU" : "SWIPE LAB").font(DS.caption2.weight(.semibold)).tracking(1)
                Spacer()
                Text(turn.createdAt.formatted(date: .omitted, time: .shortened)).font(DS.caption2)
            }.foregroundStyle(DS.textMuted)
            Text(.init(turn.text)).font(DS.body).lineSpacing(5).textSelection(.enabled)
            if let coverage = turn.coverage {
                SwipeLabCoverageView(coverage: coverage)
            }
            ForEach(turn.findingIDs, id: \.self) { id in
                if let finding = model.state.findings.first(where: { $0.id == id }) {
                    SwipeLabFindingView(finding: finding, model: model, compact: true)
                }
            }
            if let hash = turn.promptHash {
                Text("Method \(hash.prefix(8)) · source snapshot \(turn.snapshotID?.prefix(8) ?? "—")")
                    .font(DS.caption2).foregroundStyle(DS.textMuted).help("This answer retains its source and guidance version.")
            }
        }
        .padding(.leading, turn.role == .user ? DS.space12 : 0)
        .overlay(alignment: .leading) {
            if turn.role == .user { Rectangle().fill(DS.border).frame(width: 2) }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                ProgressView().controlSize(.small)
                Text(model.activity).font(DS.subheadline).foregroundStyle(DS.textSecondary)
            }
            SwipeLabCoverageView(coverage: model.coverage)
        }.accessibilityElement(children: .combine)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TextField("Ask about these posts…", text: $model.state.draftQuestion, axis: .vertical)
                .lineLimit(3...8).textFieldStyle(.plain).font(DS.body).focused($composerFocused)
                .onChange(of: model.state.draftQuestion) { _, _ in model.scheduleSave() }
            HStack {
                Text(model.clientName).font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(1)
                Spacer()
                if model.isRunning {
                    Button { model.cancel() } label: { Label("Stop", systemImage: "stop.fill") }.font(DS.subheadline)
                } else {
                    Button { model.ask(); composerFocused = true } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderedProminent).clipShape(Circle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Ask Swipe Lab (⌘Return)").accessibilityLabel("Ask Swipe Lab")
                        .disabled(model.state.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sources.isEmpty)
                }
            }
        }
        .padding(DS.space12).background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(composerFocused ? DS.focusRing : DS.border, lineWidth: 0.5))
        .padding(DS.space12)
    }
}

struct SwipeLabCoverageView: View {
    let coverage: SwipeLabCoverage
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Label(coverage.label, systemImage: coverage.isComplete ? "checkmark.circle" : "circle.dotted")
            if coverage.duplicateCount > 0 { Text("\(coverage.duplicateCount) duplicates excluded") }
            if let images = coverage.imagesInspected, images > 0 { Text("\(images) original still images inspected") }
            if coverage.total - coverage.readable - coverage.duplicateCount > 0 {
                Text("\(coverage.total - coverage.readable - coverage.duplicateCount) posts without readable originals")
            }
            if !coverage.failedIDs.isEmpty { Text("\(coverage.failedIDs.count) source readings failed · ask again to retry") }
        }.font(DS.caption2).foregroundStyle(DS.textSecondary)
    }
}

struct SwipeLabFindingView: View {
    let finding: SwipeLabFinding
    @Bindable var model: SwipeLabViewModel
    var compact = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(alignment: .top) {
                Text(finding.title).font(compact ? DS.headline : DS.blockTitleSerif)
                Spacer(minLength: DS.space8)
                if finding.status == .accepted {
                    Image(systemName: "bookmark.fill").foregroundStyle(DS.accent).font(DS.caption).accessibilityLabel("Saved principle")
                }
            }
            Text(finding.observation).font(DS.subheadline).lineSpacing(4).textSelection(.enabled)
            if !compact || expanded {
                findingField("Working explanation", finding.mechanism)
                findingField("Where it may fail", finding.limitations)
                findingField("Try for this client", finding.transfer)
            }
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Evidence in \(finding.supportCount) distinct posts").font(DS.caption.weight(.medium)).foregroundStyle(DS.textSecondary)
                ForEach(finding.support) { anchor in citation(anchor, counter: false) }
                ForEach(finding.counterevidence) { anchor in citation(anchor, counter: true) }
            }
            if compact {
                Button(expanded ? "Less detail" : "Explanation & limits") { expanded.toggle() }.font(DS.caption)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.space12) { findingActions }
                VStack(alignment: .leading, spacing: DS.space8) { findingActions }
            }
        }
        .padding(.vertical, DS.space16)
        .overlay(alignment: .top) { Rectangle().fill(DS.borderSubtle).frame(height: 0.5) }
        .opacity(finding.status == .archived || finding.status == .rejected ? 0.65 : 1)
    }

    @ViewBuilder private var findingActions: some View {
        if finding.status == .proposed {
            Button("Save principle") { Task { await model.accept(finding) } }.font(DS.subheadline.weight(.medium))
        }
        Button("Use in an idea") { model.prepareExperiment(finding) }.font(DS.subheadline)
        Menu {
            Button("Edit principle & scope…") { model.editingFinding = finding }
            Button("Archive") { Task { await model.archive(finding) } }
        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Principle actions")
    }

    private func findingField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(title).font(DS.caption.weight(.semibold)).foregroundStyle(DS.textSecondary)
            Text(value).font(DS.subheadline).lineSpacing(4).textSelection(.enabled)
        }
    }

    private func citation(_ anchor: SwipeLabAnchor, counter: Bool) -> some View {
        Button { model.open(anchor) } label: {
            VStack(alignment: .leading, spacing: DS.space4) {
                Label((counter ? "Counterexample · " : "") + anchor.label, systemImage: "arrow.up.left")
                    .font(DS.caption.weight(.medium)).foregroundStyle(DS.accent)
                Text(anchor.quote.isEmpty ? "Original image · open to inspect" : "“\(anchor.quote)”").font(DS.subheadline).foregroundStyle(DS.textSecondary).lineLimit(3).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).help("Reveal the exact original passage")
    }
}
