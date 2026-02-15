//
//  SessionSummaryCard.swift
//  CosmoOS
//
//  Modal overlay card shown when a deep work session ends.
//  Displays duration, focus score, distractions, output atoms,
//  XP earned, and optional notes.
//

import SwiftUI

// MARK: - Session Summary Card

struct SessionSummaryCard: View {

    let result: DeepWorkSessionResult
    let onDismiss: (String?) -> Void

    @State private var notes: String = ""
    @State private var showContent = false
    @State private var xpAnimated: Int = 0
    @FocusState private var isNotesFocused: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimming backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Card
            cardContent
                .scaleEffect(showContent ? 1 : 0.9)
                .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            notes = result.notes ?? ""
            withAnimation(PlannerumSprings.expand) {
                showContent = true
            }
            animateXP()
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()
                .background(Color.white.opacity(0.08))

            // Stats grid
            statsGrid
                .padding(24)

            Divider()
                .background(Color.white.opacity(0.08))

            // Notes input
            notesSection
                .padding(24)

            // Done button
            doneButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 14/255, green: 14/255, blue: 22/255).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 40, y: 16)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Focus score ring
            focusScoreRing
                .padding(.top, 28)

            Text("Session Complete")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(PlannerumColors.textPrimary)

            Text(result.taskTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PlannerumColors.textSecondary)
                .lineLimit(1)

            // XP earned (animated)
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                Text("+\(xpAnimated) XP")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
            }
            .foregroundColor(PlannerumColors.xpGold)

            // Dimension badge showing where XP was routed
            dimensionBadge
                .padding(.bottom, 20)
        }
    }

    // MARK: - Dimension Badge

    private var dimensionBadge: some View {
        VStack(spacing: 4) {
            ForEach(Array(result.dimensionAllocations.enumerated()), id: \.offset) { _, alloc in
                dimensionAllocationBadge(alloc)
            }
        }
    }

    @ViewBuilder
    private func dimensionAllocationBadge(_ alloc: DimensionXPAllocation) -> some View {
        let rgb = DimensionXPRouter.dimensionColor(alloc.dimension)
        let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        let name = DimensionXPRouter.dimensionDisplayName(alloc.dimension)

        HStack(spacing: 6) {
            Text("+\(alloc.xp) XP")
                .font(.system(size: 11, weight: .bold, design: .monospaced))

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))

            Text(name)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Focus Score Ring

    private var focusScoreRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
                .frame(width: 72, height: 72)

            // Fill
            Circle()
                .trim(from: 0, to: result.focusScore / 100)
                .stroke(
                    focusScoreColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))

            // Score text
            Text("\(Int(result.focusScore))")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(focusScoreColor)
        }
    }

    private var focusScoreColor: Color {
        let score = result.focusScore
        if score >= 80 { return Color(red: 34/255, green: 197/255, blue: 94/255) }
        if score >= 60 { return Color(red: 234/255, green: 179/255, blue: 8/255) }
        if score >= 40 { return Color(red: 249/255, green: 115/255, blue: 22/255) }
        return Color(red: 239/255, green: 68/255, blue: 68/255)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            statCell(
                icon: "clock",
                label: "Duration",
                value: durationString,
                detail: "planned \(result.plannedMinutes)m"
            )

            statCell(
                icon: "eye.slash",
                label: "Distractions",
                value: "\(result.distractionCount)",
                detail: nil
            )

            statCell(
                icon: "doc.text",
                label: "Output",
                value: "\(result.outputAtomCount)",
                detail: "atoms created"
            )

            statCell(
                icon: "target",
                label: "Focus Score",
                value: "\(Int(result.focusScore))%",
                detail: nil
            )
        }
    }

    private func statCell(icon: String, label: String, value: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(PlannerumColors.textMuted)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(PlannerumColors.textPrimary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)

            if let detail = detail {
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var durationString: String {
        let mins = result.actualMinutes
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Notes")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(PlannerumTypography.trackingWide)

            TextEditor(text: $notes)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PlannerumColors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isNotesFocused)
                .frame(height: 60)
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isNotesFocused ? PlannerumColors.primary.opacity(0.4) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty && !isNotesFocused {
                        Text("What did you accomplish?")
                            .font(.system(size: 13))
                            .foregroundColor(PlannerumColors.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: { dismiss() }) {
            Text("Done")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PlannerumColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: - Helpers

    private func dismiss() {
        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(PlannerumSprings.expand) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss(finalNotes.isEmpty ? nil : finalNotes)
        }
    }

    private func animateXP() {
        let target = result.xpEarned
        let steps = min(target, 30)
        guard steps > 0 else {
            xpAnimated = target
            return
        }

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) {
                xpAnimated = Int(Double(target) * (Double(i) / Double(steps)))
            }
        }
    }
}
