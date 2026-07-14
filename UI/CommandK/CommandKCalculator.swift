// CosmoOS/UI/CommandK/CommandKCalculator.swift
// Raycast-style inline calculator: typing math into Command-K surfaces the
// answer instantly — a split expression → result card in the rail, the big
// numeral in the detail pane, ⏎ copies. The evaluator is a hand-rolled
// recursive-descent parser (never NSExpression: it raises ObjC exceptions on
// malformed input, and the query line IS malformed input while typing).

import SwiftUI

// MARK: - Model

struct CommandKCalculation: Equatable {
    /// The typed expression, normalized to calculator typography:
    /// "5 x 15000" → "5 × 15,000".
    let expressionDisplay: String
    /// The formatted answer: "75,000".
    let resultDisplay: String
    let result: Double
}

// MARK: - Engine

enum CommandKCalculator {

    /// nil unless the query reads as an actual computation — a bare number,
    /// a date-like fragment with letters, or anything mid-typing that doesn't
    /// evaluate stays a search, never a calculator hit.
    static func evaluate(_ rawQuery: String) -> CommandKCalculation? {
        var text = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // A trailing "=" is the user asking for the answer — accept and strip.
        while text.hasSuffix("=") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty,
              text.contains(where: \.isNumber),
              text.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) })
        else { return nil }

        guard let tokens = tokenize(text), !tokens.isEmpty else { return nil }

        // A lone number ("15000", "(5)") is a search, not a sum — require an
        // actual operation before claiming the query. Two numbers with no
        // operator token can only be implicit multiplication ("(2)(3)");
        // spaced numbers ("5 3") still fail the parse below.
        let performsWork = tokens.contains {
            if case .op = $0 { return true }
            if case .percent = $0 { return true }
            return false
        }
        let numberCount = tokens.count { if case .number = $0 { return true } else { return false } }
        guard performsWork || numberCount > 1 else { return nil }

        var parser = Parser(tokens: tokens)
        guard let operand = parser.parseExpression(), parser.isAtEnd else { return nil }
        let value = operand.resolved
        guard value.isFinite, let resultDisplay = format(value) else { return nil }

        return CommandKCalculation(
            expressionDisplay: display(for: tokens),
            resultDisplay: resultDisplay,
            result: value
        )
    }

    // MARK: Tokens

    private enum Op: Character {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case power = "^"
    }

    private enum Token: Equatable {
        case number(Double)
        case op(Op)
        case percent
        case lparen
        case rparen
    }

    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789.,+-−–*×xX/÷%^() ")
        set.formUnion(.whitespaces)
        return set
    }()

    private static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t":
                i += 1
            case "+":
                tokens.append(.op(.add)); i += 1
            case "-", "−", "–":
                tokens.append(.op(.subtract)); i += 1
            case "*", "×", "x", "X":
                tokens.append(.op(.multiply)); i += 1
            case "/", "÷":
                tokens.append(.op(.divide)); i += 1
            case "^":
                tokens.append(.op(.power)); i += 1
            case "%":
                tokens.append(.percent); i += 1
            case "(":
                tokens.append(.lparen); i += 1
            case ")":
                tokens.append(.rparen); i += 1
            case _ where c.isNumber || c == ".":
                var raw = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "," {
                    raw.append(chars[i])
                    i += 1
                }
                guard let value = parseNumber(raw) else { return nil }
                tokens.append(.number(value))
            case ",":
                // A comma outside a number ("5,+3") isn't math.
                return nil
            default:
                return nil
            }
        }
        return tokens
    }

    /// Commas are US thousands separators and must sit in honest groups —
    /// "15,000" reads as fifteen thousand, but "1,5" is nobody's number and
    /// rejecting it beats silently computing the wrong thing.
    private static func parseNumber(_ raw: String) -> Double? {
        guard !raw.isEmpty else { return nil }
        var digits = raw
        if raw.contains(",") {
            let integerPart = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let groups = integerPart.split(separator: ",", omittingEmptySubsequences: false)
            guard groups.count > 1,
                  let first = groups.first, (1...3).contains(first.count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }),
                  !raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                      .dropFirst().joined().contains(",")
            else { return nil }
            digits = raw.replacingOccurrences(of: ",", with: "")
        }
        guard digits.filter({ $0 == "." }).count <= 1, digits != "." else { return nil }
        return Double(digits)
    }

    // MARK: Parser

    /// A value mid-evaluation. Percent stays symbolic until it meets its
    /// operator: "200 + 10%" is 220 (relative), "200 × 10%" is 20 (fraction).
    private struct Operand {
        var value: Double
        var isPercent = false
        var resolved: Double { isPercent ? value / 100 : value }
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }

        private var current: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func advance() { index += 1 }

        mutating func parseExpression() -> Operand? {
            guard var lhs = parseTerm() else { return nil }
            while case .op(let op) = current ?? .rparen, op == .add || op == .subtract {
                advance()
                guard let rhs = parseTerm() else { return nil }
                let base = lhs.resolved
                let delta = rhs.isPercent ? base * (rhs.value / 100) : rhs.value
                lhs = Operand(value: op == .add ? base + delta : base - delta)
            }
            return lhs
        }

        private mutating func parseTerm() -> Operand? {
            guard var lhs = parseFactor() else { return nil }
            loop: while let token = current {
                let op: Op
                switch token {
                case .op(.multiply): op = .multiply; advance()
                case .op(.divide): op = .divide; advance()
                case .lparen:
                    // Implicit multiplication: "5(3 + 2)", "(2)(3)" — but never
                    // number-after-number ("5 3" is a search, not 15).
                    op = .multiply
                default:
                    break loop
                }
                guard let rhs = parseFactor() else { return nil }
                let r = rhs.resolved
                if op == .divide {
                    guard r != 0 else { return nil }
                    lhs = Operand(value: lhs.resolved / r)
                } else {
                    lhs = Operand(value: lhs.resolved * r)
                }
            }
            return lhs
        }

        private mutating func parseFactor() -> Operand? {
            guard let base = parseUnary() else { return nil }
            if case .op(.power) = current ?? .rparen {
                advance()
                // Right-associative: 2^3^2 = 2^9.
                guard let exponent = parseFactor() else { return nil }
                return Operand(value: pow(base.resolved, exponent.resolved))
            }
            return base
        }

        private mutating func parseUnary() -> Operand? {
            var negate = false
            while case .op(let op) = current ?? .rparen, op == .add || op == .subtract {
                if op == .subtract { negate.toggle() }
                advance()
            }
            guard var operand = parsePrimary() else { return nil }
            if negate { operand.value.negate() }
            return operand
        }

        private mutating func parsePrimary() -> Operand? {
            switch current {
            case .number(let value):
                advance()
                return withPercentSuffix(Operand(value: value))
            case .lparen:
                advance()
                guard let inner = parseExpression(), case .rparen = current ?? .lparen else { return nil }
                advance()
                return withPercentSuffix(Operand(value: inner.resolved))
            default:
                return nil
            }
        }

        private mutating func withPercentSuffix(_ operand: Operand) -> Operand {
            var operand = operand
            while case .percent = current ?? .rparen {
                if operand.isPercent { operand.value /= 100 } else { operand.isPercent = true }
                advance()
            }
            return operand
        }
    }

    // MARK: Formatting

    static func format(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        let value = value == 0 ? 0 : value  // never "-0"
        let magnitude = abs(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if magnitude != 0, magnitude >= 1e15 || magnitude < 1e-9 {
            formatter.numberStyle = .scientific
            formatter.maximumSignificantDigits = 8
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.maximumFractionDigits = 8
        }
        return formatter.string(from: NSNumber(value: value))
    }

    /// Retypeset the token stream in calculator typography: grouped numbers,
    /// real × ÷ − glyphs, one space around binary operators, tight parens.
    private static func display(for tokens: [Token]) -> String {
        var out = ""
        var previous: Token?
        for token in tokens {
            switch token {
            case .number(let value):
                out += format(value) ?? String(value)
            case .op(let op):
                let isUnary: Bool = {
                    switch previous {
                    case nil, .op, .lparen: return true
                    default: return false
                    }
                }()
                if isUnary, op == .subtract {
                    out += "−"
                } else if isUnary, op == .add {
                    break  // unary plus adds nothing
                } else {
                    switch op {
                    case .add: out += " + "
                    case .subtract: out += " − "
                    case .multiply: out += " × "
                    case .divide: out += " ÷ "
                    case .power: out += " ^ "
                    }
                }
            case .percent:
                out += "%"
            case .lparen:
                switch previous {
                case .number, .rparen, .percent: out += " × ("
                default: out += "("
                }
            case .rparen:
                out += ")"
            }
            previous = token
        }
        return out
    }
}

