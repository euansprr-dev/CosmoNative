import AppKit
import SwiftUI

/// Chrome for a code block: a quiet mono wash with a hover-revealed copy
/// button. The text region (monospaced via the serializer) is injected by
/// `BlockListView`. Return inserts a soft break inside the block; Return on
/// the empty final line exits.
struct CodeBlockRowView<Content: View>: View {
    /// The block's current text — soft breaks intact — for the copy action.
    var codeText: () -> String
    var darkMode: Bool = false
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @State private var didCopy = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(washFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if isHovered || didCopy {
                    copyButton
                        .padding(DS.space6)
                        .transition(.opacity)
                }
            }
            .onHover { isHovered = $0 }
            .animation(ProMotionSprings.snappy, value: isHovered)
    }

    private var washFill: Color {
        darkMode ? Color.white.opacity(0.06) : DS.inkWash.opacity(0.05)
    }

    private var hairline: Color {
        darkMode ? Color.white.opacity(0.10) : DS.documentBorderSubtle
    }

    private var copyButton: some View {
        Button(action: copyCode) {
            HStack(spacing: DS.space4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(DS.caption2.weight(.medium))
                if didCopy {
                    Text("Copied")
                        .font(DS.caption2.weight(.medium))
                }
            }
            .foregroundStyle(didCopy ? DS.accent : DS.textMuted)
            .padding(.horizontal, DS.space6)
            .padding(.vertical, DS.space4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(darkMode ? Color.white.opacity(0.10) : DS.documentBackground.opacity(0.9))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }

    private func copyCode() {
        let text = codeText().replacingOccurrences(of: "\u{2028}", with: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(ProMotionSprings.snappy) {
            didCopy = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(ProMotionSprings.gentle) {
                didCopy = false
            }
        }
    }
}

#Preview("Code — Light") {
    CodeBlockRowView(codeText: { "let answer = 42\u{2028}print(answer)" }) {
        Text("let answer = 42\nprint(answer)")
            .font(.body.monospaced())
    }
    .padding(DS.space24)
    .frame(width: 460)
    .background(DS.documentBackground)
}
