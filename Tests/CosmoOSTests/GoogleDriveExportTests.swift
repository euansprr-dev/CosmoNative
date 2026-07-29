import XCTest
@testable import CosmoOS

/// The Drive connection's load-bearing contracts: a PKCE exchange that matches
/// the RFC, a redirect Google will actually accept, a scope check that can't be
/// fooled by a prefix, and a Markdown→HTML path that can't inject markup.
final class GoogleDriveExportTests: XCTestCase {

    // MARK: - PKCE

    /// RFC 7636 Appendix B's worked example. If this drifts, the token
    /// exchange fails at Google with an opaque `invalid_grant`.
    func testPKCEChallengeMatchesRFCVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEChallenge(verifier: verifier)
        XCTAssertEqual(challenge.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(challenge.method, "S256")
    }

    func testGeneratedVerifierIsURLSafeAndWithinRFCLengthBounds() {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<50 {
            let challenge = PKCEChallenge()
            XCTAssertGreaterThanOrEqual(challenge.verifier.count, 43)
            XCTAssertLessThanOrEqual(challenge.verifier.count, 128)
            XCTAssertTrue(
                challenge.verifier.unicodeScalars.allSatisfy(allowed.contains),
                "verifier leaked a character outside the unreserved set"
            )
        }
    }

    func testGeneratedVerifiersAreUnique() {
        let verifiers = Set((0..<200).map { _ in PKCEChallenge().verifier })
        XCTAssertEqual(verifiers.count, 200, "verifier generation is not random")
    }

    // MARK: - Client ID / redirect

    func testRedirectSchemeIsReversedClientID() {
        let clientID = "123456789-abcdef.apps.googleusercontent.com"
        XCTAssertEqual(
            GoogleDriveConfiguration.redirectScheme(for: clientID),
            "com.googleusercontent.apps.123456789-abcdef"
        )
        // Google's convention is a single slash after the scheme.
        XCTAssertEqual(
            GoogleDriveConfiguration.redirectURI(for: clientID),
            "com.googleusercontent.apps.123456789-abcdef:/oauth2redirect"
        )
    }

    func testMalformedClientIDsAreRejected() {
        let rejects = [
            "",
            "not-a-client-id",
            "123456789-abcdef.apps.google.com",
            ".apps.googleusercontent.com",
            "AIzaSyExampleApiKeyNotAClientId"
        ]
        for candidate in rejects {
            XCTAssertFalse(
                GoogleDriveConfiguration.validate(clientID: candidate),
                "\(candidate) should not validate"
            )
            XCTAssertNil(GoogleDriveConfiguration.redirectScheme(for: candidate))
        }
        XCTAssertTrue(
            GoogleDriveConfiguration.validate(clientID: "1-a.apps.googleusercontent.com")
        )
    }

    // MARK: - Token set

    func testExpiryHonoursRefreshMargin() {
        func token(expiringIn seconds: TimeInterval) -> GoogleTokenSet {
            GoogleTokenSet(
                accessToken: "at",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(seconds),
                grantedScope: GoogleDriveConfiguration.requiredScope,
                accountEmail: nil
            )
        }
        XCTAssertFalse(token(expiringIn: 3600).isExpired)
        // Inside the margin counts as expired — a token that dies mid-upload is
        // the failure this cushion exists to prevent.
        XCTAssertTrue(token(expiringIn: GoogleDriveConfiguration.refreshMargin - 10).isExpired)
        XCTAssertTrue(token(expiringIn: -1).isExpired)
    }

