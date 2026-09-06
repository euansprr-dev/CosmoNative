// CosmoOS/UI/FocusMode/Content/ContentExportPanel.swift
// Export, reinvented (September 2026): one surface that answers "what does
// this piece become, and where does it go". Format pills wear real marks;
// the preview is a Files-grammar ledger of copy-perfect sections; the rail
// holds the destinations (clipboard, Google Drive) and the publication
// record. Publishing from the board no longer passes through here — this is
// the deliberate export, reached by Export… on a piece (⌘E).

import SwiftUI
import AppKit

// MARK: - Panel

struct ContentExportPanel: View {
    let atom: Atom
    let draft: String
    let onClose: () -> Void

    @State private var platform: ExportPlatform
    @State private var sections: [ExportSection] = []
    @State private var copiedSection: Int?
    @State private var copiedAll = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var publishURL = ""
    @State private var records: [ContentPublishRecord]
    @State private var publishing = false
    @FocusState private var urlFocused: Bool

    init(atom: Atom, draft: String, onClose: @escaping () -> Void) {
        self.atom = atom
        self.draft = draft
        self.onClose = onClose
        let meta = atom.metadataValue(as: ContentAtomMetadata.self)
        _platform = State(initialValue: ExportPlatform.suggested(
            platform: meta?.platform,
            format: meta?.contentFormat.flatMap(ContentFormat.init(rawValue:))
        ))
        _records = State(initialValue: ContentPublishStore.records(for: atom))
    }

