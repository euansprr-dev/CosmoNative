// CosmoOS/UI/FocusMode/Ideas/OutlineComposer/OutlineSlideEditor.swift
// Per-slide editor card with drag-and-drop slots for codex elements.

import SwiftUI
import UniformTypeIdentifiers

struct OutlineSlideEditor: View {
    @Binding var slide: CodexOutlineSlide
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            slideHeader
            speechActSlot
            readerDeltasSlot
            frameSlot
            distanceSlot
            techniquesSlot
            transitionSlot
            noteField
        }
        .padding(DS.space12)
        .dsCard()
    }
}

// MARK: - Header

extension OutlineSlideEditor {
    private var slideHeader: some View {
        HStack {
            Text("Slide \(slide.position)")
                .font(DS.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accent, in: Capsule())

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete slide \(slide.position)")
        }
    }
}

// MARK: - Slots

extension OutlineSlideEditor {
    private var speechActSlot: some View {
        DropSlot(
            label: "Speech Act",
            acceptedCategory: .speechAct,
            currentValue: slide.speechAct,
            onDrop: { slide.speechAct = $0 },
            onRemove: { slide.speechAct = nil }
        )
    }

    private var readerDeltasSlot: some View {
        MultiDropSlot(
            label: "Reader Deltas",
            acceptedCategory: .readerDelta,
            values: slide.readerDeltas,
            onDrop: { name in
                if !slide.readerDeltas.contains(name) {
                    slide.readerDeltas.append(name)
                }
            },
            onRemove: { name in
                slide.readerDeltas.removeAll { $0 == name }
            }
        )
    }

    private var frameSlot: some View {
        DropSlot(
            label: "Frame",
            acceptedCategory: .frame,
            currentValue: slide.frame,
            onDrop: { slide.frame = $0 },
            onRemove: { slide.frame = nil }
        )
    }

    private var distanceSlot: some View {
        DropSlot(
            label: "Distance",
            acceptedCategory: .distance,
            currentValue: slide.distance,
            onDrop: { slide.distance = $0 },
            onRemove: { slide.distance = nil }
        )
    }

    private var techniquesSlot: some View {
        MultiDropSlot(
            label: "Techniques",
            acceptedCategory: .technique,
            values: slide.techniques,
            onDrop: { name in
                if !slide.techniques.contains(name) {
                    slide.techniques.append(name)
                }
            },
            onRemove: { name in
                slide.techniques.removeAll { $0 == name }
            }
        )
    }

    private var transitionSlot: some View {
        DropSlot(
            label: "\u{2192} Next",
            acceptedCategory: .transition,
            currentValue: slide.transition,
            onDrop: { slide.transition = $0 },
            onRemove: { slide.transition = nil }
        )
    }

    private var noteField: some View {
        TextField("Add note...", text: noteBinding)
            .font(DS.caption)
            .foregroundStyle(DS.text)
            .textFieldStyle(.plain)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space6)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { slide.note ?? "" },
            set: { slide.note = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - DropSlot

private struct DropSlot: View {
    let label: String
    let acceptedCategory: CodexElementCategory
    let currentValue: String?
    let onDrop: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            slotLabel
            slotContent
        }
    }

    private var slotLabel: some View {
        Text(label)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    @ViewBuilder
    private var slotContent: some View {
        if let value = currentValue {
            filledSlot(value)
        } else {
            emptySlot
        }
    }

    private func filledSlot(_ value: String) -> some View {
        HStack(spacing: 4) {
            CodexConceptTag(name: value, color: acceptedCategory.color)

            Button {
                withAnimation(ProMotionSprings.snappy) { onRemove() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(value)")
        }
        .dropDestination(for: CodexDragItem.self) { items, _ in
            guard let item = items.first, item.category == acceptedCategory else { return false }
            withAnimation(ProMotionSprings.snappy) { onDrop(item.canonicalName) }
            return true
        }
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(DS.borderSubtle)
            .frame(height: 28)
            .overlay {
                Text(label)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted.opacity(0.6))
            }
            .dropDestination(for: CodexDragItem.self) { items, _ in
                guard let item = items.first, item.category == acceptedCategory else { return false }
                withAnimation(ProMotionSprings.snappy) { onDrop(item.canonicalName) }
                return true
            }
    }
}

// MARK: - MultiDropSlot

private struct MultiDropSlot: View {
    let label: String
    let acceptedCategory: CodexElementCategory
    let values: [String]
    let onDrop: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            slotLabel
            slotContent
        }
    }

    private var slotLabel: some View {
        Text(label)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    private var slotContent: some View {
        HStack(spacing: DS.space4) {
            existingTags
            dropTarget
        }
        .dropDestination(for: CodexDragItem.self) { items, _ in
            guard let item = items.first, item.category == acceptedCategory else { return false }
            withAnimation(ProMotionSprings.snappy) { onDrop(item.canonicalName) }
            return true
        }
    }

    @ViewBuilder
    private var existingTags: some View {
        ForEach(values, id: \.self) { value in
            tagWithRemove(value)
        }
    }

    private func tagWithRemove(_ value: String) -> some View {
        HStack(spacing: 2) {
            CodexConceptTag(name: value, color: acceptedCategory.color)

            Button {
                withAnimation(ProMotionSprings.snappy) { onRemove(value) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(value)")
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: DS.radiusSmall)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(DS.borderSubtle)
            .frame(width: 60, height: 24)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted.opacity(0.5))
            }
    }
}
