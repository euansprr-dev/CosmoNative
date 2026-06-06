import SwiftUI

struct CosmoInlineAssistantPaneView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CosmoInlineAssistantPaneHeader(onClose: onClose)
            Divider().overlay(DS.borderSubtle)
            CosmoInlineAssistantPaneMessages(store: store)
            CosmoInlineAssistantPaneComposer(store: store)
        }
        .background(DS.bg)
    }
}

private struct CosmoInlineAssistantPaneHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)

            Text("Cosmo Assistant")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close assistant pane")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private struct CosmoInlineAssistantPaneMessages: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        ScrollView {
            if store.paneMessages.isEmpty {
                CosmoInlineAssistantPaneEmptyState()
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(16)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.paneMessages) { message in
                        CosmoInlineAssistantPaneMessageRow(message: message)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct CosmoInlineAssistantPaneEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DS.textMuted)

            Text("Ask about the active workspace")
                .font(.headline)
                .foregroundStyle(DS.text)

            Text("Questions open here; edit requests stay reviewable on the canvas or document.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 260)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CosmoInlineAssistantPaneMessageRow: View {
    let message: CosmoInlineAssistantPaneMessage

    var body: some View {
        Text(message.content)
            .font(.system(size: 14))
            .foregroundStyle(textColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return DS.text
        case .assistant:
            return DS.textSecondary
        case .system:
            return DS.textMuted
        }
    }

    private var backgroundFill: Color {
        switch message.role {
        case .user:
            return DS.accentSoft
        case .assistant:
            return DS.surfaceCard
        case .system:
            return DS.surface
        }
    }

    private var borderColor: Color {
        message.role == .user ? DS.accent.opacity(0.16) : DS.borderSubtle
    }
}

private struct CosmoInlineAssistantPaneComposer: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask Cosmo", text: $store.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)

            Button {
                Task { await store.submit() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(sendFill, in: Circle())
                    .foregroundStyle(sendText)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
        .padding(16)
    }

    private var canSubmit: Bool {
        !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isProcessing
    }

    private var sendFill: Color {
        canSubmit ? DS.accent : DS.borderSubtle
    }

    private var sendText: Color {
        canSubmit ? DS.textOnAccent : DS.textMuted
    }
}
