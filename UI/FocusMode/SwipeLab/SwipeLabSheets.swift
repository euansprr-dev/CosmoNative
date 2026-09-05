import SwiftUI

struct SwipeLabSettingsSheet: View {
    @Bindable var model: SwipeLabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showScopePicker = false
    @State private var scope: SwipeLabScope
    @State private var dateFilter = false
    @State private var dateFrom = Date().addingTimeInterval(-30 * 86_400)
    @State private var dateTo = Date()
    @State private var modules: [SwipeLabPromptModule] = []

    init(model: SwipeLabViewModel) {
        self.model = model
        _scope = State(initialValue: model.state.scope)
        _dateFilter = State(initialValue: model.state.scope.publishedAfter != nil)
        _dateFrom = State(initialValue: model.state.scope.publishedAfter ?? Date().addingTimeInterval(-30 * 86_400))
        _dateTo = State(initialValue: model.state.scope.publishedBefore ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            SwipeLabSheetHeader(title: "Study settings", detail: "Choose the evidence and the perspective.")
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    VStack(alignment: .leading, spacing: DS.space12) {
                        Text("Source population").font(DS.headline)
                        HStack { Text(scope.title).font(DS.body); Spacer(); Button("Change…") { showScopePicker = true } }
                        Text("The source population is separate from the client you’re learning for.").font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        Picker("Platform", selection: $scope.platform) {
                            Text("All platforms").tag(String?.none)
                            ForEach(platformOptions, id: \.self) { Text($0 == "x" ? "X / Twitter" : $0.capitalized).tag(Optional($0)) }
                        }
                        Picker("Format", selection: $scope.format) {
                            Text("All formats").tag(String?.none)
                            ForEach(formatOptions, id: \.self) { Text(ContentFormat(rawValue: $0)?.displayName ?? $0.capitalized).tag(Optional($0)) }
                        }
                        Toggle("Limit to a publication window", isOn: $dateFilter).toggleStyle(.checkbox)
                        if dateFilter {
                            DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                            DatePicker("Through", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                            Text("Posts without a publication date are excluded by this filter.").font(DS.caption).foregroundStyle(DS.textMuted)
                        }
                        Button("Apply source scope") {
                            scope.publishedAfter = dateFilter ? Calendar.current.startOfDay(for: dateFrom) : nil
                            scope.publishedBefore = dateFilter ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo)) : nil
                            Task { await model.updateStudy(scope: scope) }
                        }.disabled(model.isRunning)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: DS.space12) {
                        Picker("Learn for", selection: $model.state.targetClientID) {
                            Text("Any client").tag(String?.none)
                            ForEach(model.clients) { client in Text(client.title ?? "Untitled client").tag(Optional(client.uuid)) }
                        }.onChange(of: model.state.targetClientID) { _, _ in model.scheduleSave() }
                        Text("Uses the client’s positioning, audience, voice and accepted principles. Existing findings keep their original client scope.").font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        Picker("Outcome to examine", selection: $model.state.metric) {
                            ForEach(SwipeLabMetric.allCases) { metric in Text(metric.title).tag(metric) }
                        }.onChange(of: model.state.metric) { _, _ in model.scheduleSave() }
                    }
                    SwipeLabLabeledEditor(title: "Additional study guidance", text: $model.state.guidance, minHeight: 90)
                        .onChange(of: model.state.guidance) { _, _ in model.scheduleSave() }
                    VStack(alignment: .leading, spacing: DS.space12) {
                        Text("Craft guidance").font(DS.headline)
                        Text("The study method is always active. Relevant craft modules are chosen automatically; you can include additional references below. Disabled app modules stay disabled.")
                            .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                        ForEach(modules) { module in
                            DisclosureGroup {
                                Text(module.content).font(DS.subheadline).textSelection(.enabled).padding(.vertical, DS.space8)
                            } label: {
                                Toggle(isOn: Binding(get: { model.state.additionalModuleIDs.contains(module.id) }, set: { enabled in
                                    if enabled { model.state.additionalModuleIDs.append(module.id) }
                                    else { model.state.additionalModuleIDs.removeAll { $0 == module.id } }
                                    model.scheduleSave()
                                })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(module.title).font(DS.subheadline)
                                        Text("\(module.source) · \(module.hash.prefix(8))\(module.enabled ? "" : " · disabled in app")").font(DS.caption2).foregroundStyle(DS.textMuted)
                                    }
                                }.toggleStyle(.checkbox).disabled(!module.enabled)
                            }
                        }
                    }
                }.padding(DS.space24)
            }
            HStack { Spacer(); Button("Done") { model.scheduleSave(); dismiss() }.keyboardShortcut(.defaultAction) }.padding(DS.space16)
        }.frame(width: 600, height: 690).background(DS.bg).tint(DS.accent)
        .onAppear { modules = SwipeLabPromptCatalog.catalog() }
        .sheet(isPresented: $showScopePicker) {
            SwipeLabScopePicker(title: "Choose study sources", actionTitle: "Use this population") { newScope in
                scope = newScope; dateFilter = false; showScopePicker = false
            }
        }
    }

    private var platformOptions: [String] {
        Set(model.sources.map { SwipeLabCorpus.platformFamily($0.platform) } + ["instagram", "x", "youtube", "linkedin", "tiktok"] + [scope.platform].compactMap { $0 }).sorted()
    }
    private var formatOptions: [String] {
        Set(ContentFormat.allCases.map(\.rawValue) + model.sources.map(\.format) + ["page", "email", "frame", "flow"] + [scope.format].compactMap { $0 }).sorted()
    }
}

