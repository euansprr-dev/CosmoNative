// CosmoOS/Canvas/ClusterCreationPopover.swift
// Popover for creating a user cluster or triggering synthesis after lasso/multi-select

import SwiftUI

struct ClusterCreationPopover: View {
    let blockIds: [String]
    let position: CGPoint
    let onCreateCluster: (String, Int) -> Void
    let onSynthesize: () -> Void
    let onDismiss: () -> Void

    @State private var clusterName: String = ""
    @State private var selectedColorIndex: Int = 0
    @State private var appeared = false
    @State private var mode: PopoverMode = .choice
    @FocusState private var nameFieldFocused: Bool

    private enum PopoverMode {
        case choice
        case clusterForm
    }

    var body: some View {
        Group {
            switch mode {
            case .choice:
                choiceView
            case .clusterForm:
                clusterFormView
            }
        }
        .scaleEffect(appeared ? 1.0 : 0.85)
        .opacity(appeared ? 1.0 : 0)
        .position(x: position.x, y: position.y)
        .onAppear {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Choice View

    private var choiceView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
                Text("\(blockIds.count) blocks selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()
                .background(DS.border)

            // Create Cluster option
            choiceButton(
                icon: "square.3.layers.3d",
                label: "Create Cluster",
                color: CosmoColors.thinkspacePurple
            ) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    mode = .clusterForm
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    nameFieldFocused = true
                }
            }

            // Synthesize option
            choiceButton(
                icon: "sparkles",
                label: "Synthesize",
                color: CosmoColors.lavender
            ) {
                onSynthesize()
            }
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderActive, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - Cluster Form View

    private var clusterFormView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.thinkspacePurple)
                Text("New Cluster")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Name field
            TextField("Cluster name...", text: $clusterName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.3))
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
                        .foregroundColor(.white)
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
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderActive, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func choiceButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color.opacity(0.8))
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DS.text)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }

    private func colorSwatch(index: Int) -> some View {
        Button {
            selectedColorIndex = index
        } label: {
            Circle()
                .fill(CanvasCluster.palette[index])
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(selectedColorIndex == index ? 0.8 : 0), lineWidth: 2)
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

// MARK: - Hover Button Style

private struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? DS.border : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
