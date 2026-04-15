// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsFabricView.swift
// Deep fabric synthesis — editorial magazine typography treatment

import SwiftUI

struct PhysicsFabricView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            fabricTitle
            fabricBody
        }
        .padding(DS.space24)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
    }

    // MARK: - Title

    @ViewBuilder
    private var fabricTitle: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Deep Fabric")
                .font(DS.title2)
                .foregroundStyle(DS.entityNote)
            Text("The soul of this content")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var fabricBody: some View {
        let sections = parseFabricText(text)
        VStack(alignment: .leading, spacing: DS.space12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if section.isHeader {
                    headerRow(section.text, showDivider: index > 0)
                } else {
                    paragraphRow(section.text)
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Section Rows

    @ViewBuilder
    private func headerRow(_ title: String, showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            if showDivider {
                Rectangle()
                    .fill(DS.borderSubtle)
                    .frame(height: 0.5)
            }
            Text(title)
                .font(DS.headline)
                .foregroundStyle(DS.text)
        }
        .padding(.top, DS.space20)
    }

    @ViewBuilder
    private func paragraphRow(_ content: String) -> some View {
        Text(content)
            .font(DS.body)
            .foregroundStyle(DS.text.opacity(0.9))
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Parser

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
                if !currentParagraph.isEmpty {
                    sections.append(FabricSection(
                        text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines),
                        isHeader: false
                    ))
                    currentParagraph = ""
                }
                let header = trimmed.replacingOccurrences(of: "**", with: "")
                sections.append(FabricSection(text: header, isHeader: true))
            } else if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    sections.append(FabricSection(
                        text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines),
                        isHeader: false
                    ))
                    currentParagraph = ""
                }
            } else {
                currentParagraph += (currentParagraph.isEmpty ? "" : " ") + trimmed
            }
        }

        if !currentParagraph.isEmpty {
            sections.append(FabricSection(
                text: currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines),
                isHeader: false
            ))
        }

        return sections
    }
}
