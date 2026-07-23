// CosmoOS/Settings/RecallIndexStatusCard.swift
// Health panel for the Recall semantic index: what's indexed, what's queued,
// what's failing, and a manual re-index trigger. The index is derived data —
// visibility here is what makes "did it actually index my stuff?" answerable.
// July 2026

import SwiftUI

struct RecallIndexStatusCard: View {
    @State private var status = RecallIndexStatus()
    @State private var isWorking = false
    @State private var refreshTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRows
            if let error = status.lastError, status.failing > 0 || status.pending > 0 {
                Text(error)
                    .font(DS.caption2)
                    .foregroundStyle(DS.orange)
                    .lineLimit(2)
            }
            actions
        }
        .padding(14)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .task(id: refreshTick) {
            status = await RecallIndexer.shared.status()
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isConfigured ? DS.green : DS.orange)
                    .frame(width: 7, height: 7)
                Text(status.isConfigured
                     ? "Embeddings configured — \(status.model)"
                     : "No embeddings key — add one under Service Keys to enable recall")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            HStack(spacing: 14) {
                statPair(value: status.indexedAtoms, label: "items indexed")
                statPair(value: status.indexedVectors, label: "chunks")
                if status.pending > 0 {
                    statPair(value: status.pending, label: "queued")
                }
                if status.failing > 0 {
                    statPair(value: status.failing, label: "failing", tint: DS.orange)
                }
            }
        }
    }

    private func statPair(value: Int, label: String, tint: Color = DS.text) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(DS.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                isWorking = true
                Task {
                    _ = await RecallIndexer.shared.backfill(full: true)
                    await RecallIndexer.shared.scheduleDrain()
                    isWorking = false
                    refreshTick += 1
                }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Re-index Now")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking || !status.isConfigured)

            Button("Refresh") { refreshTick += 1 }
                .buttonStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }
}
