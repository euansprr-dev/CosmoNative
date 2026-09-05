// A single companion experience, with native shells on Mac and iPhone.
import SwiftUI

private enum CompanionPage: String, CaseIterable, Identifiable {
    case journey = "Together", cast = "The cast", rituals = "Rituals", assistant = "Assistant"
    var id: Self { self }
}

struct CompanionHomeView: View {
    var focusIsActive = false
    var onFocus: () -> Void
    private var store: CompanionStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: CompanionPage = .journey
    @State private var showTutorial = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Explore your companion", selection: $page) {
                ForEach(CompanionPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space12)
            .onChange(of: page) { _, _ in CompanionFeedback.selection() }
            ScrollView {
                CompanionPageContent(page: page, focusIsActive: focusIsActive, onFocus: onFocus, onTutorial: { showTutorial = true })
                    .padding(DS.space24)
                    .frame(maxWidth: 660)
                    .frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .id(page)
            #if os(iOS)
            .refreshable { await store.hydrate() }
            #endif
        }
        .background(DS.bg)
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: page)
        .task { await store.hydrate() }
        .sheet(isPresented: $showTutorial) { CompanionTutorialView() }
    }
}

private struct CompanionPageContent: View {
    let page: CompanionPage
    let focusIsActive: Bool
    let onFocus: () -> Void
    let onTutorial: () -> Void
    private var store: CompanionStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            switch page {
            case .journey:
                CompanionHero()
                CompanionGrowthRow()
                CompanionFocusButton(isActive: focusIsActive, onFocus: onFocus)
                CompanionActivitySection()
                CompanionLearningRow(onTutorial: onTutorial)
            case .cast:
                CompanionCastSection()
            case .rituals:
                CompanionRitualsSection(onTutorial: onTutorial)
            case .assistant:
                CompanionAssistantLearningView()
            }
            if let error = store.errorMessage {
                Button { Task { await store.hydrate() } } label: {
                    Label(error + " Tap to retry.", systemImage: "arrow.clockwise")
                        .font(DS.caption).foregroundStyle(DS.textSecondary)
                        .frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(CompanionPressStyle()).help("Retry loading and syncing your companion")
            }
        }
    }
}

private struct CompanionHero: View {
    private var store: CompanionStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delighted = false
    @State private var greeting = false
    @State private var greetingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: DS.space8) {
            Button(action: greet) {
                CompanionHabitat(companion: store.companion, growth: store.growth, delighted: delighted)
                    .scaleEffect(delighted && !reduceMotion ? 1.035 : 1)
                    .rotationEffect(.degrees(delighted && !reduceMotion ? -3 : 0))
            }
            .buttonStyle(CompanionPressStyle())
            .help("Say hello to \(store.companion.name)")
            .accessibilityLabel("Say hello to \(store.companion.accessibilityDescription)")
            Text(store.companion.name).font(DS.pageTitle).foregroundStyle(DS.text)
            Text(greeting ? store.companion.greeting : store.companion.bio)
                .font(DS.callout).foregroundStyle(DS.textSecondary)
                .contentTransition(.opacity)
            Text("\(store.growth.shortTitle) · \(store.preferences.earnedDays) days of growing")
                .font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit()
                .padding(.top, DS.space4)
        }
        .frame(maxWidth: .infinity)
        .onDisappear { greetingTask?.cancel() }
    }

    private func greet() {
        CompanionFeedback.greet(store.companion)
        greetingTask?.cancel()
        withAnimation(reduceMotion ? nil : ProMotionSprings.bouncy) { delighted = true; greeting = true }
        greetingTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1800)) } catch { return }
            withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { delighted = false; greeting = false }
        }
    }
}

struct CompanionHabitat: View {
    let companion: Companion
    let growth: CompanionGrowth
    var delighted = false

