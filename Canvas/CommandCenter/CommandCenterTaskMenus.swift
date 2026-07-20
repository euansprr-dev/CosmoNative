// Canvas/CommandCenter/CommandCenterTaskMenus.swift
// Command Center Menu V2
// Shared anchored composer host + schedule / repeat / habit task surfaces
// April 2026

import Observation
import SwiftUI

enum CommandCenterComposerHorizontalAlignment: Equatable {
    case leading
    case trailing
    case center
}

struct CommandCenterComposerAnchor: Equatable {
    var sourceRect: CGRect
    var alignment: CommandCenterComposerHorizontalAlignment = .leading
    var yOffset: CGFloat = 12
}

enum CommandCenterTaskDateTarget: Equatable {
    case dueDate
    case whenDate
    case deadline

    var title: String {
        switch self {
        case .dueDate: return "Schedule"
        case .whenDate: return "When"
        case .deadline: return "Deadline"
        }
    }
}

enum CommandCenterScheduleSelection: Equatable {
    case date(Date?)
    case someday
}

enum CommandCenterComposerRoute: Equatable {
    case batchSchedule(title: String, taskUUIDs: [String], anchor: CommandCenterComposerAnchor)
    case taskActions(task: TaskViewModel, anchor: CommandCenterComposerAnchor)
    case taskDate(
        task: TaskViewModel,
        target: CommandCenterTaskDateTarget,
        currentDate: Date?,
        anchor: CommandCenterComposerAnchor
    )
    case taskIntent(task: TaskViewModel, currentIntentUUID: String?, anchor: CommandCenterComposerAnchor)
    case taskHabit(task: TaskViewModel, currentHabitUUID: String?, anchor: CommandCenterComposerAnchor)
    case intentEditor(intent: IntentDefinition?, anchor: CommandCenterComposerAnchor)
    case intentLibrary(anchor: CommandCenterComposerAnchor)
    case habitEditor(habit: HabitDefinition?, anchor: CommandCenterComposerAnchor)
    case habitLibrary(anchor: CommandCenterComposerAnchor)

    var anchor: CommandCenterComposerAnchor {
        switch self {
        case .batchSchedule(_, _, let anchor),
             .taskActions(_, let anchor),
             .taskDate(_, _, _, let anchor),
             .taskIntent(_, _, let anchor),
             .taskHabit(_, _, let anchor),
             .intentEditor(_, let anchor),
             .intentLibrary(let anchor),
             .habitEditor(_, let anchor),
             .habitLibrary(let anchor):
            return anchor
        }
    }

    var taskUUID: String? {
        switch self {
        case let .taskActions(task, _),
             let .taskDate(task, _, _, _),
             let .taskIntent(task, _, _),
             let .taskHabit(task, _, _):
            return task.uuid
        case .batchSchedule,
             .intentEditor,
             .intentLibrary,
             .habitEditor,
             .habitLibrary:
            return nil
        }
    }
}

@MainActor
@Observable
final class CommandCenterComposerController {
    var route: CommandCenterComposerRoute?

    func present(_ route: CommandCenterComposerRoute) {
        withAnimation(ProMotionSprings.snappy) {
            self.route = route
        }
    }

    func dismiss() {
        withAnimation(ProMotionSprings.snappy) {
            route = nil
        }
    }

    func isShowingTaskAction(for taskUUID: String) -> Bool {
        guard case let .taskActions(task, _) = route else { return false }
        return task.uuid == taskUUID
    }
}

struct CommandCenterComposerHost: View {
    var viewModel: CommandCenterDashboardViewModel
    let composer: CommandCenterComposerController

    @State private var seriesDeleteTarget: TaskViewModel?
    @State private var seriesDeleteCompletionCount = 0