struct SwipeLabPrincipleEditor: View {
    @State var finding: SwipeLabFinding
    let clients: [Atom]
    let onSave: (SwipeLabFinding) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SwipeLabSheetHeader(title: "Refine the principle", detail: "Keep the claim as narrow as its evidence.")
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    TextField("Principle", text: $finding.title).textFieldStyle(.roundedBorder).font(DS.headline)
                    SwipeLabLabeledEditor(title: "What the originals show", text: $finding.observation, minHeight: 70)
                    SwipeLabLabeledEditor(title: "Working explanation", text: $finding.mechanism, minHeight: 70)
                    SwipeLabLabeledEditor(title: "Conditions & exceptions", text: $finding.limitations, minHeight: 70)
                    SwipeLabLabeledEditor(title: "How to apply it", text: $finding.transfer, minHeight: 70)
                    Picker("Applies to", selection: $finding.clientID) {
                        Text("All clients").tag(String?.none)
                        ForEach(clients) { Text($0.title ?? "Untitled client").tag(Optional($0.uuid)) }
                    }
                    Picker("Status", selection: $finding.status) {
                        Text("Proposed").tag(SwipeLabFinding.Status.proposed)
                        if finding.connectionID != nil { Text("Saved").tag(SwipeLabFinding.Status.accepted) }
                        Text("Archived").tag(SwipeLabFinding.Status.archived)
                        Text("Rejected").tag(SwipeLabFinding.Status.rejected)
                    }
                    Text("The original evidence and source version remain attached.").font(DS.caption).foregroundStyle(DS.textMuted)
                }.padding(DS.space24)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save changes") { onSave(finding) }.keyboardShortcut(.defaultAction).disabled(finding.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(DS.space16)
        }.frame(width: 600, height: 700).background(DS.bg).tint(DS.accent)
    }
}

struct SwipeLabExperimentSheet: View {
    @Bindable var model: SwipeLabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    var body: some View {
        VStack(spacing: 0) {
            SwipeLabSheetHeader(title: "Make the lesson testable.", detail: "Create an idea with one deliberate creative change.")
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    TextField("Idea title", text: $model.experimentTitle).textFieldStyle(.roundedBorder).font(DS.headline)
                    SwipeLabLabeledEditor(title: "Hypothesis", text: $model.experimentHypothesis, minHeight: 75)
                    SwipeLabLabeledEditor(title: "What will you change?", text: $model.experimentChange, minHeight: 90)
                    SwipeLabLabeledEditor(title: "What result would challenge it?", text: $model.experimentCounterPrediction, minHeight: 75)
                    Picker("Measure", selection: $model.state.metric) {
                        ForEach(SwipeLabMetric.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Observe after \(model.experimentDays) days", value: $model.experimentDays, in: 1...90)
                    Text("The idea carries the principle, linked swipes and client context into your existing creation workflow.").font(DS.subheadline).foregroundStyle(DS.textSecondary)
                    if let error = model.error { Text(error).font(DS.subheadline).foregroundStyle(DS.orange) }
                }.padding(DS.space24)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Create idea") {
                    isSaving = true
                    Task { await model.createIdea(); isSaving = false }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(isSaving || model.experimentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(DS.space16)
        }.frame(width: 600, height: 690).background(DS.bg).tint(DS.accent)
    }
}

struct SwipeLabSheetHeader: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(title).font(DS.heroTitleSerif).foregroundStyle(DS.text)
            Text(detail).font(DS.subheadline).foregroundStyle(DS.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(DS.space24)
    }
}
