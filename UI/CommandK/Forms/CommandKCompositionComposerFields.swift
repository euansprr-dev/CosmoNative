import SwiftUI

struct CommandKComposerDestinationRow: View {
    var viewModel: CommandKViewModel
    let kind: SpaceCompositionKind

    var body: some View {
        Button { viewModel.showSpaceDestinationPicker(.create(kind)) } label: {
            HStack(spacing: DS.space8) {
                Image(systemName: viewModel.composerDraft?.destination?.symbol ?? "folder")
                    .accessibilityHidden(true)
                Text("In").foregroundStyle(DS.textMuted)
                Text(viewModel.composerDraft?.destination?.breadcrumb ?? (kind == .page ? "Library · Outside a Space" : "Choose a Space…"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(DS.textMuted).accessibilityHidden(true)
            }
            .font(DS.caption)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.space12)
            .frame(minHeight: 44)
            .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isExecutingAction || viewModel.createdCompositionUUID != nil)
        .help("Choose where this \(kind.title.lowercased()) is created")
        .accessibilityLabel("Create in \(viewModel.composerDraft?.destination?.breadcrumb ?? "Library")")
    }
}

struct CommandKCompositionComposerFields: View {
    let pane: CommandKComposerPane
    let kind: SpaceCompositionKind

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            CommandKComposerHeroTitleField(placeholder: "\(kind.title) title", text: pane.binding(.title),
                accent: DS.entityNote, focus: pane.focusBinding, onSubmit: pane.commit)
            Text(kind == .group
                ? "Collect existing Pages, images, and sources while keeping their originals."
                : "Start with editable Pages and sections. You can rename, reorder, or remove them as your work develops.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
