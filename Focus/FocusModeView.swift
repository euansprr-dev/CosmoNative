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
