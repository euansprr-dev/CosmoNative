// CosmoOS/UI/FocusMode/Synthesis/SynthesisSourceCard.swift
// Compact card showing a source atom in the synthesis workspace

import SwiftUI

struct SynthesisSourceCard: View {
    let atom: Atom
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or type icon
            thumbnailView
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                // Title
                Text(atom.title ?? "Untitled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                // Clean content preview (summary/findings, not raw body)
                Text(previewText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Source index badge
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(DS.textMuted)
                .frame(width: 20, height: 20)
                .background(DS.border)
                .clipShape(Circle())
        }
        .padding(12)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let urlString = atom.thumbnailUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    iconFallback
                default:
                    iconFallback
                }
            }
        } else {
            iconFallback
        }
    }

    private var iconFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(accentColor.opacity(0.15))

            Image(systemName: typeIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(accentColor)
        }
    }

    // MARK: - Preview Text

    /// Show a clean human-readable preview — prefer summary/findings over raw body
    private var previewText: String {
        // For research atoms, prefer summary or findings
        if atom.type == .research {
            if let summary = atom.summary, !summary.isEmpty {
                return String(summary.prefix(120))
            }
            if let findings = atom.findings, !findings.isEmpty {
                return String(findings.prefix(120))
            }
        }

        // For ideas, prefer the body but skip if it looks like JSON
        if let body = atom.body, !body.isEmpty {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip raw JSON — show a clean fallback instead
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                if let summary = atom.summary, !summary.isEmpty {
                    return String(summary.prefix(120))
                }
                return atom.type.rawValue.capitalized
            }
            return String(trimmed.prefix(120))
        }

        return atom.type.rawValue.capitalized
    }

    // MARK: - Helpers

    private var typeIcon: String {
        switch atom.type {
        case .idea: return "lightbulb"
        case .research: return "doc.text.magnifyingglass"
        case .connection: return "link"
        case .content: return "doc.richtext"
        case .note: return "note.text"
        case .task: return "checkmark.circle"
        default: return "doc"
        }
    }

    private var accentColor: Color {
        switch atom.type {
        case .idea: return Color(hex: "818CF8")       // Indigo
        case .research: return Color(hex: "38BDF8")   // Sky blue
        case .connection: return DS.accent             // Purple
        case .content: return Color(hex: "34D399")    // Emerald
        case .note: return Color(hex: "FB923C")       // Orange
        case .task: return DS.green
        default: return DS.textSecondary
        }
    }
}
