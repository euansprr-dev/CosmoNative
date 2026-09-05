import SwiftUI
import AppKit

struct SwipeLabReaderPane: View {
    @Bindable var model: SwipeLabViewModel
    @State private var showContinuousText = false

    var body: some View {
        if let source = model.selectedSource {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.space24) {
                        header(source)
                        if let reader = model.readerModel {
                            SwipeStudyStagePane(model: reader, atom: source.atom)
                        }
                        HStack {
                            Text("Original passages").font(DS.headline)
                            Spacer()
                            Button(showContinuousText ? "Show beats" : "Continuous text") { showContinuousText.toggle() }.font(DS.subheadline)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(source.units.map(\.text).joined(separator: "\n\n"), forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).help("Copy the complete original text").accessibilityLabel("Copy original text")
                        }
                        if source.units.isEmpty {
                            Text("This source has no readable original text yet. Add or repair its transcript in Swipe Focus Mode to include it in analysis.")
                                .font(DS.body).foregroundStyle(DS.textSecondary)
                        } else if showContinuousText {
                            Text(source.units.map(\.text).joined(separator: "\n\n"))
                                .font(DS.body).lineSpacing(6).textSelection(.enabled)
                        } else {
                            ForEach(source.units) { unit in
                                SwipeLabPassageView(unit: unit, job: model.state.observedJobs[unit.id], selected: model.selectedAnchorID == unit.id) {
                                    model.selectUnit(unit)
                                }
                                .id(unit.id)
                                .contextMenu {
                                    Button("Ask about this passage") {
                                        model.selectUnit(unit)
                                        model.state.draftQuestion = "Explain the move in \(source.title), \(unit.anchor.label): ‘\(unit.text.prefix(240))’"
                                        model.showConversation = true
                                    }
                                    Button("Compare this beat") { model.selectUnit(unit); model.setMode(.compare) }
                                    Button("Find the same move") {
                                        model.showConversation = true
                                        model.ask("Find passages elsewhere in this study that do the same job as \(source.title), \(unit.anchor.label): ‘\(unit.text.prefix(600))’. Compare what changes, and cite the exact original passages.")
                                    }
                                    Button("Challenge this interpretation") {
                                        model.showConversation = true
                                        model.ask("Challenge the interpretation of \(source.title), \(unit.anchor.label): ‘\(unit.text.prefix(600))’. Look for counterexamples in this study and distinguish an observed move from a performance explanation.")
                                    }
                                }
                            }
                        }
                        HStack {
                            Button("Previous post") { model.step(-1) }
                            Spacer()
                            Button("Next post") { model.step(1) }
                        }.font(DS.subheadline)
                    }
                    .padding(DS.space32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .onChange(of: model.selectedAnchorID) { _, id in
                    if let id { showContinuousText = false; proxy.scrollTo(id, anchor: .center) }
                }
            }
        } else {
            SwipeLabEmptyState(icon: "books.vertical", title: "A place to look closer", detail: "Choose a board or a selection of swipes in the study settings. Original posts become the evidence for every lesson.")
        }
    }

    private func header(_ source: SwipeLabSource) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text([source.platformLabel, source.formatLabel].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                    .font(DS.caption.weight(.medium)).tracking(1.2).foregroundStyle(DS.textSecondary)
                Spacer()
                if model.canGoBack { Button("Back to passage") { model.backToPassage() }.font(DS.caption) }
            }
            Text(source.title).font(DS.heroTitleSerif).foregroundStyle(DS.text).textSelection(.enabled)
            if !source.creator.isEmpty { Text(source.creator).font(DS.subheadline).foregroundStyle(DS.textSecondary) }
            SwipeLabMetricsView(source: source, metric: model.state.metric)
        }
    }
}

struct SwipeLabPassageView: View {
    let unit: SwipeLabUnit
    var job: String? = nil
    var selected = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                if let action {
                    Button(action: action) {
                        Label(unit.anchor.label, systemImage: unit.anchor.kind == .speech ? "waveform" : "text.alignleft")
                    }.buttonStyle(.plain).help("Select and reveal this original passage")
                } else { Text(unit.anchor.label) }
                Spacer(minLength: DS.space8)
                if let job { Text(job.capitalized).foregroundStyle(DS.textMuted) }
            }.font(DS.caption).foregroundStyle(selected ? DS.accent : DS.textSecondary)
            Text(unit.text.isEmpty ? "Image without transcribed text · select to view the original" : unit.text).font(DS.body).lineSpacing(6).foregroundStyle(DS.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.space12).padding(.horizontal, DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? DS.selectionWash.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(selected ? DS.accent : DS.borderSubtle).frame(width: 2)
        }
    }
}

struct SwipeLabMetricsView: View {
    let source: SwipeLabSource
    let metric: SwipeLabMetric
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let observation = source.metrics.first(where: { $0.metric == metric }) {
                Text("\(observation.value.formatted()) \(metric.rawValue)").font(DS.subheadline.weight(.medium)).monospacedDigit()
                Text(observation.capturedAt.map { "Measured \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Capture date unknown · not age-normalized")
                    .font(DS.caption).foregroundStyle(DS.textMuted)
            } else {
                Text("\(metric.title) unavailable").font(DS.caption).foregroundStyle(DS.textMuted)
            }
        }
    }
}

