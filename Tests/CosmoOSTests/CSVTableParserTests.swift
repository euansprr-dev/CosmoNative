import XCTest
@testable import CosmoOS

final class CSVTableParserTests: XCTestCase {

    func testSimpleRows() {
        XCTAssertEqual(
            CSVTableParser.parse("a,b,c\n1,2,3"),
            [["a", "b", "c"], ["1", "2", "3"]]
        )
    }

    func testQuotedFieldWithDelimiter() {
        XCTAssertEqual(
            CSVTableParser.parse(#"name,note"# + "\n" + #""Doe, Jane",fine"#),
            [["name", "note"], ["Doe, Jane", "fine"]]
        )
    }

    func testEscapedQuotesInsideQuotedField() {
        XCTAssertEqual(
            CSVTableParser.parse(#""She said ""hi""",x"#),
            [[#"She said "hi""#, "x"]]
        )
    }

    func testNewlineInsideQuotedField() {
        XCTAssertEqual(
            CSVTableParser.parse("\"line one\nline two\",b"),
            [["line one\nline two", "b"]]
        )
    }

    func testCRLFAndBareCRRecordSeparators() {
        XCTAssertEqual(
            CSVTableParser.parse("a,b\r\nc,d\re,f"),
            [["a", "b"], ["c", "d"], ["e", "f"]]
        )
    }

    func testRaggedRowsArePreserved() {
        XCTAssertEqual(
            CSVTableParser.parse("a,b,c\nd\ne,f"),
            [["a", "b", "c"], ["d"], ["e", "f"]]
        )
    }

    func testTrailingNewlineDoesNotAddEmptyRow() {
        XCTAssertEqual(CSVTableParser.parse("a,b\n"), [["a", "b"]])
    }

    func testEmptyFieldsSurvive() {
        XCTAssertEqual(
            CSVTableParser.parse("a,,c\n,,"),
            [["a", "", "c"], ["", "", ""]]
        )
    }

    func testTabDelimiter() {
        XCTAssertEqual(
            CSVTableParser.parse("a\tb\t1,5\nc\td\te", delimiter: "\t"),
            [["a", "b", "1,5"], ["c", "d", "e"]]
        )
    }

    func testUnterminatedQuoteParsesLiterally() {
        // Malformed input must still yield content, never crash or drop data.
        XCTAssertEqual(CSVTableParser.parse("\"abc,def"), [["abc,def"]])
    }

    func testEmptyInput() {
        XCTAssertEqual(CSVTableParser.parse(""), [])
    }
}
