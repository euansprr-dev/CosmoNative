// CosmoOS/UI/Pipeline/ContentQuickLookPanel.swift
// Space on a card: a paper panel that answers "what is this piece" in two
// seconds — title, a stage/date/client ledger, and the opening of the draft.
// Modelled on the Ideas quick look; Esc or Space closes, ⏎ opens.

import SwiftUI

struct ContentQuickLookPanel: View {
    let item: PipelineContentItem
    let sessionDay: Date?
    let perf: ContentPerfSnapshot?
    let onOpen: () -> Void
    let onOpenAsPane: () -> Void
    let onSchedule: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clientTint: Color { item.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            panel
                .frame(width: 560)
                .frame(maxHeight: 620)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
        .background(keyboard)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.palette.sepiaBorder)
            ledger
            Divider().overlay(DS.palette.sepiaBorder)
            excerpt
            Divider().overlay(DS.palette.sepiaBorder)
            footer
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.palette.sepiaBorder, lineWidth: 0.5)
        )
        .dsFloatingShadow()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(clientTint)
                .frame(width: 3, height: 22)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(item.atom.title?.isEmpty == false ? item.atom.title! : "Untitled")
                    .font(DS.heroTitleSerif)
                    .foregroundStyle(DS.text)
                    .lineLimit(3)
                if let clientName = item.clientName {
                    Text(clientName)
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space20)
    }

    private var ledger: some View {
        VStack(spacing: 0) {
            ledgerRow("Stage", item.productionStage.title)
            ledgerRow("Planned publication", item.scheduledAt.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? "No date planned")
            if let sessionDay {
                ledgerRow("Session", sessionDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            }
            if let platform = item.platform {
                ledgerRow("Platform", platform.displayName)
            }
            if item.wordCount > 0 {
                ledgerRow("Length", "\(item.wordCount) words")
            }
            if let perf {
                ledgerRow("Performance", "\(perf.views) views · \(perf.likes) likes · \(perf.comments) comments")
            }
        }
        .padding(.vertical, DS.space6)
    }

    private func ledgerRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(DS.giltInk)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space6)
    }

    private var excerpt: some View {
        ScrollView {
            Text(excerptText)
                .font(DS.body)
                .foregroundStyle(excerptText.isEmpty ? DS.textMuted : DS.text)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.space20)
        }
        .frame(maxHeight: 260)
    }

    private var excerptText: String {
        let body = (item.atom.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return "Nothing written yet — open it to start the draft." }
        return String(body.prefix(1200))
    }

    private var footer: some View {
        HStack(spacing: DS.space8) {
            Button("Open in Pane", action: onOpenAsPane)
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            if !item.isShipped {
                Button(item.scheduledAt == nil ? "Plan publication…" : "Change publication date…", action: onSchedule)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textSecondary)
            }
            Button(action: onOpen) {
                Text("Open")
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .frame(height: 30)
                    .background(DS.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .font(DS.callout)
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
    }

    private var keyboard: some View {
        Group {
            Button("", action: onClose).keyboardShortcut(.escape, modifiers: [])
            Button("", action: onClose).keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