struct SwipeLabComparePane: View {
    @Bindable var model: SwipeLabViewModel
    @State private var job = "opening"
    private let jobs = ["opening", "context", "tension", "proof", "turn", "payoff", "action"]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    Text("Find the meaningful difference.").font(DS.heroTitleSerif)
                    Text("Compare the same job in two posts. A shared structure is a clue; a useful exception can teach more.")
                        .font(DS.body).foregroundStyle(DS.textSecondary)
                    controls
                    if model.state.comparisonScope != nil { cohortComparison }
                    if let source = model.selectedSource, let other = model.comparisonSource {
                        let layout = geometry.size.width >= 640 ? AnyLayout(HStackLayout(alignment: .top, spacing: DS.space24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: DS.space24))
                        layout {
                            comparisonColumn(source)
                            comparisonColumn(other)
                        }
                        Button("Study the difference") {
                            model.showConversation = true
                            model.ask("Compare the \(job) in ‘\(source.title)’ and ‘\(other.title)’. What changes the reader's expectation? Find evidence and a counterexample across the study. Distinguish content differences from measured performance.")
                        }.buttonStyle(.borderedProminent).disabled(model.isRunning)
                    } else {
                        Text("Choose at least two posts to compare. Add ordinary-performing examples to investigate what differs from your selected winners.").font(DS.body).foregroundStyle(DS.textSecondary)
                    }
                }.padding(DS.space32).frame(maxWidth: 980).frame(maxWidth: .infinity)
            }
        }
        .onAppear { job = jobs.contains(model.selectedJob) ? model.selectedJob : "opening" }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Picker("Beat", selection: $job) { ForEach(jobs, id: \.self) { Text($0.capitalized).tag($0) } }.frame(maxWidth: 300)
            Picker("Compare with", selection: $model.state.comparisonSourceID) {
                Text("Choose a post").tag(String?.none)
                ForEach(model.sources.filter { $0.id != model.selectedSource?.id }) { Text($0.title).tag(Optional($0.id)) }
            }.onChange(of: model.state.comparisonSourceID) { _, _ in model.scheduleSave() }
            HStack {
                Button("Add comparison population…") { model.showComparisonPicker = true }.disabled(model.isRunning)
                if model.state.comparisonScope != nil {
                    Button("Remove comparison") { Task { await model.addComparison(nil) } }.disabled(model.isRunning)
                }
            }.font(DS.subheadline)
            Picker("Outcome", selection: $model.state.metric) {
                ForEach(SwipeLabMetric.allCases) { Text($0.title).tag($0) }
            }.onChange(of: model.state.metric) { _, _ in model.scheduleSave() }.frame(maxWidth: 300)
        }
    }

    private var cohortComparison: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach([false, true], id: \.self) { comparison in
                let members = model.sources.filter { $0.isComparison == comparison }
                let platforms = Set(members.map(\.platform))
                let formats = Set(members.map(\.format))
                let cohort = SwipeLabStatistics.cohort(members, metric: model.state.metric, label: comparison ? "Comparison" : "Study")
                HStack {
                    Text(cohort.label).font(DS.subheadline.weight(.semibold))
                    Spacer()
                    if platforms.count <= 1 && formats.count <= 1, let median = cohort.median {
                        Text("Median \(Int(median).formatted()) \(model.state.metric.rawValue)").font(DS.subheadline).monospacedDigit()
                    } else { Text("Mixed formats or platforms").font(DS.subheadline).foregroundStyle(DS.textSecondary) }
                    Text("\(cohort.count) measured · \(cohort.missing) missing").font(DS.caption).foregroundStyle(DS.textMuted)
                }
            }
            Text("Descriptive counts from the saved snapshots. Observation windows and distribution may differ; these are not a controlled test.")
                .font(DS.caption).foregroundStyle(DS.textSecondary)
        }.padding(.vertical, DS.space12)
    }

    private func comparisonColumn(_ source: SwipeLabSource) -> some View {
        let matches = source.units.filter { (model.state.observedJobs[$0.id] ?? $0.job.lowercased()) == job }
        return VStack(alignment: .leading, spacing: DS.space16) {
            Text(source.title).font(DS.blockTitleSerif).fixedSize(horizontal: false, vertical: true)
            SwipeLabMetricsView(source: source, metric: model.state.metric)
            if matches.isEmpty {
                Text(model.state.observedJobs.isEmpty ? "This beat hasn't been identified yet. Study the posts to map their jobs, or read the original." : "No passage was identified as this beat. Its absence is part of the comparison.")
                    .font(DS.subheadline).foregroundStyle(DS.textSecondary)
            }
            ForEach(matches) { unit in
                if unit.hasVisual { SwipeLabOriginalStill(source: source, unit: unit) }
                SwipeLabPassageView(unit: unit, job: job) { model.open(unit.anchor) }
            }
            Button("Read original") { model.selectSource(source.id); model.setMode(.study) }.font(DS.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SwipeLabOriginalStill: View {
    let source: SwipeLabSource
    let unit: SwipeLabUnit
    @State private var image: NSImage?
    @State private var isLoading = true
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Original \(unit.anchor.label)")
            } else if isLoading { ProgressView("Loading original image…").font(DS.caption) }
            else { Label("Original image unavailable", systemImage: "photo").font(DS.caption).foregroundStyle(DS.textMuted) }
        }
        .task(id: unit.id) {
            let originals = await SwipeLabVisualLoader.load(source: source, units: [unit])
            if !Task.isCancelled { image = originals.first.flatMap { NSImage(data: $0.jpeg) }; isLoading = false }
        }
    }
}
