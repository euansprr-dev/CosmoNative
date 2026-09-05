import SwiftUI

struct IdeaCollectionsRail: View {
    let collections: [IdeaClientCollection]
    let scope: PipelineScope
    let archived: Bool
    let onSelect: (PipelineScope) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("COLLECTIONS").font(DS.smallCaps).tracking(DS.smallCapsTracking)
                    .foregroundStyle(DS.textMuted).padding(.horizontal, DS.space12).padding(.bottom, DS.space8)
                row("All clients", icon: "square.grid.2x2", scope: .all,
                    count: collections.reduce(0) { $0 + $1.count(archived: archived) })
                if let personal = collections.first(where: { $0.clientUUID == nil }) {
                    row("Personal", icon: "person", scope: .unassigned, count: personal.count(archived: archived))
                }
                Text("CLIENTS").font(DS.smallCaps).tracking(DS.smallCapsTracking)
                    .foregroundStyle(DS.textMuted).padding(.horizontal, DS.space12)
                    .padding(.top, DS.space24).padding(.bottom, DS.space8)
                ForEach(collections.filter { $0.clientUUID != nil }) { client in
                    row(client.name, icon: nil, scope: client.scope, count: client.count(archived: archived))
                }
            }
            .padding(.horizontal, DS.space12).padding(.vertical, DS.space24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .frame(width: 200)
        .background(DS.surface.opacity(0.55))
        .overlay(alignment: .trailing) { Rectangle().fill(DS.borderSubtle).frame(width: 0.5) }
        .accessibilityLabel("Idea collections")
    }

    private func row(_ title: String, icon: String?, scope target: PipelineScope, count: Int) -> some View {
        IdeaCollectionRow(title: title, icon: icon, clientID: target.clientUUID,
                          count: count, selected: scope == target, onSelect: { onSelect(target) })
    }
}

private struct IdeaCollectionRow: View {
    let title: String
    let icon: String?
    let clientID: String?
    let count: Int
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.space10) {
                if let icon { Image(systemName: icon).frame(width: 16) }
                else {
                    Circle().fill(clientID.map { DS.clientColor(for: $0) } ?? DS.textMuted)
                        .frame(width: 7, height: 7).frame(width: 16)
                }
                Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").font(DS.caption).monospacedDigit().foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            .font(DS.callout.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space12).frame(height: 40)
            .background(selected ? DS.accentSoft : hovered ? DS.surfaceHover : .clear,
                        in: .rect(cornerRadius: DS.radiusSmall))
            .contentShape(.rect)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .help("\(title) · \(count) ideas")
        .accessibilityLabel("\(title), \(count) ideas")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
