import SwiftUI

struct SwipeLabPracticePane: View {
    @Bindable var model: SwipeLabViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Train your eye.").font(DS.heroTitleSerif)
                    Spacer()
                    Menu("Previous practice") {
                        ForEach(model.state.practices.reversed()) { practice in
                            Button(practice.updatedAt.formatted(date: .abbreviated, time: .shortened)) { model.activePracticeID = practice.id }
                        }
                    }.font(DS.subheadline).fixedSize()
                }
                Text("Notice the move before seeing the explanation. One careful observation is more useful than another saved post.")
                    .font(DS.body).foregroundStyle(DS.textSecondary)
                if let practice = model.activePractice {
                    if let source = model.sources.first(where: { $0.id == practice.sourceID }),
                       let unit = source.units.first(where: { $0.id == practice.anchor.id }), unit.hasVisual {
                        SwipeLabOriginalStill(source: source, unit: unit)
                    }
                    SwipeLabPassageView(unit: .init(anchor: practice.anchor, job: "opening", text: practice.anchor.quote))
                    Text(practice.question).font(DS.headline).fixedSize(horizontal: false, vertical: true)
                    SwipeLabLabeledEditor(title: "Your explanation", text: Binding(get: { model.activePractice?.answer ?? "" }, set: { model.updatePractice(answer: $0) }), minHeight: 110)
                    SwipeLabLabeledEditor(title: "Try the move in your own words for \(model.clientName.lowercased())", text: Binding(get: { model.activePractice?.application ?? "" }, set: { model.updatePractice(application: $0) }), minHeight: 90)
                    HStack {
                        Button(practice.feedback == nil ? "Get feedback" : "Review my revision") { model.reviewPractice() }
                            .buttonStyle(.borderedProminent).disabled(model.isRunning || practice.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Another exercise") { model.beginPractice() }.disabled(model.isRunning)
                        if model.isRunning { ProgressView().controlSize(.small); Button("Stop") { model.cancel() } }
                    }
                    if let feedback = practice.feedback {
                        Divider()
                        Text("A closer look").font(DS.blockTitleSerif)
                        Text(.init(feedback)).font(DS.body).lineSpacing(6).textSelection(.enabled)
                        Button("Reveal the rest of the post") { model.selectSource(practice.sourceID); model.setMode(.study) }
                    }
                } else {
                    Text("Add readable sources to begin your first exercise.").font(DS.body).foregroundStyle(DS.textSecondary)
                }
            }.padding(DS.space32).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}

struct SwipeLabNotebookPane: View {
    @Bindable var model: SwipeLabViewModel
    @State private var showArchived = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                Text("Keep what you can use.").font(DS.heroTitleSerif)
                Text("Each principle keeps its original evidence, conditions and client scope. Saved principles become part of your writing guidance.")
                    .font(DS.body).foregroundStyle(DS.textSecondary)
                Toggle("Include archived principles", isOn: $showArchived).toggleStyle(.checkbox).font(DS.subheadline)
                let findings = showArchived ? model.state.findings : model.visibleFindings
                if findings.isEmpty {
                    SwipeLabEmptyState(icon: "bookmark", title: "Your first useful lesson", detail: "Ask a question in Study, inspect the evidence, then save a finding you want to use again.")
                }
                ForEach(findings) { finding in
                    SwipeLabFindingView(finding: finding, model: model)
                    Text(finding.clientID.flatMap { id in model.clients.first { $0.uuid == id }?.title } ?? (finding.clientID == nil ? "All clients" : "Client unavailable"))
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                }
            }.padding(DS.space32).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}

struct SwipeLabOutcomesPane: View {
    @Bindable var model: SwipeLabViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                Text("Close the learning loop.").font(DS.heroTitleSerif)
                Text("Turn a principle into a deliberate creative change. Then revisit the result at the observation window you chose.")
                    .font(DS.body).foregroundStyle(DS.textSecondary)
                if model.state.experiments.isEmpty {
                    SwipeLabEmptyState(icon: "chart.xyaxis.line", title: "From insight to experiment", detail: "Choose “Use in an idea” on a principle to define what you’ll change, what you’ll measure and what would challenge the idea.")
                }
                ForEach(model.state.experiments) { experiment in
                    experimentView(experiment)
                }
            }.padding(DS.space32).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }.task { await model.loadOutcomes() }
    }

    private func experimentView(_ experiment: SwipeLabExperiment) -> some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Divider()
            Text(experiment.hypothesis).font(DS.blockTitleSerif)
            Text(experiment.deliberateChange).font(DS.body).lineSpacing(4).textSelection(.enabled)
            Text("Challenge: \(experiment.counterPrediction)").font(DS.subheadline).foregroundStyle(DS.textSecondary)
            Label("\(experiment.metric.title) · \(experiment.observationDays) days after publishing", systemImage: "calendar")
                .font(DS.subheadline).foregroundStyle(DS.textSecondary)
            Picker("Published content", selection: Binding(get: { model.linkedContent(for: experiment)?.uuid ?? "" }, set: { id in
                Task { await model.linkContent(id, experimentID: experiment.id) }
            })) {
                Text("Link the resulting post…").tag("")
                ForEach(model.outcomeContent.filter { experiment.clientID == nil || SwipeLabCorpus.clientIDForContent($0) == experiment.clientID }) { content in
                    Text(content.title ?? "Untitled content").tag(content.uuid)
                }
            }
            if let content = model.linkedContent(for: experiment) {
                let source = SwipeLabCorpus.source(content, performance: model.outcomeSnapshots[content.uuid] ?? [])
                let measurements = source.metrics.filter { $0.metric == experiment.metric }
                if measurements.isEmpty {
                    Text("No measurement has been recorded for this outcome. Add a performance snapshot on the published content to review it here.")
                        .font(DS.subheadline).foregroundStyle(DS.textSecondary)
                }
                ForEach(measurements) { measurement in
                    HStack {
                        Text(measurement.value.formatted()).monospacedDigit().font(DS.headline)
                        Text(measurement.platform).font(DS.subheadline)
                        Spacer()
                        Text(measurement.ageHours.map { "Day \(Int($0 / 24))" } ?? "Age unknown").font(DS.caption).foregroundStyle(DS.textMuted)
                    }
                }
            }
            SwipeLabLabeledEditor(title: "What else changed?", text: Binding(get: { model.state.experiments.first { $0.id == experiment.id }?.resultNote ?? "" }, set: { value in
                guard let index = model.state.experiments.firstIndex(where: { $0.id == experiment.id }) else { return }
                model.state.experiments[index].resultNote = value
                model.state.experiments[index].updatedAt = Date()
                model.scheduleSave()
            }), minHeight: 64)
            Button("Review observed results") { model.reviewOutcome(experiment) }
                .disabled(model.isRunning || model.linkedContent(for: experiment).flatMap { model.outcomeSnapshots[$0.uuid] }?.isEmpty != false)
            if let review = experiment.review {
                Text(.init(review)).font(DS.body).lineSpacing(5).textSelection(.enabled)
                if let finding = model.state.findings.first(where: { $0.id == experiment.principleID }) {
                    Button("Revise the principle…") { model.editingFinding = finding }
                }
            }
        }
    }
}

struct SwipeLabLabeledEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 100
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(title).font(DS.subheadline.weight(.medium)).foregroundStyle(DS.textSecondary)
            TextEditor(text: $text).font(DS.body).scrollContentBackground(.hidden)
                .padding(DS.space8).frame(minHeight: minHeight)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.border, lineWidth: 0.5))
                .accessibilityLabel(title)
        }
    }
}
