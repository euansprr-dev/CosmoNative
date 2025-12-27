// CosmoOS/SwipeFile/InstagramSwipeModal.swift
// Modal for manual Instagram content entry (IG blocks programmatic access)
// Follows Cosmo design language - soft, pastel, premium feel

import SwiftUI

struct InstagramSwipeModal: View {
    @Binding var isPresented: Bool
    let pendingItem: Research?
    let onSave: (String, String?) async -> Void
    let onCancel: () -> Void

    @State private var hook = ""
    @State private var transcript = ""
    @State private var selectedType: ResearchRichContent.InstagramContentType
    @FocusState private var isHookFocused: Bool
    @FocusState private var isTranscriptFocused: Bool

    @State private var isSaving = false

    init(
        isPresented: Binding<Bool>,
        pendingItem: Research?,
        onSave: @escaping (String, String?) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.pendingItem = pendingItem
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize selected type from pending item
        let initialType: ResearchRichContent.InstagramContentType
        if let item = pendingItem, let richContent = item.richContent {
            initialType = richContent.instagramContentType ?? .reel
        } else {
            initialType = .reel
        }
        self._selectedType = State(initialValue: initialType)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .background(CosmoColors.glassGrey.opacity(0.4))

            formContent

            Divider()
                .background(CosmoColors.glassGrey.opacity(0.4))

            footer
        }
        .frame(width: 520, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CosmoColors.softWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 30, y: 15)
        .onAppear {
            isHookFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Instagram icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#F58529"),
                                Color(hex: "#DD2A7B"),
                                Color(hex: "#8134AF")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: contentTypeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Save Instagram Content")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)

                if let url = pendingItem?.url {
                    Text(truncatedUrl(url))
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: {
                onCancel()
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contentTypePicker
                hookField
                transcriptField
                helpText
            }
            .padding(24)
        }
    }

    // MARK: - Content Type Picker

    private var contentTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content Type")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 8) {
                ForEach([
                    ResearchRichContent.InstagramContentType.reel,
                    .post,
                    .carousel
                ], id: \.rawValue) { type in
                    ContentTypeChip(
                        type: type,
                        isSelected: selectedType == type,
                        onTap: { selectedType = type }
                    )
                }

                Spacer()
            }
        }
    }

    // MARK: - Hook Field

    private var hookField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hook")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)

                Text("(required)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CosmoColors.coral.opacity(0.8))
            }

            ZStack(alignment: .topLeading) {
                if hook.isEmpty {
                    Text("What's the opening line that grabbed you?")
                        .font(.system(size: 15))
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }

                TextField("", text: $hook, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(12)
                    .focused($isHookFocused)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHookFocused ? instagramGradientColor.opacity(0.5) : CosmoColors.glassGrey.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Transcript Field

    private var transcriptField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)

                Text("(optional)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CosmoColors.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if transcript.isEmpty {
                    Text("Paste or type the full transcript here...")
                        .font(.system(size: 15))
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $transcript)
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isTranscriptFocused)
            }
            .frame(minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isTranscriptFocused ? instagramGradientColor.opacity(0.5) : CosmoColors.glassGrey.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Help Text

    private var helpText: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.lavender)

            Text("Tip: Open the Reel in Instagram, then manually type or paste the caption/transcript here. Instagram doesn't allow automatic capture.")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.lavender.opacity(0.08))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
                isPresented = false
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: saveItem) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text("Save to Swipe File")
                }
            }
            .buttonStyle(InstagramButtonStyle())
            .disabled(!isFormValid || isSaving)
            .opacity(isFormValid && !isSaving ? 1.0 : 0.5)
        }
        .padding(20)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !hook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contentTypeIcon: String {
        switch selectedType {
        case .reel: return "video.fill"
        case .post: return "photo.fill"
        case .carousel: return "square.stack.fill"
        case .story: return "circle.dashed"
        }
    }

    private var instagramGradientColor: Color {
        Color(hex: "#DD2A7B") // Instagram pink
    }

    private func truncatedUrl(_ url: String) -> String {
        if url.count > 45 {
            return String(url.prefix(45)) + "..."
        }
        return url
    }

    private func saveItem() {
        guard isFormValid else { return }
        isSaving = true

        let trimmedHook = hook.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await onSave(trimmedHook, trimmedTranscript.isEmpty ? nil : trimmedTranscript)
            isSaving = false
            isPresented = false
        }
    }
}

// MARK: - Content Type Chip

private struct ContentTypeChip: View {
    let type: ResearchRichContent.InstagramContentType
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))

                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : CosmoColors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(instagramGradient)
                    } else {
                        Capsule().fill(Color.clear)
                    }
                }
            )
            .background(
                Capsule()
                    .fill(isHovered && !isSelected ? CosmoColors.glassGrey.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : CosmoColors.glassGrey.opacity(0.4),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var iconName: String {
        switch type {
        case .reel: return "video.fill"
        case .post: return "photo.fill"
        case .carousel: return "square.stack.fill"
        case .story: return "circle.dashed"
        }
    }

    private var displayName: String {
        switch type {
        case .reel: return "Reel"
        case .post: return "Post"
        case .carousel: return "Carousel"
        case .story: return "Story"
        }
    }

    private var instagramGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#F58529"),
                Color(hex: "#DD2A7B"),
                Color(hex: "#8134AF")
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Instagram Button Style

struct InstagramButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#F58529"),
                                Color(hex: "#DD2A7B"),
                                Color(hex: "#8134AF")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
