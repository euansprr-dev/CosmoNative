// CosmoOS/Canvas/TemplateFieldViews.swift
// SwiftUI renderers for each TemplateFieldType — fully interactive field editors
// All fields use direct Binding from $value — no @State intermediaries

import SwiftUI

// MARK: - Field Renderer (Dispatcher)

struct TemplateFieldRenderer: View {
    let field: TemplateFieldDefinition
    @Binding var value: ConditionValue?
    var compact: Bool = false

    var body: some View {
        if compact {
            compactLayout
        } else {
            fullLayout
        }
    }

    @ViewBuilder
    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(field.label)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)
            Spacer(minLength: 4)
            fieldInput
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var fullLayout: some View {
        fieldInput
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fieldInput: some View {
        switch field.fieldType {
        case .text:
            TemplateTextField(value: $value, placeholder: field.placeholder ?? "Type your answer...")
        case .url:
            TemplateTextField(value: $value, placeholder: field.placeholder ?? "https://...")
        case .longText:
            TemplateLongTextField(value: $value, placeholder: field.placeholder ?? "Type your answer...")
        case .number:
            TemplateNumberField(value: $value, placeholder: field.placeholder ?? "Enter a number...")
        case .currency:
            TemplateCurrencyField(value: $value, placeholder: field.placeholder ?? "0.00")
        case .date:
            TemplateDateField(value: $value, includeTime: false)
        case .dateTime:
            TemplateDateField(value: $value, includeTime: true)
        case .select:
            TemplateSelectField(value: $value, options: field.options ?? [], placeholder: field.placeholder)
        case .multiSelect:
            TemplateMultiSelectField(value: $value, options: field.options ?? [])
        case .toggle:
            TemplateToggleField(value: $value)
        case .rating:
            TemplateRatingField(value: $value)
        case .progress:
            TemplateProgressField(value: $value)
        case .atomReference:
            TemplateAtomRefField(value: $value, placeholder: field.placeholder ?? "Enter atom UUID...")
        case .computed:
            TemplateComputedField(value: value)
        }
    }
}

// MARK: - Text Field (single line, direct binding)

private struct TemplateTextField: View {
    @Binding var value: ConditionValue?
    var placeholder: String

    private var textBinding: Binding<String> {
        Binding(
            get: { value?.stringValue ?? "" },
            set: { value = $0.isEmpty ? nil : .string($0) }
        )
    }

    var body: some View {
        TextField(placeholder, text: textBinding)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DS.text)
    }
}

// MARK: - Long Text Field (multi-line, grows with content)

private struct TemplateLongTextField: View {
    @Binding var value: ConditionValue?
    var placeholder: String

    private var textBinding: Binding<String> {
        Binding(
            get: { value?.stringValue ?? "" },
            set: { value = $0.isEmpty ? nil : .string($0) }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder when empty
            if (value?.stringValue ?? "").isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: textBinding)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
        }
    }
}

// MARK: - Number Field (direct binding with Double parsing)

private struct TemplateNumberField: View {
    @Binding var value: ConditionValue?
    var placeholder: String

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if case .number(let n) = value { return String(format: "%g", n) }
                return value?.stringValue ?? ""
            },
            set: {
                if let n = Double($0) { value = .number(n) }
                else if $0.isEmpty { value = nil }
            }
        )
    }

    var body: some View {
        TextField(placeholder, text: textBinding)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DS.text)
    }
}

// MARK: - Currency Field

private struct TemplateCurrencyField: View {
    @Binding var value: ConditionValue?
    var placeholder: String

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if case .number(let n) = value { return String(format: "%.2f", n) }
                return ""
            },
            set: {
                if let n = Double($0) { value = .number(n) }
                else if $0.isEmpty { value = nil }
            }
        )
    }

    var body: some View {
        HStack(spacing: 2) {
            Text("$")
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
            TextField(placeholder, text: textBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
        }
    }
}

// MARK: - Date Field (direct binding)

