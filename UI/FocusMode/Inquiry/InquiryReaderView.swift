// CosmoOS/UI/FocusMode/Inquiry/InquiryReaderView.swift
// Reader morph — when the user opens a source from the right rail, the center stele
// transforms into a clean reader hosting WebSourceView or InternalSourceView.

import SwiftUI

@MainActor
struct InquiryReaderView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let tab: SourceTab

    @State private var lastSelectedText: String = ""
    @State private var readerMode: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            readerBar
            Divider().background(DS.borderSubtle)
            ZStack(alignment: .bottom) {
                content
                if !lastSelectedText.isEmpty {
                    SelectionMiniMenu(viewModel: viewModel, tab: tab, selection: lastSelectedText) {
                        lastSelectedText = ""
                    }
                    .padding(DS.space12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(ProMotionSprings.gentle, value: lastSelectedText.isEmpty)
        }
    }

    private var readerBar: some View {
        HStack(spacing: DS.space8) {
            Button {
                viewModel.dismissReader()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(CosmoTypography.label)
                }
                .foregroundStyle(CosmoColors.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.surface, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Back to question")

            Text(tab.title)
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(1)

            Spacer()

            if tab.kind == .web {
                readerToggle
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .background(DS.surface)
    }

    private var readerToggle: some View {
        Button {
            readerMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: readerMode ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
                Text(readerMode ? "Reader" : "Raw")
                    .font(CosmoTypography.caption)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
            .foregroundStyle(CosmoColors.textSecondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle reader mode")
    }

    @ViewBuilder
    private var content: some View {
        switch tab.kind {
        case .web, .pdf:
            if let urlString = tab.url, let url = URL(string: urlString) {
                WebSourceView(url: url, readerMode: readerMode, lastSelectedText: $lastSelectedText)
            } else {
                missingURLState
            }
        case .youTube:
            if let urlString = tab.url, let url = URL(string: urlString) {
                WebSourceView(url: url, readerMode: false, lastSelectedText: $lastSelectedText)
            } else {
                missingURLState
            }
        case .internalAtom, .swipe:
            if let sourceUUID = tab.sourceUUID {
                InternalSourceView(sourceUUID: sourceUUID, lastSelectedText: $lastSelectedText)
            } else {
                missingURLState
            }
        }
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
        .background(DS.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(DS.sepiaBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private func actionButton(label: String, kind: ExtractKind) -> some View {
        Button {
            Task {
                _ = await viewModel.saveSelectionAsExtract(selection, kind: kind, sourceTab: tab)
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
