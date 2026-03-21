// CosmoOS/UI/FocusMode/Content/GuidedStoryCreatorView.swift
// 8-prompt guided writing screen for brand story creation
// February 2026

import SwiftUI

struct GuidedStoryCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (ProfileDocument) -> Void

    @State private var answers: [String] = Array(repeating: "", count: 8)
    @State private var currentPromptIndex = 0

    private let prompts: [(question: String, hint: String)] = [
        (
            "What were you doing before you started your business? What was your life like?",
            "Set the scene — job, lifestyle, mindset. The relatable starting point."
        ),
        (
            "What was the moment that changed everything? What triggered you to go all in?",
            "The turning point, the breaking moment, the catalyst."
        ),
        (
            "What were the biggest struggles on the way up? Any rock bottom moments?",
            "Vulnerability builds trust. Share the hard parts."
        ),
        (
            "What's your biggest result or achievement?",
            "Revenue, followers, transformation, recognition — make it concrete."
        ),
        (
            "What do you believe that most people in your industry disagree with?",
            "Your contrarian take. This creates polarization and loyalty."
        ),
        (
            "What's your unique approach or method? What makes you different?",
            "Your proprietary framework, philosophy, or system."
        ),
        (
            "Who is your ideal client or audience? What pain are they in right now?",
            "Be specific — demographics, psychographics, current situation."
        ),
        (
            "What's the transformation you help people achieve?",
            "Before → After. The promise of working with you."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.border)
            promptContent
            Divider().background(DS.border)
            bottomBar
        }
        .frame(width: 560, height: 620)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: DS.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 16))
                .foregroundStyle(DS.accent)

            Text("Guided Story Creator")
                .font(DS.cardTitle)
                .foregroundStyle(DS.text)

            Spacer()

            Text("\(answeredCount)/8 answered")
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Prompt Content

    private var promptContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(0..<prompts.count, id: \.self) { index in
                    promptCard(index: index)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func promptCard(index: Int) -> some View {
        let prompt = prompts[index]
        let hasAnswer = !answers[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                promptNumberBadge(index: index, hasAnswer: hasAnswer)

                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.question)
                        .font(DS.buttonText)
                        .foregroundStyle(DS.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(prompt.hint)
                        .font(DS.timestamp)
                        .foregroundStyle(DS.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ZStack(alignment: .topLeading) {
                if answers[index].isEmpty {
                    Text("Write your answer...")
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: $answers[index])
                    .font(DS.cardMeta)
                    .foregroundStyle(DS.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(hasAnswer ? DS.accent.opacity(0.2) : DS.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func promptNumberBadge(index: Int, hasAnswer: Bool) -> some View {
        ZStack {
            Circle()
                .fill(hasAnswer ? DS.accent.opacity(0.2) : DS.border)
                .frame(width: 24, height: 24)

            if hasAnswer {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.accent)
            } else {
                Text("\(index + 1)")
                    .font(DS.sectionLabel)
                    .foregroundStyle(DS.textMuted)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { completeStory() }) {
                doneButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(answeredCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var doneButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text("Done (\(answeredCount) answers)")
                .font(DS.buttonText)
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(answeredCount > 0 ? DS.accent : DS.border)
        )
    }

    // MARK: - Helpers

    private var answeredCount: Int {
        answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private func completeStory() {
        var storyContent = ""
        for (index, prompt) in prompts.enumerated() {
            let answer = answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { continue }
            storyContent += "## \(prompt.question)\n\n\(answer)\n\n"
        }

        let document = ProfileDocument(
            category: .story,
            title: "Guided Brand Story",
            content: storyContent.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onComplete(document)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Guided Story Creator") {
    GuidedStoryCreatorView(onComplete: { _ in })
        .frame(width: 560, height: 620)
}
