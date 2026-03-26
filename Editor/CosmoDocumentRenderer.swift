import SwiftUI

struct CosmoDocumentRenderer: View {
    let document: RichDocument
    var fontSize: CGFloat = 16
    var darkMode: Bool = false
    var lineLimit: Int? = nil

    private var textColor: Color {
        darkMode ? .white : CosmoColors.textPrimary
    }

    private var secondaryTextColor: Color {
        darkMode ? Color.white.opacity(0.7) : CosmoColors.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, at: index)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: RichBlock, at index: Int) -> some View {
        switch block.kind {
        case .divider:
            Rectangle()
                .fill(secondaryTextColor.opacity(0.35))
                .frame(height: 1)
        case .image:
            if let image = block.inlines.compactMap(\.image).first,
               let nsImage = ImageStore.load(path: image.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(680, image.width))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("[Image]")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
        default:
            inlineText(for: block, at: index)
                .font(font(for: block))
                .foregroundColor(textColor)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineText(for block: RichBlock, at index: Int) -> Text {
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
            while j >= 0 && document.blocks[j].kind == .numberedList {
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
}