    var body: some View {
        ZStack {
            Circle().fill(companion.tint.opacity(0.055)).frame(width: 196, height: 196)
            Circle().strokeBorder(companion.tint.opacity(0.10), lineWidth: 0.7).frame(width: 228, height: 228)
            Ellipse().fill(companion.tint.opacity(0.06)).frame(width: 168, height: 22).offset(y: 72)
            CompanionPortrait(companion: companion, growth: growth, size: 190, isDelighted: delighted)
            if growth.rawValue >= 1 {
                CompanionSparkle(color: companion.tint.opacity(0.5)).frame(width: 9, height: 9).offset(x: -96, y: -32)
            }
            if growth.rawValue >= 2 {
                CompanionSparkle(color: DS.gilt).frame(width: 12, height: 12).offset(x: 89, y: -60)
            }
        }
        .frame(height: 232)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct CompanionGrowthRow: View {
    private var store: CompanionStore { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.growth.title).font(DS.headline).foregroundStyle(DS.text)
                Spacer(minLength: DS.space8)
                Text("\(store.growth.rawValue + 1) / 4").font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit()
            }
            HStack(spacing: DS.space6) {
                ForEach(CompanionGrowth.allCases) { stage in
                    Capsule().fill(stage.rawValue <= store.growth.rawValue ? DS.accent.opacity(0.6) : DS.borderSubtle)
                        .frame(height: 4)
                }
            }.accessibilityHidden(true)
            Text(growthCopy).font(DS.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.space16).companionGroup()
        .accessibilityElement(children: .combine)
    }
    private var growthCopy: String {
        if let next = store.growth.next {
            return "\(max(0, next.threshold - store.preferences.earnedDays)) more active days to \(next.shortTitle.lowercased()). A task or saved focus time grows the whole garden. Rest days never take growth away."
        }
        return "All four forms, earned together. Your garden keeps every bit of growth. Keep making small discoveries."
    }
}

private struct CompanionFocusButton: View {
    let isActive: Bool
    let onFocus: () -> Void
    var body: some View {
        Button { CompanionFeedback.commit(); onFocus() } label: {
            HStack(spacing: DS.space8) {
                Image(systemName: isActive ? "timer" : "play.fill")
                Text(isActive ? "You already have a focus session" : "Focus together")
                Spacer(minLength: DS.space8)
                if !isActive { Text("25 min").font(DS.caption).monospacedDigit().opacity(0.8) }
            }
            .font(DS.callout.weight(.semibold)).foregroundStyle(DS.accent)
            .padding(DS.space16).frame(minHeight: 52)
            .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        }
        .buttonStyle(CompanionPressStyle()).disabled(isActive)
        .help("Start a 25-minute focus session (⌘Return)")
        .keyboardShortcut(.return, modifiers: .command)
    }
}

private struct CompanionActivitySection: View {
    private var store: CompanionStore { .shared }
    @State private var selectedDate: Date?
    private var day: CompanionDay? { store.snapshot.days.first { $0.date == selectedDate } ?? store.snapshot.today }
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: DS.space4)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CompanionSectionHeading(title: "LITTLE BY LITTLE", detail: "14 days")
            VStack(alignment: .leading, spacing: DS.space16) {
                if store.hasLoaded {
                    LazyVGrid(columns: columns, spacing: DS.space4) {
                        ForEach(store.snapshot.days) { day in
                            CompanionDayButton(day: day, selected: day.date == self.day?.date) {
                                CompanionFeedback.selection(); selectedDate = day.date
                            }
                        }
                    }
                    CompanionDayDetail(day: day)
                } else {
                    Text(store.errorMessage == nil ? "Your little moments are finding their way here." : "Your history will appear when your library is available.")
                        .font(DS.callout).foregroundStyle(DS.textMuted).frame(minHeight: 80)
                }
            }.padding(DS.space16).companionGroup()
        }
    }
}

