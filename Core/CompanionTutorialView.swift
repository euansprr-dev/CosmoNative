import SwiftUI

struct CompanionTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var trigger: CompanionTrigger = .focusFinished
    @State private var response: CompanionResponse = .breathe
    @State private var previewed = false
    private var store: CompanionStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            CompanionTutorialHeader(step: step, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space24) {
                    CompanionTutorialIntroduction(step: step)
                    CompanionTutorialStage(step: step, trigger: $trigger, response: $response, previewed: $previewed)
                    CompanionTutorialFooter(step: step, previewed: previewed, onBack: back, onNext: advance)
                }.padding(DS.space24).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .id(step)
        }
        .background(DS.bg)
        #if os(macOS)
        .frame(width: 470, height: 690)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: step)
    }

    private func back() {
        CompanionFeedback.selection()
        step = max(0, step - 1)
        previewed = false
    }
    private func advance() {
        CompanionFeedback.commit()
        if step == 2 {
            store.setRitual(.init(trigger: trigger, response: response, isEnabled: true, updatedAt: .now), finishTutorial: true)
        }
        if step == 3 { dismiss() } else { step += 1; previewed = false }
    }
}

private struct CompanionTutorialHeader: View {
    let step: Int
    let onClose: () -> Void
    var body: some View {
        HStack {
            Text(step == 3 ? "Your ritual" : "A little magic · \(step + 1) of 3")
                .font(DS.headline).foregroundStyle(DS.text)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(DS.callout).foregroundStyle(DS.textSecondary).frame(width: 44, height: 44)
            }.buttonStyle(CompanionPressStyle()).help("Close tutorial").accessibilityLabel("Close tutorial")
                .keyboardShortcut(.cancelAction)
        }.padding(.horizontal, DS.space24).padding(.top, DS.space12)
    }
}

private struct CompanionTutorialIntroduction: View {
    let step: Int
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(titles[step]).font(DS.pageTitle).foregroundStyle(DS.text)
            Text(details[step]).font(DS.callout).foregroundStyle(DS.textSecondary)
        }
    }
    private var titles: [String] { ["Meet your little constant.", "Start with a real moment.", "Give it a little personality.", "A ritual, made by you."] }
    private var details: [String] { [
        "A companion keeps you company while you make things happen. Your tasks and saved focus time help the whole cast grow—on iPhone and Mac.",
        "Automations begin with a ‘when’. Choose the moment you want your companion to notice.",
        "Now choose the ‘then’. Try the response before you turn it on.",
        "The next matching action in the app will bring your companion to life. Change the response or turn it off anytime in Rituals."
    ] }
}

