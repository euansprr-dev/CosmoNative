// CosmoOS/UI/Inbox/InboxCaptureBar.swift
// The hero of the inbox page: a single calm glass input. Type, ⏎, captured.
// ⇧⏎ (or the expand control) opens a multiline editor for longer thoughts.
// June 2026 — Inbox Revamp (INBOX_REVAMP_PLAN.md §3)

import SwiftUI

struct InboxCaptureBar: View {
    @Bindable var viewModel: InboxViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            inputRow
            scanProgressLine
            captureErrorLine
        }
        .animation(ProMotionSprings.snappy, value: viewModel.captureError)
        .animation(ProMotionSprings.gentle, value: viewModel.isScanIngesting)
        .onChange(of: viewModel.captureFieldFocusRequest) {
            isFocused = true
        }
        .onChange(of: isFocused) {
            viewModel.isCaptureFieldFocused = isFocused
        }
        .onChange(of: viewModel.captureText) {
            if viewModel.captureError != nil { viewModel.captureError = nil }
        }
        // Continuity Camera lives on an invisible anchor: the camera button
        // pops ONE native menu — device items (Take Photo / Scan Documents)
        // plus our own intake routes.
        .background(
            ContinuityCameraAnchor(
                presentTick: viewModel.continuityCameraMenuTick,
                onImages: { images in
                    Task { await viewModel.ingestScanImages(images) }
                },
                fallbackItems: [
                    ("Scan with iPhone (notification)", { Task { await viewModel.requestPhoneScan() } }),
                    ("Upload images…", { viewModel.showScanImporter = true }),
                ]
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false),
            alignment: .bottomLeading
        )
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showScanImporter },
                set: { viewModel.showScanImporter = $0 }
            ),
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            // Uploaded pictures attach without transcription — only the
            // scan intakes (Continuity Camera / iPhone scan) digitize.
            let files = urls.compactMap { url -> (data: Data, filename: String)? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (data, url.lastPathComponent)
            }
            Task { await viewModel.ingestUploadedImages(files) }
        }
    }

    // MARK: - Subviews

    private var inputRow: some View {
        HStack(alignment: viewModel.isCaptureExpanded ? .top : .center, spacing: DS.space10) {
            captureIcon
            captureField
            trailingActions
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, viewModel.isCaptureExpanded ? DS.space10 : DS.space8)
        .dsGlassInput(isFocused: isFocused, cornerRadius: 14)
        .animation(ProMotionSprings.snappy, value: isFocused)
        .animation(ProMotionSprings.snappy, value: viewModel.isCaptureExpanded)
    }

    /// Pages digitizing — a quiet line, never a blocking spinner.
    @ViewBuilder
    private var scanProgressLine: some View {
        if viewModel.isScanIngesting {
            HStack(spacing: DS.space6) {
                ProgressView().controlSize(.mini)
                Text("Reading your pages…")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.space4)
            .transition(.opacity)
        }
    }

    /// Honest failure line — the save failed, the text is still in the field.
    @ViewBuilder
    private var captureErrorLine: some View {
        if let error = viewModel.captureError {
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

    private var captureIcon: some View {
        Image(systemName: viewModel.showCaptureConfirmation ? "checkmark.circle.fill" : "plus.circle")
            .font(DS.headline)
            .foregroundStyle(viewModel.showCaptureConfirmation ? DS.accent : DS.textMuted)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var captureField: some View {
        if viewModel.isCaptureExpanded {
            expandedEditor
        } else {
            singleLineField
        }
    }

    private var singleLineField: some View {
        TextField("Capture a thought…", text: $viewModel.captureText)
            .textFieldStyle(.plain)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .focused($isFocused)
            .frame(minHeight: 28)
            .onSubmit {
                Task { await viewModel.submitCapture() }
            }
    }

    private var expandedEditor: some View {
        TextEditor(text: $viewModel.captureText)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 64, maxHeight: 120)
            .focused($isFocused)
    }

    private var trailingActions: some View {
        HStack(spacing: DS.space4) {
            Button {
                viewModel.continuityCameraMenuTick += 1
            } label: {
                Image(systemName: "camera")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanIngesting)
            .help("Capture a physical page — iPhone camera, scan, or upload")
            .accessibilityLabel("Capture a physical page")

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.isCaptureExpanded.toggle()
                }
            } label: {
                Image(systemName: viewModel.isCaptureExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isCaptureExpanded ? "Collapse" : "Write something longer")
            .accessibilityLabel(viewModel.isCaptureExpanded ? "Collapse capture field" : "Expand capture field")

            if !viewModel.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await viewModel.submitCapture() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(DS.title3)
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .transition(.scale.combined(with: .opacity))
                .help("Capture (⏎, or ⌘⏎ when expanded)")
                .accessibilityLabel("Capture thought")
            }
        }
        .animation(ProMotionSprings.snappy, value: viewModel.captureText.isEmpty)
    }
}
