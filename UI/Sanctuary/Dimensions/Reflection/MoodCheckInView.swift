// CosmoOS/UI/Sanctuary/Dimensions/Reflection/MoodCheckInView.swift
// 2D Mood Check-In — Valence/Energy grid input with optional note
// WP6: Reflection Dimension — Journal, Mood, Meditation

import SwiftUI

struct MoodCheckInView: View {
    @Binding var isPresented: Bool
    let onSave: (Double, Double, String?) -> Void

    @State private var valence: Double = 0
    @State private var energy: Double = 0
    @State private var note: String = ""
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("How are you feeling?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SanctuaryColors.Text.primary)

            // 2D Mood Grid
            moodGrid
                .frame(width: 200, height: 200)

            // Current mood indicator
            HStack(spacing: 8) {
                Text(moodEmoji)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 2) {
                    Text(moodLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.primary)

                    Text(moodDescription)
                        .font(.system(size: 11))
                        .foregroundColor(SanctuaryColors.Text.secondary)
                }
            }

            // Note field
            TextField("Add a note (optional)", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.primary)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SanctuaryColors.Glass.highlight)
                )

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(SanctuaryColors.Text.secondary)

                Button(action: {
                    onSave(valence, energy, note.isEmpty ? nil : note)
                    isPresented = false
                }) {
                    Text("Save Mood")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(SanctuaryColors.Dimensions.reflection)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 280)
    }

    // MARK: - Mood Grid

    private var moodGrid: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(SanctuaryColors.Glass.highlight)

                // Grid lines
                gridLines(in: size)

                // Quadrant labels
                quadrantLabels(in: size)

                // Axis labels
                axisLabels(in: size)

                // Draggable indicator
                Circle()
                    .fill(moodColor)
                    .frame(width: isDragging ? 28 : 22, height: isDragging ? 28 : 22)
                    .shadow(color: moodColor.opacity(0.5), radius: isDragging ? 8 : 4)
                    .position(indicatorPosition(in: size))
                    .animation(.spring(response: 0.3), value: isDragging)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let x = value.location.x / size.width
                        let y = value.location.y / size.height
                        valence = max(-1.0, min(1.0, Double((x - 0.5) * 2)))
                        energy = max(-1.0, min(1.0, Double((0.5 - y) * 2)))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        ZStack {
            // Center horizontal
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            }
            .stroke(SanctuaryColors.Glass.border, lineWidth: 1)

            // Center vertical
            Path { path in
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            }
            .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
        }
    }

    private func quadrantLabels(in size: CGSize) -> some View {
        ZStack {
            Text("Excited")
                .position(x: size.width * 0.75, y: size.height * 0.15)

            Text("Anxious")
                .position(x: size.width * 0.25, y: size.height * 0.15)

            Text("Calm")
                .position(x: size.width * 0.75, y: size.height * 0.85)

            Text("Sad")
                .position(x: size.width * 0.25, y: size.height * 0.85)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.6))
    }

    private func axisLabels(in size: CGSize) -> some View {
        ZStack {
            Text("Negative")
                .position(x: 8, y: size.height / 2)
                .rotationEffect(.degrees(-90))

            Text("Positive")
                .position(x: size.width - 8, y: size.height / 2)
                .rotationEffect(.degrees(90))

            Text("High Energy")
                .position(x: size.width / 2, y: 6)

            Text("Low Energy")
                .position(x: size.width / 2, y: size.height - 6)
        }
        .font(.system(size: 7))
        .foregroundColor(SanctuaryColors.Text.tertiary.opacity(0.4))
    }

    private func indicatorPosition(in size: CGSize) -> CGPoint {
        let x = (valence + 1) / 2 * size.width
        let y = (1 - (energy + 1) / 2) * size.height
        return CGPoint(x: x, y: y)
    }

    // MARK: - Computed

    private var moodEmoji: String {
        if valence > 0.3 && energy > 0.3 { return "😊" }
        if valence > 0.3 && energy <= -0.3 { return "😌" }
        if valence <= -0.3 && energy > 0.3 { return "😰" }
        if valence <= -0.3 && energy <= -0.3 { return "😔" }
        return "😐"
    }

    private var moodLabel: String {
        if valence > 0.3 && energy > 0.3 { return "Excited" }
        if valence > 0.3 && energy <= -0.3 { return "Calm" }
        if valence <= -0.3 && energy > 0.3 { return "Anxious" }
        if valence <= -0.3 && energy <= -0.3 { return "Low" }
        return "Balanced"
    }

    private var moodDescription: String {
        let vLabel = valence > 0.3 ? "Positive" : valence < -0.3 ? "Negative" : "Neutral"
        let eLabel = energy > 0.3 ? "High Energy" : energy < -0.3 ? "Low Energy" : "Moderate"
        return "\(vLabel), \(eLabel)"
    }

    private var moodColor: Color {
        let hue = (valence + 1) / 2 * 0.3  // 0 (red) to 0.3 (green-ish)
        let saturation = 0.6 + abs(energy) * 0.3
        let brightness = 0.7 + abs(valence) * 0.2
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

// MARK: - Journal Entry Sheet

struct JournalEntrySheet: View {
    @Binding var isPresented: Bool
    let onSave: (String, String?) -> Void

    @State private var text: String = ""
    @State private var selectedPrompt: String?

    private let prompts = [
        "What am I grateful for today?",
        "What challenged me today and what did I learn?",
        "How am I feeling right now and why?",
        "What would I tell my future self?",
        "What patterns am I noticing in my life?"
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Journal Entry")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SanctuaryColors.Text.primary)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SanctuaryColors.Text.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Prompt suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(prompts, id: \.self) { prompt in
                        promptChip(prompt)
                    }
                }
            }

            // Text editor
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .foregroundColor(SanctuaryColors.Text.primary)
                .frame(minHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SanctuaryColors.Glass.highlight)
                )

            // Footer
            HStack {
                let wordCount = text.split(separator: " ").count
                Text("\(wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(SanctuaryColors.Text.tertiary)

                Spacer()

                Button(action: {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(text, selectedPrompt)
                    isPresented = false
                }) {
                    Text("Save Entry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? SanctuaryColors.Dimensions.reflection.opacity(0.4)
                                      : SanctuaryColors.Dimensions.reflection)
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(SanctuaryColors.Glass.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(SanctuaryColors.Glass.border, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 500, height: 400)
    }

    @ViewBuilder
    private func promptChip(_ prompt: String) -> some View {
        Button(action: {
            selectedPrompt = prompt
            if text.isEmpty {
                text = prompt + "\n\n"
            }
        }) {
            Text(prompt)
                .font(.system(size: 10))
                .foregroundColor(selectedPrompt == prompt ? .white : SanctuaryColors.Text.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedPrompt == prompt
                              ? SanctuaryColors.Dimensions.reflection
                              : SanctuaryColors.Glass.highlight)
                )
        }
        .buttonStyle(.plain)
    }
}
