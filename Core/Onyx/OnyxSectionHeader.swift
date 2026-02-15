// CosmoOS/Core/Onyx/OnyxSectionHeader.swift
// Section header with serif font — replaces ALL CAPS section titles.
// PRD Section 6.5: "Sentence case with New York serif, 15pt"

import SwiftUI

/// Premium section header: New York serif, sentence case, optional trailing metadata.
struct OnyxSectionHeader: View {
    let title: String
    var trailing: String?
    var trailingColor: Color
    var divider: Bool

    init(
        _ title: String,
        trailing: String? = nil,
        trailingColor: Color = OnyxColors.Text.tertiary,
        divider: Bool = false
    ) {
        self.title = title
        self.trailing = trailing
        self.trailingColor = trailingColor
        self.divider = divider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(OnyxTypography.sectionTitle)
                    .tracking(OnyxTypography.sectionTitleTracking)
                    .foregroundColor(OnyxColors.Text.secondary)

                Spacer()

                if let trailing = trailing {
                    Text(trailing)
                        .font(OnyxTypography.label)
                        .tracking(OnyxTypography.labelTracking)
                        .foregroundColor(trailingColor)
                }
            }

            if divider {
                Rectangle()
                    .fill(Color.white.opacity(OnyxLayout.dividerOpacity))
                    .frame(height: 1)
            }
        }
    }
}
