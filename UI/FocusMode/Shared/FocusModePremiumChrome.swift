import SwiftUI

struct FocusModeGlassRail<Content: View>: View {
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 24,
        contentPadding: CGFloat = DS.space12,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .cosmoGlassPanel(sceneMaterial: .neutral, role: .globalSidebar, cornerRadius: cornerRadius)
    }
}

struct FocusModeInspectorSection<Content: View>: View {
    let title: String
    let countText: String?
    let contentPadding: CGFloat
    let content: Content

    init(
        _ title: String,
        countText: String? = nil,
        contentPadding: CGFloat = DS.space12,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.countText = countText
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel(title, countText: countText)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(contentPadding)
        .background(DS.glassCardFill.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.58), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

struct FocusModeMediaWell<Content: View>: View {
    let maxWidth: CGFloat?
    let aspectRatio: CGFloat?
    let content: Content

    init(
        maxWidth: CGFloat? = nil,
        aspectRatio: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.aspectRatio = aspectRatio
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth ?? .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .padding(DS.space10)
            .background(DS.glassCardFill.opacity(0.64), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(DS.glassBorder.opacity(0.8), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.075), radius: 16, x: 0, y: 10)
    }
}