    private var title: String { atom.title?.isEmpty == false ? atom.title! : "Untitled" }
    private var wordCount: Int { draft.split(whereSeparator: \.isWhitespace).count }
    private var characterCount: Int { sections.reduce(0) { $0 + $1.text.count } }
    private var overLimitCount: Int { sections.count(where: \.isOverLimit) }
    private var record: ContentPublishRecord? { records.first { $0.platform == platform.publishPlatform.rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            header
            formatRail
            Divider().overlay(DS.commandChromeSeparator)
            HStack(spacing: 0) {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(DS.commandChromeSeparator)
                rail.frame(width: 296)
            }
        }
        .onChange(of: platform, initial: true) { _, next in
            sections = ContentExportFormatter.format(draft, for: next)
            copiedSection = nil
            copiedAll = false
        }
        .background(keyboard)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export \(title)")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            ExportPlatformMark(platform: platform, size: 36)
                .animation(ProMotionSprings.snappy, value: platform)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: DS.space12)
            FloatingOverlayCloseButton(action: onClose)
                .help("Close (Esc)")
        }
        .padding(.horizontal, DS.space20)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space12)
    }

    private var subtitle: String {
        var parts = ["Export", "\(wordCount) words"]
        if !sections.isEmpty { parts.append(sections.count == 1 ? "1 section" : "\(sections.count) sections") }
        return parts.joined(separator: " · ")
    }

    // MARK: Format rail

    private var formatRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                ForEach(ExportPlatform.allCases) { candidate in
                    ExportFormatPill(
                        platform: candidate,
                        isSelected: platform == candidate,
                        isPublished: records.contains { $0.platform == candidate.publishPlatform.rawValue }
                    ) {
                        withAnimation(ProMotionSprings.snappy) { platform = candidate }
                    }
                }
            }
            .padding(.horizontal, DS.space20)
            .padding(.bottom, DS.space12)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Export format")
    }

    // MARK: Preview (the ledger)

    private var preview: some View {
        ScrollView {
            if sections.isEmpty {
                emptyPreview
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        ExportSectionRow(
                            section: section,
                            isLast: section.index == sections.count - 1,
                            copied: copiedSection == section.index
                        ) { copy(section) }
                    }
                }
                .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DS.commandChromeBorder, lineWidth: 0.5)
                )
                .padding(DS.space20)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private var emptyPreview: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "text.page")
                .font(DS.title1)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Nothing to export yet")
                .font(DS.headline)
                .foregroundStyle(DS.textSecondary)
            Text("Write the draft first — every format here is cut from the same text.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space48)
    }

    // MARK: Rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                railSection("Destinations") { destinations }
                railSection("Publication") { publication }
                railSection("Details") { details }
            }
            .padding(DS.space20)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private func railSection(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoSectionHeader(label: label.uppercased())
            content()
        }
    }

    private var destinations: some View {
        VStack(spacing: 0) {
            ExportRailRow(
                icon: copiedAll ? "checkmark" : "doc.on.doc",
                title: copiedAll ? "Copied to clipboard" : "Copy all",
                detail: sections.count == 1 ? "One section" : "\(sections.count) sections, separated",
                shortcut: "⌘⇧C",
                tint: copiedAll ? DS.green : nil,
                isLast: false,
                action: copyAll
            )
            .disabled(sections.isEmpty)
            ExportDriveRow(atomUUID: atom.uuid, title: title, platform: platform, sections: sections)
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.commandChromeBorder, lineWidth: 0.5)
        )
    }

    private var publication: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            if let record {
                publishedRecord(record)
            } else {
                urlField
                Button(action: markPublished) {
                    Label(publishing ? "Publishing…" : "Mark published on \(platform.publishPlatform.displayName)",
                          systemImage: "paperplane")
                }
                .buttonStyle(ExportPrimaryButtonStyle())
                .disabled(publishing || sections.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Stamp the publication record (⌘↩)")
                Text("Stamps a \(platform.publishPlatform.displayName) record dated today. The piece lands in Published.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var urlField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "link")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            TextField("Post URL (optional)", text: $publishURL)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .focused($urlFocused)
                .onSubmit(markPublished)
        }
        .padding(.horizontal, DS.space12)
        .frame(height: 32)
        .dsGlassInput(isFocused: urlFocused, cornerRadius: 16)
        .accessibilityLabel("Post URL")
    }

    private func publishedRecord(_ record: ContentPublishRecord) -> some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.body)
                .foregroundStyle(DS.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Published on \(platform.publishPlatform.displayName)")
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.text)
                Text(record.publishedAtDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
            if let url = record.url.flatMap(URL.init(string:)) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Open the live post")
                .accessibilityLabel("Open the live post")
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.commandChromeBorder, lineWidth: 0.5)
        )
    }

    private var details: some View {
        VStack(spacing: DS.space6) {
            detailRow("Format", platform.displayName)
            detailRow("Sections", "\(sections.count)")
            detailRow("Characters", characterCount.formatted())
            detailRow("Words", wordCount.formatted())
            if overLimitCount > 0 {
                detailRow("Over limit", "\(overLimitCount)", tint: DS.orange)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: DS.space8)
            Text(value)
                .font(DS.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tint ?? DS.textSecondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Verbs

    private func copy(_ section: ExportSection) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.text, forType: .string)
        withAnimation(ProMotionSprings.snappy) {
            copiedSection = section.index
            copiedAll = false
        }
        scheduleCopyReset()
    }

    private func copyAll() {
        guard !sections.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ContentExportFormatter.combined(sections), forType: .string)
        withAnimation(ProMotionSprings.snappy) {
            copiedAll = true
            copiedSection = nil
        }
        scheduleCopyReset()
    }

    /// Feedback is a moment, not a state: the label returns on its own.
    private func scheduleCopyReset() {
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(ProMotionSprings.gentle) {
                copiedAll = false
                copiedSection = nil
            }
        }
    }

    /// The record is the other half of the ship: a per-platform stamp
    /// (platform + URL + today) that feeds the calendar, the client's real
    /// aggregates, and the board's Published column.
    private func markPublished() {
        guard !publishing, record == nil, !sections.isEmpty else { return }
        publishing = true
        let url = publishURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = platform.publishPlatform.rawValue
        Task { @MainActor in
            await ContentPublishStore.markPublished(atomUuid: atom.uuid, platform: target, url: url.isEmpty ? nil : url)
            if let fresh = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
                withAnimation(ProMotionSprings.gentle) { records = ContentPublishStore.records(for: fresh) }
            }
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
            publishing = false
        }
    }

    private var keyboard: some View {
        Group {
            Button("", action: onClose).keyboardShortcut(.escape, modifiers: [])
            Button("", action: copyAll).keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Overlay host (the board's presentation)

/// Export as an in-page surface over the board — the Quick Look grammar:
/// a quiet scrim, one glass-rimmed panel with a near-opaque ground, Esc or
/// a click outside to leave.
struct ContentExportOverlay: View {
    let atom: Atom
    let draft: String
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            ContentExportPanel(atom: atom, draft: draft, onClose: onClose)
                .frame(width: 900)
                .frame(maxHeight: 660)
                .background(DS.bg.opacity(0.96))
                .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 22)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

// MARK: - Format pill

/// A format is an object with identity: the platform's real mark, the
/// format's name, and the app's one selection wash. A green tick says
/// "already published there".
struct ExportFormatPill: View {
    let platform: ExportPlatform
    let isSelected: Bool
    var isPublished = false
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                ExportPlatformMark(platform: platform, size: 14, ink: isSelected ? DS.text : DS.textSecondary)
                Text(platform.shortName)
                    .font(DS.callout.weight(.medium))
                if isPublished {
                    Circle()
                        .fill(DS.green)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Published")
                }
            }
            .foregroundStyle(isSelected || hovered ? DS.text : DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(height: 32)
            .background(isSelected ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(hovered ? DS.glassInputFillFocused : DS.glassInputFill), in: .capsule)
            .overlay(Capsule().strokeBorder(isSelected ? DS.accent.opacity(0.42) : DS.glassBorder, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
        .help(platform.displayName)
        .accessibilityLabel(platform.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The platform's mark: a drawn brand mark where one exists, the format's
/// own glyph otherwise. Large sizes seat it on a quiet disc.
struct ExportPlatformMark: View {
    let platform: ExportPlatform
    var size: CGFloat = 14
    var ink: Color = DS.text

    var body: some View {
        if size >= 28 {
            glyph(size * 0.5)
                .frame(width: size, height: size)
                .background(DS.glassSectionFill, in: .rect(cornerRadius: size * 0.3))
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(DS.glassBorder, lineWidth: 0.5))
        } else {
            glyph(size)
        }
    }

    @ViewBuilder
    private func glyph(_ side: CGFloat) -> some View {
        if let key = platform.brandKey {
            PlatformBrandMark(platform: key, size: side, color: ink)
        } else {
            Image(systemName: platform.glyph)
                .font(.system(size: side * 0.85, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Section row

/// One copy-perfect section in the ledger: label + count against the
/// platform limit, a quiet Copy verb, and the text itself. Over-limit rows
/// wear a thin orange edge — the date speaks through the number, never a wall.
struct ExportSectionRow: View {
    let section: ExportSection
    let isLast: Bool
    let copied: Bool
    let onCopy: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Text(section.label.uppercased())
                    .font(DS.smallCaps)
                    .tracking(DS.smallCapsTracking)
                    .foregroundStyle(DS.giltInk)
                if let limit = section.limit {
                    Text("\(section.text.count)/\(limit)")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(section.isOverLimit ? DS.orange : DS.textMuted)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                Button(action: onCopy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(DS.caption.weight(.medium))
                        .foregroundStyle(copied ? DS.green : (hovered ? DS.text : DS.textSecondary))
                        .frame(minHeight: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Copy this section")
                .accessibilityLabel("Copy \(section.label)")
            }
            Text(section.text)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .background(hovered ? DS.glassSectionFill.opacity(0.45) : Color.clear)
        .overlay(alignment: .leading) {
            if section.isOverLimit {
                Rectangle().fill(DS.orange.opacity(0.7)).frame(width: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.commandChromeSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, DS.space16)
            }
        }
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .animation(ProMotionSprings.hover, value: hovered)
    }
}

// MARK: - Rail row

/// A destination row in the Files grammar: glyph, title, one-line detail,
/// the shortcut at the trailing edge. The whole row is the button.
struct ExportRailRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var shortcut: String? = nil
    var tint: Color? = nil
    var isLast = true
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                Image(systemName: icon)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(tint ?? DS.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DS.callout.weight(.medium))
                        .foregroundStyle(tint ?? DS.text)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.space8)
                if let shortcut {
                    Text(shortcut)
                        .font(DS.caption2.monospaced())
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(.horizontal, DS.space12)
            .frame(minHeight: 48)
            .background(hovered && isEnabled ? DS.glassSectionFill.opacity(0.6) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.commandChromeSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, 42)
            }
        }
        .onHover { hovered = $0 }
        .animation(ProMotionSprings.hover, value: hovered)
        .help(title)
    }
}

// MARK: - Drive row

/// "Send to Drive" — the one destination that completes the gesture itself.
/// Re-sending updates the document already in Drive. Disconnected states
/// are teaching rows that hand over the fix, never silence.
struct ExportDriveRow: View {
    let atomUUID: String
    let title: String
    let platform: ExportPlatform
    let sections: [ExportSection]

    private let connection = GoogleDriveConnection.shared
    @AppStorage("googleDriveExportFormat") private var storedFormat = DriveExportFormat.googleDoc.rawValue
    @State private var phase: Phase = .idle
    @State private var lastSent: DriveExportRecord?

    private enum Phase: Equatable {
        case idle, sending
        case sent(link: String?)
        case failed(String)
    }

    private var format: DriveExportFormat { DriveExportFormat(rawValue: storedFormat) ?? .googleDoc }
    private var taskKey: String { "\(atomUUID)|\(platform.rawValue)|\(storedFormat)" }

    var body: some View {
        Group {
            if connection.state.isConnected {
                connectedRow
            } else {
                unavailableRow
            }
        }
        .task(id: taskKey) { await refresh() }
    }

    private var connectedRow: some View {
        HStack(spacing: 0) {
            ExportRailRow(
                icon: phaseIcon,
                title: rowTitle,
                detail: rowDetail,
                shortcut: "⌘⇧D",
                tint: rowTint,
                isLast: true,
                action: send
            )
            .disabled(sections.isEmpty || phase == .sending)
            .keyboardShortcut("d", modifiers: [.command, .shift])
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: DS.space2) {
            if case .sent(let link) = phase, let url = link.flatMap(URL.init(string:)) {
                openButton(url)
            } else if let url = lastSent?.webViewLink.flatMap(URL.init(string:)), phase == .idle {
                openButton(url)
            }
            Menu {
                ForEach(DriveExportFormat.allCases) { candidate in
                    Button {
                        storedFormat = candidate.rawValue
                    } label: {
                        if candidate == format {
                            Label(candidate.displayName, systemImage: "checkmark")
                        } else {
                            Label(candidate.displayName, systemImage: candidate.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.space4) {
                    Image(systemName: format.icon).font(DS.caption)
                    Image(systemName: "chevron.down").font(DS.caption2.weight(.semibold))
                }
                .foregroundStyle(DS.textSecondary)
                .frame(height: 28)
                .padding(.horizontal, DS.space8)
                .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(format.displayName) — \(format.explanation)")
            .accessibilityLabel("Drive file format: \(format.displayName)")
        }
        .padding(.trailing, DS.space8)
    }

    private func openButton(_ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Image(systemName: "arrow.up.right.square")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open in Google Drive")
        .accessibilityLabel("Open in Google Drive")
    }

    private var phaseIcon: String {
        switch phase {
        case .sending: return "arrow.up.doc"
        case .sent: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .idle: return "arrow.up.doc"
        }
    }

    private var rowTitle: String {
        switch phase {
        case .sending: return "Sending to Drive…"
        case .sent: return "Sent to Drive"
        case .failed: return "Couldn't send"
        case .idle: return lastSent == nil ? "Send to Drive" : "Update in Drive"
        }
    }

    private var rowDetail: String? {
        switch phase {
        case .sending: return "\(format.displayName) · \(connection.folderName)"
        case .sent: return "\(format.displayName) · \(connection.folderName)"
        case .failed(let message): return message
        case .idle:
            if let lastSent { return "In Drive · \(lastSent.exportedAt.cosmoCompactAge)" }
            return "\(format.displayName) · \(connection.folderName)"
        }
    }

    private var rowTint: Color? {
        switch phase {
        case .sent: return DS.green
        case .failed: return DS.orange
        default: return nil
        }
    }

    private var unavailableRow: some View {
        ExportRailRow(
            icon: "externaldrive.badge.icloud",
            title: unavailableTitle,
            detail: "Set up in Settings ›",
            isLast: true
        ) {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }
        .disabled(connection.state == .connecting)
    }

    private var unavailableTitle: String {
        switch connection.state {
        case .needsReconnect: return "Google Drive sign-in expired"
        case .connecting: return "Signing in to Google…"
        default: return "Send to Google Drive"
        }
    }

    private func refresh() async {
        await connection.refreshState()
        phase = .idle
        lastSent = DriveExportLedger.shared.record(atomUUID: atomUUID, platform: platform, format: format)
    }

    private func send() {
        guard !sections.isEmpty, phase != .sending else { return }
        phase = .sending
        Task {
            do {
                let file = try await connection.export(
                    atomUUID: atomUUID, title: title, platform: platform, sections: sections, format: format
                )
                withAnimation(ProMotionSprings.gentle) {
                    phase = .sent(link: file.webViewLink ?? file.openURL?.absoluteString)
                }
                lastSent = DriveExportLedger.shared.record(atomUUID: atomUUID, platform: platform, format: format)
            } catch {
                withAnimation(ProMotionSprings.gentle) { phase = .failed(error.localizedDescription) }
            }
        }
    }
}

/// The rail's one hero: an accent capsule that lights on hover.
private struct ExportPrimaryButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(DS.callout.weight(.semibold))
            .foregroundStyle(DS.textOnAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(hovered ? DS.accentHover : DS.accent, in: .capsule)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
            .animation(reduceMotion ? nil : ProMotionSprings.press, value: configuration.isPressed)
            .contentShape(.capsule)
            .onHover { hovered = $0 }
    }
}
