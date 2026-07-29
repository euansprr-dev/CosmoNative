// CosmoOS/UI/SwipeFile/Shared/SwipeFlowMenu.swift
// "Add to flow" — the context-menu submenu that puts an existing swipe into a
// funnel, and starts one when none exists yet.
//
// Recording is the fast path (walk the funnel, every capture appends); this is
// the deliberate one, for assembling a funnel out of things you saved before
// you knew they belonged together.

import SwiftUI

struct SwipeFlowMenu: View {
    /// The swipe being filed. A flow can never be added to itself.
    let swipeUUID: String

    @State private var flows: [Atom] = []
    @State private var recorder = SwipeFlowRecorder.shared

    var body: some View {
        Menu("Add to Flow") {
            if let session = recorder.session {
                Button {
                    append(to: session.flowUUID)
                } label: {
                    Label("\(session.name) (recording)", systemImage: "record.circle")
                }
                Divider()
            }

            ForEach(flows.filter { $0.uuid != swipeUUID }, id: \.uuid) { flow in
                Button {
                    append(to: flow.uuid)
                } label: {
                    Label(
                        flow.title ?? "Funnel",
                        systemImage: SwipeKind.flow.iconName
                    )
                }
            }

            if flows.isEmpty && recorder.session == nil {
                // A teaching row, never an empty menu.
                Text("No funnels yet")
                Divider()
            }

            Button {
                startNewFlow()
            } label: {
                Label("New funnel from this swipe", systemImage: "plus")
            }
        }
        .task { await loadFlows() }
    }

    private func append(to flowUUID: String) {
        Task { await SwipeFlowStore.append(swipeUUID: swipeUUID, toFlow: flowUUID) }
    }

    /// Creating a funnel from a swipe puts that swipe in as step 1 AND opens
    /// the recording session — the overwhelmingly common next move is to walk
    /// the rest of the funnel, and making that automatic is the whole point.
    private func startNewFlow() {
        Task {
            guard let session = await recorder.start(named: SwipeFlowRecorder.defaultName()) else { return }
            await SwipeFlowStore.append(swipeUUID: swipeUUID, toFlow: session.flowUUID)
            _ = await recorder.resume(flowUUID: session.flowUUID)
        }
    }

    private func loadFlows() async {
        flows = await SwipeFlowStore.flows()
    }
}
