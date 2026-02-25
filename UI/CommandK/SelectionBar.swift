// CosmoOS/UI/CommandK/SelectionBar.swift
// Floating selection bar for Command-K gallery tabs
// Shows selected count with Deselect All and batch Delete actions

import SwiftUI

// MARK: - SelectionBar

struct SelectionBar: View {
    @ObservedObject var viewModel: CommandKViewModel
    var accentColor: Color = DS.accent
    var onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 16) {
            // Selection count
            Text("\(viewModel.selectedUUIDs.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()

            // Deselect All
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.clearSelection()
                }
            } label: {
                Text("Deselect All")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DS.border)
                    )
            }
            .buttonStyle(.plain)

            // Delete N
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete \(viewModel.selectedUUIDs.count)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#EF4444"))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .alert(
            "Delete \(viewModel.selectedUUIDs.count) items?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
