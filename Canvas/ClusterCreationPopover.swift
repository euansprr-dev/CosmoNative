// CosmoOS/Canvas/ClusterCreationPopover.swift
// Popover for creating a user cluster after lasso/multi-select

import SwiftUI

struct ClusterCreationPopover: View {
    var blockIds: [String] = []
    let position: CGPoint
    let onCreateCluster: (String, Int) -> Void
    let onDismiss: () -> Void

    @State private var clusterName: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var appeared = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        clusterFormView
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0)
            .position(x: position.x, y: position.y)
            .onAppear {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                    appeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    nameFieldFocused = true
                }
            }
    }

    // MARK: - Cluster Form View

    private var clusterFormView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: blockIds.isEmpty ? "rectangle.dashed" : "square.3.layers.3d")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.accent)
                Text(blockIds.isEmpty ? "New Zone" : "New Cluster")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                if !blockIds.isEmpty {
                    Text("\(blockIds.count) blocks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Name field
            TextField(blockIds.isEmpty ? "Zone name..." : "Cluster name...", text: $clusterName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.border, lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .focused($nameFieldFocused)
                .onSubmit {
                    createCluster()
                }

            // Color swatches
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { index in
                    colorSwatch(index: index)
                }
            }
            .padding(.horizontal, 12)

            Divider()
                .background(DS.border)
                .padding(.horizontal, 12)

            // Create button
            HStack {
                Spacer()
                Button {
                    createCluster()
                } label: {
                    Text("Create")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.textOnAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(CanvasCluster.palette[selectedColorIndex])
                        )
                }
                .buttonStyle(.plain)
                .disabled(clusterName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(clusterName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
    }

    // MARK: - Helpers

    private func colorSwatch(index: Int) -> some View {
        Button {
            selectedColorIndex = index
        } label: {
            Circle()
                .fill(CanvasCluster.palette[index])
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(DS.text.opacity(selectedColorIndex == index ? 0.6 : 0), lineWidth: 2)
                )
                .scaleEffect(selectedColorIndex == index ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: selectedColorIndex)
    }

    private func createCluster() {
        let name = clusterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreateCluster(name, selectedColorIndex)
    }
}
