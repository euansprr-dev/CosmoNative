import SwiftUI

enum CosmoDocumentRendererSurface: Equatable {
    case fullDocument
    case canvasPreview
}

enum CosmoDocumentRendererStackMode: Equatable {
    case eager
    case lazy
}

enum CosmoDocumentRendererStackPolicy {
    static let canvasPreviewLazyBlockThreshold = 24

    static func mode(
        for surface: CosmoDocumentRendererSurface,
        blockCount: Int
    ) -> CosmoDocumentRendererStackMode {
        switch surface {
        case .canvasPreview:
            return blockCount >= canvasPreviewLazyBlockThreshold ? .lazy : .eager
        case .fullDocument:
            return .eager
        }
    }
}

private struct IndexedRichBlock: Identifiable {
    let offset: Int
    let block: RichBlock

    var id: UUID { block.id }
}

private struct IndexedRichBlocks: RandomAccessCollection {
    typealias Index = Int
    typealias Element = IndexedRichBlock

    let blocks: [RichBlock]

    var startIndex: Int { blocks.startIndex }
    var endIndex: Int { blocks.endIndex }

    subscript(position: Int) -> IndexedRichBlock {
        IndexedRichBlock(offset: position, block: blocks[position])
    }
}

struct CosmoDocumentRenderer: View {
    let document: RichDocument
    var fontSize: CGFloat = 16
    var darkMode: Bool = false
    var lineLimit: Int? = nil
    var stackMode: CosmoDocumentRendererStackMode = .eager

    private var textColor: Color {
        darkMode ? .white : DS.documentText
    }

    private var secondaryTextColor: Color {
        darkMode ? Color.white.opacity(0.7) : DS.documentTextSecondary
    }

    var body: some View {
        blockStack(document.blocks, depth: 0)
    }

    private func blockStack(_ blocks: [RichBlock], depth: Int) -> AnyView {
        if stackMode == .lazy && depth == 0 {
            return AnyView(LazyVStack(alignment: .leading, spacing: 8) {
                blockRows(blocks, depth: depth)
            })
        }

        return AnyView(VStack(alignment: .leading, spacing: 8) {
            blockRows(blocks, depth: depth)
        })
    }

    @ViewBuilder
    private func blockRows(_ blocks: [RichBlock], depth: Int) -> some View {
        ForEach(IndexedRichBlocks(blocks: blocks)) { item in
            blockView(item.block, at: item.offset, in: blocks, depth: depth)
        }
    }

