// CosmoOS/UI/FocusMode/Inquiry/InquiryReaderView.swift
// Reader morph — when the user opens a source from the right rail, the center stele
// transforms into a clean reader hosting WebSourceView or InternalSourceView.

import SwiftUI

@MainActor
struct InquiryReaderView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab

    @State private var lastSelectedText: String = ""
    @State private var selectionTimestamp: Int?
    @State private var loadState: WebSourceLoadState = .loading

    var body: some View {
        // Pure content: chrome (back / title / browser / reader toggle) lives
        // in the Study's center island; the shell frames this view as a
        // document sheet.
        ZStack(alignment: .bottom) {
            content
            if !lastSelectedText.isEmpty {
                SelectionMiniMenu(
                    viewModel: viewModel,
                    tab: tab,
                    selection: lastSelectedText,
                    timestampSeconds: selectionTimestamp
                ) {
                    lastSelectedText = ""
                    selectionTimestamp = nil
                }
                .padding(DS.space12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(ProMotionSprings.gentle, value: lastSelectedText.isEmpty)
    }

    private var readerMode: Bool {
        viewModel.readerPrefersReaderMode
    }

    @ViewBuilder
    private var content: some View {
        switch tab.kind {
        case .web, .pdf:
            if let urlString = tab.url, let url = URL(string: urlString) {
                webContent(url: url, readerMode: readerMode)
            } else {
                missingURLState
            }
        case .youTube:
            // The study reader: just the video and its transcript — never the
            // watch page with its feed, comments, and recommendations.
            StudyYouTubeReaderView(
                viewModel: viewModel,
                tab: tab,
                lastSelectedText: $lastSelectedText,
                selectionTimestamp: $selectionTimestamp
            )
        case .internalAtom, .swipe:
            if let sourceUUID = tab.sourceUUID {
                InternalSourceView(sourceUUID: sourceUUID, lastSelectedText: $lastSelectedText)
            } else {
                missingURLState
            }
        case .pageScan:
            if let sourceUUID = tab.sourceUUID {
                PageScanSourceView(viewModel: viewModel, sourceUUID: sourceUUID)
            } else {
                missingURLState
            }
        }
    }

    @ViewBuilder
    private func webContent(url: URL, readerMode: Bool) -> some View {
        ZStack {
            WebSourceView(url: url, readerMode: readerMode, lastSelectedText: $lastSelectedText, loadState: $loadState)
            switch loadState {
            case .loading:
                loadingState
            case .failed(let message):
                failureState(url: url, message: message)
            case .loaded:
                EmptyView()
            }
        }
        .animation(ProMotionSprings.gentle, value: loadState)
    }

    private var loadingState: some View {
        VStack(spacing: DS.space10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading source…")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .transition(.opacity)
    }

    private func failureState(url: URL, message: String) -> some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("This page couldn't be loaded here.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
            Text(message)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: 360)
                .multilineTextAlignment(.center)
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text("Open in Browser")
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 6)
                    .background(DS.accent, in: Capsule())
                    .foregroundStyle(DS.textOnAccent)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open source in browser")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
        .transition(.opacity)
    }

    private var missingURLState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("This source has no readable address.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Selection mini menu

@MainActor
struct SelectionMiniMenu: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab
    let selection: String
    /// The moment in the video this selection begins (transcript readers) —
    /// captures cite the exact timestamp.
    var timestampSeconds: Int? = nil
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.space8) {
            Text(selection.prefix(64))
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: DS.space12)
            actionButton(label: "Note", kind: .note)
            actionButton(label: "Quote", kind: .quote)
            actionButton(label: "Claim", kind: .claim)
            actionButton(label: "Evidence", kind: .evidence)
            Button {
                viewModel.proposeBranchFromSelection(selection, originExtractUUID: nil, sourceTabId: tab.id)
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                    Text("Branch")
                        .font(CosmoTypography.caption)
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 5)
                .background(DS.accent.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Branch from selection")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss selection menu")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .glassEffect(.regular, in: .capsule)
    }

    private func actionButton(label: String, kind: ExtractKind) -> some View {
        Button {
            Task {
                _ = await viewModel.saveSelectionAsExtract(
                    selection,
                    kind: kind,
                    sourceTab: tab,
                    timestampSeconds: timestampSeconds
                )
                onDismiss()
            }
        } label: {
            Text(label)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save as \(label)")
    }
}
