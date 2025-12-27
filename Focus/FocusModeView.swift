// CosmoOS/Focus/FocusModeView.swift
// Full-screen "Thinking Canvas" for deep work
// The premium focus mode for CosmoOS - leverages Apple Silicon for 120Hz animations

import SwiftUI
import GRDB

/// Main entry point for focus mode - delegates to FocusCanvasView for the premium experience
struct FocusModeView: View {
    let entity: EntitySelection

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoiceEngine

    var body: some View {
        FocusCanvasView(entity: entity)
            .environmentObject(appState)
            .environmentObject(voiceEngine)
    }
}

// MARK: - Orbiting Block View
/// Premium orbiting block with Cosmo styling and spring physics
struct OrbitingBlockView: View {
    let block: OrbitingBlock
    let onTap: () -> Void
    let onDrag: (CGPoint) -> Void

    @State private var isHovered = false
    @State private var dragOffset: CGSize = .zero

    private var entityColor: Color {
        CosmoMentionColors.color(for: block.entityType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(entityColor)

                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(CosmoColors.textPrimary)

                Spacer()
            }

            // Preview
            if let preview = block.preview {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(2)
            }

            // Relevance indicator
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < block.relevanceScore ? entityColor : CosmoColors.glassGrey)
                        .frame(width: 4, height: 4)
                }

                Spacer()

                Text("Related")
                    .font(.system(size: 9))
                    .foregroundColor(CosmoColors.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CosmoColors.softWhite)
                .shadow(
                    color: entityColor.opacity(isHovered ? 0.35 : 0.15),
                    radius: isHovered ? 20 : 10,
                    y: isHovered ? 8 : 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entityColor.opacity(isHovered ? 0.6 : 0.25), lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .offset(dragOffset)
        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = gesture.translation
                }
                .onEnded { gesture in
                    // If dragged significantly, trigger insertion
                    if abs(gesture.translation.width) > 100 || abs(gesture.translation.height) > 100 {
                        onDrag(CGPoint(x: gesture.location.x, y: gesture.location.y))
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
        )
    }
}

// Note: Content editing is implemented in `CosmoOS/Editor/ContentEditorView.swift`
// to ensure Ideas + Content share the same TextKit-based editor core.

// MARK: - Research Detail View
struct ResearchDetailView: View {
    let researchId: Int64

    @State private var research: Research?

    private let database = CosmoDatabase.shared

    var body: some View {
        VStack(spacing: 0) {
            if let research = research {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(research.title ?? "Untitled")
                            .font(.system(size: 22, weight: .bold))

                        if let url = research.url {
                            Link(destination: URL(string: url)!) {
                                Text(url)
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    if let type = research.researchType {
                        Text(type)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let summary = research.summary {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Summary")
                                    .font(.headline)

                                Text(summary)
                                    .font(.body)
                            }
                        }

                        if !research.content.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Content")
                                    .font(.headline)

                                Text(research.content)
                                    .font(.body)
                            }
                        }

                        if let findings = research.findings {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Findings")
                                    .font(.headline)

                                Text(findings)
                                    .font(.body)
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadResearch()
        }
    }

    private func loadResearch() {
        Task {
            research = try? await database.asyncRead { db in
                guard let atom = try Atom.filter(Column("id") == researchId).fetchOne(db),
                      atom.type == .research else { return nil }
                return ResearchWrapper(atom: atom)
            }
        }
    }
}

// MARK: - Generic Entity Editor
struct GenericEntityEditor: View {
    let entity: EntitySelection

    var body: some View {
        VStack {
            Text("Editing \(entity.type.rawValue)")
                .font(.headline)

            Text("ID: \(entity.id)")
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let voiceTranscription = Notification.Name("voiceTranscription")
    // Note: bringRelatedBlocks is defined in VoiceNotifications.swift

}