    private func blockView(_ block: RichBlock, at index: Int, in siblings: [RichBlock], depth: Int) -> AnyView {
        switch block.kind {
        case .divider:
            AnyView(Rectangle()
                .fill(secondaryTextColor.opacity(0.35))
                .frame(height: 1))
        case .element:
            AnyView(elementBlockView(block, depth: depth))
        case .callout:
            AnyView(calloutBlockView(block, at: index, in: siblings))
        case .toggle:
            AnyView(toggleBlockView(block, depth: depth))
        case .code:
            AnyView(codeBlockView(block))
        case .sketch:
            AnyView(sketchBlockView(block))
        case .image:
            if let image = block.inlines.compactMap(\.image).first,
               let nsImage = ImageStore.load(path: image.path) {
                AnyView(Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(680, image.width))
                    .clipShape(RoundedRectangle(cornerRadius: 10)))
            } else {
                AnyView(Text("[Image]")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(secondaryTextColor))
            }
        default:
            AnyView(inlineText(for: block, at: index, in: siblings)
                .font(font(for: block))
                .foregroundColor(textColor)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true))
        }
    }

    private func elementBlockView(_ block: RichBlock, depth: Int) -> some View {
        let visibleChildren = DocumentElementRendering.visibleChildBlocks(for: block)
        let collapsed = DocumentElementRendering.isCollapsed(block)
        let instanceTitle = DocumentElementRendering.instanceTitle(for: block)
        let tone = DocumentElementRendering.tone(for: block)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(elementChevronColor)
                    .frame(width: 14, height: 14)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tone.wash(darkMode: darkMode))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: DocumentElementRendering.systemIcon(for: block))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(tone.ink(darkMode: darkMode))
                    )

                Text(instanceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(elementTitleColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(minHeight: 30, alignment: .center)
            .padding(.horizontal, 10)

            if !visibleChildren.isEmpty {
                blockStack(visibleChildren, depth: depth + 1)
                    .padding(.top, 2)
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.wash(darkMode: darkMode).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tone.hairline(darkMode: darkMode).opacity(0.65), lineWidth: 1)
        )
    }

    private func calloutBlockView(_ block: RichBlock, at index: Int, in siblings: [RichBlock]) -> some View {
        let tone = NoteInkPalette.tone(block.callout?.toneID)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: DocumentElementSymbol.validName(block.callout?.icon ?? RichCalloutStyle.default.icon))
                .font(.system(size: max(11, fontSize - 4), weight: .medium))
                .foregroundStyle(tone.ink(darkMode: darkMode))
                .frame(width: 18, height: 18)
            inlineText(for: block, at: index, in: siblings)
                .font(font(for: block))
                .foregroundColor(textColor)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.wash(darkMode: darkMode))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tone.hairline(darkMode: darkMode), lineWidth: 1)
        )
    }

    private func toggleBlockView(_ block: RichBlock, depth: Int) -> some View {
        let collapsed = block.toggleCollapsed ?? false
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(elementChevronColor)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)
                Text(block.plainInlineText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !collapsed, !block.children.isEmpty {
                blockStack(block.children, depth: depth + 1)
                    .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Read-only sketch miniature — same smoothing as the editor, capped
    /// height for previews.
    private func sketchBlockView(_ block: RichBlock) -> some View {
        let drawing = block.sketch ?? RichSketchDrawing()
        return Canvas { context, _ in
            for stroke in drawing.strokes {
                let path = SketchGeometry.smoothedPath(for: stroke.points)
                let base = stroke.inkID == "ink"
                    ? textColor
                    : NoteInkPalette.tone(stroke.inkID).ink(darkMode: darkMode)
                context.stroke(
                    path,
                    with: .color(stroke.isHighlighter ? base.opacity(0.35) : base),
                    style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: min(drawing.height, 180))
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(darkMode ? Color.white.opacity(0.045) : Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(darkMode ? Color.white.opacity(0.10) : DS.documentBorderSubtle, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func codeBlockView(_ block: RichBlock) -> some View {
        Text(block.plainInlineText.replacingOccurrences(of: "\u{2028}", with: "\n"))
            .font(.system(size: max(11, fontSize - 3), design: .monospaced))
            .foregroundColor(textColor)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(darkMode ? Color.white.opacity(0.06) : DS.inkWash.opacity(0.05))
            )
    }

    private var elementChevronColor: Color {
        darkMode ? Color.white.opacity(0.48) : DS.documentTextMuted.opacity(0.78)
    }

    private var elementIconColor: Color {
        darkMode ? Color.white.opacity(0.65) : DS.documentTextSecondary.opacity(0.85)
    }

    private var elementTitleColor: Color {
        darkMode ? Color.white.opacity(0.95) : textColor.opacity(0.88)
    }

    private var elementShadowColor: Color {
        darkMode ? Color.black.opacity(0.30) : Color.black.opacity(0.04)
    }

    private func inlineText(for block: RichBlock, at index: Int, in siblings: [RichBlock]) -> Text {
        let prefix: Text
        switch block.kind {
        case .quote:
            prefix = Text("│ ").foregroundColor(secondaryTextColor)
        case .bulletList:
            prefix = Text("• ")
        case .numberedList:
            // Compute list-relative position
            var listPosition = 1
            var j = index - 1
            while j >= 0 && siblings[j].kind == .numberedList {
                listPosition += 1
                j -= 1
            }
            prefix = Text("\(listPosition). ")
        case .checklist:
            prefix = Text((block.checked ?? false) ? "☑ " : "☐ ")
        default:
            prefix = Text("")
        }

        return block.inlines.reduce(prefix) { partial, node in
            partial + renderedNode(node, block: block)
        }
    }

    private func renderedNode(_ node: RichInlineNode, block: RichBlock) -> Text {
        switch node.kind {
        case .text:
            return styled(Text(node.text ?? ""), with: node.marks, block: block)
        case .mention:
            let mention = node.mention
            return styled(Text(mention?.displayText ?? ""), with: node.marks, block: block)
                .foregroundColor(CosmoMentionColors.color(for: mention?.entityType ?? .idea))
        case .imageRef:
            return Text("[Image]")
        }
    }

    private func styled(_ text: Text, with marks: Set<RichTextMark>, block: RichBlock) -> Text {
        var result = text
        if marks.contains(.bold) {
            result = result.bold()
        }
        if marks.contains(.italic) {
            result = result.italic()
        }
        if marks.contains(.underline) {
            result = result.underline()
        }
        if marks.contains(.strikethrough) {
            result = result.strikethrough()
        }
        return result
    }

    private func font(for block: RichBlock) -> Font {
        switch block.kind {
        case .heading1:
            return .system(size: max(28, fontSize + 12), weight: .bold)
        case .heading2:
            return .system(size: max(22, fontSize + 8), weight: .semibold)
        case .heading3:
            return .system(size: max(18, fontSize + 4), weight: .semibold)
        default:
            return .system(size: fontSize)
        }
    }

    private func elementBackgroundColor(depth: Int) -> Color {
        if darkMode {
            return Color(red: 0.105, green: 0.108, blue: 0.115)
        }
        return Color.white
    }

    private var elementBorderColor: Color {
        darkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
}