    var body: some View {
        GeometryReader { proxy in
            if let route = composer.route {
                let metrics = CommandCenterComposerMetrics(route: route, viewport: proxy.size)
                let position = composerPosition(
                    for: route.anchor,
                    metrics: metrics,
                    viewportBounds: proxy.frame(in: .global)
                )

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { composer.dismiss() }

                    // A fixed-height, top-aligned box: shells that fill keep
                    // their exact size, and content-hugging panels (the habit
                    // composer) still top out at the anchor — the position
                    // math centers this box, not the panel.
                    composerView(for: route)
                        .frame(width: metrics.width)
                        .frame(height: metrics.height, alignment: .top)
                        .position(position)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                            )
                        )
                        .zIndex(2)
                }
            }
        }
        .ignoresSafeArea(edges: .all)
        .allowsHitTesting(composer.route != nil)
        .onExitCommand(perform: composer.dismiss)
        .zIndex(100)
        .confirmationDialog(
            "Delete \"\(seriesDeleteTarget?.title ?? "")\"?",
            isPresented: Binding(
                get: { seriesDeleteTarget != nil },
                set: { if !$0 { seriesDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete series", role: .destructive) {
                guard let target = seriesDeleteTarget else { return }
                seriesDeleteTarget = nil
                Task { await viewModel.deleteTask(uuid: target.uuid) }
            }
            Button("Cancel", role: .cancel) { seriesDeleteTarget = nil }
        } message: {
            Text(SeriesDeleteCopy.message(completionCount: seriesDeleteCompletionCount))
        }
    }

    private func requestSeriesDelete(_ task: TaskViewModel) {
        Task {
            seriesDeleteCompletionCount = await viewModel.seriesCompletionCount(templateUUID: task.uuid)
            seriesDeleteTarget = task
        }
    }

    @ViewBuilder
    private func composerView(for route: CommandCenterComposerRoute) -> some View {
        switch route {
        case let .batchSchedule(title, taskUUIDs, _):
            CommandCenterScheduleComposer(
                title: title,
                subtitle: taskUUIDs.count == 1 ? "1 task" : "\(taskUUIDs.count) tasks",
                currentDate: nil,
                includeNilActions: true,
                showSomedayAction: true,
                onSelect: { selection in
                    applyBatchScheduleSelection(selection, taskUUIDs: taskUUIDs)
                    composer.dismiss()
                },
                onClose: composer.dismiss
            )
        case let .taskActions(task, _):
            CommandCenterTaskActionComposer(
                task: task,
                referenceDate: viewModel.selectedDate,
                currentHabit: viewModel.resolvedHabit(for: task),
                availableHabits: viewModel.availableHabitDefinitions,
                loadRecurrenceRule: { await viewModel.recurrenceRule(for: task) },
                onToggleCompletion: { toggleTaskCompletion(task) },
                onSelectSchedule: { selection in
                    applyTaskScheduleSelection(selection, task: task)
                },
                onApplyHabit: { habitUUID in
                    Task { await viewModel.applyHabit(habitUUID, to: task.uuid) }
                },
                onApplyRecurrence: { rule in
                    Task { await viewModel.setTaskRecurrence(uuid: task.uuid, rule: rule) }
                },
                onDelete: {
                    composer.dismiss()
                    if task.isOccurrence {
                        // Occurrence rows carry the template uuid — a plain delete would
                        // end the whole series, not just this day.
                        Task { _ = await viewModel.cancelOccurrence(task) }
                    } else {
                        Task { await viewModel.deleteTask(uuid: task.uuid) }
                    }
                },
                onDeleteSeries: task.isOccurrence ? {
                    composer.dismiss()
                    requestSeriesDelete(task)
                } : nil,
                onDismiss: composer.dismiss
            )
        case let .taskDate(task, target, currentDate, _):
            CommandCenterScheduleComposer(
                title: target.title,
                subtitle: task.title,
                currentDate: currentDate,
                includeNilActions: true,
                showSomedayAction: target == .dueDate,
                onSelect: { selection in
                    applyTaskDateSelection(task: task, target: target, selection: selection)
                    composer.dismiss()
                },
                onClose: composer.dismiss
            )
        case let .taskIntent(task, currentIntentUUID, _):
            CommandCenterIntentPickerComposer(
                viewModel: viewModel,
                taskTitle: task.title,
                currentIntentUUID: currentIntentUUID,
                onSelect: { intentUUID in
                    Task { await viewModel.updateTask(uuid: task.uuid, intentUUID: intentUUID) }
                    composer.dismiss()
                },
                onOpenLibrary: { anchor in
                    composer.present(.intentLibrary(anchor: anchor))
                },
                onClose: composer.dismiss
            )
        case let .intentEditor(intent, anchor):
            CommandCenterIntentComposer(
                intent: intent,
                onSave: { draft in
                    saveIntentDraft(draft, editing: intent)
                },
                onArchive: intent == nil ? nil : {
                    guard let id = intent?.id else { return }
                    Task { await viewModel.archiveIntent(id: id) }
                    composer.dismiss()
                },
                onMoveUp: intent == nil ? nil : {
                    guard let id = intent?.id else { return }
                    Task { await viewModel.moveIntent(id: id, direction: -1) }
                },
                onMoveDown: intent == nil ? nil : {
                    guard let id = intent?.id else { return }
                    Task { await viewModel.moveIntent(id: id, direction: 1) }
                },
                onOpenLibrary: {
                    composer.present(.intentLibrary(anchor: anchor))
                },
                onDismiss: composer.dismiss
            )
        case let .intentLibrary(anchor):
            CommandCenterIntentLibraryComposer(
                intents: viewModel.availableIntentDefinitions,
                onCreate: {
                    composer.present(.intentEditor(intent: nil, anchor: anchor))
                },
                onEdit: { intent in
                    composer.present(.intentEditor(intent: intent, anchor: anchor))
                },
                onClose: composer.dismiss
            )
        case let .taskHabit(task, currentHabitUUID, _):
            CommandCenterHabitPickerComposer(
                taskTitle: task.title,
                currentHabitUUID: currentHabitUUID,
                availableHabits: viewModel.availableHabitDefinitions,
                onSelect: { habitUUID in
                    Task { await viewModel.applyHabit(habitUUID, to: task.uuid) }
                    composer.dismiss()
                },
                onClose: composer.dismiss
            )
        case let .habitEditor(habit, anchor):
            CommandCenterHabitComposer(
                habit: habit,
                onSave: { draft in
                    saveHabitDraft(draft, editing: habit)
                },
                onArchive: habit?.isBuiltIn == true ? nil : {
                    guard let id = habit?.id else { return }
                    Task { await viewModel.archiveHabit(uuid: id) }
                    composer.dismiss()
                },
                onMoveUp: habit?.isBuiltIn == true ? nil : {
                    guard let id = habit?.id else { return }
                    Task { await viewModel.moveHabit(uuid: id, direction: -1) }
                },
                onMoveDown: habit?.isBuiltIn == true ? nil : {
                    guard let id = habit?.id else { return }
                    Task { await viewModel.moveHabit(uuid: id, direction: 1) }
                },
                onDisable: habit?.isBuiltIn == true ? {
                    guard let id = habit?.id else { return }
                    Task { await viewModel.setBuiltInHabitEnabled(id: id, enabled: false) }
                    composer.dismiss()
                } : nil,
                onOpenLibrary: {
                    composer.present(.habitLibrary(anchor: anchor))
                },
                availableIntents: viewModel.availableIntentDefinitions,
                onDismiss: composer.dismiss
            )
        case let .habitLibrary(anchor):
            CommandCenterHabitLibraryComposer(
                customHabits: viewModel.availableHabitDefinitions.filter { !$0.isBuiltIn && !$0.isArchived },
                builtInHabits: viewModel.builtInHabitToggles,
                onToggleBuiltIn: { id, enabled in
                    Task { await viewModel.setBuiltInHabitEnabled(id: id, enabled: enabled) }
                },
                onCreate: {
                    composer.present(.habitEditor(habit: nil, anchor: anchor))
                },
                onEdit: { habit in
                    composer.present(.habitEditor(habit: habit, anchor: anchor))
                },
                onClose: composer.dismiss
            )
        }
    }

    private func composerPosition(
        for anchor: CommandCenterComposerAnchor,
        metrics: CommandCenterComposerMetrics,
        viewportBounds: CGRect
    ) -> CGPoint {
        let inset: CGFloat = 24
        let minX = inset + metrics.width / 2
        let maxX = viewportBounds.width - inset - metrics.width / 2
        let sourceMinX = anchor.sourceRect.minX - viewportBounds.minX
        let sourceMidX = anchor.sourceRect.midX - viewportBounds.minX
        let sourceMaxX = anchor.sourceRect.maxX - viewportBounds.minX

        let preferredX: CGFloat
        switch anchor.alignment {
        case .leading:
            preferredX = sourceMinX + metrics.width / 2
        case .trailing:
            preferredX = sourceMaxX - metrics.width / 2
        case .center:
            preferredX = sourceMidX
        }

        let clampedX = min(max(preferredX, minX), maxX)
        let preferredY = anchor.sourceRect.maxY - viewportBounds.minY + anchor.yOffset + metrics.height / 2
        let minY = inset + metrics.height / 2
        let maxY = viewportBounds.height - inset - metrics.height / 2
        let clampedY = min(max(preferredY, minY), maxY)

        return CGPoint(x: clampedX, y: clampedY)
    }

    private func applyTaskDateSelection(
        task: TaskViewModel,
        target: CommandCenterTaskDateTarget,
        selection: CommandCenterScheduleSelection
    ) {
        switch target {
        case .dueDate:
            applyTaskScheduleSelection(selection, task: task)
        case .whenDate:
            guard case let .date(date) = selection else { return }
            if task.isOccurrence {
                // Date moves on an occurrence row are per-day overrides, never template rewrites.
                Task { await viewModel.rescheduleTask(task, toDate: date) }
            } else {
                Task { await viewModel.setWhenDate(taskUUID: task.uuid, date: date) }
            }
        case .deadline:
            guard case let .date(date) = selection else { return }
            Task { await viewModel.setDeadline(taskUUID: task.uuid, date: date) }
        }
    }

    private func applyTaskScheduleSelection(_ selection: CommandCenterScheduleSelection, task: TaskViewModel) {
        switch selection {
        case let .date(date):
            Task { await viewModel.rescheduleTask(task, toDate: date) }
        case .someday:
            Task { await viewModel.setSchedulingState(taskUUID: task.uuid, state: "someday") }
        }
    }

    private func applyBatchScheduleSelection(_ selection: CommandCenterScheduleSelection, taskUUIDs: [String]) {
        switch selection {
        case let .date(date):
            // Row ids: plain uuids reschedule the atom; "uuid#day" ids reschedule that
            // single recurring occurrence via an override.
            Task {
                for id in taskUUIDs {
                    await viewModel.rescheduleTaskRow(id: id, toDate: date)
                }
            }
        case .someday:
            Task {
                for taskUUID in taskUUIDs where !taskUUID.contains("#") {
                    await viewModel.setSchedulingState(taskUUID: taskUUID, state: "someday")
                }
            }
        }
    }

    private func toggleTaskCompletion(_ task: TaskViewModel) {
        Task {
            if task.isCompleted {
                _ = await viewModel.uncompleteTask(task)
            } else {
                let completed = await viewModel.completeTask(task)
                if completed {
                    viewModel.notifyCompletedTaskArrival()
                }
            }
        }
        composer.dismiss()
    }

    private func saveHabitDraft(_ draft: CommandCenterHabitEditorDraft, editing habit: HabitDefinition?) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        Task {
            if var existing = habit {
                existing.title = title
                existing.icon = draft.icon
                existing.accentColor = draft.accentColor
                existing.dailyTargetCount = draft.dailyTargetCount
                existing.goalType = draft.isTimeBased ? "minutes" : nil
                existing.dailyTargetMinutes = draft.isTimeBased ? draft.dailyTargetMinutes : nil
                existing.keywordTriggers = draft.keywords
                existing.mappedIntents = draft.mappedIntents.map(\.rawValue).sorted()
                existing.defaultIntentUUID = draft.defaultIntentUUID
                existing.allowManualCompletion = draft.allowManualCompletion
                await viewModel.updateHabit(existing)
            } else {
                await viewModel.createHabit(
                    title: title,
                    icon: draft.icon,
                    accentColor: draft.accentColor,
                    dailyTargetCount: draft.dailyTargetCount,
                    goalType: draft.isTimeBased ? "minutes" : nil,
                    dailyTargetMinutes: draft.isTimeBased ? draft.dailyTargetMinutes : nil,
                    keywordTriggers: draft.keywords,
                    mappedIntents: Array(draft.mappedIntents).sorted { $0.displayName < $1.displayName },
                    defaultIntentUUID: draft.defaultIntentUUID,
                    allowManualCompletion: draft.allowManualCompletion
                )
            }
        }

        composer.dismiss()
    }

    private func saveIntentDraft(_ draft: CommandCenterIntentEditorDraft, editing intent: IntentDefinition?) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        Task {
            if var existing = intent {
                existing.title = title
                existing.icon = draft.icon
                existing.accentColor = draft.accentColor
                existing.behaviorTemplate = draft.behaviorTemplate
                await viewModel.updateIntent(existing)
            } else {
                await viewModel.createIntent(
                    title: title,
                    icon: draft.icon,
                    accentColor: draft.accentColor,
                    behaviorTemplate: draft.behaviorTemplate
                )
            }
        }

        composer.dismiss()
    }
}

