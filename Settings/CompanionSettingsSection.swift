import SwiftUI

struct CompanionSettingsSection: View {
    private var store: CompanionStore { .shared }
    @State private var showCompanion = false

    var body: some View {
        Button { showCompanion = true } label: {
            HStack(spacing: DS.space16) {
                CompanionPortrait(companion: store.companion, growth: store.growth, size: 76)
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text("Life with \(store.companion.name)").font(DS.title2).foregroundStyle(DS.text)
                    Text("\(store.growth.shortTitle) · \(store.preferences.earnedDays) days of growing")
                        .font(DS.callout).foregroundStyle(DS.textSecondary)
                    Text("Meet the cast, discover new forms and make your own rituals.")
                        .font(DS.caption).foregroundStyle(DS.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DS.textMuted)
            }.padding(DS.space16).companionGroup()
        }
        .buttonStyle(CompanionPressStyle()).help("Open your companion’s world")
        .sheet(isPresented: $showCompanion) { CompanionPickerPopover() }
        .task { await store.hydrate() }
    }
}

struct CompanionPickerPopover: View {
    @Environment(\.dismiss) private var dismiss
    private var isActive: Bool { ActiveFocusSignal.shared.hasSession }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Companion").font(DS.title2).foregroundStyle(DS.text)
                Spacer()
                Button("Done") { dismiss() }
                    .font(DS.callout).foregroundStyle(DS.textSecondary).frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(CompanionPressStyle()).help("Close companion").keyboardShortcut(.cancelAction)
            }.padding(.horizontal, DS.space24).padding(.top, DS.space8)
            CompanionHomeView(focusIsActive: isActive) {
                guard DeepWorkSessionEngine.shared.activeSession == nil else { return }
                DeepWorkSessionEngine.shared.startSession(taskUUID: nil, taskTitle: "Focus together", intent: .general, plannedMinutes: 25)
                dismiss()
            }
        }.frame(width: 450, height: 720).background(DS.bg)
    }
}
