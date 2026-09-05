// CosmoOS/Canvas/Library/ThinkspaceLibraryGalleryView.swift
// The Gallery lens: one document at reading scale, a filmstrip to walk the
// collection, and a flat metadata ledger (the ⌘K one-surface anatomy — no
// nested boxes). This is where prose belongs; the grid stays scannable.

import SwiftUI

struct ThinkspaceLibraryGalleryView: View {
    let items: [ThinkspaceLibraryItem]
    let provenance: (ThinkspaceLibraryItem) -> String
    let context: ThinkspaceLibraryLensContext

    private var currentItem: ThinkspaceLibraryItem? {
        if let primary = context.selection.primaryID,
           let item = items.first(where: { $0.id == primary }) {
            return item
        }
        return items.first
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: DS.space24) {
                mainColumn(
                    width: max(240, geo.size.width - 280 - DS.space24),
                    height: geo.size.height
                )
                .frame(maxWidth: .infinity)
                if let item = currentItem {
                    LibraryGalleryRail(
                        model: context.cardModel(item),
                        provenance: provenance(item),
                        context: context
                    )
                    .frame(width: 280)
                }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: items.map(\.id)) { _, _ in ensureSelection() }
    }

    /// The gallery always has a subject — arriving with nothing selected
    /// lands on the first document instead of an empty stage.
    private func ensureSelection() {
        guard currentItem != nil, context.selection.isEmpty, let first = items.first else { return }
        context.selection.select(only: first.id)
    }

    private func mainColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: DS.space20) {
            stage(width: width, height: max(120, height - 96 - DS.space20))
            LibraryGalleryFilmstrip(items: items, context: context)
        }
    }

    @ViewBuilder
    private func stage(width: CGFloat, height: CGFloat) -> some View {
        if let item = currentItem {
            let model = context.cardModel(item)
            LibraryDocumentObject(
                model: model,
                wellWidth: min(560, width - DS.space16),
                wellHeight: height,
                cornerRadius: DS.radiusMedium,
                miniature: false
            )
            .cardShadow(isHovered: false)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { context.actions.openItem(item) }
            .contextMenu { LibraryItemMenuItems(model: model, context: context) }
            .id(item.id)
            .transition(.opacity)
            .animation(ProMotionSprings.gentle, value: item.id)
            .accessibilityLabel("\(item.title), \(model.kindLabel). Double-click to open.")
        } else {
            Color.clear.frame(height: height)
        }
    }
}

// MARK: - Filmstrip

private struct LibraryGalleryFilmstrip: View {
    let items: [ThinkspaceLibraryItem]
    let context: ThinkspaceLibraryLensContext

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: DS.space10) {
                    ForEach(items) { item in
                        LibraryFilmstripTile(model: context.cardModel(item), context: context)
                            .id("film-\(item.id)")
                    }
                }
                .padding(.horizontal, DS.space4)
                .padding(.vertical, DS.space4)
            }
            .scrollIndicators(.hidden)
            .frame(height: 76)
            .onChange(of: context.selection.focusedID) { _, focused in
                guard let focused else { return }
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo("film-\(focused)", anchor: .center)
                }
            }
        }
    }
}

private struct LibraryFilmstripTile: View {
    let model: ThinkspaceLibraryCardModel
    let context: ThinkspaceLibraryLensContext

    @State private var isHovered = false

    private var isSelected: Bool { context.selection.isSelected(model.item.id) }

    var body: some View {
        LibraryDocumentObject(model: model, wellWidth: 76, wellHeight: 56, cornerRadius: 6, miniature: true)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.accent.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
            )
            .opacity(isSelected || isHovered ? 1 : 0.72)
            .animation(ProMotionSprings.hover, value: isHovered)
            .animation(ProMotionSprings.snappy, value: isSelected)
            .onHover { isHovered = $0 }
            .gesture(LibraryClickGestures.selectAndOpen(
                id: model.item.id,
                selection: context.selection,
                onOpen: { context.actions.openItem(model.item) }
            ))
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ThinkspaceLibrarySpace.name))
            } action: { frame in
                context.selection.register(id: model.item.id, frame: frame)
            }
            .help(model.item.title)
            .accessibilityLabel(model.item.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Metadata rail (flat ledger, no nested boxes)

private struct LibraryGalleryRail: View {
    let model: ThinkspaceLibraryCardModel
    let provenance: String
    let context: ThinkspaceLibraryLensContext

    private var item: ThinkspaceLibraryItem { model.item }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            Text(item.title)
                .font(DS.headline.weight(.semibold))
                .foregroundStyle(DS.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            ledger
            Spacer(minLength: 0)
            actions
        }
        .padding(DS.space20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
    }

    private var ledger: some View {
        VStack(spacing: 0) {
            ledgerRow("Kind", model.kindLabel)
            ledgerRow("Where", provenance)
            ledgerRow("Modified", model.updatedAt.map(ThinkspaceLibraryDateLabel.label(for:)) ?? "—")
            ledgerRow("Created", model.createdAt.map(ThinkspaceLibraryDateLabel.label(for:)) ?? "—")
            if let url = model.metadata["url"], !url.isEmpty {
                ledgerRow("Source", URL(string: url)?.host ?? url, isLast: true)
            } else {
                ledgerRow("Canvas", item.isOnCanvas ? "Placed" : "Stored", isLast: true)
            }
        }
    }

    private func ledgerRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
                Text(label)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 64, alignment: .leading)
                Text(value)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DS.space8)
            if !isLast {
                Rectangle()
                    .fill(DS.glassBorder.opacity(0.6))
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: DS.space8) {
            LibraryRailButton(title: "Open", icon: "arrow.up.left.and.arrow.down.right", isPrimary: true, help: "Open in Focus Mode (⌘O)") {
                context.actions.openItem(item)
            }
            if item.isOnCanvas {
                LibraryRailButton(title: "Reveal on Canvas", icon: "scope", help: "Fly the canvas camera to this block") {
                    context.actions.revealOnCanvas(item)
                }
            } else {
                LibraryRailButton(title: "Place on Canvas", icon: "rectangle.dashed.badge.plus", help: "Give this member a spot on the canvas at the camera") {
                    context.actions.placeOnCanvas(item)
                }
            }
        }
    }
}

private struct LibraryRailButton: View {
    let title: String
    let icon: String
    var isPrimary = false
    var help = ""
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space6) {
                Image(systemName: icon)
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.footnote.weight(.semibold))
            }
            .foregroundStyle(isPrimary ? Color.white : DS.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(background, in: RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous)
                    .strokeBorder(isPrimary ? .clear : DS.glassBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(ProMotionSprings.press) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(ProMotionSprings.release) { isPressed = false }
                }
        )
        .help(help.isEmpty ? title : help)
        .accessibilityLabel(title)
    }

    private var background: AnyShapeStyle {
        if isPrimary {
            return AnyShapeStyle(isHovered ? DS.accent.opacity(0.9) : DS.accent)
        }
        return AnyShapeStyle(isHovered ? DS.glassCardFill : DS.glassInputFill)
    }
}
