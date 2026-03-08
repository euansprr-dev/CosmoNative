// CosmoOS/UI/CosmoWindow/ToolActivityStreamView.swift
// Live and recap tool activity rendering for the premium Cosmo window
// March 2026

import SwiftUI

enum ToolActivityStreamMode {
    case live
    case recap
}

private struct ToolActivityDisplayItem: Identifiable {
    let id: UUID
    let icon: String
    let label: String
    let detail: String?
    let isDone: Bool
}

private struct ToolActivityDisplayGroup: Identifiable {
    let id: UUID
    let category: String
    let items: [ToolActivityDisplayItem]
    let isComplete: Bool
}

struct ToolActivityStreamView: View {
    let groups: [ToolActivityDisplayGroup]
    let activeLabel: String?
    let mode: ToolActivityStreamMode

    init(
        groups: [ToolActivityGroup],
        activeLabel: String? = nil,
        mode: ToolActivityStreamMode = .live
    ) {
        self.groups = groups.map { group in
            ToolActivityDisplayGroup(
                id: group.id,
                category: group.category,
                items: group.items.map { item in
                    ToolActivityDisplayItem(
                        id: item.id,
                        icon: item.icon,
                        label: item.label,
                        detail: item.detail,
                        isDone: item.status == .done
                    )
                },
                isComplete: group.isComplete
            )
        }
        self.activeLabel = activeLabel
        self.mode = mode
    }

    init(
        recapGroups: [CosmoToolRecapGroup],
        mode: ToolActivityStreamMode = .recap
    ) {
        self.groups = recapGroups.map { group in
            ToolActivityDisplayGroup(
                id: group.id,
                category: group.category,
                items: group.items.map { item in
                    ToolActivityDisplayItem(
                        id: item.id,
                        icon: item.icon,
                        label: item.label,
                        detail: item.detail,
                        isDone: item.status == .done
                    )
                },
                isComplete: group.isComplete
            )
        }
        self.activeLabel = nil
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: mode == .live ? 10 : 8) {
            if mode == .live, let activeLabel {
                ActiveToolLabel(label: activeLabel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ForEach(groups) { group in
                ToolActivityGroupView(group: group, mode: mode)
            }
        }
    }
}

private struct ActiveToolLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    @State private var glow = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(DS.accent.opacity(glow ? 0.18 : 0.10))
                    .frame(width: 18, height: 18)

                Circle()
                    .fill(DS.accent)
                    .frame(width: 7, height: 7)
            }

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("Working")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .cosmoWindowChip(isActive: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cosmoWindowSectionChrome(cornerRadius: 14, shadow: false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

private struct ToolActivityGroupView: View {
    let group: ToolActivityDisplayGroup
    let mode: ToolActivityStreamMode

    @State private var isExpanded: Bool

    init(group: ToolActivityDisplayGroup, mode: ToolActivityStreamMode) {
        self.group = group
        self.mode = mode
        _isExpanded = State(initialValue: mode == .live)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 10)

                    Text(group.category)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("\(group.items.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .cosmoWindowChip()

                    Spacer(minLength: 0)

                    if mode == .live && activeCount > 0 {
                        Text("\(activeCount) active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip(isActive: true)
                    } else if mode == .recap && group.isComplete {
                        Text("Completed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .cosmoWindowChip(activeFill: DS.greenSoft, activeBorder: DS.green.opacity(0.18))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.items) { item in
                        ToolActivityItemRow(item: item, mode: mode)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cosmoWindowGroupChrome(cornerRadius: 14)
    }

    private var activeCount: Int {
        group.items.filter { !$0.isDone }.count
    }
}

private struct ToolActivityItemRow: View {
    let item: ToolActivityDisplayItem
    let mode: ToolActivityStreamMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(item.isDone ? DS.greenSoft : DS.accentSoft)
                    .frame(width: 28, height: 28)

                Image(systemName: item.isDone ? "checkmark" : item.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(item.isDone ? DS.green : DS.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = item.detail, mode == .recap {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
struct ToolActivityStreamView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ToolActivityStreamView(
                groups: [
                    ToolActivityGroup(
                        category: "Viewed",
                        items: [
                            ToolActivityItem(icon: "doc.text", label: "Reading Josh swipe", status: .done),
                            ToolActivityItem(icon: "doc.text", label: "Loading client profile", status: .active),
                        ]
                    )
                ],
                activeLabel: "Searching reference swipes"
            )

            ToolActivityStreamView(
                recapGroups: [
                    CosmoToolRecapGroup(
                        category: "Generated",
                        items: [
                            CosmoToolRecapItem(icon: "sparkles", label: "Drafted answer", detail: "Used current context and swipe references", status: .done)
                        ],
                        isComplete: true
                    )
                ]
            )
        }
        .padding(20)
        .frame(width: 420)
        .background(DS.bg)
    }
}
#endif