private struct CompanionDayButton: View {
    let day: CompanionDay
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.space4) {
                Image(systemName: day.isActive ? "leaf.fill" : "circle.dotted")
                    .font(DS.callout).foregroundStyle(day.isActive ? DS.accent : DS.textMuted.opacity(0.4))
                Text(day.date, format: .dateTime.day()).font(DS.caption2).foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 48)
            .background(selected ? DS.accentSoft : .clear, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(CompanionPressStyle())
        .help(day.date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)), \(day.seconds / 60) minutes focused, \(day.tasks) tasks completed")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct CompanionDayDetail: View {
    let day: CompanionDay?
    var body: some View {
        if let day {
            VStack(alignment: .leading, spacing: DS.space6) {
                Text(Calendar.current.isDateInToday(day.date) ? "Today, together" : day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(DS.headline).foregroundStyle(DS.text)
                Text(day.isActive ? "\(duration) focused · \(day.tasks) \(day.tasks == 1 ? "task" : "tasks") finished" : "Room for a small beginning. Finish a task or save some focus time.")
                    .font(DS.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
            }.accessibilityElement(children: .combine)
        }
    }
    private var duration: String {
        let seconds = day?.seconds ?? 0
        return seconds > 0 && seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

private struct CompanionLearningRow: View {
    let onTutorial: () -> Void
    var body: some View {
        Button { CompanionFeedback.tap(); onTutorial() } label: {
            HStack(spacing: DS.space12) {
                Image(systemName: "wand.and.stars").font(DS.title2).foregroundStyle(DS.textSecondary)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text("Make a little magic").font(DS.headline).foregroundStyle(DS.text)
                    Text("Learn by doing. Create your first ritual.").font(DS.caption).foregroundStyle(DS.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(DS.caption).foregroundStyle(DS.textMuted)
            }.padding(DS.space16).frame(minHeight: 60).companionGroup()
        }
        .buttonStyle(CompanionPressStyle()).help("Open the interactive companion tutorial")
    }
}

private struct CompanionCastSection: View {
    private var store: CompanionStore { .shared }
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var previewGrowth: CompanionGrowth?
    @State private var previewExpression: CompanionExpression = .resting
    private var stage: CompanionGrowth { previewGrowth ?? store.growth }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Small friends.\nBig personalities.").font(DS.pageTitle).foregroundStyle(DS.text)
                Text("Twelve little worlds to grow with. Choose anyone; your progress stays with you.")
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
            Picker("Preview a growth form", selection: Binding(get: { stage }, set: { previewGrowth = $0; CompanionFeedback.selection() })) {
                ForEach(CompanionGrowth.allCases) { Text($0.shortTitle).tag($0) }
            }.pickerStyle(.menu).tint(DS.accent)
            Picker("Try an expression", selection: $previewExpression) {
                ForEach(CompanionExpression.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(DS.accent)
            Text(stage.rawValue > store.growth.rawValue ? "Previewing a future form · unlocks at \(stage.threshold) active days" : "\(stage.shortTitle) form · tap a friend to choose")
                .font(DS.caption).foregroundStyle(DS.textMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 150 : 100), spacing: DS.space8)], spacing: DS.space16) {
                ForEach(Companion.allCases) { companion in
                    CompanionCastTile(companion: companion, growth: stage, expression: previewExpression, selected: companion == store.companion) {
                        CompanionFeedback.greet(companion); store.select(companion)
                    }
                }
            }.padding(DS.space12).companionGroup()
            Text("Your companion lives on iPhone and Mac. Your choice, growth and rituals travel with your synced library.")
                .font(DS.caption).foregroundStyle(DS.textMuted)
        }
    }
}

private struct CompanionCastTile: View {
    let companion: Companion
    let growth: CompanionGrowth
    let expression: CompanionExpression
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.space4) {
                CompanionCharacterView(companion: companion, growth: growth, expression: expression, size: 86)
                Text(companion.name).font(DS.callout.weight(.semibold)).foregroundStyle(DS.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(companion.species.replacingOccurrences(of: "the ", with: ""))
                    .font(DS.caption2).foregroundStyle(DS.textMuted).lineLimit(1)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(DS.caption).foregroundStyle(selected ? DS.accent : .clear).padding(.top, DS.space4)
            }
            .padding(.vertical, DS.space8).frame(maxWidth: .infinity)
            .background(selected ? DS.accentSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        }
        .buttonStyle(CompanionPressStyle()).help("Choose \(companion.accessibilityDescription)")
        .accessibilityLabel("\(companion.accessibilityDescription), \(growth.shortTitle) form. \(companion.bio)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct CompanionRitualsSection: View {
    let onTutorial: () -> Void
    private var store: CompanionStore { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("Your rhythm.\nTheir little response.").font(DS.pageTitle).foregroundStyle(DS.text)
                Text("A ritual connects a real action to a companion moment. Make it yours, then change it whenever you like.")
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
            CompanionSectionHeading(title: "WHEN I…", detail: "\(store.preferences.rituals.filter(\.isEnabled).count) active")
            VStack(spacing: 0) {
                ForEach(store.preferences.rituals.sorted { $0.trigger.rawValue < $1.trigger.rawValue }) { ritual in
                    CompanionRitualRow(ritual: ritual)
                    if ritual.trigger == .focusFinished { Divider().overlay(DS.borderSubtle).padding(.horizontal, DS.space16) }
                }
            }.companionGroup()
            CompanionLearningRow(onTutorial: onTutorial)
            Text("Rituals respond to tasks you finish in Today or Command, and sessions you save in the app. Imported history grows your garden quietly. No background reminders are scheduled.")
                .font(DS.caption).foregroundStyle(DS.textMuted)
        }
    }
}

private struct CompanionRitualRow: View {
    let ritual: CompanionRitual
    private var store: CompanionStore { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Toggle(isOn: Binding(get: { ritual.isEnabled }, set: { value in
                CompanionFeedback.selection(); var next = ritual; next.isEnabled = value; store.setRitual(next)
            })) {
                Label(ritual.trigger.title, systemImage: ritual.trigger.icon)
                    .font(DS.headline).foregroundStyle(DS.text)
            }.tint(DS.accent).frame(minHeight: 44)
            Picker("Then", selection: Binding(get: { ritual.response }, set: { response in
                CompanionFeedback.selection(); var next = ritual; next.response = response; store.setRitual(next)
            })) {
                ForEach(CompanionResponse.allCases) { Text($0.title).tag($0) }
            }.font(DS.callout).tint(DS.textSecondary)
            Text(ritual.response.message).font(DS.caption).foregroundStyle(DS.textMuted)
        }.padding(DS.space16)
    }
}