// MARK: - Rail card (the Raycast split card: expression | answer)

/// The calculator's list presence — not a plain rail row but the honest
/// object: expression on the left page, answer on the right, one hairline
/// spine between. Selection/hover chrome matches CortexRailRow so it still
/// reads as family.
struct CommandKCalculatorRailCard: View {
    let expression: String
    let result: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            cell(expression, font: DS.title2.weight(.regular), color: DS.textSecondary)
            Rectangle()
                .fill(DS.commandChromeSeparator)
                .frame(width: 0.5)
                .padding(.vertical, DS.space10)
            cell(result, font: DS.title2, color: DS.text)
        }
        .frame(height: 64)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Copy result (⏎)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(expression) equals \(result)")
        .accessibilityHint("Press return to copy the result")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func cell(_ text: String, font: Font, color: Color) -> some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, DS.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(isSelected ? DS.accent.opacity(0.10) : (isHovered ? DS.surfaceHover.opacity(0.40) : Color.clear))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(
                isSelected ? DS.accent.opacity(0.45) : (isHovered ? DS.commandChromeSeparator : DS.commandChromeSeparator.opacity(0.6)),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}

// MARK: - Detail hero (the big numeral)

/// The detail-pane hero for a calculator selection: the expression as the
/// quiet line above, the answer as the one hero numeral. Typeset directly on
/// the body surface — no inner card (the ⌘K one-surface anatomy).
struct CommandKCalculatorPreview: View {
    let expression: String
    let result: String

    var body: some View {
        VStack(spacing: DS.space10) {
            Text(expression)
                .font(DS.callout)
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(result)
                .font(DS.display)
                .monospacedDigit()
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, DS.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(expression) equals \(result)")
    }
}
