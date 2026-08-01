import XCTest
@testable import CosmoOS

/// The newsletter-shaped MIME reader, pinned against realistic fixtures:
/// multipart/alternative (plain listed first, HTML wins), quoted-printable
/// and base64 transfer encodings, RFC 2047 encoded-word subjects, cid: inline
/// images rewritten to data: URIs, plain-text-only wrapping, and the .emlx
/// byte-count wrapper.
final class SwipeEmailCaptureTests: XCTestCase {

    // MARK: - Fixtures

    private let multipartAlternative = """
    From: Lenny Rachitsky <lenny@substack.com>\r
    Subject: How to price your product\r
    MIME-Version: 1.0\r
    Content-Type: multipart/alternative; boundary="BOUND1"\r
    \r
    --BOUND1\r
    Content-Type: text/plain; charset=utf-8\r
    \r
    The plain version.\r
    --BOUND1\r
    Content-Type: text/html; charset=utf-8\r
    Content-Transfer-Encoding: quoted-printable\r
    \r
    <html><body><h1>How to price</h1><p>Pricing is positioning=2C not math.</p></body></html>=\r
    \r
    --BOUND1--\r
    """

    func testMultipartAlternativePrefersHTMLAndReadsHeaders() {
        let payload = SwipeEmailCapture.parse(data: Data(multipartAlternative.utf8))
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.subject, "How to price your product")
        XCTAssertEqual(payload?.senderName, "Lenny Rachitsky")
        XCTAssertEqual(payload?.senderAddress, "lenny@substack.com")
        XCTAssertTrue(payload?.html.contains("<h1>How to price</h1>") == true)
        // Quoted-printable decoded: =2C is a comma, the soft break vanished.
        XCTAssertTrue(payload?.html.contains("positioning, not math") == true)
        XCTAssertFalse(payload?.html.contains("The plain version") == true)
    }

    func testBase64HTMLPartDecodes() {
        let html = "<html><body><p>Base64 body</p></body></html>"
        let encoded = Data(html.utf8).base64EncodedString()
        let message = """
        From: news@beehiiv.com\r
        Subject: Issue 42\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: base64\r
        \r
        \(encoded)\r
        """
        let payload = SwipeEmailCapture.parse(data: Data(message.utf8))
        XCTAssertTrue(payload?.html.contains("Base64 body") == true)
        // Bare address: no display name to report.
        XCTAssertNil(payload?.senderName)
        XCTAssertEqual(payload?.senderAddress, "news@beehiiv.com")
    }

    func testEncodedWordSubjectDecodes() {
        let message = """
        From: a@b.com\r
        Subject: =?utf-8?B?8J+agCBMYXVuY2ggd2Vlaw==?=\r
        Content-Type: text/html\r
        \r
        <html><body>x</body></html>\r
        """
        let payload = SwipeEmailCapture.parse(data: Data(message.utf8))
        XCTAssertEqual(payload?.subject, "🚀 Launch week")
    }

    func testInlineCIDImagesBecomeDataURIs() {
        let pixel = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let message = """
        Subject: With images\r
        Content-Type: multipart/related; boundary="REL"\r
        \r
        --REL\r
        Content-Type: text/html\r
        \r
        <html><body><img src="cid:hero@mail"></body></html>\r
        --REL\r
        Content-Type: image/png\r
        Content-ID: <hero@mail>\r
        Content-Transfer-Encoding: base64\r
        \r
        \(pixel)\r
        --REL--\r
        """
        let payload = SwipeEmailCapture.parse(data: Data(message.utf8))
        XCTAssertTrue(payload?.html.contains("data:image/png;base64,\(pixel)") == true)
        XCTAssertFalse(payload?.html.contains("cid:hero@mail") == true)
    }

    func testPlainTextOnlyWrapsReadable() {
        let message = """
        Subject: Raw note\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        Line one.\r
        \r
        Line <two> & three.\r
        """
        let payload = SwipeEmailCapture.parse(data: Data(message.utf8))
        XCTAssertTrue(payload?.html.contains("pre-wrap") == true)
        XCTAssertTrue(payload?.html.contains("Line &lt;two&gt; &amp; three.") == true)
    }

    func testEmlxWrapperUnwraps() {
        let inner = "Subject: Wrapped\r\nContent-Type: text/html\r\n\r\n<html><body>emlx body</body></html>"
        let innerData = Data(inner.utf8)
        var wrapped = Data("\(innerData.count)\n".utf8)
        wrapped.append(innerData)
        wrapped.append(Data("<?xml plist trailer?>".utf8))
        let payload = SwipeEmailCapture.parse(data: wrapped)
        XCTAssertEqual(payload?.subject, "Wrapped")
        XCTAssertTrue(payload?.html.contains("emlx body") == true)
    }

    func testEmptyBodyAnswersNilNotAnEmptySwipe() {
        let headersOnly = "Subject: Nothing\r\nContent-Type: text/plain\r\n\r\n   \r\n"
        XCTAssertNil(SwipeEmailCapture.parse(data: Data(headersOnly.utf8)))
    }
}