    /// The scope check splits on spaces rather than substring-matching, so a
    /// scope that merely *starts with* drive.file can't pass for it.
    func testDriveScopeDetectionRequiresExactScope() {
        func token(scope: String) -> GoogleTokenSet {
            GoogleTokenSet(
                accessToken: "at", refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(3600),
                grantedScope: scope, accountEmail: nil
            )
        }
        XCTAssertTrue(token(scope: "openid email \(GoogleDriveConfiguration.requiredScope)").hasDriveAccess)
        XCTAssertFalse(token(scope: "openid email").hasDriveAccess)
        XCTAssertFalse(token(scope: "\(GoogleDriveConfiguration.requiredScope).readonly").hasDriveAccess)
        XCTAssertFalse(token(scope: "").hasDriveAccess)
    }

    func testReconnectRequiredInvalidatesConnectionButTransientErrorsDoNot() {
        XCTAssertTrue(GoogleDriveError.reconnectRequired("revoked").invalidatesConnection)
        XCTAssertTrue(GoogleDriveError.driveScopeDeclined.invalidatesConnection)
        XCTAssertFalse(GoogleDriveError.driveStorageFull.invalidatesConnection)
        XCTAssertFalse(GoogleDriveError.api(status: 500, reason: nil, message: "boom").invalidatesConnection)
        XCTAssertFalse(GoogleDriveError.authorizationCancelled.invalidatesConnection)
    }

    // MARK: - Form encoding & id_token

    func testFormEncodingEscapesReservedCharacters() {
        let encoded = GoogleOAuthService.formEncode(["code": "a+b/c=d&e"])
        XCTAssertEqual(encoded, "code=a%2Bb%2Fc%3Dd%26e")
    }

    func testEmailIsReadFromIDTokenPayload() {
        let payload = #"{"email":"euan@example.com","sub":"123"}"#
        let encoded = Data(payload.utf8).base64URLEncodedString()
        let idToken = "header.\(encoded).signature"
        XCTAssertEqual(GoogleOAuthService.email(fromIDToken: idToken), "euan@example.com")
        XCTAssertNil(GoogleOAuthService.email(fromIDToken: "garbage"))
    }

    // MARK: - File naming

    func testFileNameCarriesExtensionExceptForGoogleDocs() {
        let date = Date(timeIntervalSince1970: 1_753_660_800)  // 2025-07-28 UTC
        let doc = DriveExportBuilder.fileName(
            title: "Launch Thread", platform: .xThread, format: .googleDoc, date: date
        )
        XCTAssertFalse(doc.hasSuffix(".md"))
        XCTAssertFalse(doc.hasSuffix(".txt"))
        XCTAssertTrue(doc.contains("Launch Thread"))
        XCTAssertTrue(doc.contains("X — Thread"))

        XCTAssertTrue(
            DriveExportBuilder.fileName(title: "Launch", platform: .xThread, format: .markdown, date: date)
                .hasSuffix(".md")
        )
        XCTAssertTrue(
            DriveExportBuilder.fileName(title: "Launch", platform: .xThread, format: .plainText, date: date)
                .hasSuffix(".txt")
        )
    }

    func testSanitizeStripsPathSeparatorsAndCollapsesWhitespace() {
        XCTAssertEqual(DriveExportBuilder.sanitize("a/b\\c:d"), "a-b-c-d")
        XCTAssertEqual(DriveExportBuilder.sanitize("  spaced   out \n title "), "spaced out title")
        XCTAssertEqual(DriveExportBuilder.sanitize("line\nbreak"), "line break")
        XCTAssertLessThanOrEqual(DriveExportBuilder.sanitize(String(repeating: "x", count: 400)).count, 120)
    }

    func testEmptyTitleFallsBackRatherThanProducingANamelessFile() {
        let name = DriveExportBuilder.fileName(title: "   ", platform: .linkedIn, format: .markdown)
        XCTAssertTrue(name.hasPrefix("Untitled"))
    }

    // MARK: - Markdown → HTML

