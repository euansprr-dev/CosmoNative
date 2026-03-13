import SwiftUI

struct CommandCenterHabitEditorDraft: Equatable {
    var title: String = ""
    var icon: String = "repeat"
    var accentColor: String = "2D6A4F"
    var dailyTargetCount: Int = 1
    var allowManualCompletion: Bool = true
    var keywordInput: String = ""
    var mappedIntents: Set<TaskIntent> = []

    init() {}

    init(habit: HabitDefinition) {
        title = habit.title
        icon = habit.icon
        accentColor = habit.accentColor
        dailyTargetCount = habit.dailyTargetCount
        allowManualCompletion = habit.allowManualCompletion
        keywordInput = habit.keywordTriggers.joined(separator: ", ")
        mappedIntents = Set(habit.taskIntents)
    }

    var keywords: [String] {
        keywordInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CommandCenterHabitEditor: View {
    @Environment(\.dismiss) private var dismiss

    let habit: HabitDefinition?
    let onSave: (CommandCenterHabitEditorDraft) -> Void
    let onArchive: (() -> Void)?
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var draft: CommandCenterHabitEditorDraft
    @State private var hoveredIntent: TaskIntent?

    init(
        habit: HabitDefinition?,
        onSave: @escaping (CommandCenterHabitEditorDraft) -> Void,
        onArchive: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil
    ) {
        self.habit = habit
        self.onSave = onSave
        self.onArchive = onArchive
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        _draft = State(initialValue: habit.map(CommandCenterHabitEditorDraft.init(habit:)) ?? CommandCenterHabitEditorDraft())
    }

    private var isBuiltIn: Bool { habit?.isBuiltIn == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit == nil ? "New Habit" : draft.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text(isBuiltIn ? "Built-in habit" : "Custom habit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }

                Spacer()

                Circle()
                    .fill(Color(hex: draft.accentColor).opacity(0.16))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: draft.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: draft.accentColor))
                    )
            }

            Group {
                labeledField("Title") {
                    TextField("Habit name", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DS.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
                }
                .disabled(isBuiltIn)

                labeledField("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                        ForEach(habitIconOptions, id: \.self) { icon in
                            Button {
                                draft.icon = icon
                            } label: {
                                    Image(systemName: icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(draft.icon == icon ? DS.accent : DS.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(draft.icon == icon ? DS.accentSoft : DS.surface)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBuiltIn)
                        }
                    }
                }

                labeledField("Color") {
                    HStack(spacing: 8) {
                        ForEach(habitColorOptions, id: \.self) { color in
                            Button {
                                draft.accentColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: draft.accentColor == color ? 2 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(hex: color), lineWidth: draft.accentColor == color ? 1 : 0)
                                            .padding(-3)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBuiltIn)
                        }
                    }
                }

                labeledField("Daily target") {
                    Stepper(value: $draft.dailyTargetCount, in: 1...12) {
                        Text("\(draft.dailyTargetCount) completions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.text)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
                    .disabled(isBuiltIn)
                }

                labeledField("Keyword triggers") {
                    TextField("write, drafting, article", text: $draft.keywordInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DS.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
                        .disabled(isBuiltIn)
                }

                labeledField("Mapped intents") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(TaskIntent.allCases.filter { $0 != .general && $0 != .custom }, id: \.self) { intent in
                            Button {
                                if draft.mappedIntents.contains(intent) {
                                    draft.mappedIntents.remove(intent)
                                } else {
                                    draft.mappedIntents.insert(intent)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: intent.iconName)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(intent.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(draft.mappedIntents.contains(intent) ? DS.textOnAccent : DS.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(draft.mappedIntents.contains(intent) ? DS.accent : DS.surface)
                                )
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) {
                                if hoveredIntent == intent {
                                    intentHint(intent)
                                        .offset(y: -42)
                                        .transition(.opacity)
                                }
                            }
                            .onHover { isHovering in
                                hoveredIntent = isHovering ? intent : (hoveredIntent == intent ? nil : hoveredIntent)
                            }
                            .disabled(isBuiltIn)
                        }
                    }
                }
            }

            Toggle(isOn: $draft.allowManualCompletion) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow manual check-ins")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                    Text("Lets you tap the habit card directly when there is no task.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }
            }
            .toggleStyle(.switch)
            .tint(DS.accent)
            .disabled(isBuiltIn)

            if !isBuiltIn, habit != nil {
                HStack(spacing: 8) {
                    utilityButton("Up", icon: "arrow.up") { onMoveUp?() }
                    utilityButton("Down", icon: "arrow.down") { onMoveDown?() }

                    Spacer()

                    utilityButton("Archive", icon: "archivebox", tint: DS.red) {
                        onArchive?()
                    }
                }
            }

            HStack {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

                Spacer()

                if !isBuiltIn {
                    Button {
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text(habit == nil ? "Create Habit" : "Save Changes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.textOnAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(DS.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 32, y: 16)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundColor(DS.textMuted)
            content()
        }
    }

    private func utilityButton(_ title: String, icon: String, tint: Color = DS.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.surface))
        }
        .buttonStyle(.plain)
    }

    private func intentHint(_ intent: TaskIntent) -> some View {
        Text(intentHintText(for: intent))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DS.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
    }

    private func intentHintText(for intent: TaskIntent) -> String {
        switch intent {
        case .writeContent:
            return "Writing and drafting tasks"
        case .research:
            return "Reading, digging, and source work"
        case .studySwipes:
            return "Swipe study and pattern review"
        case .deepThink:
            return "Thinking, outlining, and synthesis"
        case .review:
            return "Reviewing an atom or finished work"
        case .general:
            return "General tasks"
        case .custom:
            return "Custom workflow routing"
        }
    }

    private let habitIconOptions = [
        "repeat",
        "brain.head.profile",
        "book.fill",
        "paintbrush.fill",
        "heart.fill",
        "pencil.line",
        "waveform.path.ecg",
        "figure.walk",
        "sparkles",
        "bolt.fill",
        "leaf.fill",
        "figure.mind.and.body",
    ]

    private let habitColorOptions = [
        "2D6A4F",
        "5B84B0",
        "7B7EC0",
        "C4A870",
        "DC3545",
        "38B764",
        "D97706",
        "8B6BAB",
    ]
}