private struct CommandCenterComposerMetrics {
    let width: CGFloat
    let height: CGFloat
    let maxHeight: CGFloat

    init(route: CommandCenterComposerRoute, viewport: CGSize) {
        switch route {
        case .intentEditor:
            width = 420
            height = min(viewport.height - 48, 560)
        case .intentLibrary:
            width = 380
            height = min(viewport.height - 48, 500)
        case .habitEditor:
            // Compact menu-register panel; the composer hugs its content and
            // falls back to internal scrolling only when the viewport is short.
            width = 360
            height = min(viewport.height - 48, 620)
        case .habitLibrary:
            width = 340
            height = min(viewport.height - 48, 520)
        case .taskActions:
            // Menu-register panel: hugs its content per tab, so the box is a
            // ceiling — the Schedule tab's calendar is the tallest state.
            width = 360
            height = min(viewport.height - 48, 680)
        case .taskHabit, .taskIntent:
            width = 320
            height = min(viewport.height - 48, 380)
        case .taskDate, .batchSchedule:
            width = 360
            height = min(viewport.height - 48, 590)
        }

        maxHeight = height
    }
}

struct CommandCenterComposerTrigger<Label: View>: View {
    let composer: CommandCenterComposerController
    var alignment: CommandCenterComposerHorizontalAlignment = .leading
    let makeRoute: (CommandCenterComposerAnchor) -> CommandCenterComposerRoute
    @ViewBuilder let label: () -> Label

    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            let anchor = CommandCenterComposerAnchor(sourceRect: frame, alignment: alignment)
            composer.present(makeRoute(anchor))
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background(CommandCenterGlobalFrameReader(frame: $frame))
    }
}

struct CommandCenterGlobalFrameReader: View {
    @Binding var frame: CGRect

    var body: some View {
        GeometryReader { proxy in
            let nextFrame = proxy.frame(in: .global)
            Color.clear
                .onAppear { frame = nextFrame }
                .onChange(of: nextFrame) { _, updatedFrame in
                    frame = updatedFrame
                }
        }
    }
}

/// Chrome treatment for a Command Center composer popover.
/// `.codex` is the warm vellum + gilt-bracket identity (default, used by the intent/habit/
/// action composers). `.glass` adopts the Greenhouse Glass language of the Discover filter
/// dropdown — a translucent `CosmoGlassPanel` floating over the canvas.
enum CommandCenterComposerChrome {
    case codex
    case glass
}

struct CommandCenterComposerShell<Content: View>: View {
    let title: String
    let subtitle: String?
    var chrome: CommandCenterComposerChrome = .codex
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .padding(.horizontal, DS.space20)
                    .padding(.vertical, DS.space18)
            }
        }
        .modifier(CommandCenterComposerChromeModifier(chrome: chrome))
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var divider: some View {
        switch chrome {
        case .codex:
            AkashicSectionDivider()
                .padding(.top, 2)
        case .glass:
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)
                .opacity(0.7)
                .padding(.horizontal, DS.space20)
                .padding(.top, 2)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(title)
                    .font(DS.smallCaps)
                    .foregroundStyle(chrome == .glass ? DS.textSecondary : DS.giltMuted)
                    .tracking(1.8)

                if let subtitle {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption)
                    .foregroundStyle(chrome == .glass ? DS.textSecondary : DS.inkFaded)
                    .frame(width: 30, height: 30)
                    .background(chrome == .glass ? DS.glassInputFill : DS.vellumDeep, in: Circle())
                    .overlay(Circle().stroke(chrome == .glass ? DS.glassBorder : DS.sepiaBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close composer")
        }
        .padding(.horizontal, DS.space20)
        .padding(.top, DS.space18)
        .padding(.bottom, DS.space16)
    }

    private var subtitleFont: Font {
        switch chrome {
        case .codex: return .system(size: 16, weight: .regular, design: .serif)
        case .glass: return DS.headline
        }
    }
}

/// Applies the container chrome for a composer shell. `chrome` is a fixed per-presentation
/// config (never animated), so branching structure here is safe — no subtree rebuild churn.
private struct CommandCenterComposerChromeModifier: ViewModifier {
    let chrome: CommandCenterComposerChrome

    @ViewBuilder
    func body(content: Content) -> some View {
        switch chrome {
        case .codex:
            content
                .background(DS.vellum, in: .rect(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DS.sepiaBorder, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    GiltCornerBracket()
                        .stroke(DS.gilt, lineWidth: 0.8)
                        .frame(width: 13, height: 13)
                        .padding(10)
                }
                .shadow(color: .black.opacity(0.08), radius: 24, y: 16)
        case .glass:
            CosmoGlassPanel(
                role: .globalSidebar,
                cornerRadius: 20
            ) {
                content
            }
            .dsFloatingShadow()
        }
    }
}

/// The task menus' chassis in the assistant-menu register — the habit
/// composer / slash-menu grammar: an icon-tile header with the one 26pt close
/// circle, a gradient divider, a content column that hugs until the viewport
/// is short, and an optional pinned footer. Glass is applied as a BACKDROP
/// (`cosmoMenuChrome`) so the panel can change height as tabs swap without
/// latching the glass layer (see CosmoMenuChrome's invariant).
struct CommandCenterMenuShell<Content: View, Footer: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    // Static per instantiation (the Footer type never changes at runtime),
    // so the structural branch below can never animate a subtree rebuild.
    private var hasFooter: Bool { Footer.self != EmptyView.self }

