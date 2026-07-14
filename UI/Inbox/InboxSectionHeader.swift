// CosmoOS/UI/Inbox/InboxSectionHeader.swift
// Pinned ledger section header — small caps, hairline, Command Center grammar.
// June 2026 — Inbox Revamp

import SwiftUI

struct InboxSectionHeader: View {
    let title: String
    let itemCount: Int

    var body: some View {
        // The one ledger-header voice (CosmoSectionHeader), wrapped with the
        // pinned-header background so the queue's temporal sections stay
        // legible while rows scroll beneath.
        CosmoSectionHeader(label: title, detail: "\(itemCount)")
            .padding(.horizontal, DS.space16)
            .padding(.top, DS.space16)
            .padding(.bottom, DS.space6)
            .background(DS.bg.opacity(0.96))
            .accessibilityLabel("\(title), \(itemCount) capture\(itemCount == 1 ? "" : "s")")
    }
}
