// CosmoOS/UI/Sanctuary/Dimensions/Creative/CreativeDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct CreativeDimensionView: View {
    let onBack: () -> Void

    public init(
        data: CreativeDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .creative,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct CreativeDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        CreativeDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
