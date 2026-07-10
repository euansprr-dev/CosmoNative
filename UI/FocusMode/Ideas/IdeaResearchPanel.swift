// CosmoOS/UI/FocusMode/Ideas/IdeaResearchPanel.swift
// Displays research findings in the idea intelligence sidebar.
// Premium redesign — April 2026

import SwiftUI

struct IdeaResearchPanel: View {
    @Binding var results: [IdeaResearchResult]
    let ideaText: String
    let clientNiche: String?

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            content
        }
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance.delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .frame(width: 22, height: 22)
                    .background(DS.accent.opacity(0.1), in: Circle())
                    .accessibilityHidden(true)
                Text("Research")
                    .font(DS.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.text)
                if !results.isEmpty {
                    Text("\(results.count)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DS.accent.opacity(0.1), in: Capsule())
                }
            }

            Spacer()

            Button {
                Task { await runResearch() }
            } label: {
                researchButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(isLoading || ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var researchButtonLabel: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(results.isEmpty ? "Run Research" : "Refresh")
                .font(DS.caption2)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.accent.opacity(0.1), in: Capsule())
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if results.isEmpty && !isLoading {
            emptyState
        } else if isLoading && results.isEmpty {
            loadingState
        } else {
            resultsList
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                researchCard(result, index: index)
            }
        }
    }

    @State private var expandedResultIds: Set<UUID> = []

    private func researchCard(_ result: IdeaResearchResult, index: Int) -> some View {
        let proofColor = proofTypeColor(result.proofType ?? "")
        let isExpanded = expandedResultIds.contains(result.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(DS.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.text)
                        .lineLimit(isExpanded ? nil : 2)
                    Text(result.snippet)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(isExpanded ? nil : 3)
                    if isExpanded, let url = result.url, !url.isEmpty {
                        Text(url)
                            .font(.system(size: 9))
                            .foregroundStyle(DS.info)
                            .lineLimit(1)
                    }
                }
                Spacer()
                includeToggle(index: index, isIncluded: result.isIncluded)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) {
                    if isExpanded {
                        expandedResultIds.remove(result.id)
                    } else {
                        expandedResultIds.insert(result.id)
                    }
                }
            }
            researchCardFooter(result, proofColor: proofColor)
        }
        .padding(10)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(result.isIncluded ? DS.green.opacity(0.3) : DS.borderSubtle, lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(ProMotionSprings.staggered(index: index), value: appeared)
    }

    private func researchCardFooter(_ result: IdeaResearchResult, proofColor: Color) -> some View {
        HStack(spacing: 6) {
            if let proofType = result.proofType, !proofType.isEmpty {
                proofTypeTag(proofType, color: proofColor)
            }
            Text(result.source)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
            Spacer()
            if let url = result.url, !url.isEmpty {
                linkButton(url)
            }
        }
    }

    private func proofTypeTag(_ name: String, color: Color) -> some View {
        Text(name)
            .font(DS.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(DS.opacitySubtle), in: Capsule())
    }

    // MARK: - Subviews

    private func includeToggle(index: Int, isIncluded: Bool) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                results[index].isIncluded.toggle()
            }
        } label: {
            Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isIncluded ? DS.green : DS.textMuted)
        }
        .buttonStyle(.plain)
        .help(isIncluded ? "Exclude from draft" : "Include in draft")
    }

    private func linkButton(_ url: String) -> some View {
        Button {
            if let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 10))
                .foregroundStyle(DS.accent)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(DS.accent.opacity(0.3))
                .accessibilityHidden(true)
            Text("Tap Research to find supporting evidence")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(DS.accent.opacity(0.02), in: .rect(cornerRadius: DS.radiusSmall))
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Finding stats, studies & evidence...")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(DS.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
        }
        .padding(8)
        .background(DS.orange.opacity(0.08), in: .rect(cornerRadius: 6))
    }

    // MARK: - Research Action

    private func runResearch() async {
        isLoading = true
        errorMessage = nil
        do {
            let findings = try await IdeaResearchAgent.shared.research(
                ideaText: ideaText,
                clientNiche: clientNiche
            )
            results = findings
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func proofTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "statistic": return DS.accent
        case "case study": return DS.green
        case "expert quote": return DS.orange
        case "social proof": return Color.purple
        case "analogy": return Color.teal
        case "contrarian data": return DS.red
        case "historical precedent": return Color.brown
        case "scientific study": return Color.indigo
        default: return DS.textMuted
        }
    }
}
