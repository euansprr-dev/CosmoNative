import AppKit
import SwiftUI

/// Chrome for a callout block: a tinted wash, hairline, and an icon seat
/// whose menu changes the callout's icon and tone. The text region itself is
/// injected by `BlockListView` (a normal `BlockTextEditorRow`), so typing,
/// splitting, and undo all behave like any other text block.
struct CalloutBlockRowView<Content: View>: View {
    let style: RichCalloutStyle
    var darkMode: Bool = false
    var onStyleChange: (RichCalloutStyle) -> Void
    @ViewBuilder var content: Content

    @State private var isHovered = false

    private var tone: NoteInkTone {
        NoteInkPalette.tone(style.toneID)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            iconSeat
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.wash(darkMode: darkMode))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tone.hairline(darkMode: darkMode), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private var iconSeat: some View {
        Menu {
            iconSection
            Divider()
            toneSection
        } label: {
            Image(systemName: DocumentElementSymbol.validName(style.icon))
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(tone.ink(darkMode: darkMode))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.top, 1)
        .opacity(isHovered ? 1 : 0.92)
        .help("Change callout icon and color")
        .accessibilityLabel("Callout style")
    }

    private var iconSection: some View {
        Picker("Icon", selection: iconBinding) {
            ForEach(CalloutIconCatalog.icons, id: \.symbol) { option in
                Label(option.label, systemImage: option.symbol)
                    .tag(option.symbol)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var toneSection: some View {
        Picker("Color", selection: toneBinding) {
            ForEach(NoteInkPalette.tones) { tone in
                Text(tone.label).tag(tone.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var iconBinding: Binding<String> {
        Binding(
            get: { style.icon },
            set: { onStyleChange(RichCalloutStyle(icon: $0, toneID: style.toneID)) }
        )
    }

    private var toneBinding: Binding<String> {
        Binding(
            get: { style.toneID },
            set: { onStyleChange(RichCalloutStyle(icon: style.icon, toneID: $0)) }
        )
    }
}

/// The curated callout icon set — deliberately small and modern.
enum CalloutIconCatalog {
    struct Option {
        let symbol: String
        let label: String
    }

    static let icons: [Option] = [
        Option(symbol: "sparkles", label: "Insight"),
        Option(symbol: "lightbulb", label: "Idea"),
        Option(symbol: "info.circle", label: "Info"),
        Option(symbol: "exclamationmark.triangle", label: "Warning"),
        Option(symbol: "flame", label: "Hot"),
        Option(symbol: "pin", label: "Pinned"),
        Option(symbol: "checkmark.circle", label: "Done"),
        Option(symbol: "quote.opening", label: "Quote")
    ]
}

#Preview("Callout — Light") {
    VStack(spacing: DS.space12) {
        CalloutBlockRowView(
            style: .default,
            onStyleChange: { _ in }
        ) {
            Text("A thought worth keeping visible while you write.")
                .font(DS.body)
        }
        CalloutBlockRowView(
            style: RichCalloutStyle(icon: "exclamationmark.triangle", toneID: "clay"),
            onStyleChange: { _ in }
        ) {
            Text("Careful — this section still needs a source.")
                .font(DS.body)
        }
    }
    .padding(DS.space24)
    .frame(width: 460)
    .background(DS.documentBackground)
}
