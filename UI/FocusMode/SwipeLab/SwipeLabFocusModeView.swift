import SwiftUI

/// One enduring reader identity. Conversation updates never recreate its player.
struct SwipeLabFocusModeView: View {
    @State private var model: SwipeLabViewModel
    @State private var breakpoint: StudyBreakpoint = .regular
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onClose: () -> Void

    init(atom: Atom, onClose: @escaping () -> Void) {
        _model = State(initialValue: SwipeLabViewModel(atom: atom))
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: DS.space8) {
                chrome
                WorkbenchShell(
                    panelsDisplace: breakpoint.panelsDisplace,
                    isLeadingShowing: model.showSources,
                    isTrailingShowing: model.showConversation && model.state.mode != .practise,
                    showsScrim: !breakpoint.panelsDisplace,
                    onScrimTap: { model.showSources = false; model.showConversation = false }
                ) {
                    SwipeLabSourcesPane(model: model, isOverlay: !breakpoint.panelsDisplace) {
                        if !breakpoint.panelsDisplace { model.showSources = false }
                    }
                    .frame(width: min(232, geometry.size.width - 48))
                } center: {
                    VStack(spacing: 0) {
                        statusBand
                        if model.isLoading {
                            ProgressView("Opening your study…").frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            workspace
                        }
                    }
                } trailing: {
                    SwipeLabConversationPane(model: model, isOverlay: !breakpoint.panelsDisplace)
                        .frame(width: min(344, geometry.size.width - 48))
                }
            }
            .background(SwipePageBackground())
            .onChange(of: geometry.size.width, initial: true) { _, width in
                let resolved = StudyBreakpoint(width: width)
                if resolved != breakpoint {
                    breakpoint = resolved
                    if !resolved.panelsDisplace { model.showSources = false; model.showConversation = false }
                }
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .atomsDidChange)) { _ in model.scheduleFreshnessCheck() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)) { _ in model.scheduleFreshnessCheck() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.SwipeFile.libraryDidChange)) { _ in model.scheduleFreshnessCheck() }
        .sheet(isPresented: $model.showSettings) { SwipeLabSettingsSheet(model: model) }
        .sheet(isPresented: $model.showComparisonPicker) {
            SwipeLabScopePicker(title: "Choose comparison posts", actionTitle: "Add comparison") { scope in
                Task { await model.addComparison(scope) }
            }
        }
        .sheet(isPresented: $model.showExperimentEditor) { SwipeLabExperimentSheet(model: model) }
        .sheet(item: $model.editingFinding) { finding in
            SwipeLabPrincipleEditor(finding: finding, clients: model.clients) { edited in
                Task { await model.saveEditedFinding(edited) }
            }
        }
        .tint(DS.accent)
        .background(keyboardCommands)
    }

    private var chrome: some View {
        CosmoChromeRow(centersAbsolutely: false) {
            CosmoChromeIsland {
                StudyToolbarButton(icon: "chevron.left", help: "Close Swipe Lab", action: onClose)
                StudyToolbarButton(icon: "sidebar.left", help: "Show sources", isActive: model.showSources) {
                    togglePanel(sources: true)
                }
                if breakpoint == .regular {
                    Text("Swipe Lab").font(DS.subheadline.weight(.semibold)).padding(.trailing, DS.space8)
                }
            }
        } center: {
            if breakpoint == .regular {
                CosmoChromeIsland {
                    ForEach(SwipeLabMode.allCases) { mode in
                        Button { model.setMode(mode) } label: {
                            Text(mode.title)
                                .font(DS.subheadline.weight(model.state.mode == mode ? .semibold : .regular))
                                .foregroundStyle(model.state.mode == mode ? DS.text : DS.textSecondary)
                                .padding(.horizontal, DS.space8).frame(height: 28)
                                .background(model.state.mode == mode ? DS.surfaceElevated : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.state.mode == mode ? .isSelected : [])
                    }
                }
            } else {
                Menu {
                    ForEach(SwipeLabMode.allCases) { mode in
                        Button { model.setMode(mode) } label: { Label(mode.title, systemImage: mode.icon) }
                    }
                } label: { Label(model.state.mode.title, systemImage: model.state.mode.icon).font(DS.subheadline) }
                .menuStyle(.borderlessButton).fixedSize()
            }
        } trailing: {
            CosmoChromeIsland {
                StudyToolbarButton(icon: "slider.horizontal.3", help: "Study scope, client and guidance") { model.showSettings = true }
                StudyToolbarButton(icon: "bubble.left.and.bubble.right", help: "Show study conversation", isActive: model.showConversation) {
                    togglePanel(sources: false)
                }
            }
        }
    }

    @ViewBuilder private var statusBand: some View {
        if let error = model.error {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(DS.orange)
                Text(error).font(DS.subheadline).textSelection(.enabled)
                Spacer(minLength: 0)
                Button("Dismiss") { model.dismissError() }.font(DS.subheadline)
            }
            .padding(DS.space12).background(DS.orangeSoft)
        }
        if model.hasUpdates {
            HStack {
                Text("Your sources have changed since this study.").font(DS.subheadline)
                Spacer(minLength: DS.space8)
                Button("Update study") { Task { await model.updateStudy() } }.disabled(model.isRunning)
            }
            .padding(DS.space12).background(DS.surfaceElevated)
        }
    }

    @ViewBuilder private var workspace: some View {
        switch model.state.mode {
        case .study: SwipeLabReaderPane(model: model)
        case .compare: SwipeLabComparePane(model: model)
        case .practise: SwipeLabPracticePane(model: model)
        case .notebook: SwipeLabNotebookPane(model: model)
        case .outcomes: SwipeLabOutcomesPane(model: model)
        }
    }

    private func togglePanel(sources: Bool) {
        withAnimation(reduceMotion ? nil : ProMotionSprings.focusTransition) {
            if sources {
                model.showSources.toggle()
                if !breakpoint.panelsDisplace { model.showConversation = false }
            } else {
                model.showConversation.toggle()
                if model.state.mode == .practise { model.setMode(.study) }
                if !breakpoint.panelsDisplace { model.showSources = false }
            }
        }
    }

    private var keyboardCommands: some View {
        Group {
            Button("Previous source") { model.step(-1) }.keyboardShortcut("[", modifiers: .command)
            Button("Next source") { model.step(1) }.keyboardShortcut("]", modifiers: .command)
            Button("Study conversation") { togglePanel(sources: false) }.keyboardShortcut("l", modifiers: [.command, .shift])
        }.hidden().accessibilityHidden(true)
    }
}

