// CosmoOS/UI/FocusMode/Inquiry/ExtractPeekView.swift
// The reading surface for inquiry captures (.extract and .question atoms).
// Before this existed, every pane/full-screen open of an extract fell through
// the entity-routing default into the Idea WORKBENCH — hooks, outline, and
// idea metadata stamped onto a verbatim capture. A capture is something you
// READ: one paper surface, the text as the serif hero, provenance as a flat
// hairline ledger (the ⌘K one-surface anatomy), and no editing chrome at all.

import SwiftUI

struct ExtractPeekView: View {
    let atom: Atom
    let onClose: () -> Void

    @Environment(\.isPaneContext) private var isPaneContext

    @State private var sourceAtom: Atom?
    @State private var parentQuestion: Atom?

    private var metadata: ExtractMetadata? { atom.extractMetadata }
    private var isQuestion: Bool { atom.type == .question }

    private var captureText: String {
        let body = atom.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !body.isEmpty { return body }
        return atom.title ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space20) {
                headerBand
                heroText
                if let note = metadata?.userNote, !note.isEmpty {
                    userNote(note)
                }
                ledger
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DS.bg)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .task(id: atom.uuid) { await loadProvenance() }
    }

    // MARK: - Header band

    private var headerBand: some View {
        HStack(spacing: DS.space8) {
            kindChip
            Spacer(minLength: 0)
            if let created = ISO8601.date(from: atom.createdAt) {
                Text(created.formatted(date: .abbreviated, time: .omitted))
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            if !isPaneContext {
                closeButton
            }
        }
    }

    private var kindChip: some View {
        let kind = metadata?.kind
        let label = isQuestion ? "Question" : (kind?.displayName ?? "Capture")
        let icon = isQuestion ? "questionmark.bubble" : (kind?.iconName ?? "quote.opening")
        return HStack(spacing: DS.space4) {
            Image(systemName: icon)
                .font(DS.caption2.weight(.medium))
                .accessibilityHidden(true)
            Text(label)
                .font(DS.smallCaps)
                .tracking(1.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(DS.entityIdea)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space2)
        .background(DS.entityIdea.opacity(0.10), in: Capsule())
        .accessibilityLabel(label)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 22, height: 22)
                .background(DS.border.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Close (Esc)")
        .accessibilityLabel("Close capture")
    }

    // MARK: - Hero

    /// The capture is content, so it speaks serif — a reading measure, not a
    /// form. Selectable: quotes exist to be taken elsewhere.
    private var heroText: some View {
        Text(captureText)
            .font(DS.spaceTitleSerif)
            .foregroundStyle(DS.text)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func userNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Text("※")
                .font(DS.callout)
                .foregroundStyle(DS.gilt)
                .accessibilityHidden(true)
            Text(note)
                .font(DS.callout)
                .italic()
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityLabel("Your note: \(note)")
    }

    // MARK: - Provenance ledger

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
            if let citation = metadata?.citation, !citation.isEmpty {
                ledgerRow(label: "Citation", value: citation)
            }
            if let source = sourceAtom {
                ledgerLinkRow(label: "Source", value: source.title ?? "Untitled") {
                    open(source)
                }
            }
            if let question = parentQuestion {
                ledgerLinkRow(label: "Question", value: question.title ?? "Untitled") {
                    openAsPane(uuid: question.uuid)
                }
            }
            if let origin = metadata?.originType, !origin.isEmpty {
                ledgerRow(label: "Captured via", value: origin.capitalized)
            }
        }
    }

    private func ledgerRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
                ledgerLabel(label)
                Text(value)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DS.space8)
            Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
        }
    }

    private func ledgerLinkRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
                ledgerLabel(label)
                Button(action: action) {
                    Text(value)
                        .font(DS.callout)
                        .foregroundStyle(DS.accent)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(label.lowercased())")
                .accessibilityLabel("Open \(label): \(value)")
            }
            .padding(.vertical, DS.space8)
            Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
        }
    }

    private func ledgerLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(DS.textMuted)
            .frame(width: 92, alignment: .leading)
    }

    // MARK: - Provenance loading & navigation

    private func loadProvenance() async {
        sourceAtom = nil
        parentQuestion = nil
        if let sourceUUID = metadata?.sourceUUID {
            sourceAtom = try? await AtomRepository.shared.fetch(uuid: sourceUUID)
        }
        if let questionUUID = metadata?.parentQuestionUUID {
            parentQuestion = try? await AtomRepository.shared.fetch(uuid: questionUUID)
        }
    }

    /// Web-backed sources open the page itself; everything else peeks as a pane.
    private func open(_ source: Atom) {
        if let urlString = source.researchMetadata?.url ?? source.url,
           let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openWebBrowserPane,
                object: nil,
                userInfo: ["url": url, "title": source.title ?? urlString]
            )
            return
        }
        openAsPane(uuid: source.uuid)
    }

    private func openAsPane(uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }
}
