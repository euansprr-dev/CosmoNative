// CosmoOS/UI/FocusMode/Content/ContentShipSheet.swift
// Ship & measure: the export sheet host (the panel lives in
// ContentExportPanel.swift — per-platform, copy-perfect, zero LLM) and the
// keyboard-first performance entry sheet for published posts.
// July 2026 · export reinvented September 2026

import SwiftUI

// MARK: - Export Composer

/// The sheet host (Content focus mode): the reinvented panel on the app
/// ground. The board presents the same panel as an in-page overlay.
struct ContentExportSheet: View {
    let atom: Atom
    let draft: String
    let onClose: () -> Void

    var body: some View {
        ContentExportPanel(atom: atom, draft: draft, onClose: onClose)
            .frame(width: 900, height: 640)
            .background(DS.bg)
    }
}

// MARK: - Performance Entry

struct ContentPerfEntrySheet: View {
    let atom: Atom
    let onClose: () -> Void

    @State private var platform: SocialPlatform = .instagram
    @State private var views = ""
    @State private var likes = ""
    @State private var comments = ""
    @State private var shares = ""
    @State private var saves = ""
    @State private var follows = ""
    @State private var didSave = false
    @State private var history: [ContentPerfSnapshot] = []
    @FocusState private var focusedField: Int?

    // URL pull: paste the live post and the numbers fill themselves.
    @State private var pullURL = ""
    @State private var pullState: PullState = .idle
    @State private var pulledPostURL: String?