private struct SwipeLabSourcesPane: View {
    @Bindable var model: SwipeLabViewModel
    let isOverlay: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(model.state.scope.title).font(DS.headline).lineLimit(2)
                Text(model.currentSnapshotLabel).font(DS.caption).foregroundStyle(DS.textSecondary)
                TextField("Find a source", text: $model.sourceQuery).textFieldStyle(.roundedBorder)
            }.padding(DS.space16)
            Divider().overlay(DS.borderSubtle)
            ScrollView {
                LazyVStack(spacing: DS.space4) {
                    ForEach(model.visibleSources) { source in
                        Button { model.selectSource(source.id); onSelect() } label: {
                            sourceRow(source)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selectedSource?.id == source.id ? .isSelected : [])
                    }
                    ForEach(model.missingSources) { source in
                        Label("\(source.title) · unavailable", systemImage: "doc.badge.ellipsis")
                            .font(DS.caption).foregroundStyle(DS.textMuted).padding(DS.space12)
                    }
                }.padding(DS.space8)
            }
            Divider().overlay(DS.borderSubtle)
            VStack(alignment: .leading, spacing: DS.space8) {
                Label(model.clientName, systemImage: "person.crop.circle").font(DS.subheadline).foregroundStyle(DS.textSecondary)
                Button("Choose scope & client…") { model.showSettings = true }.font(DS.subheadline)
            }.padding(DS.space16)
        }
        .studyPanelSurface(edge: .leading, isOverlay: isOverlay)
    }

    private func sourceRow(_ source: SwipeLabSource) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: source.isComparison ? "rectangle.split.2x1" : "doc.text")
                .font(DS.subheadline).foregroundStyle(DS.textMuted).frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(source.title).font(DS.subheadline.weight(.medium)).foregroundStyle(DS.text).lineLimit(2)
                Text(source.creator.isEmpty ? source.platform : source.creator).font(DS.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                Text(model.coverage.failedIDs.contains(source.id) ? "Reading failed · retry the question" : source.duplicateOf != nil ? "Duplicate · excluded from counts" : source.units.isEmpty ? "Original text unavailable" : source.isComparison ? "Comparison · \(source.units.count) passages" : "\(source.units.count) passages")
                    .font(DS.caption2).foregroundStyle(DS.textMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if model.coverage.inspectedIDs.contains(source.id) {
                Image(systemName: "checkmark").font(DS.caption2).foregroundStyle(DS.accent).accessibilityLabel("Studied")
            }
        }
        .padding(DS.space12).frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedSource?.id == source.id ? DS.selectionWash : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(.rect)
    }
}

struct SwipeLabEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: icon).font(DS.displaySerif).foregroundStyle(DS.textMuted)
            Text(title).font(DS.heroTitleSerif).foregroundStyle(DS.text)
            Text(detail).font(DS.body).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.padding(DS.space32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
