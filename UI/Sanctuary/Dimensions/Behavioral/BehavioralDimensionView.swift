// CosmoOS/UI/Sanctuary/Dimensions/Behavioral/BehavioralDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct BehavioralDimensionView: View {
    let onBack: () -> Void

    public init(
        data: BehavioralDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .behavioral,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct BehavioralDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        BehavioralDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
