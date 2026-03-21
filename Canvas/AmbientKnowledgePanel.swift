// CosmoOS/Canvas/AmbientKnowledgePanel.swift
// Floating right-anchored panel showing ambient knowledge results
// February 2026

import SwiftUI

struct AmbientKnowledgePanel: View {
    @ObservedObject var engine: AmbientFieldEngine
    let sourceBlockUUID: String
    let onClose: () -> Void

    private let panelWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().background(DS.border)
            panelBody
        }
        .frame(width: panelWidth)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: -4, y: 4)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(DS.accent)

            Text("Related Knowledge")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            if engine.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DS.accent)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Body

    private var panelBody: some View {
        Group {
            if engine.ambientResults.isEmpty && !engine.isLoading {
                emptyState
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(engine.ambientResults.enumerated()), id: \.element.id) { index, result in
                    AmbientResultCard(
                        result: result,
                        onPull: {
                            engine.pullToCanvas(result: result, sourceBlockUUID: sourceBlockUUID)
                        },
                        onDismiss: {
                            withAnimation(ProMotionSprings.snappy) {
                                engine.dismiss(uuid: result.id)
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(
                        ProMotionSprings.gentle.delay(Double(index) * 0.05),
                        value: engine.ambientResults.count
                    )
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 500)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 24))
                .foregroundColor(DS.textMuted)

            Text("Select a block to surface related knowledge")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
    }
}
