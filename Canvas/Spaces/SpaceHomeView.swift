import SwiftUI

struct SpaceHomeView: View {
    @State private var model: SpaceHomeModel
    @State private var editorHeight: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceID: String) { _model = State(initialValue: SpaceHomeModel(spaceID: spaceID)) }
    init(model: SpaceHomeModel) { _model = State(initialValue: model) }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                manuscript
                if geometry.size.width > 980, model.showingMaterials {
                    Divider().overlay(DS.borderSubtle)
                    SpaceHomeMaterials(model: model)
                        .frame(width: 300)
                        .padding(.top, SpaceChromeMetrics.contentTopInset + DS.space24)
                }
            }
            .background(DS.bg)
            .sheet(isPresented: $model.showingMaterialPicker) { SpaceMaterialPicker(spaceID: model.spaceID) }
            .task { await model.start() }
            .onDisappear { Task { await model.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.canvasBlocksChanged"))) { _ in
                Task { await model.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .contentCalendarNeedsReload)) { _ in
                Task { await model.load() }
            }
        }
    }

    private var manuscript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space32) {
                SpaceHomeHeading(model: model)
                if let error = model.errorMessage { errorRow(error) }
                if model.isLoaded { workingDocument } else { skeleton }
                if !model.questions.isEmpty || model.lastSession != nil { researchSection }
                if !model.outputs.isEmpty { outputsSection }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, DS.space32)
            .padding(.top, SpaceChromeMetrics.contentTopInset + DS.space32)
            .padding(.bottom, DS.space48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var workingDocument: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("WORKING NOTES").font(DS.smallCaps).foregroundStyle(DS.textMuted)
                Spacer()
                if !model.selectedText.isEmpty {
                    Button("Make idea", systemImage: "lightbulb") { model.makeIdea() }
                        .buttonStyle(.borderless).font(DS.caption).help("Create an idea from the selected text, linked to this Space")
                        .disabled(model.isCreatingIdea)
                }
                if model.isSaving { Text("Saving…").font(DS.caption).foregroundStyle(DS.textMuted) }
                Menu {
                    Button("Use as content idea", systemImage: "lightbulb") { model.makeIdea() }
                        .disabled(model.document.isEmpty || model.isCreatingIdea)
                    Button("Create a separate note", systemImage: "square.and.pencil") { model.createNote() }
                    Toggle("Show materials beside notes", isOn: Binding(get: { model.showingMaterials }, set: { model.showingMaterials = $0 }))
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Actions for your notes or selected text")
                .accessibilityLabel("Working notes actions")
            }
            CosmoDocumentEditor(
                document: Binding(get: { model.document }, set: { model.edited($0) }),
                placeholder: "What are you exploring? Keep your brief, observations and working understanding here.",
                onSelectionChanged: { model.selectedText = $0.text },
                onContentHeightChange: { editorHeight = max(240, $0) },
                editorTargetID: "space-home:\(model.spaceID)"
            )
            .frame(minHeight: editorHeight)
        }
    }

    private var researchSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CosmoSectionHeader(label: "OPEN QUESTIONS", detail: "\(model.questions.count)")
            if let session = model.lastSession {
                Button("Resume last inquiry", systemImage: "arrow.uturn.forward") { model.open(session) }
                    .buttonStyle(.borderless).font(DS.callout).foregroundStyle(DS.accent)
                    .help(session.title ?? "Continue your last inquiry")
            }
            VStack(spacing: 0) {
                ForEach(model.questions, id: \.uuid) { question in
                    SpaceHomeObjectRow(atom: question, subtitle: "Continue inquiry", action: { model.startInquiry(question: question) })
                }
            }
            .background(DS.surface, in: .rect(cornerRadius: 14))
        }
    }

    private var outputsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                CosmoSectionHeader(label: "OUTPUTS FROM THIS WORK", detail: "\(model.outputs.count)")
                Button("Open in Content", systemImage: "arrow.up.right") { model.openContent() }
                    .buttonStyle(.plain).font(DS.caption).foregroundStyle(DS.accent)
                    .help("Open the content made in this Space")
            }
            VStack(spacing: 0) {
                ForEach(model.outputs, id: \.uuid) { output in
                    SpaceHomeObjectRow(atom: output, subtitle: ContentProductionStage.of(output).title, action: { model.open(output) })
                }
            }
            .background(DS.surface, in: .rect(cornerRadius: 14))
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 4).fill(DS.glassSectionFill)
                    .frame(maxWidth: index == 3 ? 260 : .infinity).frame(height: 16)
            }
        }
        .accessibilityLabel("Loading working notes")
    }

    private func errorRow(_ message: String) -> some View {
        HStack {
            Text(message).font(DS.callout).foregroundStyle(DS.textSecondary)
            Spacer()
            Button("Retry") { Task { if model.isLoaded { await model.flush() } else { await model.load() } } }
                .buttonStyle(.plain).foregroundStyle(DS.accent)
        }
        .padding(DS.space16).background(DS.surface, in: .rect(cornerRadius: 14))
    }
}

private struct SpaceHomeHeading: View {
    let model: SpaceHomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text(model.name).font(DS.pageTitle).foregroundStyle(DS.text)
            Text("A place to develop your understanding.")
                .font(DS.body).foregroundStyle(DS.textSecondary)
            HStack(spacing: DS.space16) {
                Button("Start a note", systemImage: "square.and.pencil") { model.createNote() }
                Button("Ask a question", systemImage: "sparkle.magnifyingglass") { model.startInquiry() }
                Button("Add material", systemImage: "plus") {
                    model.showingMaterialPicker = true
                }
            }
            .buttonStyle(.plain).font(DS.callout).foregroundStyle(DS.accent)
            .frame(minHeight: 44)
        }
    }
}

private struct SpaceHomeMaterials: View {
    @Bindable var model: SpaceHomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack {
                Text("Materials").font(DS.headline).foregroundStyle(DS.text)
                Spacer()
                Button { SpaceViewStore.shared.select(.library, for: model.spaceID) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).help("Browse all materials").accessibilityLabel("Expand materials")
            }
            TextField("Search this Space", text: $model.materialQuery)
                .textFieldStyle(.plain).font(DS.callout)
                .padding(DS.space12).background(DS.glassSectionFill, in: .rect(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filteredMaterials, id: \.uuid) { atom in
                        SpaceHomeObjectRow(atom: atom, subtitle: atom.type.displayName, action: { model.openBeside(atom) })
                    }
                    if model.filteredMaterials.isEmpty {
                        Text(model.materialQuery.isEmpty ? "Add sources and notes to keep them beside your work." : "No matching materials. Try another search.")
                            .font(DS.callout).foregroundStyle(DS.textMuted).padding(.vertical, DS.space16)
                    }
                }
            }
        }
        .padding(.horizontal, DS.space20)
        .padding(.bottom, DS.space24)
    }
}

private struct SpaceHomeObjectRow: View {
    let atom: Atom
    let subtitle: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space12) {
                Image(systemName: atom.type.iconName).foregroundStyle(DS.textMuted).frame(width: 20)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(atom.title ?? "Untitled").font(DS.callout.weight(.medium)).foregroundStyle(DS.text).lineLimit(2)
                    Text(subtitle).font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(DS.caption2).foregroundStyle(DS.textMuted)
            }
            .padding(DS.space12).frame(minHeight: 56)
            .background(hovered ? DS.surfaceHover : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .help("Open \(atom.title ?? "Untitled")")
        .accessibilityElement(children: .combine)
    }
}
