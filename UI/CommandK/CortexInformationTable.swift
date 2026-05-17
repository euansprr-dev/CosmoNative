// CosmoOS/UI/CommandK/CortexInformationTable.swift
// The "INFORMATION" metadata table for the Raycast-style detail pane.
// Universal, safe fields only (type / dates / link count) from guaranteed
// Atom columns — no fragile per-type metadata-JSON parsing.

import SwiftUI

struct CortexInformationTable: View {
    let typeLabel: String
    let created: String?
    let updated: String?
    let links: Int?
    /// Shown as "Captured" when the atom hasn't been fetched yet (or has no dates).
    let fallbackMeta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            AtelierOrnamentalSectionLabel(label: "INFORMATION")
            row("Type", typeLabel)
            if let created {
                row("Created", created)
            } else if let fallbackMeta, !fallbackMeta.isEmpty {
                row("Captured", fallbackMeta)
            }
            if let updated, updated != created {
                row("Updated", updated)
            }
            if let links, links > 0 {
                row("Links", "\(links) connected")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.inkFaded)
            Spacer(minLength: DS.space12)
            Text(value)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }
}

/// ISO8601 → "MMM d, yyyy" (tolerates the fractional-seconds variant the app
/// writes for createdAt/updatedAt). Returns nil for empty/unparseable input.
func cortexFormatISO(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = withFractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    guard let date else { return nil }
    let out = DateFormatter()
    out.dateFormat = "MMM d, yyyy"
    return out.string(from: date)
}
