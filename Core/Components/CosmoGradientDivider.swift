// CosmoOS/Core/Components/CosmoGradientDivider.swift
// Premium gradient divider matching the "/" menu's visual language

import SwiftUI

struct CosmoGradientDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DS.accent.opacity(0.4), DS.sepiaBorder],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}
