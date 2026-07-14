// Tests/CosmoOSTests/CommandKCalculatorTests.swift
// The ⌘K inline calculator contract: strict detection (math and only math
// claims the query — a bare number, a date-ish word, or half-typed text must
// stay a search), Raycast-grade evaluation (x/× as multiply, thousands
// commas, percent, precedence, parens), and clean display typography.

import XCTest
@testable import CosmoOS

final class CommandKCalculatorTests: XCTestCase {

    private func result(_ query: String) -> String? {
        CommandKCalculator.evaluate(query)?.resultDisplay
    }

    private func expression(_ query: String) -> String? {
        CommandKCalculator.evaluate(query)?.expressionDisplay
    }

    // MARK: Detection — what claims the query

    func testBareNumberStaysASearch() {
        XCTAssertNil(result("15000"))
        XCTAssertNil(result("15,000"))
        XCTAssertNil(result("3.14"))
    }

    func testWordsStayASearch() {
        XCTAssertNil(result("task 3"))
        XCTAssertNil(result("meeting 2-3pm"))
        XCTAssertNil(result("q4 revenue"))
    }

    func testSpacedNumbersAreNotImplicitlyMultiplied() {
        XCTAssertNil(result("5 3"))
    }

    func testHalfTypedExpressionStaysASearch() {
        XCTAssertNil(result("5 +"))
        XCTAssertNil(result("5 x"))
        XCTAssertNil(result("(5 + 3"))
    }

    func testBadCommaGroupingIsRejectedNotMisread() {
        XCTAssertNil(result("1,5 + 2"))
        XCTAssertNil(result("15,00 * 2"))
    }

    // MARK: Arithmetic

    func testTheHeadlineCase() {
        XCTAssertEqual(result("5 x 15,000"), "75,000")
    }

    func testMultiplyGlyphVariants() {
        XCTAssertEqual(result("6x9"), "54")
        XCTAssertEqual(result("6 X 9"), "54")
        XCTAssertEqual(result("6 × 9"), "54")
        XCTAssertEqual(result("6 * 9"), "54")
    }

    func testBasicOperators() {
        XCTAssertEqual(result("2 + 3"), "5")
        XCTAssertEqual(result("10 - 4"), "6")
        XCTAssertEqual(result("15 / 4"), "3.75")
        XCTAssertEqual(result("2 ^ 10"), "1,024")
    }

    func testPrecedenceAndParens() {
        XCTAssertEqual(result("2 + 3 * 4"), "14")
        XCTAssertEqual(result("(2 + 3) * 4"), "20")
        XCTAssertEqual(result("2 ^ 3 ^ 2"), "512") // right-associative
    }

    func testImplicitMultiplicationWithParens() {
        XCTAssertEqual(result("5(3 + 2)"), "25")
        XCTAssertEqual(result("(2)(3)"), "6")
    }

    func testUnaryMinus() {
        XCTAssertEqual(result("-5 + 3"), "-2")
        XCTAssertEqual(result("5 * -3"), "-15")
    }

    func testTrailingEqualsIsAccepted() {
        XCTAssertEqual(result("5 x 15,000 ="), "75,000")
    }

    func testUnicodeMinusAndDivide() {
        XCTAssertEqual(result("10 − 4"), "6")
        XCTAssertEqual(result("10 ÷ 4"), "2.5")
    }

    // MARK: Percent

    func testBarePercentIsAFraction() {
        XCTAssertEqual(result("50% * 200"), "100")
        XCTAssertEqual(result("200 * 10%"), "20")
    }

    func testAdditivePercentIsRelative() {
        XCTAssertEqual(result("200 + 10%"), "220")
        XCTAssertEqual(result("200 - 10%"), "180")
    }

    // MARK: Failure honesty

    func testDivisionByZeroProducesNothing() {
        XCTAssertNil(result("5 / 0"))
        XCTAssertNil(result("5 / (3 - 3)"))
    }

    func testOverflowProducesNothing() {
        XCTAssertNil(result("10 ^ 10 ^ 10"))
    }

    // MARK: Display typography

    func testExpressionIsRetypesetWithRealGlyphs() {
        XCTAssertEqual(expression("5 x 15000"), "5 × 15,000")
        XCTAssertEqual(expression("10/4"), "10 ÷ 4")
        XCTAssertEqual(expression("-5+3"), "−5 + 3")
        XCTAssertEqual(expression("5(3+2)"), "5 × (3 + 2)")
    }

    func testResultsGroupThousands() {
        XCTAssertEqual(result("1000 * 1000"), "1,000,000")
    }

    func testFractionsAreTrimmedNotPadded() {
        XCTAssertEqual(result("1 / 3"), "0.33333333")
        XCTAssertEqual(result("4 / 2"), "2")
    }
}