    func testHeadingsListsAndInlineFormattingConvert() {
        let html = DriveExportBuilder.markdownToHTML("""
        # Title
        Some **bold** and *italic* and `code`.

        - one
        - two

        1. first
        2. second

        > a quote
        """)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<b>bold</b>"))
        XCTAssertTrue(html.contains("<i>italic</i>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>one</li>"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li>first</li>"))
        XCTAssertTrue(html.contains("<blockquote>a quote</blockquote>"))
    }

    /// A draft is user text, not a template. Markup in it must land as visible
    /// characters in the Doc, never as live HTML.
    func testDraftMarkupIsEscapedNotInjected() {
        let html = DriveExportBuilder.markdownToHTML("Use <script>alert(1)</script> & <b>tags</b>")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&amp;"))
    }

    func testLinksConvertAndMidWordAsterisksAreLeftAlone() {
        XCTAssertTrue(
            DriveExportBuilder.inline("see [docs](https://example.com)")
                .contains(#"<a href="https://example.com">docs</a>"#)
        )
        // `2*3*4` is arithmetic, not emphasis.
        XCTAssertFalse(DriveExportBuilder.inline("2*3*4").contains("<i>"))
    }

    func testPlainProseSurvivesTheRendererUnharmed() {
        let html = DriveExportBuilder.markdownToHTML("Just a sentence.\nAnd another.")
        XCTAssertTrue(html.contains("Just a sentence."))
        XCTAssertTrue(html.contains("And another."))
        XCTAssertTrue(html.contains("<br>"), "single newlines should stay visible as breaks")
    }

    // MARK: - Upload payload

    func testDocumentCarriesTheFormatsMimeTypePair() {
        let sections = ContentExportFormatter.format("Hello there.", for: .linkedIn)

        let doc = DriveExportBuilder.document(
            title: "Note", platform: .linkedIn, sections: sections, format: .googleDoc
        )
        XCTAssertEqual(doc.targetMimeType, GoogleDriveClient.googleDocMimeType)
        XCTAssertEqual(doc.sourceMimeType, "text/html")
        XCTAssertTrue(String(decoding: doc.data, as: UTF8.self).contains("<h1>Note</h1>"))

        let markdown = DriveExportBuilder.document(
            title: "Note", platform: .linkedIn, sections: sections, format: .markdown
        )
        XCTAssertEqual(markdown.targetMimeType, "text/markdown")
        XCTAssertTrue(String(decoding: markdown.data, as: UTF8.self).contains("# Note"))

        let text = DriveExportBuilder.document(
            title: "Note", platform: .linkedIn, sections: sections, format: .plainText
        )
        XCTAssertEqual(text.targetMimeType, "text/plain")
        XCTAssertEqual(String(decoding: text.data, as: UTF8.self), "Hello there.")
    }

    func testMultiSectionExportKeepsEverySection() {
        let draft = (1...8).map { "Paragraph \($0) " + String(repeating: "word ", count: 40) }
            .joined(separator: "\n\n")
        let sections = ContentExportFormatter.format(draft, for: .xThread)
        XCTAssertGreaterThan(sections.count, 1)

        let html = String(
            decoding: DriveExportBuilder.document(
                title: "Thread", platform: .xThread, sections: sections, format: .googleDoc
            ).data,
            as: UTF8.self
        )
        for section in sections {
            XCTAssertTrue(html.contains("<h2>\(section.label)</h2>"), "section \(section.label) went missing")
        }
    }

    // MARK: - Multipart body

    func testMultipartBodyHasMetadataThenMediaAndClosingBoundary() throws {
        let upload = DriveUpload(
            name: "note.md",
            targetMimeType: "text/markdown",
            sourceMimeType: "text/markdown",
            data: Data("# hi".utf8)
        )
        let metadata = GoogleDriveClient.uploadMetadata(for: upload, folderID: "FOLDER", isUpdate: false)
        let body = try GoogleDriveClient.multipartBody(
            metadata: metadata, upload: upload, boundary: "BOUND"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("--BOUND\r\nContent-Type: application/json"))
        XCTAssertTrue(text.contains("Content-Type: text/markdown\r\n\r\n# hi"))
        XCTAssertTrue(text.hasSuffix("\r\n--BOUND--"))
    }

    /// Drive rejects `parents` in an update's metadata body — reparenting is a
    /// query parameter — and the existing file already settles its mime type.
    func testUpdateMetadataDropsParentsAndMimeType() {
        let upload = DriveUpload(
            name: "note.md", targetMimeType: "text/markdown",
            sourceMimeType: "text/markdown", data: Data()
        )
        let create = GoogleDriveClient.uploadMetadata(for: upload, folderID: "FOLDER", isUpdate: false)
        XCTAssertEqual(create["parents"] as? [String], ["FOLDER"])
        XCTAssertEqual(create["mimeType"] as? String, "text/markdown")

        let update = GoogleDriveClient.uploadMetadata(for: upload, folderID: "FOLDER", isUpdate: true)
        XCTAssertNil(update["parents"])
        XCTAssertNil(update["mimeType"])
        XCTAssertEqual(update["name"] as? String, "note.md")
    }

    // MARK: - Error mapping

    func testStorageQuotaMapsToItsOwnError() {
        let payload = """
        {"error":{"code":403,"message":"quota","errors":[{"reason":"storageQuotaExceeded"}]}}
        """
        XCTAssertEqual(
            GoogleDriveClient.mapError(status: 403, data: Data(payload.utf8)),
            .driveStorageFull
        )
    }

    func testUnknownErrorKeepsStatusAndReason() {
        let payload = """
        {"error":{"code":404,"message":"File not found","errors":[{"reason":"notFound"}]}}
        """
        guard case .api(let status, let reason, let message) =
                GoogleDriveClient.mapError(status: 404, data: Data(payload.utf8)) else {
            return XCTFail("expected .api")
        }
        XCTAssertEqual(status, 404)
        XCTAssertEqual(reason, "notFound")
        XCTAssertEqual(message, "File not found")
    }

    func testNonJSONErrorBodyStillProducesAnError() {
        guard case .api(let status, _, _) =
                GoogleDriveClient.mapError(status: 502, data: Data("<html>bad gateway</html>".utf8)) else {
            return XCTFail("expected .api")
        }
        XCTAssertEqual(status, 502)
    }

    // MARK: - Parsing

    func testFileParsingFallsBackToAnOpenableLinkWhenDriveOmitsOne() throws {
        let file = try XCTUnwrap(GoogleDriveClient.parseFile([
            "id": "FILE123",
            "name": "Draft",
            "mimeType": GoogleDriveClient.googleDocMimeType
        ]))
        XCTAssertNil(file.webViewLink)
        XCTAssertEqual(file.openURL?.absoluteString, "https://drive.google.com/open?id=FILE123")
        XCTAssertFalse(file.isFolder)

        let folder = try XCTUnwrap(GoogleDriveClient.parseFile([
            "id": "F1", "name": "Cosmo Exports", "mimeType": GoogleDriveClient.folderMimeType
        ]))
        XCTAssertTrue(folder.isFolder)
        XCTAssertNil(GoogleDriveClient.parseFile(["name": "no id"]))
    }

    // MARK: - Ledger keys

    /// Each platform and format is its own document in Drive — one draft
    /// exported three ways must not overwrite itself twice.
    func testLedgerKeysSeparatePlatformAndFormat() {
        let base = DriveExportLedger.key(atomUUID: "A", platform: .xThread, format: .googleDoc)
        XCTAssertNotEqual(base, DriveExportLedger.key(atomUUID: "A", platform: .linkedIn, format: .googleDoc))
        XCTAssertNotEqual(base, DriveExportLedger.key(atomUUID: "A", platform: .xThread, format: .markdown))
        XCTAssertNotEqual(base, DriveExportLedger.key(atomUUID: "B", platform: .xThread, format: .googleDoc))
    }
}
