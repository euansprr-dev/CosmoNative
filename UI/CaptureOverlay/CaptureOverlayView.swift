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
            SwipeFlowRecordingPill()
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
        .animation(ProMotionSprings.gentle, value: viewModel.stagedAttachments.count)
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
                await viewModel.receive(payloads, staging: true)
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
            swipeLinkRow
        }
        .animation(ProMotionSprings.snappy, value: viewModel.laneAssist.hint?.lane.uuid)
        .animation(ProMotionSprings.snappy, value: viewModel.laneAssist.suggestion?.lane.uuid)
        .animation(ProMotionSprings.snappy, value: viewModel.swipeLink)
    }

    /// The link trigger: an Instagram / YouTube / X / TikTok link in the field
    /// surfaces the SAME Inbox | Swipe control the staged tray wears, the
    /// moment it lands. Hidden while files are staged — the tray's footer
    /// owns the choice then, and the text rides along as its note.
    @ViewBuilder
    private var swipeLinkRow: some View {
        if let link = viewModel.swipeLink, viewModel.stagedAttachments.isEmpty {
            HStack(spacing: DS.space10) {
                HStack(spacing: DS.space6) {
                    SwipePlatformGlyph(source: link.platform.glyphKey)
                        .frame(width: 12, height: 12)
                    Text("\(link.platform.displayName) link")
                        .font(DS.caption.weight(.medium))
                }
                .foregroundStyle(DS.textSecondary)
                .accessibilityElement(children: .combine)

                stagedDestinationControl

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var captureInputRow: some View {
        HStack(spacing: DS.space10) {
            LaneHighlightedCaptureField(
                text: $viewModel.captureText,
                placeholder: viewModel.stagedAttachments.isEmpty
                    ? "Capture a thought…"
                    : "Add a thought to send with them…",
                maxLines: 4,
                assist: viewModel.laneAssist,
                isFocused: $isFieldFocused,
                onSubmit: {
                    Task { await viewModel.submitText() }
                },
                onShiftSubmit: {
                    Task { await viewModel.submitText(asSwipe: true) }
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
                .help(sendArrowHelp)
                .accessibilityLabel(sendArrowAccessibilityLabel)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .dsGlassInput(isFocused: isFieldFocused, cornerRadius: 14)
        .animation(ProMotionSprings.snappy, value: viewModel.captureText.isEmpty)
    }

    /// A link in the field with Swipe selected sends to the Swipe File on ⏎;
    /// the tooltip says so, because a control that changes what ⏎ does must
    /// not leave the button's own hint contradicting it.
    private var sendArrowHelp: String {
        guard viewModel.swipeLink != nil, viewModel.stagedAttachments.isEmpty else {
            return "Capture (⏎) · ⇧⏎ saves it to the Swipe File instead"
        }
        return viewModel.stagedDestination == .swipe
            ? "Save to the Swipe File (⏎) · switch to Inbox to triage it instead"
            : "Capture to the Inbox (⏎) · ⇧⏎ saves it to the Swipe File instead"
    }

    private var sendArrowAccessibilityLabel: String {
        guard viewModel.swipeLink != nil, viewModel.stagedAttachments.isEmpty else {
            return "Capture thought"
        }
        return viewModel.stagedDestination == .swipe ? "Swipe link" : "Capture link"
    }

    // MARK: - Drop well (the hero)

    private var dropWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(viewModel.isDropTargeted ? DS.accentSoft : DS.glassCardFill)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    viewModel.isDropTargeted ? DS.accent.opacity(0.5) : DS.glassBorder,
                    style: StrokeStyle(lineWidth: 1, dash: wellDash)
                )

            if let preview = viewModel.dragPreview, viewModel.isDropTargeted {
                dragPreviewContent(preview)
            } else if !viewModel.stagedAttachments.isEmpty {
                stagedTray
            } else {
                idleWellContent
            }
        }
        .frame(minHeight: 128)
        .animation(ProMotionSprings.snappy, value: viewModel.dragPreview)
    }

    /// Dashes invite the first drop; a well holding files is a tray and
    /// wears a solid hairline.
    private var wellDash: [CGFloat] {
        viewModel.isDropTargeted || !viewModel.stagedAttachments.isEmpty ? [] : [6, 4]
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
            Text("files · screenshots · links · text")
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
            Text(releaseLine(for: preview))
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.accent)
        }
        .padding(DS.space12)
        .frame(maxWidth: 420)
    }

    /// Files stage ("add") and leave with the send button; text and links
    /// still capture the moment they land. An all-image drop says where it is
    /// headed, because that drop will default to the Swipe File and the user
    /// should learn that BEFORE release, not from the receipt.
    private func releaseLine(for preview: CaptureDragPreview) -> String {
        if preview.stagesOnDrop, preview.isAllImages {
            return preview.totalCount == 1
                ? "Release to swipe"
                : "Release to swipe \(preview.totalCount) screenshots"
        }
        // A platform link lands in the field with Swipe pre-selected — the
        // same pre-release honesty as an all-image drop.
        if preview.stagesOnDrop, preview.isSwipeLink {
            return "Release to swipe"
        }
        let verb = preview.stagesOnDrop ? "add" : "capture"
        return preview.totalCount == 1
            ? "Release to \(verb)"
            : "Release to \(verb) \(preview.totalCount) items"
    }

    // MARK: - Staged tray (files waiting for the send)

    /// Dropped files hold in the well as tiles until the user sends them —
    /// with a typed thought they leave as ONE linked capture.
    private var stagedTray: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            stagedGrid
            stagedFooter
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stagedGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: DS.space8, alignment: .top)],
            alignment: .leading,
            spacing: DS.space8
        ) {
            ForEach(viewModel.stagedAttachments) { staged in
                StagedAttachmentTile(staged: staged) {
                    viewModel.removeStaged(staged.id)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    private var stagedFooter: some View {
        HStack(spacing: DS.space12) {
            Text(stagedCountLabel)
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textSecondary)
                .contentTransition(.numericText())

            if let lane = viewModel.laneAssist.hint?.lane {
                Text("→ \(lane.name)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            } else {
                stagedDestinationControl
            }

            Spacer(minLength: DS.space8)

            Button {
                viewModel.clearStaged()
            } label: {
                Text("Clear")
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove all without capturing")
            .accessibilityLabel("Clear staged files")

            Button {
                Task { await viewModel.sendStaged() }
            } label: {
                HStack(spacing: DS.space6) {
                    Image(systemName: "arrow.up")
                        .accessibilityHidden(true)
                    Text(sendButtonLabel)
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isBusy)
            .help(sendButtonHelp)
        }
        .animation(ProMotionSprings.snappy, value: viewModel.stagedDestination)
    }

    /// The ONE kind-adjacent choice in the system, and only because staged
    /// files are genuinely ambiguous (three ad screenshots vs a PDF invoice
    /// arrive through the identical gesture). Selection = soft tint wash +
    /// hairline, never a solid fill (Law 11).
    private var stagedDestinationControl: some View {
        HStack(spacing: 2) {
            ForEach(CaptureOverlayViewModel.StagedDestination.allCases) { destination in
                destinationSegment(destination)
            }
        }
        .padding(2)
        .background(DS.glassInputFill, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination")
    }

    private func destinationSegment(
        _ destination: CaptureOverlayViewModel.StagedDestination
    ) -> some View {
        let isSelected = viewModel.stagedDestination == destination
        return Button {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.chooseStagedDestination(destination)
            }
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: destinationIcon(destination))
                    .font(DS.caption2.weight(.semibold))
                Text(destination.title)
                    .font(DS.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space10)
            .frame(height: 24)
            .background {
                if isSelected {
                    Capsule()
                        .fill(DS.accentSoft)
                        .overlay(Capsule().strokeBorder(DS.accent.opacity(0.35), lineWidth: 0.5))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(destinationHelp(destination))
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The control's subject is the staged tray when one exists, else the
    /// link in the field — the glyph and the tooltip name that subject.
    private var destinationSubjectIsLink: Bool {
        viewModel.stagedAttachments.isEmpty && viewModel.swipeLink != nil
    }

    private func destinationIcon(_ destination: CaptureOverlayViewModel.StagedDestination) -> String {
        guard destination == .swipe, destinationSubjectIsLink else { return destination.iconName }
        return SwipeKind.post.iconName
    }

    private func destinationHelp(_ destination: CaptureOverlayViewModel.StagedDestination) -> String {
        switch (destination, destinationSubjectIsLink) {
        case (.swipe, true): return "Save this link to the Swipe File — Cosmo pulls the post and reads it"
        case (.swipe, false): return "Save these as one swipe — Cosmo reads them and works out the rest"
        case (.inbox, true): return "Send this link to the Inbox for triage"
        case (.inbox, false): return "Send these to the Inbox for triage"
        }
    }

    private var sendButtonLabel: String {
        viewModel.laneAssist.hint == nil && viewModel.stagedDestination == .swipe ? "Swipe" : "Capture"
    }

    private var sendButtonHelp: String {
        if let lane = viewModel.laneAssist.hint?.lane {
            return "Capture these attachments in \(lane.name) (⌘⏎)"
        }
        return viewModel.stagedDestination == .swipe
            ? "Save as one swipe — a typed thought rides along as the note (⌘⏎)"
            : "Capture — a typed thought and these files land together (⌘⏎)"
    }

    private var stagedCountLabel: String {
        let images = viewModel.stagedAttachments.filter(\.isImage).count
        let files = viewModel.stagedAttachments.count - images
        switch (images, files) {
        case (0, let f): return f == 1 ? "1 file" : "\(f) files"
        case (let i, 0): return i == 1 ? "1 image" : "\(i) images"
        default: return "\(images + files) items"
        }
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

// MARK: - Staged attachment tile

/// One waiting file: a 64pt thumbnail (images) or kind-glyph tile (files)
/// with its name beneath and a hover ✕ to pull it back out.
private struct StagedAttachmentTile: View {
    let staged: CaptureOverlayViewModel.StagedAttachment
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: DS.space4) {
            art
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.glassBorder, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) { removeBadge }

            Text(staged.displayName)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var art: some View {
        if let thumbnail = staged.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("\(staged.kind.displayName): \(staged.displayName)")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.glassSectionFill)
                Image(systemName: symbol)
                    .font(DS.title3)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var removeBadge: some View {
        if isHovered {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(DS.bg, DS.text)
                    .padding(DS.space4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel("Remove \(staged.displayName)")
            .transition(.opacity)
        }
    }

    private var symbol: String {
        switch staged.kind {
        case .image, .screenshot, .pageScan: return "photo"
        case .pdf: return "doc.richtext"
        case .epub: return "book.closed"
        case .markdown, .textFile: return "doc.text"
        case .audio: return "waveform"
        case .video: return "film"
        case .spreadsheet: return "tablecells"
        case .document, .unknown: return "doc"
        }
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