    var body: some View {
        VStack(spacing: 0) {
            header
            CosmoGradientDivider()
            ViewThatFits(in: .vertical) {
                column
                ScrollView(.vertical, showsIndicators: false) { column }
            }
            if hasFooter {
                Rectangle()
                    .fill(DS.sepiaBorder.opacity(0.7))
                    .frame(height: 1)
                footer()
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space12)
            }
        }
        .cosmoMenuChrome(cornerRadius: 16)
        .onExitCommand(perform: onClose)
    }

    private var column: some View {
        content()
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space16)
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(subtitle == nil ? 2 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(DS.glassInputFill, in: Circle())
                    .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }
}

extension CommandCenterMenuShell where Footer == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            onClose: onClose,
            content: content,
            footer: { EmptyView() }
        )
    }
}

/// The assistant-menu section voice for the task menus (the habit composer's
/// label register — never the gilt small-caps codex voice).
private struct TaskMenuSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(DS.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(DS.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One selectable chip voice for the task menus (the habit composer's chip
/// chassis): soft accent wash + hairline when selected, warm input fill
/// otherwise, a hover lift on the pointer — never a solid fill (Law 11).
private struct TaskMenuSelectableChip<Content: View>: View {
    let isSelected: Bool
    let help: String
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .background(isSelected ? DS.accentSoft : DS.glassInputFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct CommandCenterScheduleComposer: View {
    let title: String
    let subtitle: String?
    let currentDate: Date?
    var includeNilActions: Bool = true
    var showSomedayAction: Bool = false
    let onSelect: (CommandCenterScheduleSelection) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandCenterMenuShell(icon: "calendar", title: title, subtitle: subtitle, onClose: onClose) {
            CommandCenterScheduleSection(
                currentDate: currentDate,
                includeNilActions: includeNilActions,
                showSomedayAction: showSomedayAction,
                onSelect: onSelect
            )
        }
    }
}

struct CommandCenterTaskActionComposer: View {
    let task: TaskViewModel
    /// The day the surrounding surface is viewing — overdue is judged from it
    /// so a task open on its own due day isn't branded "Overdue" here either.
    var referenceDate: Date = Date()
    let currentHabit: HabitDefinition?
    let availableHabits: [HabitDefinition]
    let loadRecurrenceRule: () async -> RecurrenceRule?
    let onToggleCompletion: () -> Void
    let onSelectSchedule: (CommandCenterScheduleSelection) -> Void
    let onApplyHabit: (String?) -> Void
    let onApplyRecurrence: (RecurrenceRule?) -> Void
    let onDelete: () -> Void
    /// Present only for recurring occurrence rows: `onDelete` removes just that occurrence,
    /// this offers deleting the whole series (behind a confirmation).
    var onDeleteSeries: (() -> Void)? = nil
    let onDismiss: () -> Void

    @State private var activeTab: ActionTab = .schedule
    /// The switcher's own selection. Split from `activeTab` so the thumb can
    /// tween inside the switcher's animated transaction while the content
    /// swap — which changes the glass panel's height — stays discrete (the
    /// glass-layer latch: see the habit composer's automation disclosure).
    @State private var switcherTab: ActionTab = .schedule
    @State private var recurrenceRule: RecurrenceRule?
    @State private var recurrencePreset: CommandCenterRepeatPreset = .weekly
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var isLoadingRecurrence = true

    private enum ActionTab: String, CaseIterable {
        case schedule
        case recurrence
        case habit

        var label: String {
            switch self {
            case .schedule: return "Schedule"
            case .recurrence: return "Repeat"
            case .habit: return "Habit"
            }
        }

        var icon: String {
            switch self {
            case .schedule: return "calendar"
            case .recurrence: return "repeat"
            case .habit: return "target"
            }
        }
    }

    var body: some View {
        CommandCenterMenuShell(
            icon: "checklist",
            title: task.title,
            onClose: onDismiss,
            content: {
                VStack(alignment: .leading, spacing: DS.space16) {
                    if hasMetadata {
                        metadataLine
                    }

                    CosmoSegmentedSwitcher(
                        options: ActionTab.allCases,
                        label: { $0.label },
                        icon: { $0.icon },
                        selection: tabBinding
                    )

                    tabContent
                }
            },
            footer: { footerRow }
        )
        .task {
            recurrenceRule = await loadRecurrenceRule()
            hydrateRepeatEditor()
            isLoadingRecurrence = false
        }
    }

    /// Routes the switcher's animated write to the thumb only: the content
    /// swap lands under a no-animation transaction so the panel height moves
    /// in one invalidation.
    private var tabBinding: Binding<ActionTab> {
        Binding(
            get: { switcherTab },
            set: { newValue in
                switcherTab = newValue
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { activeTab = newValue }
            }
        )
    }

    private var hasMetadata: Bool {
        task.dueInfo(asOf: referenceDate) != nil
            || recurrenceRule != nil
            || task.isRecurring
            || currentHabit != nil
    }

    private var metadataLine: some View {
        HStack(spacing: DS.space10) {
            if let dueInfo = task.dueInfo(asOf: referenceDate) {
                metaGlyph(text: dueInfo, icon: "calendar", color: task.isOverdue(asOf: referenceDate) ? DS.red : DS.textSecondary)
            }

            if recurrenceRule != nil || task.isRecurring {
                metaGlyph(text: recurrenceRule?.shortDisplayText ?? "Repeats", icon: "repeat", color: DS.accent)
            }

            if let currentHabit {
                metaGlyph(text: currentHabit.displayTitle, icon: currentHabit.icon, color: currentHabit.accent)
            }
        }
    }

    // MARK: Footer (pinned — the habit composer's register)

    private var footerRow: some View {
        HStack(spacing: DS.space10) {
            if onDeleteSeries != nil {
                seriesOverflowMenu
            } else {
                Button("Delete", action: onDelete)
                    .buttonStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.red)
                    .fixedSize()
                    .help("Delete task")
            }

            Spacer(minLength: 0)

            completeButton
        }
    }

    /// Occurrence rows carry two destructive depths — this day vs the whole
    /// series — so they fold behind the one overflow circle.
    private var seriesOverflowMenu: some View {
        Menu {
            Button("Remove Occurrence", systemImage: "trash") { onDelete() }
            Button("Delete Series…", systemImage: "trash.slash", role: .destructive) { onDeleteSeries?() }
        } label: {
            Image(systemName: "trash")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.red)
                .frame(width: 26, height: 26)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Remove this occurrence or delete the series")
        .accessibilityLabel("Delete options")
    }

    private var completeButton: some View {
        Button(action: onToggleCompletion) {
            HStack(spacing: DS.space6) {
                Image(systemName: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    .font(DS.caption.weight(.semibold))
                Text(task.isCompleted ? "Undo" : "Complete")
                    .font(DS.callout.weight(.semibold))
            }
            .foregroundStyle(task.isCompleted ? DS.text : DS.textOnAccent)
            .padding(.horizontal, DS.space16)
            .frame(height: 30)
            .background(task.isCompleted ? DS.glassInputFill : DS.accent, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(task.isCompleted ? DS.glassBorder : Color.clear, lineWidth: 0.5)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .help(task.isCompleted ? "Mark incomplete (⌘↩)" : "Complete task (⌘↩)")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .schedule:
            CommandCenterScheduleSection(
                currentDate: task.dueDate ?? task.whenDate,
                includeNilActions: true,
                showSomedayAction: true,
                onSelect: { selection in
                    onSelectSchedule(selection)
                    onDismiss()
                }
            )
        case .recurrence:
            repeatSection
        case .habit:
            CommandCenterHabitPickerSection(
                currentHabitUUID: currentHabit?.id,
                availableHabits: availableHabits,
                onSelect: { habitUUID in
                    onApplyHabit(habitUUID)
                    onDismiss()
                }
            )
        }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            if isLoadingRecurrence {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, DS.space16)
            } else {
                VStack(alignment: .leading, spacing: DS.space8) {
                    TaskMenuSectionLabel("CADENCE")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DS.space6)], spacing: DS.space6) {
                        ForEach(CommandCenterRepeatPreset.allCases, id: \.self) { preset in
                            repeatPresetButton(preset)
                        }
                    }
                }

                if recurrencePreset.requiresDaySelection {
                    VStack(alignment: .leading, spacing: DS.space8) {
                        TaskMenuSectionLabel("DAYS")
                        HStack(spacing: DS.space6) {
                            ForEach(DayOfWeek.allCases, id: \.self) { day in
                                repeatDayButton(day)
                            }
                        }
                    }
                }

                HStack(spacing: DS.space10) {
                    if recurrenceRule != nil || task.isRecurring {
                        Button("Stop repeating") {
                            onApplyRecurrence(nil)
                            onDismiss()
                        }
                        .buttonStyle(.plain)
                        .font(DS.callout)
                        .foregroundStyle(DS.red)
                        .help("Remove the repeat rule")
                    }

                    Spacer()

                    Button {
                        onApplyRecurrence(buildRule())
                        onDismiss()
                    } label: {
                        Text("Apply")
                            .font(DS.callout.weight(.semibold))
                            .foregroundStyle(DS.textOnAccent)
                            .padding(.horizontal, DS.space16)
                            .frame(height: 30)
                            .background(DS.accent, in: Capsule())
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .help("Apply the repeat rule")
                }
            }
        }
    }

    private func repeatPresetButton(_ preset: CommandCenterRepeatPreset) -> some View {
        TaskMenuSelectableChip(
            isSelected: recurrencePreset == preset,
            help: "Repeat \(preset.label.lowercased())",
            accessibilityLabel: "Repeat \(preset.label)"
        ) {
            recurrencePreset = preset
            if selectedDays.isEmpty {
                selectedDays = defaultDays(for: preset)
            }
        } content: {
            Text(preset.label)
                .font(DS.caption)
                .foregroundStyle(recurrencePreset == preset ? DS.text : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
        }
    }

    private func repeatDayButton(_ day: DayOfWeek) -> some View {
        let isSelected = selectedDays.contains(day)
        return TaskMenuSelectableChip(
            isSelected: isSelected,
            help: isSelected ? "Skip \(day.shortName)" : "Repeat on \(day.shortName)",
            accessibilityLabel: day.shortName
        ) {
            if isSelected {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        } content: {
            Text(day.shortName)
                .font(DS.caption)
                .foregroundStyle(isSelected ? DS.text : DS.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
        }
    }

    private func hydrateRepeatEditor() {
        guard let recurrenceRule else {
            recurrencePreset = .weekly
            selectedDays = defaultDays(for: .weekly)
            return
        }

        switch recurrenceRule.frequency {
        case .daily: recurrencePreset = .daily
        case .weekdays: recurrencePreset = .weekdays
        case .monthly, .yearly: recurrencePreset = .monthly
        case .weekly, .biweekly: recurrencePreset = .weekly
        case .custom: recurrencePreset = .custom
        }

        if let days = recurrenceRule.daysOfWeek {
            selectedDays = Set(days)
        } else {
            selectedDays = defaultDays(for: recurrencePreset)
        }
    }

    private func defaultDays(for preset: CommandCenterRepeatPreset) -> Set<DayOfWeek> {
        switch preset {
        case .weekdays:
            return Set(DayOfWeek.weekdays)
        case .daily, .monthly, .weekly, .custom:
            let weekday = Calendar.current.component(.weekday, from: task.dueDate ?? Date())
            return Set(DayOfWeek.allCases.filter { $0.rawValue == weekday })
        }
    }

    private func buildRule() -> RecurrenceRule {
        switch recurrencePreset {
        case .daily:
            return .daily()
        case .weekdays:
            return .weekdays()
        case .weekly:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .weekly)) : Array(selectedDays)
            return .weekly(on: orderedDays.sorted { $0.rawValue < $1.rawValue })
        case .monthly:
            let day = Calendar.current.component(.day, from: task.dueDate ?? Date())
            return .monthly(onDay: day)
        case .custom:
            let orderedDays = selectedDays.isEmpty ? Array(defaultDays(for: .custom)) : Array(selectedDays)
            return RecurrenceRule(
                frequency: .custom,
                interval: 1,
                daysOfWeek: orderedDays.sorted { $0.rawValue < $1.rawValue },
                dayOfMonth: nil,
                monthOfYear: nil,
                endCondition: .never
            )
        }
    }
}

struct CommandCenterIntentPickerComposer: View {
    var viewModel: CommandCenterDashboardViewModel
    let taskTitle: String
    let currentIntentUUID: String?
    let onSelect: (String?) -> Void
    let onOpenLibrary: (CommandCenterComposerAnchor) -> Void
    let onClose: () -> Void

    @State private var libraryButtonFrame: CGRect = .zero

    var body: some View {
        CommandCenterComposerShell(title: "INTENT", subtitle: taskTitle, onClose: onClose) {
            VStack(alignment: .leading, spacing: DS.space10) {
                Text("Choose the primary category this time should roll up under.")
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)

                intentRow(nil, presentation: viewModel.resolvedIntentPresentation(intentUUID: nil, legacyIntentRaw: nil))

                ForEach(viewModel.availableIntentDefinitions, id: \.id) { intent in
                    intentRow(intent.id, presentation: viewModel.resolvedIntentPresentation(intentUUID: intent.id, legacyIntentRaw: nil))
                }

                Button {
                    onOpenLibrary(.init(sourceRect: libraryButtonFrame, alignment: .trailing))
                } label: {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(DS.caption2)
                        Text("Manage intents")
                            .font(DS.callout)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.top, DS.space4)
                }
                .buttonStyle(.plain)
                .background(CommandCenterGlobalFrameReader(frame: $libraryButtonFrame))
            }
        }
    }

    private func intentRow(_ intentUUID: String?, presentation: ResolvedIntentPresentation) -> some View {
        let isSelected = currentIntentUUID == intentUUID || (intentUUID == nil && currentIntentUUID == nil)
        return Button {
            onSelect(intentUUID)
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: presentation.icon)
                    .font(DS.subheadline).fontWeight(.medium)
                    .foregroundStyle(presentation.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text(intentHintText(for: presentation))
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.caption2)
                        .foregroundStyle(presentation.accent)
                }
            }
            .padding(.vertical, DS.space8)
            .padding(.horizontal, DS.space10)
            .background(isSelected ? presentation.accent.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? presentation.accent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func intentHintText(for presentation: ResolvedIntentPresentation) -> String {
        switch presentation.behaviorTemplate {
        case .writeContent: return "Writing and drafting work"
        case .research: return "Reading, digging, and synthesis"
        case .studySwipes: return "Pattern review and swipe study"
        case .deepThink: return "Thinking, outlining, and shaping"
        case .review: return "Polishing and quality passes"
        case nil: return presentation.isUnassigned ? "Visible until you assign it." : "Categorization only"
        }
    }
}

