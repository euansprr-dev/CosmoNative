// CosmoOS/UI/FocusMode/Content/ContentShipSheet.swift
// Ship & measure: the export composer (per-platform, copy-perfect, zero LLM)
// and the keyboard-first performance entry sheet for published posts.
// July 2026

import SwiftUI

// MARK: - Export Composer

struct ContentExportSheet: View {
    let atom: Atom
    let draft: String
    let onClose: () -> Void

    @State private var platform: ExportPlatform = .xThread
    @State private var copiedIndex: Int?
    @State private var copiedAll = false

    private var sections: [ExportSection] {
        ContentExportFormatter.format(draft, for: platform)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            picker
            Divider().overlay(DS.borderSubtle)
            sectionList
            Divider().overlay(DS.borderSubtle)
            footer
        }
        .frame(width: 640, height: 560)
        .background(DS.bg)
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "paperplane")
                .font(DS.body.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Export")
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
            .accessibilityLabel("Close export")
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ExportPlatform.allCases) { candidate in
                    Button {
                        platform = candidate
                        copiedIndex = nil
                        copiedAll = false
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: candidate.icon)
                                .font(.system(size: 10))
                            Text(candidate.displayName)
                                .font(DS.caption)
                        }
                        .padding(.horizontal, DS.space10)
                        .padding(.vertical, 5)
                        .background(
                            platform == candidate ? DS.accentSoft : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(
                                platform == candidate ? DS.accent.opacity(0.4) : DS.borderSubtle,
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(platform == candidate ? DS.text : DS.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.space20)
            .padding(.vertical, DS.space10)
        }
    }

    private var sectionList: some View {
        ScrollView {
            VStack(spacing: DS.space10) {
                ForEach(sections) { section in
                    sectionCard(section)
                }
                if sections.isEmpty {
                    Text("Nothing to export yet — the draft is empty.")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .padding(.top, DS.space24)
                }
            }
            .padding(DS.space20)
        }
    }

    private func sectionCard(_ section: ExportSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack {
                Text(section.label)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                Spacer()
                if let limit = section.limit {
                    Text("\(section.text.count)/\(limit)")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(section.isOverLimit ? DS.orange : DS.textMuted)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(section.text, forType: .string)
                    copiedIndex = section.index
                    copiedAll = false
                } label: {
                    Label(
                        copiedIndex == section.index ? "Copied" : "Copy",
                        systemImage: copiedIndex == section.index ? "checkmark" : "doc.on.doc"
                    )
                    .font(DS.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedIndex == section.index ? DS.green : DS.textSecondary)
            }
            Text(section.text)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(section.isOverLimit ? DS.orange.opacity(0.4) : DS.borderSubtle, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            Text(sections.count == 1 ? "1 section" : "\(sections.count) sections")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button(copiedAll ? "Copied All" : "Copy All") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    ContentExportFormatter.combined(sections), forType: .string
                )
                copiedAll = true
                copiedIndex = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(sections.isEmpty)
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
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
            didSave = true
            history = await ContentPerfStore.snapshots(forContent: atom.uuid)
        }
    }
}
