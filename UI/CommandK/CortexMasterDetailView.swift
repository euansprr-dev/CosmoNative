// CosmoOS/UI/CommandK/CortexMasterDetailView.swift
// Phase 1 of the Raycast-style Command-K: one two-pane glass surface used
// for both .compact and .searchResults — left rail → right preview, with a
// persistent bottom action bar. .expandedDomain is untouched this phase.

import SwiftUI

struct CortexMasterDetailView: View {
    @ObservedObject var viewModel: CommandKViewModel
    var openDomain: (CommandKTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CortexResultRail(viewModel: viewModel)
                    .frame(width: 360)

                Rectangle()
                    .fill(DS.sepiaBorder)
                    .frame(width: 0.5)

                CortexDetailPane(subject: detailSubject)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            CortexActionBar(
                viewModel: viewModel,
                hasSelection: viewModel.selectedNodeId != nil
            )
        }
    }

    /// Resolve the current selection (driven by keyboard nav + row taps) into
    /// a uniform preview subject without the panes knowing the source.
    private var detailSubject: CortexDetailSubject {
        guard let id = viewModel.selectedNodeId else { return .empty }
        if viewModel.query.isEmpty {
            if let item = viewModel.recentItems.first(where: { $0.id == id }) {
                return .recent(item)
            }
        } else if let result = viewModel.unifiedFlatResults.first(where: { $0.selectionID == id }) {
            return .result(result)
        }
        return .empty
    }
}