struct CommandCenterIntentEditorDraft: Equatable {
    var title: String = ""
    var icon: String = "tag.fill"
    var accentColor: String = "2D6A4F"
    var behaviorTemplate: IntentBehaviorTemplate?

    init() {}

    init(intent: IntentDefinition) {
        title = intent.title
        icon = intent.icon
        accentColor = intent.accentColor
        behaviorTemplate = intent.behaviorTemplate
    }
}

struct CommandCenterIntentComposer: View {
    let intent: IntentDefinition?
    let onSave: (CommandCenterIntentEditorDraft) -> Void
    let onArchive: (() -> Void)?
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onOpenLibrary: (() -> Void)?
    let onDismiss: () -> Void

    @State private var draft: CommandCenterIntentEditorDraft

    init(
        intent: IntentDefinition?,
        onSave: @escaping (CommandCenterIntentEditorDraft) -> Void,
        onArchive: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onOpenLibrary: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.intent = intent
        self.onSave = onSave
        self.onArchive = onArchive
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onOpenLibrary = onOpenLibrary
        self.onDismiss = onDismiss
        _draft = State(initialValue: intent.map(CommandCenterIntentEditorDraft.init(intent:)) ?? CommandCenterIntentEditorDraft())
    }

    var body: some View {
        CommandCenterComposerShell(
            title: intent == nil ? "NEW INTENT" : "INTENT",
            subtitle: draft.title.isEmpty ? "Shape a category for your time" : draft.title,
            onClose: onDismiss
        ) {
            VStack(alignment: .leading, spacing: DS.space20) {
                composerSectionLabel("Identity")

                TextField("Writing", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, DS.space10)
                    .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.sepiaBorder, lineWidth: 0.5)
                    )

                HStack(spacing: DS.space10) {
                    ForEach(["tag.fill", "pencil.line", "magnifyingglass", "brain.head.profile", "eye", "bolt.fill"], id: \.self) { icon in
                        Button {
                            draft.icon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(DS.body).fontWeight(.medium)
                                .foregroundStyle(draft.icon == icon ? Color(hex: draft.accentColor) : DS.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(DS.vellumDeep, in: Circle())
                                .overlay(Circle().stroke(draft.icon == icon ? Color(hex: draft.accentColor).opacity(0.35) : DS.sepiaBorder, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: DS.space10) {
                    ForEach(["2D6A4F", "818CF8", "38BDF8", "FFD700", "A855F7", "4ADE80"], id: \.self) { color in
                        Button {
                            draft.accentColor = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(.white.opacity(draft.accentColor == color ? 0.9 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }

                composerSectionLabel("Behavior")
                VStack(alignment: .leading, spacing: DS.space8) {
                    behaviorRow(nil, title: "Categorization only", subtitle: "Use this only for reporting and organization.")
                    ForEach(IntentBehaviorTemplate.allCases, id: \.rawValue) { template in
                        behaviorRow(template, title: template.taskIntent.displayName, subtitle: behaviorHint(template))
                    }
                }

                HStack(spacing: DS.space10) {
                    Button(action: { onSave(draft) }) {
                        Text("Save intent")
                            .font(DS.callout)
                            .foregroundStyle(DS.accent)
                    }
                    .buttonStyle(.plain)

                    if let onOpenLibrary {
                        Button("Library", action: onOpenLibrary)
                            .buttonStyle(.plain)
                            .font(DS.callout)
                            .foregroundStyle(DS.textSecondary)
                    }

                    Spacer()

                    if let onMoveUp {
                        Button(action: onMoveUp) { Image(systemName: "arrow.up") }
                            .buttonStyle(.plain)
                    }
                    if let onMoveDown {
                        Button(action: onMoveDown) { Image(systemName: "arrow.down") }
                            .buttonStyle(.plain)
                    }
                    if let onArchive {
                        Button("Archive", action: onArchive)
                            .buttonStyle(.plain)
                            .foregroundStyle(DS.red)
                    }
                }
            }
        }
    }

    private func behaviorRow(_ template: IntentBehaviorTemplate?, title: String, subtitle: String) -> some View {
        let isSelected = draft.behaviorTemplate == template
        return Button {
            draft.behaviorTemplate = template
        } label: {
            HStack(spacing: DS.space10) {
                Circle()
                    .fill(isSelected ? Color(hex: draft.accentColor) : DS.borderSubtle)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text(subtitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                }
                Spacer()
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(isSelected ? Color(hex: draft.accentColor).opacity(0.08) : DS.vellumDeep, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color(hex: draft.accentColor).opacity(0.3) : DS.sepiaBorder, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func behaviorHint(_ template: IntentBehaviorTemplate) -> String {
        switch template {
        case .writeContent: return "Launches the writing flow."
        case .research: return "Routes into research work."
        case .studySwipes: return "Opens swipe-study mode."
        case .deepThink: return "Routes to thinking and outlining."
        case .review: return "Routes to review mode."
        }
    }
}

struct CommandCenterIntentLibraryComposer: View {
    let intents: [IntentDefinition]
    let onCreate: () -> Void
    let onEdit: (IntentDefinition) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandCenterComposerShell(title: "INTENT LIBRARY", subtitle: "Manage your time categories", onClose: onClose) {
            VStack(alignment: .leading, spacing: DS.space16) {
                if intents.isEmpty {
                    Text("No intents yet. Create one so tracked time lands somewhere real instead of a vague bucket.")
                        .font(DS.callout)
                        .foregroundStyle(DS.inkFaded)
                } else {
                    ForEach(intents, id: \.id) { intent in
                        Button {
                            onEdit(intent)
                        } label: {
                            HStack(spacing: DS.space10) {
                                Circle()
                                    .fill(intent.accent.opacity(0.14))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: intent.icon)
                                            .font(DS.callout).fontWeight(.medium)
                                            .foregroundStyle(intent.accent)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(intent.title)
                                        .font(DS.callout)
                                        .foregroundStyle(DS.text)
                                    Text(intent.behaviorTemplate?.taskIntent.displayName ?? "Categorization only")
                                        .font(DS.caption2)
                                        .foregroundStyle(DS.inkFaded)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(DS.caption2)
                                    .foregroundStyle(DS.inkFaded)
                            }
                            .padding(.horizontal, DS.space10)
                            .padding(.vertical, DS.space8)
                            .background(DS.vellumDeep, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.sepiaBorder, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: onCreate) {
                    HStack(spacing: DS.space6) {
                        Image(systemName: "plus")
                            .font(DS.caption2)
                        Text("New intent")
                            .font(DS.dateSerif)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.vertical, DS.space6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CommandCenterHabitPickerComposer: View {
    let taskTitle: String
    let currentHabitUUID: String?
    let availableHabits: [HabitDefinition]
    let onSelect: (String?) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandCenterMenuShell(icon: "target", title: "Habit", subtitle: taskTitle, onClose: onClose) {
            CommandCenterHabitPickerSection(
                currentHabitUUID: currentHabitUUID,
                availableHabits: availableHabits,
                onSelect: onSelect
            )
        }
    }
}

struct CommandCenterHabitPickerSection: View {
    let currentHabitUUID: String?
    let availableHabits: [HabitDefinition]
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            Text("Completions feed the linked habit's ring.")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .padding(.bottom, DS.space6)

            TaskMenuHabitRow(
                title: "No habit",
                icon: "slash.circle",
                tint: DS.textSecondary,
                isSelected: currentHabitUUID == nil,
                help: "Keep this task independent",
                action: { onSelect(nil) }
            )

            ForEach(availableHabits, id: \.id) { habit in
                TaskMenuHabitRow(
                    title: habit.displayTitle,
                    icon: habit.icon,
                    mark: habit.identityMark,
                    tint: habit.accent,
                    cadenceHint: cadenceHint(for: habit),
                    isSelected: currentHabitUUID == habit.id,
                    help: "Link to \(habit.displayTitle)",
                    action: { onSelect(habit.id) }
                )
            }
        }
    }

    private func cadenceHint(for habit: HabitDefinition) -> String {
        if habit.isTimeBased { return "\(habit.dailyTargetMinutes ?? 30)m/day" }
        return "\(habit.dailyTargetCount)×/day"
    }
}

/// One dense picker row in the assistant-menu grammar: the 20pt identity slot
/// (typed/keyword emoji first, picked SF icon in the habit's accent as
/// fallback — the HabitLibraryRow contract), medium title, mono cadence hint,
/// accent checkmark when linked, soft accent wash on hover.
private struct TaskMenuHabitRow: View {
    let title: String
    let icon: String
    var mark: String? = nil
    let tint: Color
    var cadenceHint: String? = nil
    let isSelected: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                Group {
                    if let mark {
                        Text(mark)
                            .font(.system(size: 13))
                    } else {
                        Image(systemName: icon)
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)

                Text(title)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let cadenceHint {
                    Text(cadenceHint)
                        .font(DS.caption.monospaced())
                        .foregroundStyle(DS.textMuted.opacity(0.8))
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.space10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isHovered ? DS.accent.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

struct CommandCenterScheduleSection: View {
    let currentDate: Date?
    var includeNilActions: Bool = true
    var showSomedayAction: Bool = false
    let onSelect: (CommandCenterScheduleSelection) -> Void

    @State private var manualInput = ""
    @State private var displayedMonth: Date

    init(
        currentDate: Date?,
        includeNilActions: Bool = true,
        showSomedayAction: Bool = false,
        onSelect: @escaping (CommandCenterScheduleSelection) -> Void
    ) {
        self.currentDate = currentDate
        self.includeNilActions = includeNilActions
        self.showSomedayAction = showSomedayAction
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: CommandCenterScheduleUtilities.startOfMonth(for: currentDate ?? Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            quickActions
            naturalLanguageField
            calendarSection

            if includeNilActions && currentDate != nil {
                HStack {
                    Spacer()
                    Button("Clear date") {
                        onSelect(.date(nil))
                    }
                    .buttonStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.red)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TaskMenuSectionLabel("QUICK")

            CosmoFlowLayout(spacing: DS.space8) {
                ForEach(quickChipModels) { model in
                    CommandCenterScheduleQuickChip(model: model) {
                        onSelect(model.selection)
                    }
                }
            }
        }
    }

    private var quickChipModels: [CommandCenterQuickChipModel] {
        var models: [CommandCenterQuickChipModel] = [
            CommandCenterQuickChipModel(title: "Today", systemImage: "sun.max", tint: DS.green, selection: .date(Date())),
            CommandCenterQuickChipModel(
                title: "Tomorrow",
                systemImage: "sunrise",
                tint: DS.orange,
                selection: .date(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
            ),
            CommandCenterQuickChipModel(
                title: "Weekend",
                systemImage: "sparkles",
                tint: DS.accent,
                selection: .date(CommandCenterScheduleUtilities.nextWeekendDate())
            ),
            CommandCenterQuickChipModel(
                title: "+1 Week",
                systemImage: "arrow.right",
                tint: DS.textSecondary,
                selection: .date(CommandCenterScheduleUtilities.nextWeekStart())
            )
        ]

        if includeNilActions {
            if showSomedayAction {
                models.append(CommandCenterQuickChipModel(title: "Someday", systemImage: "archivebox", tint: DS.giltMuted, selection: .someday))
            }
            models.append(CommandCenterQuickChipModel(title: "No Date", systemImage: "slash.circle", tint: DS.textMuted, selection: .date(nil)))
        }

        return models
    }

    private var naturalLanguageField: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TaskMenuSectionLabel("WHEN")

            TextField("tomorrow, next monday, apr 24", text: $manualInput)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(.horizontal, DS.space10)
                .frame(height: 30)
                .dsGlassInput(cornerRadius: 8)
                .help("Type a date in plain words and press Return")
                .onSubmit {
                    guard let parsed = CommandCenterScheduleUtilities.parseDateInput(manualInput) else { return }
                    displayedMonth = CommandCenterScheduleUtilities.startOfMonth(for: parsed)
                    onSelect(.date(parsed))
                }
        }
    }

    private var calendarSection: some View {
        CommandCenterMonthGrid(
            displayedMonth: $displayedMonth,
            selectedDate: currentDate,
            onSelectDate: { onSelect(.date($0)) }
        )
    }
}

/// A quick-reschedule pill in the Greenhouse Glass language — glass capsule, sans label,
/// tint-colored glyph for at-a-glance identity, and a tint hover ring (mirrors the Discover
/// `SwipeFilterChip`). `.lineLimit(1)` + `.fixedSize` guarantee the label never wraps mid-word.
private struct CommandCenterQuickChipModel: Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let tint: Color
    let selection: CommandCenterScheduleSelection
}

private struct CommandCenterScheduleQuickChip: View {
    let model: CommandCenterQuickChipModel
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Image(systemName: model.systemImage)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(model.tint)
                Text(model.title)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, DS.space10)
            .frame(height: 28)
            .background(isHovered ? DS.glassInputFillFocused : DS.glassInputFill, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isHovered ? model.tint.opacity(0.42) : DS.glassBorder, lineWidth: isHovered ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .help(model.title)
        .accessibilityLabel(model.title)
        .accessibilityAddTraits(.isButton)
    }
}

struct CommandCenterMonthGrid: View {
    @Binding var displayedMonth: Date
    let selectedDate: Date?
    let onSelectDate: (Date?) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(spacing: DS.space10) {
                monthNavButton(systemImage: "chevron.left", help: "Previous month") {
                    displayedMonth = CommandCenterScheduleUtilities.month(byAdding: -1, to: displayedMonth)
                }

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .frame(maxWidth: .infinity)

                monthNavButton(systemImage: "chevron.right", help: "Next month") {
                    displayedMonth = CommandCenterScheduleUtilities.month(byAdding: 1, to: displayedMonth)
                }
            }

            LazyVGrid(columns: columns, spacing: DS.space6) {
                ForEach(CommandCenterScheduleUtilities.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(DS.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(DS.textMuted)
                        .frame(maxWidth: .infinity)
                }

                ForEach(CommandCenterScheduleUtilities.days(for: displayedMonth), id: \.id) { day in
                    if let date = day.date {
                        TaskMenuDayCell(
                            date: date,
                            isCurrentMonth: day.isCurrentMonth,
                            isSelected: CommandCenterScheduleUtilities.matches(selectedDate, date),
                            action: { onSelectDate(date) }
                        )
                    } else {
                        Color.clear
                            .frame(height: 28)
                    }
                }
            }
        }
    }

    private func monthNavButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 24, height: 24)
                .background(DS.glassInputFill, in: Circle())
                .overlay(Circle().stroke(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One calendar day in the menu chip voice: soft accent wash + hairline when
/// selected, accent ink for today, a quiet fill on hover.
private struct TaskMenuDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)

        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(DS.caption)
                .fontWeight(isSelected || isToday ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(textColor(isToday: isToday))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(fillColor, in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? DS.accent.opacity(0.42) : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Schedule for \(date.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func textColor(isToday: Bool) -> Color {
        if isSelected { return DS.text }
        if isToday { return DS.accent }
        return isCurrentMonth ? DS.text : DS.textMuted.opacity(0.5)
    }

    private var fillColor: Color {
        if isSelected { return DS.accentSoft }
        if isHovered { return DS.glassInputFill }
        return Color.clear
    }
}

struct CommandCenterScheduleUtilities {
    struct DayCell: Identifiable {
        let id = UUID()
        let date: Date?
        let isCurrentMonth: Bool
    }

    static var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []

        guard !symbols.isEmpty else {
            return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        }

        let firstWeekdayIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[firstWeekdayIndex...]) + Array(symbols[..<firstWeekdayIndex])
    }

    static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func month(byAdding offset: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    static func days(for month: Date) -> [DayCell] {
        let calendar = Calendar.current
        let start = startOfMonth(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingSlots = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = Array(repeating: DayCell(date: nil, isCurrentMonth: false), count: leadingSlots)

        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: start)
            cells.append(DayCell(date: date, isCurrentMonth: true))
        }

        // Always fill a constant 6-week (42-cell) grid so the calendar — and therefore the
        // composer — keeps a stable height across months (matches Apple's graphical date
        // picker). Trailing empty cells render as invisible spacers, never a scroll.
        while cells.count < 42 {
            cells.append(DayCell(date: nil, isCurrentMonth: false))
        }

        return cells
    }

    static func matches(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    static func nextWeekendDate() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let saturday = DayOfWeek.saturday.rawValue
        let delta = weekday <= saturday ? saturday - weekday : (7 - weekday) + saturday
        return calendar.date(byAdding: .day, value: delta, to: today)
    }

    static func nextWeekStart() -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let monday = DayOfWeek.monday.rawValue
        let delta = ((7 - weekday) + monday) % 7
        let normalized = delta == 0 ? 7 : delta
        return calendar.date(byAdding: .day, value: normalized, to: today)
    }

    static func parseDateInput(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercase = trimmed.lowercased()
        if lowercase == "today" { return Date() }
        if lowercase == "tomorrow" {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }
        if lowercase == "next week" {
            return nextWeekStart()
        }
        if lowercase == "weekend" {
            return nextWeekendDate()
        }

        let weekdayMap: [String: DayOfWeek] = [
            "mon": .monday, "monday": .monday,
            "tue": .tuesday, "tues": .tuesday, "tuesday": .tuesday,
            "wed": .wednesday, "wednesday": .wednesday,
            "thu": .thursday, "thur": .thursday, "thurs": .thursday, "thursday": .thursday,
            "fri": .friday, "friday": .friday,
            "sat": .saturday, "saturday": .saturday,
            "sun": .sunday, "sunday": .sunday,
        ]

        if let weekday = weekdayMap[lowercase] {
            return nextDate(for: weekday)
        }

        let strippedNext = lowercase.replacingOccurrences(of: "next ", with: "")
        if let weekday = weekdayMap[strippedNext], lowercase.hasPrefix("next ") {
            return nextDate(for: weekday, allowingToday: false)
        }

        let formats = ["M/d", "M/d/yyyy", "MMM d", "MMMM d", "MMM d yyyy", "MMMM d yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return normalizedDate(date, for: format)
            }
        }

        return nil
    }

    private static func normalizedDate(_ date: Date, for format: String) -> Date {
        let calendar = Calendar.current
        if format.contains("yyyy") { return date }

        var components = calendar.dateComponents([.month, .day], from: date)
        components.year = calendar.component(.year, from: Date())
        let candidate = calendar.date(from: components) ?? date

        return candidate < calendar.startOfDay(for: Date())
            ? calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
            : candidate
    }

    private static func nextDate(for weekday: DayOfWeek, allowingToday: Bool = true) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let current = calendar.component(.weekday, from: today)
        var delta = weekday.rawValue - current
        if delta < 0 { delta += 7 }
        if delta == 0 && !allowingToday {
            delta = 7
        }
        return calendar.date(byAdding: .day, value: delta, to: today)
    }
}

private enum CommandCenterRepeatPreset: CaseIterable {
    case daily
    case weekdays
    case weekly
    case monthly
    case custom

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }

    var requiresDaySelection: Bool {
        switch self {
        case .weekly, .custom:
            return true
        case .daily, .weekdays, .monthly:
            return false
        }
    }
}

func composerSectionLabel(_ text: String) -> some View {
    HStack(spacing: DS.space8) {
        Text(text.uppercased())
            .font(DS.smallCaps)
            .foregroundStyle(DS.giltMuted)
            .tracking(1.4)
        Rectangle()
            .fill(DS.sepiaSubtle)
            .frame(height: 0.5)
    }
}

private func metaGlyph(text: String, icon: String, color: Color) -> some View {
    HStack(spacing: DS.space4) {
        Image(systemName: icon)
            .font(DS.caption2)
        Text(text)
            .font(DS.caption)
            .lineLimit(1)
    }
    .foregroundStyle(color)
}

#Preview("Schedule Composer") {
    CommandCenterScheduleComposer(
        title: "Schedule",
        subtitle: "Refine command center menus",
        currentDate: Date(),
        showSomedayAction: true,
        onSelect: { _ in },
        onClose: {}
    )
    .frame(width: 380, height: 520)
    .padding()
    .background(DS.bg)
}

#Preview("Task Action Composer") {
    CommandCenterTaskActionComposer(
        task: .previewTask(),
        currentHabit: .previewHabit(),
        availableHabits: [.previewHabit()],
        loadRecurrenceRule: { .weekly(on: [.monday, .wednesday, .friday]) },
        onToggleCompletion: {},
        onSelectSchedule: { _ in },
        onApplyHabit: { _ in },
        onApplyRecurrence: { _ in },
        onDelete: {},
        onDismiss: {}
    )
    .frame(width: 380, height: 480)
    .padding()
    .background(DS.bg)
}

#Preview("Habit Picker Composer") {
    CommandCenterHabitPickerComposer(
        taskTitle: "Write landing page",
        currentHabitUUID: HabitDefinition.previewHabit().id,
        availableHabits: [.previewHabit()],
        onSelect: { _ in },
        onClose: {}
    )
    .frame(width: 340, height: 420)
    .padding()
    .background(DS.bg)
}

extension HabitDefinition {
    static func previewHabit() -> HabitDefinition {
        HabitDefinition(
            id: "habit-writing",
            title: "Writing Habit",
            icon: "pencil.line",
            accentColor: "2D6A4F",
            dailyTargetCount: 3,
            keywordTriggers: ["write", "draft"],
            mappedIntents: [TaskIntent.writeContent.rawValue],
            defaultIntentUUID: "intent-writing",
            allowManualCompletion: true,
            sortOrder: 0,
            isBuiltIn: false,
            isArchived: false
        )
    }
}

extension TaskViewModel {
    static func previewTask() -> TaskViewModel {
        TaskViewModel(
            id: "task-preview",
            uuid: "task-preview",
            title: "Refine command center menus",
            body: "Bring the command-center overlays into the Atelier language.",
            projectUuid: nil,
            projectName: "CosmoOS",
            projectColor: DS.accent,
            dueDate: Date(),
            scheduledDate: Date(),
            scheduledTime: nil,
            estimatedMinutes: 45,
            priority: .high,
            isCompleted: false,
            completedAt: nil,
            intent: .writeContent,
            habitUUID: HabitDefinition.previewHabit().id,
            habitAssignmentSource: HabitAssignmentSource.manual.rawValue,
            linkedIdeaUUID: nil,
            linkedContentUUID: nil,
            linkedAtomUUID: nil,
            totalFocusMinutes: 32,
            sessionCount: 2,
            recurrenceParentUUID: nil,
            isRecurring: true,
            scheduledStart: nil,
            scheduledEnd: nil,
            manualSortOrder: nil,
            taskType: nil,
            energyLevel: nil,
            cognitiveLoad: nil,
            recommendationScore: 0,
            recommendationReason: nil,
            whenDate: Date(),
            deadline: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            timeOfDay: "morning",
            schedulingState: nil,
            headingUUID: nil,
            checklist: [],
            linkedAtoms: [],
            titleMentions: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
