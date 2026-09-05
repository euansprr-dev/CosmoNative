import SwiftUI

/// Quiet teaching state shared by the editorial collection and client settings.
struct IdeasEmptyState: View {
    let icon: String
    let headline: String
    let teachingLine: String

    var body: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: icon).font(DS.pageTitle).foregroundStyle(DS.textMuted)
            Text(headline).font(DS.headline).foregroundStyle(DS.textSecondary)
            Text(teachingLine).font(DS.callout).foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.space48)
        .accessibilityElement(children: .combine)
    }
}
