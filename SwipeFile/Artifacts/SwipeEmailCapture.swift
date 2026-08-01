// CosmoOS/SwipeFile/Artifacts/SwipeEmailCapture.swift
// A dragged-in email becomes a Newsletter swipe.
//
// Newsletters live in inboxes, not at URLs — dragging a message out of
// Mail.app produces an .eml file, and this reader turns it into renderable
// HTML for the page pipeline. It is deliberately NOT a general MIME library:
// it reads newsletter-shaped mail (one HTML part, maybe inline images, maybe
// a plain-text alternative) with Foundation only. Anything it can't read
// fails loudly at the capture surface, never silently.
//
// The output contract: `html` is self-renderable — inline `cid:` images are
// rewritten to `data:` URIs (a holey render would slice into empty wells),
// and a plain-text-only message is wrapped in a readable <pre>.

import Foundation

// MARK: - Payload

/// What an email file parses into — everything the intake router needs to
/// mint a correctly-titled Newsletter page swipe.
struct SwipeEmailPayload: Sendable {
    var subject: String?
    var senderName: String?
    var senderAddress: String?
    var html: String
}

// MARK: - Reader

enum SwipeEmailCapture {

    // MARK: Entry

    static func parse(data: Data) -> SwipeEmailPayload? {
        guard let raw = decodeToString(unwrapEmlx(data)) else { return nil }
        let message = MIMEPart(rawMessage: raw)

        let subject = message.header("Subject").map(decodeEncodedWords)
        let (senderName, senderAddress) = parseFrom(message.header("From").map(decodeEncodedWords))

        // Walk the tree: the newest HTML part wins; images ride along for
        // cid: rewriting; plain text is the fallback body.
        var htmlBody: String?
        var plainBody: String?
        var inlineImages: [(contentID: String, mimeType: String, base64: String)] = []
        collect(part: message, htmlBody: &htmlBody, plainBody: &plainBody, images: &inlineImages)

        if var html = htmlBody {
            for image in inlineImages {
                html = html
                    .replacingOccurrences(of: "cid:\(image.contentID)", with: "data:\(image.mimeType);base64,\(image.base64)")
            }
            return SwipeEmailPayload(
                subject: subject, senderName: senderName,
                senderAddress: senderAddress, html: html
            )
        }
        if let plain = plainBody?.trimmed, !plain.isEmpty {
            return SwipeEmailPayload(
                subject: subject, senderName: senderName,
                senderAddress: senderAddress, html: wrapPlainText(plain)
            )
        }
        return nil
    }

    // MARK: emlx