private struct CompanionTutorialStage: View {
    let step: Int
    @Binding var trigger: CompanionTrigger
    @Binding var response: CompanionResponse
    @Binding var previewed: Bool
    private var store: CompanionStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            CompanionHabitat(companion: store.companion, growth: store.growth, delighted: previewed || step == 3)
            switch step {
            case 0: greeting
            case 1: eventChoices
            case 2: responseChoices
            default: savedSummary
            }
        }
    }
    private var greeting: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Button {
                CompanionFeedback.greet(store.companion)
                withAnimation(reduceMotion ? nil : ProMotionSprings.bouncy) { previewed = true }
            } label: {
                Label(previewed ? store.companion.greeting : "Say hello to \(store.companion.name)", systemImage: "hand.wave")
                    .font(DS.headline).foregroundStyle(DS.accent).frame(maxWidth: .infinity).frame(minHeight: 48)
            }.buttonStyle(CompanionPressStyle()).help("Try a companion interaction")
            Text("Finish a task or save focus time on 3, 10 and 30 different days to discover new forms. Growth stays, even when you take a break.")
                .font(DS.caption).foregroundStyle(DS.textMuted)
        }
    }
    private var eventChoices: some View {
        VStack(spacing: 0) {
            ForEach(CompanionTrigger.allCases) { event in
                CompanionTutorialChoice(title: event.title, icon: event.icon, selected: trigger == event) {
                    CompanionFeedback.selection(); trigger = event
                }
            }
        }.companionGroup()
    }
    private var responseChoices: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Picker("Companion response", selection: $response) {
                ForEach(CompanionResponse.allCases) { Text($0.title).tag($0) }
            }.tint(DS.accent).frame(minHeight: 44)
                .onChange(of: response) { _, _ in previewed = false; CompanionFeedback.selection() }
            Button {
                CompanionFeedback.tap()
                withAnimation(reduceMotion ? nil : ProMotionSprings.bouncy) { previewed = true }
            } label: {
                Label("Try this ritual", systemImage: "play.circle")
                    .font(DS.headline).foregroundStyle(DS.accent).frame(maxWidth: .infinity).frame(minHeight: 48)
            }.buttonStyle(CompanionPressStyle()).help("Preview this ritual without changing activity")
            if previewed {
                Text(store.companion.reply(to: response)).font(DS.callout).foregroundStyle(DS.text)
                    .padding(DS.space16).frame(maxWidth: .infinity, alignment: .leading).companionGroup()
            }
            Text("Preview only. Your activity and timers stay as they are.").font(DS.caption).foregroundStyle(DS.textMuted)
        }
    }
    private var savedSummary: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Label("When \(trigger.title)", systemImage: trigger.icon)
            Label(response.title, systemImage: response.icon)
            Text("Enabled · on iPhone and Mac").font(DS.caption).foregroundStyle(DS.accent)
        }.font(DS.headline).foregroundStyle(DS.text)
            .padding(DS.space16).frame(maxWidth: .infinity, alignment: .leading).companionGroup()
    }
}

private struct CompanionTutorialChoice: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space12) {
                Image(systemName: icon).foregroundStyle(DS.textSecondary).accessibilityHidden(true)
                Text(title).foregroundStyle(DS.text)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? DS.accent : DS.textMuted).accessibilityHidden(true)
            }.font(DS.callout).padding(DS.space16).frame(minHeight: 56)
        }.buttonStyle(CompanionPressStyle()).help(title)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct CompanionTutorialFooter: View {
    let step: Int
    let previewed: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    var body: some View {
        HStack(spacing: DS.space16) {
            if step > 0 && step < 3 {
                Button("Back", action: onBack).font(DS.callout).foregroundStyle(DS.textSecondary)
                    .frame(minWidth: 44, minHeight: 48).buttonStyle(CompanionPressStyle()).help("Previous tutorial step")
            }
            Button(action: onNext) {
                Text(step == 3 ? "Make yourself at home" : step == 2 ? "Enable this ritual" : "Continue")
                    .font(DS.callout.weight(.semibold)).foregroundStyle(DS.accent)
                    .frame(maxWidth: .infinity).frame(minHeight: 48)
                    .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            }.buttonStyle(CompanionPressStyle()).help(step == 2 ? "Save and enable this ritual" : "Continue")
                .disabled((step == 0 || step == 2) && !previewed)
        }
    }
}

/// A local ritual's response; no timers, notifications or automatic task mutations.
struct CompanionMomentBanner: View {
    private var store: CompanionStore { .shared }
    var body: some View {
        if let response = store.moment {
            HStack(alignment: .center, spacing: DS.space12) {
                CompanionPortrait(companion: store.companion, growth: store.growth, size: 48, isDelighted: true)
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(store.companion.name).font(DS.headline).foregroundStyle(DS.text)
                    Text(store.companion.reply(to: response)).font(DS.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Button { CompanionFeedback.tap(); store.dismissMoment() } label: {
                    Image(systemName: "xmark").font(DS.caption).foregroundStyle(DS.textMuted).frame(width: 44, height: 44)
                }.buttonStyle(CompanionPressStyle()).help("Dismiss companion moment").accessibilityLabel("Dismiss companion moment")
            }
            .padding(DS.space12)
            .frame(maxWidth: 440)
            #if os(macOS)
            .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
            #else
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            #endif
            .accessibilityElement(children: .contain)
        }
    }
}
