// CosmoOS/UI/Sanctuary/Dimensions/Cognitive/CognitiveDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct CognitiveDimensionView: View {
    let onBack: () -> Void

    public init(
        data: CognitiveDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .cognitive,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct CognitiveDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        CognitiveDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
