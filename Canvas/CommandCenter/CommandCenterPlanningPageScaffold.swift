import SwiftUI

struct CommandCenterPlanningPageScaffold<Actions: View, Content: View>: View {
    let title: String
    let icon: String
    let subtitle: String
    let accent: Color

    private let actions: Actions
    private let content: Content

    init(
        title: String,
        icon: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.accent = accent
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space18) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(alignment: .top, spacing: DS.space12) {
                titleBlock
                Spacer(minLength: DS.space16)
                actions
            }

            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.pageTitle)
                .foregroundStyle(DS.commandCenterTitleText)

            HStack(spacing: DS.space8) {
                Image(systemName: icon)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(accent)

                Text(subtitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.commandCenterSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
    }
}

extension CommandCenterPlanningPageScaffold where Actions == EmptyView {
    init(
        title: String,
        icon: String,
        subtitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            icon: icon,
            subtitle: subtitle,
            accent: accent,
            actions: { EmptyView() },
            content: content
        )
    }
}
