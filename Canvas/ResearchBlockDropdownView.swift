// CosmoOS/Canvas/ResearchBlockDropdownView.swift
// Collapsible dropdown content for Research block canvas cards
// Shows transcript text and annotations in a compact, tabbed layout
// Dark glass design matching Sanctuary aesthetic

import SwiftUI

struct ResearchBlockDropdownView: View {
    let atomUUID: String
    let atomBody: String?

    @State private var selectedTab: DropdownTab = .transcript
    @State private var researchState: ResearchFocusModeState?
    @State private var parsedTranscript: [TranscriptEntry] = []
    @State private var isLoaded = false

    enum DropdownTab: String, CaseIterable {
        case transcript
        case annotations

        var label: String {
            switch self {
            case .transcript: return "Transcript"
            case .annotations: return "Annotations"
            }
        }

        var icon: String {
            switch self {
            case .transcript: return "text.alignleft"
            case .annotations: return "note.text"
            }
        }
    }

    /// Lightweight model for parsed transcript entries
    struct TranscriptEntry: Identifiable {
        let id = UUID()
        let start: Double
        let text: String

        var formattedTime: String {
            let minutes = Int(start) / 60
            let seconds = Int(start) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // Accent color matching research blocks
    private let accentColor = CosmoColors.blockResearch

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            tabBar

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Content
            tabContent
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear {
            loadData()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DropdownTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 9))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? accentColor : Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        selectedTab == tab
                            ? accentColor.opacity(0.08)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .transcript:
            transcriptTab
        case .annotations:
            annotationsTab
        }
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        Group {
            if !parsedTranscript.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(parsedTranscript) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                // Timestamp
                                Text(entry.formattedTime)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(accentColor.opacity(0.7))
                                    .frame(width: 32, alignment: .trailing)

                                // Text
                                Text(entry.text)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.white.opacity(0.65))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 250)
            } else if !isLoaded {
                // Loading state
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(accentColor)
                    Text("Loading transcript...")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // Empty state
                emptyState(
                    icon: "text.alignleft",
                    message: "No transcript available"
                )
            }
        }
    }

    // MARK: - Annotations Tab

    private var annotationsTab: some View {
        Group {
            let allAnnotations = collectAnnotations()

            if !allAnnotations.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Group by type
                        ForEach(AnnotationType.allCases, id: \.self) { type in
                            let group = allAnnotations.filter { $0.type == type }
                            if !group.isEmpty {
                                annotationGroup(type: type, annotations: group)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 250)
            } else if !isLoaded {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(accentColor)
                    Text("Loading annotations...")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                emptyState(
                    icon: "note.text",
                    message: "No annotations yet"
                )
            }
        }
    }

    // MARK: - Annotation Group

    private func annotationGroup(type: AnnotationType, annotations: [ResearchAnnotation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type header with badge
            HStack(spacing: 5) {
                // Colored accent bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(type.color)
                    .frame(width: 2, height: 12)

                Image(systemName: type.icon)
                    .font(.system(size: 9))
                    .foregroundColor(type.color)

                Text(type.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(type.color)
                    .tracking(0.5)

                // Count badge
                Text("\(annotations.count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(type.color.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(type.color.opacity(0.12), in: Capsule())
            }

            // Annotation items
            ForEach(annotations) { annotation in
                HStack(alignment: .top, spacing: 6) {
                    // Colored accent bar
                    RoundedRectangle(cornerRadius: 1)
                        .fill(type.color.opacity(0.4))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        // Timestamp
                        Text(annotation.timestampString)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(type.color.opacity(0.6))

                        // Content
                        if !annotation.content.isEmpty {
                            Text(annotation.content)
                                .font(.system(size: 10))
                                .foregroundColor(Color.white.opacity(0.6))
                                .lineLimit(2)
                        } else {
                            Text("(empty)")
                                .font(.system(size: 10))
                                .foregroundColor(Color.white.opacity(0.25))
                                .italic()
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color.white.opacity(0.15))

            Text(message)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Data Loading

    private func loadData() {
        // Parse transcript from atom body (JSON array of segments)
        parseTranscript()

        // Load persisted research state for annotations
        if let state = ResearchFocusModeState.load(atomUUID: atomUUID) {
            researchState = state
        }

        isLoaded = true
    }

    /// Parse `atomBody` JSON to extract transcript entries.
    /// Expected format: `[{"start": Double, "text": String}, ...]`
    /// Also handles the full TranscriptSegment format with "end", "speaker", etc.
    private func parseTranscript() {
        guard let body = atomBody,
              !body.isEmpty,
              let data = body.data(using: .utf8) else {
            return
        }

        // Try decoding as array of transcript segment objects
        if let segments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            parsedTranscript = segments.compactMap { segment in
                guard let start = segment["start"] as? Double,
                      let text = segment["text"] as? String else {
                    return nil
                }
                return TranscriptEntry(start: start, text: text)
            }
        }
    }

    /// Collect all annotations from the loaded research state
    private func collectAnnotations() -> [ResearchAnnotation] {
        guard let state = researchState else { return [] }
        return state.allAnnotations
    }
}

// MARK: - Preview

#if DEBUG
struct ResearchBlockDropdownView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // With transcript data
                ResearchBlockDropdownView(
                    atomUUID: "preview-uuid",
                    atomBody: """
                    [
                        {"start": 0, "end": 15, "text": "Identity is not fixed. It is a story you tell yourself."},
                        {"start": 15, "end": 32, "text": "Real transformation comes from subtraction, not addition."},
                        {"start": 32, "end": 48, "text": "Remove what does not serve your vision."},
                        {"start": 48, "end": 65, "text": "Your environment shapes your identity more than willpower ever will."},
                        {"start": 65, "end": 80, "text": "Design your environment to support the person you want to become."}
                    ]
                    """
                )
                .frame(width: 280)

                // Empty state
                ResearchBlockDropdownView(
                    atomUUID: "empty-preview",
                    atomBody: nil
                )
                .frame(width: 280)
            }
            .padding(20)
        }
        .frame(width: 400, height: 500)
    }
}
#endif
