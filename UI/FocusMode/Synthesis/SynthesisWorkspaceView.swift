// CosmoOS/UI/FocusMode/Synthesis/SynthesisWorkspaceView.swift
// Full-screen synthesis workspace — AI combines lasso-selected blocks into new understanding

import SwiftUI

struct SynthesisWorkspaceView: View {
    let sourceAtoms: [Atom]
    let onCreateConnection: (LassoSynthesisResult) -> Void
    let onDismiss: () -> Void

    @StateObject private var engine = SynthesisEngine()
    @State private var editableArgument: String = ""
    @State private var showEvidence = false

    var body: some View {
        ZStack {
            // Background
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                headerBar

                // Two-column layout
                HStack(spacing: 0) {
                    // Left: Sources (40%)
                    sourcesColumn
                        .frame(maxWidth: .infinity)

                    // Divider
                    Rectangle()
                        .fill(DS.border)
                        .frame(width: 1)

                    // Right: Synthesis (60%)
                    synthesisColumn
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: 0, maxWidth: .infinity)
                }

                // Action bar
                actionBar
            }
        }
        .task {
            let result = await engine.synthesize(atoms: sourceAtoms)
            editableArgument = result.synthesizedArgument
        }
        .onExitCommand {
            onDismiss()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.accent)

            Text("Synthesis Workspace")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            Text("\(sourceAtoms.count) sources")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DS.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.border).frame(height: 1)
        }
    }

    // MARK: - Sources Column (Left 40%)

    private var sourcesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("SOURCES")
                .font(DS.sectionLabel)
                .foregroundColor(DS.textMuted)
                .tracking(0.8)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(sourceAtoms.enumerated()), id: \.element.uuid) { index, atom in
                        SynthesisSourceCard(atom: atom, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Synthesis Column (Right 60%)

    private var synthesisColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with regenerate button
            HStack {
                Text("SYNTHESIS")
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(0.8)

                Spacer()

                if !engine.isGenerating {
                    Button {
                        Task {
                            let result = await engine.synthesize(atoms: sourceAtoms)
                            editableArgument = result.synthesizedArgument
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                            Text("Regenerate")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DS.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if engine.isGenerating {
                generatingState
            } else if let result = engine.result {
                synthesisContent(result)
            }
        }
    }

    // MARK: - Generating State

    private var generatingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text("Synthesizing insights...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Synthesis Content

    private func synthesisContent(_ result: LassoSynthesisResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Suggested title
                if !result.suggestedTitle.isEmpty {
                    Text(result.suggestedTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DS.text)
                }

                // Themes
                if !result.themes.isEmpty {
                    themesSection(result.themes)
                }

                // Synthesized argument (editable)
                argumentSection

                // Open questions
                if !result.openQuestions.isEmpty {
                    openQuestionsSection(result.openQuestions)
                }

                // Evidence spans (collapsible)
                if !result.evidenceSpans.isEmpty {
                    evidenceSection(result.evidenceSpans)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Themes

    private func themesSection(_ themes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Themes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            FlowLayout(spacing: 6) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DS.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Argument

    private var argumentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synthesized Argument")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            TextEditor(text: $editableArgument)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DS.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(DS.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.border, lineWidth: 1)
                )
                .frame(minHeight: 160)
        }
    }

    // MARK: - Open Questions

    private func openQuestionsSection(_ questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Questions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(questions, id: \.self) { question in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(DS.orange)
                            .padding(.top, 1)
                        Text(question)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(DS.text)
                    }
                }
            }
            .padding(12)
            .background(DS.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Evidence

    private func evidenceSection(_ spans: [LassoEvidenceSpan]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    showEvidence.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showEvidence ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Evidence (\(spans.count) citations)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)

            if showEvidence {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(spans) { span in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(span.claim)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.text)

                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(DS.accent.opacity(0.4))
                                    .frame(width: 2)

                                Text("\"\(span.excerpt)\"")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(DS.textMuted)
                                    .italic()
                            }

                            // Source label
                            if let sourceAtom = sourceAtoms.first(where: { $0.uuid == span.sourceAtomUUID }) {
                                Text("Source: \(sourceAtom.title ?? "Untitled")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.accent.opacity(0.7))
                            }
                        }
                        .padding(10)
                        .background(DS.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Spacer()

            // Cancel
            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Export (tertiary)
            Button {
                exportToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                    Text("Export")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Create Note (secondary)
            Button {
                if let result = engine.result {
                    var noteResult = result
                    noteResult.synthesizedArgument = editableArgument
                    onCreateConnection(noteResult)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .medium))
                    Text("Create Note")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(DS.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.borderActive, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(engine.isGenerating)

            // Create Connection (primary)
            Button {
                if let result = engine.result {
                    var connectionResult = result
                    connectionResult.synthesizedArgument = editableArgument
                    onCreateConnection(connectionResult)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Create Connection")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(engine.isGenerating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(DS.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.border).frame(height: 1)
        }
    }

    // MARK: - Export

    private func exportToClipboard() {
        guard let result = engine.result else { return }
        var text = "# \(result.suggestedTitle)\n\n"
        if !result.themes.isEmpty {
            text += "## Themes\n"
            for theme in result.themes {
                text += "- \(theme)\n"
            }
            text += "\n"
        }
        text += "## Synthesis\n\(editableArgument)\n\n"
        if !result.openQuestions.isEmpty {
            text += "## Open Questions\n"
            for q in result.openQuestions {
                text += "- \(q)\n"
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Flow Layout (for theme chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (CGSize(width: totalWidth, height: currentY + lineHeight), positions)
    }
}
