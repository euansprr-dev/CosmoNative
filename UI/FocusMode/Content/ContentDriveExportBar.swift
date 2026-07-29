// CosmoOS/UI/FocusMode/Content/ContentDriveExportBar.swift
// "Send to Drive" — the export sheet's second destination, next to the clipboard.
//
// The sheet's whole grammar is *copy this, then go paste it somewhere*. Drive
// is the first destination that completes the gesture itself, so the bar has to
// answer three questions the copy buttons never had to: is there a connection,
// what format is this becoming, and where did it land. Everything else about
// the sheet stays exactly as it was.
//
// Re-sending the same draft updates the document already in Drive rather than
// making a second one — so the link the user pasted into a brief last week
// still shows the newest version. The ledger behind that is a local cache, so
// the worst case if it's ever lost is one duplicate file, never a wrong write.
// July 2026

import SwiftUI
import AppKit

struct ContentDriveExportBar: View {
    let atomUUID: String
    let title: String
    let platform: ExportPlatform
    let sections: [ExportSection]

    private let connection = GoogleDriveConnection.shared

    @AppStorage("googleDriveExportFormat") private var storedFormat = DriveExportFormat.googleDoc.rawValue
    @State private var phase: Phase = .idle
    @State private var lastSent: DriveExportRecord?

    private enum Phase: Equatable {
        case idle
        case sending
        case sent(id: String, link: String?)
        case failed(String)
    }

    private var format: DriveExportFormat {
        DriveExportFormat(rawValue: storedFormat) ?? .googleDoc
    }

    var body: some View {
        HStack(spacing: DS.space8) {
            switch connection.state {
            case .connected:
                formatMenu
                sendButton
                Spacer(minLength: DS.space8)
                resultLabel
            default:
                unavailableRow
            }
        }
        .task(id: taskKey) { await refresh() }
    }

    /// Re-resolve whenever the destination or the payload identity changes —
    /// a different platform is a different document in Drive.
    private var taskKey: String { "\(atomUUID)|\(platform.rawValue)|\(storedFormat)" }

    private func refresh() async {
        await connection.refreshState()
        phase = .idle
        lastSent = DriveExportLedger.shared.record(
            atomUUID: atomUUID, platform: platform, format: format
        )
    }

    // MARK: - Connected controls

    private var formatMenu: some View {
        Menu {
            ForEach(DriveExportFormat.allCases) { candidate in
                Button {
                    storedFormat = candidate.rawValue
                } label: {
                    Label(candidate.displayName, systemImage: candidate.icon)
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: format.icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(format.displayName)
                    .font(DS.caption)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .frame(minHeight: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(format.explanation)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: DS.space6) {
                if phase == .sending {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up.doc")
                        .font(DS.caption2)
                        .accessibilityHidden(true)
                }
                Text(sendButtonTitle).font(DS.caption)
            }
            .frame(minHeight: 24)
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(sections.isEmpty || phase == .sending)
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .help("Send this to \(connection.folderName) in Google Drive")
    }

    private var sendButtonTitle: String {
        if phase == .sending { return "Sending…" }
        return lastSent == nil ? "Send to Drive" : "Update in Drive"
    }

    @ViewBuilder
    private var resultLabel: some View {
        switch phase {
        case .sent(_, let link):
            HStack(spacing: DS.space6) {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                openLink(link)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(DS.caption2)
                .foregroundStyle(DS.orange)
                .lineLimit(2)
                .help(message)
        case .idle:
            if let lastSent {
                HStack(spacing: DS.space6) {
                    Text(lastSentDescription(lastSent))
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                    openLink(lastSent.webViewLink)
                }
            }
        case .sending:
            EmptyView()
        }
    }

    @ViewBuilder
    private func openLink(_ link: String?) -> some View {
        if let url = link.flatMap(URL.init(string:)) {
            Button("Open") { NSWorkspace.shared.open(url) }
                .buttonStyle(.link)
                .font(DS.caption2)
        }
    }

    private func lastSentDescription(_ record: DriveExportRecord) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "In Drive · \(formatter.localizedString(for: record.exportedAt, relativeTo: Date()))"
    }

    // MARK: - Not connected

    @ViewBuilder
    private var unavailableRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(unavailableMessage)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Button(connection.state == .connecting ? "Connecting…" : "Set up") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .buttonStyle(.link)
            .font(DS.caption2)
            .disabled(connection.state == .connecting)
            Spacer()
        }
    }

    private var unavailableMessage: String {
        switch connection.state {
        case .needsReconnect: return "Google Drive sign-in expired."
        case .connecting: return "Signing in to Google…"
        default: return "Send finished content straight to Google Drive."
        }
    }

    // MARK: - Send

    private func send() {
        guard !sections.isEmpty else { return }
        phase = .sending
        Task {
            do {
                let file = try await connection.export(
                    atomUUID: atomUUID,
                    title: title,
                    platform: platform,
                    sections: sections,
                    format: format
                )
                phase = .sent(id: file.id, link: file.webViewLink ?? file.openURL?.absoluteString)
                lastSent = DriveExportLedger.shared.record(
                    atomUUID: atomUUID, platform: platform, format: format
                )
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
