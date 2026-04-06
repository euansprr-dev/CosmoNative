// CosmoOS/UI/CosmoWindow/Cards/AtomCardView.swift
// Compact atom preview card for inline chat results

import SwiftUI

struct AtomCardView: View {
    let data: AtomCardData

    var body: some View {
        Button(action: openAtom) {
            HStack(alignment: .top, spacing: 10) {
                typeBadge
                textContent
                Spacer(minLength: 0)
                scoreIndicator
            }
            .padding(16)
            .background(DS.surfaceElevated)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.border, lineWidth: 1)
            )
            .shadow(color: DS.text.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 400)
    }

    // MARK: - Subviews

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForType(data.type))
                .font(.caption2)
                .accessibilityLabel("\(data.type) type")
            Text(data.type.capitalized)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(DS.textOnAccent)
        .background(colorForType(data.type))
        .clipShape(.rect(cornerRadius: 6))
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Text(data.snippet)
                .font(.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var scoreIndicator: some View {
        if let score = data.score {
            Text("\(Int(score * 100))%")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.accentSoft)
                .clipShape(.rect(cornerRadius: 4))
        }
    }

    // MARK: - Helpers

    private func openAtom() {
        NotificationCenter.default.post(
            name: .init("openAtom"),
            object: nil,
            userInfo: ["uuid": data.uuid]
        )
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "idea": return "lightbulb.fill"
        case "research": return "magnifyingglass"
        case "content": return "doc.text.fill"
        case "note": return "note.text"
        case "connection": return "person.fill"
        case "swipe": return "rectangle.stack.fill"
        case "task": return "checkmark.circle.fill"
        default: return "atom"
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "idea": return DS.entityIdea
        case "research": return DS.entityResearch
        case "content": return DS.entityContent
        case "note": return DS.entityNote
        case "connection": return DS.entityConnection
        case "swipe": return DS.entitySwipe
        case "task": return DS.entityTask
        default: return DS.accent
        }
    }
}
