import SwiftUI

struct CompanionConversationLibrary: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var records: [CompanionConversationRecord] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            HStack {
                Text("Conversations").font(DS.title2)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(CompanionPressStyle()).keyboardShortcut(.cancelAction).help("Close conversation library")
            }
            Text("Continue an idea from your synced library. The original stays intact; tool receipts and edit reviews stay with it.")
                .font(DS.callout).foregroundStyle(DS.textSecondary)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error {
                        Button(error + " Retry") { Task { await load() } }.font(DS.callout).buttonStyle(CompanionPressStyle())
                    } else if loaded && records.isEmpty {
                        Text("Your saved conversations from Mac and iPhone will appear here.")
                            .font(DS.callout).foregroundStyle(DS.textMuted).padding(DS.space24)
                    }
                    ForEach(records) { record in
                        Button {
                            store.continuePortableConversation(record)
                            dismiss()
                        } label: {
                            HStack(spacing: DS.space12) {
                                Image(systemName: record.origin == "Mac" ? "desktopcomputer" : "iphone")
                                    .foregroundStyle(DS.textMuted).frame(width: 28)
                                VStack(alignment: .leading, spacing: DS.space4) {
                                    Text(record.title).font(DS.headline).foregroundStyle(DS.text).lineLimit(2)
                                    Text("\(record.origin) · \(record.messages.count) messages").font(DS.caption).foregroundStyle(DS.textMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").foregroundStyle(DS.textSecondary)
                            }.padding(DS.space16).contentShape(Rectangle())
                        }.buttonStyle(CompanionPressStyle()).help("Continue this conversation here")
                            .disabled(store.isProcessing)
                    }
                }.companionGroup()
            }
            if store.isProcessing { Text("Finish or stop the current response before switching conversations.").font(DS.caption).foregroundStyle(DS.textSecondary) }
        }
        .padding(DS.space24).frame(width: 480, height: 580).background(DS.bg).foregroundStyle(DS.text)
        .task { await load() }
    }

    private func load() async {
        do { records = try await CompanionConversationExchange.load(); error = nil }
        catch { self.error = "Couldn’t load your conversation library." }
        loaded = true
    }
}