private struct TemplateDateField: View {
    @Binding var value: ConditionValue?
    var includeTime: Bool

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                if let str = value?.stringValue,
                   let parsed = ISO8601.date(from: str) {
                    return parsed
                }
                return Date()
            },
            set: { value = .string(ISO8601.string(from: $0)) }
        )
    }

    var body: some View {
        DatePicker(
            "",
            selection: dateBinding,
            displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .controlSize(.small)
    }
}

// MARK: - Select Field (menu with options)

private struct TemplateSelectField: View {
    @Binding var value: ConditionValue?
    let options: [String]
    var placeholder: String?

    var body: some View {
        if options.isEmpty {
            Text("No options configured")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .italic()
        } else {
            Menu {
                Button("Clear") { value = nil }
                Divider()
                ForEach(options, id: \.self) { option in
                    Button {
                        value = .string(option)
                    } label: {
                        HStack {
                            Text(option)
                            if value?.stringValue == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(value?.stringValue ?? placeholder ?? "Select...")
                        .font(.system(size: 13))
                        .foregroundStyle(value != nil ? DS.text : DS.textMuted)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Multi-Select Field (toggleable chips)

private struct TemplateMultiSelectField: View {
    @Binding var value: ConditionValue?
    let options: [String]

    private var selected: [String] {
        if case .stringArray(let arr) = value { return arr }
        return []
    }

    var body: some View {
        if options.isEmpty {
            Text("No options configured")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .italic()
        } else {
            TemplateFlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    chipButton(option)
                }
            }
        }
    }

    @ViewBuilder
    private func chipButton(_ option: String) -> some View {
        let isOn = selected.contains(option)
        Button {
            var current = selected
            if isOn { current.removeAll { $0 == option } }
            else { current.append(option) }
            value = current.isEmpty ? nil : .stringArray(current)
        } label: {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(option)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? DS.accent.opacity(0.15) : DS.surfaceHover)
            .foregroundStyle(isOn ? DS.accent : DS.textSecondary)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toggle Field

private struct TemplateToggleField: View {
    @Binding var value: ConditionValue?

    private var isOn: Binding<Bool> {
        Binding(
            get: { if case .bool(let b) = value { return b }; return false },
            set: { value = .bool($0) }
        )
    }

    var body: some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

// MARK: - Rating Field (1-5 stars, interactive)

private struct TemplateRatingField: View {
    @Binding var value: ConditionValue?

    private var rating: Int {
        if case .number(let n) = value { return Int(n) }
        return 0
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    value = .number(Double(star == rating ? 0 : star))
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(star <= rating ? Color.orange : DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Progress Field (SLIDER + percentage)

private struct TemplateProgressField: View {
    @Binding var value: ConditionValue?

    private var progressBinding: Binding<Double> {
        Binding(
            get: { if case .number(let n) = value { return n }; return 0 },
            set: { value = .number($0) }
        )
    }

    private var progress: Double {
        if case .number(let n) = value { return n }
        return 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: progressBinding, in: 0...100, step: 1)
                .frame(maxWidth: .infinity)
            Text("\(Int(progress))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Atom Reference Field (text input for UUID)

private struct TemplateAtomRefField: View {
    @Binding var value: ConditionValue?
    var placeholder: String

    private var textBinding: Binding<String> {
        Binding(
            get: { value?.stringValue ?? "" },
            set: { value = $0.isEmpty ? nil : .string($0) }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundStyle(DS.accent)
            TextField(placeholder, text: textBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
        }
    }
}

// MARK: - Computed Field (read-only, intentional)

private struct TemplateComputedField: View {
    let value: ConditionValue?

    var body: some View {
        Text(value?.stringValue ?? "—")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.accent.opacity(0.08))
            .clipShape(.rect(cornerRadius: 6))
    }
}

// MARK: - Flow Layout (for multi-select chips)

struct TemplateFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// ConditionValue.stringValue is defined in AutomationRule.swift
