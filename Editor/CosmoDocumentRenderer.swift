import SwiftUI

struct CosmoDocumentRenderer: View {
    let document: RichDocument
    var fontSize: CGFloat = 16
    var darkMode: Bool = false
    var lineLimit: Int? = nil

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
        AnyView(VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, at: index, in: blocks, depth: depth)
            }
        })
    }

    private func blockView(_ block: RichBlock, at index: Int, in siblings: [RichBlock], depth: Int) -> AnyView {
        switch block.kind {
        case .divider:
            AnyView(Rectangle()
                .fill(secondaryTextColor.opacity(0.35))
                .frame(height: 1))
        case .element:
            AnyView(elementBlockView(block, depth: depth))
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
        let elementName = DocumentElementRendering.title(for: block)
        let instanceTitle = DocumentElementRendering.instanceTitle(for: block)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 28, height: 28)

                Image(systemName: DocumentElementRendering.systemIcon(for: block))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: max(13, min(15, fontSize - 2)), weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 15, height: 15)

                Text(elementName)
                    .font(.system(size: max(12, fontSize - 4), weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .frame(minWidth: 56, maxWidth: 150, alignment: .leading)

                Text(instanceTitle)
                    .font(.system(size: max(14, fontSize - 1), weight: .medium))
                    .foregroundStyle(textColor.opacity(darkMode ? 0.82 : 0.78))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(minHeight: max(42, fontSize + 24), alignment: .center)
            .padding(.horizontal, 8)

            if !visibleChildren.isEmpty {
                blockStack(visibleChildren, depth: depth + 1)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(elementBackgroundColor(depth: depth))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(elementBorderColor, lineWidth: 1)
        )
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
            return Color(red: 0.12, green: 0.125, blue: 0.13).opacity(depth == 0 ? 0.98 : 0.94)
        }
        return Color.white
    }

    private var elementBorderColor: Color {
        darkMode ? Color.white.opacity(0.11) : Color.black.opacity(0.10)
    }
}