    /// Apple's .emlx = a byte-count line, the raw RFC 822 message, then a
    /// plist of flags. Strip the wrapper; a plain .eml passes through.
    static func unwrapEmlx(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: 0x0A) else { return data }
        let firstLine = data[data.startIndex..<newline]
        guard let text = String(data: firstLine, encoding: .utf8)?.trimmed,
              !text.isEmpty, text.allSatisfy(\.isNumber), let count = Int(text)
        else { return data }
        let start = data.index(after: newline)
        let end = data.index(start, offsetBy: count, limitedBy: data.endIndex) ?? data.endIndex
        return data.subdata(in: start..<end)
    }

    private static func decodeToString(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: Part walk

    private static func collect(
        part: MIMEPart,
        htmlBody: inout String?,
        plainBody: inout String?,
        images: inout [(contentID: String, mimeType: String, base64: String)]
    ) {
        if part.isMultipart {
            for child in part.children {
                collect(part: child, htmlBody: &htmlBody, plainBody: &plainBody, images: &images)
            }
            return
        }
        let type = part.contentType.lowercased()
        if type.hasPrefix("text/html") {
            // Later parts win: multipart/alternative lists plain FIRST and
            // the richest alternative LAST by RFC 2046.
            htmlBody = part.decodedText() ?? htmlBody
        } else if type.hasPrefix("text/plain") {
            plainBody = part.decodedText() ?? plainBody
        } else if type.hasPrefix("image/"), let contentID = part.contentID {
            let base64 = part.decodedData().base64EncodedString()
            let mime = type.split(separator: ";").first.map(String.init) ?? "image/png"
            images.append((contentID, mime, base64))
        }
    }

    private static func wrapPlainText(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <html><body style="margin:0;background:#ffffff;"><pre style="white-space:pre-wrap;\
        font-family:-apple-system,Helvetica,sans-serif;font-size:16px;line-height:1.5;\
        max-width:70ch;margin:2rem auto;padding:0 1rem;">\(escaped)</pre></body></html>
        """
    }

    // MARK: From header

    /// "Lenny Rachitsky <lenny@substack.com>" → (name, address); a bare
    /// address answers as the address alone.
    static func parseFrom(_ raw: String?) -> (name: String?, address: String?) {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return (nil, nil) }
        if let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close {
            let name = String(raw[raw.startIndex..<open]).trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let address = String(raw[raw.index(after: open)..<close]).trimmed
            return (name.isEmpty ? nil : name, address.isEmpty ? nil : address)
        }
        return (nil, raw.contains("@") ? raw : nil)
    }

    // MARK: RFC 2047 encoded words

    /// "=?utf-8?B?8J+Ppg==?=" — subjects and sender names in real newsletters
    /// are almost always encoded-words. B and Q forms, charset utf-8/latin-1.
    static func decodeEncodedWords(_ input: String) -> String {
        var result = input
        let pattern = /=\?([^?]+)\?([bBqQ])\?([^?]*)\?=/
        while let match = result.firstMatch(of: pattern) {
            let charset = String(match.1).lowercased()
            let encoding: String.Encoding = charset.contains("8859") ? .isoLatin1 : .utf8
            let mode = String(match.2).lowercased()
            let payload = String(match.3)

            let decoded: String?
            if mode == "b" {
                decoded = Data(base64Encoded: payload).flatMap { String(data: $0, encoding: encoding) }
            } else {
                // Q-encoding: underscore is space, =XX is a byte.
                let qp = payload.replacingOccurrences(of: "_", with: " ")
                decoded = decodeQuotedPrintable(qp, encoding: encoding)
            }
            result.replaceSubrange(match.range, with: decoded ?? "")
        }
        // Whitespace BETWEEN two encoded words is transport artifact.
        return result.trimmed
    }

    // MARK: Quoted-printable

    static func decodeQuotedPrintable(_ input: String, encoding: String.Encoding = .utf8) -> String? {
        var bytes: [UInt8] = []
        var index = input.startIndex
        while index < input.endIndex {
            let char = input[index]
            if char == "=" {
                let next = input.index(after: index)
                // Soft line break: "=\r\n" or "=\n" disappears.
                if next < input.endIndex, input[next] == "\r" {
                    index = input.index(next, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                    continue
                }
                if next < input.endIndex, input[next] == "\n" {
                    index = input.index(after: next)
                    continue
                }
                if let hexEnd = input.index(next, offsetBy: 2, limitedBy: input.endIndex),
                   let byte = UInt8(input[next..<hexEnd], radix: 16) {
                    bytes.append(byte)
                    index = hexEnd
                    continue
                }
            }
            bytes.append(contentsOf: Array(String(char).utf8))
            index = input.index(after: index)
        }
        return String(data: Data(bytes), encoding: encoding)
            ?? String(data: Data(bytes), encoding: .isoLatin1)
    }
}

// MARK: - One MIME part

/// A message or one part of a multipart — headers plus body, with just
/// enough structure to walk a newsletter's tree.
struct MIMEPart {
    var headers: [String: String]
    var body: String

    init(rawMessage: String) {
        let normalized = rawMessage.replacingOccurrences(of: "\r\n", with: "\n")
        let (headerBlock, bodyBlock) = Self.splitHeadersAndBody(normalized)
        headers = Self.parseHeaders(headerBlock)
        body = bodyBlock
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var contentType: String {
        header("Content-Type") ?? "text/plain"
    }

    var isMultipart: Bool {
        contentType.lowercased().hasPrefix("multipart/")
    }

    /// "<part1.abc@mail>" → "part1.abc@mail".
    var contentID: String? {
        header("Content-ID")?.trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }

    var children: [MIMEPart] {
        guard isMultipart, let boundary = parameter("boundary") else { return [] }
        let marker = "--" + boundary
        var parts: [MIMEPart] = []
        // Segments between boundary markers; the preamble (index 0) and the
        // epilogue (after "--boundary--") are transport noise.
        let segments = body.components(separatedBy: marker)
        for segment in segments.dropFirst() {
            if segment.hasPrefix("--") { break }
            let trimmed = segment.drop(while: { $0 == "\n" })
            if trimmed.isEmpty { continue }
            parts.append(MIMEPart(rawMessage: String(trimmed)))
        }
        return parts
    }

    func parameter(_ name: String) -> String? {
        // boundary="abc" or boundary=abc, case-insensitive, quotes optional.
        let lower = contentType
        guard let range = lower.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        var value = String(lower[range.upperBound...])
        if let end = value.firstIndex(where: { $0 == ";" || $0 == "\n" }) {
            value = String(value[value.startIndex..<end])
        }
        return value.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    // MARK: Decoding

    func decodedText() -> String? {
        let data = decodedData()
        let charset = parameter("charset")?.lowercased() ?? "utf-8"
        let encoding: String.Encoding = charset.contains("8859") || charset.contains("latin") ? .isoLatin1 : .utf8
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .isoLatin1)
    }

    func decodedData() -> Data {
        let transfer = header("Content-Transfer-Encoding")?.trimmed.lowercased() ?? ""
        switch transfer {
        case "base64":
            let compact = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: compact) ?? Data()
        case "quoted-printable":
            let decoded = SwipeEmailCapture.decodeQuotedPrintable(body) ?? body
            return Data(decoded.utf8)
        default:
            return Data(body.utf8)
        }
    }

    // MARK: Header parsing

    private static func splitHeadersAndBody(_ message: String) -> (String, String) {
        if let range = message.range(of: "\n\n") {
            return (String(message[message.startIndex..<range.lowerBound]),
                    String(message[range.upperBound...]))
        }
        return (message, "")
    }

    private static func parseHeaders(_ block: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentName: String?
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Folded continuation of the previous header.
                if let name = currentName {
                    headers[name, default: ""] += " " + line.trimmed
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmed.lowercased()
            let value = String(line[line.index(after: colon)...]).trimmed
            headers[name] = value
            currentName = name
        }
        return headers
    }
}
