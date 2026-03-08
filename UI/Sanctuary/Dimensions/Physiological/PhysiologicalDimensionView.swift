// CosmoOS/UI/Sanctuary/Dimensions/Physiological/PhysiologicalDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct PhysiologicalDimensionView: View {
    let onBack: () -> Void

    public init(
        data: PhysiologicalDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .physiological,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct PhysiologicalDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        PhysiologicalDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