    private enum PullState: Equatable {
        case idle
        case fetching
        case done(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            form
            if !history.isEmpty {
                Divider().overlay(DS.borderSubtle)
                historyList
            }
            Divider().overlay(DS.borderSubtle)
            footer
        }
        .frame(width: 460)
        .background(DS.bg)
        .task { history = await ContentPerfStore.snapshots(forContent: atom.uuid) }
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(DS.body.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Performance")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Text(atom.title?.isEmpty == false ? atom.title! : "Untitled")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, height: 26)
                    .background(DS.border.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close performance entry")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            pullRow

            Picker("Platform", selection: $platform) {
                ForEach(SocialPlatform.allCases, id: \.self) { candidate in
                    Text(candidate.displayName).tag(candidate)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            VStack(spacing: DS.space8) {
                metricRow("Views", value: $views, field: 0)
                metricRow("Likes", value: $likes, field: 1)
                metricRow("Comments", value: $comments, field: 2)
                metricRow("Shares", value: $shares, field: 3)
                metricRow("Saves", value: $saves, field: 4)
                metricRow("Follows gained", value: $follows, field: 5)
            }
        }
        .padding(DS.space20)
        .onAppear { focusedField = 0 }
    }

    /// Paste the live post's URL — Cosmo pulls the numbers through the same
    /// Apify pipeline the swipe file uses, and transcribes the post in the
    /// background so the system knows what the winning post actually said.
    @ViewBuilder
    private var pullRow: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(spacing: DS.space8) {
                TextField("Paste the live post URL", text: $pullURL)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.caption)
                    .onSubmit { pullFromPost() }
                Button {
                    pullFromPost()
                } label: {
                    if pullState == .fetching {
                        ProgressView().controlSize(.small)
                            .frame(width: 90)
                    } else {
                        Label("Pull numbers", systemImage: "square.and.arrow.down")
                            .font(DS.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(pullState == .fetching || pullURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Fetch views, likes and comments from the live post — and transcribe it in the background")
            }

            switch pullState {
            case .idle, .fetching:
                EmptyView()
            case .done(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    private func pullFromPost() {
        let trimmed = pullURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), pullState != .fetching else { return }
        pullState = .fetching
        Task {
            do {
                let perf = try await ContentPerfImportService.fetchPerf(url: url)
                platform = perf.platform
                views = "\(perf.views)"
                likes = "\(perf.likes)"
                comments = "\(perf.comments)"
                if let pulledShares = perf.shares { shares = "\(pulledShares)" }
                pulledPostURL = trimmed

                if let videoURL = perf.videoURL {
                    pullState = .done("\(perf.views.formatted()) views pulled · transcribing in background")
                    // Never-block: the transcript lands on the atom (and the
                    // client dossier) whenever it finishes, sheet open or not.
                    let caption = perf.caption
                    let duration = perf.duration
                    let uuid = atom.uuid
                    Task {
                        await ContentPerfImportService.transcribeAndAttach(
                            contentUuid: uuid,
                            videoURL: videoURL,
                            caption: caption,
                            duration: duration
                        )
                    }
                } else {
                    pullState = .done("\(perf.views.formatted()) views pulled")
                }
            } catch {
                pullState = .failed(error.localizedDescription)
            }
        }
    }

    private func metricRow(_ label: String, value: Binding<String>, field: Int) -> some View {
        HStack {
            Text(label)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 130, alignment: .leading)
            TextField("0", text: value)
                .textFieldStyle(.roundedBorder)
                .font(DS.callout.monospacedDigit())
                .focused($focusedField, equals: field)
                .onSubmit {
                    if field < 5 { focusedField = field + 1 } else { save() }
                }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text("PREVIOUS SNAPSHOTS")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
            ForEach(history.prefix(3)) { snapshot in
                HStack(spacing: DS.space8) {
                    Text(snapshot.capturedAtDate.formatted(date: .abbreviated, time: .omitted))
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                    Text("\(snapshot.views.formatted()) views · \(snapshot.engagement.formatted()) engagement")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
    }

    private var footer: some View {
        HStack {
            if didSave {
                Label("Recorded", systemImage: "checkmark.circle.fill")
                    .font(DS.caption)
                    .foregroundStyle(DS.green)
            }
            Spacer()
            Button("Record Snapshot") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(Int(views) == nil && Int(likes) == nil)
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
    }

    private func save() {
        let snapshot = ContentPerfSnapshot(
            id: nil,
            contentUuid: atom.uuid,
            platform: platform.rawValue,
            views: Int(views) ?? 0,
            likes: Int(likes) ?? 0,
            comments: Int(comments) ?? 0,
            shares: Int(shares) ?? 0,
            saves: Int(saves) ?? 0,
            followsGained: Int(follows) ?? 0,
            capturedAt: ISO8601.string(from: Date())
        )
        Task {
            try? await ContentPerfStore.record(snapshot)
            // A pulled URL is proof of publish — stamp the record (platform +
            // URL + time) in the same gesture instead of a second chore.
            // Logging performance never moves the post on the calendar: an
            // existing record keeps its date, a fresh one lands on the
            // scheduled day (the day the calendar already shows), never "now".
            if let pulledPostURL {
                let scheduled = atom.metadataValue(as: ContentMetadata.self)?
                    .scheduledAt.flatMap { ISO8601.date(from: $0) }
                await ContentPublishStore.markPublished(
                    atomUuid: atom.uuid,
                    platform: platform.rawValue,
                    url: pulledPostURL,
                    at: scheduled,
                    preservingExistingDate: true
                )
            }
            // Real numbers are taste signals: what the audience rewarded.
            let clientUuid = atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID
            await TasteStore.record(
                kind: .perfEntry,
                clientUuid: clientUuid,
                content: "\(atom.title ?? "Untitled") [\(platform.rawValue)]: \(snapshot.views) views, \(snapshot.engagement) engagement (\(String(format: "%.1f", snapshot.engagementRate * 100))%)"
            )
            await TasteDistiller.distillIfDue(clientUuid: clientUuid)
            // Real numbers also correct the client dossier's aggregates.
            await ClientPerfAggregator.recomputeForContent(atom)
            didSave = true
            history = await ContentPerfStore.snapshots(forContent: atom.uuid)
        }
    }
}
