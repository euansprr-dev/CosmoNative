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
    /// Above this block count a canvas card preview renders lazily, so only
    /// rows near the card's visible band typeset. Kept low: a thinkspace
    /// switch mounts every visible note card in one frame, and eager
    /// typesetting of long documents was a measurable slice of the swap
    /// freeze. (Lazy rendering is visually identical — the card shows the
    /// same top-of-document content.)
    static let canvasPreviewLazyBlockThreshold = 8

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
        case .table:
            AnyView(tableBlockView(block))
        case .section:
            AnyView(sectionBlockView(block, depth: depth))
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
            // Nested list items inset by level — the same ladder the editors
            // draw, so a rendered note reads exactly like the page.
            AnyView(inlineText(for: block, at: index, in: siblings)
                .font(font(for: block))
                .foregroundColor(textColor)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, CGFloat(block.listIndentLevel) * RichListIndent.insetPerLevel))
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

    /// Read-only section: the Element container voice (one grammar) with the
    /// section's own tone, appearance and title.
    private func sectionBlockView(_ block: RichBlock, depth: Int) -> some View {
        let style = block.section ?? .default
        let tone = NoteInkPalette.tone(style.toneID)
        let tinted = style.isTinted
        let title = block.inlines.map(\.plainText).joined()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: style.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(elementChevronColor)
                    .frame(width: 14, height: 14)
                if let icon = style.icon, !icon.isEmpty {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tinted ? tone.wash(darkMode: darkMode) : elementBorderColor)
                        .frame(width: 18, height: 18)
                        .overlay(sectionIcon(icon, tone: tone, tinted: tinted))
                }
                Text(title.isEmpty ? "Section" : title)
                    .font(.system(size: max(13, fontSize - 1), weight: .semibold))
                    .foregroundStyle(title.isEmpty ? secondaryTextColor : elementTitleColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30, alignment: .center)
            .padding(.horizontal, 10)

            if !style.isCollapsed, !block.children.isEmpty {
                blockStack(block.children, depth: depth + 1)
                    .padding(.top, 2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground(style: style, tone: tone))
        .overlay(sectionBorder(style: style, tone: tone))
    }

    @ViewBuilder
    private func sectionIcon(_ icon: String, tone: NoteInkTone, tinted: Bool) -> some View {
        if icon.unicodeScalars.first?.properties.isEmoji == true, icon.count <= 2 {
            Text(icon).font(.system(size: 11))
        } else {
            Image(systemName: DocumentElementSymbol.validName(icon))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tinted ? tone.ink(darkMode: darkMode) : secondaryTextColor)
        }
    }

    @ViewBuilder
    private func sectionBackground(style: RichSectionStyle, tone: NoteInkTone) -> some View {
        switch style.appearance {
        case .wash:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.isTinted ? tone.wash(darkMode: darkMode).opacity(0.55) : DS.glassCardFill)
        case .outline, .bar:
            Color.clear
        }
    }

    @ViewBuilder
    private func sectionBorder(style: RichSectionStyle, tone: NoteInkTone) -> some View {
        let hairline = style.isTinted ? tone.hairline(darkMode: darkMode).opacity(0.65) : elementBorderColor
        switch style.appearance {
        case .wash, .outline:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1)
        case .bar:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.isTinted ? tone.ink(darkMode: darkMode) : secondaryTextColor)
                    .frame(width: 4)
                Spacer(minLength: 0)
            }
        }
    }

    /// Read-only table: the same grid geometry as the editor, static text.
    private func tableBlockView(_ block: RichBlock) -> some View {
        let table = block.table ?? RichTable()
        return GeometryReader { proxy in
            let widths = table.resolvedColumnWidths(
                available: Double(max(120, proxy.size.width)),
                minimum: Double(max(48, fontSize * 3.6))
            ).map { CGFloat($0) }
            TableLayout(columnWidths: widths, rowCount: table.rowCount, minimumRowHeight: fontSize + 14) {
                ForEach(rendererTableEntries(table)) { entry in
                    rendererTableCell(entry, table: table)
                        .tableCellPlacement(TableCellPlacement(
                            rows: table.spanRect(ofAnchorAt: entry.address).rows,
                            columns: table.spanRect(ofAnchorAt: entry.address).columns
                        ))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: table.style == .clean ? 0 : 8, style: .continuous))
            .overlay {
                if table.style == .grid {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(rendererRuleColor, lineWidth: 0.5)
                }
            }
        }
        .frame(height: rendererTableHeight(table))
    }

    private struct RendererTableEntry: Identifiable {
        let id: UUID
        let address: RichTableCellAddress
        let cell: RichTableCell
    }

    private func rendererTableEntries(_ table: RichTable) -> [RendererTableEntry] {
        var entries: [RendererTableEntry] = []
        for (rowIndex, row) in table.rows.enumerated() {
            for (columnIndex, cell) in row.cells.enumerated() where !cell.isCovered {
                entries.append(RendererTableEntry(id: cell.id, address: RichTableCellAddress(row: rowIndex, column: columnIndex), cell: cell))
            }
        }
        return entries
    }

    /// The card renderer has no cell measuring pass of its own; estimate
    /// one line per cell line (soft breaks) so the block reserves height.
    private func rendererTableHeight(_ table: RichTable) -> CGFloat {
        let lineHeight = fontSize + 14
        var total: CGFloat = 0
        for row in table.rows {
            let lines = row.cells.map { cell -> Int in
                cell.isCovered ? 1 : max(1, cell.plainText.components(separatedBy: "\u{2028}").count)
            }.max() ?? 1
            total += lineHeight + CGFloat(max(0, lines - 1)) * (fontSize + 4)
        }
        return total
    }

    private var rendererRuleColor: Color {
        darkMode ? Color.white.opacity(0.14) : DS.documentBorderSubtle
    }

    private func rendererTableCell(_ entry: RendererTableEntry, table: RichTable) -> some View {
        let isHeader = (table.hasHeaderRow && entry.address.row == 0) || (table.hasHeaderColumn && entry.address.column == 0)
        let alignment = entry.cell.alignment ?? table.columns[entry.address.column].alignment
        let span = table.spanRect(ofAnchorAt: entry.address)
        let drawsRight = table.style == .grid && span.columns.upperBound < table.columnCount - 1
        let drawsBottom = table.style != .clean && span.rows.upperBound < table.rowCount - 1
        let headerRule = table.style == .clean && table.hasHeaderRow && span.rows.upperBound == 0 && table.rowCount > 1
        var background: Color? = nil
        if let toneID = entry.cell.toneID, RichInlineColor.isKnownTone(toneID) {
            background = NoteInkPalette.tone(toneID).ink(darkMode: darkMode).opacity(darkMode ? 0.24 : 0.16)
        } else if isHeader {
            background = NoteInkPalette.tone("gilt").ink(darkMode: darkMode).opacity(darkMode ? 0.14 : 0.08)
        }
        return renderedCellText(entry.cell, block: RichBlock(kind: .paragraph, inlines: entry.cell.inlines))
            .font(.system(size: fontSize, weight: isHeader ? .semibold : .regular))
            .foregroundColor(textColor)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment.swiftUIAlignment == .center ? .top : (alignment.swiftUIAlignment == .trailing ? .topTrailing : .topLeading))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background ?? .clear)
            .overlay(alignment: .trailing) {
                if drawsRight { Rectangle().fill(rendererRuleColor).frame(width: 0.5) }
            }
            .overlay(alignment: .bottom) {
                if drawsBottom || headerRule {
                    Rectangle()
                        .fill(headerRule ? NoteInkPalette.tone("gilt").hairline(darkMode: darkMode) : rendererRuleColor)
                        .frame(height: headerRule ? 1 : 0.5)
                }
            }
    }

    private func renderedCellText(_ cell: RichTableCell, block: RichBlock) -> Text {
        var result = Text("")
        for node in cell.inlines {
            result = result + renderedNode(node, block: block)
        }
        if cell.inlines.isEmpty { result = Text(" ") }
        return result
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
            prefix = Text(RichListIndent.bulletPrefix(level: block.listIndentLevel))
        case .numberedList:
            // Level-aware position: a deeper item never breaks the run above.
            let listPosition = RichListIndent.numberedOrdinals(for: siblings)[index] + 1
            prefix = Text(RichListIndent.numberedPrefix(position: listPosition, level: block.listIndentLevel))
        case .checklist:
            // Same checkbox grammar as iOS notes: circle / checkmark.circle.fill.
            let checked = block.checked ?? false
            prefix = Text(Image(systemName: checked ? "checkmark.circle.fill" : "circle"))
                .foregroundColor(checked ? CosmoColors.cosmoAI.opacity(0.9) : secondaryTextColor)
                + Text(" ")
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
        // Thumbnail sizes are deliberately floored for card legibility, but
        // WEIGHTS follow the document ladder (H1 semibold / H3 medium) so the
        // two surfaces never disagree about how heavy a heading is.
        switch block.kind {
        case .heading1:
            return .system(size: max(28, fontSize + 12), weight: .semibold)
        case .heading2:
            return .system(size: max(22, fontSize + 8), weight: .semibold)
        case .heading3:
            return .system(size: max(18, fontSize + 4), weight: .medium)
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
