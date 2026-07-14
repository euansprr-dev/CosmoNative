// CosmoOS/UI/CaptureOverlay/CaptureOverlayView.swift
// The Capture Anywhere platter: a calm glass panel summoned over any app.
// One hero — the drop well. Type a thought, drop anything, paste, scan a
// page, shoot with the iPhone, or pick files; every capture lands as a
// session-tray row with Undo. Esc ends the session.
// July 2026 — Capture Anywhere

import SwiftUI
import UniformTypeIdentifiers

struct CaptureOverlayView: View {
    @Bindable var viewModel: CaptureOverlayViewModel
    // Plain Bool, not FocusState: the field is an NSTextView-backed
    // representable that manages first responder itself.
    @State private var isFieldFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            captureFieldRow
            dropWell
            sourceButtons
            progressLine
            errorLine
            accessibilityHintRow
            sessionTray
        }
        .padding(DS.space16)
        .frame(width: 560)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
        .overlay(dropGlow)
        .overlay(giltCorners)
        // Transparent margin so the window is larger than the platter —
        // the glass shadow (18pt radius) and drop glow render uncut.
        .padding(44)
        .scaleEffect(viewModel.isDropTargeted && !reduceMotion ? 1.01 : 1.0)
        .animation(ProMotionSprings.snappy, value: viewModel.isDropTargeted)
        .animation(ProMotionSprings.gentle, value: viewModel.sessionEntries.count)
        .animation(ProMotionSprings.snappy, value: viewModel.errorLine)
        .background(CaptureDropTarget(viewModel: viewModel))
        .background(continuityCameraAnchor)
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let payloads: [DropPayload] = urls.compactMap { url in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    // Read now, while access is scoped — the service gets bytes.
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    let type = UTType(filenameExtension: url.pathExtension) ?? .data
                    return .data(data, type: type, suggestedName: url.lastPathComponent)
                }
                await viewModel.ingest(payloads)
            }
        }
        .onChange(of: viewModel.captureFieldFocusTick) {
            isFieldFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text("CAPTURE")
                .dsSmallCapsLabel()
            if let from = viewModel.capturedFrom, !from.isEmpty {
                Text("from \(from)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer()
            Text("esc")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DS.glassSectionFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(DS.glassBorder, lineWidth: 1)
                        )
                )
                .accessibilityLabel("Press Escape to close")
        }
    }

    // MARK: - Text capture

    /// The input plus its live lane chip — a resolved `Groceries:` prefix
    /// shows where the capture will land; a prefix-in-progress offers the
    /// completion (space or click accepts).
    private var captureFieldRow: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            captureInputRow
            LaneAssistChip(text: $viewModel.captureText, assist: viewModel.laneAssist)
        }
        .animation(ProMotionSprings.snappy, value: viewModel.laneAssist.hint?.lane.uuid)
        .animation(ProMotionSprings.snappy, value: viewModel.laneAssist.suggestion?.lane.uuid)
    }

    private var captureInputRow: some View {
        HStack(spacing: DS.space10) {
            LaneHighlightedCaptureField(
                text: $viewModel.captureText,
                maxLines: 4,
                assist: viewModel.laneAssist,
                isFocused: $isFieldFocused,
                onSubmit: {
                    Task { await viewModel.submitText() }
                }
            )
            .frame(minHeight: 28)
            .onChange(of: viewModel.captureText) {
                viewModel.captureTextChanged()
            }

            if !viewModel.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.submitText() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(DS.title3)
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .help("Capture (⏎)")
                .accessibilityLabel("Capture thought")
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .dsGlassInput(isFocused: isFieldFocused, cornerRadius: 14)
        .animation(ProMotionSprings.snappy, value: viewModel.captureText.isEmpty)
    }

    // MARK: - Drop well (the hero)

    private var dropWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.isDropTargeted ? DS.accentSoft : DS.glassCardFill)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    viewModel.isDropTargeted ? DS.accent.opacity(0.5) : DS.glassBorder,
                    style: StrokeStyle(lineWidth: 1, dash: viewModel.isDropTargeted ? [] : [6, 4])
                )

            if let preview = viewModel.dragPreview, viewModel.isDropTargeted {
                dragPreviewContent(preview)
            } else {
                idleWellContent
            }
        }
        .frame(minHeight: 128)
        .animation(ProMotionSprings.snappy, value: viewModel.dragPreview)
    }

    private var idleWellContent: some View {
        VStack(spacing: DS.space6) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Drop anything")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Text("files · images · links · text")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            if viewModel.clipboardHasContent {
                Text("⌘V to paste")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
                    .padding(.top, DS.space4)
            }
        }
        .padding(DS.space16)
    }

    /// What's about to land — readable before release.
    private func dragPreviewContent(_ preview: CaptureDragPreview) -> some View {
        VStack(spacing: DS.space8) {
            VStack(alignment: .leading, spacing: DS.space4) {
                ForEach(preview.items) { item in
                    HStack(spacing: DS.space8) {
                        Image(systemName: item.systemImage)
                            .font(DS.caption)
                            .foregroundStyle(DS.accent)
                            .frame(width: 16)
                        Text(item.name)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            if preview.totalCount > preview.items.count {
                Text("and \(preview.totalCount - preview.items.count) more")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Text(preview.totalCount == 1 ? "Release to capture" : "Release to capture \(preview.totalCount) items")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.accent)
        }
        .padding(DS.space12)
        .frame(maxWidth: 420)
    }

    // MARK: - Drop glow (the cluster treatment)

    @ViewBuilder
    private var dropGlow: some View {
        if viewModel.isDropTargeted {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.accent.opacity(0.28), lineWidth: 4)
                .blur(radius: 5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var giltCorners: some View {
        if viewModel.isDropTargeted {
            GeometryReader { proxy in
                captureGiltCorners(size: proxy.size)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Four accent L-brackets — the cluster drop grammar, panel-sized.
    private func captureGiltCorners(size: CGSize) -> some View {
        let opacity = DS.palette.isDark ? 0.48 : 0.34
        let bracket: CGFloat = 14
        let inset: CGFloat = 10
        let stroke = DS.accent.opacity(opacity)

        return ZStack {
            GiltCornerBracket()
                .stroke(stroke, lineWidth: 1.15)
                .frame(width: bracket, height: bracket)
                .position(x: inset + bracket / 2, y: inset + bracket / 2)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: 1.15)
                .frame(width: bracket, height: bracket)
                .rotationEffect(.degrees(90))
                .position(x: size.width - inset - bracket / 2, y: inset + bracket / 2)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: 1.15)
                .frame(width: bracket, height: bracket)
                .rotationEffect(.degrees(180))
                .position(x: size.width - inset - bracket / 2, y: size.height - inset - bracket / 2)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: 1.15)
                .frame(width: bracket, height: bracket)
                .rotationEffect(.degrees(270))
                .position(x: inset + bracket / 2, y: size.height - inset - bracket / 2)
        }
    }

    // MARK: - Source buttons

    private var sourceButtons: some View {
        HStack(spacing: DS.space8) {
            sourceButton(
                title: "Scan pages",
                systemImage: "doc.viewfinder",
                help: "Scan pages with your iPhone, or upload images (⌘1)",
                shortcut: "1"
            ) {
                viewModel.continuityCameraMenuTick += 1
            }
            sourceButton(
                title: "iPhone camera",
                systemImage: "camera",
                help: "Take a photo with your iPhone (⌘2)",
                shortcut: "2"
            ) {
                viewModel.continuityCameraMenuTick += 1
            }
            sourceButton(
                title: "Files",
                systemImage: "folder",
                help: "Choose files to capture (⌘3)",
                shortcut: "3"
            ) {
                viewModel.showFileImporter = true
            }
        }
    }

    private func sourceButton(
        title: String,
        systemImage: String,
        help: String,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        CaptureSourceButton(title: title, systemImage: systemImage, action: action)
            .keyboardShortcut(shortcut, modifiers: .command)
            .help(help)
            .disabled(viewModel.isBusy)
    }

    // MARK: - Progress / error

    @ViewBuilder
    private var progressLine: some View {
        if viewModel.isBusy {
            HStack(spacing: DS.space6) {
                ProgressView().controlSize(.mini)
                Text(viewModel.receivingCount > 0 ? "Receiving files…" : "Reading your capture…")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.space4)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error = viewModel.errorLine {
            HStack(spacing: DS.space6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
                    .accessibilityHidden(true)
                Text(error)
                    .font(DS.caption)
                    .foregroundStyle(DS.red)
            }
            .padding(.horizontal, DS.space4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Denied state as a teaching row: the global hotkey needs Accessibility
    /// trust — hand the user the fix, never fail silently.
    @ViewBuilder
    private var accessibilityHintRow: some View {
        if viewModel.accessibilityHintNeeded {
            HStack(spacing: DS.space8) {
                Image(systemName: "lock.shield")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
                Text("The global \(HotkeyManager.shared.captureHotkey.displayName) hotkey needs Accessibility access")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.accent)
                .help("Grant Cosmo Accessibility access, then return here")
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.glassSectionFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.glassBorder, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Session tray

    @ViewBuilder
    private var sessionTray: some View {
        if !viewModel.sessionEntries.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space6) {
                    Text("CAPTURED")
                        .dsSmallCapsLabel()
                    Text("\(viewModel.capturedCount)")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .contentTransition(.numericText())
                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(viewModel.sessionEntries.suffix(6).reversed()) { entry in
                        CaptureSessionRow(entry: entry) {
                            Task { await viewModel.undo(entry) }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.glassSectionFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.glassBorder, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Continuity Camera

    private var continuityCameraAnchor: some View {
        ContinuityCameraAnchor(
            presentTick: viewModel.continuityCameraMenuTick,
            onImages: { images in
                Task { await viewModel.ingestScanImages(images) }
            },
            fallbackItems: [
                ("Scan with iPhone (notification)", { Task { await viewModel.requestPhoneScan() } }),
                ("Upload images…", { viewModel.showFileImporter = true }),
            ]
        )
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
}

// MARK: - Source button

private struct CaptureSourceButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.space4) {
                Image(systemName: systemImage)
                    .font(DS.headline)
                    .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
                Text(title)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.glassCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isHovered ? DS.accent.opacity(0.35) : DS.glassBorder, lineWidth: 1)
                    )
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Session row

private struct CaptureSessionRow: View {
    let entry: CaptureOverlayViewModel.SessionEntry
    let onUndo: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: stateSymbol)
                .font(DS.caption)
                .foregroundStyle(stateColor)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(entry.displayName)
                .font(DS.callout)
                .foregroundStyle(isUndone ? DS.textMuted : DS.text)
                .strikethrough(isUndone)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DS.space8)

            Text(trailingLabel)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            if canUndo && isHovered {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(DS.caption.weight(.medium))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .help("Dismiss this capture (restorable from Recently dismissed)")
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private var isUndone: Bool {
        if case .undone = entry.state { return true }
        return false
    }

    private var canUndo: Bool {
        if case .captured(let uuid) = entry.state { return uuid != nil }
        return false
    }

    private var stateSymbol: String {
        switch entry.state {
        case .receiving: return "arrow.down.circle.dotted"
        case .captured: return "checkmark.circle.fill"
        case .consumed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .undone: return "arrow.uturn.backward.circle"
        }
    }

    private var stateColor: Color {
        switch entry.state {
        case .receiving: return DS.textMuted
        case .captured: return DS.accent
        case .consumed: return DS.textMuted
        case .failed: return DS.red
        case .undone: return DS.textMuted
        }
    }

    private var trailingLabel: String {
        if let destination = entry.destinationLabel { return destination }
        switch entry.state {
        case .receiving: return "receiving…"
        case .captured(let uuid): return uuid == nil ? "" : "→ Inbox"
        case .consumed: return "already handled"
        case .failed(let detail): return detail
        case .undone: return "undone"
        }
    }
}
