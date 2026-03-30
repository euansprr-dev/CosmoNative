// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsFabricView.swift
// Deep fabric synthesis — the soul of the analysis, beautifully typeset

import SwiftUI

struct PhysicsFabricView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space6) {
                Text("THE FABRIC")
                    .font(DS.caption)
                    .tracking(1.2)
                    .foregroundStyle(DS.entitySwipe)
                Spacer()
            }

            fabricContent
        }
        .padding(DS.space16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DS.entitySwipe)
                .frame(width: 3)
                .padding(.vertical, DS.space16)
        }
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
    }

    @ViewBuilder
    private var fabricContent: some View {
        // Parse markdown-style **bold** headers into attributed text sections
        let sections = parseFabricText(text)
        VStack(alignment: .leading, spacing: DS.space12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                if section.isHeader {
                    Text(section.text)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.text)
                        .padding(.top, DS.space4)
                } else {
                    Text(section.text)
                        .font(DS.body)
                        .foregroundStyle(DS.text.opacity(0.9))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private struct FabricSection {
        let text: String
        let isHeader: Bool
    }

    private func parseFabricText(_ raw: String) -> [FabricSection] {
        var sections: [FabricSection] = []
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var currentParagraph = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") {
                // Flush current paragraph
                if !currentParagraph.isEmpty {
                    sections.append(FabricSection(text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines), isHeader: false))
                    currentParagraph = ""
                }
                // Add header (strip ** markers)
                let header = trimmed.replacingOccurrences(of: "**", with: "")
                sections.append(FabricSection(text: header, isHeader: true))
            } else if trimmed.isEmpty {
                // Paragraph break
                if !currentParagraph.isEmpty {
                    sections.append(FabricSection(text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines), isHeader: false))
                    currentParagraph = ""
                }
            } else {
                currentParagraph += (currentParagraph.isEmpty ? "" : " ") + trimmed
            }
        }

        if !currentParagraph.isEmpty {
            sections.append(FabricSection(text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines), isHeader: false))
        }

        return sections
    }
}
