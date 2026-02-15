// CosmoOS/UI/FocusMode/Research/AnnotationTypePickerPopover.swift
// Popover for picking annotation type when text is selected in transcript
// February 2026 - Feature 5: Transcript Text Highlighting for Annotation Creation

import SwiftUI

// MARK: - Annotation Type Picker Popover

/// A small popover that appears when transcript text is selected,
/// letting the user pick Note / Question / Insight to create a highlight annotation.
struct AnnotationTypePickerPopover: View {
    let selectedText: String
    let onSelect: (AnnotationType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header label
            Text("Annotate:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)

            // Selected text preview (truncated)
            Text("\"\(selectedText.prefix(60))\(selectedText.count > 60 ? "..." : "")\"")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.7))
                .italic()
                .lineLimit(2)

            Divider().opacity(0.3)

            // Annotation type buttons
            ForEach(AnnotationType.allCases, id: \.rawValue) { type in
                Button {
                    onSelect(type)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(type.color)
                            .frame(width: 3, height: 16)
                        Image(systemName: type.icon)
                            .font(.system(size: 11))
                        Text(type.label)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(type.color)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(type.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct AnnotationTypePickerPopover_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AnnotationTypePickerPopover(
                selectedText: "Identity is not fixed. It's a story you tell yourself.",
                onSelect: { type in print("Selected: \(type.label)") },
                onCancel: { print("Cancelled") }
            )
        }
        .frame(width: 300, height: 300)
    }
}
#endif
