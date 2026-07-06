// CosmoOS/UI/FocusMode/Inquiry/Scan/InquiryScanPanel.swift
// The digitizing panel — a floating glass strip above the thinking bar that
// shows pages arriving, transcribing, and routing. Each page is an honest
// object (its actual thumbnail) whose state whispers beside it; finished
// pages hand off to the session's routing receipts and the panel recedes.

import SwiftUI

@MainActor
struct InquiryScanPanel: View {
    @Bindable var controller: InquiryScanController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            header
            if controller.isWaitingForPhone {
                waitingLine
            } else if !controller.pages.isEmpty {
                pagesRow
            }
            if let note = controller.phoneRequestNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(DS.space12)
        .frame(maxWidth: 420, alignment: .leading)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 18)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    /// The phone hasn't sent pages yet — say exactly what's happening.
    private var waitingLine: some View {
        HStack(spacing: DS.space6) {
            ProgressView().controlSize(.mini)
            Text(controller.phoneRequest?.status == .claimed
                ? "Your iPhone has the scanner open…"
                : "Waking your iPhone…")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "doc.viewfinder")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)

            Text(headline)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
                .contentTransition(.numericText())

            Spacer(minLength: DS.space8)

            Button {
                withAnimation(ProMotionSprings.gentle) {
                    controller.dismissPanel()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(DS.glassSectionFill, in: .circle)
            }
            .buttonStyle(.plain)
            .help("Hide the digitizing panel")
            .accessibilityLabel("Hide the digitizing panel")
        }
    }

    private var headline: String {
        if controller.isBusy {
            return "Digitizing \(controller.pages.count == 1 ? "your page" : "\(controller.pages.count) pages")"
        }
        let units = controller.pages.reduce(0) { total, page in
            if case .done(let count) = page.state { return total + count }
            return total
        }
        return units > 0 ? "\(units) thought\(units == 1 ? "" : "s") routed" : "Scan ready"
    }

    private var pagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                ForEach(controller.pages) { page in
                    pageCell(page)
                }
            }
        }
        .animation(ProMotionSprings.gentle, value: controller.pages.map(\.id))
    }

    private func pageCell(_ page: InquiryScanController.ScanPage) -> some View {
        VStack(spacing: DS.space4) {
            ZStack {
                if let thumbnail = page.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(DS.glassSectionFill)
                }
            }
            .frame(width: 56, height: 74)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.borderSubtle, lineWidth: 0.5)
            )

            stateLine(page.state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(page.pageIndex + 1), \(stateDescription(page.state))")
    }

    @ViewBuilder
    private func stateLine(_ state: InquiryScanController.ScanPage.State) -> some View {
        switch state {
        case .storing, .transcribing:
            HStack(spacing: 3) {
                ProgressView().controlSize(.mini)
                Text("Reading")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        case .routing:
            HStack(spacing: 3) {
                ProgressView().controlSize(.mini)
                Text("Routing")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        case .done(let unitCount):
            Text(unitCount == 1 ? "1 thought" : "\(unitCount) thoughts")
                .font(DS.caption2.monospacedDigit())
                .foregroundStyle(DS.textSecondary)
        case .failed:
            Text("Failed")
                .font(DS.caption2)
                .foregroundStyle(DS.orange)
        }
    }

    private func stateDescription(_ state: InquiryScanController.ScanPage.State) -> String {
        switch state {
        case .storing, .transcribing: return "reading"
        case .routing: return "routing"
        case .done(let count): return "\(count) thoughts routed"
        case .failed(let message): return "failed: \(message)"
        }
    }
}
