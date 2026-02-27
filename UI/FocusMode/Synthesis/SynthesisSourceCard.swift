// CosmoOS/UI/FocusMode/Synthesis/SynthesisSourceCard.swift
// Compact card showing a source atom in the synthesis workspace

import SwiftUI

struct SynthesisSourceCard: View {
    let atom: Atom
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Type icon with accent
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: typeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(atom.title ?? "Untitled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                // Content preview
                if let body = atom.body, !body.isEmpty {
                    Text(body.prefix(80).description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DS.textSecondary)
                        .lineLimit(2)
                }
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
