// CosmoOS/UI/FocusMode/Synthesis/SynthesisWorkspaceLoader.swift
// Async wrapper that loads atoms for synthesis workspace

import SwiftUI

struct SynthesisWorkspaceLoader: View {
    let blockIds: [String]
    let blocks: [CanvasBlock]
    let onCreateConnection: (LassoSynthesisResult) -> Void
    let onDismiss: () -> Void

    @State private var atoms: [Atom] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    DS.bg.ignoresSafeArea()
                    ProgressView("Loading sources…")
                        .foregroundColor(DS.textSecondary)
                }
            } else {
                SynthesisWorkspaceView(
                    sourceAtoms: atoms,
                    onCreateConnection: onCreateConnection,
                    onDismiss: onDismiss
                )
            }
        }
        .task {
            await loadAtoms()
        }
    }

    private func loadAtoms() async {
        let atomRepo = AtomRepository.shared
        var loaded: [Atom] = []

        for blockId in blockIds {
            guard let block = blocks.first(where: { $0.id == blockId }) else { continue }
            let uuid = block.entityUuid
            guard !uuid.isEmpty else { continue }

            if let atom = try? await atomRepo.fetch(uuid: uuid) {
                loaded.append(atom)
            }
        }

        atoms = loaded
        isLoading = false
    }
}
