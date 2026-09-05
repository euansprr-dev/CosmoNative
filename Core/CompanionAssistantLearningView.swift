import SwiftUI

/// The tutorial is a local rehearsal. It never submits a prompt or modifies an
/// existing conversation. The ritual lesson saves only when Enable is pressed.
struct CompanionAssistantLearningView: View {
    @AppStorage("companion.assistant.character") private var showsCharacter = true
    @AppStorage("companion.assistant.quietMotion") private var quietMotion = false
    @AppStorage("companion.assistant.opensAsPane") private var opensAsPane = false
    @AppStorage("companion.assistant.entrance") private var showsEntrance = true
    @State private var showGuide = false
    @State private var showRituals = false
    @State private var showStudio = false
    private var companion: CompanionStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("A familiar face.\nA capable assistant.").font(DS.pageTitle).foregroundStyle(DS.text)
                Text("\(companion.companion.name) is your way into Cosmo. Every character has the same assistant behind it. Choose the company you like.")
                    .font(DS.callout).foregroundStyle(DS.textSecondary)
            }
            preferences
            lessons
            Text("Your character, growth and rituals travel with your library. Appearance and movement settings stay on this device.")
                .font(DS.caption).foregroundStyle(DS.textMuted)
        }
        .sheet(isPresented: $showGuide) { CompanionAssistantGuide() }
        .sheet(isPresented: $showRituals) { CompanionTutorialView() }
        #if os(macOS)
        .sheet(isPresented: $showStudio) { CosmoAssistantStudioView { showStudio = false } }
        #endif
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Toggle("Show my companion", isOn: $showsCharacter)
                .help("Use your character as the assistant entrance. Turn off for a minimal symbol.")
            Toggle("Quiet movement", isOn: $quietMotion)
                .help("Keep expressions and growth, with still poses")
            #if os(macOS)
            Toggle("Open directly as a pane", isOn: $opensAsPane)
                .help("Open your existing conversation in the pane deck when you click the companion")
            Toggle("Show assistant entrance", isOn: $showsEntrance)
                .help("When hidden, open the assistant pane with ⌥A. Restore the entrance here at any time.")
            #endif
            Text("Cosmo stays available in either appearance. System Reduce Motion is always respected.")
                .font(DS.caption).foregroundStyle(DS.textMuted)
        }
        .font(DS.callout).tint(DS.accent)
        .padding(DS.space16).companionGroup()
        .onChange(of: showsCharacter) { _, _ in CompanionFeedback.selection() }
        .onChange(of: quietMotion) { _, _ in CompanionFeedback.selection() }
    }

    private var lessons: some View {
        VStack(spacing: 0) {
            lesson("Make room for an idea", detail: "Try opening and moving a conversation", icon: "bubble.left.and.bubble.right") { showGuide = true }
            Divider().overlay(DS.borderSubtle).padding(.horizontal, DS.space16)
            lesson("Make your first ritual", detail: "A real moment, a response you choose", icon: "leaf") { showRituals = true }
            #if os(macOS)
            Divider().overlay(DS.borderSubtle).padding(.horizontal, DS.space16)
            lesson("Build a skill", detail: "Teach Cosmo a repeatable way of working", icon: "square.stack.3d.up") { showStudio = true }
            #endif
        }.companionGroup()
    }

    private func lesson(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { CompanionFeedback.tap(); action() } label: {
            HStack(spacing: DS.space12) {
                Image(systemName: icon).foregroundStyle(DS.textSecondary).frame(width: 28)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(title).font(DS.headline).foregroundStyle(DS.text)
                    Text(detail).font(DS.caption).foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(DS.caption).foregroundStyle(DS.textMuted)
            }.padding(DS.space16).frame(minHeight: 60).contentShape(Rectangle())
        }.buttonStyle(CompanionPressStyle()).help(title)
    }
}

struct CompanionAssistantGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false
    @State private var isExpanded = false
    @State private var hasExpanded = false
    @State private var draft = "Help me make room for a good idea."
    private var companion: CompanionStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Make yourself at home").font(DS.headline)
                Spacer()
                Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(CompanionPressStyle()).keyboardShortcut(.cancelAction).help("Close the guide")
            }.padding(.horizontal, DS.space24).padding(.top, DS.space8)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    introduction
                    rehearsal
                    Text(hasExpanded ? "Your draft stays with the conversation. Closing chat keeps it, too." : "This is a practice space. Nothing here sends a message or changes your work.")
                        .font(DS.callout).foregroundStyle(DS.textSecondary)
                    #if os(macOS)
                    Text("Use @ to bring in context. Choose a skill for a repeatable task. The current document is always named above the conversation.")
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                    #else
                    Text("Use conversation history to return to an idea. Your draft stays on this device; conversations from your library can be continued here as a new chat.")
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                    #endif
                }.padding(DS.space24)
            }
        }
        .background(DS.bg).foregroundStyle(DS.text)
        #if os(macOS)
        .frame(width: 500, height: 610)
        #else
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        #endif
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isExpanded)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: isOpen)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("A conversation\nthat moves with you.").font(DS.pageTitle)
            #if os(macOS)
            Text("Open the companion, write a thought, then try the pane button. You can make room without starting over.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            #else
            Text("Tap your companion to open Cosmo. Expand the sheet when you want more room. On Mac, the same entrance opens a compact chat and a pane.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            #endif
        }
    }

    private var rehearsal: some View {
        VStack(alignment: .trailing, spacing: DS.space12) {
            if isOpen {
                VStack(alignment: .leading, spacing: DS.space12) {
                    HStack {
                        CompanionCharacterView(companion: companion.companion, growth: companion.growth, expression: .attentive, size: 44)
                        Text("Practice").font(DS.headline)
                        Spacer()
                        Button {
                            CompanionFeedback.tap()
                            isExpanded.toggle()
                            hasExpanded = true
                        } label: {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44)
                        }.buttonStyle(CompanionPressStyle()).help(isExpanded ? "Return to compact" : "Make more room")
                            .accessibilityLabel(isExpanded ? "Return to compact chat" : "Expand practice chat")
                    }
                    Text("Your draft, right where you left it.").font(DS.callout).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: 0)
                    TextField("Try writing something", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(DS.callout).lineLimit(2...4)
                        .padding(DS.space12).background(DS.bg, in: .rect(cornerRadius: 12))
                        .accessibilityLabel("Practice draft; never sent")
                }
                .padding(DS.space16)
                .frame(maxWidth: isExpanded ? .infinity : 330)
                .frame(height: isExpanded ? 248 : 200)
                .companionGroup()
            }
            Button {
                CompanionFeedback.tap()
                isOpen.toggle()
            } label: {
                HStack(spacing: DS.space8) {
                    Text(isOpen ? "Close practice chat" : "Try your companion").font(DS.callout).foregroundStyle(DS.textSecondary)
                    CompanionCharacterView(companion: companion.companion, growth: companion.growth, expression: isOpen ? .attentive : .resting, size: 64)
                }.contentShape(Rectangle())
            }.buttonStyle(CompanionPressStyle()).help("Open or close the practice conversation")
        }
        .frame(maxWidth: .infinity)
    }
}
