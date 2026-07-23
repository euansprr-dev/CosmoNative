// CosmoOS/Focus/FocusModeView.swift
// Full-screen "Thinking Canvas" for deep work
// The premium focus mode for CosmoOS - leverages Apple Silicon for 120Hz animations

import SwiftUI
import GRDB

/// Main entry point for focus mode - delegates to FocusCanvasView for the premium experience
struct FocusModeView: View {
    let entity: EntitySelection

    @EnvironmentObject var appState: AppState

    var body: some View {
        FocusCanvasView(entity: entity)
            .environmentObject(appState)
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