struct CompanionSectionHeading: View {
    let title: String
    let detail: String
    var body: some View {
        HStack {
            Text(title).font(DS.smallCaps).foregroundStyle(DS.giltMuted)
            Spacer()
            Text(detail).font(DS.caption).foregroundStyle(DS.textMuted).monospacedDigit().contentTransition(.numericText())
        }.accessibilityElement(children: .combine)
    }
}

struct CompanionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.press, value: configuration.isPressed)
            .modifier(CompanionHover())
    }
}

private struct CompanionHover: ViewModifier {
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .brightness(hovered ? 0.025 : 0)
            .scaleEffect(hovered && !reduceMotion ? 1.01 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: hovered)
    }
}

extension View {
    @ViewBuilder func companionGroup() -> some View {
        #if os(iOS)
        self.dsGroupedContainer()
        #else
        self.dsGlassSection(cornerRadius: DS.radiusLarge)
        #endif
    }
}

@MainActor
enum CompanionFeedback {
    static func greet(_ companion: Companion) {
        #if os(iOS)
        Haptics.tap()
        Sound.companionFlourish(companion)
        #endif
    }
    static func tap() {
        #if os(iOS)
        Haptics.tap()
        #endif
    }
    static func selection() {
        #if os(iOS)
        Haptics.selection()
        #endif
    }
    static func commit() {
        #if os(iOS)
        Haptics.commit()
        #endif
    }
}
